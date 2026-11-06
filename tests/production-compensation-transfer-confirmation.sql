do $$declare x jsonb;f uuid;a jsonb;p jsonb;r jsonb;before_n bigint;begin
 x:=compensation_test.fixture('transfer-confirmation');f:=(x->>'factory')::uuid;a:=compensation_test.replace(x,6);
 perform public.finish_product_item(f,(x->>'item')::uuid);
 select count(*) into before_n from private.manufactured_completion_work where factory_id=f;
 p:=jsonb_build_object('allowance_id',a->>'compensation_id','quantity','6','mode','PLANNED','reason','All actual output recorded; unmade allowance needs a planned job');
 perform late_test.fails(format('select public.plan_production_compensation(%L,%L,%L,4,%L)',f,x->>'output',p,gen_random_uuid()),'output_recording_confirmation');
 perform compensation_test.ok((select count(*)=before_n from private.manufactured_completion_work where factory_id=f) and private.compensation_remaining(f,(a->>'compensation_id')::uuid)=6,'Finish alone cannot move allowance away from still-permitted same-shift recording');
 r:=public.plan_production_compensation(f,(x->>'output')::uuid,p||'{"recording_complete_confirmation":true}'::jsonb,4,gen_random_uuid());
 perform compensation_test.ok(private.compensation_remaining(f,(a->>'compensation_id')::uuid)=0 and (select intent#>>'{payload,recording_complete_confirmation}'='true' from private.manufactured_completion_work where item_id=(r->>'item_id')::uuid),'explicit recording-complete attestation is immutable with the transfer decision');
end$$;
select count(*) from compensation_test.checks;
