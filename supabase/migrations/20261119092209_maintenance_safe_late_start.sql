-- A duration estimate forecasts resource use. The original approved window remains immutable.
create function private.maintenance_start_blocker(r public.maintenance_requests,s public.maintenance_schedules,at_time timestamptz)
returns text language plpgsql stable security definer set search_path='' as $$
declare
  equipment public.work_centers;
  conflict jsonb;
begin
  if not coalesce((select enabled from private.maintenance_planning_activation where singleton),false) then
    return 'maintenance_planning_inactive';
  end if;
  if s.state is distinct from 'CONFIRMED' then return 'maintenance_approval_required'; end if;
  if at_time<s.planned_start then return 'maintenance_early_start'; end if;
  if coalesce(r.estimated_duration_minutes,0)<=0 then return 'maintenance_unknown_window'; end if;
  select * into equipment from public.work_centers
    where factory_id=r.factory_id and id=r.work_center_id;
  if not found or equipment.archived or equipment.status not in ('idle','stopped','offline') then
    return 'maintenance_machine_not_ready';
  end if;
  if (select evidence from public.maintenance_schedule_resources
      where schedule_id=s.id and machine_id=equipment.id)
      is distinct from private.maintenance_machine_evidence(r.factory_id,equipment.id) then
    return 'maintenance_configuration_changed';
  end if;
  if exists(select 1 from public.production_transfers where factory_id=r.factory_id and ended_at is null
    and (original_id=equipment.id or alternative_id=equipment.id)) then
    return 'maintenance_transfer_unresolved';
  end if;
  conflict:=private.maintenance_capacity_conflict(r.factory_id,equipment.line_id,null,equipment.id,at_time,
    greatest(s.planned_end,at_time+make_interval(mins=>r.estimated_duration_minutes)),s.id);
  return conflict->>'reason';
end$$;
revoke all on function private.maintenance_start_blocker(public.maintenance_requests,public.maintenance_schedules,timestamptz) from public,anon,authenticated;

create or replace function private.maintenance_planned_lifecycle() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.maintenance_schedules;stamp timestamptz;before_row jsonb;blocker text;begin
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
 -- Keep activation steady and recheck the real equipment and current plan at write time.
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
   raise exception 'maintenance_conflict' using errcode='40001';
 end if;
 perform 1 from private.maintenance_planning_activation where singleton for share;
 stamp:=clock_timestamp();
 blocker:=private.maintenance_start_blocker(new,s,stamp);
 if blocker is not null then raise exception '%',blocker;end if;
 new.started_at:=stamp;
 before_row:=to_jsonb(s);update public.maintenance_schedules set hold_started_at=stamp,revision=revision+1,updated_at=stamp where id=s.id;
 perform private.maintenance_schedule_history(s.id,before_row,'start',format(
   'Maintenance started. Start deviation: %s seconds. Estimated overrun: %s seconds.',
   extract(epoch from (stamp-s.planned_start)),
   greatest(0,extract(epoch from (stamp+make_interval(mins=>new.estimated_duration_minutes)-s.planned_end)))));
 elsif new.status='VERIFIED' and s.hold_started_at is not null then
 before_row:=to_jsonb(s);update public.maintenance_schedules set state='RELEASED',released_at=clock_timestamp(),released_by=auth.uid(),revision=revision+1,updated_at=clock_timestamp() where id=s.id;
 perform private.maintenance_schedule_history(s.id,before_row,'release','Independent verification; physical machine unchanged');
 end if;
 return new;
end$$;

-- Advisory status uses the same start guard. The command always recomputes after locking.
create function public.maintenance_start_context(factory uuid,maintenance_request uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  r public.maintenance_requests;
  s public.maintenance_schedules;
  equipment public.work_centers;
  checked_at timestamptz:=statement_timestamp();
  forecast_start timestamptz;
  forecast_end timestamptz;
  blocker text;
  affected jsonb:='[]'::jsonb;
begin
  perform private.require_permission(factory,'factory','view');
  select * into r from public.maintenance_requests where factory_id=factory and id=maintenance_request;
  if not found or not private.maintenance_visible(factory,r.assigned_to,r.requested_by) then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  select * into s from public.maintenance_schedules where factory_id=factory and maintenance_request_id=r.id;
  if not private.maintenance_kind_can_book(r)
    or (r.maintenance_kind='CORRECTIVE' and (s.id is null or s.state in ('UNSCHEDULED','RELEASED') and s.hold_started_at is null)) then
    return jsonb_build_object('applies',false);
  end if;
  if r.status='ASSIGNED' then
    blocker:=private.maintenance_start_blocker(r,s,checked_at);
    if s.state='CONFIRMED' and r.estimated_duration_minutes>0 then
      forecast_start:=greatest(checked_at,s.planned_start);
      forecast_end:=forecast_start+make_interval(mins=>r.estimated_duration_minutes);
      select * into equipment from public.work_centers where factory_id=factory and id=r.work_center_id;
      if equipment.id is not null and (private.has_permission(factory,'orders','view') or private.has_permission(factory,'maintenance','view')) then
        select coalesce(jsonb_agg(to_jsonb(work)), '[]'::jsonb) into affected
        from (
          select o.kind,coalesce(po.code,mr.code) code,o.state,
            case when isfinite(o.starts) then o.starts end starts,
            case when isfinite(o.ends) then o.ends end ends
          from private.maintenance_occupancy(factory,equipment.line_id,null,equipment.id,s.id,null,true,checked_at,
            forecast_start,greatest(s.planned_end,forecast_end)) o
          left join public.production_orders po on o.kind='PRODUCTION' and po.factory_id=factory and po.id=o.id
          left join public.maintenance_schedules ms on o.kind='MAINTENANCE' and ms.factory_id=factory and ms.id=o.id
          left join public.maintenance_requests mr on mr.factory_id=factory and mr.id=ms.maintenance_request_id
          where (o.kind='PRODUCTION' and private.has_permission(factory,'orders','view'))
             or (o.kind='MAINTENANCE' and private.has_permission(factory,'maintenance','view'))
          order by o.starts,o.id limit 6
        ) work;
      end if;
    end if;
  end if;
  return jsonb_build_object('applies',true,'blocker',blocker,'planned_start',s.planned_start,'planned_end',s.planned_end,
    'estimated_end',forecast_end,'overrun_seconds',case when forecast_end is not null then
      greatest(0,extract(epoch from (forecast_end-s.planned_end))) end,'affected',affected,
    'actual_start',r.started_at,'actual_end',r.completed_at);
end$$;
revoke all on function public.maintenance_start_context(uuid,uuid) from public,anon,authenticated;
grant execute on function public.maintenance_start_context(uuid,uuid) to authenticated;
