do $$declare x jsonb;f uuid;w jsonb;g jsonb;begin
 x:=compensation_test.fixture('revised-planned',true,true);f:=(x->>'factory')::uuid;w:=compensation_test.replace(x,5);
 g:=private.output_quality(f,(x->>'output')::uuid)->'groups';
 perform public.manufactured_output_command(f,'QUALITY',(x->>'output')::uuid,jsonb_build_object('groups',g,'total','100','rejected','5','actual_rejected_kg','2.5','reason','New authoritative review requires work revalidation'),2,gen_random_uuid());
 perform public.plan_product_item(f,(w->>'item_id')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '1 day');
 perform late_test.fails(format('select public.start_product_item(%L,%L)',f,w->>'item_id'),'output_compensation_stale');
 perform compensation_test.ok((select status='planned' and actual_start is null from public.production_orders where id=(w->>'item_id')::uuid),'later Quality revision cannot start obsolete planned replacement');
end$$;
do $$declare x jsonb;f uuid;g jsonb;w jsonb;o uuid;begin
 x:=compensation_test.fixture('fully-held');f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 w:=public.plan_manufactured_completion(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','COMPLETE','operations',jsonb_build_array(x->>'step1'),'reason','Issue identified source before changed finding'),3,gen_random_uuid());
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Four identified meters physically issued'),gen_random_uuid());
 perform public.manufactured_output_command(f,'QUALITY',o,jsonb_build_object('groups','[]'::jsonb,'total','909','rejected','909','actual_rejected_kg','454.5','reason','Entire physical batch requires reconciliation'),4,gen_random_uuid());
 perform compensation_test.ok(public.production_compensation_read(f,o)->>'blocked_reason'='output_quality_hold','removed finding groups cannot hide existing issued-source holds');
end$$;
do $$declare x jsonb;r jsonb;begin
 select c.x into x from compensation_test.contexts c where label='same-shift';perform set_config('request.jwt.claim.sub',x->>'owner',true);
 r:=public.manufactured_output_read((x->>'factory')::uuid,'options',(x->>'item')::uuid);
 perform compensation_test.ok(r->>'available'='true' and r->>'replacement_allowance'='0','actual recording options expose exact remaining allowance without parameter collision');
end$$;
select count(*) from compensation_test.checks;
