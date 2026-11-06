begin;
truncate late_test.checks;
do $$declare x jsonb;y jsonb;f uuid;w jsonb;r jsonb;p jsonb;so uuid;sl uuid;i uuid;state jsonb;begin
 -- Replacement has no input issue; actual Start alone must still prohibit undo.
 x:=output4_test.context('Started replacement');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);y:=output4_test.start(x,w);
 perform output4c_test.publish(x,output4cb2_test.finding(x,'reduction'));x:=x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'output_work_started');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'output_allocation_retirement_required');
 perform late_test.ok((select status='active' from public.production_orders where id=(w->>'item_id')::uuid) and (select warehouse_quantity=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'started replacement and stored source unchanged');

 x:=output4_test.context('Consumed and inspected recovery');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);y:=output4_test.start(x,w);
 r:=public.record_manufactured_output(f,output2_test.payload(y,4)||jsonb_build_object('input_lot',x->>'lot','input_quantity',4),gen_random_uuid());
 perform output4_test.receive(f,(r->>'entry_id')::uuid);
 perform output4c_test.publish(x,output4cb2_test.finding(x,'reduction'));x:=x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'output_work_started');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'output_allocation_retirement_required');
 perform late_test.ok((select quantity_available=6 and warehouse_quantity=0 from public.unfinished_lots where id=(x->>'lot')::uuid) and private.output_demand_received(f,(x->>'item')::uuid)=94,'consumed four and inspected child receipt are neither undone nor fulfilled twice');
 perform late_test.ok(private.output_source_held(f,(r->>'entry_id')::uuid) and private.output_accounting(f,(x->>'output')::uuid)->>'pending'='true','authoritative finding retains downstream source hold');

 x:=output4_test.context('Elapsed held schedule');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 perform public.plan_product_item(f,(w->>'item_id')::uuid,(x->>'line')::uuid,now()-interval '20 seconds');
 perform output4c_test.publish(x,output4cb2_test.finding(x,'reduction'));x:=x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'planning_already_started');
 perform late_test.ok((select start_time<=now() and status='planned' from public.production_orders where id=(w->>'item_id')::uuid),'elapsed Planning history not rewritten');

 x:=output4_test.context('Dependent stock recovery');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);
 r:=output4_test.decision(x||'{"revision":5}','STOCK',4);
 perform output4c_test.publish(x,output4cb2_test.finding(x,'reduction'));x:=x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'output_work_dependent');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'output_allocation_retirement_required');
 perform late_test.ok((select replaced=10 and stock=4 and reserved=4 from private.output_work_allocations(f,(x->>'lot')::uuid)) and (select warehouse_quantity=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'dependent STOCK entitlement and request preserved');

 x:=output4_test.context('Committed replacement');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);
 insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,1,'meter') returning id into sl;
 insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,sl,(w->>'item_id')::uuid,1);
 perform output4c_test.publish(x,output4cb2_test.finding(x,'reduction'));x:=x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'output_work_committed');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'output_allocation_retirement_required');
 perform late_test.ok((select quantity=1 and released_quantity=0 from public.sales_incoming_allocations where line_id=sl),'no automatic Sales redistribution to bypass commitment');

 -- Stale Planning state is independently checked even if source revision is current.
 x:=output4cb2_test.context('Stale cancellation state');f:=(x->>'factory')::uuid;p:=output4b_test.payload(x,x->'work');
 perform public.plan_product_item(f,(x#>>'{work,item_id}')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '5 days');
 perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L,6,%L)',f,x#>>'{work,item_id}',p,gen_random_uuid()),'output_revision');
 perform late_test.ok((select status='planned' and line_id is not null from public.production_orders where id=(x#>>'{work,item_id}')::uuid),'stale cancellation cannot unschedule newer Planning state');

 -- Original Sales commitments convert only the actual four confirmed meters.
 x:=output4_test.context('Original Sales ownership');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,100,'meter') returning id into sl;
 perform private.reserve_finished(f,sl,90);
 insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,sl,(x->>'item')::uuid,10);
 perform output4c_test.publish(x,output4cb2_test.finding(x,'reduction'));x:=x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform output4cb2_test.cancel(x);x:=x||'{"expected":7}';r:=output4cb2_test.apply(x);
 perform late_test.ok((select on_hand=90 and reserved=90 from public.finished_goods_balances where factory_id=f) and (select quantity=10 from public.sales_incoming_allocations where line_id=sl),'withdrawal/cancellation do not steal original stock or incoming commitment');
 perform output4cb2_test.receive(x,(r->>'handoff_group')::uuid,4,8);
 perform late_test.ok((select on_hand=94 and reserved=94 from public.finished_goods_balances where factory_id=f) and (select quantity=6 and received_quantity=4 from public.sales_incoming_allocations where line_id=sl),'only confirmed four convert original incoming into reserved stock');
 perform late_test.ok((select count(*)=2 from public.production_orders where factory_id=f),'Sales conversion creates no automatic recovery or replacement');
end$$;
select count(*) assertions from late_test.checks;
rollback;
