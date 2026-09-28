-- Planning changes are recorded at the table boundary, including generic order writes.
alter table public.production_orders
  add column planning_locked_at timestamptz,
  add column planning_locked_by uuid references auth.users,
  add column planning_locked_by_name text,
  add constraint planning_lock_pair check (
    (planning_locked_at is null and planning_locked_by is null and planning_locked_by_name is null)
    or (planning_locked_at is not null and planning_locked_by is not null)
  );

create table public.production_plan_revisions (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null,
  item_id uuid not null,
  revision_no integer not null check (revision_no > 0),
  event text not null check (event in ('baseline','initial','replanned','unscheduled')),
  before_line_id uuid,
  before_start timestamptz,
  before_finish timestamptz,
  after_line_id uuid,
  after_start timestamptz,
  after_finish timestamptz,
  reason_code text check (reason_code in (
    'priority_change','customer_request','machine_unavailable','maintenance',
    'material_delay','capacity_conflict','quality_issue','management_decision','other'
  )),
  reason_note text check (length(reason_note) <= 240),
  changed_by uuid references auth.users,
  changed_by_name text,
  changed_at timestamptz not null default now(),
  unique (factory_id,item_id,revision_no),
  foreign key (factory_id,item_id) references public.production_orders(factory_id,id),
  foreign key (factory_id,before_line_id) references public.production_lines(factory_id,id),
  foreign key (factory_id,after_line_id) references public.production_lines(factory_id,id),
  check (event not in ('replanned','unscheduled') or reason_code is not null)
);
create index production_plan_revisions_item on public.production_plan_revisions(factory_id,item_id,revision_no);
alter table public.production_plan_revisions enable row level security;
create policy read_authorized on public.production_plan_revisions for select to authenticated
  using (private.has_permission(factory_id,'orders','view'));
grant select on public.production_plan_revisions to authenticated;

-- Existing schedules have an unknown original actor and time. Record an honest baseline.
insert into public.production_plan_revisions
  (factory_id,item_id,revision_no,event,after_line_id,after_start,after_finish)
select factory_id,id,1,'baseline',line_id,start_time,expected_finish
from public.production_orders
where line_id is not null or start_time is not null or expected_finish is not null;

create function private.record_plan_revision()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  reason text := nullif(current_setting('app.plan_reason',true),'');
  note text := nullif(btrim(current_setting('app.plan_note',true)),'');
  kind text;
  actor_name text;
  next_revision integer;
begin
  if (old.line_id,old.start_time,old.expected_finish) is not distinct from
     (new.line_id,new.start_time,new.expected_finish) then return new; end if;
  if old.planning_locked_at is not null then raise exception 'planning_locked'; end if;
  if old.status <> 'planned' or old.produced_quantity > 0 or
    (old.start_time is not null and old.start_time <= now()) then
    raise exception 'planning_already_started';
  end if;
  if old.line_id is null and old.start_time is null and old.expected_finish is null then
    kind := 'initial';
  else
    if reason not in ('priority_change','customer_request','machine_unavailable','maintenance',
      'material_delay','capacity_conflict','quality_issue','management_decision','other')
      or reason is null or (reason='other' and note is null) then
      raise exception 'planning_reason_required';
    end if;
    kind := case when new.line_id is null then 'unscheduled' else 'replanned' end;
  end if;
  if (new.line_id is null and (new.start_time is not null or new.expected_finish is not null)) or
     (new.line_id is not null and (new.start_time is null or new.expected_finish is null)) then
    raise exception 'planning_invalid_start';
  end if;
  select display_name into actor_name from public.memberships
    where factory_id=old.factory_id and user_id=auth.uid();
  select coalesce(max(revision_no),0)+1 into next_revision
    from public.production_plan_revisions
    where factory_id=old.factory_id and item_id=old.id;
  insert into public.production_plan_revisions
    (factory_id,item_id,revision_no,event,before_line_id,before_start,before_finish,
      after_line_id,after_start,after_finish,reason_code,reason_note,changed_by,changed_by_name)
  values (old.factory_id,old.id,next_revision,kind,old.line_id,old.start_time,old.expected_finish,
    new.line_id,new.start_time,new.expected_finish,case when kind='initial' then null else reason end,
    case when kind='initial' then null else note end,auth.uid(),actor_name);
  return new;
end;
$$;
revoke all on function private.record_plan_revision() from public,anon,authenticated;
create trigger record_plan_revision before update of line_id,start_time,expected_finish
  on public.production_orders for each row execute function private.record_plan_revision();

-- The existing planning function retains calendar, rate, setup and overlap validation.
-- A failure of either history or plan update rolls back the entire RPC.
create function public.revise_product_plan(factory uuid,item uuid,target_line uuid,
  planned_start timestamptz,reason_code text,reason_note text)
returns uuid language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(factory,'orders','edit');
  if reason_code not in ('priority_change','customer_request','machine_unavailable','maintenance',
    'material_delay','capacity_conflict','quality_issue','management_decision','other')
    or reason_code is null or (reason_code='other' and nullif(btrim(reason_note),'') is null)
    or length(reason_note)>240 then raise exception 'planning_reason_required'; end if;
  perform set_config('app.plan_reason',reason_code,true);
  perform set_config('app.plan_note',coalesce(reason_note,''),true);
  return private.plan_product_item(factory,item,target_line,planned_start);
end;
$$;
revoke all on function public.revise_product_plan(uuid,uuid,uuid,timestamptz,text,text)
  from public,anon,authenticated;
grant execute on function public.revise_product_plan(uuid,uuid,uuid,timestamptz,text,text)
  to authenticated;

create function public.set_plan_lock(factory uuid,item uuid,locked boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  target public.production_orders%rowtype;
  actor_name text;
begin
  perform private.require_permission(factory,'orders','edit');
  select * into target from public.production_orders
    where factory_id=factory and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status <> 'planned' or target.produced_quantity > 0 or
     target.line_id is null or target.start_time is null or target.start_time<=now() then
    raise exception 'planning_already_started'; end if;
  if locked is null then raise exception 'invalid_input'; end if;
  if locked and target.planning_locked_at is null then
    select display_name into actor_name from public.memberships
      where factory_id=factory and user_id=auth.uid();
    update public.production_orders set planning_locked_at=now(),
      planning_locked_by=auth.uid(),planning_locked_by_name=actor_name
      where factory_id=factory and id=item;
  elsif not locked and target.planning_locked_at is not null then
    update public.production_orders set planning_locked_at=null,
      planning_locked_by=null,planning_locked_by_name=null
      where factory_id=factory and id=item;
  end if;
  return item;
end;
$$;
revoke all on function public.set_plan_lock(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.set_plan_lock(uuid,uuid,boolean) to authenticated;
