-- Engineer-confirmed impact is separate from the immutable estimate and from
-- the physical downtime interval. Keep legacy actual observations untouched.
alter table public.production_loss_actuals
  add column actual_loss_minutes numeric check (actual_loss_minutes >= 0),
  add column actual_lost_output_quantity numeric check (actual_lost_output_quantity >= 0),
  add column actual_lost_output_unit text;

alter table public.production_loss_actuals
  add constraint production_loss_actual_output_unit check (
    (actual_lost_output_quantity is null and actual_lost_output_unit is null)
    or (actual_lost_output_quantity is not null and
      actual_lost_output_unit in ('meter','piece'))
  );

alter table public.production_loss_actuals
  drop constraint production_loss_actuals_check1,
  drop constraint production_loss_actuals_check2;

alter table public.production_loss_actuals
  add constraint production_loss_actual_scrap_breakdown check (
    (shutdown_scrap_quantity is null and restart_scrap_quantity is null)
    or (scrap_quantity is not null and
      coalesce(shutdown_scrap_quantity,0) + coalesce(restart_scrap_quantity,0)
        <= scrap_quantity + greatest(0.000001, scrap_quantity * 0.000000001) and
      (shutdown_scrap_quantity is null or restart_scrap_quantity is null or
        abs(scrap_quantity - shutdown_scrap_quantity - restart_scrap_quantity)
          <= greatest(0.000001, scrap_quantity * 0.000000001)))
  ),
  add constraint production_loss_actual_any_value check (
    scrap_quantity is not null or recovery_minutes is not null or
    actual_loss_minutes is not null or actual_lost_output_quantity is not null
  );

-- Replace the callable signature. The old seven-argument version remains in
-- the catalog for compatibility, but is no longer executable by clients.
revoke execute on function public.record_production_loss_actuals(
  uuid,uuid,numeric,text,numeric,numeric,numeric) from authenticated;

create function public.record_production_loss_actuals(
  factory uuid,event uuid,scrap_quantity numeric,scrap_unit text,
  recovery_minutes numeric,shutdown_scrap numeric,restart_scrap numeric,
  actual_loss_minutes numeric,actual_lost_output_quantity numeric,
  actual_lost_output_unit text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; total_scrap numeric := scrap_quantity;
  tolerance numeric;
begin
  perform private.require_permission(factory,'downtime','edit');
  if not exists(select 1 from public.downtime_events
    where factory_id=factory and id=event and ended_at is not null)
    then raise exception 'downtime_not_reviewable'; end if;
  if (scrap_quantity is not null and scrap_quantity < 0) or
    (shutdown_scrap is not null and shutdown_scrap < 0) or
    (restart_scrap is not null and restart_scrap < 0) or
    (recovery_minutes is not null and recovery_minutes < 0) or
    (actual_loss_minutes is not null and actual_loss_minutes < 0) or
    (actual_lost_output_quantity is not null and actual_lost_output_quantity < 0)
    then raise exception 'loss_actual_nonnegative'; end if;
  if total_scrap is null and (shutdown_scrap is null) <> (restart_scrap is null)
    then raise exception 'loss_scrap_need_total_or_both'; end if;
  if total_scrap is null and shutdown_scrap is not null then
    total_scrap := shutdown_scrap + restart_scrap;
  end if;
  if total_scrap is not null then
    if scrap_unit not in ('kg','piece') or scrap_unit is null
      then raise exception 'loss_actual_invalid_unit'; end if;
    tolerance := greatest(0.000001,total_scrap*0.000000001);
    if coalesce(shutdown_scrap,0)+coalesce(restart_scrap,0) > total_scrap+tolerance
      then raise exception 'loss_scrap_breakdown_exceeds_total'; end if;
    if shutdown_scrap is not null and restart_scrap is not null and
      abs(total_scrap-shutdown_scrap-restart_scrap)>tolerance
      then raise exception 'loss_scrap_breakdown_mismatch'; end if;
  elsif scrap_unit is not null then raise exception 'loss_actual_invalid_unit';
  end if;
  if (actual_lost_output_quantity is null) <> (actual_lost_output_unit is null)
    or (actual_lost_output_quantity is not null and
      actual_lost_output_unit not in ('meter','piece'))
    then raise exception 'loss_actual_invalid_unit'; end if;
  if total_scrap is null and recovery_minutes is null and
    actual_loss_minutes is null and actual_lost_output_quantity is null
    then raise exception 'loss_actual_at_least_one'; end if;
  insert into public.production_loss_actuals(factory_id,event_id,
    scrap_quantity,scrap_unit,recovery_minutes,shutdown_scrap_quantity,
    restart_scrap_quantity,actual_loss_minutes,actual_lost_output_quantity,
    actual_lost_output_unit,recorded_by)
  values(factory,event,total_scrap,scrap_unit,recovery_minutes,shutdown_scrap,
    restart_scrap,actual_loss_minutes,actual_lost_output_quantity,
    actual_lost_output_unit,auth.uid())
  on conflict(factory_id,event_id) do update set
    scrap_quantity=excluded.scrap_quantity,scrap_unit=excluded.scrap_unit,
    recovery_minutes=excluded.recovery_minutes,
    shutdown_scrap_quantity=excluded.shutdown_scrap_quantity,
    restart_scrap_quantity=excluded.restart_scrap_quantity,
    actual_loss_minutes=excluded.actual_loss_minutes,
    actual_lost_output_quantity=excluded.actual_lost_output_quantity,
    actual_lost_output_unit=excluded.actual_lost_output_unit,
    recorded_by=auth.uid(),recorded_at=clock_timestamp()
  returning id into result_id;
  return result_id;
end;
$$;
revoke all on function public.record_production_loss_actuals(
  uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text)
  from public,anon,authenticated;
grant execute on function public.record_production_loss_actuals(
  uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text)
  to authenticated;
