-- Focused eligibility / provenance acceptance. Entire synthetic scenario rolls back.
begin;
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55499 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable local only';end if;end$$;
\ir quality-compensation-fixture.sql
do $$declare x jsonb;f uuid;o uuid;k uuid:=gen_random_uuid();p jsonb;r jsonb;s jsonb;lot uuid;w jsonb;before_stock bigint;before_reason text;begin
 x:=compensation_test.unreceived_fixture('fix-all-six',true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 s:=public.production_compensation_read(f,o);
 perform compensation_test.ok(s->>'available'='6' and s->>'unfinished_unassigned'='4' and not exists(select 1 from private.manufactured_output_lots where output_id=o),'fix: unreceived four plus rejected two are eligible six without a fake lot');
 select count(*)into before_stock from public.finished_goods_movements;
 p:='{"quantity":"6","mode":"PLANNED"}';r:=public.plan_production_compensation(f,o,p,2,k);
 perform compensation_test.ok(r->>'quantity'='6' and (select target_quantity=909 from public.production_orders where id=(x->>'item')::uuid) and (select status='planned' and line_id is null from public.production_orders where id=(r->>'item_id')::uuid),'fix: ended six creates unscheduled work and preserves original target');
 perform compensation_test.ok((select reason like '%Measured Quality result%' and intent#>>'{quality_evidence,reason_source}'='QUALITY' and intent#>>'{quality_evidence,quality_id}'is not null and jsonb_array_length(intent#>'{quality_evidence,groups}')=2 from private.production_compensation where id=k),'fix: ordinary reason and immutable finding provenance are server-derived');
 perform compensation_test.ok((select quantity=4 and lot_id is null from private.production_compensation_releases where compensation_id=k) and (select count(*)=before_stock from public.finished_goods_movements) and not exists(select 1 from private.manufactured_output_lots where output_id=o),'fix: pre-receipt disposition releases four demand units without physical movements');
 perform compensation_test.ok(public.plan_production_compensation(f,o,p,2,k)=r and (select count(*)=1 from private.production_compensation where output_id=o),'fix: omitted-reason UUID replay returns same result once');
 perform late_test.fails(format('select public.plan_production_compensation(%L,%L,%L::jsonb,2,%L)',f,o,'{"quantity":"5","mode":"PLANNED"}',k),'request_conflict');
 perform public.receive_manufactured_output(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','2','location','Identified partial storage','physical_confirmation',true),3,gen_random_uuid());
 raise notice 'Partial receipt evidence: %',(select jsonb_build_object('stored',l.warehouse_quantity,'physical_lot',l.quantity_available,'created',l.quantity_created,'assigned_entitlement',a.assigned,'released_entitlement',a.replaced)from private.manufactured_output_lots m join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id cross join lateral private.output_work_allocations(f,l.id)a where m.output_id=o);
 perform compensation_test.ok((select l.warehouse_quantity=2 and l.quantity_available=2 and a.assigned=4 from private.manufactured_output_lots m join public.unfinished_lots l on l.factory_id=m.factory_id and l.id=m.lot_id cross join lateral private.output_work_allocations(f,l.id)a where m.output_id=o),'fix: partial receipt inherits one complete group entitlement without double counting');
 perform public.receive_manufactured_output(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','2','location','Identified partial storage','physical_confirmation',true),4,gen_random_uuid());
 select lot_id into lot from private.manufactured_output_lots where output_id=o;
 perform compensation_test.ok((select quantity_available=4 and warehouse_quantity=4 from public.unfinished_lots where id=lot) and (select assigned=4 and replaced=4 from private.output_work_allocations(f,lot)),'fix: later real receiving preserves four physical meters and inherits released entitlement');
 perform late_test.fails(format('select public.plan_manufactured_completion(%L,%L,%L::jsonb,5,%L)',f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','COMPLETE','reason','Must not fulfill original demand twice','operations',jsonb_build_array(x->>'step1')),gen_random_uuid()),'output_allocation_unavailable');
 w:=public.plan_manufactured_completion(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','STOCK','reason','Independent stock-only future recovery','operations',jsonb_build_array(x->>'step1')),5,gen_random_uuid());
 perform compensation_test.ok((select demand_item_id is null from private.manufactured_completion_work where item_id=(w->>'item_id')::uuid) and private.output_demand_received(f,(x->>'item')::uuid)=0 and (select count(*)=before_stock from public.finished_goods_movements),'fix: later stock-only work cannot create original demand fulfillment or finished credit');
 select reason into before_reason from private.production_compensation where id=k;
 perform public.manufactured_output_command(f,'QUALITY',o,jsonb_build_object('groups',private.output_quality(f,o)->'groups','total','909','rejected','2','actual_rejected_kg','1','reason','New reviewed wording must not rewrite earlier evidence'),5,gen_random_uuid());
 perform compensation_test.ok(public.plan_production_compensation(f,o,p,2,k)=r and (select reason=before_reason from private.production_compensation where id=k),'fix: replay after later Quality wording preserves original evidence');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform late_test.fails(format('select public.plan_production_compensation(%L,%L,%L::jsonb,5,%L)',f,o,p,gen_random_uuid()),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform late_test.fails(format('select public.plan_production_compensation(%L,%L,%L::jsonb,5,%L)',gen_random_uuid(),o,p,gen_random_uuid()),'permission_denied');
end$$;
do $$declare x jsonb;f uuid;o uuid;r jsonb;begin
 x:=compensation_test.unreceived_fixture('fix-active-partial');f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 r:=public.plan_production_compensation(f,o,'{"quantity":"3","mode":"ACTIVE"}',2,gen_random_uuid());
 perform compensation_test.ok(r->>'item_id'=x->>'item' and (select quantity=1 and lot_id is null from private.production_compensation_releases where compensation_id=(r->>'compensation_id')::uuid) and public.production_compensation_read(f,o)->>'available'='3','fix: active partial replacement consumes rejection first and releases only one unfinished unit');
 perform late_test.fails(format('select public.plan_production_compensation(%L,%L,%L::jsonb,2,%L)',f,o,'{"quantity":"3","mode":"ACTIVE"}',gen_random_uuid()),'output_revision');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform compensation_test.ok(public.production_compensation_read(f,o)->>'available'='3','fix: existing Orders view permits read without granting write authority');
end$$;
do $$declare x jsonb;f uuid;o uuid;w jsonb;rev jsonb;r jsonb;state jsonb;begin
 x:=compensation_test.fixture('fix-existing-complete',true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 w:=public.plan_manufactured_completion(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','COMPLETE','reason','Four assigned to actual completion','operations',jsonb_build_array(x->>'step1')),3,gen_random_uuid());
 state:=private.output_work_revision_state(f,(w->>'item_id')::uuid);
 perform compensation_test.ok(public.production_compensation_read(f,o)->>'available'='2' and state->>'change_available'='true','fix: existing completion four leaves two and permits only protected eligible supersession');
 r:=public.revise_manufactured_completion(f,(w->>'item_id')::uuid,jsonb_build_object('action','CHANGE','choice','REPLACE','operations','[]'::jsonb,'reason','Manager chooses new replacement instead of unfinished processing','expected_state',state->'state'),(state->>'revision')::bigint,gen_random_uuid());
 perform compensation_test.ok(private.output_work_retired(f,(w->>'item_id')::uuid) and (select choice='REPLACE' and demand_item_id=(x->>'item')::uuid from private.manufactured_completion_work where item_id=(r#>>'{successor,item_id}')::uuid) and (select warehouse_quantity=4 from public.unfinished_lots where source_entry_id=(select entry_id from private.manufactured_outputs where id=o)),'fix: protected CHANGE retires wholly unissued completion; stored four unchanged');
end$$;
do $$declare x jsonb;f uuid;o uuid;w jsonb;s jsonb;begin
 x:=compensation_test.fixture('fix-issued',true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 w:=public.plan_manufactured_completion(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','COMPLETE','reason','Issued source cannot be silently switched','operations',jsonb_build_array(x->>'step1')),3,gen_random_uuid());
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Physically issued four'),gen_random_uuid());
 s:=private.output_work_revision_state(f,(w->>'item_id')::uuid);
 perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L::jsonb,%s,%L)',f,w->>'item_id',jsonb_build_object('action','CHANGE','choice','REPLACE','operations','[]'::jsonb,'reason','Blocked switch','expected_state',s->'state'),s->>'revision',gen_random_uuid()),'output_material_issued');
 perform compensation_test.ok(s->>'change_available'='false' and public.production_compensation_read(f,o)->>'available'='2','fix: issued work stays protected while remaining rejection is separate');
 perform public.manufactured_output_command(f,'QUALITY',o,jsonb_build_object('groups','[]'::jsonb,'total','909','rejected','909','actual_rejected_kg','454.5','reason','Issued batch must be reconciled'),4,gen_random_uuid());
 perform late_test.fails(format('select public.plan_production_compensation(%L,%L,%L::jsonb,5,%L)',f,o,'{"quantity":"6","mode":"PLANNED"}',gen_random_uuid()),'output_quality_hold');
 perform compensation_test.ok(public.production_compensation_read(f,o)->>'blocked_reason'='output_quality_hold','fix: current Quality holds still close all new replacement');
end$$;
select count(*) as passed from compensation_test.checks where label like 'fix:%';
rollback;
