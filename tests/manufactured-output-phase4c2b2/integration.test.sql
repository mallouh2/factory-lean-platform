do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55491 then raise exception 'Disposable localhost only';end if;end$$;
create schema output4cb2_test;
create function output4cb2_test.finding(x jsonb,kind text) returns jsonb language plpgsql as $$
declare qa jsonb;g jsonb;groups jsonb:='[]';begin
 qa:=private.output_quality((x->>'factory')::uuid,(x->>'output')::uuid);
 for g in select value from jsonb_array_elements(qa->'groups') loop
  if jsonb_array_length(g->'missing_operations')=0 then
   if kind='reduction' then g:=g||'{"quantity":"94","released":"94"}';end if;groups:=groups||jsonb_build_array(g);
  elsif kind='operations' then groups:=groups||jsonb_build_array(g||jsonb_build_object('id',gen_random_uuid(),'missing_operations',jsonb_build_array(x->>'step2',x->>'step1')));
  elsif kind='split' then groups:=groups||jsonb_build_array(g||'{"quantity":"6","released":"6"}',jsonb_build_object('id',gen_random_uuid(),'quantity','4','released','4','missing_operations',jsonb_build_array(x->>'step2'),'restriction',''));
  elsif kind='split_new' then groups:=groups||jsonb_build_array(g||jsonb_build_object('id',gen_random_uuid(),'quantity','6','released','6'),jsonb_build_object('id',gen_random_uuid(),'quantity','4','released','4','missing_operations',jsonb_build_array(x->>'step2'),'restriction',''));
  elsif kind='reduction' then groups:=groups||jsonb_build_array(g||'{"quantity":"6","released":"6"}');
  else groups:=groups||jsonb_build_array(g);end if;
 end loop;
 return jsonb_build_object('groups',groups,'rejected','0','reason','Authoritative correction to stored unfinished material');
end$$;
create function output4cb2_test.context(label text,kind text default 'reduction',choice text default 'COMPLETE') returns jsonb language plpgsql as $$
declare x jsonb;w jsonb;r jsonb;f uuid;begin
 x:=output4_test.context(label);f:=(x->>'factory')::uuid;w:=output4_test.decision(x,choice,10);
 r:=output4c_test.publish(x,output4cb2_test.finding(x,kind));
 return x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6,'kind',kind,'source_location',(select location from private.manufactured_output_lots where factory_id=f and lot_id=(x->>'lot')::uuid));
end$$;
create function output4cb2_test.payload(x jsonb) returns jsonb language sql as $$
 select jsonb_build_object('source_lot_id',x->>'lot','source_location',(select location from private.manufactured_output_lots where factory_id=(x->>'factory')::uuid and lot_id=(x->>'lot')::uuid),'physical_confirmation',true,
 'identification_note','The source quantity is separately identifiable and segregated in this bay','reason','Confirmed stored source reclassification')
$$;
create function output4cb2_test.apply(x jsonb,k uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.reconcile_manufactured_output((x->>'factory')::uuid,(x->>'output')::uuid,(x->>'finding')::uuid,output4cb2_test.payload(x),(x->>'expected')::bigint,k)
$$;
create function output4cb2_test.cancel(x jsonb) returns jsonb language sql as $$
 select output4b_test.revise(x,x->'work')
$$;
create function output4cb2_test.receive(x jsonb,g uuid,q numeric,rev bigint,k uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.receive_manufactured_output((x->>'factory')::uuid,(x->>'output')::uuid,jsonb_build_object('group_id',g,'quantity',q::text,'physical_confirmation',true,'location',case when g::text=x->>'group' then 'Recovery bay' else 'Corrected material bay' end),rev,k)
$$;
begin;
truncate late_test.checks;
do $$declare x jsonb;y jsonb;f uuid;r jsonb;a jsonb;w jsonb;p jsonb;old_entry jsonb;k uuid;receipt uuid;g uuid;group2 uuid;step text;so uuid;sl uuid;state jsonb;begin
 x:=output4cb2_test.context('94 and 6');f:=(x->>'factory')::uuid;k:=gen_random_uuid();
 select to_jsonb(e) into old_entry from public.production_entries e join private.manufactured_outputs h on h.entry_id=e.id where h.id=(x->>'output')::uuid;
 perform late_test.ok(private.output_accounting(f,(x->>'output')::uuid)#>>'{affected_allocations,0,item_id}'=x#>>'{work,item_id}','reader exposes existing Phase4B cancellation eligibility');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'output_allocation_retirement_required');
 perform late_test.ok((select warehouse_quantity=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'Warehouse cannot silently cancel Planning decision');
 r:=output4cb2_test.cancel(x);x:=x||'{"expected":7}';
 perform late_test.ok((select status='cancelled' from public.production_orders where id=(x#>>'{work,item_id}')::uuid) and (select status='CANCELLED' from public.material_requests where id=(x#>>'{work,material_request_id}')::uuid),'existing whole-decision cancellation retires work and unissued request');
 perform late_test.ok(private.output_group_held(f,(x->>'output')::uuid,(x->>'group')::uuid) and (select warehouse_quantity=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'hold and physical stock survive separate Planning action');
 r:=output4cb2_test.apply(x,k);a:=private.output_accounting(f,(x->>'output')::uuid);
 perform late_test.ok(r->>'mode'='UNFINISHED_RECLASS' and r->>'quantity'='4' and r->>'unfinished_movement_id' is not null,'four-unit withdrawal uses existing unfinished movement');
 perform late_test.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f) and (select quantity_available=6 and warehouse_quantity=6 from public.unfinished_lots where id=(x->>'lot')::uuid),'withdrawal alone cannot fabricate finished four');
 perform late_test.ok(a->>'pending'='true' and a->>'remaining_handoff'='4' and private.output_group_held(f,(x->>'output')::uuid,(x->>'group')::uuid),'retained six remains held across accounting handoff');
 perform late_test.ok(output4cb2_test.apply(x,k)=r and (select count(*)=1 from private.manufactured_output_adjustments where factory_id=f),'same UUID cannot withdraw twice');
 perform late_test.fails(format('select public.reconcile_manufactured_output(%L,%L,%L,%L,7,%L)',f,x->>'output',x->>'finding',output4cb2_test.payload(x)||'{"reason":"Different intent"}',k),'request_conflict');
 select (value->>'id')::uuid into g from jsonb_array_elements(private.output_quality(f,(x->>'output')::uuid)->'groups') where jsonb_array_length(value->'missing_operations')=0;
 receipt:=gen_random_uuid();r:=output4cb2_test.receive(x,g,4,8,receipt);
 perform late_test.ok((select on_hand=94 from public.finished_goods_balances where factory_id=f) and (select warehouse_quantity=6 from public.unfinished_lots where id=(x->>'lot')::uuid),'confirmed four receipt produces 94 finished and six stored once');
 perform late_test.ok(private.output_demand_received(f,(x->>'item')::uuid)=94 and private.output_accounting(f,(x->>'output')::uuid)->>'pending'='false','only Warehouse receipt changes finished demand to six remaining');
 perform late_test.ok((select to_jsonb(e)=old_entry from public.production_entries e where id=(old_entry->>'id')::uuid),'technician evidence unchanged');
 w:=output4_test.decision(x||'{"revision":9}','COMPLETE',6);
 perform late_test.ok(w->>'quantity'='6' and (select target_quantity=10 and status='cancelled' from public.production_orders where id=(x#>>'{work,item_id}')::uuid),'new explicit six decision does not resize original ten');
 perform late_test.ok((select count(*)=3 from public.production_orders where factory_id=f) and (select assigned=6 from private.output_work_allocations(f,(x->>'lot')::uuid)),'exactly one explicit successor; no automatic work');
 perform late_test.ok(output4cb2_test.receive(x,g,4,8,receipt)=r,'receipt UUID recovers original evidence after subsequent Planning');

 foreach step in array array['operations','split','split_new'] loop
  x:=output4cb2_test.context('Correct classification '||step,step);f:=(x->>'factory')::uuid;
  perform output4cb2_test.cancel(x);x:=x||'{"expected":7}';r:=output4cb2_test.apply(x);
  perform late_test.ok((select sum(warehouse_quantity)=case when step='split' then 6 else 0 end from public.unfinished_lots where factory_id=f),'old source withdrawn only once for '||step);
  perform late_test.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f),'unfinished reclassification never credits finished stock');
  for a in select value from jsonb_array_elements(r->'handoffs') loop
   perform output4cb2_test.receive(x,(a->>'group_id')::uuid,(a->>'quantity')::numeric,(select max(revision) from private.manufactured_output_events where factory_id=f and output_id=(x->>'output')::uuid));
  end loop;
  perform late_test.ok((select sum(warehouse_quantity)=10 and sum(quantity_available)=10 from public.unfinished_lots where factory_id=f) and private.output_accounting(f,(x->>'output')::uuid)->>'pending'='false','classification conservation after receipts: '||step);
  perform late_test.ok((select count(*)=2 from public.production_orders where factory_id=f),'no automatic jobs for '||step);
  perform late_test.ok((select bool_and(source_entry_id=(select entry_id from private.manufactured_outputs where id=(x->>'output')::uuid)) from public.unfinished_lots where factory_id=f),'source genealogy retained for '||step);
 end loop;

 x:=output4cb2_test.context('Replacement reduction','reduction','REPLACE');f:=(x->>'factory')::uuid;
 perform output4cb2_test.cancel(x);x:=x||'{"expected":7}';r:=output4cb2_test.apply(x);
 select (value->>'id')::uuid into g from jsonb_array_elements(private.output_quality(f,(x->>'output')::uuid)->'groups') where jsonb_array_length(value->'missing_operations')=0;
 perform output4cb2_test.receive(x,g,4,8);
 perform late_test.ok((select replaced=0 and assigned=0 from private.output_work_allocations(f,(x->>'lot')::uuid)) and private.output_demand_received(f,(x->>'item')::uuid)=94,'invalid replacement retired without duplicate demand fulfillment');

 x:=output4cb2_test.context('Equivalent operations','same');f:=(x->>'factory')::uuid;
 r:=public.reconcile_manufactured_output(f,(x->>'output')::uuid,(x->>'finding')::uuid,'{"reason":"Same canonical operation set"}',6,gen_random_uuid());
 perform late_test.ok(r->>'mode'='UNCHANGED' and r->>'quantity'='0' and private.output_accounting(f,(x->>'output')::uuid)->>'pending'='false','equivalent classification needs no physical reclassification');
 perform late_test.ok((select status='planned' from public.production_orders where id=(x#>>'{work,item_id}')::uuid) and (select count(*)=0 from private.manufactured_output_adjustments where factory_id=f),'unchanged live decision preserved without movement');

 -- Permissions and locks are the existing Phase4B contract, not a new wrapper.
 x:=output4cb2_test.context('Independent permissions');f:=(x->>'factory')::uuid;
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'worker')::uuid,'quality','view'),(f,(x->>'worker')::uuid,'quality','edit');
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'permission_denied');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform public.plan_product_item(f,(x#>>'{work,item_id}')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '5 days');
 perform public.set_plan_lock(f,(x#>>'{work,item_id}')::uuid,true);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'planning_locked');
 perform late_test.ok((select status='planned' from public.production_orders where id=(x#>>'{work,item_id}')::uuid) and private.output_work_held(f,(x#>>'{work,item_id}')::uuid),'Planning lock leaves authoritative finding and work hold intact');

 x:=output4_test.context('Already issued');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Actual physical issue'),gen_random_uuid());
 perform output4c_test.publish(x,output4cb2_test.finding(x,'reduction'));x:=x||jsonb_build_object('work',w,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb2_test.cancel(%L)',x),'output_material_issued');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'output_allocation_retirement_required');
 perform late_test.ok((select warehouse_quantity=0 and quantity_available=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'no physical return fabricated');

 x:=output4cb2_test.context('Identification and revision');f:=(x->>'factory')::uuid;perform output4cb2_test.cancel(x);x:=x||'{"expected":7}';
 perform late_test.fails(format('select public.reconcile_manufactured_output(%L,%L,%L,%L,7,%L)',f,x->>'output',x->>'finding',output4cb2_test.payload(x)-'identification_note',gen_random_uuid()),'output_source_identification_required');
 perform late_test.fails(format('select public.reconcile_manufactured_output(%L,%L,%L,%L,7,%L)',f,x->>'output',x->>'finding',output4cb2_test.payload(x)||'{"source_location":"Wrong bay"}',gen_random_uuid()),'output_stock_unavailable');
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x||'{"expected":6}'),'output_revision');
 perform late_test.ok((select warehouse_quantity=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'bad identification and stale revision leave stock held');

 -- Sequential reconciliation must use immutable receipt evidence: withdrawing
 -- a formerly received B1 handoff must not resurrect its completed old hold.
 x:=output4cb_test.context('Completed B1 then B2');f:=(x->>'factory')::uuid;
 r:=output4cb_test.apply(x);perform output4cb_test.receive(x,5,7);
 g:=(x->>'handoff')::uuid;
 a:=private.output_quality(f,(x->>'output')::uuid);p:=jsonb_build_object('groups',(select jsonb_agg(case when value->>'id'=g::text then value||'{"quantity":"3","released":"3"}' when jsonb_array_length(value->'missing_operations')=0 then value||'{"quantity":"87","released":"87"}' else value end) from jsonb_array_elements(a->'groups')),'rejected','0','reason','Later correction of two stored meters');
 perform public.manufactured_output_command(f,'QUALITY',(x->>'output')::uuid,p,8,gen_random_uuid());
 x:=x||jsonb_build_object('finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',9,'lot',(select lot_id from private.manufactured_output_lots where factory_id=f and output_id=(x->>'output')::uuid and group_id=g));
 p:=output4cb2_test.payload(x)||'{"source_location":"Reclassified material bay"}';
 r:=public.reconcile_manufactured_output(f,(x->>'output')::uuid,(x->>'finding')::uuid,p,9,gen_random_uuid());
 perform late_test.ok(private.output_accounting(f,(x->>'output')::uuid)#>>'{handoffs,0,remaining}'='0','later withdrawal never reopens completed B1 handoff');
 perform late_test.ok((select warehouse_quantity=3 from public.unfinished_lots where id=(x->>'lot')::uuid),'later source debit exact two while unrelated allocated ten unchanged');
 perform public.supply_command(f,'material_change',jsonb_build_object('id',x#>>'{work,material_request_id}','revision',1,'action','issue','reason','Separately identifiable original ten remains unaffected'),gen_random_uuid());
 perform late_test.ok((select quantity_available=10 and warehouse_quantity=0 from public.unfinished_lots where id=(select lot_id from private.manufactured_completion_work where item_id=(x#>>'{work,item_id}')::uuid)),'unaffected source still issues while separate reconciliation waits');
 y:=output4cb2_test.context('Other factory');perform set_config('request.jwt.claim.sub',y->>'owner',false);
 perform late_test.fails(format('select output4cb2_test.apply(%L)',x),'permission_denied');
 perform late_test.ok(not has_function_privilege('authenticated','private.output_reconcile_lot_allowed(public.unfinished_lots,public.unfinished_lots)','execute'),'no private context bypass');
 perform late_test.ok((select count(*)=0 from private.manufactured_output_context),'no leaked mutation contexts');
end$$;
select count(*) assertions from late_test.checks;
rollback;
