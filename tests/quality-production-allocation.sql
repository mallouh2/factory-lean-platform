-- All test business records roll back. Runs only on independently verified55499.
begin;
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55499 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable QA only';end if;end$$;
do $$declare x jsonb;f uuid;o uuid;k uuid;r jsonb;d jsonb;n numeric;v record;before_count bigint;begin
 for v in select * from(values('2',2,0,0,4),('5',2,3,0,1),('6',2,4,0,0),('8',2,4,2,0),('2.5',2,.5,0,3.5))a(q,r,u,s,left_q) loop
 x:=compensation_test.unreceived_fixture('auto-'||replace(v.q,'.','d'),true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;k:=gen_random_uuid();
 r:=public.plan_quality_production(f,o,jsonb_build_object('quantity',v.q,'mode','PLANNED'),2,k);d:=r->'distribution';
 perform compensation_test.ok((d->>'rejected')::numeric=v.r and(d->>'unfinished')::numeric=v.u and(d->>'stock')::numeric=v.s and(d->>'uncovered')::numeric=v.left_q,'automatic allocation '||v.q);
 perform compensation_test.ok((select target_quantity=909 from public.production_orders where id=(x->>'item')::uuid)and not exists(select 1 from private.manufactured_output_lots where output_id=o),'unchanged demand and no stock credit '||v.q);
 perform compensation_test.ok((public.production_compensation_read(f,o)->>'available')::numeric=v.left_q,'remaining eligible demand '||v.q);
 perform compensation_test.ok(public.plan_quality_production(f,o,jsonb_build_object('quantity',v.q,'mode','PLANNED'),2,k)=r,'immutable retry '||v.q);
 perform late_test.fails(format('select public.plan_quality_production(%L,%L,%L::jsonb,2,%L)',f,o,'{"quantity":"9","mode":"PLANNED"}',k),'request_conflict');
 if v.s>0 then
  perform compensation_test.ok((select po.target_quantity=2 and po.line_id is null and po.start_time is null and po.actual_start is null and pr.request_type='INTERNAL_PRODUCTION' and pr.priority='normal' from public.production_orders po join public.production_requests pr on pr.factory_id=po.factory_id and pr.id=po.request_id where po.id=(r#>>'{stock,item_id}')::uuid)
   and not exists(select 1 from private.manufactured_completion_work where item_id=(r#>>'{stock,item_id}')::uuid),'separate unscheduled stock request has no original fulfillment allocation');
  perform compensation_test.ok(jsonb_array_length(public.production_compensation_read(f,o)->'stock_work')=1,'real stock work visible');
 end if;
 end loop;
 -- The existing source revision and permissions remain mandatory.
 perform late_test.fails(format('select public.plan_quality_production(%L,%L,%L::jsonb,2,%L)',f,o,'{"quantity":"8","mode":"PLANNED"}',gen_random_uuid()),'output_revision');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform late_test.fails(format('select public.plan_quality_production(%L,%L,%L::jsonb,2,%L)',f,o,'{"quantity":"8","mode":"PLANNED"}',gen_random_uuid()),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform late_test.fails(format('select public.plan_quality_production(%L,%L,%L::jsonb,2,%L)',gen_random_uuid(),o,'{"quantity":"8","mode":"PLANNED"}',gen_random_uuid()),'permission_denied');
 perform late_test.fails(format('update private.quality_production_decisions set result=result where id=%L',k),'manufactured_output_immutable');
end$$;
-- Atomic failure after replacement succeeds but before the stock request commits.
do $$declare x jsonb;f uuid;o uuid;r jsonb;b text;begin
 b:=pg_get_functiondef('compensation_test.unreceived_fixture(text,boolean,boolean)'::regprocedure);
 execute replace(replace(b,'compensation_test.unreceived_fixture','compensation_test.piece_fixture'),'''meter''','''piece''');
 x:=compensation_test.piece_fixture('auto-piece',true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 perform late_test.fails(format('select public.plan_quality_production(%L,%L,%L::jsonb,2,%L)',f,o,'{"quantity":"2.5","mode":"PLANNED"}',gen_random_uuid()),'output_compensation_quantity');
 r:=public.plan_quality_production(f,o,'{"quantity":"8","mode":"PLANNED"}',2,gen_random_uuid());
 perform compensation_test.ok(r#>>'{stock,unit}'='piece' and r#>>'{stock,quantity}'='2','Piece uses real product/rate/recording/Quality contracts; fractional Piece rejected');
 x:=compensation_test.fixture('auto-stored',true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 r:=public.plan_quality_production(f,o,'{"quantity":"5","mode":"PLANNED"}',3,gen_random_uuid());
 perform compensation_test.ok((select warehouse_quantity=4 and quantity_available=4 from public.unfinished_lots where source_entry_id=(select entry_id from private.manufactured_outputs where id=o))
 and private.compensation_group_remaining(f,o,(x->>'unfinished')::uuid)=1,'partial replacement retains all four physical stored units and one original-demand entitlement');
end$$;
do $$declare x jsonb;f uuid;o uuid;w jsonb;s jsonb;r jsonb;begin
 x:=compensation_test.fixture('auto-issued',true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 w:=public.plan_manufactured_completion(f,o,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','COMPLETE','reason','Existing source allocation','operations',jsonb_build_array(x->>'step1')),3,gen_random_uuid());
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Physically issued four'),gen_random_uuid());
 s:=public.production_compensation_read(f,o);
 perform compensation_test.ok(s#>>'{distribution,rejected_available}'='2' and s#>>'{distribution,unfinished_available}'='0','existing issued completion is excluded from the new split');
 r:=public.plan_quality_production(f,o,'{"quantity":"8","mode":"PLANNED"}',4,gen_random_uuid());
 perform compensation_test.ok(r#>>'{distribution,rejected}'='2' and r#>>'{distribution,unfinished}'='0' and r#>>'{distribution,stock}'='6' and not private.output_work_retired(f,(w->>'item_id')::uuid),'additional request does not supersede issued work');
 perform public.manufactured_output_command(f,'QUALITY',o,jsonb_build_object('groups','[]'::jsonb,'total','909','rejected','909','actual_rejected_kg','454.5','reason','Physical reconciliation required'),4,gen_random_uuid());
 perform late_test.fails(format('select public.plan_quality_production(%L,%L,%L::jsonb,5,%L)',f,o,'{"quantity":"8","mode":"PLANNED"}',gen_random_uuid()),'output_quality_hold');
end$$;
create function pg_temp.fail_stock()returns trigger language plpgsql as $$begin if new.name='Additional stock production' then raise exception 'injected_stock_failure';end if;return new;end$$;
create trigger allocation_test_failure before insert on public.production_requests for each row execute function pg_temp.fail_stock();
do $$declare x jsonb;f uuid;o uuid;k uuid:=gen_random_uuid();begin
 x:=compensation_test.unreceived_fixture('atomic-stock',true);f:=(x->>'factory')::uuid;o:=(x->>'output')::uuid;
 perform late_test.fails(format('select public.plan_quality_production(%L,%L,%L::jsonb,2,%L)',f,o,'{"quantity":"8","mode":"PLANNED"}',k),'injected_stock_failure');
 perform compensation_test.ok(not exists(select 1 from private.production_compensation where id=k)and not exists(select 1 from private.quality_production_decisions where id=k)and public.production_compensation_read(f,o)->>'available'='6','stock failure rolls back replacement, dispositions and receipt');
end$$;
rollback;
