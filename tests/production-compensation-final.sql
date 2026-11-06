-- Physical unfinished released from demand is still reusable stock, never a
-- second entitlement to fulfill the original order.
do $$declare x jsonb;f uuid;w jsonb;p jsonb;lot uuid;v bigint;begin
 select c.x into x from compensation_test.contexts c where label='active-all';f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);
 select max(revision) into v from private.manufactured_output_events where output_id=(x->>'output')::uuid;
 w:=public.plan_manufactured_completion(f,(x->>'output')::uuid,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','STOCK','operations',jsonb_build_array(x->>'step1'),'reason','Complete legitimately released stock independently'),v,gen_random_uuid());
 perform public.plan_product_item(f,(w->>'item_id')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '2 days');
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Issue released physical stock'),gen_random_uuid());
 perform public.start_product_item(f,(w->>'item_id')::uuid);select lot_id into lot from private.manufactured_completion_work where item_id=(w->>'item_id')::uuid;
 p:=compensation_test.finish_output(x||jsonb_build_object('item',w->>'item_id'),4,jsonb_build_object('input_lot',lot,'input_quantity',4));
 perform public.finish_product_item(f,(w->>'item_id')::uuid);
 perform public.receive_manufactured_output(f,(p->>'output')::uuid,jsonb_build_object('group_id',p->>'group','quantity','4','location','Independent released stock','physical_confirmation',true),2,gen_random_uuid());
 perform compensation_test.ok(private.output_demand_received(f,(x->>'item')::uuid)=909 and (select on_hand=913 from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid),'released four becomes stock but never fulfills original twice');
 perform compensation_test.ok((select quantity_available=0 and warehouse_quantity=0 from public.unfinished_lots where id=lot) and private.output_work_demand(f,(w->>'item_id')::uuid) is null,'stock processing consumes preserved source with no original demand link');
 perform late_test.fails(format('update public.production_orders set target_quantity=915 where id=%L',x->>'item'),'output_compensation_identity');
 perform late_test.fails(format('update public.production_orders set status=''active'' where id=%L',x->>'item'),'output_compensation_identity');
end$$;
-- Actual protected subsequent reservation. No historical timestamps are edited.
do $$declare x jsonb;f uuid;pr uuid;next_item uuid;stamp timestamptz;w jsonb;begin
 x:=compensation_test.fixture('capacity',false,true);f:=(x->>'factory')::uuid;
 -- A second capable line is not needed. Advance no clocks; this new schedule
 -- legitimately starts immediately after the original saved window.
 select expected_finish+interval '.1 second' into stamp from public.production_orders where id=(x->>'item')::uuid;
 pr:=public.create_production_request(f,'Protected subsequent commitment','normal',null,'Capacity acceptance fixture',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',10,'unit','meter')));
 select id into next_item from public.production_orders where request_id=pr;
 perform public.plan_product_item(f,next_item,(x->>'line')::uuid,stamp);
 -- Record the reservation; the runner waits for real time if it is still beyond
 -- the extra minute. No forced start, queue skip or schedule changes.
 insert into compensation_test.contexts values('capacity-next',x||jsonb_build_object('next_item',next_item,'next_start',stamp));
end$$;
select count(*) from compensation_test.checks;
