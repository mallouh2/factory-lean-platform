do $$declare x jsonb;f uuid;r jsonb;k uuid:=gen_random_uuid();p jsonb;s jsonb;before_start timestamptz;begin
 select c.x into x from compensation_test.contexts c where label='capacity-next';f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);
 if clock_timestamp()+interval '1 minute'<(x->>'next_start')::timestamptz then raise exception 'Wait for the real subsequent commitment window; never alter clocks or schedules';end if;
 perform late_test.fails(format('select compensation_test.replace(%L::jsonb,5)',x),'output_planning_conflict');
 s:=public.production_compensation_read(f,(x->>'output')::uuid);
 perform compensation_test.ok(s->>'active_block'='output_planning_conflict' and s->>'planned_fallback'='true','active extension reports real subsequent capacity conflict');
 p:=jsonb_build_object('quantity','5','reason','Use separate Planning work because subsequent capacity is reserved','mode','PLANNED');
 r:=public.plan_production_compensation(f,(x->>'output')::uuid,p,2,k);
 perform compensation_test.ok(r->>'mode'='PLANNED' and (r->>'item_id')::uuid<>(x->>'item')::uuid and (select line_id is null and actual_start is null from public.production_orders where id=(r->>'item_id')::uuid),'explicit capacity fallback creates unscheduled work without moving reserved jobs');
 perform compensation_test.ok((select status='active' from public.production_orders where id=(x->>'item')::uuid) and (select start_time=(x->>'next_start')::timestamptz from public.production_orders where id=(x->>'next_item')::uuid),'fallback preserves original execution and subsequent planned time');
end$$;
do $$declare x jsonb;f uuid;r jsonb;p jsonb;k uuid:=gen_random_uuid();a uuid;s jsonb;begin
 x:=compensation_test.fixture('unused-active');f:=(x->>'factory')::uuid;
 r:=compensation_test.replace(x,6);a:=(r->>'compensation_id')::uuid;
 perform public.finish_product_item(f,(x->>'item')::uuid);
 s:=public.production_compensation_read(f,(x->>'output')::uuid);
 perform compensation_test.ok(s#>>'{transfer_allowance,remaining}'='6' and s->>'available'='0','ending execution retains unused entitlement without allowing duplicate replacement');
 p:=jsonb_build_object('quantity','6','reason','Plan the unused allowance after execution ended','mode','PLANNED','allowance_id',a,'recording_complete_confirmation',true);
 r:=public.plan_production_compensation(f,(x->>'output')::uuid,p,4,k);
 perform public.plan_production_compensation(f,(x->>'output')::uuid,p,4,k);
 perform compensation_test.ok(private.compensation_remaining(f,a)=0 and (select count(*)=1 from private.production_compensation where output_id=(x->>'output')::uuid) and (select quantity=6 and choice='REPLACE' from private.manufactured_completion_work where item_id=(r->>'item_id')::uuid),'explicit unused allowance transfer creates one planned obligation and no second allowance');
 perform compensation_test.ok((select sum(quantity)=4 from private.production_compensation_releases where compensation_id=a) and (select warehouse_quantity=4 from public.unfinished_lots where id=(select lot_id from private.manufactured_output_lots where output_id=(x->>'output')::uuid)),'unused transfer does not release entitlement or stock twice');
 perform late_test.fails(format('select public.plan_production_compensation(%L,%L,%L,4,%L)',f,x->>'output',p,gen_random_uuid()),'output_compensation_transfer');
end$$;
select count(*) from compensation_test.checks;
