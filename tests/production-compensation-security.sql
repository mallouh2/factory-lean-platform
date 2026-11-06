do $$declare x jsonb;f uuid;p jsonb;r jsonb;k uuid:=gen_random_uuid();i uuid;before_n bigint;begin
 x:=compensation_test.fixture('security');f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;
 p:=late_test.payload(x,2)||jsonb_build_object('confirm_overproduction',true,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','2','missing_operations','[]'::jsonb)));
 select count(*) into before_n from public.production_entries where order_id=i;
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,k),'output_compensation_required');
 r:=compensation_test.replace(x,2);
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,k),'recording_stale_context');
 p:=late_test.payload(x,3)||jsonb_build_object('confirm_overproduction',true,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','3','missing_operations','[]'::jsonb)));
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,k),'output_compensation_exceeded');
 perform compensation_test.ok((select count(*)=before_n from public.production_entries where order_id=i),'unapproved stale or excessive output creates no entry');
 p:=late_test.payload(x,2)||jsonb_build_object('confirm_overproduction',true,'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','2','missing_operations','[]'::jsonb)));
 r:=public.record_manufactured_output(f,p,k);perform public.record_manufactured_output(f,p,k);
 perform compensation_test.ok((select count(*)=1 from public.production_entries where factory_id=f and request_id=k) and private.compensation_recorded(f,i)=2,'recording UUID replay attributes two exactly once');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p||'{"notes":"Changed replay"}',k),'request_conflict');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform late_test.fails(format('select compensation_test.replace(%L::jsonb,1)',x),'permission_denied');
 perform late_test.fails(format('select public.production_compensation_read(%L,%L)',gen_random_uuid(),x->>'output'),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform late_test.fails(format('select public.production_compensation_read(%L,%L)',f,gen_random_uuid()),'output_not_found');
 perform compensation_test.ok(private.compensation_recorded(f,i)=2 and (select count(*)=1 from private.production_compensation where item_id=i),'denials and edited retries preserve allowance and output');
 insert into compensation_test.contexts values('security-result',x||jsonb_build_object('receipt',r,'payload',p,'uuid',k));
end$$;
-- Hold after receiving must block new compensation; no physical stock adjusted.
do $$declare x jsonb;f uuid;o uuid;g jsonb;before_n bigint;begin
 x:=compensation_test.fixture('hold');f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 g:=public.plan_manufactured_completion(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','COMPLETE','operations',jsonb_build_array(x->>'step1'),'reason','Protected issued input hold fixture'),3,gen_random_uuid());
 perform public.supply_command(f,'material_change',jsonb_build_object('id',g->>'material_request_id','revision',1,'action','issue','reason','Issue four identified meters'),gen_random_uuid());
 select jsonb_agg(value||case when value->>'id'=x->>'unfinished' then '{"quantity":"3","released":"3"}'::jsonb else '{}'::jsonb end) into g from jsonb_array_elements(private.output_quality(f,o)->'groups');
 perform public.manufactured_output_command(f,'QUALITY',o,jsonb_build_object('groups',g,'total','909','rejected','3','actual_rejected_kg','1.5','reason','One issued meter found defective'),4,gen_random_uuid());
 x:=x||'{"revision":5}';
 perform late_test.fails(format('select compensation_test.replace(%L::jsonb,3)',x),'output_quality_hold');
 perform compensation_test.ok(public.production_compensation_read(f,o)->>'blocked_reason'='output_quality_hold' and not exists(select 1 from private.production_compensation where output_id=o),'unreconciled stored finding blocks compensation without stock mutation');
end$$;
select count(*) from compensation_test.checks;
