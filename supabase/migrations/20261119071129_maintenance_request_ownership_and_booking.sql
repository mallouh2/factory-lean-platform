-- Manual corrective work with a known duration can be booked into a future slot.
-- Downtime-linked corrective work stays in the original repair/stop workflow.
create function private.maintenance_kind_can_book(r public.maintenance_requests)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(r.maintenance_kind='PLANNED' or
   (r.maintenance_kind='CORRECTIVE' and r.source='MANUAL' and r.downtime_id is null),false)
$$;
revoke all on function private.maintenance_kind_can_book(public.maintenance_requests) from public,anon,authenticated;


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
 if r.status not in ('OPEN','ASSIGNED') then raise exception 'maintenance_state';end if;
 if s.state in ('CONFIRMED','INVALIDATED') then raise exception 'maintenance_details_locked';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in ('maintenance_kind','estimated_duration_minutes','preferred_start','preferred_end','planning_notes','work_center_id','title','description','priority')) then raise exception 'maintenance_invalid';end if;
 if coalesce(payload->>'maintenance_kind','') not in ('CORRECTIVE','PLANNED') then raise exception 'maintenance_invalid';end if;
 if payload ? 'title' and coalesce(length(btrim(payload->>'title')),0) not between 1 and 200
 or payload ? 'description' and length(coalesce(payload->>'description',''))>4000
 or payload ? 'priority' and coalesce(payload->>'priority','') not in ('NORMAL','URGENT',r.priority) then
   raise exception 'maintenance_invalid';
 end if;
 if payload ? 'work_center_id' then
   if r.source='DOWNTIME' and (payload->>'work_center_id')::uuid is distinct from r.work_center_id then
     raise exception 'maintenance_downtime';
   end if;
   select * into m from public.work_centers where factory_id=factory and id=(payload->>'work_center_id')::uuid and not archived;
   if not found and (payload->>'work_center_id')::uuid is distinct from r.work_center_id then raise exception 'maintenance_machine';end if;
 end if;
 update public.maintenance_requests set
 work_center_id=coalesce(m.id,r.work_center_id),
 line_id=case when m.id is not null and m.id<>r.work_center_id then m.line_id else r.line_id end,
 title=case when payload ? 'title' then btrim(payload->>'title') else r.title end,
 description=case when payload ? 'description' then coalesce(payload->>'description','') else r.description end,
 priority=coalesce(payload->>'priority',r.priority),
 maintenance_kind=payload->>'maintenance_kind',estimated_duration_minutes=(payload->>'estimated_duration_minutes')::integer,
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
 if not private.maintenance_kind_can_book(r) or r.status not in ('OPEN','ASSIGNED') or s.hold_started_at is not null then raise exception 'maintenance_state';end if;
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

create or replace function private.maintenance_reader_context_before_activation(f uuid,rid uuid,request_revision integer,schedule_revision integer,
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
 eligible:=private.maintenance_kind_can_book(r) and r.estimated_duration_minutes>0 and r.status in ('OPEN','ASSIGNED') and s.hold_started_at is null;
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

create or replace function private.maintenance_planned_lifecycle() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.maintenance_schedules;m public.work_centers;stamp timestamptz;before_row jsonb;begin
 if old.status=new.status or not private.maintenance_kind_can_book(old) then return new;end if;
 perform private.maintenance_planning_lock(new.factory_id);
 select * into s from public.maintenance_schedules where factory_id=new.factory_id and maintenance_request_id=new.id for update;
 -- An unscheduled corrective repair keeps its existing lifecycle. A booking uses the original hold and release rules.
 if old.maintenance_kind='CORRECTIVE' and (s.id is null or s.state in ('UNSCHEDULED','RELEASED')) then return new;end if;
 if new.status='CANCELLED' and s.state in ('CONFIRMED','INVALIDATED') then raise exception 'maintenance_unschedule_required';end if;
 if new.status='CANCELLED' and s.state='PROPOSED' then
 before_row:=to_jsonb(s);update public.maintenance_schedules set state='UNSCHEDULED',revision=revision+1,updated_at=clock_timestamp() where id=s.id;
 perform private.maintenance_schedule_history(s.id,before_row,'cancel','Unconfirmed request cancelled');
 end if;
 if old.status='ASSIGNED' and new.status='IN_PROGRESS' then
 if not (select enabled from private.maintenance_planning_activation where singleton) then raise exception 'maintenance_planning_inactive';end if;
 if s.state is distinct from 'CONFIRMED' then raise exception 'maintenance_approval_required';end if;
 stamp:=clock_timestamp();
 if stamp<s.planned_start then raise exception 'maintenance_early_start';end if;
 if stamp+make_interval(mins=>new.estimated_duration_minutes)>s.planned_end then raise exception 'maintenance_late_start';end if;
 select * into m from public.work_centers where factory_id=new.factory_id and id=new.work_center_id;
 if not found or m.archived or m.status not in ('idle','stopped','offline') then raise exception 'maintenance_machine_not_ready';end if;
 if (select evidence from public.maintenance_schedule_resources where schedule_id=s.id and machine_id=m.id) is distinct from private.maintenance_machine_evidence(new.factory_id,m.id) then raise exception 'maintenance_configuration_changed';end if;
 if exists(select 1 from public.production_transfers where factory_id=new.factory_id and ended_at is null and (original_id=m.id or alternative_id=m.id)) then raise exception 'maintenance_transfer_unresolved';end if;
 perform private.maintenance_assert_capacity(new.factory_id,m.line_id,null,m.id,stamp,s.planned_end,s.id);
 before_row:=to_jsonb(s);update public.maintenance_schedules set hold_started_at=stamp,revision=revision+1,updated_at=stamp where id=s.id;
 perform private.maintenance_schedule_history(s.id,before_row,'start','Actual planned maintenance hold started');
 elsif new.status='VERIFIED' and s.hold_started_at is not null then
 before_row:=to_jsonb(s);update public.maintenance_schedules set state='RELEASED',released_at=clock_timestamp(),released_by=auth.uid(),revision=revision+1,updated_at=clock_timestamp() where id=s.id;
 perform private.maintenance_schedule_history(s.id,before_row,'release','Independent verification; physical machine unchanged');
 end if;
 return new;
end$$;

create or replace function public.stop_machine_for_maintenance(factory uuid,work_center uuid,nature text,reason uuid,activity text,
 notes text,schedule uuid,expected_revision integer,expected_request_revision integer,request_id uuid) returns uuid
 language plpgsql security definer set search_path='' as $$
declare s public.maintenance_schedules;r public.maintenance_requests;old public.maintenance_commands;keyed jsonb;e uuid;approval_rev integer;begin
 perform private.require_permission(factory,'factory','view');
 if not private.has_permission(factory,'centers','edit') then perform private.require_permission(factory,'machine_status','edit');end if;
 perform private.require_permission(factory,'maintenance','view');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then raise exception 'maintenance_stop_conflict' using errcode='40001';end if;
 perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');
 if not private.has_permission(factory,'centers','edit') then perform private.require_permission(factory,'machine_status','edit');end if;
 if request_id is null then raise exception 'maintenance_invalid';end if;
 if nature='planned' and (activity is null or activity not in ('cleaning','changeover','preventive_maintenance','inspection','planned_process','other')) then raise exception 'invalid_planned_activity';end if;
 keyed:=jsonb_build_object('machine',work_center,'nature',nature,'reason',reason,'activity',activity,'notes',notes,
 'schedule',schedule,'revision',expected_revision,'request_revision',expected_request_revision);
 select * into old from public.maintenance_commands c where c.factory_id=factory and c.request_id=stop_machine_for_maintenance.request_id;
 if found then
 if old.actor_id<>auth.uid() or old.operation<>'stop:linked' or old.payload<>keyed then raise exception 'request_conflict';end if;
 select event_id into e from public.maintenance_stop_associations a where a.factory_id=factory and a.request_id=stop_machine_for_maintenance.request_id;
 return e;end if;
 if not (select enabled from private.maintenance_planning_activation where singleton) then raise exception 'maintenance_planning_inactive';end if;
 select * into r from public.maintenance_requests where factory_id=factory and id=(select maintenance_request_id from public.maintenance_schedules where factory_id=factory and id=schedule) for update;
 select * into s from public.maintenance_schedules where factory_id=factory and id=schedule for update;
 if s.id is null then raise exception 'maintenance_missing';end if;
 if s.revision is distinct from expected_revision or r.revision is distinct from expected_request_revision then raise exception 'maintenance_stop_conflict' using errcode='40001';end if;
 if s.state<>'CONFIRMED' or not private.maintenance_kind_can_book(r) or r.status not in ('OPEN','ASSIGNED','IN_PROGRESS') then raise exception 'maintenance_approval_required';end if;
 if clock_timestamp()<s.planned_start or clock_timestamp()>=s.planned_end then raise exception 'maintenance_stop_window';end if;
 if r.work_center_id<>work_center or not exists(select 1 from public.maintenance_schedule_resources rr where rr.factory_id=factory and rr.schedule_id=s.id
 and rr.resource_kind='MACHINE' and rr.machine_id=work_center and rr.evidence=private.maintenance_machine_evidence(factory,work_center)) then raise exception 'maintenance_stop_scope';end if;
 select revision into approval_rev from public.maintenance_schedule_revisions where factory_id=factory and schedule_id=s.id and event in ('confirm','reschedule') order by revision desc limit 1;
 e:=public.stop_machine(factory,work_center,nature,reason,activity,notes);
 perform private.maintenance_append_stop(factory,e,s.id,approval_rev,'LINK','Explicit scheduled stop',request_id);
 insert into public.maintenance_commands(factory_id,request_id,actor_id,operation,payload,result_id) values(factory,request_id,auth.uid(),'stop:linked',keyed,r.id);
 return e;
end$$;

create or replace function public.maintenance_stop_context(factory uuid,machine uuid default null,maintenance_request uuid default null,
 history_page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare req public.maintenance_requests;chosen public.maintenance_schedules;items jsonb;current_rows jsonb;history jsonb;total integer;begin
 perform private.require_permission(factory,'factory','view');
 if (machine is null)=(maintenance_request is null) or history_page not between 1 and 1000000 then raise exception 'maintenance_invalid' using errcode='22023';end if;
 if machine is not null then
 perform private.require_permission(factory,'maintenance','view');
 if not private.has_permission(factory,'centers','edit') then perform private.require_permission(factory,'machine_status','edit');end if;
 if not exists(select 1 from public.work_centers where factory_id=factory and id=machine and not archived) then raise exception 'maintenance_machine';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.planned_start,x.id),'[]') into items from (
 select s.id,s.revision,r.revision request_revision,r.code,r.title,s.planned_start,s.planned_end
 from public.maintenance_schedules s join public.maintenance_requests r on r.factory_id=s.factory_id and r.id=s.maintenance_request_id
 where s.factory_id=factory and r.work_center_id=machine and private.maintenance_kind_can_book(r) and r.status in ('OPEN','ASSIGNED','IN_PROGRESS')
 and s.state='CONFIRMED' and s.planned_start<=statement_timestamp() and s.planned_end>statement_timestamp()
 and (select enabled from private.maintenance_planning_activation where singleton)
 and exists(select 1 from public.maintenance_schedule_resources rr where rr.factory_id=factory and rr.schedule_id=s.id
 and rr.machine_id=machine and rr.evidence=private.maintenance_machine_evidence(factory,machine)) limit 101)x;
 if jsonb_array_length(items)>100 then raise exception 'maintenance_preview_incomplete';end if;
 return jsonb_build_object('factory',factory,'machine',machine,'eligible',items);
 end if;
 select * into req from public.maintenance_requests where factory_id=factory and id=maintenance_request;
 if not found or not private.maintenance_visible(factory,req.assigned_to,req.requested_by) then raise exception 'permission_denied' using errcode='42501';end if;
 perform private.require_permission(factory,'downtime','view');
 select * into chosen from public.maintenance_schedules where factory_id=factory and maintenance_request_id=req.id;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.started_at desc,x.event_id),'[]') into current_rows from (
 select a.id,a.schedule_id,a.event_id,a.revision,a.relationship,a.approval_revision,a.approval,d.started_at,d.ended_at
 from public.maintenance_stop_associations a join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id
 where a.factory_id=factory and a.schedule_id=chosen.id and a.operation='LINK'
 and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=factory and n.event_id=a.event_id and n.revision>a.revision)
 order by d.started_at desc,a.event_id limit 101)x;
 if jsonb_array_length(current_rows)>100 then raise exception 'maintenance_preview_incomplete';end if;
 -- History includes later unlink/reassignment evidence for events once linked here.
 select count(*) into total from public.maintenance_stop_associations a where a.factory_id=factory and exists(
 select 1 from public.maintenance_stop_associations origin where origin.factory_id=factory and origin.event_id=a.event_id and origin.schedule_id=chosen.id);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.recorded_at desc,x.id),'[]') into history from (
 select a.*,d.started_at,d.ended_at from public.maintenance_stop_associations a join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id where a.factory_id=factory and exists(
 select 1 from public.maintenance_stop_associations origin where origin.factory_id=factory and origin.event_id=a.event_id and origin.schedule_id=chosen.id)
 order by a.recorded_at desc,a.id limit 25 offset (history_page-1)*25)x;
 return jsonb_build_object('factory',factory,'request',req.id,'current',current_rows,'history',history,'history_total',total);
end$$;
