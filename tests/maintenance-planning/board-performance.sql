-- Persist ONLY within this disposable database until the runner removes it.
do $$declare x jsonb;f uuid;m uuid;a timestamptz;begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local fixture only';end if;
 x:=mp_test.fixture('board-query-plan');f:=(x->>'factory')::uuid;m:=(x->>'machine')::uuid;a:=clock_timestamp()+interval '1 day';
 with req as(insert into public.maintenance_requests(factory_id,work_center_id,title,priority,source,requested_by,requested_by_name,status)
 select f,m,'Plan history '||n,'NORMAL','MANUAL',(x->>'owner')::uuid,'Local fixture','CANCELLED' from generate_series(1,6000)n returning id)
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end)
 select f,id,'UNSCHEDULED',a-interval '2 years',a-interval '2 years'+interval '1 hour' from req;
 with req as(insert into public.maintenance_requests(factory_id,work_center_id,title,priority,source,requested_by,requested_by_name,status)
 select f,m,'Relevant plan '||n,'NORMAL','MANUAL',(x->>'owner')::uuid,'Local fixture','OPEN' from generate_series(1,600)n returning id)
 insert into public.maintenance_schedules(factory_id,maintenance_request_id,state,planned_start,planned_end)
 select f,id,'PROPOSED',a,a+interval '1 hour' from req;
 create table mp_test.board_plan_case as select x data,a starts,a+interval '7 days' ends;
end$$;
select set_config('request.jwt.claim.sub',(select data->>'owner' from mp_test.board_plan_case),false);
select set_config('request.jwt.claim.role','authenticated',false);
analyze public.maintenance_requests;
analyze public.maintenance_schedules;
explain (analyze,buffers,format json)
select * from private.planning_operational_rows((select (data->>'factory')::uuid from mp_test.board_plan_case),
 (select starts from mp_test.board_plan_case),(select ends from mp_test.board_plan_case),null,null,'maintenance',statement_timestamp());
explain (analyze,buffers,format json)
select public.planning_operational_board((select (data->>'factory')::uuid from mp_test.board_plan_case),
 (select starts from mp_test.board_plan_case),(select ends from mp_test.board_plan_case),null,null,'maintenance');
select jsonb_array_length(public.planning_operational_board((select (data->>'factory')::uuid from mp_test.board_plan_case),
 (select starts from mp_test.board_plan_case),(select ends from mp_test.board_plan_case),null,null,'maintenance')->'rows') bounded_page_records;
select enabled as activation from private.maintenance_planning_activation;
