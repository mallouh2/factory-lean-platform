do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55497 then raise exception 'Owned same-shift fixture only';end if;end$$;
create function same_shift_test.payload(x jsonb,g numeric,w numeric default 0,s numeric default 0)returns jsonb language plpgsql as $$
declare p jsonb;groups jsonb:='[]';begin
 p:=late_test.payload(x,g)||jsonb_build_object('unfinished',w,'remaining_work',case when w>0 then 'Printing remains' else '' end,'scrap_kg',s);
 if g>0 then groups:=groups||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',g::text,'missing_operations','[]'::jsonb));end if;
 if w>0 then groups:=groups||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',w::text,'missing_operations',jsonb_build_array(x->>'step1')));end if;
 return p||jsonb_build_object('output_groups',groups);end$$;
do $$declare x jsonb;f uuid;p jsonb;r jsonb;again jsonb;key uuid:=gen_random_uuid();e public.production_entries;v jsonb;j public.production_orders;unused uuid;begin
 select t.x into x from same_shift_test.context t;f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 v:=public.production_shift_work(f);
 perform same_shift_test.ok(v->>'late_recording_available'='false' and v#>>'{rows,0,same_shift_recording_available}'='true' and v#>>'{rows,0,can_record}'='true' and v#>'{rows,0,blocked_reason}'='null'::jsonb,'FALSE late gate publishes valid completed same-shift reporting');
 p:=same_shift_test.payload(x,2,1,.1);r:=public.record_manufactured_output(f,p,key);
 select * into e from public.production_entries where id=(r->>'entry_id')::uuid;
 select * into j from public.production_orders where id=(x->>'item')::uuid;
 perform same_shift_test.ok(e.effective_good=2 and e.effective_unfinished=1 and e.effective_scrap_kg=.1 and e.effective_scrap=0,'finished/unfinished production units and measured Scrap KG preserved');
 perform same_shift_test.ok(j.status='completed' and j.actual_start=(x#>>'{before_job,actual_start}')::timestamptz and j.actual_finish=(x#>>'{before_job,actual_finish}')::timestamptz and j.start_time=(x#>>'{before_job,start_time}')::timestamptz,'execution finish/start and plan remain unchanged');
 perform same_shift_test.ok(e.original_period_end=j.actual_finish and e.original_period_end<e.created_at and e.execution_key=p#>>'{recording_context,execution_key}','completed recording uses actual execution period, not submission time');
 perform same_shift_test.ok(e.original_occurrence_key=p#>>'{recording_context,occurrence_key}' and e.shift_id=(x->>'shift')::uuid,'source execution and occurrence/shift retained');
 perform same_shift_test.ok(not exists(select 1 from public.finished_goods_movements where factory_id=f) and not exists(select 1 from public.unfinished_lots where factory_id=f),'new output produces no Warehouse credit or available unfinished stock');
 v:=public.manufactured_output_read(f,'quality',null,0);
 perform same_shift_test.ok(exists(select 1 from jsonb_array_elements(v->'rows')a where a->>'entry_id'=e.id::text),'actual declaration appears in protected Quality queue');
 perform same_shift_test.ok(not exists(select 1 from private.manufactured_output_events where factory_id=f and operation in ('QUALITY','RECEIPT')),'stopped before Quality determination or stock receipt');
 again:=public.record_manufactured_output(f,p,key);
 perform same_shift_test.ok(again->>'entry_id'=r->>'entry_id' and again->>'replayed'='true' and (select count(*)=1 from public.production_entries where factory_id=f),'same UUID replay is exact-once');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p||'{"good":3}',key),'request_conflict');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'recording_stale_context');
 perform same_shift_test.ok((select count(*)=1 and sum(effective_good)=2 and sum(effective_scrap_kg)=.1 from public.production_entries where factory_id=f),'conflicting UUID and stale second UUID conserve quantities');
 -- Fresh reads still support the existing additive-recording contract.
 p:=same_shift_test.payload(x,1);again:=public.record_manufactured_output(f,p,gen_random_uuid());
 perform same_shift_test.ok((select count(*)=2 and sum(effective_good)=3 from public.production_entries where factory_id=f),'fresh explicit additional declaration preserves existing cumulative semantics');
 unused:=public.create_production_request(f,'Never started','normal',null,'Not executable evidence',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',2,'unit','meter')));
 select id into unused from public.production_orders where request_id=unused;
 perform same_shift_test.ok(not exists(select 1 from jsonb_array_elements(public.production_shift_work(f)->'rows')a where a->>'item_id'=unused::text),'never-started job excluded');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,jsonb_set(p,'{item}',to_jsonb(unused::text)),gen_random_uuid()),'recording_stale_context');
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'permission_denied');
 perform set_config('request.jwt.claim.sub',(select t.x->>'owner'from late_test.context t),false);
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'permission_denied');
 perform same_shift_test.ok(not exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0),'late recording gate remains FALSE/schema0');
end$$;

-- A zero-Good declaration also invalidates stale forms: no duplicate unfinished/Scrap.
do $$declare x jsonb;f uuid;s uuid;p jsonb;begin
 x:=late_test.new_context('same-shift-wip',3600,true);f:=(x->>'factory')::uuid;
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id)values(f,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid)returning id into s;x:=x||jsonb_build_object('step1',s);
 p:=same_shift_test.payload(x,0,2,.1);perform public.record_manufactured_output(f,p,gen_random_uuid());
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'recording_stale_context');
 perform same_shift_test.ok((select count(*)=1 and sum(effective_unfinished)=2 and sum(effective_scrap_kg)=.1 from public.production_entries where factory_id=f),'zero-Good stale submissions cannot duplicate unfinished or Scrap');
end$$;

-- Current active production keeps working with both shipped gates disabled.
do $$declare x jsonb;f uuid;p jsonb;begin
 x:=late_test.new_context('same-shift-active',3600,false);f:=(x->>'factory')::uuid;p:=same_shift_test.payload(x,1);
 perform public.record_manufactured_output(f,p,gen_random_uuid());
 perform same_shift_test.ok((select status='active' from public.production_orders where id=(x->>'item')::uuid) and (select count(*)=1 from public.production_entries where factory_id=f),'in-progress recording remains valid');
end$$;

-- Wait for the real clock, never rewrite execution evidence or shift boundaries.
do $$declare x jsonb;f uuid;p jsonb;r jsonb;key uuid:=gen_random_uuid();s time;second uuid;begin
 x:=late_test.new_context('same-shift-real-expiry',2.5,true);f:=(x->>'factory')::uuid;
 select end_time into s from public.production_shifts where id=(x->>'shift')::uuid;
 second:=public.configure_production_shift(f,'Following shift','الوردية التالية',s,s+interval '1 hour');
 p:=same_shift_test.payload(x,1);r:=public.record_manufactured_output(f,p,key);perform pg_sleep(2.7);
 perform same_shift_test.ok(not exists(select 1 from jsonb_array_elements(public.production_shift_work(f)->'rows')a where a->>'item_id'=x->>'item'),'completed prior-shift job not offered in following shift');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,p,gen_random_uuid()),'recording_stale_context');
 perform same_shift_test.ok((public.record_manufactured_output(f,p,key)->>'entry_id')=r->>'entry_id' and (select count(*)=1 from public.production_entries where factory_id=f),'after-shift exact receipt recovery creates no additional production');
end$$;
select count(*) as same_shift_assertions from same_shift_test.checks;
