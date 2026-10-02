-- Forward correction: separate PL/pgSQL row variables from SQL aliases.
create or replace function public.adjust_finished_stock(factory uuid,product uuid,unit text,quantity numeric,reason text,request_id uuid default gen_random_uuid())
 returns uuid language plpgsql security definer set search_path='' as $$declare old uuid;result uuid:=gen_random_uuid();p jsonb:=jsonb_build_object('product',product,'unit',unit,'quantity',quantity,'reason',reason);l record;begin
 perform private.require_permission(factory,'warehouse','edit');old:=private.fulfillment_retry(factory,request_id,'adjust',p);if old is not null then return old;end if;
 if quantity is null or quantity=0 or quantity::text in ('NaN','Infinity','-Infinity') or unit not in ('meter','piece') or length(trim(coalesce(reason,''))) not between 3 and 2000
 or not exists(select 1 from public.products where factory_id=factory and id=product and stage='finished') then raise exception 'fulfillment_invalid';end if;
 perform private.finished_balance(factory,product,unit);
 if exists(select 1 from public.finished_goods_balances b where b.factory_id=factory and b.product_id=product and b.unit=adjust_finished_stock.unit and b.on_hand+quantity<b.reserved) then raise exception 'fulfillment_stock_committed';end if;
 update public.finished_goods_balances set on_hand=on_hand+quantity where factory_id=factory and product_id=product and finished_goods_balances.unit=adjust_finished_stock.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,created_by) values(result,factory,product,unit,'adjustment',quantity,reason,auth.uid());
 -- Fill genuine unallocated demand, not an existing production commitment a second time.
 for l in select t_l.id from public.sales_order_lines t_l join public.sales_orders t_s on t_s.id=t_l.order_id where t_l.factory_id=factory and t_l.product_id=product and t_l.unit=adjust_finished_stock.unit and t_s.status='approved' order by t_s.created_at,t_l.id loop
 perform private.allocate_sales_line(factory,l.id);end loop;
 perform private.replenish_finished(factory,product);
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'adjust',p,result,clock_timestamp());return result;
end$$;

create or replace function public.dispatch_sales_order(factory uuid,sales_order uuid,line uuid default null,request_id uuid default gen_random_uuid()) returns uuid
 language plpgsql security definer set search_path='' as $$declare s public.sales_orders;l record;old uuid;all_ready boolean;p jsonb:=jsonb_build_object('order',sales_order,'line',line);begin
 perform private.require_permission(factory,'warehouse','issue');
 old:=private.fulfillment_retry(factory,request_id,'dispatch',p);if old is not null then return old;end if;
 select * into s from public.sales_orders where factory_id=factory and id=sales_order for update;
 if not found or s.status<>'approved' then raise exception 'fulfillment_state';end if;
 select bool_and(coalesce(r.quantity,0)>=t_l.quantity-t_l.dispatched_quantity) into all_ready from public.sales_order_lines t_l
 left join public.finished_goods_reservations r on r.line_id=t_l.id where t_l.factory_id=factory and t_l.order_id=sales_order;
 if line is not null and not exists(select 1 from public.sales_order_lines t_l where t_l.factory_id=factory and t_l.order_id=sales_order and t_l.id=line
 and (t_l.release_when_ready or all_ready)) then raise exception 'fulfillment_hold';end if;
 if line is null and not all_ready then raise exception 'fulfillment_hold';end if;
 for l in select t_l.*,coalesce(r.quantity,0) reserved_quantity from public.sales_order_lines t_l
 left join public.finished_goods_reservations r on r.line_id=t_l.id where t_l.factory_id=factory and t_l.order_id=sales_order
 and (line is null or t_l.id=line) and t_l.dispatched_quantity<t_l.quantity order by t_l.id loop
 if l.reserved_quantity<l.quantity-l.dispatched_quantity then raise exception 'fulfillment_not_ready';end if;
 perform private.reserve_finished(factory,l.id,-(l.quantity-l.dispatched_quantity));
 update public.finished_goods_balances set on_hand=on_hand-(l.quantity-l.dispatched_quantity) where factory_id=factory and product_id=l.product_id and unit=l.unit;
 insert into public.finished_goods_movements(factory_id,product_id,unit,kind,stock_delta,sales_line_id,created_by)
 values(factory,l.product_id,l.unit,'dispatch',-(l.quantity-l.dispatched_quantity),l.id,auth.uid());
 update public.sales_order_lines set dispatched_quantity=quantity where id=l.id;
 end loop;
 if not exists(select 1 from public.sales_order_lines where order_id=sales_order and dispatched_quantity<quantity)
 then update public.sales_orders set status='completed' where id=sales_order;end if;
 for l in select distinct product_id from public.sales_order_lines where order_id=sales_order loop perform private.replenish_finished(factory,l.product_id);end loop;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'dispatch',p,sales_order,clock_timestamp());return sales_order;
end$$;

create or replace function public.change_sales_order(factory uuid,sales_order uuid,payload jsonb,reason text,request_id uuid default gen_random_uuid()) returns uuid
 language plpgsql security definer set search_path='' as $$declare s public.sales_orders;old uuid;l public.sales_order_lines;a record;q numeric;entry jsonb;cancel boolean:=coalesce((payload->>'cancel')::boolean,false);reallocate boolean:=false;p jsonb:=jsonb_build_object('order',sales_order,'changes',payload,'reason',reason);begin
 perform private.require_permission(factory,'sales_orders','edit');
 old:=private.fulfillment_retry(factory,request_id,'change',p);if old is not null then return old;end if;
 select * into s from public.sales_orders where factory_id=factory and id=sales_order for update;
 if not found or s.status in ('completed','cancelled') then raise exception 'fulfillment_state';end if;
 if length(trim(coalesce(reason,''))) not between 3 and 2000 then raise exception 'reason_required';end if;
 if s.status='approved' then perform private.require_permission(factory,'sales_orders','approve');end if;
 if (payload ? 'safety_buffer_days' and (payload->>'safety_buffer_days')::integer is distinct from s.safety_buffer_days)
 or (payload ? 'promised_delivery' and nullif(payload->>'promised_delivery','')::timestamptz is distinct from s.promised_delivery)
 then perform private.require_permission(factory,'sales_orders','approve');end if;
 if payload ? 'lines' then
 if jsonb_typeof(payload->'lines') is distinct from 'array'
 or jsonb_array_length(payload->'lines')<>(select count(*) from public.sales_order_lines where order_id=sales_order)
 or (select count(distinct x->>'id') from jsonb_array_elements(payload->'lines') x)<>jsonb_array_length(payload->'lines') then raise exception 'fulfillment_invalid';end if;
 for entry in select value from jsonb_array_elements(payload->'lines') loop
 select * into l from public.sales_order_lines where factory_id=factory and order_id=sales_order and id=(entry->>'id')::uuid;
 if not found or (entry->>'quantity')::numeric<l.dispatched_quantity then raise exception 'fulfillment_invalid';end if;
 reallocate:=reallocate or (entry->>'quantity')::numeric is distinct from l.quantity;
 end loop;end if;
 -- Release allocations first under the same factory lock. Active production remains intact.
 if cancel or reallocate then
 for l in select * from public.sales_order_lines where factory_id=factory and order_id=sales_order order by id loop
 q:=(select coalesce(quantity,0) from public.finished_goods_reservations where factory_id=factory and line_id=l.id);
 perform private.reserve_finished(factory,l.id,-coalesce(q,0));
 for a in select t_a.*,o.status,o.actual_start,o.planning_locked_at,r.sales_order_line_id
 from public.sales_incoming_allocations t_a join public.production_orders o on o.id=t_a.item_id join public.production_requests r on r.id=o.request_id
 where t_a.factory_id=factory and t_a.line_id=l.id and t_a.quantity>0 loop
 if a.sales_order_line_id=l.id and a.status='planned' and a.actual_start is null then
 if a.planning_locked_at is not null then raise exception 'fulfillment_planner_decision';end if;
 update public.production_orders set status='cancelled' where id=a.item_id;
 end if;
 update public.sales_incoming_allocations set released_quantity=released_quantity+quantity,quantity=0 where id=a.id;
 end loop;
 end loop;
 end if;
 if payload ? 'lines' then
 if jsonb_typeof(payload->'lines') is distinct from 'array' or jsonb_array_length(payload->'lines')<>(select count(*) from public.sales_order_lines where order_id=sales_order)
 or (select count(distinct x->>'id') from jsonb_array_elements(payload->'lines') x)<>jsonb_array_length(payload->'lines')
 then raise exception 'fulfillment_invalid';end if;
 for entry in select value from jsonb_array_elements(payload->'lines') loop
 select * into l from public.sales_order_lines where factory_id=factory and order_id=sales_order and id=(entry->>'id')::uuid;
 if not found or (entry->>'quantity')::numeric<l.dispatched_quantity then raise exception 'fulfillment_invalid';end if;
 update public.sales_order_lines set quantity=(entry->>'quantity')::numeric,release_when_ready=coalesce((entry->>'release_when_ready')::boolean,l.release_when_ready) where id=l.id;
 end loop;
 end if;
 update public.sales_orders set
 customer_reference=case when payload ? 'customer_reference' then payload->>'customer_reference' else customer_reference end,
 requested_delivery=case when payload ? 'requested_delivery' then (payload->>'requested_delivery')::timestamptz else requested_delivery end,
 promised_delivery=case when payload ? 'promised_delivery' then nullif(payload->>'promised_delivery','')::timestamptz else promised_delivery end,
 safety_buffer_days=case when payload ? 'safety_buffer_days' then (payload->>'safety_buffer_days')::integer else safety_buffer_days end,
 notes=case when payload ? 'notes' then payload->>'notes' else notes end,
 status=case when cancel then 'cancelled' else status end where id=sales_order;
 update public.production_requests set required_by=(select requested_delivery from public.sales_orders where id=sales_order)
 where factory_id=factory and sales_order_line_id in(select id from public.sales_order_lines where order_id=sales_order);
 if not cancel and s.status='approved' then
 for l in select * from public.sales_order_lines where order_id=sales_order order by id loop perform private.allocate_sales_line(factory,l.id);end loop;end if;
 for l in select * from public.sales_order_lines where order_id=sales_order loop perform private.replenish_finished(factory,l.product_id);end loop;
 insert into public.audit_logs(factory_id,actor_id,action,entity,entity_id,new_data) values(factory,auth.uid(),'CHANGE','sales_orders',sales_order,p);
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'change',p,sales_order,clock_timestamp());return sales_order;
end$$;

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
 where t_a.factory_id=new.factory_id and t_a.item_id=job.id and t_a.quantity>0 and s.status='approved' order by s.created_at,t_a.id for update of a loop
 take:=least(leftover,a.quantity);exit when take<=0;
 perform private.reserve_finished(new.factory_id,a.line_id,take);
 update public.sales_incoming_allocations set quantity=quantity-take,received_quantity=received_quantity+take where id=a.id;
 leftover:=leftover-take;end loop;
 return new;
end$$;

create or replace function private.sales_order_detail(f uuid,sales uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare s public.sales_orders;l record;a record;lines jsonb:='[]';line_ready timestamptz;earliest timestamptz:=now();estimated timestamptz:=now();
 plan jsonb;virtual jsonb:='[]';unknown boolean:=false;target timestamptz;all_ready boolean:=true;line_complete boolean;ready boolean;reserved numeric;incoming numeric;production_needed numeric;state text;risk text;begin
 select * into s from public.sales_orders where factory_id=f and id=sales;
 if not found then return null;end if;
 select ((coalesce(s.promised_delivery,s.requested_delivery) at time zone timezone)-make_interval(days=>s.safety_buffer_days)) at time zone timezone into target from public.factories where id=f;
 for l in select t_l.*,p.name product_name,p.name_ar product_name_ar from public.sales_order_lines t_l join public.products p on p.id=t_l.product_id where t_l.factory_id=f and t_l.order_id=sales order by t_l.id loop
 select coalesce(sum(quantity),0) into reserved from public.finished_goods_reservations where factory_id=f and line_id=l.id;
 select coalesce(sum(quantity),0) into incoming from public.sales_incoming_allocations where factory_id=f and line_id=l.id;
 production_needed:=greatest(l.quantity-l.dispatched_quantity-reserved,0);line_complete:=l.dispatched_quantity=l.quantity;
 ready:=line_complete or reserved>=l.quantity-l.dispatched_quantity;all_ready:=all_ready and ready;
 if s.status='draft' then
 production_needed:=greatest(production_needed-coalesce((select on_hand-reserved from public.finished_goods_balances where factory_id=f and product_id=l.product_id and unit=l.unit),0),0);
 end if;
 line_ready:=now();
 for a in select o.*,r.request_type,t_a.quantity allocated from public.sales_incoming_allocations t_a join public.production_orders o on o.id=t_a.item_id
 join public.production_requests r on r.id=o.request_id where t_a.factory_id=f and t_a.line_id=l.id and t_a.quantity>0 order by o.id loop
 if a.status not in ('planned','active') then unknown:=true;continue;end if;
 if a.expected_finish is not null and a.line_id is not null and a.expected_finish>now() then
 line_ready:=greatest(line_ready,a.expected_finish);
 else
 plan:=private.fulfillment_slot(f,l.product_id,l.unit,a.remaining_quantity,a.id,extra=>virtual);
 if plan is null then unknown:=true;else
 virtual:=virtual||jsonb_build_array(plan);line_ready:=greatest(line_ready,(plan->>'finish')::timestamptz);end if;
 end if;end loop;
 if production_needed>incoming or (s.status='draft' and production_needed>0) then
 plan:=private.fulfillment_slot(f,l.product_id,l.unit,greatest(production_needed-incoming,0),extra=>virtual);
 if plan is null then unknown:=true;else virtual:=virtual||jsonb_build_array(plan);line_ready:=greatest(line_ready,(plan->>'finish')::timestamptz);end if;end if;
 earliest:=greatest(earliest,line_ready);estimated:=greatest(estimated,line_ready);
 lines:=lines||jsonb_build_array(to_jsonb(l)||jsonb_build_object('reserved_quantity',reserved,'incoming_quantity',incoming,
 'production_required',production_needed,'ready',ready,'estimated_ready',case when production_needed>0 then line_ready end,
 'dispatch_allowed',not line_complete and ready and l.release_when_ready));
 end loop;
 -- Requested/Promised dates never move with this derived forecast.
 state:=case when s.status in ('draft','completed','cancelled') then s.status
 when all_ready then 'ready' when exists(select 1 from public.sales_order_lines where order_id=sales and dispatched_quantity>0) then 'partially_dispatched' else 'approved' end;
 risk:=case when s.status in ('draft','cancelled','completed') then 'none'
 when (coalesce(s.promised_delivery,s.requested_delivery)<now() and not all_ready) or (not unknown and estimated>coalesce(s.promised_delivery,s.requested_delivery)) then 'late'
 when unknown then 'unknown' when estimated>target then 'at_risk' else 'on_time' end;
 if all_ready then lines:=(select coalesce(jsonb_agg(x||jsonb_build_object('dispatch_allowed',(x->>'dispatched_quantity')::numeric<(x->>'quantity')::numeric)),'[]') from jsonb_array_elements(lines) x);end if;
 return to_jsonb(s)||jsonb_build_object('lines',lines,'fulfillment_status',state,'risk',risk,'target_ready',target,
 'earliest_feasible',case when not unknown then earliest end,'estimated_ready',case when not unknown then estimated end,
 'requested_feasible',case when not unknown then earliest<=s.requested_delivery end,
 'delay_days',case when not unknown then greatest(ceil(extract(epoch from (estimated-coalesce(s.promised_delivery,s.requested_delivery)))/86400),0) end,
 'dispatch_allowed',s.status='approved' and all_ready);
end$$;

create or replace function private.refresh_finished_projection() returns trigger language plpgsql security definer set search_path='' as $$declare a record;begin
 if new.status='cancelled' then
 for a in select distinct line_id from public.sales_incoming_allocations where item_id=new.id and quantity>0 loop
 update public.sales_incoming_allocations set released_quantity=released_quantity+quantity,quantity=0 where item_id=new.id and line_id=a.line_id;
 perform private.allocate_sales_line(new.factory_id,a.line_id);end loop;end if;
 -- Run after all Recording/correction writes so incoming and receipts cannot be double-counted.
 perform private.replenish_finished(new.factory_id,new.product_id);return new;
end$$;

