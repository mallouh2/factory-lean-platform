begin;
-- Runs only when the protected disposition creates a new immutable work link.
-- Existing priorities and subsequent authorized overrides are never rewritten.
create function private.output_shortage_priority() returns trigger
language plpgsql set search_path='' as $$begin
 if new.choice in ('COMPLETE','REPLACE') and new.demand_item_id is not null and exists(
 select 1 from public.production_orders d where d.factory_id=new.factory_id and d.id=new.demand_item_id
 and d.target_quantity>private.output_demand_received(new.factory_id,d.id)) then
 update public.production_requests r set priority='high' from public.production_orders o
 where o.factory_id=new.factory_id and o.id=new.item_id and r.factory_id=new.factory_id and r.id=o.request_id and r.priority='normal';
 end if;return new;
end$$;
create trigger output_shortage_priority after insert on private.manufactured_completion_work
for each row execute function private.output_shortage_priority();
revoke all on function private.output_shortage_priority() from public,anon,authenticated,service_role;
commit;
