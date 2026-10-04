-- Material units are existing configured TEXT truth, including legacy unit-count stock.
-- Every receipt still matches its exact material unit; finished goods stay meter/piece.
create or replace function public.receive_warehouse_stock(factory uuid,item uuid,item_type text,unit text,quantity numeric,source text,reference text default '',note text default '',request_id uuid default gen_random_uuid()) returns uuid
 language plpgsql security definer set search_path='' as $$declare result uuid;old uuid;p jsonb;begin
 perform private.require_permission(factory,'warehouse','edit');
 p:=jsonb_build_object('item',item,'type',item_type,'unit',unit,'quantity',quantity,'source',source,'reference',reference,'note',note);
 old:=private.fulfillment_retry(factory,request_id,'receive_stock',p);if old is not null then return old;end if;
 if quantity is null or quantity<=0 or quantity::text in ('NaN','Infinity','-Infinity') or source is null or source not in ('opening_balance','external_receipt')
  or unit is null or length(btrim(unit)) not between 1 and 50 or length(coalesce(reference,''))>200 or length(coalesce(note,''))>2000 then raise exception 'fulfillment_invalid';end if;
 result:=gen_random_uuid();
 if item_type='finished' then
  if not exists(select 1 from public.products p where p.factory_id=factory and p.id=item and p.stage='finished' and p.stock_unit=receive_warehouse_stock.unit) then raise exception 'fulfillment_stock_identity';end if;
  if source='opening_balance' and exists(select 1 from public.finished_goods_movements where factory_id=factory and product_id=item and finished_goods_movements.unit=receive_warehouse_stock.unit and (stock_delta<>0 or kind='opening_balance')) then raise exception 'stock_opening_exists';end if;
  perform private.finished_balance(factory,item,unit);
  update public.finished_goods_balances set on_hand=on_hand+quantity where factory_id=factory and product_id=item and finished_goods_balances.unit=receive_warehouse_stock.unit;
  insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by) values(result,factory,item,unit,source,quantity,coalesce(note,''),coalesce(reference,''),auth.uid());
  -- Receive physical stock without creating production or replacing committed incoming work.
  perform private.reserve_received_stock(factory,item,unit);
 elsif item_type='material' then
  if not exists(select 1 from public.materials m where m.factory_id=factory and m.id=item and m.unit=receive_warehouse_stock.unit) then raise exception 'fulfillment_stock_identity';end if;
  if source='opening_balance' and exists(select 1 from public.inventory_transactions where factory_id=factory and material_id=item) then raise exception 'stock_opening_exists';end if;
  insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by) values(result,factory,item,quantity,source,unit,coalesce(reference,''),coalesce(note,''),auth.uid());
 else raise exception 'fulfillment_invalid';end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'receive_stock',p,result,clock_timestamp());return result;
end$$;
