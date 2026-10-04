-- Enforce configured stock units even when a draft predates stock configuration.
create function private.guard_sales_stock_unit() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.fulfillment_lock(new.factory_id);
 if tg_table_name='sales_order_lines' then
  if exists(select 1 from public.products p where p.factory_id=new.factory_id and p.id=new.product_id and p.stock_unit is not null and p.stock_unit is distinct from new.unit)
  then raise exception 'fulfillment_stock_identity';end if;
 else
  if new.stock_unit is not null and new.stock_unit is distinct from old.stock_unit and exists(
   select 1 from public.sales_order_lines l join public.sales_orders s on s.id=l.order_id
   where l.factory_id=new.factory_id and l.product_id=new.id and l.unit<>new.stock_unit and s.status in ('draft','approved'))
  then raise exception 'fulfillment_stock_identity';end if;
 end if;return new;end$$;
create trigger sales_stock_unit_guard before insert or update of product_id,unit on public.sales_order_lines for each row execute function private.guard_sales_stock_unit();
create trigger product_sales_unit_guard before update of stock_unit on public.products for each row execute function private.guard_sales_stock_unit();
revoke all on function private.guard_sales_stock_unit() from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.allocate_sales_line(f uuid, line uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare l public.sales_order_lines;s public.sales_orders;need numeric;take numeric;stock numeric;candidate record;i uuid;begin
 select * into l from public.sales_order_lines where factory_id=f and id=line for update;
 if exists(select 1 from public.products p where p.factory_id=f and p.id=l.product_id and p.stock_unit is not null and p.stock_unit is distinct from l.unit) then raise exception 'fulfillment_stock_identity';end if;
 select * into s from public.sales_orders where factory_id=f and id=l.order_id;
 if s.status<>'approved' then return;end if;
 perform private.finished_balance(f,l.product_id,l.unit);
 select greatest(l.quantity-l.dispatched_quantity-coalesce(r.quantity,0)-(select coalesce(sum(quantity),0) from public.sales_incoming_allocations where factory_id=f and line_id=l.id),0)
 into need from (select 1) dummy left join public.finished_goods_reservations r on r.factory_id=f and r.line_id=l.id;
 select on_hand-reserved into stock from public.finished_goods_balances where factory_id=f and product_id=l.product_id and unit=l.unit for update;
 take:=least(need,stock);perform private.reserve_finished(f,l.id,take);need:=need-take;
 for candidate in select o.*,o.remaining_quantity-(select coalesce(sum(a.quantity),0) from public.sales_incoming_allocations a where a.item_id=o.id) free_quantity
 from public.production_orders o join public.production_requests r on r.id=o.request_id
 where o.factory_id=f and o.product_id=l.product_id and o.unit=l.unit and o.status in ('planned','active')
 and ((r.sales_order_line_id=l.id and o.status='active') or
 (o.line_id is not null and o.start_time is not null and o.expected_finish is not null
 and (s.requested_delivery is null or o.expected_finish<=s.requested_delivery)
 and (r.request_type is null or r.request_type='STOCK_REPLENISHMENT'))) order by o.expected_finish,o.id for update of o loop
 take:=least(need,greatest(candidate.free_quantity,0));
 if take>0 then insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,l.id,candidate.id,take)
 on conflict(factory_id,line_id,item_id) do update set quantity=public.sales_incoming_allocations.quantity+excluded.quantity;need:=need-take;end if;
 exit when need=0;end loop;
 if need>0 and exists(select 1 from public.products p where p.factory_id=f and p.id=l.product_id and p.supply_source='MANUFACTURED') then
 i:=private.fulfillment_production(f,l.product_id,l.unit,need,'SALES_PRODUCTION',l.id,s.requested_delivery);
 insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,l.id,i,need);
 end if;
end$function$;
