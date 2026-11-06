do $$declare x jsonb;f uuid;w jsonb;p jsonb;r jsonb;begin
 x:=compensation_test.fixture('planned-budget',true,true);f:=(x->>'factory')::uuid;w:=compensation_test.replace(x,5);
 perform public.plan_product_item(f,(w->>'item_id')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '1 day');perform public.start_product_item(f,(w->>'item_id')::uuid);
 x:=x||jsonb_build_object('item',w->>'item_id');
 p:=late_test.payload(x,6)||jsonb_build_object('confirm_overproduction',true,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','6','missing_operations','[]'::jsonb)));
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'output_compensation_exceeded');
 perform compensation_test.ok(not exists(select 1 from public.production_entries where order_id=(w->>'item_id')::uuid),'planned compensation cannot bypass its quantity budget with ordinary overproduction confirmation');
 r:=compensation_test.finish_output(x,5);perform public.finish_product_item(f,(w->>'item_id')::uuid);
 perform compensation_test.ok(private.compensation_gross(f,(w->>'item_id')::uuid)=5 and (select status='completed' from public.production_orders where id=(w->>'item_id')::uuid),'valid planned replacement still records and finishes normally after rejected excess');
end$$;
select count(*) from compensation_test.checks;
