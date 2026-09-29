-- Qualify RPC arguments that share downtime_events column names. The first V1
-- migration is already applied to TESTING, so this is a forward-only repair.
create or replace function public.set_downtime_initial(factory uuid,event uuid,
  reason uuid,notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
begin
  if not private.has_permission(factory,'machine_status','edit')
    and not private.has_permission(factory,'centers','edit') then
    perform private.require_permission(factory,'downtime','edit'); end if;
  if reason is null or not exists(select 1 from public.downtime_reasons
    where factory_id=factory and id=reason and parent_id is null) then
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
  if cause is null or not exists(select 1 from public.downtime_reasons
    where factory_id=factory and id=cause and parent_id is null) then
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
  if $3 is null or $4 is null or $4<=$3
    or $4>clock_timestamp() then raise exception 'downtime_invalid_interval'; end if;
  if length(coalesce($6,''))>2000 then raise exception 'invalid_notes'; end if;
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
    values(factory,work_center,reason,$3,$4,
      coalesce($6,''),coalesce($6,''),auth.uid(),auth.uid(),true)
    returning id into new_id;
  return new_id;
end;
$$;
