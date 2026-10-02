-- TESTING only. All fixtures, permission changes, outputs and audit changes roll back.
begin;
create function pg_temp.sales_assert(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Sales fulfillment assertion: %',label;end if;end$$;
create function pg_temp.sales_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=expected then return;end if;raise exception 'expected %, got %',expected,sqlerrm;end;
 raise exception 'expected % but command succeeded',expected;end$$;
do $test$
declare f uuid;actor uuid;tech uuid;p uuid;p2 uuid;stockp uuid;ln uuid;wc uuid;s uuid;s2 uuid;s3 uuid;s4 uuid;
 l uuid;l2 uuid;i uuid;i2 uuid;r uuid:=gen_random_uuid();entry uuid;req uuid;qty numeric;info jsonb;plan jsonb;before_plan jsonb;before_machines jsonb;before_transfers jsonb;
 before_legacy jsonb;original_items integer;due timestamptz;promised timestamptz;
begin
 select m.factory_id,m.user_id,m.id into f,actor,tech from public.memberships m join public.factories fac on fac.id=m.factory_id
 where fac.is_demo and m.status='approved' and m.is_owner limit 1;
 if f is null then raise exception 'existing TESTING actor required';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select jsonb_agg(to_jsonb(x) order by id) into before_legacy from public.production_orders x;
 select jsonb_agg(to_jsonb(x) order by id) into before_machines from public.work_centers x;
 select jsonb_agg(to_jsonb(x) order by id) into before_transfers from public.production_transfers x;
 update public.production_shifts set archived=true where factory_id=f and not archived;
 update public.factories set working_days_mask=127,workday_start='00:00',workday_end='23:59' where id=f;
 insert into public.products(factory_id,name,code,unit) values(f,'Sales QA meter','SF-'||substr(gen_random_uuid()::text,1,8),'meter') returning id into p;
 insert into public.products(factory_id,name,code,unit) values(f,'Sales QA piece','SF-'||substr(gen_random_uuid()::text,1,8),'piece') returning id into p2;
 insert into public.products(factory_id,name,code,unit) values(f,'Sales QA stock','SF-'||substr(gen_random_uuid()::text,1,8),'meter') returning id into stockp;
 insert into public.production_lines(factory_id,name,code) values(f,'Sales QA line','SF-'||substr(gen_random_uuid()::text,1,8)) returning id into ln;
 insert into public.work_centers(factory_id,name,code,line_id,category_id)
 select f,'Sales QA center','SF-'||substr(gen_random_uuid()::text,1,8),ln,category_id from public.work_centers where factory_id=f and category_id is not null limit 1 returning id into wc;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,wc,p,100,'meter'),(f,wc,p2,100,'piece'),(f,wc,stockp,100,'meter');
 due:=now()+interval '10 days';promised:=due+interval '1 day';
 perform public.configure_product_stock(f,p,'MAKE_TO_ORDER','meter');
 perform public.adjust_finished_stock(f,p,'meter',150,'QA opening stock',r);
 perform public.adjust_finished_stock(f,p,'meter',150,'QA opening stock',r);
 perform pg_temp.sales_assert((select on_hand=150 from public.finished_goods_balances where product_id=p),'stock adjustment retry');
 -- A: fully stocked approval reserves without physical dispatch or production.
 s:=public.create_sales_order(f,jsonb_build_object('requested_delivery',due,'promised_delivery',promised,'lines',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',100,'unit','meter'))));
 perform pg_temp.sales_assert((select status='draft' from public.sales_orders where id=s),'draft');
 info:=private.sales_order_detail(f,s);perform pg_temp.sales_assert((info->'lines'->0->>'production_required')::numeric=0 and info->>'earliest_feasible' is not null,'stocked draft reads without reservation');
 r:=gen_random_uuid();perform public.approve_sales_order(f,s,r);perform public.approve_sales_order(f,s,r);
 select id into l from public.sales_order_lines where order_id=s;
 perform pg_temp.sales_assert((select on_hand=150 and reserved=100 from public.finished_goods_balances where product_id=p),'approval reserve not issue');
 perform pg_temp.sales_assert(not exists(select 1 from public.production_requests where sales_order_line_id=l),'full stock no PR');
 perform pg_temp.sales_error(format('select public.adjust_finished_stock(%L,%L,%L,-100,%L)',f,p,'meter','QA reserved removal'),'fulfillment_stock_committed');
 r:=gen_random_uuid();perform public.dispatch_sales_order(f,s,request_id=>r);perform public.dispatch_sales_order(f,s,request_id=>r);
 perform pg_temp.sales_assert((select on_hand=50 and reserved=0 from public.finished_goods_balances where product_id=p),'dispatch physical deduction exactly once');
 perform pg_temp.sales_assert((select status='completed' from public.sales_orders where id=s),'completion requires dispatch');
 -- B/C/G/H: shortage, Good receipt, scrap/WIP exclusion and excess stock.
 s2:=public.create_sales_order(f,jsonb_build_object('requested_delivery',due,'promised_delivery',promised,'lines',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',100,'unit','meter'))));perform public.approve_sales_order(f,s2);
 select id into l from public.sales_order_lines where order_id=s2;
 select o.id,o.request_id into i,req from public.production_orders o join public.production_requests pr on pr.id=o.request_id where pr.sales_order_line_id=l and o.status='planned';
 perform pg_temp.sales_assert((select target_quantity=50 and line_id is null from public.production_orders where id=i),'shortage exactly 50/manual Planning');
 update public.production_orders set target_quantity=60 where id=i;update public.production_orders set target_quantity=50 where id=i;
 perform pg_temp.sales_assert((select target_quantity=50 from public.production_orders where id=i),'safe quantity edits that preserve commitments');
 perform pg_temp.sales_error(format('update public.production_orders set target_quantity=20 where id=%L',i),'fulfillment_stock_committed');
 perform pg_temp.sales_error(format('update public.production_orders set unit=%L where id=%L','piece',i),'fulfillment_stock_committed');
 perform pg_temp.sales_assert((select quantity=50 from public.finished_goods_reservations where line_id=l),'partial stock reservation');
 info:=private.sales_order_detail(f,s2);perform pg_temp.sales_assert((info->>'earliest_feasible') is not null,'capacity-derived feasibility');
 plan:=public.sales_planning_slot(f,i);perform pg_temp.sales_assert(plan is not null and (plan->>'finish')::timestamptz<=(info->>'target_ready')::timestamptz,'backward buffered slot');
 -- Metadata-only edits preserve generated request and allocation identity.
 perform public.change_sales_order(f,s2,jsonb_build_object('requested_delivery',due+interval '1 day','lines',jsonb_build_array(jsonb_build_object('id',l,'quantity',100,'release_when_ready',false))),'QA date correction');
 perform pg_temp.sales_assert((select status='planned' from public.production_orders where id=i),'metadata edit keeps PR');
 -- Test setup moves this isolated job into the past so normal execution can run now.
 update public.production_orders set line_id=ln,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=i;
 select jsonb_build_array(line_id,start_time,expected_finish) into before_plan from public.production_orders where id=i;
 perform public.start_product_item(f,i);
 entry:=public.record_production(f,'line',ln,i,tech,25,5,unfinished=>5,remaining_work=>'Packing');
 perform pg_temp.sales_assert((select on_hand=75 and reserved=75 from public.finished_goods_balances where product_id=p),'Good only receipts; scrap and unfinished excluded');
 perform pg_temp.sales_assert(exists(select 1 from public.unfinished_lots where source_entry_id=entry and quantity_available=5),'WIP separate');
 perform pg_temp.sales_error(format('select public.dispatch_sales_order(%L,%L)',f,s2),'fulfillment_hold');
 perform pg_temp.sales_error(format('select public.correct_production_entry(%L,%L,20,5,%L,unfinished=>5,remaining_work=>%L)',f,entry,'QA committed correction','Packing'),'fulfillment_stock_committed');
 r:=gen_random_uuid();entry:=public.record_production(f,'line',ln,i,tech,35,0,confirm_overproduction=>true,request_id=>r);
 perform public.record_production(f,'line',ln,i,tech,35,0,confirm_overproduction=>true,request_id=>r);
 perform pg_temp.sales_assert((select on_hand=110 and reserved=100 from public.finished_goods_balances where product_id=p),'excess 10 available/receipt retry');
 perform public.finish_product_item(f,i);perform public.dispatch_sales_order(f,s2);
 perform pg_temp.sales_assert((select on_hand=10 and reserved=0 from public.finished_goods_balances where product_id=p),'excess after dispatch');
 perform pg_temp.sales_assert((select jsonb_build_array(line_id,start_time,expected_finish) from public.production_orders where id=i)=before_plan,'Planning preserved');
 -- D: MTS projected trigger/max, no duplicate refill.
 perform public.configure_product_stock(f,stockp,'MAKE_TO_STOCK','meter',40,100);
 select o.id into i2 from public.production_orders o join public.production_requests pr on pr.id=o.request_id where o.product_id=stockp and o.status='planned' and pr.request_type='STOCK_REPLENISHMENT';
 perform private.replenish_finished(f,stockp);perform pg_temp.sales_assert((select count(*)=1 from public.production_orders where product_id=stockp and status='planned'),'single replenishment');
 perform pg_temp.sales_assert(private.projected_finished(f,stockp,'meter')=100,'projected includes incoming');
 -- F: compatible scheduled replenishment allocated before generating Sales production.
 update public.production_orders set line_id=ln,start_time=now()+interval '1 hour',expected_finish=now()+interval '2 hours' where id=i2;
 s3:=public.create_sales_order(f,jsonb_build_object('requested_delivery',due,'lines',jsonb_build_array(jsonb_build_object('product_id',stockp,'quantity',30,'unit','meter'))));perform public.approve_sales_order(f,s3);
 select id into l2 from public.sales_order_lines where order_id=s3;
 perform pg_temp.sales_assert(exists(select 1 from public.sales_incoming_allocations where line_id=l2 and item_id=i2 and quantity=30),'incoming refill reuse');
 perform pg_temp.sales_assert(not exists(select 1 from public.production_requests where sales_order_line_id=l2),'incoming no duplicated Sales production');
 perform pg_temp.sales_assert(private.projected_finished(f,stockp,'meter')=70,'incoming minus commitment');
 -- E/F: multiple products, default hold, complete-line-only early release.
 s4:=public.create_sales_order(f,jsonb_build_object('requested_delivery',due,'lines',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',10,'unit','meter'),jsonb_build_object('product_id',p2,'quantity',5,'unit','piece'))));perform public.approve_sales_order(f,s4);
 select id into l from public.sales_order_lines where order_id=s4 and product_id=p;
 perform pg_temp.sales_error(format('select public.dispatch_sales_order(%L,%L,%L)',f,s4,l),'fulfillment_hold');
 perform public.change_sales_order(f,s4,jsonb_build_object('lines',(select jsonb_agg(jsonb_build_object('id',sl.id,'quantity',sl.quantity,'release_when_ready',sl.id=l)) from public.sales_order_lines sl where sl.order_id=s4)),'QA explicit early release');
 perform public.dispatch_sales_order(f,s4,l);
 perform pg_temp.sales_assert((select status='approved' from public.sales_orders where id=s4),'not completed while another product unfinished');
 perform pg_temp.sales_error(format('select public.change_sales_order(%L,%L,%L::jsonb,%L)',f,s4,jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('id',l,'quantity',1))),'QA below dispatched'),'fulfillment_invalid');
 perform public.change_sales_order(f,s4,'{"cancel":true}','QA cancellation');
 -- Active cancellation/reduction: do not cancel or reschedule actual work.
 s4:=public.create_sales_order(f,jsonb_build_object('requested_delivery',due,'lines',jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',20,'unit','piece'))));perform public.approve_sales_order(f,s4);
 select id into l from public.sales_order_lines where order_id=s4;
 select o.id into i from public.production_orders o join public.production_requests pr on pr.id=o.request_id where pr.sales_order_line_id=l and o.status='planned';
 update public.production_orders set line_id=ln,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=i;perform public.start_product_item(f,i);
 perform public.change_sales_order(f,s4,jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('id',l,'quantity',10))),'QA demand reduction');
 perform pg_temp.sales_assert((select status='active' and target_quantity=20 from public.production_orders where id=i),'active work preserved on reduction');
 perform pg_temp.sales_assert((select sum(quantity)=10 from public.sales_incoming_allocations where line_id=l),'active allocation reduced without duplicate');
 perform public.change_sales_order(f,s4,'{"cancel":true}','QA active cancellation');
 perform pg_temp.sales_assert((select status='active' from public.production_orders where id=i),'active cancellation does not cancel job');
 perform public.record_production(f,'line',ln,i,tech,20,0);perform public.finish_product_item(f,i);
 perform pg_temp.sales_assert((select on_hand=20 and reserved=0 from public.finished_goods_balances where product_id=p2),'cancelled demand output becomes free stock');
 -- I/J: impossible date and plan-slip risk without promise mutation.
 s4:=public.create_sales_order(f,jsonb_build_object('requested_delivery',now()-interval '1 day','promised_delivery',now()+interval '1 day','lines',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',100,'unit','meter'))));perform public.approve_sales_order(f,s4);
 info:=private.sales_order_detail(f,s4);perform pg_temp.sales_assert((info->>'requested_feasible')::boolean=false,'impossible requested date');
 select id into l from public.sales_order_lines where order_id=s4;
 select o.id into i from public.production_orders o join public.production_requests pr on pr.id=o.request_id where pr.sales_order_line_id=l and o.status='planned';
 update public.production_orders set line_id=ln,start_time=now()+interval '2 days',expected_finish=now()+interval '3 days' where id=i;
 info:=private.sales_order_detail(f,s4);perform pg_temp.sales_assert((info->>'earliest_feasible')::timestamptz<(info->>'estimated_ready')::timestamptz,'earliest differs from delayed current plan');perform pg_temp.sales_assert(info->>'risk'='late' and (info->>'promised_delivery')::timestamptz<now()+interval '2 days','plan slip risk/promised immutable');
 perform pg_temp.sales_assert(exists(select 1 from jsonb_array_elements(public.fulfillment_production_context(f,i)->'rows') x where x->>'risk'='late'),'Planning/Floor context');
 -- Scope/authorization/direct-write denial independent of preview role.
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 perform pg_temp.sales_error(format('select public.approve_sales_order(%L,%L)',f,s4),'permission_denied');
 perform pg_temp.sales_error(format('select public.warehouse_page(%L)',f),'permission_denied');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform pg_temp.sales_error(format('select public.approve_sales_order(%L,%L)',gen_random_uuid(),s4),'permission_denied');
 perform pg_temp.sales_assert(not has_table_privilege('authenticated','public.finished_goods_balances','update'),'RLS direct stock writes denied');
 perform pg_temp.sales_assert(not has_function_privilege('authenticated','private.allocate_sales_line(uuid,uuid)','execute'),'helper inaccessible');
 perform pg_temp.sales_assert(exists(select 1 from public.audit_logs where entity='sales_orders' and entity_id=s4),'audit exists');
 perform pg_temp.sales_assert(before_machines=(select jsonb_agg(to_jsonb(x) order by id) from public.work_centers x where id<>wc),'machines unchanged');
 perform pg_temp.sales_assert(before_transfers is not distinct from (select jsonb_agg(to_jsonb(x) order by id) from public.production_transfers x),'transfers unchanged');
 perform pg_temp.sales_assert(before_legacy=(select jsonb_agg(to_jsonb(x) order by id) from public.production_orders x where product_id not in (p,p2,stockp)),'legacy unchanged');
 -- Exercise deferred projection hooks before rollback, not after test assertions.
 set constraints all immediate;
end $test$;
rollback;
select 'Sales fulfillment A-J + reservation/dispatch/receipt/retry/cancel/RLS/legacy passed' result;
