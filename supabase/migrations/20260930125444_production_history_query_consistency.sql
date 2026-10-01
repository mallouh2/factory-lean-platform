-- Separate request retry identity from the parent Production Request. Untyped historical output is not aggregated.
create or replace function public.production_history(factory uuid,filters jsonb default '{}',
 sort_key text default 'date',sort_direction text default 'desc',page integer default 1)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; zone text; begin
 perform private.require_permission(factory,'orders','view');
 if sort_key not in ('date','good','scrap','unit','technician','shift') or sort_direction not in ('asc','desc')
 or page is null or page<1 or page>1000000 or jsonb_typeof(filters)<>'object' then raise exception 'history_invalid';end if;
 select timezone into zone from public.factories where id=factory;
 with base as materialized (
 select e.*,o.request_id as production_request_id,o.product_id,r.code as request_code,o.code as item_code,
 p.name as product_name,p.name_ar as product_name_ar,
 coalesce(l.name,c.name) as unit_name,coalesce(l.name_ar,c.name_ar) as unit_name_ar,
 case when e.line_id is not null then 'line:'||e.line_id else 'machine:'||e.work_center_id end as unit_key,
 tech.display_name as technician_name,actor.display_name as submitter_name,
 sh.name as shift_name,sh.name_ar as shift_name_ar,
 to_jsonb(o) as history_item,
 exists(select 1 from public.production_entry_corrections x where x.factory_id=factory and x.entry_id=e.id) as corrected
 from public.production_entries e join public.production_orders o on o.id=e.order_id and o.factory_id=e.factory_id
 left join public.production_requests r on r.id=o.request_id and r.factory_id=e.factory_id
 left join public.products p on p.id=o.product_id and p.factory_id=e.factory_id
 left join public.production_lines l on l.id=e.line_id and l.factory_id=e.factory_id
 left join public.work_centers c on c.id=e.work_center_id and c.factory_id=e.factory_id
 left join public.memberships tech on tech.id=e.technician_id and tech.factory_id=e.factory_id
 left join public.memberships actor on actor.user_id=e.created_by and actor.factory_id=e.factory_id
 left join public.production_shifts sh on sh.id=e.shift_id and sh.factory_id=e.factory_id
 where e.factory_id=factory),
 filtered as materialized (select * from base b where
 (nullif(filters->>'request','') is null or b.production_request_id=(filters->>'request')::uuid)
 and (nullif(filters->>'product','') is null or b.product_id=(filters->>'product')::uuid)
 and (nullif(filters->>'technician','') is null or (filters->>'technician'='unknown' and b.technician_id is null)
 or (filters->>'technician'<>'unknown' and b.technician_id=nullif(nullif(filters->>'technician',''),'unknown')::uuid))
 and (nullif(filters->>'unit','') is null or b.unit_key=filters->>'unit')
 and (nullif(filters->>'shift','') is null or (filters->>'shift'='unknown' and b.shift_id is null)
 or (filters->>'shift'<>'unknown' and b.shift_id=nullif(nullif(filters->>'shift',''),'unknown')::uuid))
 and (nullif(filters->>'from','') is null or b.created_at>=((filters->>'from')::date::timestamp at time zone zone))
 and (nullif(filters->>'to','') is null or b.created_at<(((filters->>'to')::date+1)::timestamp at time zone zone))
 and (coalesce(filters->>'scrap','all')<>'has' or b.effective_scrap>0)
 and (nullif(filters->>'minimum_scrap','') is null or b.effective_scrap>=(filters->>'minimum_scrap')::numeric)
 and (coalesce(filters->>'corrected','all')='all' or b.corrected=(filters->>'corrected'='yes'))),
 ranked as (select *,row_number() over(order by
 case when sort_key='date' and sort_direction='asc' then created_at end asc,
 case when sort_key='date' and sort_direction='desc' then created_at end desc,
 case when sort_key='good' and sort_direction='asc' then effective_good end asc,
 case when sort_key='good' and sort_direction='desc' then effective_good end desc,
 case when sort_key='scrap' and sort_direction='asc' then effective_scrap end asc,
 case when sort_key='scrap' and sort_direction='desc' then effective_scrap end desc,
 case when sort_key='unit' and sort_direction='asc' then unit_name end asc,
 case when sort_key='unit' and sort_direction='desc' then unit_name end desc,
 case when sort_key='technician' and sort_direction='asc' then technician_name end asc,
 case when sort_key='technician' and sort_direction='desc' then technician_name end desc,
 case when sort_key='shift' and sort_direction='asc' then shift_name end asc,
 case when sort_key='shift' and sort_direction='desc' then shift_name end desc,
 created_at desc,id) as position from filtered),
 totals as (select coalesce(unit,'unknown') as measurement_unit,count(*) as records,
 sum(effective_good) as good,sum(effective_scrap) as scrap from filtered where unit in ('meter','piece') group by coalesce(unit,'unknown')),
 groups as (select coalesce(unit,'unknown') as measurement_unit,'unit' as kind,unit_key as identity,
 unit_name as name,unit_name_ar as name_ar,sum(effective_scrap) as scrap from filtered group by coalesce(unit,'unknown'),unit_key,unit_name,unit_name_ar
 union all select coalesce(unit,'unknown'),'shift',shift_id::text,shift_name,shift_name_ar,sum(effective_scrap) from filtered group by coalesce(unit,'unknown'),shift_id,shift_name,shift_name_ar
 union all select coalesce(unit,'unknown'),'technician',technician_id::text,technician_name,technician_name,sum(effective_scrap) from filtered group by coalesce(unit,'unknown'),technician_id,technician_name),
 winners as (select *,row_number() over(partition by measurement_unit,kind order by scrap desc,identity nulls last) as rank from groups)
 select jsonb_build_object('total',(select count(*) from filtered),'page',page,'page_size',50,
 'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.position),'[]') from
 (select ranked.*,(select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at,c.id),'[]') from
 public.production_entry_corrections c where c.factory_id=factory and c.entry_id=ranked.id) as corrections
 from ranked where position between (page-1)*50+1 and page*50) x),
 'unknown_unit_records',(select count(*) from filtered where unit is null or unit not in ('meter','piece')),
 'totals',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from totals t),
 'highest',(select coalesce(jsonb_agg(to_jsonb(w)),'[]') from winners w where rank=1 and scrap>0 and measurement_unit in ('meter','piece'))) into result;
 return result;
end$$;

