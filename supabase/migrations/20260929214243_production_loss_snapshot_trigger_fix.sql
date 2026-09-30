-- Trigger records have different columns. Branch before accessing them so a
-- downtime insert never reads work_center-only fields.
create or replace function private.capture_production_loss_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare changed_at timestamptz;
begin
  if tg_op='DELETE' then
    perform private.capture_production_loss_context(old.factory_id,clock_timestamp());
    return old;
  end if;
  if tg_table_name='downtime_events' then
    if tg_op='INSERT' then changed_at:=new.started_at;
    else changed_at:=new.ended_at; end if;
  elsif tg_table_name='work_centers' then
    if tg_op='UPDATE' and old.status is distinct from new.status then
      changed_at:=new.updated_at;
    else changed_at:=clock_timestamp(); end if;
  elsif tg_table_name='production_transfers' then
    if tg_op='INSERT' then changed_at:=new.created_at;
    else changed_at:=clock_timestamp(); end if;
  else
    changed_at:=clock_timestamp();
  end if;
  perform private.capture_production_loss_context(new.factory_id,changed_at);
  return new;
end;
$$;
