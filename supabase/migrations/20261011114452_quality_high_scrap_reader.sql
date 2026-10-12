-- Read-only additive Quality assessment. No ledger, standards, or grants change.
begin;
create or replace function public.quality_read(factory uuid,query jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare mode text:=coalesce(query->>'mode','board');page integer:=coalesce((query->>'page')::integer,1);result jsonb;begin
 if jsonb_typeof(query) is distinct from 'object' or page not between 1 and 1000000 or octet_length(query::text)>5000 then raise exception 'quality_quantity';end if;
 if mode='notifications' then perform private.require_permission(factory,'orders','view');
 elsif mode='detail' then
  if not (private.has_permission(factory,'quality_history','view') or private.has_permission(factory,'orders','view')) then raise exception 'permission_denied' using errcode='42501';end if;
  result:=private.quality_detail(factory,(query->>'rejection')::uuid);if result is null then raise exception 'not_found' using errcode='P0002';end if;return result;
 elsif mode='history' then perform private.require_permission(factory,'quality_history','view');
 else perform private.require_permission(factory,'quality','view');end if;
 if mode='filters' then return jsonb_build_object(
  'products',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,name_ar from public.products where factory_id=factory order by name,id limit 5000)x),'[]'),
  'lines',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,name_ar from public.production_lines where factory_id=factory order by name,id limit 5000)x),'[]'),
  'shifts',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,name_ar from public.production_shifts where factory_id=factory order by name,id limit 5000)x),'[]'));
 elsif mode='reasons' then
  if length(coalesce(query->>'search',''))>120 then raise exception 'quality_reason';end if;
  if query->>'active_only'='true' then
   with matches as materialized(select * from public.quality_reasons where factory_id=factory and active and not is_other
    and (strpos(lower(name),lower(btrim(coalesce(query->>'search',''))))>0 or strpos(lower(name_ar),lower(btrim(coalesce(query->>'search',''))))>0)),
   choices as (select * from matches order by name,id limit 100 offset (page-1)*100),
   selectable as (select * from choices union select * from public.quality_reasons where factory_id=factory and active and (is_other or id=(query->>'selected')::uuid))
   select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by is_other,name,id) from selectable x),'[]'),'total',(select count(*) from matches),'page_size',100) into result;
   return result;
  end if;
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.quality_reasons where factory_id=factory order by is_other,name,id limit 100 offset (page-1)*100)x),'[]'));
 elsif mode in ('notifications','history') then
  with data as materialized(select q.id,q.created_at from public.quality_rejections q join public.quality_notifications n on n.factory_id=q.factory_id and n.id=q.id
   where q.factory_id=factory and (query->>'entry' is null or q.entry_id=(query->>'entry')::uuid)
   and (mode<>'notifications' or n.status<>'RESOLVED'))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(private.quality_detail(factory,x.id)) from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),'[]'),'total',(select count(*) from data)) into result;
 elsif mode='board' then
  with data as materialized(select e.id,e.order_id as item_id,e.unit,e.created_at,e.good_quantity::text as recorded_good,e.effective_good::text as current_good,
   coalesce((select sum(q.quantity) from public.quality_rejections q where q.factory_id=factory and q.entry_id=e.id and not exists(select 1 from public.quality_reversals v where v.factory_id=factory and v.rejection_id=q.id)),0) as rejected,
   s.id as source_id,s.physical_label,s.shift_id,s.shift_name,s.shift_name_ar,s.shift_date,s.factory_timezone,
   least(coalesce(s.quantity_available-private.source_reserved(factory,s.id),0),coalesce(b.on_hand-b.reserved,0))::text as eligible,
   o.code as item_code,pr.code as request_code,p.name as product_name,p.name_ar as product_name_ar,p.code as product_code,
   (case when p.stock_unit=e.unit then p.unit_weight_kg end)::text as weight_kg_per_unit,e.line_id,coalesce(l.name,c.name) as line_name,coalesce(l.name_ar,c.name_ar) as line_name_ar
   from public.production_entries e join public.production_orders o on o.factory_id=factory and o.id=e.order_id join public.products p on p.factory_id=factory and p.id=o.product_id
   left join public.production_requests pr on pr.factory_id=factory and pr.id=o.request_id left join public.finished_goods_sources s on s.factory_id=factory and s.entry_id=e.id
   left join public.finished_goods_balances b on b.factory_id=factory and b.product_id=o.product_id and b.unit=e.unit
   left join public.production_lines l on l.factory_id=factory and l.id=e.line_id left join public.work_centers c on c.factory_id=factory and c.id=e.work_center_id
   where e.factory_id=factory and e.unit in ('meter','piece') and e.effective_good>0
   and (query->>'entry' is null or e.id=(query->>'entry')::uuid)
   and (query->>'date' is null or s.shift_date=(query->>'date')::date) and (query->>'shift' is null or s.shift_id=(query->>'shift')::uuid)
   and (query->>'line' is null or e.line_id=(query->>'line')::uuid) and (query->>'product' is null or p.id=(query->>'product')::uuid)
   and (query->>'order' is null or pr.code ilike '%'||(query->>'order')||'%' or o.code ilike '%'||(query->>'order')||'%'))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object('rejected',x.rejected::text,'accepted',(x.current_good::numeric-x.rejected)::text,
   'scrap',jsonb_build_object('version',1,'product_id',o.product_id,'line_id',e.line_id,'unit',e.unit,
    'production_scrap_kg',e.effective_scrap_kg::text,'quality_scrap_kg',q.kg::text,
    'produced_kg',mass.kg::text,'captured_produced_kg',e.produced_weight_kg::text,
    'mass_source',case when e.produced_weight_kg is not null then 'CAPTURED' when mass.kg is not null then 'HISTORICAL_WEIGHT' else 'UNAVAILABLE' end,
    'weight_kg_per_unit',e.weight_kg_per_unit::text,
    'running_standard_percent',e.running_standard_percent::text,'standard_revision',e.scrap_standard_revision,
    'startup_id',e.lean_startup_id,'startup_standard_kg',s.standard_kg::text,'startup_standard_revision',s.standard_revision,
    'startup_kg',e.effective_startup_kg::text,'previous_startup_kg',history.previous_kg::text,
    'cumulative_startup_kg',history.total_kg::text,
    'startup_context_complete',e.lean_startup_id is null or (s.id is not null and history.complete),
    'startup_allowance_kg',allowance.kg::text,
    'above_running_standard',case when mass.kg>0 then
     e.effective_scrap_kg+q.kg-allowance.kg>mass.kg*e.running_standard_percent/100 end,
    'running_excess_kg',case when mass.kg>0 and e.running_standard_percent is not null
     and e.effective_scrap_kg is not null and allowance.kg is not null then
     greatest(0,e.effective_scrap_kg+q.kg-allowance.kg-mass.kg*e.running_standard_percent/100) end)) order by x.created_at desc,x.id)
   from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x
   join public.production_entries e on e.factory_id=factory and e.id=x.id
   join public.production_orders o on o.factory_id=factory and o.id=e.order_id
   -- A missing separate mass may be derived only from captured historical weight
   -- and known effective gross Good/new WIP. Never read today's Product weight here.
   cross join lateral(select coalesce(e.produced_weight_kg,case when e.unit in ('meter','piece')
    and e.weight_kg_per_unit>0 and e.effective_good>=0 and e.effective_unfinished>=0
    then (e.effective_good+e.effective_unfinished)*e.weight_kg_per_unit end) kg) mass
   left join public.lean_startups s on s.factory_id=factory and s.id=e.lean_startup_id
    and s.line_id=e.line_id and s.item_id=e.order_id and s.product_id=o.product_id
   cross join lateral(select coalesce(sum(r.actual_scrap_kg),0) kg from public.quality_rejections r
    where r.factory_id=factory and r.entry_id=e.id and r.disposition='SCRAP'
     and not exists(select 1 from public.quality_reversals v where v.factory_id=factory and v.rejection_id=r.id)) q
   -- Full startup history precedes UI filters/pagination and includes prior shifts.
   cross join lateral(select coalesce(sum(p.effective_startup_kg) filter(where (p.created_at,p.id)<(e.created_at,e.id)),0) previous_kg,
    coalesce(sum(p.effective_startup_kg),0) total_kg,count(*)=count(p.effective_startup_kg) complete
    from public.production_entries p where p.factory_id=factory and p.lean_startup_id=s.id and (p.created_at,p.id)<=(e.created_at,e.id)) history
   cross join lateral(select case when e.lean_startup_id is null then 0
    when s.standard_kg is null or not history.complete then null
    else least(e.effective_startup_kg,greatest(0,s.standard_kg-history.previous_kg)) end kg) allowance),'[]'),'total',(select count(*) from data),
   'quality_scrap_kg',(select coalesce(sum(q.actual_scrap_kg),0)::text from public.quality_rejections q join data d on d.id=q.entry_id where q.factory_id=factory and q.disposition='SCRAP' and not exists(select 1 from public.quality_reversals v where v.factory_id=factory and v.rejection_id=q.id))) into result;
 else raise exception 'quality_quantity';end if;
 return result||jsonb_build_object('page',page,'page_size',50);
end$$;

revoke all on function public.quality_read(uuid,jsonb) from public,anon;
grant execute on function public.quality_read(uuid,jsonb) to authenticated;
commit;
