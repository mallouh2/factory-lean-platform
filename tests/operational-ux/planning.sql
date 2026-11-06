do $$declare x jsonb;f uuid;i uuid;other uuid;pr uuid;mr uuid;revision bigint;old_start timestamptz;new_start timestamptz;before_count integer;begin
 x:=mp_test.fixture('ux-overdue');f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform public.update_settings(f,'Overdue local','UTC',null);perform public.configure_working_calendar(f,127,'00:00','23:59');
 old_start:=clock_timestamp()+interval '.3 seconds';perform public.plan_product_item(f,i,(x->>'line')::uuid,old_start);perform pg_sleep(.6);
 perform late_test.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''other'','''')',f,i,x->>'line',clock_timestamp()+interval '2 hours'),'planning_reason_required');
 new_start:=clock_timestamp()+interval '2 hours';perform public.revise_product_plan(f,i,(x->>'line')::uuid,new_start,'material_delay','Material delivery later than expected');
 perform ux_test.ok((select start_time>old_start and actual_start is null and actual_finish is null from public.production_orders where id=i),'elapsed planned start with no execution can be replanned');
 perform ux_test.ok((select count(*)=2 from public.production_plan_revisions where item_id=i)and exists(select 1 from public.production_plan_revisions where item_id=i and event='replanned' and before_start=old_start and after_start>=new_start and changed_by=(x->>'owner')::uuid),'before/after plan, reason and actor retained');
 perform public.revise_product_plan(f,i,(x->>'line')::uuid,new_start,'material_delay','Material delivery later than expected');
 perform ux_test.ok((select count(*)=2 from public.production_plan_revisions where item_id=i),'identical planning retry adds no revision');
 pr:=public.create_production_request(f,'Overlap control','normal',null,'Fixture',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',100,'unit','meter')));select id into other from public.production_orders where request_id=pr;
 perform public.plan_product_item(f,other,(x->>'line')::uuid,clock_timestamp()+interval '4 hours');
 perform late_test.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''other'',''Conflict test'')',f,other,x->>'line',new_start+interval '1 minute'),'planning_overlap');
 perform public.set_plan_lock(f,i,true);
 perform late_test.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''other'',''Locked test'')',f,i,x->>'line',clock_timestamp()+interval '6 hours'),'planning_locked');perform public.set_plan_lock(f,i,false);
 perform public.start_product_item(f,i);
 perform late_test.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''other'',''Started test'')',f,i,x->>'line',clock_timestamp()+interval '6 hours'),'planning_already_started');
 perform set_config('request.jwt.claim.sub',x->>'viewer',false);
 perform late_test.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''other'',''Denied test'')',f,other,x->>'line',clock_timestamp()+interval '6 hours'),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform late_test.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''other'',''Foreign test'')',gen_random_uuid(),other,x->>'line',clock_timestamp()+interval '6 hours'),'permission_denied');
 -- Actual protected Warehouse issue, not a fabricated issued status.
 perform public.adjust_finished_stock(f,(x->>'product')::uuid,'meter',2,'Material issue test stock',gen_random_uuid());
 mr:=public.supply_command(f,'material_request',jsonb_build_object('item',x->>'product','item_type','product','unit','meter','quantity',1,'production_item_id',other),gen_random_uuid());
 select r.revision into revision from public.material_requests r where id=mr;
 perform public.source_stock_command(f,'issue',jsonb_build_object('id',mr,'revision',revision,'reason','Controlled source issue'),jsonb_build_array(jsonb_build_object('source_id',null,'quantity','1')),gen_random_uuid());
 perform late_test.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''other'',''Issued material test'')',f,other,x->>'line',clock_timestamp()+interval '6 hours'),'planning_material_committed');
 perform ux_test.ok((select actual_start is null from public.production_orders where id=other)and(select status='ISSUED' from public.material_requests where id=mr),'issued material is distinguished from unstarted execution and prevents replan');
end$$;
