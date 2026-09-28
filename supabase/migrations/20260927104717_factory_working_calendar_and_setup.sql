-- A null calendar retains continuous scheduling for existing factories until configured.
alter table public.factories
  add column working_days_mask integer,
  add column workday_start time without time zone,
  add column workday_end time without time zone,
  add constraint factory_working_calendar_valid check (
    (working_days_mask is null and workday_start is null and workday_end is null) or
    (working_days_mask between 1 and 127 and workday_start is not null and
      workday_end is not null and workday_start < workday_end)
  );

alter table public.work_center_capabilities
  add column setup_minutes integer not null default 0
  check (setup_minutes between 0 and 10080);

create function private.next_working_start(f uuid, desired timestamptz)
returns timestamptz language plpgsql stable security definer set search_path='' as $$
declare
  calendar record;
  day date;
  opening timestamptz;
  closing timestamptz;
begin
  select timezone,working_days_mask,workday_start,workday_end into calendar
    from public.factories where id=f;
  if not found then raise exception 'not_found'; end if;
  if calendar.working_days_mask is null then return desired; end if;
  day := (desired at time zone calendar.timezone)::date;
  for i in 0..7 loop
    if (calendar.working_days_mask & (1 << extract(dow from day)::integer)) <> 0 then
      opening := (day + calendar.workday_start) at time zone calendar.timezone;
      closing := (day + calendar.workday_end) at time zone calendar.timezone;
      if closing > desired then return greatest(desired,opening); end if;
    end if;
    day := day + 1;
  end loop;
  raise exception 'planning_invalid_calendar';
end;
$$;

create function private.finish_after_working_minutes(f uuid, planned_start timestamptz,
  minutes_required integer)
returns timestamptz language plpgsql stable security definer set search_path='' as $$
declare
  calendar record;
  cursor_time timestamptz;
  day date;
  closing timestamptz;
  available_minutes numeric;
  remaining numeric := minutes_required;
begin
  select timezone,working_days_mask,workday_end into calendar
    from public.factories where id=f;
  if not found then raise exception 'not_found'; end if;
  if calendar.working_days_mask is null then
    return planned_start + make_interval(mins=>minutes_required);
  end if;
  cursor_time := private.next_working_start(f,planned_start);
  for i in 1..4000 loop
    day := (cursor_time at time zone calendar.timezone)::date;
    closing := (day + calendar.workday_end) at time zone calendar.timezone;
    available_minutes := extract(epoch from (closing-cursor_time))/60;
    if remaining <= available_minutes then
      return cursor_time + make_interval(mins=>remaining::integer);
    end if;
    remaining := remaining - available_minutes;
    cursor_time := private.next_working_start(f,closing+interval '1 minute');
  end loop;
  raise exception 'planning_invalid_calendar';
end;
$$;

create function public.configure_working_calendar(factory uuid, days_mask integer,
  day_start time without time zone, day_end time without time zone)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(factory,'settings','edit');
  if days_mask is null or days_mask not between 1 and 127 or
    day_start is null or day_end is null or day_start>=day_end then
    raise exception 'planning_invalid_calendar';
  end if;
  update public.factories set working_days_mask=days_mask,
    workday_start=day_start,workday_end=day_end where id=factory;
  if not found then raise exception 'not_found'; end if;
end;
$$;
revoke all on function public.configure_working_calendar(uuid,integer,time,time) from public,anon,authenticated;
grant execute on function public.configure_working_calendar(uuid,integer,time,time) to authenticated;

create or replace function private.configure_center_capabilities(f uuid,w uuid,capabilities jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(f,'centers','edit');
  perform 1 from public.work_centers where id=w and factory_id=f and not archived for update;
  if not found then raise exception 'not_found'; end if;
  if capabilities is null or jsonb_typeof(capabilities)<>'array' then
    raise exception 'invalid_capabilities'; end if;
  if exists(
    select 1 from jsonb_to_recordset(capabilities)
      x(product_id uuid,rate numeric,rate_unit text,setup_minutes integer)
    where x.rate is null or x.rate<=0 or x.rate_unit not in ('meter','piece') or
      x.rate_unit is null or coalesce(x.setup_minutes,0) not between 0 and 10080
  ) then raise exception 'invalid_capabilities'; end if;
  delete from public.work_center_capabilities where factory_id=f and work_center_id=w;
  insert into public.work_center_capabilities
    (factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes)
  select f,w,x.product_id,x.rate,x.rate_unit,coalesce(x.setup_minutes,0)
  from jsonb_to_recordset(capabilities)
    x(product_id uuid,rate numeric,rate_unit text,setup_minutes integer);
end;
$$;

create or replace function private.plan_product_item(f uuid,item uuid,target_line uuid,planned_start timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  target public.production_orders%rowtype;
  matches integer;
  typed_matches integer;
  slowest numeric;
  fastest numeric;
  shortest_setup integer;
  longest_setup integer;
  minutes_required numeric;
  actual_start timestamptz;
  planned_finish timestamptz;
begin
  perform private.require_permission(f,'orders','edit');
  select * into target from public.production_orders
    where factory_id=f and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status<>'planned' or target.produced_quantity>0 then
    raise exception 'planning_already_started'; end if;
  if target_line is null and planned_start is null then
    update public.production_orders set line_id=null,start_time=null,expected_finish=null
      where factory_id=f and id=item;
    return item;
  end if;
  if target_line is null or planned_start is null or planned_start<now()-interval '1 minute' then
    raise exception 'planning_invalid_start'; end if;
  perform 1 from public.production_lines
    where factory_id=f and id=target_line and not archived for update;
  if not found then raise exception 'planning_incompatible_line'; end if;
  select count(*),count(*) filter (where cap.rate_unit=target.unit),
    min(cap.rate) filter (where cap.rate_unit=target.unit),
    max(cap.rate) filter (where cap.rate_unit=target.unit),
    min(cap.setup_minutes),max(cap.setup_minutes)
    into matches,typed_matches,slowest,fastest,shortest_setup,longest_setup
  from public.work_centers center
  join public.work_center_capabilities cap
    on cap.factory_id=center.factory_id and cap.work_center_id=center.id
      and cap.product_id=target.product_id
  where center.factory_id=f and center.line_id=target_line and not center.archived;
  if matches=0 then raise exception 'planning_incompatible_line'; end if;
  if target.unit not in ('meter','piece') or typed_matches<>matches then
    raise exception 'planning_missing_rate'; end if;
  if slowest<>fastest then raise exception 'planning_ambiguous_rate'; end if;
  if shortest_setup<>longest_setup then raise exception 'planning_ambiguous_setup'; end if;
  minutes_required:=ceil(target.target_quantity / slowest * 60)+shortest_setup;
  if minutes_required<1 or minutes_required>5256000 then
    raise exception 'planning_invalid_quantity'; end if;
  actual_start:=private.next_working_start(f,planned_start);
  planned_finish:=private.finish_after_working_minutes(f,actual_start,minutes_required::integer);
  if exists(
    select 1 from public.production_orders other
    where other.factory_id=f and other.id<>item and other.line_id=target_line
      and other.status in ('planned','active') and
      (other.start_time is null or other.expected_finish is null)
  ) then raise exception 'planning_unknown_block'; end if;
  if exists(
    select 1 from public.production_orders other
    where other.factory_id=f and other.id<>item and other.line_id=target_line
      and other.status in ('planned','active')
      and actual_start<other.expected_finish and planned_finish>other.start_time
  ) then raise exception 'planning_overlap'; end if;
  update public.production_orders set
    line_id=target_line,start_time=actual_start,expected_finish=planned_finish
    where factory_id=f and id=item;
  return item;
end;
$$;
