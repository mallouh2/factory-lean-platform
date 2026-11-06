-- Deterministic disposable fixtures, never a hosted seed.
do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55491 then raise exception 'Disposable Phase4B localhost only';end if;end$$;
create schema output4b_test;
create function output4b_test.payload(x jsonb,w jsonb,action text default 'CANCEL',choice text default null) returns jsonb language plpgsql as $$
declare s jsonb;p jsonb;begin
 s:=private.output_work_revision_state((x->>'factory')::uuid,(w->>'item_id')::uuid);
 p:=jsonb_build_object('action',action,'reason','Controlled change before physical issue','expected_state',s->'state');
 if action='CHANGE' then p:=p||jsonb_build_object('choice',choice,'operations',case when choice='COMPLETE' then jsonb_build_array(x->>'step1') else '[]'::jsonb end);end if;
 return p;
end$$;
create function output4b_test.revise(x jsonb,w jsonb,action text default 'CANCEL',choice text default null) returns jsonb language sql as $$
 select public.revise_manufactured_completion((x->>'factory')::uuid,(w->>'item_id')::uuid,output4b_test.payload(x,w,action,choice),
 (private.output_work_revision_state((x->>'factory')::uuid,(w->>'item_id')::uuid)->>'revision')::bigint,gen_random_uuid())
$$;
begin;
truncate late_test.checks;
do $$declare x jsonb;y jsonb;w jsonb;r jsonb;p jsonb;k uuid;f uuid;i uuid;old_work jsonb;before_count bigint;choice text;ver bigint;s jsonb;package uuid;begin
 foreach choice in array array['COMPLETE','REPLACE'] loop
  x:=output4_test.context('Cancel '||choice);f:=(x->>'factory')::uuid;w:=output4_test.decision(x,choice,10);i:=(w->>'item_id')::uuid;
  select to_jsonb(a) into old_work from private.manufactured_completion_work a where item_id=i;
  p:=output4b_test.payload(x,w);k:=gen_random_uuid();r:=public.revise_manufactured_completion(f,i,p,5,k);
  perform late_test.ok((select status='cancelled' from public.production_orders where id=i),'cancel unstarted '||choice);
  perform late_test.ok((select to_jsonb(a)=old_work from private.manufactured_completion_work a where item_id=i),'immutable work retained '||choice);
  perform late_test.ok((select assigned=0 and reserved=0 and replaced=0 from private.output_work_allocations(f,(x->>'lot')::uuid)),'effective allocation released '||choice);
  perform late_test.ok((select warehouse_quantity=10 and quantity_available=10 from public.unfinished_lots where id=(x->>'lot')::uuid) and private.output_demand_received(f,(x->>'item')::uuid)=90,'stock ten and shortage ten preserved '||choice);
  if choice='COMPLETE' then perform late_test.ok((select status='CANCELLED' and movement_id is null from public.material_requests where id=(w->>'material_request_id')::uuid),'unissued request cancelled with no movement');end if;
  perform late_test.ok(public.revise_manufactured_completion(f,i,p,5,k)=r,'same UUID immutable result '||choice);
  perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L,5,%L)',f,i,p||jsonb_build_object('reason','Changed retry intent'),k),'request_conflict');
  perform late_test.ok((select count(*)=1 from private.manufactured_output_events where factory_id=f and operation='RETIRE'),'one retirement');
  perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L,6,%L)',f,i,p,gen_random_uuid()),'output_work_retired');
  perform late_test.fails(format('select public.save_record(%L,''orders'',%L,%L)',f,i,'{"status":"planned"}'),'execution_use_command');
  perform late_test.fails(format('select public.plan_product_item(%L,%L,%L,%L)',f,i,x->>'line',date_trunc('day',clock_timestamp())+interval '5 days'),'planning_already_started');
  perform late_test.fails(format('delete from public.production_orders where id=%L',i),'manufactured_output_immutable');
  perform late_test.fails(format('update private.manufactured_output_events set result=''{}'' where factory_id=%L',f),'23514');
  w:=output4_test.decision(x||jsonb_build_object('revision',6),'COMPLETE',10);
  perform late_test.ok((select assigned=10 and reserved=10 from private.output_work_allocations(f,(x->>'lot')::uuid)),'new decision uses released historical entitlement');
 end loop;
 x:=output4_test.context('Round trip');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 r:=output4b_test.revise(x,w,'CHANGE','REPLACE');w:=r->'successor';
 perform late_test.ok(w->>'choice'='REPLACE' and (select line_id is null from public.production_orders where id=(w->>'item_id')::uuid),'COMPLETE to distinct unscheduled REPLACE');
 perform late_test.ok((select assigned=10 and replaced=10 and reserved=0 from private.output_work_allocations(f,(x->>'lot')::uuid)),'exactly one replacement allocation');
 r:=output4b_test.revise(x,w,'CHANGE','COMPLETE');w:=r->'successor';
 perform late_test.ok(w->>'choice'='COMPLETE' and (select count(*)=3 from private.manufactured_completion_work where factory_id=f),'REPLACE to distinct COMPLETE preserves three identities');
 perform late_test.ok((select assigned=10 and replaced=0 and reserved=10 from private.output_work_allocations(f,(x->>'lot')::uuid)),'roundtrip uses ten not thirty');
 perform late_test.ok(private.output_demand_received(f,(x->>'item')::uuid)=90,'roundtrip never fulfills original finished shortage');
 perform late_test.ok((public.manufactured_completion_read(f)#>>'{rows,0,unassigned}')='0' and (public.manufactured_completion_read(f)#>>'{rows,0,available_to_allocate}')='0','reader agrees with authoritative allocation');
 perform late_test.ok((select count(*)=0 from private.manufactured_output_context),'revision contexts removed');

 x:=output4_test.context('Scheduled');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);i:=(w->>'item_id')::uuid;
 perform public.plan_product_item(f,i,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '5 days');
 p:=output4b_test.payload(x,w);perform public.set_plan_lock(f,i,true);
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'planning_locked');
 perform public.set_plan_lock(f,i,false);
 perform public.revise_product_plan(f,i,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '6 days','management_decision','Different slot');
 perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L,5,%L)',f,i,p,gen_random_uuid()),'output_revision');
 r:=output4b_test.revise(x,w,'CHANGE','REPLACE');
 perform late_test.ok((select line_id is null and start_time is null and expected_finish is null from public.production_orders where id=i),'old schedule cleared');
 perform late_test.ok((select count(*)=1 from public.production_plan_revisions where item_id=i and event='unscheduled' and reason_code='management_decision'),'immutable unschedule history');
 perform late_test.ok((select line_id is null from public.production_orders where id=(r#>>'{successor,item_id}')::uuid),'successor inherits no Gantt slot');

 x:=output4_test.context('Rollback');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);i:=(w->>'item_id')::uuid;
 p:=output4b_test.payload(x,w,'CHANGE','COMPLETE')||jsonb_build_object('operations',jsonb_build_array(gen_random_uuid()));
 perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L,5,%L)',f,i,p,gen_random_uuid()),'output_work_operations');
 perform late_test.ok((select status='planned' from public.production_orders where id=i) and not private.output_work_retired(f,i) and (select count(*)=1 from private.manufactured_completion_work where factory_id=f),'failed successor rolls back retirement and old cancellation');
 perform late_test.ok((select count(*)=0 from private.manufactured_output_context),'failed successor context rolled back');
 perform late_test.fails(format('select public.save_record(%L,''orders'',%L,%L)',f,i,'{"status":"cancelled"}'),'output_revision_required');

 -- Existing package and direct grants, with no role/title authorization.
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'worker')::uuid,'orders','view'),(f,(x->>'worker')::uuid,'orders','edit');
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform late_test.fails(format('select output4b_test.revise(%L,%L,''CHANGE'',''COMPLETE'')',x,w),'permission_denied');
 r:=output4b_test.revise(x,w);perform late_test.ok(r->>'action'='CANCEL','Orders edit without create can cancel replacement');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 w:=output4_test.decision(x||jsonb_build_object('revision',6),'COMPLETE',10);
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 insert into public.permission_packages(factory_id,name,created_by) values(f,'Revision Warehouse',(x->>'owner')::uuid) returning id into package;
 insert into public.permission_package_permissions(factory_id,package_id,module,action) values(f,package,'warehouse','issue');
 insert into public.member_permission_packages(factory_id,user_id,package_id) values(f,(x->>'worker')::uuid,package);
 perform set_config('request.jwt.claim.sub',x->>'worker',true);r:=output4b_test.revise(x,w);
 perform late_test.ok(r->>'action'='CANCEL','effective package Warehouse issue permits linked request cancellation');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform late_test.fails(format('select public.manufactured_completion_read(%L)',f),'permission_denied');
 y:=output4_test.context('Other factory');perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'permission_denied');

 x:=output4_test.context('Issued');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Physical source issue'),gen_random_uuid());
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_material_issued');
 y:=output4_test.start(x,w||jsonb_build_object('material_request_id',null));
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_work_started');
 r:=public.record_manufactured_output(f,output2_test.payload(y,4)||jsonb_build_object('input_lot',x->>'lot','input_quantity',4),gen_random_uuid());
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_work_started');
 perform output4_test.receive(f,(r->>'entry_id')::uuid);
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_work_started');
 perform late_test.ok((select quantity_available=6 and warehouse_quantity=0 from public.unfinished_lots where id=(x->>'lot')::uuid) and private.output_demand_received(f,(x->>'item')::uuid)=94,'rejected undo preserves partial consumption receipt and shortage');

 x:=output4_test.context('Stock dependency');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);
 y:=output4_test.decision(x||jsonb_build_object('revision',5),'STOCK',4);
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_work_dependent');
 perform late_test.fails(format('select output4b_test.revise(%L,%L,''CHANGE'',''COMPLETE'')',x,w),'output_work_dependent');
 perform late_test.ok((select assigned=10 and replaced=10 and stock=4 and reserved=4 from private.output_work_allocations(f,(x->>'lot')::uuid)),'dependent four preserved');
 perform late_test.ok(not has_function_privilege('anon','public.revise_manufactured_completion(uuid,uuid,jsonb,bigint,uuid)','execute') and not has_table_privilege('authenticated','private.manufactured_output_events','insert'),'RPC grants and immutable events protected');
end$$;
set constraints all immediate;
select count(*) assertions from late_test.checks;
rollback;
