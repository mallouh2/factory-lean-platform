-- Current occurrence, not yesterday's completed work or a merely scheduled item.
do $$declare x jsonb;foreign_x jsonb;f uuid;p jsonb;finish_at time;req uuid;item uuid;begin
 x:=late_test.new_context('activation-next-shift',1.5);f:=(x->>'factory')::uuid;
 select end_time into finish_at from public.production_shifts where id=(x->>'shift')::uuid;
 perform public.configure_production_shift(f,'Next occurrence','الوردية التالية',finish_at,finish_at+interval '1 hour');
 update private.production_recording_v3_activation set enabled=true,schema_contract_version=3 where factory_id=f;
 p:=late_test.payload(x,1);perform pg_sleep(1.6);
 perform late_test.ok(public.production_shift_work(f)->>'available'='true' and jsonb_array_length(public.production_shift_work(f)->'rows')=0,'previous-shift completion excluded in next active occurrence');
 perform late_test.fails(format('select public.record_lean_production(%L,%L,%L)',f,p,gen_random_uuid()),'recording_stale_context');
 update private.production_recording_v3_activation set enabled=false,schema_contract_version=0 where factory_id=f;
 foreign_x:=mp_test.fixture('activation-foreign');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform late_test.fails(format('select public.production_shift_work(%L)',foreign_x->>'factory'),'42501');
 perform late_test.fails(format('select public.record_lean_production(%L,%L,%L)',foreign_x->>'factory',p,gen_random_uuid()),'42501');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 req:=public.create_production_request(f,'Scheduled only','normal',null,'Never started fixture',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',10,'unit','meter')));
 select id into item from public.production_orders where request_id=req;
 perform public.plan_product_item(f,item,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '3 days');
 perform late_test.ok(public.production_shift_work(f)->>'available'='true' and jsonb_array_length(public.production_shift_work(f)->'rows')=0,'never-started scheduled work excluded within a verified current occurrence');
end$$;
select count(*) as activation_checks from late_test.checks;
