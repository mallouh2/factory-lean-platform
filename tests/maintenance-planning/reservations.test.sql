begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'MP assertion failed: %',label;end if;insert into assertions values(label);
end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
 if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %: %',message,sqlerrm,statement;end;
 raise exception 'Expected rejection %',message;
end$$;
do $$declare x jsonb;y jsonb;sid uuid;f uuid;r uuid;i uuid;m uuid;other uuid;retry uuid;start_at timestamptz;ends timestamptz;begin
 x:=mp_test.fixture('reservation');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;i:=(x->>'item')::uuid;m:=(x->>'machine')::uuid;
 perform pg_temp.ok(not (select enabled from private.maintenance_planning_activation),'activation disabled by default');
 perform pg_temp.ok((select maintenance_kind='PLANNED' and status='ASSIGNED' and downtime_id is null from public.maintenance_requests where id=r),'planned unscheduled request preserves lifecycle/origin');
 perform pg_temp.ok((select count(*)=0 from public.maintenance_schedules where factory_id=f),'no automatic schedule');
 start_at:=now()+interval '30 minutes';ends:=start_at+interval '1 hour';sid:=mp_test.plan(x,start_at,ends);
 perform pg_temp.ok(private.maintenance_capacity_conflict(f,(x->>'line')::uuid,null,null,start_at,ends) is null,'proposal has no capacity');
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''confirm'',''{}'',1,gen_random_uuid())',f,r),'maintenance_planning_inactive');
 update private.maintenance_planning_activation set enabled=true;
 retry:=gen_random_uuid();perform mp_test.command(f,r,'confirm','{}',1,retry);
 perform mp_test.command(f,r,'confirm','{}',1,retry);
 perform pg_temp.ok((select count(*)=1 from public.maintenance_schedules where maintenance_request_id=r),'idempotent confirmation');
 perform pg_temp.ok((select count(*)=2 from public.maintenance_schedule_resources where schedule_id=sid),'blocking machine and line reserved');
 perform pg_temp.ok((select count(*)=2 from public.maintenance_schedule_revisions where schedule_id=sid),'retry adds no history');
 perform pg_temp.fails(format('select public.plan_product_item(%L,%L,%L,%L)',f,i,x->>'line',start_at),'maintenance_capacity_reserved');
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''reschedule'',%L,1,gen_random_uuid())',f,r,jsonb_build_object('start',start_at+interval '3 hours','reason','Stale edit')),'maintenance_preview_stale');
 perform public.plan_product_item(f,i,(x->>'line')::uuid,ends);
 perform public.set_plan_lock(f,i,true);
 perform pg_temp.fails(format('select public.revise_product_plan(%L,%L,%L,%L,''maintenance'',''No override'')',f,i,x->>'line',ends+interval '2 hours'),'planning_locked');
 perform pg_temp.ok((select planning_locked_at is not null and start_time=ends from public.production_orders where id=i),'locked plan unchanged and adjacency valid');
 perform pg_temp.fails(format('select public.start_product_item(%L,%L)',f,i),'maintenance_capacity_reserved');
 perform pg_temp.ok((select status='planned' and actual_start is null from public.production_orders where id=i),'early production failure rolls back');
 perform pg_temp.fails(format('update public.production_orders set start_time=%L,expected_finish=%L where id=%L',start_at,ends,i),'maintenance_capacity_reserved');
 -- Confirm another request against persisted production, with no UI-only warning.
 other:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',m,'title','Other planned service','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'separate_problem',true),gen_random_uuid());
 perform mp_test.plan(x||jsonb_build_object('request',other),ends,ends+interval '30 minutes');
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''confirm'',''{}'',1,gen_random_uuid())',f,other),'maintenance_production_conflict');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''unschedule'',''{"reason":"No authority"}'',2,gen_random_uuid())',f,r),'permission_denied');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform mp_test.command(f,r,'unschedule','{"reason":"Explicit planning release"}',2,gen_random_uuid());
 perform pg_temp.ok((select state='UNSCHEDULED' and revision=3 from public.maintenance_schedules where id=sid),'reasoned unschedule');
 perform public.start_product_item(f,i);perform public.finish_product_item(f,i);
 perform pg_temp.ok((select actual_finish is not null and start_time=ends and planning_locked_at is not null from public.production_orders where id=i),'normal execution no conflict preserves plan and lock');
 perform mp_test.command(f,r,'reschedule',jsonb_build_object('start',ends+interval '1 day','reason','Explicit new maintenance window'),3,gen_random_uuid());
 perform pg_temp.ok((select state='CONFIRMED' and revision=4 and planned_start=ends+interval '1 day' from public.maintenance_schedules where id=sid),'successful reasoned reschedule');
 perform pg_temp.ok((select count(*)=4 from public.maintenance_schedule_revisions where schedule_id=sid),'historical windows preserved');
 perform mp_test.command(f,r,'unschedule','{"reason":"Eligible future cancellation"}',4,gen_random_uuid());
 perform public.change_maintenance_request(f,r,'cancel','{"cancellation_note":"Cancel future service"}',2,gen_random_uuid());
 perform pg_temp.ok((select status='CANCELLED' from public.maintenance_requests where id=r),'future request cancellation after explicit release');

 -- Independent machines do not block unrelated line capacity.
 x:=mp_test.fixture('independent');f:=(x->>'factory')::uuid;
 r:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',x->>'independent','title','Independent service','priority','NORMAL','assigned_to',x->>'worker','maintenance_kind','PLANNED','estimated_duration_minutes',1),gen_random_uuid());
 x:=x||jsonb_build_object('request',r);sid:=mp_test.plan(x,start_at,ends);perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());
 perform pg_temp.ok((select count(*)=1 from public.maintenance_schedule_resources where schedule_id=sid),'independent machine only');
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'other_line')::uuid,start_at);
 perform public.start_product_item(f,(x->>'item')::uuid);perform public.finish_product_item(f,(x->>'item')::uuid);
 perform pg_temp.ok((select state='CONFIRMED' from public.maintenance_schedules where id=sid),'unrelated execution unchanged');
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform pg_temp.fails(format('select public.change_maintenance_request(%L,%L,''start'',''{}'',2,gen_random_uuid())',f,r),'maintenance_early_start');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);

 -- Topology/capability changes keep approval history but invalidate readiness.
 x:=mp_test.fixture('configuration');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;m:=(x->>'machine')::uuid;
 update public.work_centers set dependency_mode='buffer',buffer_minutes=30 where id=m;
 sid:=mp_test.plan(x,start_at,ends);perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());
 perform pg_temp.ok((select count(*)=1 from public.maintenance_schedule_resources where schedule_id=sid and resource_kind='LINE'),'unknown buffer still reserves line');
 perform public.configure_center_capabilities(f,m,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',100,'rate_unit','meter','setup_minutes',5)));
 perform pg_temp.ok((select state='INVALIDATED' and confirmed_at is not null from public.maintenance_schedules where id=sid),'configuration invalidates without erasing approval');
 perform pg_temp.ok((select count(*)=3 from public.maintenance_schedule_revisions where schedule_id=sid),'invalidation audited');
 perform pg_temp.fails(format('select public.plan_product_item(%L,%L,%L,%L)',f,x->>'item',x->>'line',ends+interval '4 hours'),'maintenance_capacity_reserved');
 y:=mp_test.fixture('foreign');perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''propose'',%L,0,gen_random_uuid())',f,y->>'request',jsonb_build_object('start',start_at)),'maintenance_missing');
 perform pg_temp.ok(not has_table_privilege('authenticated','public.maintenance_schedules','UPDATE'),'no direct schedule writes');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.maintenance_capacity_conflict(uuid,uuid,uuid,uuid,timestamptz,timestamptz,uuid,uuid,boolean)','EXECUTE'),'no private conflict bypass');
end$$;
select count(*)||' Maintenance reservation assertions passed' from assertions;
rollback;
