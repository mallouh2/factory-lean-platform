-- Maintenance is a response record; it never changes machine, stop, transfer or plan truth.
insert into public.permissions(module,action) values
 ('maintenance','view'),('maintenance','create'),('maintenance','edit') on conflict do nothing;

create sequence private.maintenance_reference_seq;
create table public.maintenance_requests (
 id uuid primary key default gen_random_uuid(),
 factory_id uuid not null references public.factories,
 code text not null default ('MR-'||lpad(nextval('private.maintenance_reference_seq')::text,7,'0')) unique,
 work_center_id uuid not null,line_id uuid,downtime_id uuid,
 title text not null check(length(btrim(title)) between 1 and 200),
 description text not null default '' check(length(description)<=4000),
 priority text not null check(priority in ('LOW','NORMAL','HIGH','URGENT')),
 source text not null check(source in ('MANUAL','DOWNTIME')),
 requested_by uuid not null references auth.users,requested_by_name text not null,
 requested_at timestamptz not null default clock_timestamp(),
 assigned_to uuid,assigned_at timestamptz,assigned_by uuid references auth.users,
 status text not null default 'OPEN' check(status in ('OPEN','ASSIGNED','IN_PROGRESS','COMPLETED','VERIFIED','CANCELLED')),
 started_at timestamptz,started_by uuid references auth.users,
 completed_at timestamptz,completed_by uuid references auth.users,
 work_note text not null default '' check(length(work_note)<=4000),
 verified_at timestamptz,verified_by uuid references auth.users,
 verification_note text not null default '' check(length(verification_note)<=4000),
 verification_result text check(verification_result in ('RESOLVED','REWORK_REQUIRED')),
 checked_at timestamptz,checked_by uuid references auth.users,
 cancelled_at timestamptz,cancelled_by uuid references auth.users,
 cancellation_note text not null default '' check(length(cancellation_note)<=4000),
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 revision integer not null default 1,
 unique(factory_id,id),
 foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),
 foreign key(factory_id,line_id) references public.production_lines(factory_id,id),
 foreign key(factory_id,downtime_id) references public.downtime_events(factory_id,id),
 foreign key(factory_id,assigned_to) references public.memberships(factory_id,user_id),
 check((source='MANUAL' and downtime_id is null) or (source='DOWNTIME' and downtime_id is not null)),
 check((assigned_to is null)=(assigned_at is null)),
 check(status<>'OPEN' or assigned_to is null),
 check(status not in ('ASSIGNED','IN_PROGRESS','COMPLETED','VERIFIED') or assigned_to is not null),
 check(status not in ('IN_PROGRESS','COMPLETED','VERIFIED') or started_at is not null),
 check(status not in ('COMPLETED','VERIFIED') or (completed_at is not null and completed_by is not null and length(btrim(work_note))>0)),
 check((status='VERIFIED')=(verified_at is not null)),
 check(status<>'VERIFIED' or (verified_by is not null and verified_by<>assigned_to and verified_by<>completed_by
   and verification_result='RESOLVED' and length(btrim(verification_note))>0))
);
create unique index maintenance_active_downtime on public.maintenance_requests(factory_id,downtime_id)
 where downtime_id is not null and status not in ('VERIFIED','CANCELLED');
create index maintenance_factory_time on public.maintenance_requests(factory_id,requested_at desc,id);
create index maintenance_machine_active on public.maintenance_requests(factory_id,work_center_id,requested_at desc)
 where status not in ('VERIFIED','CANCELLED');
create index maintenance_assignee on public.maintenance_requests(factory_id,assigned_to,status,requested_at desc);
create index maintenance_line on public.maintenance_requests(factory_id,line_id);
create table public.maintenance_commands (
 factory_id uuid not null references public.factories,request_id uuid not null,actor_id uuid not null references auth.users,
 operation text not null,payload jsonb not null,result_id uuid not null,
 created_at timestamptz not null default clock_timestamp(),primary key(factory_id,request_id),
 foreign key(factory_id,result_id) references public.maintenance_requests(factory_id,id)
);
alter table public.maintenance_requests enable row level security;
alter table public.maintenance_commands enable row level security;
create function private.maintenance_member(f uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.has_permission(f,'factory','view') and exists(select 1 from public.memberships
  where factory_id=f and user_id=auth.uid() and status='approved');
$$;
create function private.maintenance_visible(f uuid,assignee uuid,requester uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select private.has_permission(f,'factory','view') and
  (private.has_permission(f,'maintenance','view') or private.has_permission(f,'maintenance','edit')
   or (private.maintenance_member(f) and (assignee=auth.uid() or requester=auth.uid())));
$$;
create policy maintenance_read on public.maintenance_requests for select to authenticated
 using(private.maintenance_visible(factory_id,assigned_to,requested_by));
grant select on public.maintenance_requests to authenticated;
revoke all on public.maintenance_commands from anon,authenticated;
revoke insert,update,delete,truncate on public.maintenance_requests from anon,authenticated;
create trigger audit_maintenance after insert or update or delete on public.maintenance_requests
 for each row execute function private.audit_change();
create function private.maintenance_stamp() returns trigger language plpgsql set search_path='' as $$begin
 new.updated_at:=clock_timestamp();new.revision:=old.revision+1;return new;
end$$;
create trigger maintenance_stamp before update on public.maintenance_requests
 for each row execute function private.maintenance_stamp();
revoke all on function private.maintenance_stamp() from public,anon,authenticated;

create function public.create_maintenance_request(factory uuid,payload jsonb,request_id uuid) returns uuid
 language plpgsql security definer set search_path='' as $$
declare m public.work_centers;d public.downtime_events;old public.maintenance_commands;
 result uuid;person uuid;stamp timestamptz;requester text;src text;line uuid;
begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'maintenance','create');
 if request_id is null or jsonb_typeof(payload) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(payload) k where k not in
   ('work_center_id','downtime_id','title','description','priority','assigned_to','separate_problem'))
 then raise exception 'maintenance_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(factory::text||':structure',0));
 select * into old from public.maintenance_commands c where c.factory_id=factory and c.request_id=create_maintenance_request.request_id;
 if found then
  if old.actor_id<>auth.uid() or old.operation<>'create' or old.payload<>payload then raise exception 'request_conflict';end if;
  return old.result_id;
 end if;
 select * into m from public.work_centers where factory_id=factory and id=(payload->>'work_center_id')::uuid and not archived;
 if not found then raise exception 'maintenance_machine';end if;
 src:='MANUAL';line:=m.line_id;
 if nullif(payload->>'downtime_id','') is not null then
  perform private.require_permission(factory,'downtime','view');
  select * into d from public.downtime_events where factory_id=factory and id=(payload->>'downtime_id')::uuid;
  if not found or d.work_center_id<>m.id then raise exception 'maintenance_downtime';end if;
  src:='DOWNTIME';line:=d.line_id;
  select id into result from public.maintenance_requests r where r.factory_id=factory and r.downtime_id=d.id
   and r.status not in ('VERIFIED','CANCELLED');
 end if;
 if result is null then
  if coalesce(length(btrim(payload->>'title')),0) not between 1 and 200
   or length(coalesce(payload->>'description',''))>4000
   or coalesce(payload->>'priority','') not in ('LOW','NORMAL','HIGH','URGENT')
   then raise exception 'maintenance_invalid';end if;
  if src='MANUAL' and exists(select 1 from public.maintenance_requests r where r.factory_id=factory
    and r.work_center_id=m.id and r.status not in ('VERIFIED','CANCELLED'))
    and coalesce(payload->>'separate_problem','false')<>'true' then raise exception 'maintenance_existing';end if;
  person:=nullif(payload->>'assigned_to','')::uuid;
  if person is not null then
   perform private.require_permission(factory,'maintenance','edit');
   if not exists(select 1 from public.memberships where factory_id=factory and user_id=person and status='approved')
    then raise exception 'maintenance_assignee';end if;
  end if;
  select display_name into requester from public.memberships where factory_id=factory and user_id=auth.uid() and status='approved';
  if requester is null then raise exception 'permission_denied' using errcode='42501';end if;
  stamp:=clock_timestamp();
  insert into public.maintenance_requests(factory_id,work_center_id,line_id,downtime_id,title,description,priority,source,
   requested_by,requested_by_name,requested_at,assigned_to,assigned_at,assigned_by,status,created_at,updated_at)
  values(factory,m.id,line,d.id,btrim(payload->>'title'),coalesce(payload->>'description',''),payload->>'priority',src,
   auth.uid(),requester,stamp,person,case when person is not null then stamp end,case when person is not null then auth.uid() end,
   case when person is null then 'OPEN' else 'ASSIGNED' end,stamp,stamp) returning id into result;
 end if;
 insert into public.maintenance_commands values(factory,request_id,auth.uid(),'create',payload,result,clock_timestamp());
 return result;
end$$;

create function public.change_maintenance_request(factory uuid,maintenance_request uuid,operation text,
 payload jsonb,expected_revision integer,request_id uuid) returns uuid
 language plpgsql security definer set search_path='' as $$
declare r public.maintenance_requests;old public.maintenance_commands;stamp timestamptz;person uuid;manager boolean;keyed jsonb;
begin
 perform private.require_permission(factory,'factory','view');
 if request_id is null or jsonb_typeof(payload) is distinct from 'object' then raise exception 'maintenance_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(factory::text||':structure',0));
 select * into r from public.maintenance_requests where factory_id=factory and id=maintenance_request for update;
 if not found then raise exception 'maintenance_missing' using errcode='P0002';end if;
 manager:=private.has_permission(factory,'maintenance','edit');
 if not manager and not (private.maintenance_member(factory) and r.assigned_to=auth.uid()
   and operation in ('start','note','complete')) then raise exception 'permission_denied' using errcode='42501';end if;
 keyed:=jsonb_build_object('id',maintenance_request,'revision',expected_revision,'payload',payload);
 select * into old from public.maintenance_commands c where c.factory_id=factory and c.request_id=change_maintenance_request.request_id;
 if found then
  if old.actor_id<>auth.uid() or old.operation<>operation or old.payload<>keyed then raise exception 'request_conflict';end if;
  return old.result_id;
 end if;
 if r.revision is distinct from expected_revision then raise exception 'maintenance_conflict';end if;
 if r.status in ('VERIFIED','CANCELLED') then raise exception 'maintenance_state';end if;
 stamp:=clock_timestamp();
 if operation='assign' then
  if r.status not in ('OPEN','ASSIGNED','IN_PROGRESS') or
   exists(select 1 from jsonb_object_keys(payload) k where k<>'assigned_to') then raise exception 'maintenance_state';end if;
  person:=nullif(payload->>'assigned_to','')::uuid;
  if person is null or not exists(select 1 from public.memberships where factory_id=factory and user_id=person and status='approved')
   then raise exception 'maintenance_assignee';end if;
  update public.maintenance_requests set assigned_to=person,assigned_at=stamp,assigned_by=auth.uid(),
   status=case when r.status='OPEN' then 'ASSIGNED' else r.status end where id=r.id;
 elsif operation='priority' then
  if coalesce(payload->>'priority','') not in ('LOW','NORMAL','HIGH','URGENT') or
   exists(select 1 from jsonb_object_keys(payload) k where k<>'priority') then raise exception 'maintenance_invalid';end if;
  update public.maintenance_requests set priority=payload->>'priority' where id=r.id;
 elsif operation='start' then
  if r.status<>'ASSIGNED' or payload<>'{}'::jsonb then raise exception 'maintenance_state';end if;
  update public.maintenance_requests set status='IN_PROGRESS',started_at=stamp,started_by=auth.uid() where id=r.id;
 elsif operation in ('note','complete') then
  if r.status<>'IN_PROGRESS' then raise exception 'maintenance_state';end if;
  if coalesce(length(btrim(payload->>'work_note')),0) not between 1 and 4000 or
   exists(select 1 from jsonb_object_keys(payload) k where k<>'work_note') then raise exception 'maintenance_note';end if;
  update public.maintenance_requests set work_note=btrim(payload->>'work_note'),
   status=case when operation='complete' then 'COMPLETED' else status end,
   completed_at=case when operation='complete' then stamp else completed_at end,
   completed_by=case when operation='complete' then auth.uid() else completed_by end where id=r.id;
 elsif operation='verify' then
  if r.status<>'COMPLETED' then raise exception 'maintenance_state';end if;
  if auth.uid() in (r.assigned_to,r.completed_by) then raise exception 'maintenance_independent_verifier';end if;
  if coalesce(payload->>'result','') not in ('RESOLVED','REWORK_REQUIRED') or
   coalesce(length(btrim(payload->>'verification_note')),0) not between 1 and 4000 or
   exists(select 1 from jsonb_object_keys(payload) k where k not in ('result','verification_note'))
   then raise exception 'maintenance_note';end if;
  update public.maintenance_requests set verification_result=payload->>'result',verification_note=btrim(payload->>'verification_note'),
   checked_at=stamp,checked_by=auth.uid(),
   status=case when payload->>'result'='RESOLVED' then 'VERIFIED' else 'IN_PROGRESS' end,
   verified_at=case when payload->>'result'='RESOLVED' then stamp end,
   verified_by=case when payload->>'result'='RESOLVED' then auth.uid() end,
   completed_at=case when payload->>'result'='RESOLVED' then completed_at end,
   completed_by=case when payload->>'result'='RESOLVED' then completed_by end where id=r.id;
 elsif operation='cancel' then
  if coalesce(length(btrim(payload->>'cancellation_note')),0) not between 1 and 4000 or
   exists(select 1 from jsonb_object_keys(payload) k where k<>'cancellation_note') then raise exception 'maintenance_note';end if;
  update public.maintenance_requests set status='CANCELLED',cancelled_at=stamp,cancelled_by=auth.uid(),
   cancellation_note=btrim(payload->>'cancellation_note') where id=r.id;
 else raise exception 'maintenance_invalid';end if;
 -- The BEFORE stamp trigger supplies revision/time in the same audited update.
 insert into public.maintenance_commands values(factory,request_id,auth.uid(),operation,keyed,r.id,stamp);
 return r.id;
end$$;

create function public.maintenance_page(factory uuid,filters jsonb default '{}',page integer default 1,
 selected uuid default null,history_page integer default 1) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;total integer;counts jsonb;detail jsonb;hist jsonb;hist_count integer;options jsonb;wide boolean;allowed boolean;
 machine uuid;line uuid;person uuid;since_date date;until_date date;zone text;
begin
 perform private.require_permission(factory,'factory','view');
 wide:=private.has_permission(factory,'maintenance','view') or private.has_permission(factory,'maintenance','edit');
 allowed:=wide or private.has_permission(factory,'maintenance','create') or private.maintenance_member(factory);
 if not allowed then raise exception 'permission_denied' using errcode='42501';end if;
 if page not between 1 and 1000000 or history_page not between 1 and 1000000 or jsonb_typeof(filters) is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(filters) k where k not in ('status','priority','machine','line','assignee','source','since','until','mine'))
  or coalesce(filters->>'status','ACTIVE') not in ('ACTIVE','ALL','OPEN','ASSIGNED','IN_PROGRESS','COMPLETED','VERIFIED','CANCELLED')
  or coalesce(filters->>'priority','ALL') not in ('ALL','LOW','NORMAL','HIGH','URGENT')
  or coalesce(filters->>'source','ALL') not in ('ALL','MANUAL','DOWNTIME') then raise exception 'maintenance_invalid' using errcode='22023';end if;
 machine:=nullif(filters->>'machine','')::uuid;line:=nullif(filters->>'line','')::uuid;person:=nullif(filters->>'assignee','')::uuid;
 since_date:=nullif(filters->>'since','')::date;until_date:=nullif(filters->>'until','')::date;
 select timezone into zone from public.factories where id=factory;
 with scoped as (select r.* from public.maintenance_requests r where r.factory_id=factory
  and (wide or private.maintenance_visible(r.factory_id,r.assigned_to,r.requested_by))
  and (coalesce(filters->>'mine','false')<>'true' or r.assigned_to=auth.uid())
  and (machine is null or r.work_center_id=machine) and (line is null or r.line_id=line)
  and (person is null or r.assigned_to=person)
  and (coalesce(filters->>'priority','ALL')='ALL' or r.priority=filters->>'priority')
  and (coalesce(filters->>'source','ALL')='ALL' or r.source=filters->>'source')
  and (since_date is null or r.requested_at>=since_date::timestamp at time zone zone)
  and (until_date is null or r.requested_at<(until_date+1)::timestamp at time zone zone)),
 matched as(select * from scoped r where coalesce(filters->>'status','ACTIVE')='ALL'
  or (coalesce(filters->>'status','ACTIVE')='ACTIVE' and r.status not in ('VERIFIED','CANCELLED')) or r.status=filters->>'status'),
 paged as(select r.*,w.code machine_code,w.name machine_name,w.name_ar machine_name_ar,l.name line_name,l.name_ar line_name_ar,
  a.display_name assignee_name from matched r join public.work_centers w on w.id=r.work_center_id
  left join public.production_lines l on l.id=r.line_id left join public.memberships a on a.factory_id=r.factory_id and a.user_id=r.assigned_to
  order by r.requested_at desc,r.id limit 25 offset (page-1)*25)
 select (select coalesce(jsonb_agg(to_jsonb(x) order by x.requested_at desc,x.id),'[]') from paged x),
  (select count(*) from matched),(select coalesce(jsonb_object_agg(status,n),'{}') from(select status,count(*) n from scoped group by status)x)
 into rows,total,counts;
 if selected is not null then
  select to_jsonb(r)||jsonb_build_object('machine_name',w.name,'machine_name_ar',w.name_ar,'machine_code',w.code,
   'line_name',l.name,'line_name_ar',l.name_ar,'assignee_name',a.display_name,'completer_name',c.display_name,'verifier_name',v.display_name,
   'checker_name',ch.display_name,'downtime',case when private.has_permission(factory,'downtime','view') then to_jsonb(d)||jsonb_build_object(
    'reason_name',dr.name,'reason_name_ar',dr.name_ar,'approved_cause_name',ac.name,'approved_cause_name_ar',ac.name_ar) end,
   'saved_loss',case when private.has_permission(factory,'downtime','view') then e.result end)
  into detail from public.maintenance_requests r join public.work_centers w on w.id=r.work_center_id
  left join public.production_lines l on l.id=r.line_id left join public.memberships a on a.factory_id=r.factory_id and a.user_id=r.assigned_to
  left join public.memberships c on c.factory_id=r.factory_id and c.user_id=r.completed_by
  left join public.memberships v on v.factory_id=r.factory_id and v.user_id=r.verified_by
  left join public.memberships ch on ch.factory_id=r.factory_id and ch.user_id=r.checked_by
  left join public.downtime_events d on d.factory_id=r.factory_id and d.id=r.downtime_id
  left join public.downtime_reasons dr on dr.id=d.reason_id left join public.downtime_reasons ac on ac.id=d.approved_cause_id
  left join public.production_loss_estimates e on e.factory_id=r.factory_id and e.event_id=r.downtime_id
  where r.factory_id=factory and r.id=selected and private.maintenance_visible(r.factory_id,r.assigned_to,r.requested_by);
  if detail is null then raise exception 'maintenance_missing' using errcode='P0002';end if;
  select count(*) into hist_count from public.audit_logs where factory_id=factory and entity='maintenance_requests' and entity_id=selected;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') into hist from
   (select h.id,h.action,h.actor_id,a.display_name actor_name,h.created_at,h.old_data,h.new_data from public.audit_logs h
    left join public.memberships a on a.factory_id=h.factory_id and a.user_id=h.actor_id
    where h.factory_id=factory and h.entity='maintenance_requests' and h.entity_id=selected
    order by h.created_at desc,h.id limit 25 offset (history_page-1)*25)x;
 end if;
 -- Small configuration choices, scoped here so assigned staff need no Employees admin permission.
 select jsonb_build_object('machines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from
  (select id,code,name,name_ar from public.work_centers where factory_id=factory and not archived order by code limit 500)x),
  'lines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select id,name,name_ar from public.production_lines where factory_id=factory and not archived order by name limit 500)x),
  'people',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select user_id id,display_name name from public.memberships where factory_id=factory and status='approved'
   and (wide or user_id=auth.uid()) order by display_name limit 500)x)) into options;
 return jsonb_build_object('rows',rows,'total',total,'counts',counts,'detail',detail,'history',coalesce(hist,'[]'),
  'history_total',coalesce(hist_count,0),'options',options,'wide',wide);
end$$;

-- Compact, per-machine operational context, loaded only when a drawer/event is inspected.
create function public.maintenance_machine_context(factory uuid,machine uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$declare rows jsonb;total integer;begin
 perform private.require_permission(factory,'factory','view');
 if not (private.has_permission(factory,'maintenance','view') or private.has_permission(factory,'maintenance','create')
  or private.has_permission(factory,'maintenance','edit') or private.maintenance_member(factory)) then
  raise exception 'permission_denied' using errcode='42501';end if;
 if not exists(select 1 from public.work_centers where factory_id=factory and id=machine) then
  raise exception 'maintenance_machine' using errcode='22023';end if;
 select count(*) into total from public.maintenance_requests r where r.factory_id=factory and r.work_center_id=machine
  and r.status not in ('VERIFIED','CANCELLED') and (private.maintenance_visible(factory,r.assigned_to,r.requested_by)
   or private.has_permission(factory,'maintenance','create'));
 select coalesce(jsonb_agg(to_jsonb(x) order by requested_at desc,id),'[]') into rows from
  (select id,code,status,downtime_id,requested_at,private.maintenance_visible(factory,assigned_to,requested_by) can_open
   from public.maintenance_requests r where r.factory_id=factory and r.work_center_id=machine
   and r.status not in ('VERIFIED','CANCELLED') and (private.maintenance_visible(factory,r.assigned_to,r.requested_by)
    or private.has_permission(factory,'maintenance','create')) order by requested_at desc,id limit 10)x;
 return jsonb_build_object('rows',rows,'total',total);
end$$;

create function public.maintenance_downtime_context(factory uuid,event uuid) returns jsonb
 language plpgsql stable security invoker set search_path='' as $$declare result jsonb;begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'downtime','view');
 select jsonb_build_object('event',to_jsonb(d),'machine',to_jsonb(m),'line',to_jsonb(l),
  'reason',to_jsonb(r),'approved_cause',to_jsonb(c)) into result from public.downtime_events d
  join public.work_centers m on m.factory_id=d.factory_id and m.id=d.work_center_id
  left join public.production_lines l on l.factory_id=d.factory_id and l.id=d.line_id
  left join public.downtime_reasons r on r.factory_id=d.factory_id and r.id=d.reason_id
  left join public.downtime_reasons c on c.factory_id=d.factory_id and c.id=d.approved_cause_id
  where d.factory_id=factory and d.id=event;
 if result is null then raise exception 'maintenance_missing' using errcode='P0002';end if;
 return result;
end$$;
revoke all on function public.maintenance_downtime_context(uuid,uuid) from public,anon;
grant execute on function public.maintenance_downtime_context(uuid,uuid) to authenticated;
revoke all on sequence private.maintenance_reference_seq from public,anon,authenticated;
revoke all on function private.maintenance_member(uuid),private.maintenance_visible(uuid,uuid,uuid) from public,anon;
grant execute on function private.maintenance_member(uuid),private.maintenance_visible(uuid,uuid,uuid) to authenticated;
revoke all on function public.create_maintenance_request(uuid,jsonb,uuid),
 public.change_maintenance_request(uuid,uuid,text,jsonb,integer,uuid),public.maintenance_page(uuid,jsonb,integer,uuid,integer),
 public.maintenance_machine_context(uuid,uuid) from public,anon;
grant execute on function public.create_maintenance_request(uuid,jsonb,uuid),
 public.change_maintenance_request(uuid,uuid,text,jsonb,integer,uuid),public.maintenance_page(uuid,jsonb,integer,uuid,integer),
 public.maintenance_machine_context(uuid,uuid) to authenticated;
