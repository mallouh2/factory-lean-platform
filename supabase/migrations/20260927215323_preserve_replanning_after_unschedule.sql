-- Remember that an item was planned even after its current line and times are cleared.
alter table public.production_orders
  add column planning_ever_scheduled boolean not null default false;
update public.production_orders o set planning_ever_scheduled=true
where exists (
  select 1 from public.production_plan_revisions r
  where r.factory_id=o.factory_id and r.item_id=o.id and r.after_line_id is not null
);

create or replace function private.record_plan_revision()
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
  if not old.planning_ever_scheduled then
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
  if new.line_id is not null then new.planning_ever_scheduled := true; end if;
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
