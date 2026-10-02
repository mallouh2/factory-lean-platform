-- Correct the renamed receipt allocation row-lock alias.
create or replace function private.capture_finished_good() returns trigger language plpgsql security definer set search_path='' as $$
declare job public.production_orders;received numeric;delta numeric;leftover numeric;take numeric;a record;correction uuid;begin
 select * into job from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 if new.unit not in ('meter','piece') or new.unit is null or not exists(select 1 from public.products where id=job.product_id and stage='finished') then return new;end if;
 perform private.fulfillment_lock(new.factory_id);
 select received_good into received from public.finished_goods_entry_receipts where factory_id=new.factory_id and entry_id=new.id for update;
 -- Historical entries are not warehouse receipts. Editing one must not fabricate an opening stock balance.
 if tg_op='UPDATE' and not found then return new;end if;
 delta:=coalesce(new.effective_good,0)-coalesce(received,0);
 if delta=0 then
 if tg_op='INSERT' then insert into public.finished_goods_entry_receipts values(new.factory_id,new.id,0);end if;
 return new;end if;
 perform private.finished_balance(new.factory_id,job.product_id,new.unit);
 if delta<0 and exists(select 1 from public.finished_goods_balances where factory_id=new.factory_id and product_id=job.product_id and unit=new.unit and on_hand+delta<reserved)
 then raise exception 'fulfillment_stock_committed';end if;
 update public.finished_goods_balances set on_hand=on_hand+delta where factory_id=new.factory_id and product_id=job.product_id and unit=new.unit;
 insert into public.finished_goods_entry_receipts values(new.factory_id,new.id,new.effective_good)
 on conflict(factory_id,entry_id) do update set received_good=excluded.received_good;
 insert into public.finished_goods_movements(factory_id,product_id,unit,kind,stock_delta,entry_id,reason,created_by)
 values(new.factory_id,job.product_id,new.unit,case when tg_op='INSERT' then 'production_receipt' else 'production_correction' end,delta,new.id,
 case when tg_op='UPDATE' then (select c.reason from public.production_entry_corrections c where c.entry_id=new.id order by c.created_at desc,c.id desc limit 1) end,auth.uid());
 leftover:=greatest(delta,0);
 for a in select t_a.id,t_a.line_id,t_a.quantity from public.sales_incoming_allocations t_a
 join public.sales_order_lines l on l.id=t_a.line_id join public.sales_orders s on s.id=l.order_id
 where t_a.factory_id=new.factory_id and t_a.item_id=job.id and t_a.quantity>0 and s.status='approved' order by s.created_at,t_a.id for update of t_a loop
 take:=least(leftover,a.quantity);exit when take<=0;
 perform private.reserve_finished(new.factory_id,a.line_id,take);
 update public.sales_incoming_allocations set quantity=quantity-take,received_quantity=received_quantity+take where id=a.id;
 leftover:=leftover-take;end loop;
 return new;
end$$;

