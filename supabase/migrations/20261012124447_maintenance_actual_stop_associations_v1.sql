-- Local Phase 5B only. Does not enable Maintenance Planning or change Loss math.
create table public.maintenance_stop_associations (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 event_id uuid not null,revision integer not null check(revision>0),
 operation text not null check(operation in ('LINK','UNLINK')),schedule_id uuid not null,
 previous_id uuid references public.maintenance_stop_associations,
 approval_revision integer not null,approval jsonb not null,resources jsonb not null,
 relationship text not null check(relationship in ('PLANNED_MAINTENANCE','CONTEXTUAL_UNPLANNED')),
 actor_id uuid not null references auth.users,actor_name text,recorded_at timestamptz not null default clock_timestamp(),
 reason text not null check(length(btrim(reason)) between 1 and 4000),request_id uuid not null,
 reviewed_evidence jsonb not null default '[]',
 unique(factory_id,event_id,revision),unique(factory_id,request_id),
 foreign key(factory_id,schedule_id) references public.maintenance_schedules(factory_id,id),
 foreign key(factory_id,event_id) references public.downtime_events(factory_id,id)
);
create index maintenance_stop_schedule on public.maintenance_stop_associations(factory_id,schedule_id,event_id,revision desc);
alter table public.maintenance_stop_associations enable row level security;
revoke all on public.maintenance_stop_associations from public,anon,authenticated;
create function private.maintenance_stop_immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception 'maintenance_stop_immutable';end$$;
create trigger maintenance_stop_immutable before update or delete on public.maintenance_stop_associations
 for each row execute function private.maintenance_stop_immutable();

create function private.maintenance_active_stop(f uuid,sid uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.maintenance_stop_associations a join public.downtime_events d on d.id=a.event_id and d.factory_id=a.factory_id
 where a.factory_id=f and a.schedule_id=sid and a.operation='LINK' and d.ended_at is null
 and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=f and n.event_id=a.event_id and n.revision>a.revision));
$$;

-- Reuse authoritative occupancy; an open physical stop also extends its hold.
create or replace function private.maintenance_occupancy(f uuid,l uuid,p uuid,w uuid,
 skip_schedule uuid,skip_item uuid,with_production boolean,evaluated timestamptz,
 range_start timestamptz default '-infinity',range_end timestamptz default 'infinity',record_limit integer default null)
 returns table(kind text,id uuid,starts timestamptz,ends timestamptz,state text,unknown boolean,sort_at timestamptz)
 language sql stable security definer set search_path='' as $$
 with scoped as (
 select 'MAINTENANCE'::text kind,s.id,least(s.planned_start,coalesce(s.hold_started_at,s.planned_start),coalesce((select min(d.started_at) from public.maintenance_stop_associations a join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id where a.factory_id=f and a.schedule_id=s.id and a.operation='LINK' and d.ended_at is null and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=f and n.event_id=a.event_id and n.revision>a.revision)),s.planned_start)) starts,
 case when private.maintenance_active_stop(f,s.id) or s.hold_started_at is not null or s.state='INVALIDATED' or s.planned_end<=evaluated then 'infinity'::timestamptz else s.planned_end end ends,
 s.state,false unknown,s.planned_start sort_at from public.maintenance_schedules s
 where s.factory_id=f and s.id is distinct from skip_schedule and s.state in ('CONFIRMED','INVALIDATED')
 and exists(select 1 from public.maintenance_schedule_resources r left join public.work_centers m on m.factory_id=r.factory_id and m.id=r.machine_id
 where r.factory_id=f and r.schedule_id=s.id and
 ((l is not null and (r.line_id=l or m.line_id=l)) or (w is not null and r.machine_id=w)
 or (p is not null and r.machine_id in(select rs.work_center_id from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center'))
 or (l is not null and r.machine_id in(select t.alternative_id from public.production_transfers t join public.production_orders o on o.factory_id=t.factory_id and o.id=t.order_id where t.factory_id=f and t.ended_at is null and o.line_id=l))))
 union all
 select 'PRODUCTION',o.id,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then '-infinity'::timestamptz else o.start_time end,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then 'infinity'::timestamptz else o.expected_finish end,
 o.status,(o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time),o.start_time
 from public.production_orders o where with_production and o.factory_id=f and o.id is distinct from skip_item and o.status in ('planned','active')
 and ((l is not null and o.line_id=l) or (w is not null and
 (o.id in(select c.order_id from public.work_centers c where c.factory_id=f and c.id=w)
 or o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center')))))
 select * from scoped where starts<range_end and ends>range_start order by kind,id limit record_limit;
$$;

-- Protect physical holds even before the repair task starts. Existing command
-- authorization, independent verification and emergency invalidation stay intact.
create function private.maintenance_stop_schedule_guard() returns trigger
 language plpgsql security definer set search_path='' as $$begin
 if private.maintenance_active_stop(old.factory_id,old.id) and
 ((new.state not in ('CONFIRMED','INVALIDATED')) or
 (new.planned_start,new.planned_end,new.confirmed_at,new.confirmed_by) is distinct from (old.planned_start,old.planned_end,old.confirmed_at,old.confirmed_by)) then
 raise exception 'maintenance_active_stop';end if;return new;end$$;
create trigger maintenance_stop_schedule_guard before update on public.maintenance_schedules
 for each row execute function private.maintenance_stop_schedule_guard();
create function private.maintenance_stop_request_guard() returns trigger
 language plpgsql security definer set search_path='' as $$begin
 if new.status in ('CANCELLED','VERIFIED') and old.status<>new.status and exists(
 select 1 from public.maintenance_schedules s where s.factory_id=new.factory_id and s.maintenance_request_id=new.id
 and private.maintenance_active_stop(new.factory_id,s.id)) then raise exception 'maintenance_active_stop';end if;return new;end$$;
create trigger maintenance_actual_stop_request_guard before update of status on public.maintenance_requests
 for each row execute function private.maintenance_stop_request_guard();

create function private.maintenance_append_stop(f uuid,e uuid,sid uuid,approval_rev integer,op text,note text,retry uuid)
 returns uuid language plpgsql security definer set search_path='' as $$
declare d public.downtime_events;s public.maintenance_schedules;h public.maintenance_schedule_revisions;
 previous public.maintenance_stop_associations;v uuid;reviewed jsonb;begin
 select * into d from public.downtime_events where factory_id=f and id=e;
 if not found then raise exception 'maintenance_downtime';end if;
 if d.stop_nature not in ('planned','unplanned') then raise exception 'maintenance_stop_scope';end if;
 select * into s from public.maintenance_schedules where factory_id=f and id=sid;
 if not found then raise exception 'maintenance_missing';end if;
 select * into previous from public.maintenance_stop_associations where factory_id=f and event_id=e order by revision desc limit 1;
 if op='UNLINK' then
 if previous.id is null or previous.operation<>'LINK' or previous.schedule_id<>sid then raise exception 'maintenance_stop_conflict';end if;
 h.after_data:=previous.approval;h.resources:=previous.resources;h.revision:=previous.approval_revision;
 else
 select * into h from public.maintenance_schedule_revisions where factory_id=f and schedule_id=sid
 and revision=approval_rev and event in ('confirm','reschedule');
 if not found or not exists(select 1 from jsonb_array_elements(h.resources) r
 where r->>'resource_kind'='MACHINE' and r->>'machine_id'=d.work_center_id::text) then raise exception 'maintenance_stop_scope';end if;
 if d.stop_nature='planned' then
 if d.started_at<(h.after_data->>'planned_start')::timestamptz or d.started_at>=(h.after_data->>'planned_end')::timestamptz then
 raise exception 'maintenance_stop_window';end if;
 elsif d.started_at>=(h.after_data->>'planned_end')::timestamptz or coalesce(d.ended_at,'infinity')<=(h.after_data->>'planned_start')::timestamptz then
 raise exception 'maintenance_stop_window';end if;
 -- An open historical event cannot acquire an unrelated old/released reservation.
 if d.ended_at is null and (s.state not in ('CONFIRMED','INVALIDATED') or
 (s.planned_start,s.planned_end) is distinct from ((h.after_data->>'planned_start')::timestamptz,(h.after_data->>'planned_end')::timestamptz)) then
 raise exception 'maintenance_stop_scope';end if;
 end if;
 if coalesce(length(btrim(note)),0) not between 1 and 4000 then raise exception 'maintenance_note';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'calculated_at',x.calculated_at,'model_version',x.model_version,
 'result_hash',md5(x.result::text))),'[]') into reviewed from public.production_loss_estimates x where x.factory_id=f and x.event_id=e;
 insert into public.maintenance_stop_associations(factory_id,event_id,revision,operation,schedule_id,previous_id,approval_revision,
 approval,resources,relationship,actor_id,actor_name,reason,request_id,reviewed_evidence)
 values(f,e,coalesce(previous.revision,0)+1,op,sid,previous.id,h.revision,h.after_data,h.resources,
 case when d.stop_nature='planned' then 'PLANNED_MAINTENANCE' else 'CONTEXTUAL_UNPLANNED' end,auth.uid(),
 (select display_name from public.memberships where factory_id=f and user_id=auth.uid()),note,retry,reviewed) returning id into v;
 return v;
end$$;

create function public.stop_machine_for_maintenance(factory uuid,work_center uuid,nature text,reason uuid,activity text,
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
 if s.state<>'CONFIRMED' or r.maintenance_kind is distinct from 'PLANNED' or r.status not in ('OPEN','ASSIGNED','IN_PROGRESS') then raise exception 'maintenance_approval_required';end if;
 if clock_timestamp()<s.planned_start or clock_timestamp()>=s.planned_end then raise exception 'maintenance_stop_window';end if;
 if r.work_center_id<>work_center or not exists(select 1 from public.maintenance_schedule_resources rr where rr.factory_id=factory and rr.schedule_id=s.id
 and rr.resource_kind='MACHINE' and rr.machine_id=work_center and rr.evidence=private.maintenance_machine_evidence(factory,work_center)) then raise exception 'maintenance_stop_scope';end if;
 select revision into approval_rev from public.maintenance_schedule_revisions where factory_id=factory and schedule_id=s.id and event in ('confirm','reschedule') order by revision desc limit 1;
 e:=public.stop_machine(factory,work_center,nature,reason,activity,notes);
 perform private.maintenance_append_stop(factory,e,s.id,approval_rev,'LINK','Explicit scheduled stop',request_id);
 insert into public.maintenance_commands(factory_id,request_id,actor_id,operation,payload,result_id) values(factory,request_id,auth.uid(),'stop:linked',keyed,r.id);
 return e;
end$$;

create function public.correct_maintenance_stop(factory uuid,event uuid,schedule uuid,approval_revision integer,operation text,
 reason text,expected_revision integer,request_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare old public.maintenance_commands;current_link public.maintenance_stop_associations;keyed jsonb;v uuid;rid uuid;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','edit');perform private.require_permission(factory,'downtime','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then raise exception 'maintenance_stop_conflict' using errcode='40001';end if;
 perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','edit');perform private.require_permission(factory,'downtime','edit');
 if request_id is null or operation not in ('LINK','UNLINK') or operation is null then raise exception 'maintenance_invalid';end if;
 keyed:=jsonb_build_object('event',event,'schedule',schedule,'approval_revision',approval_revision,'operation',operation,'reason',reason,'revision',expected_revision);
 select * into old from public.maintenance_commands c where c.factory_id=factory and c.request_id=correct_maintenance_stop.request_id;
 if found then
 if old.actor_id<>auth.uid() or old.operation<>'stop:correct' or old.payload<>keyed then raise exception 'request_conflict';end if;
 select id into v from public.maintenance_stop_associations a where a.factory_id=factory and a.request_id=correct_maintenance_stop.request_id;return v;end if;
 select * into current_link from public.maintenance_stop_associations where factory_id=factory and event_id=event order by revision desc limit 1;
 if coalesce(current_link.revision,0) is distinct from expected_revision then raise exception 'maintenance_stop_conflict' using errcode='40001';end if;
 -- Closing the real stop is required before removing/reassigning its safety hold.
 if current_link.operation='LINK' and exists(select 1 from public.downtime_events where factory_id=factory and id=event and ended_at is null) then raise exception 'maintenance_active_stop';end if;
 select maintenance_request_id into rid from public.maintenance_schedules where factory_id=factory and id=schedule;
 v:=private.maintenance_append_stop(factory,event,schedule,approval_revision,operation,reason,request_id);
 insert into public.maintenance_commands(factory_id,request_id,actor_id,operation,payload,result_id) values(factory,request_id,auth.uid(),'stop:correct',keyed,rid);
 return v;
end$$;

-- One bounded, permission-scoped reader for the existing Floor/detail surfaces.
create function public.maintenance_stop_context(factory uuid,machine uuid default null,maintenance_request uuid default null,
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
 where s.factory_id=factory and r.work_center_id=machine and r.maintenance_kind='PLANNED' and r.status in ('OPEN','ASSIGNED','IN_PROGRESS')
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

revoke all on function private.maintenance_stop_immutable(),private.maintenance_active_stop(uuid,uuid),
 private.maintenance_stop_schedule_guard(),private.maintenance_stop_request_guard(),private.maintenance_append_stop(uuid,uuid,uuid,integer,text,text,uuid) from public,anon,authenticated;
revoke all on function public.stop_machine_for_maintenance(uuid,uuid,text,uuid,text,text,uuid,integer,integer,uuid),
 public.correct_maintenance_stop(uuid,uuid,uuid,integer,text,text,integer,uuid),public.maintenance_stop_context(uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.stop_machine_for_maintenance(uuid,uuid,text,uuid,text,text,uuid,integer,integer,uuid),
 public.correct_maintenance_stop(uuid,uuid,uuid,integer,text,text,integer,uuid),public.maintenance_stop_context(uuid,uuid,uuid,integer) to authenticated;
