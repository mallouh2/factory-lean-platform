begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Maintenance Loss assertion failed: %',label;end if;insert into assertions values(label);end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %',message,sqlerrm;end;
 raise exception 'Expected rejection %',message;end$$;
create temporary table cases(x jsonb);
grant all on cases,assertions to authenticated;
do $$declare x jsonb;f uuid;e uuid;m jsonb;p uuid;begin
 x:=mp_test.released('loss-reader');f:=(x->>'factory')::uuid;e:=(x->>'event')::uuid;insert into cases values(x);
 m:=public.production_loss_maintenance_context(f,e);
 perform pg_temp.ok(m->>'review_state'='UNREVIEWED','new event is not reviewed');
 perform pg_temp.ok((m->'evidence'->>'valid')::boolean,'frozen approved machine scope verified');
 perform pg_temp.ok(m->'evidence'->>'association_revision'='1','exact association revision');
 perform pg_temp.ok(m->'evidence'->>'machine_id'=x->>'machine','machine matches actual event');
 perform pg_temp.ok((select bool_and(context->>'maintenance_loss_context_version'='1' and context->>'demand_complete'='true' and jsonb_typeof(context->'routing_steps')='array') from public.production_loss_context_snapshots where factory_id=f and event_id=e),'new snapshots capture completeness and routing');
 m:=public.production_loss_review_inputs(f,e);
 perform pg_temp.ok(length(m->>'input_hash')=64,'trusted source bundle SHA256');
 perform pg_temp.ok(jsonb_array_length(m->'samples')>0,'trusted samples in authoritative statement');
 perform pg_temp.ok(m->'maintenance'=public.production_loss_maintenance_context(f,e)->'evidence','read and write policy evidence agree');
 perform pg_temp.ok(not has_function_privilege('authenticated','public.persist_production_loss_estimate(uuid,uuid,uuid,jsonb,uuid)','execute'),'browser cannot persist result JSON');
 perform pg_temp.ok(has_function_privilege('service_role','public.persist_production_loss_estimate(uuid,uuid,uuid,jsonb,uuid)','execute'),'trusted service-only persistence');
 perform pg_temp.ok(not has_table_privilege('authenticated','public.maintenance_stop_associations','select'),'association ledger never exposed');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.production_loss_inputs(uuid,uuid)','execute'),'private bundle inaccessible');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.correct_downtime_classification_before_loss(uuid,uuid,text,uuid,text,text)','execute'),'classification predecessor private');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.record_production_loss_actuals_before_loss(uuid,uuid,numeric,text,numeric,numeric,numeric,numeric,numeric,text)','execute'),'actuals predecessor private');
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'viewer')::uuid,'downtime','view');
 p:=public.save_permission_package(f,gen_random_uuid(),jsonb_build_object('name','Local Loss edit'),jsonb_build_array(jsonb_build_object('module','downtime','action','view'),jsonb_build_object('module','downtime','action','edit')),0);
 perform public.set_member_permission_packages(f,(x->>'worker')::uuid,array[p],'{}');
end$$;
set local role authenticated;
do $$declare x jsonb;f uuid;e uuid;begin
 x:=(select cases.x from cases);f:=(x->>'factory')::uuid;e:=(x->>'event')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.ok(public.production_loss_maintenance_context(f,e)->>'review_state'='UNREVIEWED','view-only engineer can read evidence');
 perform pg_temp.fails(format('select public.production_loss_review_inputs(%L,%L)',f,e),'permission_denied');
 perform pg_temp.fails(format('select public.production_loss_maintenance_context(%L,%L)',gen_random_uuid(),e),'permission_denied');
 perform pg_temp.fails(format('select public.production_loss_maintenance_context(%L,%L)',f,gen_random_uuid()),'history_event_not_found');
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform pg_temp.ok(length(public.production_loss_review_inputs(f,e)->>'input_hash')=64,'package-only trusted calculation read');
end$$;
reset role;
do $$declare x jsonb;f uuid;e uuid;a timestamptz;v uuid;begin
 x:=(select cases.x from cases);f:=(x->>'factory')::uuid;e:=(x->>'event')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 a:=(select planned_start from public.maintenance_schedules where id=(x->>'schedule')::uuid);
 -- Explicit isolated historical fixture; the protected link retains frozen approval.
 insert into public.downtime_events(factory_id,work_center_id,line_id,started_at,ended_at,entered_by,stop_nature,planned_activity)
 values(f,(x->>'machine')::uuid,(x->>'line')::uuid,a-interval '1 minute',a+interval '1 minute',(x->>'owner')::uuid,'planned','inspection') returning id into v;
 perform public.correct_maintenance_stop(f,v,(x->>'schedule')::uuid,2,'LINK','Recorded early start, retain approval',0,gen_random_uuid());
 perform pg_temp.ok((public.production_loss_maintenance_context(f,v)->'evidence'->>'approved_start')::timestamptz=a,'early actual stop never extends frozen approval');
 perform pg_temp.ok((select count(*)=2 from public.maintenance_stop_associations where factory_id=f and schedule_id=(x->>'schedule')::uuid and operation='LINK'),'multiple real stops retain separate associations');
 perform pg_temp.ok(not(select enabled from private.maintenance_planning_activation),'activation restored false');
end$$;
select count(*) as passed_assertions from assertions;
rollback;
