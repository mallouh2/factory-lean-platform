do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55491 then raise exception 'Disposable localhost only';end if;end$$;
create schema output4cb_test;
create function output4cb_test.context(label text,identify boolean default true,q numeric default 5,reserve numeric default 0) returns jsonb language plpgsql as $$
declare x jsonb;w jsonb;p jsonb;r jsonb;src uuid;f uuid;finding uuid;ng uuid;so uuid;sl uuid;begin
 x:=output4_test.context(label);f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 if identify then src:=output4c_test.identify(x);else select id into src from public.finished_goods_sources where factory_id=f;end if;
 if reserve>0 then
  insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
  insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,reserve,'meter') returning id into sl;
  perform private.reserve_finished(f,sl,reserve);
 end if;
 p:=output4c_test.amendment(x);
 select jsonb_agg(case when jsonb_array_length(value->'missing_operations')=0 then value||jsonb_build_object('quantity',(90-q)::text,'released',(90-q)::text)
 when value->>'id'<>x->>'group' then value||jsonb_build_object('quantity',q::text,'released',q::text) else value end) into r from jsonb_array_elements(p->'groups') where not(q=90 and jsonb_array_length(value->'missing_operations')=0);
 p:=p||jsonb_build_object('groups',r);
 r:=output4c_test.publish(x,p);
 finding:=(private.output_accounting(f,(x->>'output')::uuid)->>'finding_id')::uuid;
 select (value->>'id')::uuid into ng from jsonb_array_elements(r->'groups') where jsonb_array_length(value->'missing_operations')>0 and value->>'id'<>x->>'group';
 return x||jsonb_build_object('work',w,'source',src,'finding',finding,'handoff',ng,'expected',6,'finding_payload',p,'sales_order',so,'sales_line',sl);
end$$;
create function output4cb_test.payload(x jsonb) returns jsonb language sql as $$
 select jsonb_build_object('source_id',x->>'source','physical_confirmation',true,'reason','Physically identified material reclassified by Quality')
$$;
create function output4cb_test.apply(x jsonb,k uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.reconcile_manufactured_output((x->>'factory')::uuid,(x->>'output')::uuid,(x->>'finding')::uuid,output4cb_test.payload(x),(x->>'expected')::bigint,k)
$$;
create function output4cb_test.receive(x jsonb,q numeric,rev bigint,k uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.receive_manufactured_output((x->>'factory')::uuid,(x->>'output')::uuid,jsonb_build_object('group_id',x->>'handoff','quantity',q::text,'physical_confirmation',true,'location','Reclassified material bay'),rev,k)
$$;
create function output4cb_test.fail_event() returns trigger language plpgsql as $$begin
 if new.operation='RECONCILE' then raise exception 'fixture_reconciliation_failure';end if;return new;
end$$;
begin;
truncate late_test.checks;
do $$declare x jsonb;y jsonb;f uuid;r jsonb;a jsonb;b jsonb;k uuid;rk uuid;entry uuid;before_entry jsonb;before_work jsonb;so uuid;sl uuid;package uuid;v text;begin
 x:=output4cb_test.context('Safe 85 plus 15');f:=(x->>'factory')::uuid;k:=gen_random_uuid();
 select entry_id into entry from private.manufactured_outputs where id=(x->>'output')::uuid;
 select to_jsonb(e) into before_entry from public.production_entries e where id=entry;
 select to_jsonb(w) into before_work from private.manufactured_completion_work w where item_id=(x#>>'{work,item_id}')::uuid;
 perform late_test.ok(public.manufactured_receiving_read(f)#>>'{rows,0,accounting,finding_id}'=x->>'finding','Warehouse reader exposes immutable finding identity');
 r:=output4cb_test.apply(x,k);a:=private.output_accounting(f,(x->>'output')::uuid);
 perform late_test.ok(r->>'quantity'='5' and r->>'stage'='WITHDRAWN_AWAITING_RECEIPT' and r->>'finding_id'=x->>'finding','specific finding reconciles exact five');
 perform late_test.ok((select on_hand=85 and reserved=0 from public.finished_goods_balances where factory_id=f),'finished debit exactly five');
 perform late_test.ok((select sum(warehouse_quantity)=10 and sum(quantity_available)=10 from public.unfinished_lots where factory_id=f),'unfinished not credited by withdrawal');
 perform late_test.ok(a->>'pending'='true' and a->>'stage'='AWAITING_RECEIPT' and a->>'remaining_handoff'='5' and a->>'applied_revision'='6','durable partial accounting stage visible');
 perform late_test.ok(not private.output_source_held(f,entry) and private.output_group_held(f,(x->>'output')::uuid,(x->>'handoff')::uuid),'only finished obligation cleared; unfinished handoff held');
 perform late_test.ok(private.output_demand_received(f,(x->>'item')::uuid)=85 and public.manufactured_completion_read(f)#>>'{work,0,demand_shortage}'='15','finished demand outstanding fifteen');
 perform late_test.ok((select to_jsonb(e)=before_entry from public.production_entries e where id=entry) and (select to_jsonb(w)=before_work from private.manufactured_completion_work w where item_id=(x#>>'{work,item_id}')::uuid),'technician and original allocation history unchanged');
 perform late_test.ok((select count(*)=1 from private.manufactured_output_adjustments where factory_id=f and quality_revision=6 and finished_movement_id=(r->>'finished_movement_id')::uuid),'existing adjustment links finding and original finished movement');
 perform late_test.ok(output4cb_test.apply(x,k)=r and (select count(*)=1 from private.manufactured_output_events where factory_id=f and operation='RECONCILE'),'withdrawal UUID replay creates no duplicate');
 perform late_test.fails(format('select public.reconcile_manufactured_output(%L,%L,%L,%L,6,%L)',f,x->>'output',x->>'finding',output4cb_test.payload(x)||'{"reason":"Changed retry"}',k),'request_conflict');
 perform late_test.fails(format('select output4cb_test.apply(%L)',x||'{"expected":7}'),'output_reconciliation_applied');
 perform late_test.fails(format('select output4cb_test.receive(%L,6,7)',x),'output_receipt_quantity');
 perform late_test.fails(format('select public.receive_manufactured_output(%L,%L,%L,7,%L)',f,x->>'output',jsonb_build_object('group_id',x->>'handoff','quantity','5','physical_confirmation',false,'location','Reclassified material bay'),gen_random_uuid()),'output_physical_confirmation');
 a:=output4cb_test.receive(x,2,7);b:=private.output_accounting(f,(x->>'output')::uuid);
 perform late_test.ok((select sum(warehouse_quantity)=12 from public.unfinished_lots where factory_id=f) and b->>'remaining_handoff'='3' and b->>'pending'='true','partial physical receipt two preserves remaining three');
 perform late_test.ok(a->>'finding_id'=x->>'finding' and a->>'reconciliation_id'=b#>>'{reconciliation,id}','receipt evidence directly links reconciliation and finding');
 perform late_test.ok(private.output_group_held(f,(x->>'output')::uuid,(x->>'handoff')::uuid),'partial handoff not incorrectly fully released');
 perform late_test.fails(format('select public.plan_manufactured_completion(%L,%L,%L,8,%L)',f,x->>'output',jsonb_build_object('group_id',x->>'handoff','quantity','1','choice','COMPLETE','operations',jsonb_build_array(x->>'step1'),'reason','Partial handoff must stay held'),gen_random_uuid()),'output_quality_hold');
 rk:=gen_random_uuid();a:=output4cb_test.receive(x,3,8,rk);b:=private.output_accounting(f,(x->>'output')::uuid);
 perform late_test.ok(b->>'pending'='false' and b->>'stage'='RECONCILED' and b->>'remaining_handoff'='0' and b->'held_groups'='[]'::jsonb,'full Warehouse confirmation resolves only completed finding obligations');
 perform late_test.ok((select on_hand=85 from public.finished_goods_balances where factory_id=f) and (select sum(warehouse_quantity)=15 from public.unfinished_lots where factory_id=f),'85 finished plus 15 stored conserves one hundred');
 perform late_test.ok((select assigned=10 and reserved=10 from private.output_work_allocations(f,(x->>'lot')::uuid)) and (select assigned=0 from private.output_work_allocations(f,(select lot_id from private.manufactured_output_lots where factory_id=f and output_id=(x->>'output')::uuid and group_id=(x->>'handoff')::uuid))),'original ten allocation intact; additional five unallocated');
 perform late_test.ok((select count(*)=2 from public.production_orders where factory_id=f) and (select count(*)=1 from private.manufactured_completion_work where factory_id=f),'no automatic new recovery or replacement production');
 perform late_test.ok((select source_entry_id=entry from public.unfinished_lots where manufactured_group_id=(x->>'handoff')::uuid) and (select demand_item_id=(x->>'item')::uuid from private.manufactured_output_lots where group_id=(x->>'handoff')::uuid),'new handoff preserves origin and original demand');
 perform late_test.ok(output4cb_test.receive(x,3,8,rk)=a and output4cb_test.apply(x,k)=r,'receipt and withdrawal lost-response retries recover original committed results');
 perform late_test.fails(format('select output4cb_test.receive(%L,1,9)',x),'output_receipt_quantity');
 perform late_test.ok((select count(*)=1 from public.finished_goods_movements where factory_id=f and kind='quality_rejection') and (select count(*)=0 from public.quality_rejections where factory_id=f),'one classification debit, no invented Scrap KG rejection');

 -- Warehouse authority is independent of Quality's authority to make findings.
 x:=output4cb_test.context('Warehouse permissions');f:=(x->>'factory')::uuid;
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'worker')::uuid,'quality','view'),(f,(x->>'worker')::uuid,'quality','edit');
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 insert into public.permission_packages(factory_id,name,created_by) values(f,'Local Warehouse reconciliation',(x->>'owner')::uuid) returning id into package;
 insert into public.permission_package_permissions(factory_id,package_id,module,action) values(f,package,'warehouse','view'),(f,package,'warehouse','edit');
 insert into public.member_permission_packages(factory_id,user_id,package_id) values(f,(x->>'worker')::uuid,package);
 delete from public.user_permissions where factory_id=f and user_id=(x->>'worker')::uuid and module='quality';
 perform set_config('request.jwt.claim.sub',x->>'worker',false);r:=output4cb_test.apply(x);
 perform late_test.ok(r->>'quantity'='5','effective Warehouse package permits physical action without granting Quality edit');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform late_test.fails(format('select public.reconcile_manufactured_output(%L,%L,%L,%L,7,%L)',f,x->>'output',x->>'finding',output4cb_test.payload(x),(select request_id from private.manufactured_output_events where id=(x->>'finding')::uuid)),'request_conflict');

 -- Unavailable/unidentified stock never becomes a manufactured receipt.
 x:=output4cb_test.context('Unidentified',false);f:=(x->>'factory')::uuid;
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'output_stock_unavailable');
 perform late_test.ok(private.output_accounting(f,(x->>'output')::uuid)->>'stage'='PENDING' and (select on_hand=90 from public.finished_goods_balances where factory_id=f),'unidentified finding remains held with unchanged stock');
 perform late_test.fails(format('select public.reconcile_manufactured_output(%L,%L,%L,%L,6,%L)',f,x->>'output',x->>'finding',output4cb_test.payload(x)||'{"physical_confirmation":false}',gen_random_uuid()),'output_physical_confirmation');
 perform public.source_stock_command(f,'identify',jsonb_build_object('source',x->>'source','quantity','5','label','Five actually segregated meters','physically_identified',true),'[]',gen_random_uuid());
 r:=output4cb_test.apply(x);
 perform late_test.ok((select on_hand=85 from public.finished_goods_balances where factory_id=f) and (select quantity_available=0 from public.finished_goods_sources where id=(x->>'source')::uuid),'normal physical identification of only affected five makes that share eligible');
 perform late_test.ok(private.output_stock_free(f,(x->>'product')::uuid,'meter')=85 and private.output_accounting(f,(x->>'output')::uuid)->>'pending'='true','remaining finished pool released only after actual withdrawal, handoff still pending');

 -- Existing Sales source assignments and incoming commitments stay intact.
 x:=output4_test.context('Reserved eighty six');f:=(x->>'factory')::uuid;begin
  r:=output4_test.decision(x,'COMPLETE',10);k:=output4c_test.identify(x);
  insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
  insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,100,'meter') returning id into sl;
  perform private.reserve_finished(f,sl,86);perform private.source_assign_reservation(f,sl,jsonb_build_array(jsonb_build_object('source_id',k,'quantity','86')));
  insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,sl,(x->>'item')::uuid,10);
  perform output4c_test.publish(x,output4c_test.amendment(x));
  x:=x||jsonb_build_object('source',k,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 end;
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'output_stock_unavailable');
 perform late_test.ok((select on_hand=90 and reserved=86 from public.finished_goods_balances where factory_id=f) and (select quantity=86 from public.finished_goods_source_reservations where source_id=k) and (select quantity=10 from public.sales_incoming_allocations where line_id=sl),'insufficient unreserved source blocks without touching commitments');

 x:=output4_test.context('Shipped eighty six');f:=(x->>'factory')::uuid;r:=output4_test.decision(x,'COMPLETE',10);k:=output4c_test.identify(x);
 insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,86,'meter') returning id into sl;
 perform private.reserve_finished(f,sl,86);perform public.source_stock_command(f,'dispatch',jsonb_build_object('sales_order',so,'line',sl),jsonb_build_array(jsonb_build_object('source_id',k,'sales_line_id',sl,'quantity','86')),gen_random_uuid());
 perform output4c_test.publish(x,output4c_test.amendment(x));x:=x||jsonb_build_object('source',k,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'output_stock_unavailable');
 perform late_test.ok((select on_hand=4 from public.finished_goods_balances where factory_id=f) and (select dispatched_quantity=86 from public.sales_order_lines where id=sl),'cannot withdraw shipped quantities or invent returned stock');

 -- Unsafe allocated-group change remains a B2 hold, not a hidden cancellation.
 x:=output4_test.context('Allocated classification change');f:=(x->>'factory')::uuid;r:=output4_test.decision(x,'COMPLETE',10);k:=output4c_test.identify(x);
 perform output4c_test.publish(x,output4c_test.amendment(x,'operations'));x:=x||jsonb_build_object('source',k,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'output_allocation_retirement_required');
 perform late_test.ok(private.output_work_held(f,(r->>'item_id')::uuid) and (select assigned=10 from private.output_work_allocations(f,(x->>'lot')::uuid)),'affected allocation remains unchanged and held for B2');

 -- A newer finding or another unresolved finding cannot be silently cleared.
 x:=output4cb_test.context('Further inspection');f:=(x->>'factory')::uuid;r:=output4cb_test.apply(x);
 perform output4c_test.publish(x,x->'finding_payload',7);
 perform late_test.fails(format('select output4cb_test.receive(%L,5,8)',x),'output_quality_hold');
 a:=private.output_accounting(f,(x->>'output')::uuid);
 perform late_test.ok(a->>'pending'='true' and a#>>'{handoffs,0,remaining}'='5' and (select sum(warehouse_quantity)=10 from public.unfinished_lots where factory_id=f),'new finding does not erase older unfinished handoff or lift holds');

 x:=output4cb_test.context('Exact fractional transfer',true,0.123456789012345678901);f:=(x->>'factory')::uuid;r:=output4cb_test.apply(x);
 perform late_test.ok(r->>'quantity'='0.123456789012345678901' and (select on_hand=89.876543210987654321099 from public.finished_goods_balances where factory_id=f),'reconciliation uses exact numeric quantity, not floating point');
 perform output4cb_test.receive(x,0.123456789012345678901,7);
 perform late_test.ok((select sum(warehouse_quantity)=10.123456789012345678901 from public.unfinished_lots where factory_id=f),'exact fractional received quantity conserved');

 x:=output4cb_test.context('Whole finished group reclassified',true,90);f:=(x->>'factory')::uuid;r:=output4cb_test.apply(x);
 perform late_test.ok((select on_hand=0 from public.finished_goods_balances where factory_id=f) and private.output_demand_received(f,(x->>'item')::uuid)=0,'whole eligible finished share withdrawn without zero-quantity stock group');
 perform output4cb_test.receive(x,90,7);
 perform late_test.ok((select sum(warehouse_quantity)=100 from public.unfinished_lots where factory_id=f) and (select assigned=10 from private.output_work_allocations(f,(x->>'lot')::uuid)),'full reclassification preserves quantity and unchanged ten allocation');

 x:=output4_test.context('Quality release still required');f:=(x->>'factory')::uuid;r:=output4_test.decision(x,'COMPLETE',10);k:=output4c_test.identify(x);
 a:=output4c_test.amendment(x);a:=a||jsonb_build_object('groups',(select jsonb_agg(case when value->>'quantity'='5' then value||'{"released":"0"}'::jsonb else value end) from jsonb_array_elements(a->'groups')));
 perform output4c_test.publish(x,a);x:=x||jsonb_build_object('source',k,'finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',6);
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'output_reconciliation_release_required');
 perform late_test.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f),'unreleased handoff cannot be fabricated by Warehouse authority');

 x:=output4cb_test.context('Multiple unresolved findings');f:=(x->>'factory')::uuid;
 perform output4c_test.publish(x,x->'finding_payload',6);
 perform late_test.fails(format('select output4cb_test.apply(%L)',x||'{"expected":7}'),'output_finding_stale');
 x:=x||jsonb_build_object('finding',private.output_accounting(f,(x->>'output')::uuid)->>'finding_id','expected',7);
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'output_reconciliation_multiple_findings');
 perform late_test.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f),'B1 never clears another unresolved finding');

 x:=output4cb_test.context('Atomic rollback after withdrawal');f:=(x->>'factory')::uuid;k:=gen_random_uuid();
 execute 'create trigger output4cb_failure before insert on private.manufactured_output_events for each row execute function output4cb_test.fail_event()';
 perform late_test.fails(format('select output4cb_test.apply(%L,%L)',x,k),'fixture_reconciliation_failure');
 execute 'drop trigger output4cb_failure on private.manufactured_output_events';
 perform late_test.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f) and (select quantity_available=90 from public.finished_goods_sources where id=(x->>'source')::uuid) and not exists(select 1 from private.manufactured_output_adjustments where factory_id=f),'unexpected persistence error rolls back withdrawal and adjustment');
 perform late_test.ok((select count(*)=0 from private.manufactured_output_context) and private.output_accounting(f,(x->>'output')::uuid)->>'stage'='PENDING','failed physical transaction leaves no context or cleared hold');
 r:=output4cb_test.apply(x,k);
 perform late_test.ok((select on_hand=85 from public.finished_goods_balances where factory_id=f) and (select count(*)=1 from private.manufactured_output_events where factory_id=f and operation='RECONCILE'),'same UUID after verified rollback commits only one physical result');

 x:=output4cb_test.context('Cross factory target');y:=output4cb_test.context('Other factory actor');perform set_config('request.jwt.claim.sub',y->>'owner',false);
 perform late_test.fails(format('select output4cb_test.apply(%L)',x),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform late_test.fails(format('select public.reconcile_manufactured_output(%L,%L,%L,%L,6,%L)',x->>'factory',x->>'output',x->>'finding',output4cb_test.payload(x)||jsonb_build_object('source_id',y->>'source'),gen_random_uuid()),'output_stock_unavailable');
 perform set_config('request.jwt.claim.sub',x->>'viewer',false);perform late_test.fails(format('select output4cb_test.apply(%L)',x),'permission_denied');
 perform late_test.ok(not has_function_privilege('anon','public.reconcile_manufactured_output(uuid,uuid,uuid,jsonb,bigint,uuid)','execute') and not has_function_privilege('authenticated','private.output_reconcile_pick_allowed(uuid,uuid,text,numeric,uuid)','execute'),'no anonymous/private-context authorization bypass');
 perform late_test.ok((select count(*)=0 from private.manufactured_output_context),'no transaction context leaks');
end$$;
select count(*) assertions from late_test.checks;
rollback;
