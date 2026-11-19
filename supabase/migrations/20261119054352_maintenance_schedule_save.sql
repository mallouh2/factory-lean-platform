-- A single save uses the existing locked confirmation, resources, history and retry guards.
create or replace function public.maintenance_planning_command(factory uuid,maintenance_request uuid,operation text,payload jsonb,
 expected_revision integer,request_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.maintenance_requests;s public.maintenance_schedules;m public.work_centers;old public.maintenance_commands;
 ctx jsonb;keyed jsonb;before_row jsonb;a timestamptz;b timestamptz;stamp timestamptz;sid uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='details' then perform private.require_permission(factory,'maintenance','edit');else
 perform private.require_permission(factory,'maintenance','view');perform private.require_permission(factory,'orders','edit');end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or operation not in ('details','propose','confirm','reschedule','unschedule','save') then raise exception 'maintenance_invalid';end if;
 if operation in ('confirm','reschedule','save') then
 perform private.require_permission(factory,'orders','view');
 -- A transaction-level old snapshot cannot reload state committed during a lock wait.
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
 raise exception 'maintenance_preview_stale' using errcode='40001',detail='{"reason":"snapshot_isolation"}';end if;
 end if;
 perform private.maintenance_planning_lock(factory);
 -- Serialize activation changes after the existing structure lock, before item rows.
 if operation in ('confirm','reschedule','save') then
 perform 1 from private.maintenance_planning_activation where singleton for share;
 end if;
 perform private.require_permission(factory,'factory','view');
 if operation in ('confirm','reschedule','save') then perform private.require_permission(factory,'orders','view');end if;
 if operation='details' then perform private.require_permission(factory,'maintenance','edit');else
 perform private.require_permission(factory,'maintenance','view');perform private.require_permission(factory,'orders','edit');end if;
 select * into r from public.maintenance_requests where factory_id=factory and id=maintenance_request for update;
 if not found then raise exception 'maintenance_missing';end if;
 keyed:=jsonb_build_object('id',maintenance_request,'revision',expected_revision,'payload',payload);
 select * into old from public.maintenance_commands c where c.factory_id=factory and c.request_id=maintenance_planning_command.request_id;
 if found then if old.actor_id<>auth.uid() or old.operation<>'planning:'||operation or old.payload<>keyed then raise exception 'request_conflict';end if;return old.result_id;end if;
 select * into s from public.maintenance_schedules where factory_id=factory and maintenance_request_id=r.id for update;
 if operation='details' then
 if r.revision is distinct from expected_revision then raise exception 'maintenance_conflict';end if;
 if r.status not in ('OPEN','ASSIGNED') or s.state in ('CONFIRMED','INVALIDATED') then raise exception 'maintenance_state';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in ('maintenance_kind','estimated_duration_minutes','preferred_start','preferred_end','planning_notes')) then raise exception 'maintenance_invalid';end if;
 if coalesce(payload->>'maintenance_kind','') not in ('CORRECTIVE','PLANNED') then raise exception 'maintenance_invalid';end if;
 update public.maintenance_requests set maintenance_kind=payload->>'maintenance_kind',estimated_duration_minutes=(payload->>'estimated_duration_minutes')::integer,
 preferred_start=(payload->>'preferred_start')::timestamptz,preferred_end=(payload->>'preferred_end')::timestamptz,planning_notes=coalesce(payload->>'planning_notes','') where id=r.id;
 else
 if coalesce(s.revision,0) is distinct from expected_revision then
 if operation in ('confirm','reschedule','save') then raise exception 'maintenance_preview_stale' using errcode='40001',detail='{"reason":"schedule_revision"}';end if;
 raise exception 'maintenance_conflict';end if;
 if operation in ('confirm','reschedule','save') then
 if not coalesce((select enabled from private.maintenance_planning_activation where singleton),false) then raise exception 'maintenance_planning_inactive';end if;
 if jsonb_typeof(payload->'context_hash') is distinct from 'string' or coalesce(payload->>'context_hash','') !~ '^[a-f0-9]{64}$'
 or jsonb_typeof(payload->'request_revision') is distinct from 'number' or coalesce(payload->>'request_revision','') !~ '^[1-9][0-9]*$' then
 raise exception 'maintenance_preview_required' using errcode='22023';end if;
 if (payload->>'request_revision')::numeric<>r.revision then raise exception 'maintenance_preview_stale' using errcode='40001',detail='{"reason":"request_revision"}';end if;
 end if;
 if r.maintenance_kind is distinct from 'PLANNED' or r.status not in ('OPEN','ASSIGNED') or s.hold_started_at is not null then raise exception 'maintenance_state';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in ('start','end','reason')
 and not (operation in ('confirm','reschedule','save') and k in ('context_hash','request_revision'))) then raise exception 'maintenance_invalid';end if;
 if operation='confirm' and (payload ? 'start' or payload ? 'end') then raise exception 'maintenance_invalid';end if;
 if operation in ('reschedule','unschedule') and coalesce(length(btrim(payload->>'reason')),0) not between 1 and 4000 then raise exception 'maintenance_note';end if;
 if s.id is not null and (operation not in ('confirm','save') or operation='save' and s.state in ('CONFIRMED','INVALIDATED'))
 and coalesce(length(btrim(payload->>'reason')),0) not between 1 and 4000 then raise exception 'maintenance_note';end if;
 before_row:=case when s.id is not null then to_jsonb(s) end;stamp:=clock_timestamp();
 if operation='unschedule' then
 if s.id is null or s.state not in ('PROPOSED','CONFIRMED','INVALIDATED') then raise exception 'maintenance_state';end if;
 update public.maintenance_schedules set state='UNSCHEDULED',invalid_reason=null,revision=revision+1,updated_at=stamp where id=s.id;sid:=s.id;
 else
 if s.id is not null and s.state in ('CONFIRMED','INVALIDATED') and operation not in ('reschedule','save') then raise exception 'maintenance_state';end if;
 if operation='confirm' and (s.id is null or s.state<>'PROPOSED') then raise exception 'maintenance_state';end if;
 a:=case when operation='confirm' then s.planned_start else (payload->>'start')::timestamptz end;
 b:=case when operation='confirm' then s.planned_end else coalesce((payload->>'end')::timestamptz,a+make_interval(mins=>r.estimated_duration_minutes)) end;
 if operation='save' then
   if payload ? 'end' or coalesce(r.estimated_duration_minutes,0)<=0 then raise exception 'maintenance_invalid';end if;
   b:=a+make_interval(mins=>r.estimated_duration_minutes);
 end if;
 if a is null or not isfinite(a) or a<stamp or b is null or not isfinite(b) or b<a+make_interval(mins=>r.estimated_duration_minutes) then raise exception 'maintenance_unknown_window';end if;
 if operation in ('confirm','reschedule','save')
 and ((r.preferred_start is not null and a<r.preferred_start) or (r.preferred_end is not null and b>r.preferred_end))
 and coalesce(length(btrim(payload->>'reason')),0) not between 1 and 4000 then
   raise exception 'maintenance_preferred_reason';
 end if;
 select * into m from public.work_centers where factory_id=factory and id=r.work_center_id;
 if operation not in ('confirm','reschedule','save') then
 if m.id is null or m.archived or m.category_id is null then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is null and m.dependency_mode<>'independent' then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is not null and not exists(select 1 from public.production_lines where factory_id=factory and id=m.line_id and not archived) then raise exception 'maintenance_configuration_unknown';end if;
 end if;
 if operation in ('confirm','reschedule','save') then
 -- New SELECT after structure/request/schedule locks; reuse the exact reader fingerprint.
 ctx:=private.maintenance_reader_context(factory,r.id,r.revision,coalesce(s.revision,0),a,b,stamp);
 if payload->>'context_hash' is distinct from ctx->>'context_hash' then
 raise exception 'maintenance_preview_stale' using errcode='40001',detail='{"reason":"context_changed"}';end if;
 if m.id is null or m.archived or m.category_id is null then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is null and m.dependency_mode<>'independent' then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is not null and not exists(select 1 from public.production_lines where factory_id=factory and id=m.line_id and not archived) then raise exception 'maintenance_configuration_unknown';end if;
 if not (ctx->>'occupancy_complete')::boolean then raise exception 'maintenance_preview_incomplete' using errcode='22023';end if;
 if (ctx->>'unknown')::boolean or not (ctx->>'eligible')::boolean then raise exception 'maintenance_configuration_unknown';end if;
 if exists(select 1 from public.production_transfers t where t.factory_id=factory and t.ended_at is null and
 (t.original_id=m.id or t.alternative_id=m.id or t.original_id in(select id from public.work_centers where factory_id=factory and line_id=m.line_id))) then raise exception 'maintenance_transfer_unresolved';end if;
 perform private.maintenance_assert_capacity(factory,m.line_id,null,m.id,a,b,s.id);
 end if;
 if s.id is null then
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end,confirmed_at,confirmed_by)
 values(factory,r.id,case when operation='save' then 'CONFIRMED' else 'PROPOSED' end,a,b,
 case when operation='save' then stamp end,case when operation='save' then auth.uid() end) returning id into sid;
 else
 sid:=s.id;update public.maintenance_schedules set planned_start=a,planned_end=b,
 state=case when operation='propose' then 'PROPOSED' else 'CONFIRMED' end,
 confirmed_at=case when operation='propose' then null else stamp end,confirmed_by=case when operation='propose' then null else auth.uid() end,
 invalid_reason=null,revision=revision+1,updated_at=stamp where id=sid;
 end if;
 delete from public.maintenance_schedule_resources where schedule_id=sid;
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,machine_id,impact_reason,evidence)
 values(factory,sid,'MACHINE',m.id,'Physical machine reserved',private.maintenance_machine_evidence(factory,m.id));
 if m.line_id is not null then
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,line_id,impact_reason,evidence)
 values(factory,sid,'LINE',m.line_id,'Conservative whole-line occupancy: no enforceable future route/alternative/buffer allocation',jsonb_build_object('line',m.line_id));end if;
 end if;
 perform private.maintenance_schedule_history(sid,before_row,case when operation='save' then case when s.state in ('CONFIRMED','INVALIDATED') then 'reschedule' else 'confirm' end else operation end,coalesce(payload->>'reason','Initial proposal/confirmation'),request_id);
 end if;
 insert into public.maintenance_commands(factory_id,request_id,actor_id,operation,payload,result_id) values(factory,request_id,auth.uid(),'planning:'||operation,keyed,r.id);
 return r.id;
end$$;

-- Unscheduled requests retain the revision needed to schedule them again outside their old window.
CREATE OR REPLACE FUNCTION private.planning_operational_rows(f uuid, a timestamp with time zone, b timestamp with time zone, l uuid, w uuid, domain text, at_time timestamp with time zone)
 RETURNS TABLE(kind text, id uuid, payload jsonb, uncertain boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with event_scope as materialized (
 select d.* from public.downtime_events d where d.factory_id=f and
 (d.ended_at is null or (d.started_at<b and d.ended_at>a))
 ), links as materialized (
 select assoc.schedule_id,d.id event_id,d.work_center_id,d.started_at,d.ended_at,assoc.id association_id,assoc.revision,assoc.approval_revision,assoc.approval->>'planned_start' approved_start,assoc.approval->>'planned_end' approved_end,row_number() over(partition by assoc.schedule_id order by case when d.started_at<b and coalesce(d.ended_at,'infinity')>a then 0 else 1 end,d.started_at,d.id) ordinal
 from event_scope d join public.maintenance_stop_associations assoc on assoc.factory_id=f and assoc.event_id=d.id
 where assoc.operation='LINK' and not exists(select 1 from public.maintenance_stop_associations n
 where n.factory_id=f and n.event_id=assoc.event_id and n.revision>assoc.revision)
 ), stop_groups as (
 select schedule_id,min(started_at) filter(where ended_at is null) open_start,
 count(*) filter(where started_at<b and coalesce(ended_at,'infinity')>a) stop_count,
 coalesce(jsonb_agg(jsonb_build_object('id',event_id,'work_center_id',work_center_id,'started_at',started_at,'ended_at',ended_at,
 'association_id',association_id,'association_revision',revision,'approval_revision',approval_revision,'approved_start',approved_start,'approved_end',approved_end) order by started_at,event_id)
 filter(where ordinal<=100 and started_at<b and coalesce(ended_at,'infinity')>a),'[]') stops from links group by schedule_id
 ), candidates as materialized (
 select s.*,g.open_start,coalesce(g.stop_count,0) stop_count,coalesce(g.stops,'[]') stops,
 least(s.planned_start,coalesce(s.hold_started_at,s.planned_start),coalesce(g.open_start,s.planned_start)) effective_start,
 case when s.state='RELEASED' then coalesce(s.released_at,s.planned_end)
 when s.state in ('CONFIRMED','INVALIDATED') and (s.hold_started_at is not null or g.open_start is not null or s.state='INVALIDATED' or s.planned_end<=at_time)
 then 'infinity'::timestamptz else s.planned_end end effective_end
 from public.maintenance_schedules s left join stop_groups g on g.schedule_id=s.id
 where s.factory_id=f and ((s.planned_start<b and s.planned_end>a) or
 (s.state in ('CONFIRMED','INVALIDATED') and (s.hold_started_at is not null or g.open_start is not null or s.state='INVALIDATED' or s.planned_end<=at_time))
 or coalesce(g.stop_count,0)>0 or (s.released_at>a and s.planned_start<b))
 ), resource_rows as materialized (
 select c.id schedule_id,r.resource_kind,r.machine_id,r.line_id,r.impact_reason,m.line_id current_line
 from candidates c join public.maintenance_schedule_resources r on r.factory_id=f and r.schedule_id=c.id
 left join public.work_centers m on m.factory_id=f and m.id=r.machine_id
 ), line_scope as (
 select schedule_id,line_id from resource_rows where line_id is not null
 union select schedule_id,current_line from resource_rows where current_line is not null
 union select c.id,m.line_id from candidates c join public.maintenance_requests r on r.factory_id=f and r.id=c.maintenance_request_id
 join public.work_centers m on m.factory_id=f and m.id=r.work_center_id where m.line_id is not null and not exists(select 1 from resource_rows rr where rr.schedule_id=c.id)
 union select r.schedule_id,o.line_id from resource_rows r join public.production_transfers t on t.factory_id=f and t.alternative_id=r.machine_id and t.ended_at is null
 join public.production_orders o on o.factory_id=f and o.id=t.order_id where o.line_id is not null
 ), machine_scope as (
 select schedule_id,machine_id from resource_rows where machine_id is not null
 union select c.id,r.work_center_id from candidates c join public.maintenance_requests r on r.factory_id=f and r.id=c.maintenance_request_id
 ), line_groups as (select schedule_id,jsonb_agg(line_id order by line_id) line_ids from line_scope group by schedule_id),
 machine_groups as (select schedule_id,jsonb_agg(machine_id order by machine_id) machine_ids from machine_scope group by schedule_id),
 product_groups as (select rr.schedule_id,jsonb_agg(distinct rs.product_id order by rs.product_id) product_ids from resource_rows rr join public.production_routing_steps rs on rs.factory_id=f and rs.kind='work_center' and rs.work_center_id=rr.machine_id group by rr.schedule_id),
 resource_groups as (select rr.schedule_id,jsonb_agg(jsonb_build_object('resource_kind',rr.resource_kind,'machine_id',rr.machine_id,'line_id',rr.line_id,'impact_reason',rr.impact_reason) order by rr.resource_kind,rr.machine_id,rr.line_id) resources from resource_rows rr group by rr.schedule_id),
 groups as (
 select c.id,coalesce(lg.line_ids,'[]') line_ids,coalesce(mg.machine_ids,'[]') machine_ids,coalesce(pg.product_ids,'[]') product_ids,coalesce(rg.resources,'[]') resources
 from candidates c left join line_groups lg on lg.schedule_id=c.id left join machine_groups mg on mg.schedule_id=c.id
 left join product_groups pg on pg.schedule_id=c.id left join resource_groups rg on rg.schedule_id=c.id
 ), maintenance as (
 select 'MAINTENANCE'::text kind,c.id,jsonb_build_object('schedule',to_jsonb(c)-'open_start'-'stop_count'-'stops'-'effective_start'-'effective_end'||
 jsonb_build_object('work_center_id',r.work_center_id,'code',r.code,'machine_code',m.code,'machine_name',m.name,'machine_name_ar',m.name_ar,'resources',g.resources,'line_ids',g.line_ids,'machine_ids',g.machine_ids,
 'actual_stops',case when c.stop_count<=100 then c.stops else '[]'::jsonb end,
 'actual_hold',c.state in ('CONFIRMED','INVALIDATED') and (c.hold_started_at is not null or c.open_start is not null),'overrun',c.state in ('CONFIRMED','INVALIDATED') and (c.hold_started_at is not null or c.open_start is not null) and c.planned_end<at_time,
 'missed_window',c.state='CONFIRMED' and c.hold_started_at is null and c.open_start is null and c.planned_end<=at_time,
 'occupancy',jsonb_build_object('id',c.id,'lineIds',g.line_ids,'machineIds',g.machine_ids,'productIds',g.product_ids,
 'start',c.effective_start,'finish',case when isfinite(c.effective_end) then c.effective_end end,'continues',not isfinite(c.effective_end),'reserved',c.state in ('CONFIRMED','INVALIDATED'))),
 'request',to_jsonb(r)||jsonb_build_object('machine_code',m.code,'machine_name',m.name,'machine_name_ar',m.name_ar)) payload,
 (c.stop_count>100 or c.state='RELEASED' and c.open_start is not null or (c.state in ('CONFIRMED','INVALIDATED') and not exists(select 1 from jsonb_array_elements(g.resources) resource where resource->>'resource_kind'='MACHINE' and resource->>'machine_id'=r.work_center_id::text))) uncertain
 from candidates c join groups g on g.id=c.id join public.maintenance_requests r on r.factory_id=f and r.id=c.maintenance_request_id
 join public.work_centers m on m.factory_id=f and m.id=r.work_center_id
 where ((c.effective_start<b and c.effective_end>a) or (c.planned_start<b and c.planned_end>a) or c.stop_count>0)
 and (l is null or g.line_ids ? l::text or jsonb_array_length(g.line_ids)=0 or c.state='PROPOSED' and m.line_id=l)
 and (w is null or g.machine_ids ? w::text)
 ), production as (
 select 'PRODUCTION'::text kind,o.id,jsonb_build_object('order',to_jsonb(o),'request',to_jsonb(r),
 'occupancy',case when o.status in ('planned','active') and o.line_id is not null then jsonb_build_object(
 'id',o.id,'lineIds',jsonb_build_array(o.line_id),'start',case when domain<>'production_plan'and o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then null else o.start_time end,
 'finish',case when domain<>'production_plan'and o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then null else o.expected_finish end,'reserved',true) else null end) payload,
 (domain<>'production_plan'and o.status='active' and o.line_id is null or o.status='planned' and o.line_id is not null and (o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time)) uncertain
 from public.production_orders o join public.production_requests r on r.factory_id=f and r.id=o.request_id
 where domain in('all','production_plan') and o.factory_id=f and o.status<>'cancelled' and
 (o.status='active' or o.status='planned' and (o.line_id is null or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time) or o.start_time<b and o.expected_finish>a)
 and (l is null or o.line_id=l or o.line_id is null) and (w is null or
 o.id in(select m.order_id from public.work_centers m where m.factory_id=f and m.id=w) or
 o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center') or
 o.line_id in(select m.line_id from public.work_centers m where m.factory_id=f and m.id=w and m.line_id is not null))
 ), needs as (
 select 'REQUEST'::text kind,r.id,jsonb_build_object('request',to_jsonb(r)||jsonb_build_object('machine_code',m.code,'machine_name',m.name,'machine_name_ar',m.name_ar,'planning_schedule_revision',coalesce((select s.revision from public.maintenance_schedules s where s.factory_id=f and s.maintenance_request_id=r.id),0))) payload,false uncertain
 from public.maintenance_requests r join public.work_centers m on m.factory_id=f and m.id=r.work_center_id
 where r.factory_id=f and r.status in ('OPEN','ASSIGNED','IN_PROGRESS')
 and not exists(select 1 from public.maintenance_schedules s where s.factory_id=f and s.maintenance_request_id=r.id and s.state in ('PROPOSED','CONFIRMED','INVALIDATED','RELEASED'))
 and (l is null or m.line_id=l or m.line_id is null) and (w is null or m.id=w)
 ) select * from maintenance union all select * from production union all select * from needs;
$function$
;
