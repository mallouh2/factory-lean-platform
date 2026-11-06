-- Phase6 integration only. Never enables the protected activation gate.
-- Reuse the frozen reader context/fingerprint and existing command validation.
alter function private.maintenance_reader_context(uuid,uuid,integer,integer,timestamptz,timestamptz,timestamptz) rename to maintenance_reader_context_before_activation;
revoke all on function private.maintenance_reader_context_before_activation(uuid,uuid,integer,integer,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;
create function private.maintenance_reader_context(f uuid,rid uuid,request_revision integer,schedule_revision integer,
 range_start timestamptz,range_end timestamptz,evaluated timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare context jsonb;enabled boolean;begin
 context:=private.maintenance_reader_context_before_activation(f,rid,request_revision,schedule_revision,range_start,range_end,evaluated);
 enabled:=coalesce((select a.enabled from private.maintenance_planning_activation a where singleton),false);
 return context||jsonb_build_object('activation_enabled',enabled,
 'confirmation_available',enabled and private.has_permission(f,'orders','edit'));
end$$;
revoke all on function private.maintenance_reader_context(uuid,uuid,integer,integer,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;

create or replace function public.maintenance_planning_command(factory uuid,maintenance_request uuid,operation text,payload jsonb,
 expected_revision integer,request_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.maintenance_requests;s public.maintenance_schedules;m public.work_centers;old public.maintenance_commands;
 ctx jsonb;keyed jsonb;before_row jsonb;a timestamptz;b timestamptz;stamp timestamptz;sid uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='details' then perform private.require_permission(factory,'maintenance','edit');else
 perform private.require_permission(factory,'maintenance','view');perform private.require_permission(factory,'orders','edit');end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or operation not in ('details','propose','confirm','reschedule','unschedule') then raise exception 'maintenance_invalid';end if;
 if operation in ('confirm','reschedule') then
 perform private.require_permission(factory,'orders','view');
 -- A transaction-level old snapshot cannot reload state committed during a lock wait.
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
 raise exception 'maintenance_preview_stale' using errcode='40001',detail='{"reason":"snapshot_isolation"}';end if;
 end if;
 perform private.maintenance_planning_lock(factory);
 -- Serialize activation changes after the existing structure lock, before item rows.
 if operation in ('confirm','reschedule') then
 perform 1 from private.maintenance_planning_activation where singleton for share;
 end if;
 perform private.require_permission(factory,'factory','view');
 if operation in ('confirm','reschedule') then perform private.require_permission(factory,'orders','view');end if;
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
 if operation in ('confirm','reschedule') then raise exception 'maintenance_preview_stale' using errcode='40001',detail='{"reason":"schedule_revision"}';end if;
 raise exception 'maintenance_conflict';end if;
 if operation in ('confirm','reschedule') then
 if not coalesce((select enabled from private.maintenance_planning_activation where singleton),false) then raise exception 'maintenance_planning_inactive';end if;
 if jsonb_typeof(payload->'context_hash') is distinct from 'string' or coalesce(payload->>'context_hash','') !~ '^[a-f0-9]{64}$'
 or jsonb_typeof(payload->'request_revision') is distinct from 'number' or coalesce(payload->>'request_revision','') !~ '^[1-9][0-9]*$' then
 raise exception 'maintenance_preview_required' using errcode='22023';end if;
 if (payload->>'request_revision')::numeric<>r.revision then raise exception 'maintenance_preview_stale' using errcode='40001',detail='{"reason":"request_revision"}';end if;
 end if;
 if r.maintenance_kind is distinct from 'PLANNED' or r.status not in ('OPEN','ASSIGNED') or s.hold_started_at is not null then raise exception 'maintenance_state';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in ('start','end','reason')
 and not (operation in ('confirm','reschedule') and k in ('context_hash','request_revision'))) then raise exception 'maintenance_invalid';end if;
 if operation='confirm' and (payload ? 'start' or payload ? 'end') then raise exception 'maintenance_invalid';end if;
 if operation in ('reschedule','unschedule') and coalesce(length(btrim(payload->>'reason')),0) not between 1 and 4000 then raise exception 'maintenance_note';end if;
 if s.id is not null and operation<>'confirm' and coalesce(length(btrim(payload->>'reason')),0) not between 1 and 4000 then raise exception 'maintenance_note';end if;
 before_row:=case when s.id is not null then to_jsonb(s) end;stamp:=clock_timestamp();
 if operation='unschedule' then
 if s.id is null or s.state not in ('PROPOSED','CONFIRMED','INVALIDATED') then raise exception 'maintenance_state';end if;
 update public.maintenance_schedules set state='UNSCHEDULED',invalid_reason=null,revision=revision+1,updated_at=stamp where id=s.id;sid:=s.id;
 else
 if s.id is not null and s.state in ('CONFIRMED','INVALIDATED') and operation<>'reschedule' then raise exception 'maintenance_state';end if;
 if operation='confirm' and (s.id is null or s.state<>'PROPOSED') then raise exception 'maintenance_state';end if;
 a:=case when operation='confirm' then s.planned_start else (payload->>'start')::timestamptz end;
 b:=case when operation='confirm' then s.planned_end else coalesce((payload->>'end')::timestamptz,a+make_interval(mins=>r.estimated_duration_minutes)) end;
 if a is null or not isfinite(a) or a<stamp or b is null or not isfinite(b) or b<a+make_interval(mins=>r.estimated_duration_minutes) then raise exception 'maintenance_unknown_window';end if;
 select * into m from public.work_centers where factory_id=factory and id=r.work_center_id;
 if operation not in ('confirm','reschedule') then
 if m.id is null or m.archived or m.category_id is null then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is null and m.dependency_mode<>'independent' then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is not null and not exists(select 1 from public.production_lines where factory_id=factory and id=m.line_id and not archived) then raise exception 'maintenance_configuration_unknown';end if;
 end if;
 if operation in ('confirm','reschedule') then
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
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end)
 values(factory,r.id,'PROPOSED',a,b) returning id into sid;
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
 perform private.maintenance_schedule_history(sid,before_row,operation,coalesce(payload->>'reason','Initial proposal/confirmation'),request_id);
 end if;
 insert into public.maintenance_commands(factory_id,request_id,actor_id,operation,payload,result_id) values(factory,request_id,auth.uid(),'planning:'||operation,keyed,r.id);
 return r.id;
end$$;
