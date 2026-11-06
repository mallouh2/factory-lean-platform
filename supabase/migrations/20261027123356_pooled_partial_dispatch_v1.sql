begin;
-- Pool is existing UNATTRIBUTED stock only. Never choose a physical batch.
create function private.pooled_dispatch_available(f uuid,l uuid) returns numeric
language sql stable set search_path='' as $$
 select case when s.status<>'approved' or private.output_pool_held(f,x.product_id,x.unit) then 0 else
 greatest(least(x.quantity-x.dispatched_quantity,coalesce(r.quantity,0)-coalesce((select sum(quantity)from public.finished_goods_source_reservations a where a.factory_id=f and a.sales_line_id=x.id),0),coalesce(u.quantity,0)),0) end
 from public.sales_order_lines x join public.sales_orders s on s.factory_id=f and s.id=x.order_id
 left join public.finished_goods_reservations r on r.factory_id=f and r.line_id=x.id
 left join private.finished_goods_unattributed u on u.factory_id=f and u.product_id=x.product_id and u.unit=x.unit where x.factory_id=f and x.id=l
$$;
create function public.pooled_dispatch_context(factory uuid,sales_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'warehouse','view');
 if not exists(select 1 from public.sales_orders where factory_id=factory and id=sales_order) then raise exception 'fulfillment_state';end if;
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'ordered',trim_scale(l.quantity)::text,'reserved',trim_scale(coalesce(r.quantity,0))::text,'dispatched',trim_scale(l.dispatched_quantity)::text,'outstanding',trim_scale(l.quantity-l.dispatched_quantity)::text,'dispatchable',trim_scale(private.pooled_dispatch_available(factory,l.id))::text,'source_assigned',trim_scale(coalesce((select sum(quantity)from public.finished_goods_source_reservations a where a.factory_id=factory and a.sales_line_id=l.id),0))::text)order by l.id),'[]')from public.sales_order_lines l left join public.finished_goods_reservations r on r.factory_id=factory and r.line_id=l.id where l.factory_id=factory and l.order_id=sales_order));
end$$;
create function public.dispatch_sales_quantity(factory uuid,sales_order uuid,line uuid,quantity numeric,request_id uuid) returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare old uuid;l public.sales_order_lines;s public.sales_orders;p jsonb:=jsonb_build_object('order',sales_order,'line',line,'quantity',quantity);result uuid;begin
 perform private.require_permission(factory,'warehouse','issue');
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 old:=private.fulfillment_retry(factory,request_id,'pooled_partial_dispatch',p);if old is not null then return old;end if;
 perform private.require_permission(factory,'warehouse','issue');
 select * into s from public.sales_orders where factory_id=factory and id=sales_order for update;
 select * into l from public.sales_order_lines where factory_id=factory and order_id=sales_order and id=line for update;
 if s.id is null or s.status<>'approved' or l.id is null then raise exception 'fulfillment_state';end if;
 if quantity is null or quantity<=0 or quantity::text in ('NaN','Infinity','-Infinity') or (l.unit='piece' and quantity<>trunc(quantity)) then raise exception 'fulfillment_invalid';end if;
 if quantity>private.pooled_dispatch_available(factory,line) then raise exception 'pooled_dispatch_unavailable';end if;
 -- Release only this line's unassigned reservation, retaining identified assignments.
 perform private.reserve_finished(factory,line,-quantity);
 update public.finished_goods_balances set on_hand=on_hand-quantity where factory_id=factory and product_id=l.product_id and unit=l.unit and on_hand>=quantity;
 if not found then raise exception 'fulfillment_not_ready';end if;
 -- Existing trigger consumes pool and writes source_id NULL allocation exactly once.
 insert into public.finished_goods_movements(factory_id,product_id,unit,kind,stock_delta,sales_line_id,created_by)
 values(factory,l.product_id,l.unit,'dispatch',-quantity,line,auth.uid()) returning id into result;
 update public.sales_order_lines set dispatched_quantity=dispatched_quantity+dispatch_sales_quantity.quantity where factory_id=factory and id=line;
 if not exists(select 1 from public.sales_order_lines where factory_id=factory and order_id=sales_order and dispatched_quantity<sales_order_lines.quantity)
 then update public.sales_orders set status='completed' where factory_id=factory and id=sales_order;end if;
 perform private.replenish_finished(factory,l.product_id);
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'pooled_partial_dispatch',p,result,clock_timestamp());return result;
end$$;
revoke all on function private.pooled_dispatch_available(uuid,uuid),public.pooled_dispatch_context(uuid,uuid),public.dispatch_sales_quantity(uuid,uuid,uuid,numeric,uuid) from public,anon,authenticated,service_role;
grant execute on function public.pooled_dispatch_context(uuid,uuid),public.dispatch_sales_quantity(uuid,uuid,uuid,numeric,uuid) to authenticated;
commit;
