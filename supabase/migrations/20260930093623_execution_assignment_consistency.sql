-- A line's active Product Item is execution truth. order_id is its managed
-- compatibility projection; an OPEN transfer takes precedence for a borrower.
-- No historical assignments are mass-repaired by this migration.
create function private.execution_center_order(f uuid,w uuid,l uuid,independent_order uuid)
returns uuid language sql stable security definer set search_path='' as $$
  select coalesce(
    (select t.order_id from public.production_transfers t
      where t.factory_id=f and t.alternative_id=w and t.ended_at is null),
    case when l is not null then
      (select o.id from public.production_orders o
        where o.factory_id=f and o.line_id=l and o.status='active')
    else
      (select o.id from public.production_orders o
        where o.factory_id=f and o.id=independent_order and o.status='active')
    end
  );
$$;
revoke all on function private.execution_center_order(uuid,uuid,uuid,uuid)
  from public,anon,authenticated;

create function private.project_center_execution()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- a_lock_structure runs first, using the same factory lock as execution RPCs.
  new.order_id:=private.execution_center_order(
    new.factory_id,new.id,new.line_id,new.order_id);
  return new;
end;
$$;
revoke all on function private.project_center_execution() from public,anon,authenticated;
create trigger b_project_center_execution before insert or update on public.work_centers
  for each row execute function private.project_center_execution();

create function private.project_item_execution()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status is not distinct from new.status then return new; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.factory_id::text||':structure',0));
  perform 1 from public.work_centers c
    where c.factory_id=new.factory_id
      and (c.line_id=new.line_id or c.order_id=new.id)
    order by c.id for update;
  update public.work_centers c
    set order_id=private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id),
        updated_at=pg_catalog.clock_timestamp()
    where c.factory_id=new.factory_id
      and (c.line_id=new.line_id or c.order_id=new.id)
      and c.order_id is distinct from
        private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id);
  return new;
end;
$$;
revoke all on function private.project_item_execution() from public,anon,authenticated;
-- Before loss_context_plan: captured contexts see the synchronized assignment.
create trigger execution_assignment after update of status on public.production_orders
  for each row execute function private.project_item_execution();

create or replace function public.start_product_item(factory uuid,item uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target public.production_orders%rowtype;
  first_item uuid;
begin
  perform private.require_permission(factory,'orders','edit');
  -- Lock before item/center rows, shared with transfer and layout operations.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(factory::text||':structure',0));
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

create or replace function public.finish_product_item(factory uuid,item uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target public.production_orders%rowtype;
begin
  perform private.require_permission(factory,'orders','edit');
  -- Lock before item/center rows, shared with transfer and layout operations.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(factory::text||':structure',0));
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

create or replace function private.transfer_production(f uuid,w uuid,a uuid,n text)
returns uuid language plpgsql security definer set search_path='' as $$
declare o uuid;d uuid;i uuid;previous_order uuid;
begin
 perform private.require_permission(f,'centers','edit');
 perform private.require_permission(f,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from public.work_centers where factory_id=f and id in (w,a) order by id for update;
 select order_id into o from public.work_centers
 where id=w and factory_id=f and not archived and status='stopped';
 select id into d from public.downtime_events
 where work_center_id=w and factory_id=f and ended_at is null;
 if o is null or d is null or not exists(
  select 1 from public.production_orders where id=o and status='active'
 ) then raise exception 'invalid_order'; end if;
 if exists(select 1 from public.production_transfers
   where factory_id=f and original_id=w and ended_at is null)
 then raise exception 'transfer_already_active'; end if;
 if not exists(
   select 1 from public.work_center_alternatives
   where factory_id=f and work_center_id=w and alternative_id=a
 ) or not exists(
   select 1 from public.work_centers c
   left join public.production_lines home
     on home.id=c.line_id and home.factory_id=f and not home.archived
   where c.id=a and c.factory_id=f and not c.archived and c.status='idle'
     and (c.order_id is null or c.order_id=o or home.paused_at is not null)
 ) or (select category_id from public.work_centers where id=w)
      is distinct from (select category_id from public.work_centers where id=a)
   or not exists(
     select 1 from public.work_center_capabilities cap
     join public.production_orders job on job.factory_id=cap.factory_id
       and job.product_id=cap.product_id
     where cap.factory_id=f and cap.work_center_id=a and job.id=o
       and cap.rate>0 and cap.rate_unit=job.unit
   )
   or exists(
     select 1 from public.production_transfers
     where factory_id=f and alternative_id=a and ended_at is null
   )
 then raise exception 'incompatible_alternative'; end if;
 select order_id into previous_order
 from public.work_centers where id=a and factory_id=f;
 insert into public.production_transfers(
  factory_id,original_id,alternative_id,order_id,downtime_id,reason,
  created_by,alternative_previous_order_id,alternative_order_captured
 ) values(f,w,a,o,d,n,auth.uid(),previous_order,true) returning id into i;
 update public.work_centers set order_id=o where id=a;
 perform private.change_status(f,a,'running',null,null,n,null,null,null,false);
 update public.downtime_events set alternative_id=a,transferred=true where id=d;
 return i;
end$$;

