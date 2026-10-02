-- An allocated incoming quantity cannot be silently reduced/substituted by a generic Product Item edit.
-- Explicit cancellation still uses the existing deferred release/reallocation path.
create function private.guard_sales_production_commitment() returns trigger language plpgsql security definer set search_path='' as $$declare committed numeric;begin
 perform private.fulfillment_lock(new.factory_id);
 select coalesce(sum(a.quantity),0) into committed from public.sales_incoming_allocations a where a.factory_id=old.factory_id and a.item_id=old.id;
 if committed>0 and new.status<>'cancelled' and
 (new.product_id is distinct from old.product_id or new.unit is distinct from old.unit or greatest(new.target_quantity-new.good_quantity,0)<committed)
 then raise exception 'fulfillment_stock_committed';end if;
 return new;
end$$;
revoke all on function private.guard_sales_production_commitment() from public,anon,authenticated;
create trigger sales_production_commitment before update of target_quantity,product_id,unit on public.production_orders
 for each row execute function private.guard_sales_production_commitment();
