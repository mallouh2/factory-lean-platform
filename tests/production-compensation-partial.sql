-- Install partial_fixture from the existing fixture body with target100 and
-- initial recorded50 (see partial-fixture.mjs); no historical quantity edits.
do $$declare x jsonb;f uuid;r jsonb;p jsonb;h uuid;g jsonb;begin
 x:=compensation_test.partial_fixture('partial-current',false,true);f:=(x->>'factory')::uuid;
 perform compensation_test.ok(public.production_compensation_read(f,(x->>'output')::uuid)->>'available'='2','partial baseline50 plus accepted48 exposes only two replacement meters');
 perform compensation_test.replace(x,2);
 p:=late_test.payload(x,2)||jsonb_build_object('confirm_overproduction',false,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','2','missing_operations','[]'::jsonb)));
 r:=public.record_manufactured_output(f,p,gen_random_uuid());
 perform compensation_test.ok(private.compensation_recorded(f,(x->>'item')::uuid)=2 and (select quantity=2 from private.production_compensation_entries where entry_id=(r->>'entry_id')::uuid),'next output is explicitly attributed to allowance before original baseline is exhausted');
 p:=late_test.payload(x,50)||jsonb_build_object('confirm_overproduction',false,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','50','missing_operations','[]'::jsonb)));
 r:=public.record_manufactured_output(f,p,gen_random_uuid());
 perform compensation_test.ok(private.compensation_recorded(f,(x->>'item')::uuid)=2 and not exists(select 1 from private.production_compensation_entries where entry_id=(r->>'entry_id')::uuid) and (select target_quantity=100 from public.production_orders where id=(x->>'item')::uuid),'remaining fifty stays baseline with original requirement100');
 p:=late_test.payload(x,1)||jsonb_build_object('confirm_overproduction',true,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','1','missing_operations','[]'::jsonb)));
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'output_compensation_exceeded');
 perform compensation_test.ok(private.compensation_gross(f,(x->>'item')::uuid)=102 and private.output_demand_received(f,(x->>'item')::uuid)=0,'baseline and allowance cap102 raw units; no fabricated receipt');
end$$;
select count(*) from compensation_test.checks;
