-- Optional customer targets; historical promises remain immutable, never forecasts.
alter table public.sales_orders alter column requested_delivery drop not null;
alter table public.products add column supply_source text not null default 'MANUFACTURED'
 check(supply_source in ('MANUFACTURED','EXTERNAL','BOTH'));
alter table public.finished_goods_movements drop constraint finished_goods_movements_kind_check;
alter table public.finished_goods_movements add constraint finished_goods_movements_kind_check
 check(kind in ('production_receipt','production_correction','reservation','release','dispatch','adjustment','opening_balance','external_receipt'));
alter table public.finished_goods_movements add column external_reference text check(length(external_reference)<=200);
create unique index finished_opening_once on public.finished_goods_movements(factory_id,product_id,unit) where kind='opening_balance';
-- Reuse the existing material ledger, without BOM consumption or purchasing.
alter table public.materials add column inventory_kind text not null default 'RAW_MATERIAL'
 check(inventory_kind in ('RAW_MATERIAL','SEMI_FINISHED'));
alter table public.inventory_transactions drop constraint inventory_transactions_kind_check;
alter table public.inventory_transactions add constraint inventory_transactions_kind_check
 check(kind in ('purchase_receipt','material_consumption','production_output','sales_reservation','sales_delivery','warehouse_transfer','adjustment','scrap','opening_balance','external_receipt'));
alter table public.inventory_transactions add column unit text,add column reference text check(length(reference)<=200),add column note text check(length(note)<=2000);
create unique index material_opening_once on public.inventory_transactions(factory_id,material_id) where kind='opening_balance';
create index material_inventory_time on public.inventory_transactions(factory_id,material_id,created_at desc,id);
revoke insert,update,delete,truncate on public.materials,public.inventory_transactions from anon,authenticated;
create policy warehouse_material_read on public.materials for select to authenticated using(private.has_permission(factory_id,'warehouse','view'));
create policy warehouse_material_movement_read on public.inventory_transactions for select to authenticated using(private.has_permission(factory_id,'warehouse','view'));
create function private.guard_historical_promise() returns trigger language plpgsql set search_path='' as $$begin
 if (tg_op='INSERT' and new.promised_delivery is not null) or (tg_op='UPDATE' and new.promised_delivery is distinct from old.promised_delivery)
 then raise exception 'sales_promise_read_only';end if;return new;end$$;
create trigger historical_promise_guard before insert or update of promised_delivery on public.sales_orders for each row execute function private.guard_historical_promise();
create function private.guard_stock_identity() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.fulfillment_lock(new.factory_id);
 if tg_table_name='products' then
  if (new.stage is distinct from old.stage or new.stock_unit is distinct from old.stock_unit) and
   exists(select 1 from public.finished_goods_movements where factory_id=old.factory_id and product_id=old.id)
  then raise exception 'fulfillment_stock_identity';end if;
  if new.supply_source='EXTERNAL' and new.supply_source is distinct from old.supply_source and exists(
   select 1 from public.production_orders where factory_id=old.factory_id and product_id=old.id and status in ('planned','active'))
  then raise exception 'fulfillment_planner_decision';end if;
 else
  if new.unit is distinct from old.unit and exists(select 1 from public.inventory_transactions where factory_id=old.factory_id and material_id=old.id)
  then raise exception 'fulfillment_stock_identity';end if;
 end if;return new;end$$;
create trigger product_stock_identity before update of stage,stock_unit,supply_source on public.products for each row execute function private.guard_stock_identity();
create trigger material_stock_identity before update of unit on public.materials for each row execute function private.guard_stock_identity();
CREATE OR REPLACE FUNCTION public.create_sales_order(factory uuid, payload jsonb, request_id uuid DEFAULT gen_random_uuid())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare result uuid;entry jsonb;buffer integer;begin
 perform private.require_permission(factory,'sales_orders','create');
 result:=private.fulfillment_retry(factory,request_id,'create',payload);if result is not null then return result;end if;
 if jsonb_typeof(payload)<>'object' or jsonb_typeof(payload->'lines') is distinct from 'array'
 or jsonb_array_length(payload->'lines') not between 1 and 50
 then raise exception 'fulfillment_invalid';end if;
 if payload ? 'promised_delivery' then raise exception 'sales_promise_read_only';end if;
 select delivery_buffer_days into buffer from public.factories where id=factory;
 if payload ? 'safety_buffer_days' and (payload->>'safety_buffer_days')::integer<>buffer then
 perform private.require_permission(factory,'sales_orders','approve');buffer:=(payload->>'safety_buffer_days')::integer;end if;
 insert into public.sales_orders(factory_id,customer_reference,requested_by,created_by,requested_delivery,promised_delivery,safety_buffer_days,notes)
 values(factory,coalesce(payload->>'customer_reference',''),auth.uid(),auth.uid(),nullif(payload->>'requested_delivery','')::timestamptz,
 null,buffer,coalesce(payload->>'notes','')) returning id into result;
 for entry in select value from jsonb_array_elements(payload->'lines') loop
 if not exists(select 1 from public.products where factory_id=factory and id=(entry->>'product_id')::uuid and stage='finished')
 then raise exception 'fulfillment_product';end if;
 if exists(select 1 from public.products p where p.id=(entry->>'product_id')::uuid and p.stock_unit is not null and p.stock_unit is distinct from entry->>'unit') then raise exception 'fulfillment_stock_identity';end if;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit,release_when_ready)
 values(factory,result,(entry->>'product_id')::uuid,(entry->>'quantity')::numeric,entry->>'unit',coalesce((entry->>'release_when_ready')::boolean,false));
 end loop;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'create',payload,result,clock_timestamp());return result;
end$function$;

CREATE OR REPLACE FUNCTION public.change_sales_order(factory uuid, sales_order uuid, payload jsonb, reason text, request_id uuid DEFAULT gen_random_uuid())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare s public.sales_orders;old uuid;l public.sales_order_lines;a record;q numeric;entry jsonb;cancel boolean:=coalesce((payload->>'cancel')::boolean,false);reallocate boolean:=false;p jsonb:=jsonb_build_object('order',sales_order,'changes',payload,'reason',reason);begin
 perform private.require_permission(factory,'sales_orders','edit');
 if payload ? 'promised_delivery' then raise exception 'sales_promise_read_only';end if;
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
 requested_delivery=case when payload ? 'requested_delivery' then nullif(payload->>'requested_delivery','')::timestamptz else requested_delivery end,
 
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
end$function$;

CREATE OR REPLACE FUNCTION private.allocate_sales_line(f uuid, line uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare l public.sales_order_lines;s public.sales_orders;need numeric;take numeric;stock numeric;candidate record;i uuid;begin
 select * into l from public.sales_order_lines where factory_id=f and id=line for update;
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

CREATE OR REPLACE FUNCTION private.replenish_finished(f uuid, p uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare prod public.products;editable public.production_orders;base numeric;needed numeric;begin
 perform private.fulfillment_lock(f);
 select * into prod from public.products where factory_id=f and id=p;
 if prod.supply_mode<>'MAKE_TO_STOCK' or prod.supply_source<>'MANUFACTURED' then return;end if;
 -- Recalculate only the still-unplanned, unstarted stock request. Persisted schedules never move.
 select o.* into editable from public.production_orders o join public.production_requests r on r.id=o.request_id
 where o.factory_id=f and o.product_id=p and o.unit=prod.stock_unit and r.request_type='STOCK_REPLENISHMENT'
 and o.status='planned' and o.actual_start is null and o.produced_quantity=0 and o.line_id is null and o.start_time is null
 and o.planning_locked_at is null and not exists(select 1 from public.sales_incoming_allocations a where a.item_id=o.id and a.quantity>0)
 order by o.created_at,o.id limit 1 for update of o;
 base:=private.projected_finished(f,p,prod.stock_unit,editable.id);
 needed:=case when editable.id is not null or base<prod.minimum_stock then greatest(prod.maximum_stock-base,0) else 0 end;
 if editable.id is not null then
 if needed=0 then update public.production_orders set status='cancelled' where id=editable.id;
 elsif editable.target_quantity<>needed then update public.production_orders set target_quantity=needed where id=editable.id;end if;
 elsif needed>0 then perform private.fulfillment_production(f,p,prod.stock_unit,needed,'STOCK_REPLENISHMENT',null,null);end if;
end$function$;

CREATE OR REPLACE FUNCTION private.fulfillment_production(f uuid, p uuid, u text, q numeric, kind text, l uuid, due timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare r uuid;i uuid;begin
 if not exists(select 1 from public.products where factory_id=f and id=p and supply_source='MANUFACTURED') then raise exception 'fulfillment_source_decision';end if;
 insert into public.production_requests(factory_id,code,name,requested_by,requested_by_name,priority,required_by,request_type,sales_order_line_id)
 values(f,'',case when kind='SALES_PRODUCTION' then 'Sales production' else 'Stock replenishment' end,auth.uid(),
 (select display_name from public.memberships where factory_id=f and user_id=auth.uid()),
 case when kind='SALES_PRODUCTION' and due is not null then 'high' when kind='SALES_PRODUCTION' then 'normal' else 'low' end,due,kind,l) returning id into r;
 insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit) values(f,r,p,q,u) returning id into i;
 return i;
end$function$;

CREATE OR REPLACE FUNCTION private.create_production_request(f uuid, request_name text, request_priority text, request_required_by timestamp with time zone, request_notes text, request_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result_id uuid; entry jsonb; product uuid; amount numeric; item_unit text;
 seen uuid[] := '{}'; actor_name text; internal_reason text;
begin
 perform private.require_permission(f,'orders','create');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 if length(btrim(coalesce(request_name,''))) not between 1 and 200 then
  raise exception 'request_name_required';end if;
 if coalesce(request_priority,'normal') not in ('low','normal','high','urgent') then
  raise exception 'invalid_priority';end if;
 internal_reason:=regexp_replace(coalesce(request_notes,''),'^\s+|\s+$','','g');
 if internal_reason='' then raise exception 'internal_reason_required';end if;
 if length(internal_reason)>2000 then raise exception 'invalid_notes';end if;
 if jsonb_typeof(request_items) is distinct from 'array' or jsonb_array_length(request_items) not between 1 and 100 then
  raise exception 'request_items_required';end if;
 select m.display_name into actor_name from public.memberships m
  where m.factory_id=f and m.user_id=auth.uid() and m.status='approved';
 actor_name:=coalesce(nullif(btrim(actor_name),''),(select split_part(u.email,'@',1) from auth.users u where u.id=auth.uid()));
 insert into public.production_requests(factory_id,code,name,requested_by,requested_by_name,priority,required_by,notes,request_type,created_at)
 values(f,'',btrim(request_name),auth.uid(),actor_name,coalesce(request_priority,'normal'),request_required_by,internal_reason,'INTERNAL_PRODUCTION',clock_timestamp())
 returning id into result_id;
 for entry in select value from jsonb_array_elements(request_items) loop
  if jsonb_typeof(entry) is distinct from 'object' or exists(select 1 from jsonb_object_keys(entry) k where k not in ('product_id','quantity','unit')) then
   raise exception 'invalid_request_item';end if;
  product:=nullif(entry->>'product_id','')::uuid;amount:=nullif(entry->>'quantity','')::numeric;item_unit:=entry->>'unit';
  if product is null or not exists(select 1 from public.products p where p.factory_id=f and p.id=product) then
   raise exception 'invalid_request_product';end if;
  if exists(select 1 from public.products p where p.factory_id=f and p.id=product and p.supply_source='EXTERNAL') then raise exception 'fulfillment_source_decision';end if;
  if product=any(seen) then raise exception 'duplicate_request_product';end if;
  if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') then raise exception 'invalid_request_quantity';end if;
  if item_unit is null or item_unit not in ('meter','piece') then raise exception 'invalid_request_unit';end if;
  seen:=array_append(seen,product);
  insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit)
   values(f,result_id,product,amount,item_unit);
 end loop;
 return result_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.sales_order_detail(f uuid, sales uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare so public.sales_orders;sl record;allocation record;lines jsonb:='[]';line_estimate timestamptz;line_earliest timestamptz;
 earliest timestamptz:=now();estimated timestamptz;plan jsonb;early_plan jsonb;virtual jsonb:='[]';early_virtual jsonb:='[]';
 unknown boolean:=false;line_unknown boolean;early_unknown boolean:=false;target timestamptz;all_ready boolean:=true;complete boolean;ready boolean;
 reserved_qty numeric;incoming_qty numeric;needed numeric;state text;risk text;begin
 select * into so from public.sales_orders where factory_id=f and id=sales;if not found then return null;end if;
 select ((so.requested_delivery at time zone fac.timezone)-make_interval(days=>so.safety_buffer_days)) at time zone fac.timezone into target from public.factories fac where fac.id=f;
 for sl in select l.*,p.name product_name,p.name_ar product_name_ar,p.supply_source from public.sales_order_lines l join public.products p on p.id=l.product_id where l.factory_id=f and l.order_id=sales order by l.id loop
 select coalesce(sum(r.quantity),0) into reserved_qty from public.finished_goods_reservations r where r.factory_id=f and r.line_id=sl.id;
 select coalesce(sum(ia.quantity),0) into incoming_qty from public.sales_incoming_allocations ia where ia.factory_id=f and ia.line_id=sl.id;
 needed:=greatest(sl.quantity-sl.dispatched_quantity-reserved_qty,0);complete:=sl.dispatched_quantity=sl.quantity;
 ready:=complete or reserved_qty>=sl.quantity-sl.dispatched_quantity;all_ready:=all_ready and ready;
 if so.status='draft' then needed:=greatest(needed-coalesce((select b.on_hand-b.reserved from public.finished_goods_balances b where b.factory_id=f and b.product_id=sl.product_id and b.unit=sl.unit),0),0);end if;
 line_unknown:=false;
 line_estimate:=coalesce((select max(created_at) from public.finished_goods_movements where factory_id=f and sales_line_id=sl.id and (reserved_delta>0 or kind='dispatch')),so.approved_at,so.created_at);line_earliest:=now();
 for allocation in select o.*,ia.quantity allocated from public.sales_incoming_allocations ia join public.production_orders o on o.id=ia.item_id
 where ia.factory_id=f and ia.line_id=sl.id and ia.quantity>0 order by o.id loop
 if allocation.status not in ('planned','active') then line_unknown:=true;early_unknown:=true;continue;end if;
 if allocation.status='active' then
 -- An overdue active job cannot be moved to another line by a forecast. Mark unknown rather than invent execution.
 if allocation.line_id is null or allocation.expected_finish is null or allocation.expected_finish+greatest(coalesce(allocation.actual_start-allocation.start_time,interval '0'),interval '0')<=now() then line_unknown:=true;early_unknown:=true;
 else line_estimate:=greatest(line_estimate,allocation.expected_finish+greatest(coalesce(allocation.actual_start-allocation.start_time,interval '0'),interval '0'));line_earliest:=greatest(line_earliest,line_estimate);end if;
 continue;end if;
 early_plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,allocation.remaining_quantity,allocation.id,extra=>early_virtual);
 if early_plan is null then early_unknown:=true;else early_virtual:=early_virtual||jsonb_build_array(early_plan);line_earliest:=greatest(line_earliest,(early_plan->>'finish')::timestamptz);end if;
 if allocation.expected_finish is not null and allocation.line_id is not null and allocation.expected_finish>now() then
 line_estimate:=greatest(line_estimate,allocation.expected_finish);
 else line_unknown:=true;
 end if;end loop;
 if needed>incoming_qty then
 line_unknown:=true;
 if sl.supply_source='MANUFACTURED' then
  early_plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,needed-incoming_qty,extra=>early_virtual);
  if early_plan is null then early_unknown:=true;else early_virtual:=early_virtual||jsonb_build_array(early_plan);line_earliest:=greatest(line_earliest,(early_plan->>'finish')::timestamptz);end if;
 else early_unknown:=true;end if;
 end if;
 unknown:=unknown or line_unknown;
 earliest:=greatest(earliest,line_earliest);estimated:=greatest(estimated,line_estimate);
 lines:=lines||jsonb_build_array(to_jsonb(sl)||jsonb_build_object('reserved_quantity',reserved_qty,'incoming_quantity',incoming_qty,'production_required',case when sl.supply_source='MANUFACTURED' then needed else incoming_qty end,'external_shortage',case when sl.supply_source='EXTERNAL' then greatest(needed-incoming_qty,0) else 0 end,'source_decision_quantity',case when sl.supply_source='BOTH' then greatest(needed-incoming_qty,0) else 0 end,'ready',ready,
 'estimated_ready',case when not line_unknown then line_estimate end,'dispatch_allowed',not complete and ready and sl.release_when_ready));
 end loop;
 state:=case when so.status in ('draft','completed','cancelled') then so.status when all_ready then 'ready'
 when exists(select 1 from public.sales_order_lines l where l.order_id=sales and l.dispatched_quantity>0) then 'partially_dispatched' else 'approved' end;
 risk:=case when so.requested_delivery is null then 'none' when so.status in ('draft','cancelled','completed') then 'none'
 when (so.requested_delivery<now() and not all_ready) or (not unknown and estimated>so.requested_delivery) then 'late'
 when unknown then 'unknown' when estimated>target then 'at_risk' else 'on_time' end;
 if all_ready then lines:=(select coalesce(jsonb_agg(x||jsonb_build_object('dispatch_allowed',(x->>'dispatched_quantity')::numeric<(x->>'quantity')::numeric)),'[]') from jsonb_array_elements(lines) x);end if;
 return to_jsonb(so)||jsonb_build_object('lines',lines,'fulfillment_status',state,'risk',risk,'target_ready',target,
 'earliest_feasible',case when not early_unknown then earliest end,'estimated_ready',case when not unknown then estimated end,
 'requested_feasible',case when so.requested_delivery is not null and not early_unknown then earliest<=so.requested_delivery end,
 'delay_days',case when so.requested_delivery is not null and not unknown then greatest(ceil(extract(epoch from (estimated-so.requested_delivery))/86400),0) end,
 'dispatch_allowed',so.status='approved' and all_ready);
end$function$;

create function public.configure_product_supply(factory uuid,product uuid,source text) returns uuid language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'warehouse','edit');perform private.fulfillment_lock(factory);
 if source is null or source not in ('MANUFACTURED','EXTERNAL','BOTH') then raise exception 'fulfillment_invalid';end if;
 update public.products set supply_source=source where factory_id=factory and id=product and stage='finished';
 if not found then raise exception 'fulfillment_product';end if;return product;end$$;
create function private.reserve_received_stock(f uuid,p uuid,u text) returns void language plpgsql security definer set search_path='' as $$declare l record;need numeric;free numeric;begin
 for l in select x.* from public.sales_order_lines x join public.sales_orders s on s.id=x.order_id where x.factory_id=f and x.product_id=p and x.unit=u and s.status='approved' order by s.created_at,x.id loop
  select greatest(l.quantity-l.dispatched_quantity-coalesce((select quantity from public.finished_goods_reservations where factory_id=f and line_id=l.id),0)-coalesce((select sum(quantity) from public.sales_incoming_allocations where factory_id=f and line_id=l.id),0),0) into need;
  select on_hand-reserved into free from public.finished_goods_balances where factory_id=f and product_id=p and unit=u;
  perform private.reserve_finished(f,l.id,least(need,free));
 end loop;end$$;
create function public.receive_warehouse_stock(factory uuid,item uuid,item_type text,unit text,quantity numeric,source text,reference text default '',note text default '',request_id uuid default gen_random_uuid()) returns uuid
 language plpgsql security definer set search_path='' as $$declare result uuid;old uuid;p jsonb;begin
 perform private.require_permission(factory,'warehouse','edit');
 p:=jsonb_build_object('item',item,'type',item_type,'unit',unit,'quantity',quantity,'source',source,'reference',reference,'note',note);
 old:=private.fulfillment_retry(factory,request_id,'receive_stock',p);if old is not null then return old;end if;
 if quantity is null or quantity<=0 or quantity::text in ('NaN','Infinity','-Infinity') or source is null or source not in ('opening_balance','external_receipt')
  or unit is null or unit not in ('meter','piece','kg') or length(coalesce(reference,''))>200 or length(coalesce(note,''))>2000 then raise exception 'fulfillment_invalid';end if;
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
create function public.create_warehouse_material(factory uuid,payload jsonb,request_id uuid) returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 perform private.require_permission(factory,'warehouse','edit');result:=private.fulfillment_retry(factory,request_id,'material',payload);if result is not null then return result;end if;
 if jsonb_typeof(payload) is distinct from 'object' or exists(select 1 from jsonb_object_keys(payload) k where k not in ('name','name_ar','code','unit','inventory_kind'))
  or coalesce(length(btrim(payload->>'name')),0) not between 1 and 200 or coalesce(length(btrim(payload->>'code')),0) not between 1 and 100
  or coalesce(payload->>'unit','') not in ('kg','meter','piece') or coalesce(payload->>'inventory_kind','RAW_MATERIAL') not in ('RAW_MATERIAL','SEMI_FINISHED') then raise exception 'fulfillment_invalid';end if;
 insert into public.materials(factory_id,name,name_ar,code,unit,inventory_kind) values(factory,btrim(payload->>'name'),coalesce(payload->>'name_ar',''),btrim(payload->>'code'),payload->>'unit',coalesce(payload->>'inventory_kind','RAW_MATERIAL')) returning id into result;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'material',payload,result,clock_timestamp());return result;end$$;
CREATE OR REPLACE FUNCTION public.warehouse_page(factory uuid, page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare balances jsonb;orders jsonb;materials jsonb;begin
 perform private.require_permission(factory,'warehouse','view');if page is null or page not between 1 and 1000000 then raise exception 'fulfillment_invalid';end if;
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('available',x.on_hand-x.reserved,'projected',private.projected_finished(factory,x.product_id,x.unit),
 'incoming',(select coalesce(sum(o.remaining_quantity),0) from public.production_orders o where o.factory_id=factory and o.product_id=x.product_id and o.unit=x.unit and o.status in ('planned','active')))),'[]')
 into balances from(select b.*,p.name,p.name_ar,p.supply_source,p.supply_mode,p.minimum_stock,p.maximum_stock from public.finished_goods_balances b join public.products p on p.id=b.product_id
 where b.factory_id=factory order by p.name,b.unit limit 50 offset (page-1)*50)x;
 select coalesce(jsonb_agg(private.sales_order_detail(factory,id) order by created_at,id),'[]') into orders
 from(select id,created_at from public.sales_orders where factory_id=factory and status='approved' order by created_at,id limit 25 offset (page-1)*25)s;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into materials from(select m.*,
 coalesce((select sum(quantity) from public.inventory_transactions where factory_id=factory and material_id=m.id),0) on_hand,
 coalesce((select sum(quantity) from public.inventory_reservations where factory_id=factory and material_id=m.id and released_at is null),0) reserved
 from public.materials m where m.factory_id=factory order by m.name,m.id limit 50 offset (page-1)*50)x;
 return jsonb_build_object('materials',materials,'materials_total',(select count(*) from public.materials where factory_id=factory),'rows',balances,'total',(select count(*) from public.finished_goods_balances where factory_id=factory),'orders',orders,'page',page,'page_size',50,
 'orders_total',(select count(*) from public.sales_orders where factory_id=factory and status='approved'));
end$function$;

create function public.warehouse_movements(factory uuid,item uuid,item_type text,page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;total integer;begin
 perform private.require_permission(factory,'warehouse','view');if page is null or page not between 1 and 1000000 then raise exception 'fulfillment_invalid';end if;
 if item_type='finished' then
  select count(*) into total from public.finished_goods_movements where factory_id=factory and product_id=item;
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('actor_name',(select display_name from public.memberships where factory_id=factory and user_id=x.created_by))),'[]') into rows from(select id,kind,stock_delta quantity,unit,reason note,external_reference reference,created_by,created_at from public.finished_goods_movements where factory_id=factory and product_id=item order by created_at desc,id limit 25 offset (page-1)*25)x;
 elsif item_type='material' then
  select count(*) into total from public.inventory_transactions where factory_id=factory and material_id=item;
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('actor_name',(select display_name from public.memberships where factory_id=factory and user_id=x.created_by))),'[]') into rows from(select id,kind,quantity,unit,note,reference,created_by,created_at from public.inventory_transactions where factory_id=factory and material_id=item order by created_at desc,id limit 25 offset (page-1)*25)x;
 else raise exception 'fulfillment_invalid';end if;return jsonb_build_object('rows',rows,'total',total);end$$;
revoke all on function private.guard_historical_promise(),private.guard_stock_identity(),private.reserve_received_stock(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.configure_product_supply(uuid,uuid,text),public.receive_warehouse_stock(uuid,uuid,text,text,numeric,text,text,text,uuid),public.create_warehouse_material(uuid,jsonb,uuid),public.warehouse_movements(uuid,uuid,text,integer) from public,anon;
grant execute on function public.configure_product_supply(uuid,uuid,text),public.receive_warehouse_stock(uuid,uuid,text,text,numeric,text,text,text,uuid),public.create_warehouse_material(uuid,jsonb,uuid),public.warehouse_movements(uuid,uuid,text,integer) to authenticated;

-- One transaction for source, stocking policy and thresholds; no intermediate refill.
create function public.configure_warehouse_product(factory uuid,product uuid,source text,mode text,unit text,minimum numeric default null,maximum numeric default null) returns uuid
language plpgsql security definer set search_path='' as $$begin
 perform public.configure_product_supply(factory,product,source);
 return public.configure_product_stock(factory,product,mode,unit,minimum,maximum);
end$$;
create function private.guard_production_source() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.fulfillment_lock(new.factory_id);
 if new.status in ('planned','active') and exists(select 1 from public.products p where p.factory_id=new.factory_id and p.id=new.product_id and p.supply_source='EXTERNAL')
 then raise exception 'fulfillment_source_decision';end if;return new;end$$;
create trigger production_source_guard before insert or update of product_id,status on public.production_orders for each row execute function private.guard_production_source();

create function public.sales_planning_guidance(factory uuid,item uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare job public.production_orders;context jsonb;due timestamptz;target timestamptz;buffer integer;plan jsonb;forward_plan jsonb;state text;begin
 perform private.require_permission(factory,'orders','view');
 select * into job from public.production_orders where factory_id=factory and id=item and status='planned';if not found then raise exception 'fulfillment_state';end if;
 context:=public.fulfillment_production_context(factory,item);
 select s.requested_delivery,s.safety_buffer_days,(x->>'target_ready')::timestamptz into due,buffer,target
 from jsonb_array_elements(context->'rows') x join public.sales_orders s on s.id=(x->>'sales_order_id')::uuid
 where s.requested_delivery is not null order by (x->>'target_ready')::timestamptz,s.id limit 1;
 if due is null then return jsonb_build_object('requested_delivery',null,'state','no_target');end if;
 plan:=private.fulfillment_slot(factory,job.product_id,job.unit,job.target_quantity,job.id,target,true);
 if plan is not null then state:='achievable';else
  plan:=private.fulfillment_slot(factory,job.product_id,job.unit,job.target_quantity,job.id,due,true);
  if plan is not null then state:='tight';else
   forward_plan:=private.fulfillment_slot(factory,job.product_id,job.unit,job.target_quantity,job.id);
   state:=case when forward_plan is not null or exists(
    select 1 from public.production_lines ln join lateral (
     select count(*) matches,count(*) filter(where c.rate_unit=job.unit) typed,min(c.rate) slowest,max(c.rate) fastest,min(c.setup_minutes) shortest,max(c.setup_minutes) longest
     from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id
     where w.factory_id=factory and w.line_id=ln.id and not w.archived and c.product_id=job.product_id
    ) rates on true where ln.factory_id=factory and not ln.archived and rates.matches>0 and rates.typed=rates.matches and rates.slowest=rates.fastest and rates.shortest=rates.longest
    and not exists(select 1 from public.production_orders o where o.factory_id=factory and o.line_id=ln.id and o.id<>job.id and o.status in ('planned','active')
     and (o.start_time is null or o.expected_finish is null or (o.status='active' and o.expected_finish<now())))
   ) then 'unachievable' else 'insufficient' end;
  end if;
 end if;
 return jsonb_build_object('requested_delivery',due,'target_ready',target,'safety_buffer_days',buffer,'state',state,'suggestion',plan,'earliest',forward_plan);
end$$;
revoke all on function private.guard_production_source() from public,anon,authenticated;
revoke all on function public.configure_warehouse_product(uuid,uuid,text,text,text,numeric,numeric),public.sales_planning_guidance(uuid,uuid) from public,anon;
grant execute on function public.configure_warehouse_product(uuid,uuid,text,text,text,numeric,numeric),public.sales_planning_guidance(uuid,uuid) to authenticated;

-- Allocate uncommitted received Good output to approved stock demand, including deliberate hybrid production.
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
 if delta>0 then perform private.reserve_received_stock(new.factory_id,job.product_id,new.unit);end if;
 return new;
end$$;
