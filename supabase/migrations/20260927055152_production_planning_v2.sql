-- A capability's rate is per hour, but its quantity unit was previously unknown.
-- Existing rates remain untyped until a factory user confirms Meter or Piece.
alter table public.work_center_capabilities
  add column rate_unit text check (rate_unit in ('meter','piece'));

create or replace function private.configure_center_capabilities(f uuid,w uuid,capabilities jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(f,'centers','edit');
  perform 1 from public.work_centers where id=w and factory_id=f and not archived for update;
  if not found then raise exception 'not_found'; end if;
  if capabilities is null or jsonb_typeof(capabilities)<>'array' then
    raise exception 'invalid_capabilities'; end if;
  if exists(
    select 1 from jsonb_to_recordset(capabilities) x(product_id uuid,rate numeric,rate_unit text)
    where x.rate is null or x.rate<=0 or x.rate_unit not in ('meter','piece') or x.rate_unit is null
  ) then raise exception 'invalid_capabilities'; end if;
  delete from public.work_center_capabilities where factory_id=f and work_center_id=w;
  insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit)
  select f,w,x.product_id,x.rate,x.rate_unit
  from jsonb_to_recordset(capabilities) x(product_id uuid,rate numeric,rate_unit text);
end;
$$;

-- Serialize plans per line. The final overlap check belongs in the database:
-- two planners must not both accept the same free gap.
create function private.plan_product_item(f uuid,item uuid,target_line uuid,planned_start timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  target public.production_orders%rowtype;
  matches integer;
  typed_matches integer;
  slowest numeric;
  fastest numeric;
  minutes_required numeric;
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
    max(cap.rate) filter (where cap.rate_unit=target.unit)
    into matches,typed_matches,slowest,fastest
  from public.work_centers center
  join public.work_center_capabilities cap
    on cap.factory_id=center.factory_id and cap.work_center_id=center.id
      and cap.product_id=target.product_id
  where center.factory_id=f and center.line_id=target_line and not center.archived;
  if matches=0 then raise exception 'planning_incompatible_line'; end if;
  if target.unit not in ('meter','piece') or typed_matches<>matches then
    raise exception 'planning_missing_rate'; end if;
  if slowest<>fastest then raise exception 'planning_ambiguous_rate'; end if;
  minutes_required:=ceil(target.target_quantity / slowest * 60);
  if minutes_required<1 or minutes_required>5256000 then
    raise exception 'planning_invalid_quantity'; end if;
  planned_finish:=planned_start+make_interval(mins=>minutes_required::integer);
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
      and planned_start<other.expected_finish and planned_finish>other.start_time
  ) then raise exception 'planning_overlap'; end if;
  update public.production_orders set
    line_id=target_line,start_time=planned_start,expected_finish=planned_finish
    where factory_id=f and id=item;
  return item;
end;
$$;

create function public.plan_product_item(factory uuid,item uuid,target_line uuid,planned_start timestamptz)
returns uuid language sql security definer set search_path='' as $$
  select private.plan_product_item(factory,item,target_line,planned_start)
$$;
revoke all on function private.plan_product_item(uuid,uuid,uuid,timestamptz),
  public.plan_product_item(uuid,uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.plan_product_item(uuid,uuid,uuid,timestamptz) to authenticated;
