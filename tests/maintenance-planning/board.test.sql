-- Disposable loopback fixture only: synthetic historical/operational reservations,
-- not claims of actual production or hosted acceptance. Application triggers stay enabled.
begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Operational board assertion failed: %',label;end if;insert into assertions values(label);end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %',message,sqlerrm;end;
 raise exception 'Expected rejection %',message;end$$;
create temporary table cases(x jsonb,a timestamptz,b timestamptz);
grant all on cases,assertions to authenticated;
do $$declare x jsonb;f uuid;m uuid;a timestamptz;b timestamptz;sid uuid;v jsonb;v2 jsonb;ids uuid[];lastk text;lasti uuid;hash text;at_time timestamptz;counted integer:=0;begin
 x:=mp_test.fixture('board-scale');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;
 a:=clock_timestamp()+interval '1 day';b:=a+interval '7 days';
 -- More than500 visible proposals, each with normal factory/machine FKs.
 with req as (insert into public.maintenance_requests(factory_id,work_center_id,title,priority,source,requested_by,requested_by_name,status)
 select f,m,'Board synthetic proposal '||n,'NORMAL','MANUAL',(x->>'owner')::uuid,'Local fixture','OPEN' from generate_series(1,551)n returning id),
 booked as (insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end)
 select f,id,'PROPOSED',a,a+interval '1 hour' from req returning id)
 select array_agg(id) into ids from booked;
 sid:=ids[1];x:=x||jsonb_build_object('schedule',sid);
 with req as(insert into public.production_requests(factory_id,code,name,requested_by,priority)
 select f,'BOARD-P-'||n,'Synthetic board production '||n,(x->>'owner')::uuid,'normal' from generate_series(1,551)n returning id,code)
 insert into public.production_orders(factory_id,request_id,product_id,code,target_quantity,unit,status,line_id,start_time,expected_finish)
 select f,id,(x->>'product')::uuid,f::text||code,1,'meter','planned',(x->>'line')::uuid,
 a+row_number() over(order by id)*interval '10 minutes',a+row_number() over(order by id)*interval '10 minutes'+interval '6 minutes' from req;
 -- More than500 unrelated completed/cancelled historical records must stay outside the horizon.
 with req as (insert into public.maintenance_requests(factory_id,work_center_id,title,priority,source,requested_by,requested_by_name,status)
 select f,m,'Old historical board '||n,'NORMAL','MANUAL',(x->>'owner')::uuid,'Local fixture','CANCELLED' from generate_series(1,701)n returning id)
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end)
 select f,id,'UNSCHEDULED',a-interval '2 years',a-interval '2 years'+interval '1 hour' from req;
 with old as(insert into public.production_requests(factory_id,code,name,requested_by,priority)
 select f,'BOARD-H-'||n,'Historical production '||n,(x->>'owner')::uuid,'normal' from generate_series(1,701)n returning id,code)
 insert into public.production_orders(factory_id,request_id,product_id,code,target_quantity,unit,status,line_id,start_time,expected_finish)
 select f,id,(x->>'product')::uuid,f::text||code,1,'meter','planned',(x->>'line')::uuid,
 a-interval '2 years'+row_number() over(order by id)*interval '10 minutes',a-interval '2 years'+row_number() over(order by id)*interval '10 minutes'+interval '6 minutes' from old;
 insert into cases values(x,a,b);
 loop
 v:=public.planning_operational_board(f,a,b,null,null,'maintenance',100,lastk,lasti,hash,at_time);
 perform pg_temp.ok(v->>'completeness'='INCOMPLETE','single page never labels a partial board complete');
 perform pg_temp.ok((v->>'scope_complete')::boolean,'all operational scope evaluated');
 perform pg_temp.ok((v->>'total')::integer=552,'551 proposals plus one current unscheduled request, history excluded');
 counted:=counted+jsonb_array_length(v->'rows');
 exit when not(v->>'has_more')::boolean;
 lastk:=v->'next'->>'kind';lasti:=(v->'next'->>'id')::uuid;hash:=v->>'context_hash';at_time:=(v->>'evaluated_at')::timestamptz;
 end loop;
 perform pg_temp.ok(counted=552,'six bounded pages contain every relevant record, beyond500');
 v:=public.planning_operational_board(f,a,b);
 raise notice 'All-domain total %, production rows %, stored rows %',v->>'total',
 (select count(*) from private.planning_operational_rows(f,a,b,null,null,'all',clock_timestamp()) where kind='PRODUCTION'),
 (select count(*) from public.production_orders where factory_id=f);
 perform pg_temp.ok((v->>'total')::integer=1104,'complete production and Maintenance scope exceeds500 independently');
 perform pg_temp.ok((select count(*)=551 from private.planning_operational_rows(f,a,b,null,null,'all',clock_timestamp()) where kind='PRODUCTION' and payload->'order'->>'line_id'=x->>'line'),'all551 production reservations selected by overlap');
 perform pg_temp.ok(not exists(select 1 from private.planning_operational_rows(f,a,b,null,null,'maintenance',clock_timestamp()) r where r.payload->'request'->>'title' like 'Old historical%'),'unrelated701 histories excluded at database boundary');
 v:=public.planning_operational_board(f,a,b,(x->>'other_line')::uuid,null,'maintenance');
 perform pg_temp.ok(v->>'total'='0' and v->>'completeness'='COMPLETE','selected unrelated line is complete empty scope');
 v:=public.planning_operational_board(f,a,b,null,(x->>'independent')::uuid,'maintenance');
 perform pg_temp.ok(v->>'total'='0','independent machine scoped separately');
 perform pg_temp.fails(format('select public.planning_operational_board(%L,%L,%L,null,null,''maintenance'',101)',f,a,b),'maintenance_invalid');
 perform pg_temp.fails(format('select public.planning_operational_board(%L,%L,%L)',f,a,a+interval '32 days'),'maintenance_invalid');
 perform pg_temp.fails(format('select public.planning_operational_board(%L,%L,%L,%L)',f,a,b,gen_random_uuid()),'maintenance_missing');
 v:=public.planning_operational_board(f,a,b,null,null,'maintenance');
 update public.maintenance_requests set title=title||' corrected' where id=(select maintenance_request_id from public.maintenance_schedules where id=sid);
 perform pg_temp.fails(format('select public.planning_operational_board(%L,%L,%L,null,null,''maintenance'',100,%L,%L,%L,%L)',f,a,b,v->'next'->>'kind',v->'next'->>'id',v->>'context_hash',v->>'evaluated_at'),'maintenance_board_changed');
end$$;
do $$declare x jsonb;y jsonb;f uuid;r uuid;sid uuid;a timestamptz;b timestamptz;v jsonb;row jsonb;begin
 x:=mp_test.fixture('board-retained');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;
 a:=clock_timestamp()+interval '1 day';b:=a+interval '1 day';
 -- A missed original window is still a current protective reservation.
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end,confirmed_by,confirmed_at)
 values(f,r,'CONFIRMED',a-interval '30 days',a-interval '29 days',(x->>'owner')::uuid,clock_timestamp()) returning id into sid;
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,machine_id,impact_reason,evidence) values(f,sid,'MACHINE',(x->>'machine')::uuid,'Local machine reservation','{}');
 insert into public.maintenance_schedule_resources(factory_id,schedule_id,resource_kind,line_id,impact_reason,evidence) values(f,sid,'LINE',(x->>'line')::uuid,'Local line reservation','{}');
 v:=public.planning_operational_board(f,a,b,(x->>'line')::uuid,null,'maintenance');row:=v->'rows'->0->'payload'->'schedule';
 perform pg_temp.ok(v->>'total'='1','old missed window is included by effective overlap');
 perform pg_temp.ok(row->>'missed_window'='true' and row->'occupancy'->>'continues'='true','missed reservation stays protective');
 perform pg_temp.ok(row->>'overrun'='false' and row->>'actual_hold'='false','missed window does not invent physical overrun or actual hold');
 perform pg_temp.ok(jsonb_array_length(row->'line_ids')=1,'machine/line reservation deduplicated');
 perform pg_temp.ok((row->'occupancy'->>'start')::timestamptz=(select starts from private.maintenance_occupancy(f,(x->>'line')::uuid,null,null,null,null,false,clock_timestamp(),a,b) where id=sid),'projection starts match authoritative occupancy');
 perform pg_temp.ok((select ends='infinity'::timestamptz from private.maintenance_occupancy(f,(x->>'line')::uuid,null,null,null,null,false,clock_timestamp(),a,b) where id=sid),'authoritative missed occupancy also continues');
 update public.maintenance_schedules set state='INVALIDATED' where id=sid;
 v:=public.planning_operational_board(f,a,b,null,null,'maintenance');
 perform pg_temp.ok(v->'rows'->0->'payload'->'schedule'->>'state'='INVALIDATED','invalidated window still represented');
 delete from public.maintenance_schedule_resources where schedule_id=sid;
 v:=public.planning_operational_board(f,a,b,null,null,'maintenance');
 perform pg_temp.ok(v->>'completeness'='INCOMPLETE' and v->>'scope_complete'='false','missing persisted reservation resources are unknown, never free');
 y:=mp_test.released('board-actual');f:=(y->>'factory')::uuid;
 a:=clock_timestamp()-interval '1 hour';b:=a+interval '2 hours';
 v:=public.planning_operational_board(f,a,b,null,null,'maintenance');
 select z->'payload'->'schedule' into row from jsonb_array_elements(v->'rows')z where z->>'id'=y->>'schedule';
 perform pg_temp.ok(row->>'state'='RELEASED' and row->'occupancy'->>'reserved'='false','released original window visible without reserving current capacity');
 perform pg_temp.ok(row->>'actual_hold'='false','released maintenance has no current physical hold');
 perform pg_temp.ok(jsonb_array_length(row->'actual_stops')=1,'real linked physical stop represented separately');
 perform pg_temp.ok((row->'actual_stops'->0->>'started_at')::timestamptz=(select started_at from public.downtime_events where id=(y->>'event')::uuid),'original physical timestamp unchanged');
 y:=mp_test.released('board-active-hold',false,false,false);f:=(y->>'factory')::uuid;
 a:=clock_timestamp()+interval '1 day';b:=a+interval '1 day';
 v:=public.planning_operational_board(f,a,b,null,null,'maintenance');
 select z->'payload'->'schedule' into row from jsonb_array_elements(v->'rows')z where z->>'id'=y->>'schedule';
 perform pg_temp.ok(row->>'actual_hold'='true' and row->'occupancy'->>'continues'='true','real active hold before horizon remains visible after physical stop closure');
 perform pg_temp.ok((row->>'planned_end')::timestamptz<a,'held schedule original approved timestamps stay before horizon');
 perform pg_temp.ok(row->'actual_stops'='[]'::jsonb,'closed historical physical stop is not invented inside future horizon');

end$$;
set local role authenticated;
do $$declare x jsonb;a timestamptz;b timestamptz;begin
 select cases.x,cases.a,cases.b into x,a,b from cases;
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.ok(public.planning_operational_board((x->>'factory')::uuid,a,b,null,null,'maintenance')->>'total'='552','Maintenance-only viewer can read its operational queue');
 perform pg_temp.fails(format('select public.planning_operational_board(%L,%L,%L)',x->>'factory',a,b),'permission_denied');
 perform pg_temp.fails(format('select public.planning_operational_board(%L,%L,%L,null,null,''maintenance'')',gen_random_uuid(),a,b),'permission_denied');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.planning_operational_rows(uuid,timestamptz,timestamptz,uuid,uuid,text,timestamptz)','execute'),'no direct projection helper access');
end$$;
reset role;
select count(*) as passed_assertions from assertions;
rollback;
