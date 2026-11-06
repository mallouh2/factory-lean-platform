begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Reader assertion failed: %',label;end if;insert into assertions values(label);end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %',message,sqlerrm;end;
 raise exception 'Expected rejection %',message;end$$;
do $$declare x jsonb;f uuid;r uuid;m uuid;i uuid;sid uuid;rr integer;a timestamptz;b timestamptz;outcome jsonb;g jsonb;hist jsonb;hash text;before_counts text;
 extra uuid;begin
 x:=mp_test.fixture('readers');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;m:=(x->>'machine')::uuid;i:=(x->>'item')::uuid;
 select revision into rr from public.maintenance_requests where id=r;
 a:=clock_timestamp()+interval '2 days';b:=a+interval '1 hour';
 outcome:=public.maintenance_planning_preview(f,r,a,b,rr,0);
 perform pg_temp.ok(outcome->>'capacity'='CLEAR' and outcome->>'binding'='false','clear read is nonbinding');
 perform pg_temp.ok(outcome->>'confirmation_available'='false' and not (select enabled from private.maintenance_planning_activation),'gate disabled');
 perform pg_temp.ok(outcome->'scope'->>'kind'='WHOLE_LINE','conservative full line scope');
 perform pg_temp.ok((outcome->>'slack_minutes')::numeric=59,'continuous elapsed duration/slack');
 perform pg_temp.fails(format('select public.maintenance_planning_preview(%L,%L,%L,%L,%s,0)',f,r,a,b,rr+1),'maintenance_preview_stale');
 perform pg_temp.fails(format('select public.maintenance_planning_preview(%L,%L,%L,%L,%s,1)',f,r,a,b,rr),'maintenance_preview_stale');
 perform pg_temp.fails(format('select public.maintenance_planning_preview(%L,%L,%L,%L,%s,0,''bad'')',f,r,a,b,rr),'maintenance_preview_stale');
 perform public.plan_product_item(f,i,(x->>'line')::uuid,a);
 select expected_finish into b from public.production_orders where id=i;
 outcome:=public.maintenance_planning_preview(f,r,a,b,rr,0);
 perform pg_temp.ok(outcome->>'capacity'='BLOCKED' and outcome->'conflicts'->0->>'code'='maintenanceProductionConflict','production setup included once');
 perform pg_temp.ok(public.maintenance_planning_preview(f,r,b,b+interval '1 minute',rr,0)->>'capacity'='CLEAR','adjacent half-open interval');
 g:=public.maintenance_planning_gaps(f,r,a,a+interval '1 day',rr,0);
 perform pg_temp.ok(g->'suggestions'->0->>'start'=to_jsonb(b)#>>'{}','gap begins at stored production finish');
 hash:=g->>'context_hash';
 perform public.revise_product_plan(f,i,(x->>'line')::uuid,a+interval '3 hours','management_decision','Local context change');
 perform pg_temp.fails(format('select public.maintenance_planning_gaps(%L,%L,%L,%L,%s,0,null,10,null,%L)',f,r,a,a+interval '1 day',rr,hash),'maintenance_preview_stale');
 perform pg_temp.fails(format('select public.maintenance_planning_gaps(%L,%L,%L,%L,%s,0)',f,r,a,a+interval '32 days',rr),'maintenance_invalid');
 g:=public.maintenance_planning_gaps(f,r,a,a+interval '1 day',rr,0,null,1);
 perform pg_temp.ok(g->>'has_more'='true' and g->>'occupancy_complete'='true','complete occupancy with paginated suggestions');
 outcome:=public.maintenance_planning_gaps(f,r,a,a+interval '1 day',rr,0,null,1,(g->>'next_after_start')::timestamptz,g->>'context_hash');
 perform pg_temp.ok((outcome->'suggestions'->0->>'start')::timestamptz>(g->'suggestions'->0->>'start')::timestamptz,'stable ascending gap cursor');
 extra:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',x->>'independent','title','Independent preview','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1),gen_random_uuid());
 select revision into rr from public.maintenance_requests where id=extra;
 perform pg_temp.ok(public.maintenance_planning_preview(f,extra,a,b,rr,0)->'scope'->>'kind'='MACHINE','independent machine excludes unrelated line occupancy');
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,(x->>'independent')::uuid,(x->>'product')::uuid,100,'meter');
 perform pg_temp.ok(public.maintenance_planning_preview(f,extra,a,b,rr,0)->>'capacity'='UNKNOWN','unattributed independent product routing remains unknown');
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,(x->>'product')::uuid,1,'work_center',(x->>'independent')::uuid);
 perform pg_temp.ok(public.maintenance_planning_preview(f,extra,a+interval '3 hours',a+interval '4 hours',rr,0)->>'capacity'='BLOCKED','explicit independent machine routing sees production');
 select revision into rr from public.maintenance_requests where id=r;
 sid:=mp_test.plan(x,a,a+interval '1 hour');
 perform public.maintenance_planning_command(f,r,'propose',jsonb_build_object('start',a+interval '1 hour','reason','Local revision'),1,gen_random_uuid());
 hist:=public.maintenance_planning_history(f,r,1);
 perform pg_temp.ok(hist->>'has_more'='true' and hist->>'through_revision'='2','history keyset/high water');
 perform pg_temp.ok(hist->'rows'->0->>'before_evidence'='ADJACENT_RECORDED','previous scope from recorded adjacent revision');
 perform pg_temp.ok(not (hist->'rows'->0->'after_resources'->0 ? 'capabilities'),'history evidence redacted');
 perform public.maintenance_planning_command(f,r,'propose',jsonb_build_object('start',a+interval '2 hours','reason','Later append'),2,gen_random_uuid());
 hist:=public.maintenance_planning_history(f,r,1,2,2);
 perform pg_temp.ok(hist->'rows'->0->>'revision'='1' and hist->>'through_revision'='2','history append does not change frozen older page');
 delete from public.maintenance_schedule_revisions where schedule_id=sid and revision=1;
 hist:=public.maintenance_planning_history(f,r);
 perform pg_temp.ok(hist->'rows'->1->>'before_evidence'='NOT_RECORDED','missing historical scope stays unknown');
 -- Local synthetic fixture setup only: no application writes or gate activation.
 extra:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',m,'title','Conflicting fixture','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'separate_problem',true),gen_random_uuid());
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end,confirmed_by,confirmed_at)
 values(f,extra,'CONFIRMED',a,a+interval '1 hour',(x->>'owner')::uuid,now()) returning id into extra;
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,line_id,impact_reason,evidence) values(f,extra,'LINE',(x->>'line')::uuid,'Local recorded scope','{}');
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,machine_id,impact_reason,evidence) values(f,extra,'MACHINE',m,'Local recorded scope','{}');
 outcome:=public.maintenance_planning_preview(f,r,a,a+interval '1 hour',rr,3);
 perform pg_temp.ok(outcome->>'capacity'='BLOCKED' and jsonb_array_length(outcome->'conflicts')=1,'machine/line resources deduplicated');
 perform pg_temp.ok(private.maintenance_capacity_conflict(f,(x->>'line')::uuid,null,m,a,b)->>'reason'='maintenance_capacity_reserved','write conflict precedence preserved');
 update public.maintenance_schedules set planned_start=now()-interval '2 hours',planned_end=now()-interval '1 hour' where id=extra;
 perform pg_temp.ok(public.maintenance_planning_preview(f,r,a,b,rr,3)->>'capacity'='BLOCKED','missed reservation remains protective');
 update public.maintenance_schedules set state='INVALIDATED' where id=extra;
 perform pg_temp.ok(public.maintenance_planning_gaps(f,r,a,a+interval '1 day',rr,3)->'suggestions'='[]','invalidated has no future gaps');
 update public.maintenance_schedules set state='CONFIRMED',hold_started_at=now() where id=extra;
 perform pg_temp.ok(public.maintenance_planning_gaps(f,r,a,a+interval '1 day',rr,3)->'suggestions'='[]','active hold/overrun is indefinite');
 update public.maintenance_schedules set state='RELEASED',released_at=now(),released_by=(x->>'owner')::uuid where id=extra;
 perform pg_temp.ok(public.maintenance_planning_preview(f,r,a,a+interval '1 hour',rr,3)->>'capacity'='CLEAR','verified release no longer occupies');
 select md5(concat((select count(*) from public.audit_logs),(select count(*) from public.maintenance_commands),(select count(*) from public.maintenance_schedules),(select count(*) from public.maintenance_schedule_revisions),(select sum(revision) from public.maintenance_requests))) into before_counts;
 perform public.maintenance_planning_preview(f,r,a,b,rr,3);perform public.maintenance_planning_gaps(f,r,a,a+interval '1 day',rr,3);perform public.maintenance_planning_history(f,r);
 perform pg_temp.ok(before_counts=md5(concat((select count(*) from public.audit_logs),(select count(*) from public.maintenance_commands),(select count(*) from public.maintenance_schedules),(select count(*) from public.maintenance_schedule_revisions),(select sum(revision) from public.maintenance_requests))),'readers create no audit/history/command/state changes');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.fails(format('select public.maintenance_planning_preview(%L,%L,%L,%L,%s,3)',f,r,a,b,rr),'permission_denied');
 perform pg_temp.ok(public.maintenance_planning_history(f,r)->>'request_id'=r::text,'history does not require Orders view');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.fails(format('select public.maintenance_planning_preview(%L,%L,%L,%L,%s,0)',f,gen_random_uuid(),a,b,rr),'maintenance_missing');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.maintenance_reader_context(uuid,uuid,integer,integer,timestamptz,timestamptz,timestamptz)','EXECUTE'),'private helper cannot bypass readers');
 x:=x||jsonb_build_object('foreign',mp_test.fixture('foreign-reader'));
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.fails(format('select public.maintenance_planning_history(%L,%L)',x->'foreign'->>'factory',x->'foreign'->>'request'),'permission_denied');
 perform pg_temp.fails(format('select public.maintenance_planning_history(%L,%L)',f,x->'foreign'->>'request'),'maintenance_missing');
 -- More than 500 irrelevant historical records must not control selected-resource availability.
 insert into public.maintenance_requests(factory_id,work_center_id,title,priority,source,requested_by,requested_by_name)
 select f,(x->>'other_machine')::uuid,'Old unrelated '||n,'NORMAL','MANUAL',(x->>'owner')::uuid,'Local fixture' from generate_series(1,600)n;
 perform pg_temp.ok(public.maintenance_planning_preview(f,r,a,a+interval '1 hour',rr,3)->>'capacity'='CLEAR','600 unrelated historical requests ignored');
 -- Bound relevant occupancy, fail closed above 10000; no truncated safe windows.
 with created as(insert into public.maintenance_requests(factory_id,work_center_id,title,priority,source,requested_by,requested_by_name)
 select f,m,'Dense relevant '||n,'NORMAL','MANUAL',(x->>'owner')::uuid,'Local fixture' from generate_series(1,10001)n returning id),
 booked as(insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end,confirmed_by,confirmed_at)
 select f,id,'CONFIRMED',a,a+interval '1 hour',(x->>'owner')::uuid,now() from created returning id)
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,line_id,impact_reason,evidence)
 select f,id,'LINE',(x->>'line')::uuid,'Dense local fixture','{}' from booked;
 g:=public.maintenance_planning_gaps(f,r,a,a+interval '1 day',rr,3);
 perform pg_temp.ok(g->>'capacity'='INCOMPLETE' and g->'suggestions'='[]' and g->>'occupancy_complete'='false','incomplete occupancy returns no usable suggestions');
end$$;
select 'PASS '||label from assertions;
rollback;
