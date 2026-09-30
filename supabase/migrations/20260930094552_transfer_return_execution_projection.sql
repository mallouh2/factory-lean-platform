-- Re-project after an explicit transfer end, including same-line borrowing
-- where the captured previous order equals the borrowed order. Physical state
-- and transfer ending rules remain owned by the existing return command.
create function private.project_transfer_execution()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.factory_id::text||':structure',0));
  perform 1 from public.work_centers where factory_id=new.factory_id
    and id=new.alternative_id for update;
  update public.work_centers c
    set order_id=private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id),
        updated_at=pg_catalog.clock_timestamp()
    where c.factory_id=new.factory_id and c.id=new.alternative_id
      and c.order_id is distinct from
        private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id);
  return new;
end;
$$;
revoke all on function private.project_transfer_execution() from public,anon,authenticated;
create trigger execution_assignment after update of ended_at on public.production_transfers
  for each row when (old.ended_at is null and new.ended_at is not null)
  execute function private.project_transfer_execution();
