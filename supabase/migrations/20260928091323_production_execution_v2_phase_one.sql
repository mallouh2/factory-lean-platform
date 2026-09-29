-- Planned timestamps remain the approved schedule. Actual timestamps are written
-- only by the dedicated, factory-scoped execution commands below.
alter table public.production_orders
  add column actual_start timestamptz,
  add column actual_finish timestamptz,
  add constraint production_actual_time_order check (
    actual_finish is null or (actual_start is not null and actual_finish >= actual_start)
  );

-- Includes pre-existing active items whose actual start was never recorded.
-- The unique index is the final concurrency boundary for one job per line.
create unique index production_orders_one_active_per_line
  on public.production_orders(factory_id,line_id)
  where status = 'active' and line_id is not null;

create function private.guard_product_execution()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'planned' or new.actual_start is not null
      or new.actual_finish is not null then
      raise exception 'execution_use_command';
    end if;
    return new;
  end if;

  if (old.status,old.actual_start,old.actual_finish) is not distinct from
     (new.status,new.actual_start,new.actual_finish) then return new; end if;

  -- Keep the pre-existing generic cancellation path for unstarted work.
  if old.status = 'planned' and new.status = 'cancelled'
    and old.actual_start is null and new.actual_start is null
    and old.actual_finish is null and new.actual_finish is null then
    return new;
  end if;

  if (old.line_id,old.start_time,old.expected_finish) is distinct from
     (new.line_id,new.start_time,new.expected_finish) then
    raise exception 'execution_use_command';
  end if;

  if old.status = 'planned' and new.status = 'active'
    and old.actual_start is null and old.actual_finish is null
    and new.actual_start is not null and new.actual_finish is null then
    return new;
  end if;
  if old.status = 'active' and new.status = 'completed'
    and old.actual_start is not null and old.actual_finish is null
    and new.actual_start = old.actual_start and new.actual_finish is not null then
    return new;
  end if;
  raise exception 'execution_use_command';
end;
$$;
revoke all on function private.guard_product_execution() from public,anon,authenticated;
create trigger guard_product_execution_insert before insert on public.production_orders
  for each row execute function private.guard_product_execution();
create trigger guard_product_execution_update
  before update of status,actual_start,actual_finish on public.production_orders
  for each row execute function private.guard_product_execution();

create function public.start_product_item(factory uuid,item uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target public.production_orders%rowtype;
  first_item uuid;
begin
  perform private.require_permission(factory,'orders','edit');
  select * into target from public.production_orders
    where factory_id= factory and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status <> 'planned' or target.actual_start is not null
    or target.actual_finish is not null or target.produced_quantity > 0 then
    raise exception 'execution_already_started';
  end if;
  if target.line_id is null or target.start_time is null
    or target.expected_finish is null or target.expected_finish <= target.start_time
    or not exists(select 1 from public.production_lines l
      where l.factory_id=factory and l.id=target.line_id and not l.archived) then
    raise exception 'execution_plan_required';
  end if;

  -- Serialize competing starts on this line before reading its queue.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target.line_id::text,0));
  if exists(select 1 from public.production_orders other
    where other.factory_id=factory and other.line_id=target.line_id
      and other.status='active') then
    raise exception 'execution_line_busy';
  end if;
  select other.id into first_item from public.production_orders other
    where other.factory_id=factory and other.line_id=target.line_id
      and other.status='planned' and other.actual_start is null
      and other.actual_finish is null and other.start_time is not null
      and other.expected_finish > other.start_time
    order by other.start_time,other.id limit 1;
  if first_item is distinct from item then
    raise exception 'execution_out_of_sequence';
  end if;

  update public.production_orders set status='active',actual_start=pg_catalog.clock_timestamp()
    where factory_id=factory and id=item;
  return item;
end;
$$;

create function public.finish_product_item(factory uuid,item uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target public.production_orders%rowtype;
begin
  perform private.require_permission(factory,'orders','edit');
  select * into target from public.production_orders
    where factory_id=factory and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status <> 'active' or target.actual_start is null
    or target.actual_finish is not null then
    raise exception 'execution_not_running';
  end if;
  update public.production_orders set status='completed',
    actual_finish=pg_catalog.clock_timestamp()
    where factory_id=factory and id=item;
  return item;
end;
$$;

revoke all on function public.start_product_item(uuid,uuid),
  public.finish_product_item(uuid,uuid) from public,anon,authenticated;
grant execute on function public.start_product_item(uuid,uuid),
  public.finish_product_item(uuid,uuid) to authenticated;
