-- Capture one server timestamp after the machine row lock. Direct transitions
-- between downtime statuses then close and open adjacent, nonoverlapping events.
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
    if reason is not null and not exists(select 1 from public.downtime_reasons
      where id=reason and factory_id=f and parent_id is null) then
      raise exception 'reason_required'; end if;
    if sub_reason is not null and (reason is null or not exists(select 1
      from public.downtime_reasons where id=sub_reason and parent_id=reason
        and factory_id=f)) then raise exception 'invalid_sub_reason'; end if;
    if eta is not null and eta<transition_time then raise exception 'invalid_restart_time'; end if;
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
      values(f,w,reason,sub_reason,coalesce(n,''),transition_time,eta,
        responsible,alternative,false,auth.uid(),auth.uid());
  end if;
  update public.work_centers set status=s,updated_at=transition_time,
    last_restart_time=case when s='running' then transition_time
      else last_restart_time end
    where id=w;
end;
$$;
