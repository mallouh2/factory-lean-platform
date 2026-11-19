-- Unscheduled production is queue demand, not an equipment capacity claim.
-- Preserve assigned/partial windows, active work, physical ownership and all locks/gates.
CREATE OR REPLACE FUNCTION private.maintenance_occupancy(f uuid, l uuid, p uuid, w uuid, skip_schedule uuid, skip_item uuid, with_production boolean, evaluated timestamp with time zone, range_start timestamp with time zone DEFAULT '-infinity'::timestamp with time zone, range_end timestamp with time zone DEFAULT 'infinity'::timestamp with time zone, record_limit integer DEFAULT NULL::integer)
 RETURNS TABLE(kind text, id uuid, starts timestamp with time zone, ends timestamp with time zone, state text, unknown boolean, sort_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with scoped as (
 select 'MAINTENANCE'::text kind,s.id,least(s.planned_start,coalesce(s.hold_started_at,s.planned_start),coalesce((select min(d.started_at) from public.maintenance_stop_associations a join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id where a.factory_id=f and a.schedule_id=s.id and a.operation='LINK' and d.ended_at is null and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=f and n.event_id=a.event_id and n.revision>a.revision)),s.planned_start)) starts,
 case when private.maintenance_active_stop(f,s.id) or s.hold_started_at is not null or s.state='INVALIDATED' or s.planned_end<=evaluated then 'infinity'::timestamptz else s.planned_end end ends,
 s.state,false unknown,s.planned_start sort_at from public.maintenance_schedules s
 where s.factory_id=f and s.id is distinct from skip_schedule and s.state in ('CONFIRMED','INVALIDATED')
 and exists(select 1 from public.maintenance_schedule_resources r left join public.work_centers m on m.factory_id=r.factory_id and m.id=r.machine_id
 where r.factory_id=f and r.schedule_id=s.id and
 ((l is not null and (r.line_id=l or m.line_id=l)) or (w is not null and r.machine_id=w)
 or (p is not null and r.machine_id in(select private.execution_effective_center(f,skip_item,rs.work_center_id) from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center'))
 or (l is not null and r.machine_id in(select t.alternative_id from public.production_transfers t join public.production_orders o on o.factory_id=t.factory_id and o.id=t.order_id where t.factory_id=f and t.ended_at is null and (case when o.status='active'then coalesce(o.actual_line_id,o.line_id)else o.line_id end)=l))))
 union all
 select 'PRODUCTION',o.id,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then '-infinity'::timestamptz else o.start_time end,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then 'infinity'::timestamptz else o.expected_finish end,
 o.status,(o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time),o.start_time
 from public.production_orders o where with_production and o.factory_id=f and o.id is distinct from skip_item and o.status in ('planned','active')
 and not (o.status='planned' and o.line_id is null and o.start_time is null and o.expected_finish is null
 and not exists(select 1 from public.work_centers assigned where assigned.factory_id=f and assigned.order_id=o.id))
 and ((l is not null and (case when o.status='active'then coalesce(o.actual_line_id,o.line_id)else o.line_id end)=l) or (w is not null and
 (o.id in(select c.order_id from public.work_centers c where c.factory_id=f and c.id=w)
 or o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center')))))
 select * from scoped where starts<range_end and ends>range_start order by kind,id limit record_limit;
$function$;
