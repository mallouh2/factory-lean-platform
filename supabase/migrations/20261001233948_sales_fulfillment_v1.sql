-- Finished-goods fulfillment starts here. No historical output/stock backfill.
alter table public.permissions drop constraint permissions_action_check;
alter table public.permissions add constraint permissions_action_check
 check(action in ('view','create','edit','delete','approve','export','issue'));
insert into public.permissions(module,action) values
 ('sales_orders','view'),('sales_orders','create'),('sales_orders','edit'),('sales_orders','approve'),
 ('warehouse','view'),('warehouse','edit'),('warehouse','issue');
-- Existing owner semantics use explicit person grants, never a runtime role bypass.
insert into public.user_permissions(factory_id,user_id,module,action)
 select m.factory_id,m.user_id,p.module,p.action from public.memberships m cross join public.permissions p
 where m.is_owner and m.status='approved' and p.module in ('sales_orders','warehouse') on conflict do nothing;
alter table public.factories add column delivery_buffer_days integer not null default 2 check(delivery_buffer_days between 0 and 90);
alter table public.products add column supply_mode text not null default 'MAKE_TO_ORDER' check(supply_mode in ('MAKE_TO_ORDER','MAKE_TO_STOCK')),
 add column stock_unit text check(stock_unit in ('meter','piece')),add column minimum_stock numeric,add column maximum_stock numeric,
 add constraint product_stock_configuration check(supply_mode='MAKE_TO_ORDER' or
 (stock_unit is not null and minimum_stock is not null and maximum_stock is not null and minimum_stock>=0
 and maximum_stock>=minimum_stock and maximum_stock>0 and maximum_stock::text not in ('NaN','Infinity','-Infinity')));
create sequence private.sales_order_number_seq;
create function private.next_sales_code() returns text language plpgsql volatile set search_path='' as $$declare n text;begin
 n:=nextval('private.sales_order_number_seq')::text;return 'SO-'||lpad(n,greatest(7,length(n)),'0');end$$;
create table public.sales_orders(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 code text not null default private.next_sales_code(),
 customer_reference text not null default '' check(length(customer_reference)<=200),
 requested_by uuid not null references auth.users,created_by uuid not null references auth.users,
 requested_delivery timestamptz not null,promised_delivery timestamptz,
 safety_buffer_days integer not null check(safety_buffer_days between 0 and 90),notes text not null default '' check(length(notes)<=2000),
 status text not null default 'draft' check(status in ('draft','approved','completed','cancelled')),
 approved_at timestamptz,approved_by uuid references auth.users,created_at timestamptz not null default clock_timestamp(),
 unique(factory_id,id),unique(factory_id,code)
);
create table public.sales_order_lines(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,order_id uuid not null,product_id uuid not null,
 quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
 unit text not null check(unit in ('meter','piece')),release_when_ready boolean not null default false,
 dispatched_quantity numeric not null default 0 check(dispatched_quantity>=0 and dispatched_quantity<=quantity),
 unique(factory_id,id),unique(order_id,product_id),
 foreign key(factory_id,order_id) references public.sales_orders(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id)
);
alter table public.production_requests add column request_type text check(request_type in ('SALES_PRODUCTION','STOCK_REPLENISHMENT')),
 add column sales_order_line_id uuid,
 add foreign key(factory_id,sales_order_line_id) references public.sales_order_lines(factory_id,id);
create table public.finished_goods_balances(
 factory_id uuid not null,product_id uuid not null,unit text not null check(unit in ('meter','piece')),
 on_hand numeric not null default 0,reserved numeric not null default 0,
 primary key(factory_id,product_id,unit),foreign key(factory_id,product_id) references public.products(factory_id,id),
 check(on_hand>=0 and reserved>=0 and reserved<=on_hand)
);
create table public.finished_goods_reservations(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,line_id uuid not null,
 quantity numeric not null check(quantity>=0),unique(factory_id,line_id),
 foreign key(factory_id,line_id) references public.sales_order_lines(factory_id,id)
);
create table public.sales_incoming_allocations(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,line_id uuid not null,item_id uuid not null,
 quantity numeric not null check(quantity>=0),received_quantity numeric not null default 0 check(received_quantity>=0),
 released_quantity numeric not null default 0 check(released_quantity>=0),created_at timestamptz not null default clock_timestamp(),
 unique(factory_id,line_id,item_id),foreign key(factory_id,line_id) references public.sales_order_lines(factory_id,id),
 foreign key(factory_id,item_id) references public.production_orders(factory_id,id)
);
create table public.finished_goods_movements(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,product_id uuid not null,unit text not null,
 kind text not null check(kind in ('production_receipt','production_correction','reservation','release','dispatch','adjustment')),
 stock_delta numeric not null default 0,reserved_delta numeric not null default 0,
 sales_line_id uuid,entry_id uuid,reason text,created_by uuid references auth.users,created_at timestamptz not null default clock_timestamp(),
 foreign key(factory_id,product_id) references public.products(factory_id,id),
 foreign key(factory_id,sales_line_id) references public.sales_order_lines(factory_id,id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id)
);
create table public.finished_goods_entry_receipts(
 factory_id uuid not null,entry_id uuid not null,received_good numeric not null check(received_good>=0),
 primary key(factory_id,entry_id),foreign key(factory_id,entry_id) references public.production_entries(factory_id,id)
);
create table public.fulfillment_commands(
 factory_id uuid not null references public.factories,request_id uuid not null,actor_id uuid not null references auth.users,
 operation text not null,payload jsonb not null,result_id uuid not null,created_at timestamptz not null default clock_timestamp(),
 primary key(factory_id,request_id)
);
create function private.fulfillment_lock(f uuid) returns void language sql volatile set search_path='' as $$
 select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
$$;
create function private.fulfillment_retry(f uuid,r uuid,op text,p jsonb) returns uuid
 language plpgsql security definer set search_path='' as $$declare old public.fulfillment_commands;begin
 if r is null then raise exception 'fulfillment_invalid';end if;
 perform private.fulfillment_lock(f);
 select * into old from public.fulfillment_commands where factory_id=f and request_id=r;
 if found then
 if old.actor_id<>auth.uid() or old.operation<>op or old.payload<>p then raise exception 'request_conflict';end if;
 return old.result_id;end if;return null;
end$$;
create function public.create_sales_order(factory uuid,payload jsonb,request_id uuid default gen_random_uuid()) returns uuid
 language plpgsql security definer set search_path='' as $$declare result uuid;entry jsonb;buffer integer;begin
 perform private.require_permission(factory,'sales_orders','create');
 result:=private.fulfillment_retry(factory,request_id,'create',payload);if result is not null then return result;end if;
 if jsonb_typeof(payload)<>'object' or jsonb_typeof(payload->'lines') is distinct from 'array'
 or jsonb_array_length(payload->'lines') not between 1 and 50 or nullif(payload->>'requested_delivery','') is null
 then raise exception 'fulfillment_invalid';end if;
 if nullif(payload->>'promised_delivery','') is not null then perform private.require_permission(factory,'sales_orders','approve');end if;
 select delivery_buffer_days into buffer from public.factories where id=factory;
 if payload ? 'safety_buffer_days' and (payload->>'safety_buffer_days')::integer<>buffer then
 perform private.require_permission(factory,'sales_orders','approve');buffer:=(payload->>'safety_buffer_days')::integer;end if;
 insert into public.sales_orders(factory_id,customer_reference,requested_by,created_by,requested_delivery,promised_delivery,safety_buffer_days,notes)
 values(factory,coalesce(payload->>'customer_reference',''),auth.uid(),auth.uid(),(payload->>'requested_delivery')::timestamptz,
 nullif(payload->>'promised_delivery','')::timestamptz,buffer,coalesce(payload->>'notes','')) returning id into result;
 for entry in select value from jsonb_array_elements(payload->'lines') loop
 if not exists(select 1 from public.products where factory_id=factory and id=(entry->>'product_id')::uuid and stage='finished')
 then raise exception 'fulfillment_product';end if;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit,release_when_ready)
 values(factory,result,(entry->>'product_id')::uuid,(entry->>'quantity')::numeric,entry->>'unit',coalesce((entry->>'release_when_ready')::boolean,false));
 end loop;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'create',payload,result,clock_timestamp());return result;
end$$;
create function public.approve_sales_order(factory uuid,sales_order uuid,request_id uuid default gen_random_uuid()) returns uuid
 language plpgsql security definer set search_path='' as $$declare old uuid;s public.sales_orders;l record;p jsonb:=jsonb_build_object('order',sales_order);begin
 perform private.require_permission(factory,'sales_orders','approve');
 old:=private.fulfillment_retry(factory,request_id,'approve',p);if old is not null then return old;end if;
 select * into s from public.sales_orders where factory_id=factory and id=sales_order for update;
 if not found or s.status='cancelled' then raise exception 'fulfillment_state';end if;
 if s.status='draft' then
 update public.sales_orders set status='approved',approved_at=clock_timestamp(),approved_by=auth.uid() where id=sales_order;
 for l in select id,product_id from public.sales_order_lines where factory_id=factory and order_id=sales_order order by id loop
 perform private.allocate_sales_line(factory,l.id);end loop;
 for l in select distinct product_id from public.sales_order_lines where order_id=sales_order loop perform private.replenish_finished(factory,l.product_id);end loop;
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'approve',p,sales_order,clock_timestamp());return sales_order;
end$$;
create function public.change_sales_order(factory uuid,sales_order uuid,payload jsonb,reason text,request_id uuid default gen_random_uuid()) returns uuid
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
 for a in select a.*,o.status,o.actual_start,o.planning_locked_at,r.sales_order_line_id
 from public.sales_incoming_allocations a join public.production_orders o on o.id=a.item_id join public.production_requests r on r.id=o.request_id
 where a.factory_id=factory and a.line_id=l.id and a.quantity>0 loop
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
create function public.dispatch_sales_order(factory uuid,sales_order uuid,line uuid default null,request_id uuid default gen_random_uuid()) returns uuid
 language plpgsql security definer set search_path='' as $$declare s public.sales_orders;l record;old uuid;all_ready boolean;p jsonb:=jsonb_build_object('order',sales_order,'line',line);begin
 perform private.require_permission(factory,'warehouse','issue');
 old:=private.fulfillment_retry(factory,request_id,'dispatch',p);if old is not null then return old;end if;
 select * into s from public.sales_orders where factory_id=factory and id=sales_order for update;
 if not found or s.status<>'approved' then raise exception 'fulfillment_state';end if;
 select bool_and(coalesce(r.quantity,0)>=l.quantity-l.dispatched_quantity) into all_ready from public.sales_order_lines l
 left join public.finished_goods_reservations r on r.line_id=l.id where l.factory_id=factory and l.order_id=sales_order;
 if line is not null and not exists(select 1 from public.sales_order_lines l where l.factory_id=factory and l.order_id=sales_order and l.id=line
 and (l.release_when_ready or all_ready)) then raise exception 'fulfillment_hold';end if;
 if line is null and not all_ready then raise exception 'fulfillment_hold';end if;
 for l in select l.*,coalesce(r.quantity,0) reserved_quantity from public.sales_order_lines l
 left join public.finished_goods_reservations r on r.line_id=l.id where l.factory_id=factory and l.order_id=sales_order
 and (line is null or l.id=line) and l.dispatched_quantity<l.quantity order by l.id loop
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
create function public.configure_product_stock(factory uuid,product uuid,mode text,unit text,minimum numeric default null,maximum numeric default null)
 returns uuid language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'warehouse','edit');perform private.fulfillment_lock(factory);
 if mode not in ('MAKE_TO_STOCK','MAKE_TO_ORDER') or unit not in ('meter','piece') or mode is null or unit is null then raise exception 'fulfillment_invalid';end if;
 update public.products set supply_mode=mode,stock_unit=configure_product_stock.unit,minimum_stock=minimum,maximum_stock=maximum where factory_id=factory and id=product and stage='finished';
 if not found then raise exception 'fulfillment_product';end if;perform private.finished_balance(factory,product,unit);
 perform private.replenish_finished(factory,product);return product;
end$$;
create function public.configure_delivery_buffer(factory uuid,days integer) returns void
 language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'settings','edit');update public.factories set delivery_buffer_days=days where id=factory;
end$$;
create function public.adjust_finished_stock(factory uuid,product uuid,unit text,quantity numeric,reason text,request_id uuid default gen_random_uuid())
 returns uuid language plpgsql security definer set search_path='' as $$declare old uuid;result uuid:=gen_random_uuid();p jsonb:=jsonb_build_object('product',product,'unit',unit,'quantity',quantity,'reason',reason);l record;begin
 perform private.require_permission(factory,'warehouse','edit');old:=private.fulfillment_retry(factory,request_id,'adjust',p);if old is not null then return old;end if;
 if quantity is null or quantity=0 or quantity::text in ('NaN','Infinity','-Infinity') or unit not in ('meter','piece') or length(trim(coalesce(reason,''))) not between 3 and 2000
 or not exists(select 1 from public.products where factory_id=factory and id=product and stage='finished') then raise exception 'fulfillment_invalid';end if;
 perform private.finished_balance(factory,product,unit);
 if exists(select 1 from public.finished_goods_balances b where b.factory_id=factory and b.product_id=product and b.unit=adjust_finished_stock.unit and b.on_hand+quantity<b.reserved) then raise exception 'fulfillment_stock_committed';end if;
 update public.finished_goods_balances set on_hand=on_hand+quantity where factory_id=factory and product_id=product and finished_goods_balances.unit=adjust_finished_stock.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,created_by) values(result,factory,product,unit,'adjustment',quantity,reason,auth.uid());
 -- Fill genuine unallocated demand, not an existing production commitment a second time.
 for l in select l.id from public.sales_order_lines l join public.sales_orders s on s.id=l.order_id where l.factory_id=factory and l.product_id=product and l.unit=adjust_finished_stock.unit and s.status='approved' order by s.created_at,l.id loop
 perform private.allocate_sales_line(factory,l.id);end loop;
 perform private.replenish_finished(factory,product);
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'adjust',p,result,clock_timestamp());return result;
end$$;
create function private.finished_balance(f uuid,p uuid,u text) returns void
 language plpgsql security definer set search_path='' as $$begin
 insert into public.finished_goods_balances(factory_id,product_id,unit) values(f,p,u) on conflict do nothing;
end$$;
create function private.reserve_finished(f uuid,l uuid,q numeric) returns void
 language plpgsql security definer set search_path='' as $$declare ln public.sales_order_lines;begin
 if q=0 then return;end if;
 select * into ln from public.sales_order_lines where factory_id=f and id=l;
 update public.finished_goods_balances set reserved=reserved+q where factory_id=f and product_id=ln.product_id and unit=ln.unit;
 update public.finished_goods_reservations set quantity=quantity+q where factory_id=f and line_id=l;
 if not found then insert into public.finished_goods_reservations(factory_id,line_id,quantity) values(f,l,q);end if;
 insert into public.finished_goods_movements(factory_id,product_id,unit,kind,reserved_delta,sales_line_id,created_by)
 values(f,ln.product_id,ln.unit,case when q>0 then 'reservation' else 'release' end,q,l,auth.uid());
end$$;
create function private.fulfillment_production(f uuid,p uuid,u text,q numeric,kind text,l uuid,due timestamptz) returns uuid
 language plpgsql security definer set search_path='' as $$declare r uuid;i uuid;begin
 insert into public.production_requests(factory_id,code,name,requested_by,requested_by_name,priority,required_by,request_type,sales_order_line_id)
 values(f,'',case when kind='SALES_PRODUCTION' then 'Sales production' else 'Stock replenishment' end,auth.uid(),
 (select display_name from public.memberships where factory_id=f and user_id=auth.uid()),
 case when kind='SALES_PRODUCTION' then 'high' else 'low' end,due,kind,l) returning id into r;
 insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit) values(f,r,p,q,u) returning id into i;
 return i;
end$$;
create function private.projected_finished(f uuid,p uuid,u text,excluding uuid default null) returns numeric
 language sql stable security definer set search_path='' as $$
 select coalesce((select on_hand-reserved from public.finished_goods_balances where factory_id=f and product_id=p and unit=u),0)
 +coalesce((select sum(o.remaining_quantity) from public.production_orders o where o.factory_id=f and o.product_id=p and o.unit=u
 and o.status in ('planned','active') and o.id is distinct from excluding),0)
 -coalesce((select sum(a.quantity) from public.sales_incoming_allocations a join public.sales_order_lines l on l.id=a.line_id
 where a.factory_id=f and l.product_id=p and l.unit=u),0)
 -coalesce((select sum(greatest(l.quantity-l.dispatched_quantity-coalesce(r.quantity,0)
 -(select coalesce(sum(a.quantity),0) from public.sales_incoming_allocations a where a.factory_id=f and a.line_id=l.id),0))
 from public.sales_order_lines l join public.sales_orders s on s.id=l.order_id left join public.finished_goods_reservations r on r.line_id=l.id
 where l.factory_id=f and l.product_id=p and l.unit=u and s.status='approved'),0);
$$;
create function private.replenish_finished(f uuid,p uuid) returns void
 language plpgsql security definer set search_path='' as $$declare prod public.products;editable public.production_orders;base numeric;needed numeric;begin
 perform private.fulfillment_lock(f);
 select * into prod from public.products where factory_id=f and id=p;
 if prod.supply_mode<>'MAKE_TO_STOCK' then return;end if;
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
end$$;
create function private.allocate_sales_line(f uuid,line uuid) returns void
 language plpgsql security definer set search_path='' as $$declare l public.sales_order_lines;s public.sales_orders;need numeric;take numeric;stock numeric;candidate record;i uuid;begin
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
 and o.expected_finish<=least(s.requested_delivery,coalesce(s.promised_delivery,s.requested_delivery))
 and (r.request_type is null or r.request_type='STOCK_REPLENISHMENT'))) order by o.expected_finish,o.id for update of o loop
 take:=least(need,greatest(candidate.free_quantity,0));
 if take>0 then insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,l.id,candidate.id,take)
 on conflict(factory_id,line_id,item_id) do update set quantity=public.sales_incoming_allocations.quantity+excluded.quantity;need:=need-take;end if;
 exit when need=0;end loop;
 if need>0 then
 i:=private.fulfillment_production(f,l.product_id,l.unit,need,'SALES_PRODUCTION',l.id,s.requested_delivery);
 insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,l.id,i,need);
 end if;
end$$;
-- The receipt trigger is the boundary even when an existing Recording helper is called directly.
create function private.capture_finished_good() returns trigger language plpgsql security definer set search_path='' as $$
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
 for a in select a.id,a.line_id,a.quantity from public.sales_incoming_allocations a
 join public.sales_order_lines l on l.id=a.line_id join public.sales_orders s on s.id=l.order_id
 where a.factory_id=new.factory_id and a.item_id=job.id and a.quantity>0 and s.status='approved' order by s.created_at,a.id for update of a loop
 take:=least(leftover,a.quantity);exit when take<=0;
 perform private.reserve_finished(new.factory_id,a.line_id,take);
 update public.sales_incoming_allocations set quantity=quantity-take,received_quantity=received_quantity+take where id=a.id;
 leftover:=leftover-take;end loop;
 return new;
end$$;
create trigger finished_goods_receipt after insert or update of effective_good on public.production_entries
 for each row execute function private.capture_finished_good();
create function private.refresh_finished_projection() returns trigger language plpgsql security definer set search_path='' as $$declare a record;begin
 if new.status='cancelled' then
 for a in select distinct line_id from public.sales_incoming_allocations where item_id=new.id and quantity>0 loop
 update public.sales_incoming_allocations set released_quantity=released_quantity+quantity,quantity=0 where item_id=new.id and line_id=a.line_id;
 perform private.allocate_sales_line(new.factory_id,a.line_id);end loop;end if;
 -- Run after all Recording/correction writes so incoming and receipts cannot be double-counted.
 perform private.replenish_finished(new.factory_id,new.product_id);return new;
end$$;
create constraint trigger finished_goods_projection after update on public.production_orders
 deferrable initially deferred for each row
 when(old.produced_quantity is distinct from new.produced_quantity or old.rejected_quantity is distinct from new.rejected_quantity or old.status is distinct from new.status)
 execute function private.refresh_finished_projection();

-- One-line feasibility uses the exact existing rate/setup/calendar model. No schedule writes.
-- Extra windows simulate the other lines of the same Sales Order to avoid double-booking its forecast.
create function private.fulfillment_slot(f uuid,p uuid,u text,q numeric,exclude_item uuid default null,
 deadline timestamptz default null,backward boolean default false,extra jsonb default '[]') returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare ln record;gap record;rates record;minutes numeric;start_at timestamptz;finish_at timestamptz;
 cursor_at timestamptz;horizon timestamptz:=coalesce(deadline,now()+interval '180 days');lo timestamptz;hi timestamptz;mid timestamptz;candidate jsonb;best jsonb;begin
 for ln in select l.id from public.production_lines l where l.factory_id=f and not l.archived and l.paused_at is null order by l.id loop
 select count(*) matches,count(*) filter(where c.rate_unit=u) typed,min(c.rate) slowest,max(c.rate) fastest,min(c.setup_minutes) shortest,max(c.setup_minutes) longest into rates
 from public.work_centers w join public.work_center_capabilities c on c.factory_id=w.factory_id and c.work_center_id=w.id
 where w.factory_id=f and w.line_id=ln.id and not w.archived and c.product_id=p;
 if rates.matches=0 or rates.typed<>rates.matches or rates.slowest<>rates.fastest or rates.shortest<>rates.longest then continue;end if;
 minutes:=ceil(q/rates.slowest*60)+rates.shortest;if minutes<1 or minutes>5256000 then continue;end if;
 if exists(select 1 from public.production_orders o where o.factory_id=f and o.line_id=ln.id and o.id is distinct from exclude_item and o.status in ('planned','active')
 and (o.start_time is null or o.expected_finish is null or (o.status='active' and o.expected_finish<now()))) then continue;end if;
 cursor_at:=now();
 for gap in select x.start_at,x.finish_at from (
 select o.start_time start_at,o.expected_finish finish_at from public.production_orders o where o.factory_id=f and o.line_id=ln.id
 and o.id is distinct from exclude_item and o.status in ('planned','active') and o.expected_finish>now()
 union all select (x->>'start')::timestamptz,(x->>'finish')::timestamptz from jsonb_array_elements(extra) x where (x->>'line')::uuid=ln.id
 union all select horizon,horizon) x order by start_at,finish_at loop
 if gap.start_at>cursor_at then
 start_at:=private.next_working_start(f,cursor_at);finish_at:=private.finish_after_working_minutes(f,start_at,minutes::integer);
 if finish_at<=gap.start_at and finish_at<=horizon then
 if backward then
 lo:=cursor_at;hi:=gap.start_at;
 for step in 1..40 loop
 if hi-lo<=interval '1 minute' then exit;end if;
 mid:=lo+(hi-lo)/2;start_at:=private.next_working_start(f,mid);
 if private.finish_after_working_minutes(f,start_at,minutes::integer)<=gap.start_at then lo:=mid;else hi:=mid;end if;end loop;
 start_at:=private.next_working_start(f,lo);finish_at:=private.finish_after_working_minutes(f,start_at,minutes::integer);
 end if;
 candidate:=jsonb_build_object('line',ln.id,'start',start_at,'finish',finish_at,'minutes',minutes);
 if best is null or (not backward and finish_at<(best->>'finish')::timestamptz) or (backward and finish_at>(best->>'finish')::timestamptz) then best:=candidate;end if;
 end if;end if;
 cursor_at:=greatest(cursor_at,gap.finish_at);end loop;
 end loop;return best;
end$$;
create function private.sales_order_detail(f uuid,sales uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare s public.sales_orders;l record;a record;lines jsonb:='[]';line_ready timestamptz;earliest timestamptz:=now();estimated timestamptz:=now();
 plan jsonb;virtual jsonb:='[]';unknown boolean:=false;target timestamptz;all_ready boolean:=true;line_complete boolean;ready boolean;reserved numeric;incoming numeric;production_needed numeric;state text;risk text;begin
 select * into s from public.sales_orders where factory_id=f and id=sales;
 if not found then return null;end if;
 select ((coalesce(s.promised_delivery,s.requested_delivery) at time zone timezone)-make_interval(days=>s.safety_buffer_days)) at time zone timezone into target from public.factories where id=f;
 for l in select l.*,p.name product_name,p.name_ar product_name_ar from public.sales_order_lines l join public.products p on p.id=l.product_id where l.factory_id=f and l.order_id=sales order by l.id loop
 select coalesce(sum(quantity),0) into reserved from public.finished_goods_reservations where factory_id=f and line_id=l.id;
 select coalesce(sum(quantity),0) into incoming from public.sales_incoming_allocations where factory_id=f and line_id=l.id;
 production_needed:=greatest(l.quantity-l.dispatched_quantity-reserved,0);line_complete:=l.dispatched_quantity=l.quantity;
 ready:=line_complete or reserved>=l.quantity-l.dispatched_quantity;all_ready:=all_ready and ready;
 if s.status='draft' then
 production_needed:=greatest(production_needed-coalesce((select on_hand-reserved from public.finished_goods_balances where factory_id=f and product_id=l.product_id and unit=l.unit),0),0);
 end if;
 line_ready:=now();
 for a in select o.*,r.request_type,a.quantity allocated from public.sales_incoming_allocations a join public.production_orders o on o.id=a.item_id
 join public.production_requests r on r.id=o.request_id where a.factory_id=f and a.line_id=l.id and a.quantity>0 order by o.id loop
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
create function public.sales_orders_page(factory uuid,page integer default 1,selected uuid default null) returns jsonb
 language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 perform private.require_permission(factory,'sales_orders','view');
 if page is null or page not between 1 and 1000000 then raise exception 'fulfillment_invalid';end if;
 select coalesce(jsonb_agg(private.sales_order_detail(factory,id) order by created_at desc,id),'[]') into result
 from(select id,created_at from public.sales_orders where factory_id=factory order by created_at desc,id limit 25 offset (page-1)*25)s;
 return jsonb_build_object('rows',result,'total',(select count(*) from public.sales_orders where factory_id=factory),
 'page',page,'page_size',25,'selected',case when selected is not null then private.sales_order_detail(factory,selected) end);
end$$;
create function public.warehouse_page(factory uuid,page integer default 1) returns jsonb
 language plpgsql stable security definer set search_path='' as $$declare balances jsonb;orders jsonb;begin
 perform private.require_permission(factory,'warehouse','view');if page is null or page not between 1 and 1000000 then raise exception 'fulfillment_invalid';end if;
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('available',x.on_hand-x.reserved,'projected',private.projected_finished(factory,x.product_id,x.unit),
 'incoming',(select coalesce(sum(o.remaining_quantity),0) from public.production_orders o where o.factory_id=factory and o.product_id=x.product_id and o.unit=x.unit and o.status in ('planned','active')))),'[]')
 into balances from(select b.*,p.name,p.name_ar,p.supply_mode,p.minimum_stock,p.maximum_stock from public.finished_goods_balances b join public.products p on p.id=b.product_id
 where b.factory_id=factory order by p.name,b.unit limit 50 offset (page-1)*50)x;
 select coalesce(jsonb_agg(private.sales_order_detail(factory,id) order by created_at,id),'[]') into orders
 from(select id,created_at from public.sales_orders where factory_id=factory and status='approved' order by created_at,id limit 25 offset (page-1)*25)s;
 return jsonb_build_object('rows',balances,'total',(select count(*) from public.finished_goods_balances where factory_id=factory),'orders',orders,'page',page,'page_size',50,
 'orders_total',(select count(*) from public.sales_orders where factory_id=factory and status='approved'));
end$$;
create function public.fulfillment_production_context(factory uuid,item uuid default null) returns jsonb
 language plpgsql stable security definer set search_path='' as $$declare rows jsonb;begin
 perform private.require_permission(factory,'orders','view');
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from(
 select o.id item_id,r.request_type,l.order_id sales_order_id,s.code sales_order_code,s.requested_delivery,s.promised_delivery,
 (private.sales_order_detail(factory,s.id)->>'target_ready')::timestamptz target_ready,
 private.sales_order_detail(factory,s.id)->>'risk' risk,
 (private.sales_order_detail(factory,s.id)->>'estimated_ready')::timestamptz estimated_ready,
 a.quantity incoming_allocated
 from public.production_orders o join public.production_requests r on r.id=o.request_id
 left join public.sales_incoming_allocations a on a.item_id=o.id and a.quantity>0
 left join public.sales_order_lines l on l.id=a.line_id left join public.sales_orders s on s.id=l.order_id and s.status='approved'
 where o.factory_id=factory and o.status in ('planned','active') and (item is null or o.id=item)
 and (r.request_type is not null or a.id is not null) order by o.id limit 500)x;
 return jsonb_build_object('rows',rows);
end$$;
create function public.sales_planning_slot(factory uuid,item uuid) returns jsonb
 language plpgsql stable security definer set search_path='' as $$declare job public.production_orders;context jsonb;target timestamptz;begin
 perform private.require_permission(factory,'orders','view');
 select * into job from public.production_orders where factory_id=factory and id=item and status='planned';if not found then raise exception 'fulfillment_state';end if;
 context:=public.fulfillment_production_context(factory,item);
 select min((x->>'target_ready')::timestamptz) into target from jsonb_array_elements(context->'rows') x;
 if target is null then return null;end if;
 return private.fulfillment_slot(factory,job.product_id,job.unit,job.target_quantity,job.id,target,true);
end$$;

do $$declare t text;fn record;begin
 foreach t in array array['sales_orders','sales_order_lines','finished_goods_balances','finished_goods_reservations','sales_incoming_allocations','finished_goods_movements','finished_goods_entry_receipts','fulfillment_commands'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('create index on public.%I(factory_id)',t);
 if t in ('sales_orders','sales_order_lines','finished_goods_reservations','sales_incoming_allocations','finished_goods_movements') then
 execute format('create trigger audit_fulfillment after insert or update or delete on public.%I for each row execute function private.audit_change()',t);end if;
 end loop;
 -- Reads use scoped RPCs; no new direct writes or large snapshot arrays.
 for fn in select p.oid::regprocedure signature,n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='private' and p.proname in ('next_sales_code','fulfillment_lock','fulfillment_retry','finished_balance','reserve_finished','fulfillment_production','projected_finished','replenish_finished','allocate_sales_line','capture_finished_good','refresh_finished_projection','fulfillment_slot','sales_order_detail'))
 or (n.nspname='public' and p.proname in ('create_sales_order','approve_sales_order','change_sales_order','dispatch_sales_order','configure_product_stock','configure_delivery_buffer','adjust_finished_stock','sales_orders_page','warehouse_page','fulfillment_production_context','sales_planning_slot')) loop
 execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 if fn.nspname='public' then execute format('grant execute on function %s to authenticated',fn.signature);end if;
 end loop;
end$$;
