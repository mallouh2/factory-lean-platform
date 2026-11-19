begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'MP lifecycle assertion failed: %',label;end if;insert into assertions values(label);
end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
 if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %',message,sqlerrm;end;
 raise exception 'Expected rejection %',message;
end$$;
do $$declare x jsonb;f uuid;r uuid;sid uuid;missed uuid;missed_schedule uuid;start_at timestamptz;stop_digest text;machine_digest text;begin
 x:=mp_test.fixture('lifecycle');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;
 update private.maintenance_planning_activation set enabled=true;
 start_at:=clock_timestamp()+interval '2 seconds';sid:=mp_test.plan(x,start_at,start_at+interval '70 seconds');
 perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());
 missed:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',x->>'independent','title','Missed local window','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'assigned_to',x->>'worker'),gen_random_uuid());
 missed_schedule:=mp_test.plan(x||jsonb_build_object('request',missed),start_at);perform mp_test.command(f,missed,'confirm','{}',1,gen_random_uuid());
 select md5(coalesce(jsonb_agg(to_jsonb(e))::text,'')) into stop_digest from public.downtime_events e where e.factory_id=f;
 select md5(jsonb_agg(to_jsonb(m) order by m.id)::text) into machine_digest from public.work_centers m where m.factory_id=f;
 perform pg_sleep(2.1);
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform public.change_maintenance_request(f,r,'start','{}',2,gen_random_uuid());
 perform pg_temp.ok((select hold_started_at is not null and state='CONFIRMED' from public.maintenance_schedules where id=sid),'own assignee starts within available time');
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Local repair complete"}',3,gen_random_uuid());
 perform pg_temp.ok((select hold_started_at is not null and released_at is null from public.maintenance_schedules where id=sid),'completion retains hold');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform public.change_maintenance_request(f,r,'verify','{"result":"REWORK_REQUIRED","verification_note":"Repeat local check"}',4,gen_random_uuid());
 perform pg_temp.ok((select status='IN_PROGRESS' and verified_at is null from public.maintenance_requests where id=r),'failed verification returns work');
 perform pg_temp.ok((select released_at is null from public.maintenance_schedules where id=sid),'failed verification retains hold');
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''unschedule'',''{"reason":"Cannot release active hold"}'',3,gen_random_uuid())',f,r),'maintenance_state');
 perform pg_temp.fails(format('select public.change_maintenance_request(%L,%L,''cancel'',''{"cancellation_note":"Cannot release"}'',5,gen_random_uuid())',f,r),'maintenance_unschedule_required');
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Retested"}',5,gen_random_uuid());
 -- Real elapsed clock overrun in the disposable database; no timestamp edits.
 perform pg_sleep(70);
 perform pg_temp.ok((select planned_end<clock_timestamp() and released_at is null from public.maintenance_schedules where id=sid),'actual overrun retains hold');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.ok(exists(select 1 from jsonb_array_elements(public.maintenance_planning_read(f)->'rows') q where q->>'id'=sid::text and (q->>'overrun')::boolean),'overrun exposed by protected reader');
 perform pg_temp.ok(private.maintenance_capacity_conflict(f,null,null,(x->>'independent')::uuid,clock_timestamp(),clock_timestamp()+interval '1 hour') is not null,'missed window never silently frees capacity');
 perform pg_temp.ok(exists(select 1 from jsonb_array_elements(public.maintenance_planning_read(f)->'rows') q where q->>'id'=missed_schedule::text and (q->>'missed_window')::boolean),'missed window exposed separately from overrun');
 perform pg_temp.fails(format('select public.plan_product_item(%L,%L,%L,%L)',f,x->>'item',x->>'line',clock_timestamp()+interval '1 hour'),'maintenance_capacity_reserved');
 perform public.change_maintenance_request(f,r,'verify','{"result":"RESOLVED","verification_note":"Independent local verification"}',6,gen_random_uuid());
 perform pg_temp.ok((select state='RELEASED' and released_by=(x->>'owner')::uuid from public.maintenance_schedules where id=sid),'independent verification releases hold');
 perform pg_temp.ok((select md5(jsonb_agg(to_jsonb(m) order by m.id)::text)=machine_digest from public.work_centers m where m.factory_id=f),'maintenance lifecycle never changes machines');
 perform pg_temp.ok((select md5(coalesce(jsonb_agg(to_jsonb(e))::text,''))=stop_digest from public.downtime_events e where e.factory_id=f),'no automatic downtime');
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '1 hour');

 x:=mp_test.fixture('late');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;
 start_at:=clock_timestamp()+interval '1 second';sid:=mp_test.plan(x,start_at);perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());perform pg_sleep(1.1);
 perform public.change_maintenance_request(f,r,'start','{}',2,gen_random_uuid());
 perform pg_temp.ok((select hold_started_at is not null from public.maintenance_schedules where id=sid),'late start uses the existing hold');
 -- Legacy/corrective repair never needs Scheduling activation or approval.
 update private.maintenance_planning_activation set enabled=false;
 r:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',x->>'machine','title','Emergency correction','priority','URGENT','assigned_to',x->>'worker','maintenance_kind','CORRECTIVE','separate_problem',true),gen_random_uuid());
 perform set_config('request.jwt.claim.sub',x->>'worker',true);perform public.change_maintenance_request(f,r,'start','{}',2,gen_random_uuid());
 perform pg_temp.ok((select status='IN_PROGRESS' from public.maintenance_requests where id=r),'emergency corrective repair unaffected while activation disabled');
end$$;
select count(*)||' Maintenance lifecycle assertions passed' from assertions;
rollback;
