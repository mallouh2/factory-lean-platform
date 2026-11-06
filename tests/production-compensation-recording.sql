do $$declare x jsonb;f uuid;r jsonb;p jsonb;k uuid:=gen_random_uuid();stamp timestamptz;begin
 x:=compensation_test.fixture('same-shift');f:=(x->>'factory')::uuid;
 perform compensation_test.replace(x,2);perform public.finish_product_item(f,(x->>'item')::uuid);
 select actual_finish into stamp from public.production_orders where id=(x->>'item')::uuid;
 p:=late_test.payload(x,2)||jsonb_build_object('confirm_overproduction',false,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','2','missing_operations','[]'::jsonb)));
 r:=public.record_manufactured_output(f,p,k);perform public.record_manufactured_output(f,p,k);
 perform compensation_test.ok(private.compensation_recorded(f,(x->>'item')::uuid)=2 and (select recording_kind='LATE_ORDINARY' and effective_period_end=stamp and not overproduction_confirmed from public.production_entries where id=(r->>'entry_id')::uuid),'approved allowance records after Finish in actual same open shift without generic overproduction');
 perform compensation_test.ok((select status='completed' and actual_finish=stamp and target_quantity=909 from public.production_orders where id=(x->>'item')::uuid) and not exists(select 1 from private.production_recording_v3_activation where enabled),'same-shift allowance never reopens execution or activates after-shift recording');
end$$;
-- Once unused entitlement has moved to Planning, stale late recording cannot
-- also spend it on the ended original execution.
do $$declare x jsonb;f uuid;p jsonb;n bigint;begin
 select c.x into x from compensation_test.contexts c where label='unused-active';f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);
 p:=late_test.payload(x,6)||jsonb_build_object('confirm_overproduction',false,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','6','missing_operations','[]'::jsonb)));
 select count(*) into n from public.production_entries where order_id=(x->>'item')::uuid;
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'output_compensation_exceeded');
 perform compensation_test.ok((select count(*)=n from public.production_entries where order_id=(x->>'item')::uuid),'planned transfer prevents duplicate same-shift allowance spending');
end$$;
select count(*) from compensation_test.checks;
