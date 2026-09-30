-- Production Loss Impact V1. All existing events predate stop-nature capture;
-- preserve that uncertainty instead of recategorizing history as failures.
alter table public.downtime_events
  add column stop_nature text,
  add column planned_activity text,
  add column loss_model_version integer not null default 1;
update public.downtime_events set stop_nature='legacy_unknown';
alter table public.downtime_events alter column stop_nature set default 'unplanned';
alter table public.downtime_events alter column stop_nature set not null;
alter table public.downtime_events add constraint downtime_stop_nature_valid check (
  (stop_nature='planned' and reason_id is null and planned_activity in
    ('cleaning','changeover','preventive_maintenance','inspection',
     'planned_process','other')) or
  (stop_nature in ('unplanned','legacy_unknown') and planned_activity is null)
);
alter table public.downtime_events drop constraint downtime_initial_audit_pair;
alter table public.downtime_events add constraint downtime_initial_audit_pair check (
  (stop_nature='planned' and initial_entered_at is not null) or
  (stop_nature<>'planned' and
    ((reason_id is null and initial_entered_at is null and initial_entered_by is null)
      or (reason_id is not null and initial_entered_at is not null)))
);
alter table public.downtime_events drop constraint downtime_approval_audit_pair;
alter table public.downtime_events add constraint downtime_approval_audit_pair check (
  (approved_cause_id is null and approved_by is null and approved_at is null) or
  (stop_nature='planned' and approved_cause_id is null
    and approved_by is not null and approved_at is not null) or
  (stop_nature<>'planned' and approved_cause_id is not null
    and approved_by is not null and approved_at is not null)
);

create or replace function private.guard_downtime_capture()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='INSERT' then
    new.entered_by:=coalesce(new.entered_by,new.created_by);
    if new.retroactive and new.reason_id is null then
      new.stop_nature:='legacy_unknown';
    end if;
    if new.reason_id is not null or new.stop_nature='planned' then
      new.initial_entered_by:=coalesce(new.initial_entered_by,new.created_by);
      new.initial_entered_at:=coalesce(new.initial_entered_at,clock_timestamp());
      new.initial_note:=coalesce(nullif(new.initial_note,''),new.notes,'');
    end if;
    if new.retroactive and (new.entered_by is null or new.ended_at is null) then
      raise exception 'downtime_invalid_interval';
    end if;
    return new;
  end if;
  if (old.factory_id,old.work_center_id,old.started_at,old.retroactive,
      old.entered_by,old.stop_nature,old.planned_activity,old.loss_model_version)
    is distinct from
    (new.factory_id,new.work_center_id,new.started_at,new.retroactive,
      new.entered_by,new.stop_nature,new.planned_activity,new.loss_model_version)
    or (old.ended_at is not null and old.ended_at is distinct from new.ended_at) then
    raise exception 'downtime_immutable';
  end if;
  if old.reason_id is not null and
    (old.reason_id,old.initial_note,old.initial_entered_by,old.initial_entered_at)
      is distinct from
    (new.reason_id,new.initial_note,new.initial_entered_by,new.initial_entered_at) then
    raise exception 'downtime_initial_locked';
  end if;
  if old.stop_nature='planned' and
    (old.initial_note,old.initial_entered_by,old.initial_entered_at)
      is distinct from
    (new.initial_note,new.initial_entered_by,new.initial_entered_at) then
    raise exception 'downtime_initial_locked';
  end if;
  if old.approved_at is not null and
    (old.approved_cause_id,old.approved_by,old.approved_at,old.engineering_note)
      is distinct from
    (new.approved_cause_id,new.approved_by,new.approved_at,new.engineering_note) then
    raise exception 'downtime_approval_locked';
  end if;
  return new;
end;
$$;

-- The event's original classification is immutable. Corrections append a
-- separate engineer decision and do not rewrite the operator's observation.
create table public.downtime_classification_corrections (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references public.factories(id),
  event_id uuid not null,
  stop_nature text not null check(stop_nature in ('planned','unplanned')),
  reason_id uuid,
  planned_activity text,
  note text not null check(length(trim(note)) between 3 and 2000),
  corrected_by uuid not null references auth.users(id),
  corrected_at timestamptz not null default clock_timestamp(),
  foreign key(factory_id,event_id) references public.downtime_events(factory_id,id),
  foreign key(factory_id,reason_id) references public.downtime_reasons(factory_id,id),
  check ((stop_nature='unplanned' and reason_id is not null and planned_activity is null)
    or (stop_nature='planned' and reason_id is null and planned_activity in
      ('cleaning','changeover','preventive_maintenance','inspection',
       'planned_process','other')))
);
create index downtime_correction_latest on public.downtime_classification_corrections
  (event_id,corrected_at desc,id desc);
alter table public.downtime_classification_corrections enable row level security;
create policy read_authorized on public.downtime_classification_corrections
  for select to authenticated using(private.has_permission(factory_id,'downtime','view'));
grant select on public.downtime_classification_corrections to authenticated;

create function public.correct_downtime_classification(
  factory uuid,event uuid,nature text,reason uuid,activity text,note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
  perform private.require_permission(factory,'downtime','edit');
  if not exists(select 1 from public.downtime_events
    where factory_id=factory and id=event) then raise exception 'not_found'; end if;
  if nature='unplanned' then
    if activity is not null or not private.current_downtime_reason(factory,reason)
      then raise exception 'reason_required'; end if;
  elsif nature='planned' then
    if reason is not null or activity not in
      ('cleaning','changeover','preventive_maintenance','inspection',
       'planned_process','other') then raise exception 'invalid_planned_activity'; end if;
  else raise exception 'invalid_stop_nature'; end if;
  insert into public.downtime_classification_corrections
    (factory_id,event_id,stop_nature,reason_id,planned_activity,note,corrected_by)
  values(factory,event,nature,reason,activity,note,auth.uid()) returning id into result_id;
  return result_id;
end;
$$;
revoke all on function public.correct_downtime_classification(
  uuid,uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.correct_downtime_classification(
  uuid,uuid,text,uuid,text,text) to authenticated;

create function public.approve_planned_downtime(factory uuid,event uuid,
  notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(factory,'downtime','edit');
  if length(coalesce(notes,''))>2000 then raise exception 'invalid_notes'; end if;
  update public.downtime_events set approved_by=auth.uid(),
    approved_at=clock_timestamp(),engineering_note=coalesce(notes,'')
    where factory_id=factory and id=event and stop_nature='planned'
      and ended_at is not null and approved_at is null;
  if not found then raise exception 'downtime_not_reviewable'; end if;
  return event;
end;
$$;
revoke all on function public.approve_planned_downtime(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.approve_planned_downtime(uuid,uuid,text)
  to authenticated;

-- Engineer assumptions are distinct from physical machine configuration and
-- from the product-specific normal rate in work_center_capabilities.
create table public.production_loss_profiles (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references public.factories(id),
  work_center_id uuid not null,
  product_id uuid not null,
  can_defer boolean,
  scrap_expected boolean,
  shutdown_scrap_quantity numeric check(shutdown_scrap_quantity>=0),
  restart_scrap_quantity numeric check(restart_scrap_quantity>=0),
  scrap_unit text check(length(trim(scrap_unit)) between 1 and 30),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id),
  unique(factory_id,work_center_id,product_id),
  foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),
  foreign key(factory_id,product_id) references public.products(factory_id,id),
  check ((scrap_expected is null and shutdown_scrap_quantity is null
      and restart_scrap_quantity is null and scrap_unit is null)
    or (scrap_expected=false and shutdown_scrap_quantity is null
      and restart_scrap_quantity is null and scrap_unit is null)
    or (scrap_expected=true and shutdown_scrap_quantity is not null
      and restart_scrap_quantity is not null and scrap_unit is not null))
);
create table public.production_loss_recovery_rates (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references public.factories(id),
  work_center_id uuid not null,
  product_id uuid not null,
  rate numeric not null check(rate>0),
  unit text not null check(unit in ('meter','piece')),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id),
  unique(factory_id,work_center_id,product_id),
  foreign key(factory_id,work_center_id) references public.work_centers(factory_id,id),
  foreign key(factory_id,product_id) references public.products(factory_id,id)
);
create table public.production_loss_actuals (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references public.factories(id),
  event_id uuid not null,
  scrap_quantity numeric check(scrap_quantity>=0),
  scrap_unit text check(length(trim(scrap_unit)) between 1 and 30),
  shutdown_scrap_quantity numeric check(shutdown_scrap_quantity>=0),
  restart_scrap_quantity numeric check(restart_scrap_quantity>=0),
  recovery_minutes numeric check(recovery_minutes>=0),
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default clock_timestamp(),
  unique(factory_id,event_id),
  foreign key(factory_id,event_id) references public.downtime_events(factory_id,id),
  check ((scrap_quantity is null and scrap_unit is null)
    or (scrap_quantity is not null and scrap_unit is not null)),
  check ((shutdown_scrap_quantity is null and restart_scrap_quantity is null)
    or (shutdown_scrap_quantity is not null and restart_scrap_quantity is not null
      and scrap_quantity is not null
      and scrap_quantity=shutdown_scrap_quantity+restart_scrap_quantity)),
  check(scrap_quantity is not null or recovery_minutes is not null)
);
do $$ declare tab text; begin
  foreach tab in array array['production_loss_profiles',
    'production_loss_recovery_rates','production_loss_actuals'] loop
    execute format('alter table public.%I enable row level security',tab);
    execute format('create policy read_authorized on public.%I for select to authenticated using(private.has_permission(factory_id,''downtime'',''view''))',tab);
    execute format('grant select on public.%I to authenticated',tab);
    execute format('create trigger audit_record after insert or update or delete on public.%I for each row execute function private.audit_change()',tab);
  end loop;
end $$;

create function public.configure_production_loss_profile(
  factory uuid,work_center uuid,product uuid,can_defer boolean,scrap_expected boolean,
  shutdown_scrap numeric,restart_scrap numeric,scrap_unit text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
  perform private.require_permission(factory,'centers','edit');
  perform private.require_permission(factory,'downtime','edit');
  if not exists(select 1 from public.work_centers where factory_id=factory
    and id=work_center and not archived) then raise exception 'not_found'; end if;
  if not exists(select 1 from public.work_center_capabilities
    where factory_id=factory and work_center_id=work_center
      and product_id=product) then raise exception 'loss_profile_incompatible'; end if;
  insert into public.production_loss_profiles(factory_id,work_center_id,product_id,
    can_defer,scrap_expected,shutdown_scrap_quantity,restart_scrap_quantity,
    scrap_unit,updated_by)
  values(factory,work_center,product,can_defer,scrap_expected,shutdown_scrap,
    restart_scrap,nullif(trim(scrap_unit),''),auth.uid())
  on conflict(factory_id,work_center_id,product_id) do update set
    can_defer=excluded.can_defer,scrap_expected=excluded.scrap_expected,
    shutdown_scrap_quantity=excluded.shutdown_scrap_quantity,
    restart_scrap_quantity=excluded.restart_scrap_quantity,
    scrap_unit=excluded.scrap_unit,updated_at=clock_timestamp(),
    updated_by=auth.uid()
  returning id into result_id;
  return result_id;
end;
$$;
create function public.configure_production_loss_recovery_rate(
  factory uuid,work_center uuid,product uuid,rate numeric,unit text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
  perform private.require_permission(factory,'centers','edit');
  perform private.require_permission(factory,'downtime','edit');
  if not exists(select 1 from public.work_center_capabilities c
    where c.factory_id=factory and c.work_center_id=work_center
      and c.product_id=product and c.rate_unit=unit) then
    raise exception 'loss_recovery_incompatible'; end if;
  insert into public.production_loss_recovery_rates
    (factory_id,work_center_id,product_id,rate,unit,updated_by)
  values(factory,work_center,product,rate,unit,auth.uid())
  on conflict(factory_id,work_center_id,product_id) do update set
    rate=excluded.rate,unit=excluded.unit,updated_at=clock_timestamp(),
    updated_by=auth.uid()
  returning id into result_id;
  return result_id;
end;
$$;
create function public.record_production_loss_actuals(
  factory uuid,event uuid,scrap_quantity numeric,scrap_unit text,
  recovery_minutes numeric,shutdown_scrap numeric,restart_scrap numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid;
begin
  perform private.require_permission(factory,'downtime','edit');
  if not exists(select 1 from public.downtime_events
    where factory_id=factory and id=event and ended_at is not null)
    then raise exception 'downtime_not_reviewable'; end if;
  insert into public.production_loss_actuals(factory_id,event_id,
    scrap_quantity,scrap_unit,recovery_minutes,shutdown_scrap_quantity,
    restart_scrap_quantity,recorded_by)
  values(factory,event,scrap_quantity,nullif(trim(scrap_unit),''),
    recovery_minutes,shutdown_scrap,restart_scrap,auth.uid())
  on conflict(factory_id,event_id) do update set
    scrap_quantity=excluded.scrap_quantity,scrap_unit=excluded.scrap_unit,
    recovery_minutes=excluded.recovery_minutes,
    shutdown_scrap_quantity=excluded.shutdown_scrap_quantity,
    restart_scrap_quantity=excluded.restart_scrap_quantity,
    recorded_by=auth.uid(),
    recorded_at=clock_timestamp()
  returning id into result_id;
  return result_id;
end;
$$;
revoke all on function public.configure_production_loss_profile(
  uuid,uuid,uuid,boolean,boolean,numeric,numeric,text),
  public.configure_production_loss_recovery_rate(uuid,uuid,uuid,numeric,text),
  public.record_production_loss_actuals(uuid,uuid,numeric,text,numeric,numeric,numeric)
  from public,anon,authenticated;
grant execute on function public.configure_production_loss_profile(
  uuid,uuid,uuid,boolean,boolean,numeric,numeric,text),
  public.configure_production_loss_recovery_rate(uuid,uuid,uuid,numeric,text),
  public.record_production_loss_actuals(uuid,uuid,numeric,text,numeric,numeric,numeric)
  to authenticated;

-- A stop is a physical state transition. Its planned/unplanned observation is
-- recorded at the same database timestamp and cannot be changed in place.
create function public.stop_machine(factory uuid,work_center uuid,nature text,
  reason uuid,activity text,notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare old_s text; transition_time timestamptz; event_id uuid;
begin
  if not private.has_permission(factory,'centers','edit') then
    perform private.require_permission(factory,'machine_status','edit'); end if;
  if length(coalesce(notes,''))>2000 then raise exception 'invalid_notes'; end if;
  if nature='unplanned' then
    if activity is not null or not private.current_downtime_reason(factory,reason)
      then raise exception 'reason_required'; end if;
  elsif nature='planned' then
    if reason is not null or activity not in
      ('cleaning','changeover','preventive_maintenance','inspection',
       'planned_process','other') then raise exception 'invalid_planned_activity'; end if;
  else raise exception 'invalid_stop_nature'; end if;
  select status into old_s from public.work_centers
    where factory_id=factory and id=work_center and not archived for update;
  if not found then raise exception 'not_found'; end if;
  if old_s='stopped' then raise exception 'status_unchanged'; end if;
  transition_time:=clock_timestamp();
  update public.downtime_events set ended_at=transition_time
    where factory_id=factory and work_center_id=work_center and ended_at is null;
  insert into public.status_events(factory_id,work_center_id,old_status,
    new_status,reason_id,notes,created_at,created_by)
    values(factory,work_center,old_s,'stopped',reason,coalesce(notes,''),
      transition_time,auth.uid());
  insert into public.downtime_events(factory_id,work_center_id,reason_id,
    notes,started_at,created_by,entered_by,stop_nature,planned_activity)
    values(factory,work_center,reason,coalesce(notes,''),transition_time,
      auth.uid(),auth.uid(),nature,activity) returning id into event_id;
  update public.work_centers set status='stopped',updated_at=transition_time
    where factory_id=factory and id=work_center;
  return event_id;
end;
$$;
revoke all on function public.stop_machine(uuid,uuid,text,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.stop_machine(uuid,uuid,text,uuid,text,text)
  to authenticated;

-- Context is sampled after every material change while a stop is open. The
-- model replays these immutable samples; later Planning or engineer edits do
-- not reprice historical intervals. There is no second flow implementation.
create table public.production_loss_context_snapshots (
  id bigint generated always as identity primary key,
  factory_id uuid not null references public.factories(id),
  event_id uuid not null,
  captured_at timestamptz not null,
  context jsonb not null,
  foreign key(factory_id,event_id) references public.downtime_events(factory_id,id)
);
create index production_loss_context_event_time on
  public.production_loss_context_snapshots(event_id,captured_at,id);
alter table public.production_loss_context_snapshots enable row level security;
create policy read_authorized on public.production_loss_context_snapshots
  for select to authenticated using(private.has_permission(factory_id,'downtime','view'));
grant select on public.production_loss_context_snapshots to authenticated;

create function private.capture_production_loss_context(f uuid,at_time timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare event_row record; context_value jsonb;
begin
  if f is null or at_time is null then return; end if;
  for event_row in select id from public.downtime_events
    where factory_id=f and not retroactive and started_at<=at_time
      and (ended_at is null or ended_at>=at_time) loop
    select jsonb_build_object(
      'centers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.work_centers x where x.factory_id=f),
      'stops',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.downtime_events x where x.factory_id=f and x.ended_at is null),
      'transfers',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_transfers x where x.factory_id=f and x.ended_at is null),
      'orders',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_orders x where x.factory_id=f and x.status<>'cancelled'),
      'products',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.products x where x.factory_id=f),
      'capabilities',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.work_center_capabilities x where x.factory_id=f),
      'alternatives',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.work_center_alternatives x where x.factory_id=f),
      'profiles',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_loss_profiles x where x.factory_id=f),
      'recovery_rates',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_loss_recovery_rates x where x.factory_id=f),
      'lines',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb)
        from public.production_lines x where x.factory_id=f)
    ) into context_value;
    insert into public.production_loss_context_snapshots
      (factory_id,event_id,captured_at,context)
      values(f,event_row.id,at_time,context_value);
  end loop;
end;
$$;
revoke all on function private.capture_production_loss_context(uuid,timestamptz)
  from public,anon,authenticated;

create function private.capture_production_loss_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare changed_at timestamptz;
begin
  if tg_op='DELETE' then
    perform private.capture_production_loss_context(old.factory_id,clock_timestamp());
    return old;
  end if;
  changed_at:=case
    when tg_table_name='downtime_events' and tg_op='INSERT' then new.started_at
    when tg_table_name='downtime_events' and tg_op='UPDATE' then new.ended_at
    when tg_table_name='work_centers' and tg_op='UPDATE'
      and old.status is distinct from new.status then new.updated_at
    when tg_table_name='production_transfers' and tg_op='INSERT' then new.created_at
    when tg_table_name='production_transfers' and tg_op='UPDATE' then new.ended_at
    else clock_timestamp() end;
  perform private.capture_production_loss_context(new.factory_id,changed_at);
  return new;
end;
$$;
revoke all on function private.capture_production_loss_change()
  from public,anon,authenticated;
create trigger loss_context_stop_start after insert on public.downtime_events
  for each row execute function private.capture_production_loss_change();
create trigger loss_context_stop_end after update of ended_at on public.downtime_events
  for each row when(old.ended_at is distinct from new.ended_at)
  execute function private.capture_production_loss_change();
create trigger loss_context_center after update of status,line_id,position,
  dependency_mode,impact_scope,buffer_minutes,archived on public.work_centers
  for each row execute function private.capture_production_loss_change();
create trigger loss_context_transfer_start after insert on public.production_transfers
  for each row execute function private.capture_production_loss_change();
create trigger loss_context_transfer_end after update of ended_at on public.production_transfers
  for each row when(old.ended_at is distinct from new.ended_at)
  execute function private.capture_production_loss_change();
create trigger loss_context_plan after insert or update of
  line_id,product_id,start_time,expected_finish,status on public.production_orders
  for each row execute function private.capture_production_loss_change();
create trigger loss_context_capability after insert or update or delete
  on public.work_center_capabilities for each row execute function private.capture_production_loss_change();
create trigger loss_context_profile after insert or update
  on public.production_loss_profiles for each row execute function private.capture_production_loss_change();
create trigger loss_context_recovery after insert or update
  on public.production_loss_recovery_rates for each row execute function private.capture_production_loss_change();
create trigger loss_context_alternatives after insert or update or delete
  on public.work_center_alternatives for each row execute function private.capture_production_loss_change();
create trigger loss_context_line after update of paused_at,archived
  on public.production_lines for each row execute function private.capture_production_loss_change();

-- Extend the established authorized snapshot with V1 loss data.
create or replace function public.factory_snapshot(factory uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';
begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when private.is_platform_admin() then $1 when m->>'status'='approved'
   then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
   if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
   perform private.require_permission(f,'factory','view');
   perform private.record_access(f,'READ');
   select to_jsonb(x) into fac from public.factories x where id=f;
   foreach tab in array array[
     'areas','work_center_categories','production_lines','work_centers',
     'products','production_requests','production_orders','downtime_reasons',
     'status_events','downtime_events','memberships','roles','role_permissions',
     'support_access','audit_logs','oee_observations','production_entries',
     'operator_assignments','work_center_alternatives','work_center_capabilities',
     'daily_targets','user_permissions','production_transfers',
     'production_routing_steps','downtime_classification_corrections',
     'production_loss_profiles','production_loss_recovery_rates',
     'production_loss_actuals','production_loss_context_snapshots'] loop
     execute format('select coalesce(jsonb_agg(x),''[]'') from
       (select * from public.%I where factory_id=$1 %s limit 5000) x',
       tab,case when tab in ('status_events','audit_logs','production_entries',
         'downtime_events') then 'order by created_at desc,id'
         when tab='production_loss_context_snapshots' then 'order by id desc'
         else '' end) into rows using f;
     data:=data||jsonb_build_object(tab,rows);
     if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
   end loop;
   data:=data||jsonb_build_object('machine_statuses',
     (select jsonb_agg(x) from public.machine_statuses x where code<>'maintenance'),
     'permissions',(select jsonb_agg(x) from public.permissions x));
 end if;
 return jsonb_build_object('platformAdmin',private.is_platform_admin(),
   'factories',case when f is null then private.platform_factories() else '[]'::jsonb end,
   'factory',fac,'membership',m,
   'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,
   'tables',data,'supportFactories',
   (select coalesce(jsonb_agg(x),'[]'::jsonb) from public.support_access x
     where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end;
$$;
