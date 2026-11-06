-- Actual pre-V3 active recording/correction; no fabricated execution timestamps.
do $$declare x jsonb;f uuid;m uuid;e uuid;c uuid;cause uuid:=gen_random_uuid();obs uuid:=gen_random_uuid();problem uuid;p jsonb;r uuid:=gen_random_uuid();begin
 x:=mp_test.fixture('pre-v3-upgrade');f:=(x->>'factory')::uuid;
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');
 perform public.start_product_item(f,(x->>'item')::uuid);
 select id into m from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid;
 e:=(public.record_lean_production(f,jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',x->>'item','technician',m,'good',2,'scrap_kg',.25,'discarded_quantity',0),gen_random_uuid())->>'id')::uuid;
 p:=jsonb_build_object('entry',e,'good',3,'discarded_quantity',0,'scrap_kg',.5,'reason','Pre-V3 measured correction');
 c:=public.correct_lean_production(f,p,r);
 perform public.supply_command(f,'acknowledge_good',jsonb_build_object('entry',e),gen_random_uuid());
 perform public.lean_command(f,gen_random_uuid(),'cause',jsonb_build_object('id',cause,'name','Pre-V3 preserved cause'));
 perform public.lean_command(f,gen_random_uuid(),'scrap_observation',jsonb_build_object('id',obs,'entry_id',e,'occurred_at',clock_timestamp(),'preliminary_cause_id',cause,'observation','Explicit pre-V3 exact fixture observation','response','Preserve its original assertion'));
 perform public.lean_command(f,gen_random_uuid(),'scrap_review',jsonb_build_object('id',obs,'approved_cause_id',cause,'note','Pre-V3 review','expected_revision',1));
 problem:=(public.lean_command(f,gen_random_uuid(),'problem',jsonb_build_object('mechanism','scrap','line_id',x->>'line','product_id',x->>'product','cause_id',cause,'expected_revision',0))->>'id')::uuid;
 -- Explicit saved historical fixture, not a new model calculation.
 insert into public.lean_saved_comparisons(id,factory_id,problem_id,product_id,cutoff,desired_hours,evidence,created_by)
 values(gen_random_uuid(),f,problem,(x->>'product')::uuid,clock_timestamp(),1,'{"version":1,"fixture":"pre-V3 preserved snapshot"}',(x->>'owner')::uuid);
 insert into acceptance_test.legacy values(x||jsonb_build_object('entry',e,'correction',c,'retry',r,'payload',p));
 insert into acceptance_test.historical select 'entry',id,to_jsonb(t) from public.production_entries t where factory_id=f
 union all select 'order',id,to_jsonb(t) from public.production_orders t where factory_id=f
 union all select 'source',id,to_jsonb(t) from public.finished_goods_sources t where factory_id=f
 union all select 'correction',id,to_jsonb(t) from public.production_entry_corrections t where factory_id=f
 union all select 'comparison',id,to_jsonb(t) from public.lean_saved_comparisons t where factory_id=f
 union all select 'observation',id,to_jsonb(t) from public.lean_scrap_events t where factory_id=f;
 perform acceptance_test.ok((select effective_good=3 and effective_scrap_kg=.5 from public.production_entries where id=e),'upgrade starts with real pre-V3 official quantities');
end$$;
