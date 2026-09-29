-- The seven current categories remain in the existing reason table. Historic
-- legacy rows stay in place for event, status and report references, but cannot
-- be selected for new capture or approval.
update public.downtime_reasons set requires_description=false
where parent_id is null and name='Other' and requires_description;

insert into public.downtime_reasons(factory_id,name,name_ar,requires_description)
select f.id,choice.name,choice.name_ar,false
from public.factories f cross join (values
  ('Mechanical Failure','عطل ميكانيكي'),
  ('Electrical Failure','عطل كهربائي'),
  ('Material Shortage','نقص مواد'),
  ('Quality Problem','مشكلة جودة'),
  ('Setup / Changeover','إعداد / تغيير المنتج'),
  ('Utilities','المرافق'),
  ('Other','أخرى')
) as choice(name,name_ar)
where not exists(select 1 from public.downtime_reasons r
  where r.factory_id=f.id and r.parent_id is null and r.name=choice.name);

create function private.current_downtime_reason(f uuid,reason uuid)
returns boolean language sql stable set search_path='' as $$
  select exists(select 1 from public.downtime_reasons r
    where r.factory_id=f and r.id=reason and r.parent_id is null
      and r.name in ('Mechanical Failure','Electrical Failure',
        'Material Shortage','Quality Problem','Setup / Changeover',
        'Utilities','Other'));
$$;
revoke all on function private.current_downtime_reason(uuid,uuid)
  from public,anon,authenticated;

-- Prevent the retired editable taxonomy from adding a second set of reasons.
-- Existing legacy rows remain readable for history and are never rewritten.
create function private.guard_current_downtime_catalog()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op in ('UPDATE','DELETE') then raise exception 'downtime_catalog_fixed'; end if;
  if new.parent_id is not null or new.name not in
    ('Mechanical Failure','Electrical Failure','Material Shortage',
     'Quality Problem','Setup / Changeover','Utilities','Other')
    or exists(select 1 from public.downtime_reasons r
      where r.factory_id=new.factory_id and r.parent_id is null
        and r.name=new.name) then
    raise exception 'downtime_catalog_fixed';
  end if;
  new.requires_description:=false;
  return new;
end;
$$;
create trigger guard_current_downtime_catalog
  before insert or update or delete on public.downtime_reasons
  for each row execute function private.guard_current_downtime_catalog();
revoke all on function private.guard_current_downtime_catalog()
  from public,anon,authenticated;

-- Future factories receive only the six base categories here; the existing
-- factory-insert trigger creates Utilities as the seventh category.
create or replace function private.create_factory(n text,tz text,industry text)
returns uuid language plpgsql security definer set search_path='' as $$
declare f uuid; r uuid; v text;
begin
  if auth.uid() is null or not exists(select 1 from auth.users
    where id=auth.uid() and email_confirmed_at is not null) then
    raise exception 'verify_email'; end if;
  if not private.is_platform_admin() and exists(select 1 from public.memberships
    where user_id=auth.uid()) then raise exception 'already_joined'; end if;
  if not exists(select 1 from pg_timezone_names where name=tz) then
    raise exception 'invalid_timezone'; end if;
  insert into public.factories(name,timezone,industry,created_by)
    values(n,tz,industry,auth.uid()) returning id into f;
  insert into private.join_codes values(f,
    'FAC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)));
  foreach v in array array['Factory Owner','Factory Manager',
    'Production Engineer','Planning Engineer','Warehouse Manager',
    'Sales Employee','Quality Engineer','Maintenance Engineer',
    'Safety Officer','Production Supervisor','Technician / Operator',
    'Platform Support Engineer','Custom Role'] loop
    insert into public.roles(factory_id,name) values(f,v) returning id into r;
    if v='Factory Owner' and not private.is_platform_admin() then
      insert into public.memberships(factory_id,user_id,display_name,role_id,is_owner,status)
      values(f,auth.uid(),split_part((select email from auth.users
        where id=auth.uid()),'@',1),r,true,'approved'); end if;
    if v='Factory Manager' then
      insert into public.role_permissions select f,r,module,action
      from public.permissions where module not in ('roles','support');
    elsif v in ('Production Engineer','Production Supervisor') then
      insert into public.role_permissions select f,r,module,action
      from public.permissions where (action='view' and module in
        ('dashboard','factory','lines','centers','orders','downtime','reports','employees'))
        or (action='edit' and module in ('centers','orders','downtime'));
    elsif v='Technician / Operator' then
      insert into public.role_permissions select f,r,module,action
      from public.permissions where (action='view' and module in
        ('dashboard','factory','lines','centers','orders','downtime'))
        or (action='edit' and module='machine_status'); end if;
  end loop;
  insert into public.downtime_reasons(factory_id,name,name_ar,requires_description)
  select f,x.en,x.ar,false from (values
    ('Mechanical Failure','عطل ميكانيكي'),
    ('Electrical Failure','عطل كهربائي'),
    ('Material Shortage','نقص مواد'),
    ('Quality Problem','مشكلة جودة'),
    ('Setup / Changeover','إعداد / تغيير المنتج'),
    ('Other','أخرى')) x(en,ar);
  perform private.seed_default_work_center_categories(f);
  if private.is_platform_admin() then perform private.open_platform_factory(f); end if;
  return f;
end;
$$;

-- A live physical stop or transition into any downtime status cannot create
-- an unclassified event. Notes are always optional; subreason taxonomy is
-- retired for new live stops. The locked transition timestamp stays shared.
create or replace function private.change_status(f uuid,w uuid,s text,reason uuid,
  sub_reason uuid,n text,eta timestamptz,responsible uuid,alternative uuid,
  transferred boolean)
returns void language plpgsql security definer set search_path='' as $$
declare old_s text; down boolean; transition_time timestamptz;
begin
  if transferred then raise exception 'use_transfer_command'; end if;
  if not private.has_permission(f,'centers','edit') then
    perform private.require_permission(f,'machine_status','edit'); end if;
  if length(coalesce(n,''))>2000 then raise exception 'invalid_notes'; end if;
  if responsible is not null and not exists(select 1 from public.memberships
    where id=responsible and factory_id=f and status='approved') then
    raise exception 'invalid_responsible'; end if;
  if alternative=w or (alternative is not null and not exists(select 1
    from public.work_centers where id=alternative and factory_id=f and not archived)) then
    raise exception 'invalid_alternative'; end if;
  select status into old_s from public.work_centers
    where id=w and factory_id=f and not archived for update;
  if not found then raise exception 'not_found'; end if;
  if old_s=s then raise exception 'status_unchanged'; end if;
  select is_downtime into down from public.machine_statuses where code=s;
  if not found then raise exception 'invalid_status'; end if;
  transition_time:=clock_timestamp();
  if down then
    if not private.current_downtime_reason(f,reason) then
      raise exception 'reason_required'; end if;
    if sub_reason is not null then raise exception 'invalid_sub_reason'; end if;
    if eta is not null and eta<transition_time then
      raise exception 'invalid_restart_time'; end if;
  end if;
  update public.downtime_events set ended_at=transition_time
    where factory_id=f and work_center_id=w and ended_at is null;
  insert into public.status_events(factory_id,work_center_id,old_status,
    new_status,reason_id,notes,created_at,created_by)
    values(f,w,old_s,s,reason,coalesce(n,''),transition_time,auth.uid());
  if down then
    insert into public.downtime_events(factory_id,work_center_id,reason_id,
      sub_reason_id,notes,started_at,expected_restart,responsible_id,
      alternative_id,transferred,created_by,entered_by)
      values(f,w,reason,null,coalesce(n,''),transition_time,eta,
        responsible,alternative,false,auth.uid(),auth.uid());
  end if;
  update public.work_centers set status=s,updated_at=transition_time,
    last_restart_time=case when s='running' then transition_time
      else last_restart_time end where id=w;
end;
$$;

create or replace function public.set_downtime_initial(factory uuid,event uuid,
  reason uuid,notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
begin
  if not private.has_permission(factory,'machine_status','edit')
    and not private.has_permission(factory,'centers','edit') then
    perform private.require_permission(factory,'downtime','edit'); end if;
  if not private.current_downtime_reason(factory,reason) then
    raise exception 'reason_required'; end if;
  if length(coalesce($4,''))>2000 then raise exception 'invalid_notes'; end if;
  update public.downtime_events set reason_id=reason,
    initial_note=coalesce($4,''),initial_entered_by=auth.uid(),
    initial_entered_at=clock_timestamp()
    where factory_id=factory and id=event and reason_id is null;
  if not found then raise exception 'downtime_initial_locked'; end if;
  return event;
end;
$$;

create or replace function public.approve_downtime_cause(factory uuid,event uuid,
  cause uuid,notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(factory,'downtime','edit');
  if not private.current_downtime_reason(factory,cause) then
    raise exception 'reason_required'; end if;
  if length(coalesce($4,''))>2000 then raise exception 'invalid_notes'; end if;
  update public.downtime_events set approved_cause_id=cause,
    approved_by=auth.uid(),approved_at=clock_timestamp(),
    engineering_note=coalesce($4,'')
    where factory_id=factory and id=event and ended_at is not null
      and approved_at is null;
  if not found then raise exception 'downtime_not_reviewable'; end if;
  return event;
end;
$$;

create or replace function public.record_missed_downtime(factory uuid,work_center uuid,
  started_at timestamptz,ended_at timestamptz,reason uuid default null,
  notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare new_id uuid;
begin
  perform private.require_permission(factory,'downtime','edit');
  if $3 is null or $4 is null or $4<=$3 or $4>clock_timestamp() then
    raise exception 'downtime_invalid_interval'; end if;
  if length(coalesce($6,''))>2000 then raise exception 'invalid_notes'; end if;
  if reason is not null and not private.current_downtime_reason(factory,reason) then
    raise exception 'reason_required'; end if;
  perform 1 from public.work_centers
    where factory_id=factory and id=work_center and not archived for update;
  if not found then raise exception 'not_found'; end if;
  if exists(select 1 from public.downtime_events existing
    where existing.factory_id=factory and existing.work_center_id=work_center
      and existing.started_at<$4
      and coalesce(existing.ended_at,'infinity'::timestamptz)>$3) then
    raise exception 'downtime_overlap'; end if;
  insert into public.downtime_events(factory_id,work_center_id,reason_id,
    started_at,ended_at,notes,initial_note,created_by,entered_by,retroactive)
    values(factory,work_center,reason,$3,$4,
      coalesce($6,''),coalesce($6,''),auth.uid(),auth.uid(),true)
    returning id into new_id;
  return new_id;
end;
$$;
