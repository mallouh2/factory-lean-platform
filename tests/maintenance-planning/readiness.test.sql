begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Readiness assertion failed: %',label;end if;insert into assertions values(label);end$$;
create function pg_temp.fails(statement text,message text,reason text default null) returns void language plpgsql as $$declare detail text;begin
 begin execute statement;exception when others then
 if sqlerrm<>message then raise exception 'Expected %, got %',message,sqlerrm;end if;
 if reason is not null then get stacked diagnostics detail=PG_EXCEPTION_DETAIL;
 if detail::jsonb->>'reason'<>reason or detail::jsonb->'machine'->>'id' is null then raise exception 'Wrong machine/reason: %',detail;end if;end if;
 insert into assertions values(message||coalesce(':'||reason,''));return;end;
 raise exception 'Expected rejection %',message;end$$;
create function pg_temp.snapshot(f uuid) returns jsonb language sql as $$select jsonb_build_object(
 'events',(select jsonb_agg(to_jsonb(x) order by x.id) from public.downtime_events x where factory_id=f),
 'loss',(select jsonb_agg(to_jsonb(x) order by x.id) from public.production_loss_estimates x where factory_id=f),
 'entries',(select jsonb_agg(to_jsonb(x) order by x.id) from public.production_entries x),
 'goods',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.finished_goods_balances x),
 'sources',(select jsonb_agg(to_jsonb(x) order by x.id) from public.finished_goods_sources x),
 'allocations',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.finished_goods_source_allocations x),
 'movements',(select jsonb_agg(to_jsonb(x) order by x.id) from public.finished_goods_movements x),
 'reservations',(select jsonb_agg(to_jsonb(x) order by x.id) from public.finished_goods_reservations x),
 'wip',(select jsonb_agg(to_jsonb(x) order by x.id) from public.unfinished_lots x),
 'wip_movements',(select jsonb_agg(to_jsonb(x) order by x.id) from public.unfinished_movements x))$$;
do $$declare x jsonb;y jsonb;f uuid;m uuid;i uuid;r uuid;s uuid;e uuid;why uuid;pkg uuid;v jsonb;before_state jsonb;plan jsonb;physical_state text;other uuid;a timestamptz;begin
 perform quality_test.make_fixture('readiness-stock','meter',.35,10,5);
 x:=mp_test.released('idle');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 perform pg_temp.ok((select state='RELEASED' from public.maintenance_schedules where id=(x->>'schedule')::uuid),'normal independent verification released capacity');
 perform pg_temp.ok((select ended_at is not null from public.downtime_events where id=(x->>'event')::uuid),'physical linked stop closed normally');
 perform public.set_plan_lock(f,i,true);
 insert into public.production_loss_estimates(factory_id,event_id,model_version,result,recorded_by) values(f,(x->>'event')::uuid,1,'{"status":"READY","fixture":"immutable evidence"}',(x->>'owner')::uuid);
 before_state:=pg_temp.snapshot(f);select jsonb_build_object('start',start_time,'end',expected_finish,'lock',planning_locked_at) into plan from public.production_orders where id=i;
 v:=public.production_start_readiness(f,i);
 perform pg_temp.ok((v->>'queue_ready')::boolean and (v->'physical'->>'ready')::boolean and (v->'physical'->>'applicable')::boolean,'queue and IDLE physical preparation are distinct, ready facts');
 perform public.start_product_item(f,i);
 perform pg_temp.ok((select status='idle' from public.work_centers where id=m),'Start preparation never restarts IDLE machine');
 perform pg_temp.ok((select actual_start is not null and jsonb_build_object('start',start_time,'end',expected_finish,'lock',planning_locked_at)=plan from public.production_orders where id=i),'Start preserves planned timestamps and planning lock');
 perform public.finish_product_item(f,i);
 perform pg_temp.ok(before_state=pg_temp.snapshot(f),'Good/Scrap/WIP/sources/reservations/movements/downtime/saved Loss unchanged');
 x:=mp_test.released('running');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 perform public.change_status(f,m,'running');perform public.start_product_item(f,i);
 perform pg_temp.ok((select status='active' from public.production_orders where id=i),'RUNNING follows existing execution eligibility');
 foreach physical_state in array array['stopped','offline','setup'] loop
 x:=mp_test.released(physical_state);f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 insert into public.downtime_reasons(factory_id,name) values(f,'Local readiness reason') returning id into why;
 if physical_state='stopped' then perform public.stop_machine(f,m,'planned',null,'inspection','Local status');else perform public.change_status(f,m,physical_state,why);end if;
 before_state:=pg_temp.snapshot(f);
 v:=public.production_start_readiness(f,i);
 perform pg_temp.ok((v->>'queue_ready')::boolean and not (v->'physical'->>'ready')::boolean and v->'physical'->'machine'->>'status'=physical_state,'queue ready but physical '||physical_state||' blocked');
 perform pg_temp.fails(format('select public.start_product_item(%L,%L)',f,i),'execution_physical_not_ready','PHYSICAL_STATUS');
 perform pg_temp.ok((select status='planned' and actual_start is null from public.production_orders where id=i),'unsafe Start rolled back for '||physical_state);
 perform pg_temp.ok(before_state=pg_temp.snapshot(f),'denied Start creates no quantity/downtime/Loss writes for '||physical_state);
 end loop;
 -- Historical inconsistent imported release: only the isolated fixture owner
 -- inserts this impossible legacy state. Normal Phase5B RPCs prohibit it.
 x:=mp_test.released('legacy-open');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 e:=public.stop_machine(f,m,'planned',null,'inspection','Legacy inconsistent fixture');
 insert into public.maintenance_stop_associations(factory_id,event_id,revision,operation,schedule_id,approval_revision,approval,resources,relationship,actor_id,reason,request_id)
 select f,e,1,'LINK',schedule_id,approval_revision,approval,resources,relationship,actor_id,'Imported inconsistent test evidence',gen_random_uuid()
 from public.maintenance_stop_associations where event_id=(x->>'event')::uuid limit 1;
 perform pg_temp.fails(format('select public.start_product_item(%L,%L)',f,i),'execution_physical_not_ready','OPEN_LINKED_STOP');
 x:=mp_test.released('unrelated');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 perform public.stop_machine(f,m,'planned',null,'inspection','Serviced line remains stopped');
 perform public.revise_product_plan(f,i,(x->>'other_line')::uuid,clock_timestamp()+interval '1 hour','maintenance','Use unrelated capable line');
 perform pg_temp.ok(not (public.production_start_readiness(f,i)->'physical'->>'applicable')::boolean,'unrelated line ignores old released machine');
 perform public.start_product_item(f,i);
 perform pg_temp.ok((select status='active' from public.production_orders where id=i),'unrelated line Start unaffected');
 x:=mp_test.released('independent',true);f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 perform public.stop_machine(f,m,'planned',null,'inspection','Unrelated independent product');
 perform public.start_product_item(f,i);
 perform pg_temp.ok((select status='active' from public.production_orders where id=i),'released independent service does not block unrelated Product/line');
 x:=mp_test.fixture('ordinary');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 perform pg_temp.ok(public.production_start_readiness(f,i)->>'queue_ready'='false','unscheduled queue readiness is a Boolean false');
 perform public.stop_machine(f,m,'planned',null,'inspection','No released maintenance');
 perform public.plan_product_item(f,i,(x->>'line')::uuid,clock_timestamp()+interval '1 hour');
 perform public.start_product_item(f,i);
 perform pg_temp.ok((select status='active' from public.production_orders where id=i),'ordinary execution unchanged; no universal running-flow requirement');

 x:=mp_test.released('failed-verification',false,false,false);f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;r:=(x->>'request')::uuid;
 perform public.change_maintenance_request(f,r,'verify','{"result":"REWORK_REQUIRED","verification_note":"Further repair required"}',4,gen_random_uuid());
 perform pg_temp.ok((select state='CONFIRMED' and hold_started_at is not null and released_at is null from public.maintenance_schedules where id=(x->>'schedule')::uuid),'failed verification retains hold');
 perform pg_temp.ok(public.production_start_readiness(f,i)->'maintenance_block'->>'reason'='MAINTENANCE_HOLD','held capacity is displayed separately from queue readiness');
 perform pg_temp.fails(format('select public.start_product_item(%L,%L)',f,i),'maintenance_capacity_reserved');
 x:=mp_test.released('permissions');f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.fails(format('select public.start_product_item(%L,%L)',f,i),'permission_denied');
 perform pg_temp.fails(format('select public.production_start_readiness(%L,%L)',f,i),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 pkg:=public.save_permission_package(f,gen_random_uuid(),'{"name":"Local execution"}','[{"module":"orders","action":"view"},{"module":"orders","action":"edit"}]',0);
 perform public.set_member_permission_packages(f,(x->>'viewer')::uuid,array[pkg],'{}');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.ok((public.production_start_readiness(f,i)->'physical'->>'ready')::boolean,'package-only view grant reads readiness');
 perform public.start_product_item(f,i);
 perform pg_temp.ok((select status='active' from public.production_orders where id=i),'package-only edit grant starts normally');
 y:=mp_test.fixture('foreign');perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.fails(format('select public.production_start_readiness(%L,%L)',y->>'factory',y->>'item'),'permission_denied');
 perform pg_temp.fails(format('select public.production_start_readiness(%L,%L)',f,y->>'item'),'not_found');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.start_product_item_before_readiness(uuid,uuid)','EXECUTE'),'old command body cannot bypass new guard');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.maintenance_execution_readiness(uuid,uuid,uuid,uuid)','EXECUTE'),'private readiness helper not callable directly');
 perform pg_temp.ok(not(select enabled from private.maintenance_planning_activation),'gate remains disabled after local fixture setup');
end$$;
select count(*)||' readiness assertions passed' from assertions;
rollback;
