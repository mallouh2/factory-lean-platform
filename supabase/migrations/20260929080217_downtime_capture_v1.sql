-- The physical stop starts immediately. Classification and engineering approval
-- are separate, audited facts; the original observation is never overwritten.
alter table public.downtime_events alter column reason_id drop not null;
alter table public.downtime_events
  add column initial_note text not null default '',
  add column initial_entered_by uuid references auth.users,
  add column initial_entered_at timestamptz,
  add column approved_cause_id uuid,
  add column approved_by uuid references auth.users,
  add column approved_at timestamptz,
  add column engineering_note text not null default '',
  add column retroactive boolean not null default false,
  add column entered_by uuid references auth.users,
  add foreign key(factory_id,approved_cause_id)
    references public.downtime_reasons(factory_id,id);

-- Old change_status required a reason at insertion, so its event creation time
-- and actor are reliable entry audit data. No approval is inferred.
update public.downtime_events set
  initial_note=notes,
  initial_entered_by=created_by,
  initial_entered_at=created_at,
  entered_by=created_by
where reason_id is not null;

alter table public.downtime_events
  add constraint downtime_initial_audit_pair check
    ((reason_id is null and initial_entered_at is null and initial_entered_by is null)
      or (reason_id is not null and initial_entered_at is not null)),
  add constraint downtime_approval_audit_pair check
    ((approved_cause_id is null and approved_by is null and approved_at is null)
      or (approved_cause_id is not null and approved_by is not null and approved_at is not null)),
  add constraint downtime_note_lengths check
    (length(initial_note) <= 2000 and length(engineering_note) <= 2000),
  add constraint downtime_retroactive_closed check (not retroactive or ended_at is not null);

-- Utilities is the only V1 top-level choice absent from the existing catalog.
insert into public.downtime_reasons(factory_id,name,name_ar)
select f.id,'Utilities','المرافق' from public.factories f
where not exists(select 1 from public.downtime_reasons r
  where r.factory_id=f.id and r.name='Utilities' and r.parent_id is null);
create function private.seed_utilities_downtime_reason()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.downtime_reasons(factory_id,name,name_ar)
    values(new.id,'Utilities','المرافق');
  return new;
end;
$$;
create trigger seed_utilities_downtime_reason
  after insert on public.factories for each row
  execute function private.seed_utilities_downtime_reason();
revoke all on function private.seed_utilities_downtime_reason()
  from public,anon,authenticated;

create or replace function private.capture_stop_context()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  machine public.work_centers%rowtype;
  borrowed_line uuid;
  borrowed_item uuid;
begin
  -- Current assignment is not trustworthy context for a missed historical stop.
  if new.retroactive then return new; end if;
  select * into machine from public.work_centers
    where factory_id=new.factory_id and id=new.work_center_id;
  select source.line_id, transfer.order_id into borrowed_line, borrowed_item
    from public.production_transfers transfer
    join public.work_centers source
      on source.factory_id=transfer.factory_id and source.id=transfer.original_id
    where transfer.factory_id=new.factory_id
      and transfer.alternative_id=new.work_center_id and transfer.ended_at is null
    order by transfer.created_at desc limit 1;
  if found then
    new.line_id:=borrowed_line;
    new.order_id:=borrowed_item;
  else
    new.line_id:=machine.line_id;
    new.order_id:=machine.order_id;
  end if;
  new.impact_scope_at_start:=machine.impact_scope;
  new.blocking_at_start:=machine.dependency_mode in ('blocking','buffer')
    and machine.impact_scope<>'none';
  new.buffer_minutes_at_start:=case when machine.dependency_mode='buffer'
    then machine.buffer_minutes else 0 end;
  new.rate_at_start:=machine.production_speed;
  return new;
end;
$$;

create function private.guard_downtime_capture()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='INSERT' then
    new.entered_by:=coalesce(new.entered_by,new.created_by);
    if new.reason_id is not null then
      new.initial_entered_by:=coalesce(new.initial_entered_by,new.created_by);
      new.initial_entered_at:=coalesce(new.initial_entered_at,clock_timestamp());
      new.initial_note:=coalesce(nullif(new.initial_note,''),new.notes,'');
    end if;
    if new.retroactive and (new.entered_by is null or new.ended_at is null) then
      raise exception 'downtime_invalid_interval';
    end if;
    return new;
  end if;
  if (old.factory_id,old.work_center_id,old.started_at,old.retroactive,old.entered_by)
    is distinct from
     (new.factory_id,new.work_center_id,new.started_at,new.retroactive,new.entered_by)
    or (old.ended_at is not null and old.ended_at is distinct from new.ended_at) then
    raise exception 'downtime_immutable';
  end if;
  if old.reason_id is not null and
    (old.reason_id,old.initial_note,old.initial_entered_by,old.initial_entered_at)
      is distinct from
    (new.reason_id,new.initial_note,new.initial_entered_by,new.initial_entered_at) then
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
create trigger guard_downtime_capture
  before insert or update on public.downtime_events
  for each row execute function private.guard_downtime_capture();
revoke all on function private.guard_downtime_capture() from public,anon,authenticated;

-- Preserve all existing machine/transfer transitions; only remove the
-- requirement to classify before the physical downtime event is created.
create or replace function private.change_status(f uuid,w uuid,s text,reason uuid,
  sub_reason uuid,n text,eta timestamptz,responsible uuid,alternative uuid,
  transferred boolean)
returns void language plpgsql security definer set search_path='' as $$
declare old_s text; down boolean;
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
  if down then
    if reason is not null and not exists(select 1 from public.downtime_reasons
      where id=reason and factory_id=f and parent_id is null) then
      raise exception 'reason_required'; end if;
    if sub_reason is not null and (reason is null or not exists(select 1
      from public.downtime_reasons where id=sub_reason and parent_id=reason
        and factory_id=f)) then raise exception 'invalid_sub_reason'; end if;
    if eta is not null and eta<now() then raise exception 'invalid_restart_time'; end if;
  end if;
  update public.downtime_events set ended_at=clock_timestamp()
    where factory_id=f and work_center_id=w and ended_at is null;
  insert into public.status_events(factory_id,work_center_id,old_status,
    new_status,reason_id,notes,created_by)
    values(f,w,old_s,s,reason,coalesce(n,''),auth.uid());
  if down then
    insert into public.downtime_events(factory_id,work_center_id,reason_id,
      sub_reason_id,notes,expected_restart,responsible_id,alternative_id,
      transferred,created_by,entered_by)
      values(f,w,reason,sub_reason,coalesce(n,''),eta,responsible,alternative,
        false,auth.uid(),auth.uid());
  end if;
  update public.work_centers set status=s,updated_at=now(),
    last_restart_time=case when s='running' then now() else last_restart_time end
    where id=w;
end;
$$;

create function public.set_downtime_initial(factory uuid,event uuid,reason uuid,
  notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
begin
  if not private.has_permission(factory,'machine_status','edit')
    and not private.has_permission(factory,'centers','edit') then
    perform private.require_permission(factory,'downtime','edit'); end if;
  if reason is null or not exists(select 1 from public.downtime_reasons
    where factory_id=factory and id=reason and parent_id is null) then
    raise exception 'reason_required'; end if;
  if length(coalesce(notes,''))>2000 then raise exception 'invalid_notes'; end if;
  update public.downtime_events set reason_id=reason,
    initial_note=coalesce(notes,''),initial_entered_by=auth.uid(),
    initial_entered_at=clock_timestamp()
    where factory_id=factory and id=event and reason_id is null;
  if not found then raise exception 'downtime_initial_locked'; end if;
  return event;
end;
$$;

create function public.approve_downtime_cause(factory uuid,event uuid,cause uuid,
  notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(factory,'downtime','edit');
  if cause is null or not exists(select 1 from public.downtime_reasons
    where factory_id=factory and id=cause and parent_id is null) then
    raise exception 'reason_required'; end if;
  if length(coalesce(notes,''))>2000 then raise exception 'invalid_notes'; end if;
  update public.downtime_events set approved_cause_id=cause,
    approved_by=auth.uid(),approved_at=clock_timestamp(),
    engineering_note=coalesce(notes,'')
    where factory_id=factory and id=event and ended_at is not null
      and approved_at is null;
  if not found then raise exception 'downtime_not_reviewable'; end if;
  return event;
end;
$$;

create function public.record_missed_downtime(factory uuid,work_center uuid,
  started_at timestamptz,ended_at timestamptz,reason uuid default null,
  notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare new_id uuid;
begin
  perform private.require_permission(factory,'downtime','edit');
  if started_at is null or ended_at is null or ended_at<=started_at
    or ended_at>clock_timestamp() then raise exception 'downtime_invalid_interval'; end if;
  if length(coalesce(notes,''))>2000 then raise exception 'invalid_notes'; end if;
  if reason is not null and not exists(select 1 from public.downtime_reasons
    where factory_id=factory and id=reason and parent_id is null) then
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
    values(factory,work_center,reason,started_at,ended_at,
      coalesce(notes,''),coalesce(notes,''),auth.uid(),auth.uid(),true)
    returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.set_downtime_initial(uuid,uuid,uuid,text),
  public.approve_downtime_cause(uuid,uuid,uuid,text),
  public.record_missed_downtime(uuid,uuid,timestamptz,timestamptz,uuid,text)
  from public,anon,authenticated;
grant execute on function public.set_downtime_initial(uuid,uuid,uuid,text),
  public.approve_downtime_cause(uuid,uuid,uuid,text),
  public.record_missed_downtime(uuid,uuid,timestamptz,timestamptz,uuid,text)
  to authenticated;
