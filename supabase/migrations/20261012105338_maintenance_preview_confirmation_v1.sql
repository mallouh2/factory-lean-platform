-- Local Phase 4. No activation update. Existing public RPC signature retained.
-- Fingerprints are change evidence, not authorization; all enforcement remains mandatory.
create or replace function private.maintenance_reader_context(f uuid,rid uuid,request_revision integer,schedule_revision integer,
 range_start timestamptz,range_end timestamptz,evaluated timestamptz)
 returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare r public.maintenance_requests;s public.maintenance_schedules;m public.work_centers;fac public.factories;
 occupancy jsonb;config jsonb;scope jsonb;eligible boolean;uncertain boolean;transfer_open boolean;configuration_valid boolean;begin
 perform private.require_permission(f,'factory','view');perform private.require_permission(f,'maintenance','view');perform private.require_permission(f,'orders','view');
 if request_revision is null or request_revision<1 or schedule_revision is null or schedule_revision<0 then raise exception 'maintenance_invalid' using errcode='22023';end if;
 select * into r from public.maintenance_requests where factory_id=f and id=rid;
 if not found then raise exception 'maintenance_missing' using errcode='P0002';end if;
 select * into s from public.maintenance_schedules where factory_id=f and maintenance_request_id=r.id;
 if r.revision<>request_revision or coalesce(s.revision,0)<>schedule_revision then raise exception 'maintenance_preview_stale' using errcode='40001';end if;
 select * into m from public.work_centers where factory_id=f and id=r.work_center_id;
 select * into fac from public.factories where id=f;
 configuration_valid:=m.id is not null and not m.archived and m.category_id is not null and
 ((m.line_id is null and m.dependency_mode='independent') or exists(select 1 from public.production_lines where factory_id=f and id=m.line_id and not archived));
 eligible:=r.maintenance_kind='PLANNED' and r.estimated_duration_minutes>0 and r.status in ('OPEN','ASSIGNED') and s.hold_started_at is null;
 transfer_open:=exists(select 1 from public.production_transfers t where t.factory_id=f and t.ended_at is null and
 (t.original_id=m.id or t.alternative_id=m.id or t.original_id in(select id from public.work_centers where factory_id=f and line_id=m.line_id)));
 uncertain:=not configuration_valid or (m.status='running' and m.order_id is null) or
 (m.line_id is null and exists(select 1 from public.production_orders o join public.work_center_capabilities c on c.factory_id=o.factory_id and c.product_id=o.product_id
 where o.factory_id=f and c.work_center_id=m.id and o.status in ('planned','active') and o.id is distinct from m.order_id and
 not exists(select 1 from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=o.product_id and rs.kind='work_center' and rs.work_center_id=m.id)));
 select coalesce(jsonb_agg(to_jsonb(o) order by o.kind,o.id),'[]') into occupancy from
 (select * from private.maintenance_occupancy(f,m.line_id,null,m.id,s.id,null,true,evaluated,range_start,range_end,10001))o;
 uncertain:=uncertain or exists(select 1 from jsonb_array_elements(occupancy) x where (x->>'unknown')::boolean);
 config:=jsonb_build_object('machine',private.maintenance_machine_evidence(f,m.id),'calendar',jsonb_build_object('timezone',fac.timezone,'days',fac.working_days_mask,'start',fac.workday_start,'end',fac.workday_end),
 'physical',m.status,'assignment',m.order_id,'transfer_open',transfer_open,'uncertain',uncertain,
 -- Current whole-line topology and configured alternatives are evidence, never capacity credit.
 'topology',coalesce((select jsonb_agg(jsonb_build_object('evidence',private.maintenance_machine_evidence(f,c.id),'physical',c.status,'assignment',c.order_id) order by c.id)
 from public.work_centers c where c.factory_id=f and (c.id=m.id or (m.line_id is not null and c.line_id=m.line_id)
 or c.id in(select a.alternative_id from public.work_center_alternatives a where a.factory_id=f and
 (a.work_center_id=m.id or a.work_center_id in(select id from public.work_centers where factory_id=f and line_id=m.line_id))))),'[]'),
 'routing',coalesce((select jsonb_agg(to_jsonb(rs) order by rs.product_id,rs.position,rs.id) from public.production_routing_steps rs
 where rs.factory_id=f and (rs.work_center_id=m.id or rs.product_id in(select o.product_id from public.production_orders o where o.factory_id=f and o.line_id=m.line_id and o.status in ('planned','active'))
 or rs.product_id in(select c.product_id from public.work_center_capabilities c join public.work_centers wc on wc.factory_id=c.factory_id and wc.id=c.work_center_id
 where c.factory_id=f and (wc.id=m.id or (m.line_id is not null and wc.line_id=m.line_id))))),'[]'),
 'open_ownership',coalesce((select jsonb_agg(jsonb_build_object('transfer',to_jsonb(t),'owner_line',o.line_id,'product',o.product_id) order by t.id)
 from public.production_transfers t left join public.production_orders o on o.factory_id=t.factory_id and o.id=t.order_id
 where t.factory_id=f and t.ended_at is null and (t.original_id=m.id or t.alternative_id=m.id or o.line_id=m.line_id
 or t.original_id in(select id from public.work_centers where factory_id=f and line_id=m.line_id)
 or t.alternative_id in(select id from public.work_centers where factory_id=f and line_id=m.line_id))),'[]'));
 scope:=jsonb_build_object('machine_id',m.id,'line_id',m.line_id,'kind',case when m.line_id is null then 'MACHINE' else 'WHOLE_LINE' end,
 'dependency',m.dependency_mode,'buffer_credit',false,'alternative_credit',false);
 return jsonb_build_object('factory_id',f,'evaluated_at',evaluated,'timezone',fac.timezone,'request_id',r.id,'request_code',r.code,
 'request_revision',r.revision,'schedule_id',s.id,'schedule_revision',coalesce(s.revision,0),'duration_minutes',r.estimated_duration_minutes,
 'eligible',coalesce(eligible,false),'scope',scope,'configuration_hash',md5(config::text),
 'context_hash',encode(sha256(convert_to(jsonb_build_object('version',4,'factory',f,'config',config,'request',to_jsonb(r),'schedule',to_jsonb(s),'scope',scope,'occupancy',occupancy,'from',range_start,'until',range_end)::text,'UTF8')),'hex'),
 'physical_readiness',case when not configuration_valid then 'UNKNOWN' when m.status in ('idle','stopped','offline') then 'READY_NOW' else 'NOT_READY_NOW' end,
 'unknown',coalesce(uncertain,true),'transfer_open',transfer_open,'occupancy_complete',jsonb_array_length(occupancy)<=10000,
 'calendar_mode','ELAPSED_MAINTENANCE_STORED_PRODUCTION_WINDOWS','binding',false,
 'activation_enabled',(select enabled from private.maintenance_planning_activation where singleton),'confirmation_available',false,'occupancy',occupancy);
end$$;

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
 if not (select enabled from private.maintenance_planning_activation where singleton) then raise exception 'maintenance_planning_inactive';end if;
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
revoke all on function public.maintenance_planning_command(uuid,uuid,text,jsonb,integer,uuid) from public,anon,authenticated;
grant execute on function public.maintenance_planning_command(uuid,uuid,text,jsonb,integer,uuid) to authenticated;

-- Calendar/timezone are fingerprint inputs. Serialize their existing settings paths
-- before inherited factory row locks; preserve public signatures and validation.
alter function public.configure_working_calendar(uuid,integer,time,time) rename to maintenance_calendar_base;
alter function public.maintenance_calendar_base(uuid,integer,time,time) set schema private;
create function public.configure_working_calendar(factory uuid,days_mask integer,day_start time,day_end time)
returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'settings','edit');perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'settings','edit');perform private.maintenance_calendar_base(factory,days_mask,day_start,day_end);
end$$;
alter function private.update_settings(uuid,text,text,text) rename to maintenance_settings_base;
create function private.update_settings(f uuid,n text,tz text,logo text) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'settings','edit');perform private.maintenance_planning_lock(f);
 perform private.require_permission(f,'settings','edit');perform private.maintenance_settings_base(f,n,tz,logo);
end$$;
revoke all on function private.maintenance_calendar_base(uuid,integer,time,time),private.maintenance_settings_base(uuid,text,text,text),
 public.configure_working_calendar(uuid,integer,time,time),private.update_settings(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.configure_working_calendar(uuid,integer,time,time),private.update_settings(uuid,text,text,text) to authenticated;
