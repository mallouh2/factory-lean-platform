-- Forward read correction: draft availability, distinct earliest/current-plan forecasts,
-- and one detailed calculation per linked Sales Order in the bounded production context.
create or replace function private.sales_order_detail(f uuid,sales uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare so public.sales_orders;sl record;allocation record;lines jsonb:='[]';line_estimate timestamptz;line_earliest timestamptz;
 earliest timestamptz:=now();estimated timestamptz:=now();plan jsonb;early_plan jsonb;virtual jsonb:='[]';early_virtual jsonb:='[]';
 unknown boolean:=false;early_unknown boolean:=false;target timestamptz;all_ready boolean:=true;complete boolean;ready boolean;
 reserved_qty numeric;incoming_qty numeric;needed numeric;state text;risk text;begin
 select * into so from public.sales_orders where factory_id=f and id=sales;if not found then return null;end if;
 select ((coalesce(so.promised_delivery,so.requested_delivery) at time zone fac.timezone)-make_interval(days=>so.safety_buffer_days)) at time zone fac.timezone into target from public.factories fac where fac.id=f;
 for sl in select l.*,p.name product_name,p.name_ar product_name_ar from public.sales_order_lines l join public.products p on p.id=l.product_id where l.factory_id=f and l.order_id=sales order by l.id loop
 select coalesce(sum(r.quantity),0) into reserved_qty from public.finished_goods_reservations r where r.factory_id=f and r.line_id=sl.id;
 select coalesce(sum(ia.quantity),0) into incoming_qty from public.sales_incoming_allocations ia where ia.factory_id=f and ia.line_id=sl.id;
 needed:=greatest(sl.quantity-sl.dispatched_quantity-reserved_qty,0);complete:=sl.dispatched_quantity=sl.quantity;
 ready:=complete or reserved_qty>=sl.quantity-sl.dispatched_quantity;all_ready:=all_ready and ready;
 if so.status='draft' then needed:=greatest(needed-coalesce((select b.on_hand-b.reserved from public.finished_goods_balances b where b.factory_id=f and b.product_id=sl.product_id and b.unit=sl.unit),0),0);end if;
 line_estimate:=now();line_earliest:=now();
 for allocation in select o.*,ia.quantity allocated from public.sales_incoming_allocations ia join public.production_orders o on o.id=ia.item_id
 where ia.factory_id=f and ia.line_id=sl.id and ia.quantity>0 order by o.id loop
 if allocation.status not in ('planned','active') then unknown:=true;early_unknown:=true;continue;end if;
 if allocation.status='active' then
 -- An overdue active job cannot be moved to another line by a forecast. Mark unknown rather than invent execution.
 if allocation.line_id is null or allocation.expected_finish is null or allocation.expected_finish<=now() then unknown:=true;early_unknown:=true;
 else line_estimate:=greatest(line_estimate,allocation.expected_finish);line_earliest:=greatest(line_earliest,allocation.expected_finish);end if;
 continue;end if;
 early_plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,allocation.remaining_quantity,allocation.id,extra=>early_virtual);
 if early_plan is null then early_unknown:=true;else early_virtual:=early_virtual||jsonb_build_array(early_plan);line_earliest:=greatest(line_earliest,(early_plan->>'finish')::timestamptz);end if;
 if allocation.expected_finish is not null and allocation.line_id is not null and allocation.expected_finish>now() then
 line_estimate:=greatest(line_estimate,allocation.expected_finish);
 else plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,allocation.remaining_quantity,allocation.id,extra=>virtual);
 if plan is null then unknown:=true;else virtual:=virtual||jsonb_build_array(plan);line_estimate:=greatest(line_estimate,(plan->>'finish')::timestamptz);end if;
 end if;end loop;
 if needed>incoming_qty then
 plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,needed-incoming_qty,extra=>virtual);
 early_plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,needed-incoming_qty,extra=>early_virtual);
 if plan is null then unknown:=true;else virtual:=virtual||jsonb_build_array(plan);line_estimate:=greatest(line_estimate,(plan->>'finish')::timestamptz);end if;
 if early_plan is null then early_unknown:=true;else early_virtual:=early_virtual||jsonb_build_array(early_plan);line_earliest:=greatest(line_earliest,(early_plan->>'finish')::timestamptz);end if;
 end if;
 earliest:=greatest(earliest,line_earliest);estimated:=greatest(estimated,line_estimate);
 lines:=lines||jsonb_build_array(to_jsonb(sl)||jsonb_build_object('reserved_quantity',reserved_qty,'incoming_quantity',incoming_qty,'production_required',needed,'ready',ready,
 'estimated_ready',case when needed>0 then line_estimate end,'dispatch_allowed',not complete and ready and sl.release_when_ready));
 end loop;
 state:=case when so.status in ('draft','completed','cancelled') then so.status when all_ready then 'ready'
 when exists(select 1 from public.sales_order_lines l where l.order_id=sales and l.dispatched_quantity>0) then 'partially_dispatched' else 'approved' end;
 risk:=case when so.status in ('draft','cancelled','completed') then 'none'
 when (coalesce(so.promised_delivery,so.requested_delivery)<now() and not all_ready) or (not unknown and estimated>coalesce(so.promised_delivery,so.requested_delivery)) then 'late'
 when unknown then 'unknown' when estimated>target then 'at_risk' else 'on_time' end;
 if all_ready then lines:=(select coalesce(jsonb_agg(x||jsonb_build_object('dispatch_allowed',(x->>'dispatched_quantity')::numeric<(x->>'quantity')::numeric)),'[]') from jsonb_array_elements(lines) x);end if;
 return to_jsonb(so)||jsonb_build_object('lines',lines,'fulfillment_status',state,'risk',risk,'target_ready',target,
 'earliest_feasible',case when not early_unknown then earliest end,'estimated_ready',case when not unknown then estimated end,
 'requested_feasible',case when not early_unknown then earliest<=so.requested_delivery end,
 'delay_days',case when not unknown then greatest(ceil(extract(epoch from (estimated-coalesce(so.promised_delivery,so.requested_delivery)))/86400),0) end,
 'dispatch_allowed',so.status='approved' and all_ready);
end$$;
create or replace function public.fulfillment_production_context(factory uuid,item uuid default null) returns jsonb
 language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 perform private.require_permission(factory,'orders','view');
 with base as materialized (
 select o.id item_id,r.request_type,l.order_id sales_order_id,s.code sales_order_code,s.requested_delivery,s.promised_delivery,a.quantity incoming_allocated
 from public.production_orders o join public.production_requests r on r.id=o.request_id
 left join public.sales_incoming_allocations a on a.item_id=o.id and a.quantity>0
 left join public.sales_order_lines l on l.id=a.line_id left join public.sales_orders s on s.id=l.order_id and s.status='approved'
 where o.factory_id=factory and o.status in ('planned','active') and (item is null or o.id=item)
 and (r.request_type is not null or a.id is not null) order by o.id limit 500),
 details as materialized (select id,private.sales_order_detail(factory,id) detail from(select distinct sales_order_id id from base where sales_order_id is not null) ids)
 select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('target_ready',d.detail->>'target_ready','risk',d.detail->>'risk','estimated_ready',d.detail->>'estimated_ready')),'[]') into result
 from base b left join details d on d.id=b.sales_order_id;
 return jsonb_build_object('rows',result);
end$$;
create index sales_incoming_item on public.sales_incoming_allocations(item_id) where quantity>0;
create index sales_order_lines_order on public.sales_order_lines(order_id);
create index sales_orders_factory_created on public.sales_orders(factory_id,created_at desc,id);
