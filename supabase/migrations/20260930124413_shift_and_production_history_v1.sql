-- Configured identities only. No schedules or historical inference.
create table public.production_shifts (
 id uuid primary key default gen_random_uuid(), factory_id uuid not null references public.factories,
 name text not null check(length(trim(name)) between 1 and 120),
 name_ar text not null check(length(trim(name_ar)) between 1 and 120),
 archived boolean not null default false, created_at timestamptz not null default clock_timestamp(),
 created_by uuid not null references auth.users, unique(factory_id,id)
);
alter table public.production_shifts enable row level security;
create policy scoped_read on public.production_shifts for select to authenticated
 using(private.has_permission(factory_id,'orders','view') or private.has_permission(factory_id,'settings','view'));
grant select on public.production_shifts to authenticated;
create trigger audit_change after insert or update on public.production_shifts for each row execute function private.audit_change();
alter table public.production_entries
 add column shift_id uuid, add column original_shift_id uuid,
 add foreign key(factory_id,shift_id) references public.production_shifts(factory_id,id),
 add foreign key(factory_id,original_shift_id) references public.production_shifts(factory_id,id);
alter table public.production_entry_corrections
 add column shift_changed boolean not null default false,
 add column previous_shift_id uuid, add column corrected_shift_id uuid,
 add foreign key(factory_id,previous_shift_id) references public.production_shifts(factory_id,id),
 add foreign key(factory_id,corrected_shift_id) references public.production_shifts(factory_id,id);
create index on public.production_entries(factory_id,created_at desc,id);
create index on public.production_entries(factory_id,shift_id,created_at desc);
create index on public.production_entries(factory_id,order_id,created_at desc);

create function public.configure_production_shift(factory uuid, name text,name_ar text,
 id uuid default null, archived boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; begin
 perform private.require_permission(factory,'settings','edit');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(factory::text||':structure',0));
 if length(trim(coalesce(name,''))) not between 1 and 120 or length(trim(coalesce(name_ar,''))) not between 1 and 120
 or archived is null then raise exception 'shift_invalid';end if;
 if id is null then
 insert into public.production_shifts(factory_id,name,name_ar,archived,created_by)
 values($1,trim($2),trim($3),$5,auth.uid()) returning production_shifts.id into result;
 else update public.production_shifts s set name=trim($2),name_ar=trim($3),archived=$5
 where s.factory_id=$1 and s.id=$4 returning s.id into result;
 if result is null then raise exception 'shift_invalid';end if;end if;
 return result;
end$$;

-- Explicit validation shared by new entries and audited shift corrections.
create function private.validate_production_shift(f uuid,s uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 if s is not null and not exists(select 1 from public.production_shifts x where x.factory_id=f and x.id=s and not x.archived)
 then raise exception 'shift_invalid';end if;
 if s is null and exists(select 1 from public.production_shifts x where x.factory_id=f and not x.archived)
 then raise exception 'shift_required';end if;
end$$;

create function public.production_history(factory uuid,filters jsonb default '{}',
 sort_key text default 'date',sort_direction text default 'desc',page integer default 1)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; zone text; begin
 perform private.require_permission(factory,'orders','view');
 if sort_key not in ('date','good','scrap','unit','technician','shift') or sort_direction not in ('asc','desc')
 or page is null or page<1 or page>1000000 or jsonb_typeof(filters)<>'object' then raise exception 'history_invalid';end if;
 select timezone into zone from public.factories where id=factory;
 with base as materialized (
 select e.*,o.request_id,o.product_id,r.code as request_code,o.code as item_code,
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
 (nullif(filters->>'request','') is null or b.request_id=(filters->>'request')::uuid)
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
 sum(effective_good) as good,sum(effective_scrap) as scrap from filtered group by coalesce(unit,'unknown')),
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
 'totals',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from totals t),
 'highest',(select coalesce(jsonb_agg(to_jsonb(w)),'[]') from winners w where rank=1 and scrap>0)) into result;
 return result;
end$$;

create function public.production_history_options(factory uuid) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders','view');
 return jsonb_build_object(
 'requests',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.code,'name_ar',r.code) order by r.code),'[]') from public.production_requests r where r.factory_id=factory),
 'products',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'name_ar',p.name_ar) order by p.name),'[]') from public.products p where p.factory_id=factory),
 'units',(select coalesce(jsonb_agg(to_jsonb(u)),'[]') from (
 select 'line:'||id as id,name,name_ar from public.production_lines where factory_id=factory
 union all select 'machine:'||id,name,name_ar from public.work_centers where factory_id=factory and (line_id is null or exists(select 1 from public.production_entries e where e.work_center_id=work_centers.id))) u),
 'technicians',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',display_name,'name_ar',display_name)),'[]') from public.memberships where factory_id=factory),
 'shifts',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.production_shifts s where factory_id=factory));
end$$;
revoke all on function public.configure_production_shift(uuid,text,text,uuid,boolean),
 public.production_history(uuid,jsonb,text,text,integer),public.production_history_options(uuid),
 private.validate_production_shift(uuid,uuid) from public,anon;
revoke all on function private.validate_production_shift(uuid,uuid) from authenticated;
grant execute on function public.configure_production_shift(uuid,text,text,uuid,boolean),
 public.production_history(uuid,jsonb,text,text,integer),public.production_history_options(uuid) to authenticated;

drop function public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid);
drop function public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid);
revoke execute on function private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid),private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid) from authenticated;
create function private.record_production(f uuid,kind text,u uuid,i uuid,technician uuid,good numeric,scrap numeric,n text,confirmed boolean,r uuid,shift uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare job public.production_orders;previous public.production_entries;result uuid;total numeric;
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or technician is null or good is null or scrap is null or good<0 or scrap<0 or good+scrap<=0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(coalesce(n,''))>2000 then raise exception 'recording_invalid_quantity';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entries e where e.factory_id=f and e.request_id=r;
 if found then
   if previous.recording_version<>2 or previous.order_id<>i or previous.technician_id<>technician
     or previous.line_id is distinct from (case when kind='line' then u end)
     or previous.work_center_id is distinct from (case when kind='machine' then u end)
     or previous.good_quantity<>good or previous.scrap_quantity<>scrap or previous.notes<>coalesce(n,'')
     or previous.original_shift_id is distinct from shift or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false)
     then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 perform private.validate_production_shift(f,shift);
 select * into job from public.production_orders o where o.factory_id=f and o.id=i for update;
 if not found or not exists(select 1 from private.production_recording_units(f) x
   where x.unit_kind=kind and x.unit_id=u and x.item_id=i) then raise exception 'recording_invalid_unit';end if;
 if not exists(select 1 from public.memberships m where m.factory_id=f and m.id=technician and m.status='approved')
   then raise exception 'invalid_operator';end if;
 total:=job.good_quantity+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entries(factory_id,order_id,line_id,work_center_id,technician_id,unit,recording_version,
   produced,rejected,good_quantity,scrap_quantity,effective_good,effective_scrap,notes,created_by,created_at,request_id,
   running_good,remaining_quantity,overproduction_confirmed,shift_id,original_shift_id)
 values(f,i,case when kind='line' then u end,case when kind='machine' then u end,technician,job.unit,2,
   good+scrap,scrap,good,scrap,good,scrap,coalesce(n,''),auth.uid(),clock_timestamp(),r,total,greatest(job.target_quantity-total,0),coalesce(confirmed,false),shift,shift)
 returning id into result;
 update public.production_orders set produced_quantity=produced_quantity+good+scrap,rejected_quantity=rejected_quantity+scrap where id=i;
 return result;
end$$;
create function public.record_production(factory uuid,unit_kind text,production_unit uuid,item uuid,technician uuid,
 good numeric,scrap numeric,notes text default '',confirm_overproduction boolean default false,request_id uuid default gen_random_uuid(),shift uuid default null)
returns uuid language sql security invoker set search_path='' as $$
 select private.record_production(factory,unit_kind,production_unit,item,technician,good,scrap,notes,confirm_overproduction,request_id,shift)
$$;

create function private.correct_production(f uuid,e uuid,good numeric,scrap numeric,reason text,confirmed boolean,r uuid,shift uuid,change_shift boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare original public.production_entries;job public.production_orders;previous public.production_entry_corrections;result uuid;total numeric;new_shift uuid;
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or good is null or scrap is null or good<0 or scrap<0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(trim(coalesce(reason,''))) not between 3 and 2000 then raise exception 'recording_correction_reason';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entry_corrections c where c.factory_id=f and c.request_id=r;
 if found then
   if previous.entry_id<>e or previous.corrected_good<>good or previous.corrected_scrap<>scrap or previous.reason<>reason
     or previous.shift_changed is distinct from change_shift or (change_shift and previous.corrected_shift_id is distinct from shift) or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false) then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e;
 if not found then raise exception 'invalid_order';end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=original.order_id for update;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e for update;
 new_shift:=case when change_shift then shift else original.shift_id end;
 if change_shift and new_shift is distinct from original.shift_id then perform private.validate_production_shift(f,new_shift);end if;
 total:=job.good_quantity-original.effective_good+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entry_corrections(factory_id,entry_id,previous_good,previous_scrap,corrected_good,corrected_scrap,reason,created_by,request_id,overproduction_confirmed,previous_shift_id,corrected_shift_id,shift_changed)
 values(f,e,original.effective_good,original.effective_scrap,good,scrap,reason,auth.uid(),r,coalesce(confirmed,false),original.shift_id,new_shift,change_shift) returning id into result;
 update public.production_orders set produced_quantity=produced_quantity-original.effective_good-original.effective_scrap+good+scrap,
   rejected_quantity=rejected_quantity-original.effective_scrap+scrap where id=job.id;
 update public.production_entries set effective_good=good,effective_scrap=scrap,shift_id=new_shift where id=e;
 return result;
end$$;
create function public.correct_production_entry(factory uuid,entry uuid,good numeric,scrap numeric,reason text,
 confirm_overproduction boolean default false,request_id uuid default gen_random_uuid(),shift uuid default null,change_shift boolean default false)
returns uuid language sql security invoker set search_path='' as $$
 select private.correct_production(factory,entry,good,scrap,reason,confirm_overproduction,request_id,shift,change_shift)
$$;


revoke all on function private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid),public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid),private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean),public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean) from public,anon;
grant execute on function private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid),public.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid),private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean),public.correct_production_entry(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean) to authenticated;
