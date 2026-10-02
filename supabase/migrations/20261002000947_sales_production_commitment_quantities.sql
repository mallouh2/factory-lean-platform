-- Generated Good is computed after BEFORE triggers; compare authoritative base quantities.
create or replace function private.guard_sales_production_commitment() returns trigger language plpgsql security definer set search_path='' as $$declare committed numeric;begin
 perform private.fulfillment_lock(new.factory_id);
 select coalesce(sum(a.quantity),0) into committed from public.sales_incoming_allocations a where a.factory_id=old.factory_id and a.item_id=old.id;
 if committed>0 and new.status<>'cancelled' and
 (new.product_id is distinct from old.product_id or new.unit is distinct from old.unit or greatest(new.target_quantity-(new.produced_quantity-new.rejected_quantity),0)<committed)
 then raise exception 'fulfillment_stock_committed';end if;
 return new;
end$$;

