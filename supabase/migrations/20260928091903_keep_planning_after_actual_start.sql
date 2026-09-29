-- Avoid PL/pgSQL ambiguity after adding the production_orders.actual_start column.
-- The calendar, capability, setup and overlap calculations are unchanged.
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
  effective_start timestamptz;
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
  effective_start:=private.next_working_start(f,planned_start);
  planned_finish:=private.finish_after_working_minutes(f,effective_start,minutes_required::integer);
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
      and effective_start<other.expected_finish and planned_finish>other.start_time
  ) then raise exception 'planning_overlap'; end if;
  update public.production_orders set
    line_id=target_line,start_time=effective_start,expected_finish=planned_finish
    where factory_id=f and id=item;
  return item;
end;
$$;
