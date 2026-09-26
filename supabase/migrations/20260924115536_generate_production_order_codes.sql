-- The database owns the order number, including for callers of the existing
-- generic save_record RPC. Sequence values are global and safe under concurrency.
create sequence private.production_order_number_seq;

create function private.assign_production_order_code()
returns trigger language plpgsql set search_path = '' as $$
declare order_number text;
begin
  loop
    order_number := nextval('private.production_order_number_seq'::regclass)::text;
    new.code := 'PO-' || lpad(order_number, greatest(7, length(order_number)), '0');
    exit when not exists (
      select 1 from public.production_orders o
      where o.factory_id = new.factory_id and o.code = new.code
    );
  end loop;
  return new;
end;
$$;

create trigger assign_production_order_code
before insert on public.production_orders
for each row execute function private.assign_production_order_code();
