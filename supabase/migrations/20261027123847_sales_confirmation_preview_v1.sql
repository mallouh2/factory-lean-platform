begin;
-- The allocator and advisory confirmation reader share candidate eligibility.
create function private.sales_incoming_candidates(f uuid,target uuid)
returns table(item_id uuid,free_quantity numeric) language sql stable set search_path='' as $$
 select o.id,private.quality_production_remaining(f,o.id)-(select coalesce(sum(a.quantity),0)from public.sales_incoming_allocations a where a.item_id=o.id)
 from public.sales_order_lines l join public.sales_orders s on s.factory_id=f and s.id=l.order_id
 join public.production_orders o on o.factory_id=f and o.product_id=l.product_id and o.unit=l.unit
 join public.production_requests r on r.id=o.request_id
 where l.factory_id=f and l.id=target and not exists(select 1 from private.manufactured_completion_work w where w.factory_id=f and w.item_id=o.id and w.demand_item_id is not null)
 and (o.status in ('planned','active') or private.output_pending(o.factory_id,o.id)>0)
 and ((r.sales_order_line_id=l.id and o.status='active') or (o.line_id is not null and o.start_time is not null and o.expected_finish is not null
 and (s.requested_delivery is null or o.expected_finish<=s.requested_delivery) and (r.request_type is null or r.request_type='STOCK_REPLENISHMENT')))
 order by o.expected_finish,o.id
$$;
do $patch$declare b text;a integer;z integer;begin
 b:=pg_get_functiondef('private.allocate_sales_line(uuid,uuid)'::regprocedure);
 a:=position('for candidate in select o.*' in b);z:=position('for update of o loop' in b);
 if a=0 or z<=a then raise exception 'Sales allocation candidate contract changed';end if;
 b:=substring(b from 1 for a-1)||'for candidate in select o.*,c.free_quantity from private.sales_incoming_candidates(f,l.id)c join public.production_orders o on o.factory_id=f and o.id=c.item_id order by o.expected_finish,o.id for update of o loop'||substring(b from z+length('for update of o loop'));
 execute b;
end$patch$;
create function public.sales_confirmation_preview(factory uuid,sales_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.sales_orders;l record;c record;stock numeric;take numeric;need numeric;incoming numeric;key text;stocks jsonb:='{}';candidates jsonb:='{}';rows jsonb:='[]';begin
 perform private.require_permission(factory,'sales_orders','view');perform private.require_permission(factory,'sales_orders','approve');
 select * into s from public.sales_orders where factory_id=factory and id=sales_order;
 if s.id is null or s.status<>'draft' then raise exception 'fulfillment_state';end if;
 for l in select * from public.sales_order_lines where factory_id=factory and order_id=sales_order order by id loop
  key:=l.product_id::text||'|'||l.unit;
  stock:=coalesce((stocks->>key)::numeric,private.output_stock_free(factory,l.product_id,l.unit));
  take:=least(l.quantity,greatest(stock,0));need:=l.quantity-take;incoming:=0;stocks:=jsonb_set(stocks,array[key],to_jsonb(stock-take));
  for c in select * from private.sales_incoming_candidates(factory,l.id) loop
   stock:=least(need,greatest(c.free_quantity-coalesce((candidates->>c.item_id::text)::numeric,0),0));
   incoming:=incoming+stock;need:=need-stock;candidates:=jsonb_set(candidates,array[c.item_id::text],to_jsonb(coalesce((candidates->>c.item_id::text)::numeric,0)+stock));exit when need=0;
  end loop;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',l.id,'unit',l.unit,'ordered',trim_scale(l.quantity)::text,'available',trim_scale(take)::text,'to_reserve',trim_scale(take)::text,'incoming',trim_scale(incoming)::text,'additional',trim_scale(need)::text));
 end loop;
 return jsonb_build_object('advisory',true,'rows',rows);
end$$;
revoke all on function private.sales_incoming_candidates(uuid,uuid),public.sales_confirmation_preview(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.sales_confirmation_preview(uuid,uuid) to authenticated;
commit;
