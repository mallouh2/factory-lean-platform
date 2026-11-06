begin;
create temporary table assertions(label text);
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'Contract assertion: %',label;end if;insert into assertions values(label);end$$;
create function pg_temp.inject_failure() returns trigger language plpgsql as $$begin raise exception 'fixture_history_failure';end$$;
create function pg_temp.fails(statement text,message text,code text default null) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
 if sqlerrm=message and (code is null or sqlstate=code) then insert into assertions values(message);return;end if;
 raise exception 'Expected %/%, got %/%',message,code,sqlerrm,sqlstate;end;
 raise exception 'Expected rejection %',message;end$$;
do $$declare x jsonb;y jsonb;f uuid;r uuid;sid uuid;a timestamptz;b timestamptz;v jsonb;p jsonb;fresh jsonb;retry uuid;counts text;begin
 x:=mp_test.fixture('contract');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;
 a:=clock_timestamp()+interval '2 days';b:=a+interval '1 hour';sid:=mp_test.plan(x,a,b);
 v:=public.maintenance_planning_preview(f,r,a,b,2,1);
 p:=jsonb_build_object('context_hash',v->>'context_hash','request_revision',2);
 perform pg_temp.ok(v->>'capacity'='CLEAR' and length(v->>'context_hash')=64,'SHA256 clear context');
 perform pg_sleep(.03);
 perform pg_temp.ok(v->>'context_hash'=public.maintenance_planning_preview(f,r,a,b,2,1)->>'context_hash','evaluation time excluded');
 perform set_config('TimeZone','Asia/Riyadh',true);
 perform pg_temp.ok(v->>'context_hash'=public.maintenance_planning_preview(f,r,a,b,2,1)->>'context_hash','same instants different session timezone');
 perform set_config('TimeZone','UTC',true);
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,r,p),'maintenance_planning_inactive');
 update private.maintenance_planning_activation set enabled=true;
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',''{}'',1,gen_random_uuid())',f,r),'maintenance_preview_required','22023');
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,r,p||jsonb_build_object('start',a)),'maintenance_invalid');
 -- Capability change after a clear preview must require a new preview even if capacity remains clear.
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',101,'rate_unit','meter','setup_minutes',5)));
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,r,p),'maintenance_preview_stale','40001');
 fresh:=public.maintenance_planning_preview(f,r,a,b,2,1);p:=jsonb_build_object('context_hash',fresh->>'context_hash','request_revision',2);
 retry:=gen_random_uuid();perform public.maintenance_planning_command(f,r,'confirm',p,1,retry);
 perform public.maintenance_planning_command(f,r,'confirm',p,1,retry);
 perform pg_temp.ok((select state='CONFIRMED' and revision=2 from public.maintenance_schedules where id=sid),'fresh confirmation');
 perform pg_temp.ok((select count(*)=2 from public.maintenance_schedule_revisions where schedule_id=sid),'identical retry adds no history');
 perform pg_temp.ok((select count(*)=2 from public.maintenance_schedule_resources where schedule_id=sid),'one source scope allocation');
 perform pg_temp.ok((select payload->'payload'->>'context_hash'=fresh->>'context_hash' from public.maintenance_commands where request_id=retry),'approved fingerprint retained in actor-bound ledger');
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,r,p),'maintenance_preview_stale','40001');
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,%L)',f,r,p||jsonb_build_object('reason','Different retry'),retry),'request_conflict');
 -- Reschedule cannot reuse the old window's preview, nor omit the contract.
 a:=a+interval '1 day';b:=a+interval '1 hour';
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''reschedule'',%L,2,gen_random_uuid())',f,r,jsonb_build_object('start',a,'end',b,'reason','No preview')),'maintenance_preview_required','22023');
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''reschedule'',%L,2,gen_random_uuid())',f,r,p||jsonb_build_object('start',a,'end',b,'reason','Wrong candidate')),'maintenance_preview_stale','40001');
 fresh:=public.maintenance_planning_preview(f,r,a,b,2,2);
 p:=jsonb_build_object('context_hash',fresh->>'context_hash','request_revision',2,'start',a,'end',b,'reason','Reviewed move');
 perform public.maintenance_planning_command(f,r,'reschedule',p,2,gen_random_uuid());
 perform pg_temp.ok((select revision=3 and planned_start=a from public.maintenance_schedules where id=sid),'fresh reschedule');
 -- A correct fingerprint for a blocked window never replaces capacity enforcement.
 y:=x||jsonb_build_object('request',public.create_maintenance_request(f,jsonb_build_object('work_center_id',x->>'machine','title','Second planned service','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'separate_problem',true),gen_random_uuid()));
 perform mp_test.plan(y,a,b);fresh:=public.maintenance_planning_preview(f,(y->>'request')::uuid,a,b,2,1);
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,y->>'request',jsonb_build_object('context_hash',fresh->>'context_hash','request_revision',2)),'maintenance_capacity_reserved');
 perform pg_temp.ok((select state='PROPOSED' from public.maintenance_schedules where maintenance_request_id=(y->>'request')::uuid),'failed capacity check leaves proposal');
 -- Request revision changed, then proposal revision changed.
 x:=mp_test.fixture('contract-revisions');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;sid:=mp_test.plan(x,a,b);
 v:=public.maintenance_planning_preview(f,r,a,b,2,1);p:=jsonb_build_object('context_hash',v->>'context_hash','request_revision',2);
 perform public.maintenance_planning_command(f,r,'details','{"maintenance_kind":"PLANNED","estimated_duration_minutes":2}',2,gen_random_uuid());
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,r,p),'maintenance_preview_stale','40001');
 perform public.maintenance_planning_command(f,r,'propose',jsonb_build_object('start',a,'end',b,'reason','Revise draft'),1,gen_random_uuid());
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,r,p),'maintenance_preview_stale','40001');
 v:=public.maintenance_planning_preview(f,r,a,b,3,2);p:=jsonb_build_object('context_hash',v->>'context_hash','request_revision',3);
 -- Existing individual grants, not role labels or the preview hash, authorize commands.
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,2,gen_random_uuid())',f,r,p),'permission_denied','42501');
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'viewer')::uuid,'orders','edit');
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,2,gen_random_uuid())',f,r,p),'permission_denied','42501');
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'viewer')::uuid,'orders','view');
 perform public.maintenance_planning_command(f,r,'confirm',p,2,gen_random_uuid());
 perform pg_temp.ok((select confirmed_by=(x->>'viewer')::uuid from public.maintenance_schedules where id=sid),'person with exact grants can confirm');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 y:=mp_test.fixture('contract-foreign');perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,2,gen_random_uuid())',y->>'factory',r,p),'permission_denied','42501');
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,2,gen_random_uuid())',f,y->>'request',p),'maintenance_missing');
 perform pg_temp.ok(not has_function_privilege('authenticated','private.maintenance_reader_context(uuid,uuid,integer,integer,timestamptz,timestamptz,timestamptz)','EXECUTE'),'no private context bypass');
 perform pg_temp.ok(not has_function_privilege('anon','public.maintenance_planning_command(uuid,uuid,text,jsonb,integer,uuid)','EXECUTE'),'no anonymous command');
 perform pg_temp.ok(not has_table_privilege('authenticated','public.maintenance_schedules','UPDATE'),'no direct reservation write');
 -- Any failure after the reservation update rolls back resources, history, audit and retry ledger.
 x:=mp_test.fixture('contract-rollback');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;sid:=mp_test.plan(x,a,b);
 fresh:=public.maintenance_planning_preview(f,r,a,b,2,1);p:=jsonb_build_object('context_hash',fresh->>'context_hash','request_revision',2);retry:=gen_random_uuid();
 select jsonb_build_array((select count(*) from public.audit_logs where factory_id=f),(select count(*) from public.maintenance_commands where factory_id=f),
  (select count(*) from public.maintenance_schedule_revisions where factory_id=f),(select count(*) from public.maintenance_schedule_resources where factory_id=f))::text into counts;
 create trigger contract_fixture_failure before insert on public.maintenance_schedule_revisions for each row execute function pg_temp.inject_failure();
 perform pg_temp.fails(format('select public.maintenance_planning_command(%L,%L,''confirm'',%L,1,%L)',f,r,p,retry),'fixture_history_failure');
 drop trigger contract_fixture_failure on public.maintenance_schedule_revisions;
 perform pg_temp.ok((select state='PROPOSED' and revision=1 from public.maintenance_schedules where id=sid),'failed persistence rolls back schedule');
 perform pg_temp.ok(counts=jsonb_build_array((select count(*) from public.audit_logs where factory_id=f),(select count(*) from public.maintenance_commands where factory_id=f),
  (select count(*) from public.maintenance_schedule_revisions where factory_id=f),(select count(*) from public.maintenance_schedule_resources where factory_id=f))::text,'failed persistence conserves history resources audit and command counts');
 perform public.maintenance_planning_command(f,r,'confirm',p,1,retry);
 perform pg_temp.ok((select state='CONFIRMED' and revision=2 from public.maintenance_schedules where id=sid),'same payload can retry after rollback');
 update private.maintenance_planning_activation set enabled=false;
 perform pg_temp.ok(not (select enabled from private.maintenance_planning_activation),'gate restored');
end$$;
select count(*)||' Phase 4 contract assertions passed' from assertions;
rollback;
