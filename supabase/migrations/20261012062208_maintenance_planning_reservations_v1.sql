-- Backend phase only. Confirmation is deliberately inactive until a separately
-- reviewed activation migration; no application caller can change this gate.
create table private.maintenance_planning_activation (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 reason text not null default 'Backend phase only: scheduling UI and actual-stop integration pending'
);
insert into private.maintenance_planning_activation default values;
revoke all on private.maintenance_planning_activation from public,anon,authenticated;

alter table public.maintenance_requests
 add column maintenance_kind text check(maintenance_kind in ('CORRECTIVE','PLANNED')),
 add column estimated_duration_minutes integer check(estimated_duration_minutes>0),
 add column preferred_start timestamptz,
 add column preferred_end timestamptz,
 add column planning_notes text not null default '' check(length(planning_notes)<=4000),
 add constraint maintenance_preferred_window check(preferred_start is null or preferred_end is null or preferred_end>preferred_start),
 add constraint maintenance_preferred_finite check((preferred_start is null or isfinite(preferred_start)) and (preferred_end is null or isfinite(preferred_end))),
 add constraint maintenance_planned_duration check(maintenance_kind is distinct from 'PLANNED' or estimated_duration_minutes is not null),
 add constraint maintenance_downtime_corrective check(source<>'DOWNTIME' or maintenance_kind is distinct from 'PLANNED');
-- NULL means historical/unclassified. Never infer preventive intent from MANUAL.
create table public.maintenance_schedules (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,
 maintenance_request_id uuid not null,revision integer not null default 1 check(revision>0),
 state text not null check(state in ('PROPOSED','CONFIRMED','INVALIDATED','UNSCHEDULED','RELEASED')),
 planned_start timestamptz not null,planned_end timestamptz not null,
 confirmed_by uuid references auth.users,confirmed_at timestamptz,
 hold_started_at timestamptz,released_at timestamptz,released_by uuid references auth.users,
 invalid_reason text,created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 unique(factory_id,id),unique(factory_id,maintenance_request_id),
 foreign key(factory_id,maintenance_request_id) references public.maintenance_requests(factory_id,id),
 check(planned_end>planned_start and isfinite(planned_start) and isfinite(planned_end)),
 check((confirmed_at is null)=(confirmed_by is null)),
 check(state not in ('CONFIRMED','INVALIDATED','RELEASED') or confirmed_at is not null),
 check((state='RELEASED')=(released_at is not null)),
 check((released_at is null)=(released_by is null)),
 check(hold_started_at is null or confirmed_at is not null)
);
create table public.maintenance_schedule_resources (
 factory_id uuid not null,schedule_id uuid not null,resource_kind text not null check(resource_kind in ('MACHINE','LINE')),
 machine_id uuid,line_id uuid,impact_reason text not null,evidence jsonb not null,
 foreign key(factory_id,schedule_id) references public.maintenance_schedules(factory_id,id),
 foreign key(factory_id,machine_id) references public.work_centers(factory_id,id),
 foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
 check((resource_kind='MACHINE' and machine_id is not null and line_id is null)
    or (resource_kind='LINE' and line_id is not null and machine_id is null))
);
create unique index maintenance_resource_machine on public.maintenance_schedule_resources(factory_id,schedule_id,machine_id) where machine_id is not null;
create unique index maintenance_resource_line on public.maintenance_schedule_resources(factory_id,schedule_id,line_id) where line_id is not null;
create index maintenance_machine_occupancy on public.maintenance_schedule_resources(factory_id,machine_id,schedule_id) where machine_id is not null;
create index maintenance_line_occupancy on public.maintenance_schedule_resources(factory_id,line_id,schedule_id) where line_id is not null;
create index maintenance_schedule_window on public.maintenance_schedules(factory_id,planned_start,planned_end) where state in ('CONFIRMED','INVALIDATED');
create table public.maintenance_schedule_revisions (
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,schedule_id uuid not null,
 revision integer not null,event text not null,reason text not null,
 before_data jsonb,after_data jsonb not null,resources jsonb not null,
 actor_id uuid references auth.users,actor_name text,changed_at timestamptz not null default clock_timestamp(),
 request_id uuid,unique(factory_id,schedule_id,revision),
 foreign key(factory_id,schedule_id) references public.maintenance_schedules(factory_id,id)
);
alter table public.maintenance_schedules enable row level security;
alter table public.maintenance_schedule_resources enable row level security;
alter table public.maintenance_schedule_revisions enable row level security;
revoke all on public.maintenance_schedules,public.maintenance_schedule_resources,public.maintenance_schedule_revisions from public,anon,authenticated;
create trigger audit_maintenance_schedule after insert or update on public.maintenance_schedules for each row execute function private.audit_change();

create function private.maintenance_planning_lock(f uuid) returns void language sql volatile security definer set search_path='' as $$
 select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
$$;
create function private.maintenance_machine_evidence(f uuid,w uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('machine',jsonb_build_object('id',m.id,'line',m.line_id,'category',m.category_id,
 'dependency',m.dependency_mode,'scope',m.impact_scope,'buffer',m.buffer_minutes,'position',m.position,'archived',m.archived,
 'line_archived',(select archived from public.production_lines where factory_id=f and id=m.line_id)),
 'capabilities',coalesce((select jsonb_agg(to_jsonb(c) order by c.product_id) from public.work_center_capabilities c where c.factory_id=f and c.work_center_id=w),'[]'),
 'alternatives',coalesce((select jsonb_agg(to_jsonb(a) order by a.alternative_id) from public.work_center_alternatives a where a.factory_id=f and a.work_center_id=w),'[]'))
 from public.work_centers m where m.factory_id=f and m.id=w;
$$;

-- One half-open conflict contract for production and maintenance. Holds and
-- invalidated approvals are open-ended: their planned end is not release truth.
create function private.maintenance_capacity_conflict(f uuid,l uuid,p uuid,w uuid,starts timestamptz,ends timestamptz,
 skip_schedule uuid default null,skip_item uuid default null,with_production boolean default true)
 returns jsonb language plpgsql stable security definer set search_path='' as $$
declare found_id uuid;begin
 if starts is null or ends is null or ends<=starts then return jsonb_build_object('reason','maintenance_unknown_window');end if;
 select s.id into found_id from public.maintenance_schedules s
 join public.maintenance_schedule_resources r on r.factory_id=s.factory_id and r.schedule_id=s.id
 left join public.work_centers m on m.factory_id=r.factory_id and m.id=r.machine_id
 where s.factory_id=f and s.id is distinct from skip_schedule and s.state in ('CONFIRMED','INVALIDATED')
 and least(s.planned_start,coalesce(s.hold_started_at,s.planned_start))<ends
 and (case when s.hold_started_at is not null or s.state='INVALIDATED' or s.planned_end<=clock_timestamp() then 'infinity'::timestamptz else s.planned_end end)>starts
 and ((l is not null and (r.line_id=l or m.line_id=l)) or (w is not null and r.machine_id=w)
 or (p is not null and r.machine_id in(select rs.work_center_id from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center'))
 or (l is not null and r.machine_id in(select t.alternative_id from public.production_transfers t join public.production_orders o on o.factory_id=t.factory_id and o.id=t.order_id where t.factory_id=f and t.ended_at is null and o.line_id=l)))
 order by s.planned_start,s.id limit 1;
 if found_id is not null then return jsonb_build_object('reason','maintenance_capacity_reserved','schedule',found_id);end if;
 if with_production then
 select o.id into found_id from public.production_orders o where o.factory_id=f and o.id is distinct from skip_item and o.status in ('planned','active')
 and ((l is not null and o.line_id=l) or (w is not null and (o.id in(select c.order_id from public.work_centers c where c.factory_id=f and c.id=w)
 or o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center'))))
 and (o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time
 or o.status='active' or (o.start_time<ends and o.expected_finish>starts)) order by o.id limit 1;
 if found_id is not null then return jsonb_build_object('reason','maintenance_production_conflict','item',found_id);end if;
 end if;
 return null;
end$$;
create function private.maintenance_assert_capacity(f uuid,l uuid,p uuid,w uuid,starts timestamptz,ends timestamptz,
 skip_schedule uuid default null,skip_item uuid default null,with_production boolean default true)
 returns void language plpgsql security definer set search_path='' as $$
declare issue jsonb;begin
 issue:=private.maintenance_capacity_conflict(f,l,p,w,starts,ends,skip_schedule,skip_item,with_production);
 if issue is not null then raise exception '%',issue->>'reason' using detail=issue::text;end if;
end$$;
create function private.maintenance_schedule_history(sid uuid,before_row jsonb,action text,note text,retry uuid default null)
 returns void language plpgsql security definer set search_path='' as $$
declare s public.maintenance_schedules;begin
 select * into s from public.maintenance_schedules where id=sid;
 insert into public.maintenance_schedule_revisions(factory_id,schedule_id,revision,event,reason,before_data,after_data,resources,actor_id,actor_name,request_id)
 select s.factory_id,s.id,s.revision,action,note,before_row,to_jsonb(s),
 coalesce((select jsonb_agg(to_jsonb(r) order by r.resource_kind,r.machine_id,r.line_id) from public.maintenance_schedule_resources r where r.schedule_id=s.id),'[]'),
 auth.uid(),(select display_name from public.memberships where factory_id=s.factory_id and user_id=auth.uid()),retry;
end$$;

-- Preserve the existing lifecycle implementation behind a private wrapper.
alter function public.create_maintenance_request(uuid,jsonb,uuid) rename to maintenance_create_base;
alter function public.maintenance_create_base(uuid,jsonb,uuid) set schema private;
-- The preserved function uses its former name to qualify request_id.
do $$begin
 execute replace(pg_get_functiondef('private.maintenance_create_base(uuid,jsonb,uuid)'::regprocedure),
 'create_maintenance_request.request_id','maintenance_create_base.request_id');
end$$;
revoke all on function private.maintenance_create_base(uuid,jsonb,uuid) from public,anon,authenticated;
create function public.create_maintenance_request(factory uuid,payload jsonb,request_id uuid) returns uuid
 language plpgsql security definer set search_path='' as $$
declare r uuid;old public.maintenance_commands;base jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','create');
 perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'maintenance','create');
 if jsonb_typeof(payload) is distinct from 'object' or request_id is null then raise exception 'maintenance_invalid';end if;
 base:=payload-array['maintenance_kind','estimated_duration_minutes','preferred_start','preferred_end','planning_notes'];
 if payload ? 'maintenance_kind' and coalesce(payload->>'maintenance_kind','') not in ('CORRECTIVE','PLANNED') then raise exception 'maintenance_invalid';end if;
 select * into old from public.maintenance_commands c where c.factory_id=factory and c.request_id=create_maintenance_request.request_id;
 if found then
 if old.actor_id<>auth.uid() or old.operation<>'create' or old.payload<>payload then raise exception 'request_conflict';end if;return old.result_id;
 end if;
 r:=private.maintenance_create_base(factory,base,request_id);
 -- An existing DOWNTIME request returned by duplicate detection is not edited.
 if payload ?| array['maintenance_kind','estimated_duration_minutes','preferred_start','preferred_end','planning_notes'] then
 if exists(select 1 from public.maintenance_commands c where c.factory_id=factory and c.result_id=r and c.request_id<>create_maintenance_request.request_id) then raise exception 'maintenance_existing';end if;
 update public.maintenance_requests set maintenance_kind=payload->>'maintenance_kind',
 estimated_duration_minutes=(payload->>'estimated_duration_minutes')::integer,
 preferred_start=(payload->>'preferred_start')::timestamptz,preferred_end=(payload->>'preferred_end')::timestamptz,
 planning_notes=coalesce(payload->>'planning_notes','') where id=r;
 end if;
 update public.maintenance_commands c set payload=create_maintenance_request.payload where c.factory_id=factory and c.request_id=create_maintenance_request.request_id;
 return r;
end$$;
revoke all on function public.create_maintenance_request(uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.create_maintenance_request(uuid,jsonb,uuid) to authenticated;

create function public.maintenance_planning_command(factory uuid,maintenance_request uuid,operation text,payload jsonb,
 expected_revision integer,request_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.maintenance_requests;s public.maintenance_schedules;m public.work_centers;old public.maintenance_commands;
 keyed jsonb;before_row jsonb;a timestamptz;b timestamptz;stamp timestamptz;sid uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='details' then perform private.require_permission(factory,'maintenance','edit');else
 perform private.require_permission(factory,'maintenance','view');perform private.require_permission(factory,'orders','edit');end if;
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' or operation not in ('details','propose','confirm','reschedule','unschedule') then raise exception 'maintenance_invalid';end if;
 perform private.maintenance_planning_lock(factory);
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
 if coalesce(s.revision,0) is distinct from expected_revision then raise exception 'maintenance_conflict';end if;
 if r.maintenance_kind is distinct from 'PLANNED' or r.status not in ('OPEN','ASSIGNED') or s.hold_started_at is not null then raise exception 'maintenance_state';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where k not in ('start','end','reason')) then raise exception 'maintenance_invalid';end if;
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
 select * into m from public.work_centers where factory_id=factory and id=r.work_center_id and not archived;
 if not found or m.category_id is null then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is null and m.dependency_mode<>'independent' then raise exception 'maintenance_configuration_unknown';end if;
 if m.line_id is not null and not exists(select 1 from public.production_lines where factory_id=factory and id=m.line_id and not archived) then raise exception 'maintenance_configuration_unknown';end if;
 if operation in ('confirm','reschedule') then
 if not (select enabled from private.maintenance_planning_activation where singleton) then raise exception 'maintenance_planning_inactive';end if;
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

-- Lifecycle hook: corrective requests remain completely unchanged. Planned
-- starts require a valid approval; completion alone never releases a hold.
create function private.maintenance_planned_lifecycle() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.maintenance_schedules;m public.work_centers;stamp timestamptz;before_row jsonb;begin
 if old.maintenance_kind is distinct from 'PLANNED' or old.status=new.status then return new;end if;
 perform private.maintenance_planning_lock(new.factory_id);
 select * into s from public.maintenance_schedules where factory_id=new.factory_id and maintenance_request_id=new.id for update;
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
create trigger maintenance_planned_lifecycle before update of status on public.maintenance_requests for each row execute function private.maintenance_planned_lifecycle();

-- Always obtain the structure lock before the production item/line row locks.
-- Existing Planning validation and immutable revision triggers remain intact.
alter function private.plan_product_item(uuid,uuid,uuid,timestamptz) rename to plan_product_item_without_maintenance;
create function private.plan_product_item(f uuid,item uuid,target_line uuid,planned_start timestamptz) returns uuid
 language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'orders','edit');perform private.maintenance_planning_lock(f);
 perform private.require_permission(f,'orders','edit');
 return private.plan_product_item_without_maintenance(f,item,target_line,planned_start);
end$$;
create function private.maintenance_production_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare finish_time timestamptz;minutes_required integer;m public.work_centers;begin
 perform private.maintenance_planning_lock(new.factory_id);
 if new.status in ('planned','active') and new.line_id is not null then
 perform private.maintenance_assert_capacity(new.factory_id,new.line_id,new.product_id,null,new.start_time,new.expected_finish,null,new.id,false);
 end if;
 if tg_op='UPDATE' and old.status<>'active' and new.status='active' then
 if private.maintenance_capacity_conflict(new.factory_id,new.line_id,new.product_id,null,new.actual_start,'infinity',null,new.id,false) is not null then
 select ceil(new.target_quantity/min(cap.rate)*60)+max(cap.setup_minutes) into minutes_required
 from public.work_centers c join public.work_center_capabilities cap on cap.factory_id=c.factory_id and cap.work_center_id=c.id
 where c.factory_id=new.factory_id and c.line_id=new.line_id and not c.archived and cap.product_id=new.product_id and cap.rate_unit=new.unit and cap.rate>0;
 -- Conservative intended window, never a claimed actual completion timestamp.
 if minutes_required is null then raise exception 'maintenance_execution_window_unknown';end if;
 finish_time:=private.finish_after_working_minutes(new.factory_id,new.actual_start,minutes_required);
 perform private.maintenance_assert_capacity(new.factory_id,new.line_id,new.product_id,null,new.actual_start,finish_time,null,new.id,false);
 end if;
 end if;
 return new;
end$$;
create trigger maintenance_production_guard before insert or update of line_id,product_id,start_time,expected_finish,status,actual_start on public.production_orders for each row execute function private.maintenance_production_guard();

-- Unsafe borrower assignment is checked without changing OPEN transfer truth.
create function private.maintenance_transfer_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare o public.production_orders;begin
 if new.ended_at is not null then return new;end if;
 perform private.maintenance_planning_lock(new.factory_id);
 select * into o from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 perform private.maintenance_assert_capacity(new.factory_id,o.line_id,o.product_id,new.alternative_id,clock_timestamp(),'infinity',null,o.id,false);
 return new;
end$$;
create trigger maintenance_transfer_guard before insert on public.production_transfers for each row execute function private.maintenance_transfer_guard();

create function private.maintenance_invalidate() returns trigger language plpgsql security definer set search_path='' as $$
declare f uuid;w uuid;l uuid;s public.maintenance_schedules;before_row jsonb;begin
 if tg_table_name='production_lines' then f:=new.factory_id;l:=new.id;
 if old.archived is not distinct from new.archived then return new;end if;
 elsif tg_table_name='work_centers' then f:=new.factory_id;w:=new.id;
 if (old.line_id,old.position,old.dependency_mode,old.impact_scope,old.buffer_minutes,old.category_id,old.archived) is not distinct from
 (new.line_id,new.position,new.dependency_mode,new.impact_scope,new.buffer_minutes,new.category_id,new.archived)
 and not (old.status is distinct from new.status and new.status='stopped' and exists(select 1 from public.downtime_events d where d.factory_id=new.factory_id and d.work_center_id=new.id and d.ended_at is null and d.stop_nature='unplanned')) then return new;end if;
 else
 if tg_op='DELETE' then f:=old.factory_id;w:=old.work_center_id;else f:=new.factory_id;w:=new.work_center_id;end if;
 end if;
 perform private.maintenance_planning_lock(f);
 for s in select ms.* from public.maintenance_schedules ms where ms.factory_id=f and ms.state='CONFIRMED'
 and exists(select 1 from public.maintenance_schedule_resources r where r.schedule_id=ms.id and (r.machine_id=w or r.line_id=l or r.line_id in(select line_id from public.work_centers where factory_id=f and id=w))) for update loop
 before_row:=to_jsonb(s);update public.maintenance_schedules set state='INVALIDATED',invalid_reason=tg_table_name||' changed',revision=revision+1,updated_at=clock_timestamp() where id=s.id;
 perform private.maintenance_schedule_history(s.id,before_row,'invalidate',tg_table_name||' configuration changed');
 end loop;
 if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger maintenance_invalidate_center after update of line_id,position,dependency_mode,impact_scope,buffer_minutes,category_id,archived,status on public.work_centers for each row execute function private.maintenance_invalidate();
create trigger maintenance_invalidate_capability after insert or update or delete on public.work_center_capabilities for each row execute function private.maintenance_invalidate();
create trigger maintenance_invalidate_alternative after insert or update or delete on public.work_center_alternatives for each row execute function private.maintenance_invalidate();
create trigger maintenance_invalidate_line after update of archived on public.production_lines for each row execute function private.maintenance_invalidate();

create function public.maintenance_planning_read(factory uuid,page integer default 1) returns jsonb
 language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'maintenance','view');
 if page not between 1 and 100000 then raise exception 'maintenance_invalid';end if;
 return jsonb_build_object('active',(select enabled from private.maintenance_planning_activation where singleton),
 'activation_reason',(select reason from private.maintenance_planning_activation where singleton),
 'total',(select count(*) from public.maintenance_schedules where factory_id=factory),
 'rows',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select s.*,r.code,r.work_center_id,
 coalesce((select jsonb_agg(to_jsonb(res)) from public.maintenance_schedule_resources res where res.schedule_id=s.id),'[]') resources,
 (s.state in ('CONFIRMED','INVALIDATED') and s.hold_started_at is null and clock_timestamp()>s.planned_end) missed_window,
 (s.hold_started_at is not null and s.state<>'RELEASED') actual_hold,
 (s.hold_started_at is not null and s.state<>'RELEASED' and clock_timestamp()>s.planned_end) overrun
 from public.maintenance_schedules s join public.maintenance_requests r on r.factory_id=s.factory_id and r.id=s.maintenance_request_id
 where s.factory_id=factory order by s.planned_start,s.id limit 50 offset (page-1)*50)x));
end$$;
revoke all on function public.maintenance_planning_read(uuid,integer) from public,anon,authenticated;
grant execute on function public.maintenance_planning_read(uuid,integer) to authenticated;

-- Entry-point wrappers acquire structure BEFORE their inherited row locks.
alter function private.configure_center_capabilities(uuid,uuid,jsonb) rename to maintenance_capabilities_base;
create function private.configure_center_capabilities(f uuid,w uuid,capabilities jsonb) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'centers','edit');perform private.maintenance_planning_lock(f);
 perform private.require_permission(f,'centers','edit');perform private.maintenance_capabilities_base(f,w,capabilities);
end$$;
alter function private.configure_center_alternatives(uuid,uuid,uuid[]) rename to maintenance_alternatives_base;
create function private.configure_center_alternatives(f uuid,w uuid,alternatives uuid[]) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'centers','edit');perform private.maintenance_planning_lock(f);
 perform private.require_permission(f,'centers','edit');perform private.maintenance_alternatives_base(f,w,alternatives);
end$$;
alter function private.save_record(uuid,text,uuid,jsonb) rename to maintenance_save_base;
create function private.save_record(f uuid,resource text,record_id uuid,p jsonb) returns uuid language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(f,'factory','view');perform private.maintenance_planning_lock(f);
 return private.maintenance_save_base(f,resource,record_id,p);
end$$;
alter function public.set_plan_lock(uuid,uuid,boolean) rename to maintenance_plan_lock_base;
alter function public.maintenance_plan_lock_base(uuid,uuid,boolean) set schema private;
create function public.set_plan_lock(factory uuid,item uuid,locked boolean) returns uuid language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'orders','edit');perform private.maintenance_planning_lock(factory);
 return private.maintenance_plan_lock_base(factory,item,locked);
end$$;
revoke all on function private.maintenance_capabilities_base(uuid,uuid,jsonb),private.maintenance_alternatives_base(uuid,uuid,uuid[]),
 private.maintenance_save_base(uuid,text,uuid,jsonb),private.maintenance_plan_lock_base(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function private.configure_center_capabilities(uuid,uuid,jsonb),private.configure_center_alternatives(uuid,uuid,uuid[]),
 private.save_record(uuid,text,uuid,jsonb),public.set_plan_lock(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function private.configure_center_capabilities(uuid,uuid,jsonb),private.configure_center_alternatives(uuid,uuid,uuid[]),
 private.save_record(uuid,text,uuid,jsonb),public.set_plan_lock(uuid,uuid,boolean) to authenticated;

alter function public.stop_machine(uuid,uuid,text,uuid,text,text) rename to maintenance_stop_base;
alter function public.maintenance_stop_base(uuid,uuid,text,uuid,text,text) set schema private;
create function public.stop_machine(factory uuid,work_center uuid,nature text,reason uuid,activity text,notes text default '') returns uuid language plpgsql security definer set search_path='' as $$begin
 if not private.has_permission(factory,'centers','edit') then perform private.require_permission(factory,'machine_status','edit');end if;
 perform private.maintenance_planning_lock(factory);
 return private.maintenance_stop_base(factory,work_center,nature,reason,activity,notes);
end$$;
alter function private.change_status(uuid,uuid,text,uuid,uuid,text,timestamptz,uuid,uuid,boolean) rename to maintenance_status_base;
create function private.change_status(f uuid,w uuid,s text,reason uuid,sub_reason uuid,n text,eta timestamptz,responsible uuid,alternative uuid,transferred boolean) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.has_permission(f,'centers','edit') then perform private.require_permission(f,'machine_status','edit');end if;
 perform private.maintenance_planning_lock(f);
 perform private.maintenance_status_base(f,w,s,reason,sub_reason,n,eta,responsible,alternative,transferred);
end$$;
revoke all on function private.maintenance_stop_base(uuid,uuid,text,uuid,text,text),private.maintenance_status_base(uuid,uuid,text,uuid,uuid,text,timestamptz,uuid,uuid,boolean),
 public.stop_machine(uuid,uuid,text,uuid,text,text),private.change_status(uuid,uuid,text,uuid,uuid,text,timestamptz,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.stop_machine(uuid,uuid,text,uuid,text,text),private.change_status(uuid,uuid,text,uuid,uuid,text,timestamptz,uuid,uuid,boolean) to authenticated;

create function private.maintenance_center_execution_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare o public.production_orders;begin
 if new.order_id is not null and (tg_op='INSERT' or old.order_id is distinct from new.order_id or (old.status<>'running' and new.status='running')) then
 select * into o from public.production_orders where factory_id=new.factory_id and id=new.order_id and status='active';
 if found then perform private.maintenance_assert_capacity(new.factory_id,o.line_id,o.product_id,new.id,clock_timestamp(),
 case when new.line_id is null then 'infinity'::timestamptz else clock_timestamp()+interval '1 second' end,null,o.id,false);end if;
 end if;return new;
end$$;
create trigger c_maintenance_center_execution_guard before insert or update on public.work_centers for each row execute function private.maintenance_center_execution_guard();
revoke all on function private.maintenance_center_execution_guard() from public,anon,authenticated;

-- WIP may be processed on a completed item's independent machine without a
-- new normal line start. Protect new output too; historical corrections are
-- not execution and deliberately remain outside this INSERT-only guard.
create function private.maintenance_recording_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;stamp timestamptz;begin
 perform private.maintenance_planning_lock(new.factory_id);stamp:=clock_timestamp();
 select product_id into p from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 perform private.maintenance_assert_capacity(new.factory_id,new.line_id,p,new.work_center_id,stamp,stamp+interval '1 microsecond',null,new.order_id,false);
 return new;
end$$;
create trigger maintenance_recording_guard before insert on public.production_entries for each row execute function private.maintenance_recording_guard();
revoke all on function private.maintenance_recording_guard() from public,anon,authenticated;
revoke all on function private.maintenance_planning_lock(uuid),private.maintenance_machine_evidence(uuid,uuid),
 private.maintenance_capacity_conflict(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,uuid,boolean),
 private.maintenance_assert_capacity(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,uuid,boolean),
 private.maintenance_schedule_history(uuid,jsonb,text,text,uuid),private.maintenance_planned_lifecycle(),
 private.plan_product_item_without_maintenance(uuid,uuid,uuid,timestamptz),private.plan_product_item(uuid,uuid,uuid,timestamptz),
 private.maintenance_production_guard(),private.maintenance_transfer_guard(),private.maintenance_invalidate() from public,anon,authenticated;
