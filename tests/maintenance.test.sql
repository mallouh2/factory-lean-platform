-- TESTING only. Everything, including temporary grants and factory fixtures, rolls back.
begin;
create function pg_temp.mr_assert(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Maintenance: %',label;end if;end$$;
create function pg_temp.mr_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlerrm=expected then return;end if;raise exception 'expected %, got %',expected,sqlerrm;end;
 raise exception 'expected % but succeeded',expected;end$$;
do $test$
declare f uuid:='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a';actor uuid:='d699a3ac-fab0-4faf-b958-f3902bc357ba';
 worker uuid:='90a63464-4abd-5143-b2c2-062fd16efb53';verifier uuid:='1b833245-6ef7-5fab-b096-78605cbde7f1';
 rejected uuid:='3f9d81aa-562a-54c0-bd6d-d48b85d9bdbe';m uuid;event uuid;r uuid;r2 uuid;r3 uuid;retry uuid:=gen_random_uuid();
 p jsonb;command text;stamp timestamptz:=clock_timestamp();old_stops jsonb;old_machines jsonb;old_transfers jsonb;old_loss jsonb;
 old_orders jsonb;foreign_factory uuid;foreign_machine uuid;foreign_category uuid;detail jsonb;
begin
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.user_permissions(factory_id,user_id,module,action)
  select f,u,'maintenance',a from unnest(array[actor,verifier]) u cross join unnest(array['view','create','edit']) a on conflict do nothing;
 select id into m from public.work_centers where factory_id=f and not archived and status='running' order by code limit 1;
 perform pg_temp.mr_assert(m is not null,'running machine fixture exists');
 select d.id into event from public.downtime_events d where d.factory_id=f and not exists(select 1 from public.maintenance_requests r
  where r.factory_id=f and r.downtime_id=d.id and r.status not in ('VERIFIED','CANCELLED')) order by d.started_at desc limit 1;
 select jsonb_agg(to_jsonb(x) order by id) into old_stops from public.downtime_events x;
 select jsonb_agg(to_jsonb(x) order by id) into old_machines from public.work_centers x;
 select jsonb_agg(to_jsonb(x) order by id) into old_transfers from public.production_transfers x;
 select jsonb_agg(to_jsonb(x) order by id) into old_loss from public.production_loss_estimates x;
 select jsonb_agg(to_jsonb(x) order by id) into old_orders from public.production_orders x;
 p:=jsonb_build_object('work_center_id',m,'title',' QA manual ','description','Problem context','priority','HIGH','separate_problem',true);
 r:=public.create_maintenance_request(f,p,retry);
 perform pg_temp.mr_assert((select status='OPEN' and requested_by=actor and requested_at>=stamp and created_at=requested_at
  and priority='HIGH' and title='QA manual' and source='MANUAL' and downtime_id is null from public.maintenance_requests where id=r),'manual server actor/time and fields');
 perform pg_temp.mr_assert(public.create_maintenance_request(f,p,retry)=r,'manual retry persistence');
 r3:=public.create_maintenance_request(f,p||'{"title":"Confirmed separate sensor fault"}',gen_random_uuid());
 perform pg_temp.mr_assert(r3<>r and (select count(*) from public.maintenance_requests where id in(r,r3)
  and work_center_id=m and source='MANUAL' and downtime_id is null)=2,'distinct confirmed manual problems share a running machine');
 perform pg_temp.mr_assert((select status='running' from public.work_centers where id=m),'maintenance never stops the running machine');
 perform pg_temp.mr_assert((public.maintenance_machine_context(f,m)->>'total')::integer>=2,'active problems remain visible in machine context');
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,%L)',f,p||'{"title":"other"}',retry),'request_conflict');
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,gen_random_uuid())',f,p||'{"separate_problem":false}'),'maintenance_existing');
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,gen_random_uuid())',f,p||'{"priority":"INVALID"}'),'maintenance_invalid');
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,gen_random_uuid())',f,p||jsonb_build_object('requested_by',worker)),'maintenance_invalid');
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,gen_random_uuid())',f,p||jsonb_build_object('work_center_id',gen_random_uuid())),'maintenance_machine');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,1,gen_random_uuid())',f,r,'assign',jsonb_build_object('assigned_to',rejected)),'maintenance_assignee');
 perform public.change_maintenance_request(f,r,'assign',jsonb_build_object('assigned_to',worker),1,gen_random_uuid());
 perform pg_temp.mr_assert((select status='ASSIGNED' and assigned_to=worker and assigned_by=actor and assigned_at is not null and revision=2 from public.maintenance_requests where id=r),'assignment');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,1,gen_random_uuid())',f,r,'priority','{"priority":"LOW"}'),'maintenance_conflict');
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform pg_temp.mr_assert(not private.has_permission(f,'maintenance','edit'),'worker has no manager grant');
 perform pg_temp.mr_assert((public.maintenance_page(f,'{"status":"ALL"}',1,r)->'detail'->>'id')::uuid=r,'own request visible without broad grant');
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,gen_random_uuid())',f,p),'permission_denied');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,2,gen_random_uuid())',f,r,'priority','{"priority":"URGENT"}'),'permission_denied');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,2,gen_random_uuid())',f,r,'assign',jsonb_build_object('assigned_to',actor)),'permission_denied');
 retry:=gen_random_uuid();perform public.change_maintenance_request(f,r,'start','{}',2,retry);
 perform pg_temp.mr_assert(public.change_maintenance_request(f,r,'start','{}',2,retry)=r,'start retry');
 perform pg_temp.mr_assert((select status='IN_PROGRESS' and started_by=worker and started_at is not null and revision=3 from public.maintenance_requests where id=r),'started');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,3,gen_random_uuid())',f,r,'complete','{"work_note":" "}'),'maintenance_note');
 perform public.change_maintenance_request(f,r,'note','{"work_note":"Diagnosed coupling"}',3,gen_random_uuid());
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Replaced coupling, test run done"}',4,gen_random_uuid());
 perform pg_temp.mr_assert((select status='COMPLETED' and work_note='Replaced coupling, test run done' and completed_by=worker
  and completed_at is not null and verified_at is null and verified_by is null from public.maintenance_requests where id=r),'completed is not verified');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,5,gen_random_uuid())',f,r,'verify','{"result":"RESOLVED","verification_note":"Pass"}'),'permission_denied');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform public.change_maintenance_request(f,r,'verify','{"result":"REWORK_REQUIRED","verification_note":"Still vibrating"}',5,gen_random_uuid());
 perform pg_temp.mr_assert((select status='IN_PROGRESS' and verified_at is null and checked_by=actor and verification_result='REWORK_REQUIRED' from public.maintenance_requests where id=r),'failed verification returns work');
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Alignment corrected"}',6,gen_random_uuid());
 insert into public.user_permissions values(f,worker,'maintenance','edit',now(),actor) on conflict do nothing;
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,7,gen_random_uuid())',f,r,'verify','{"result":"RESOLVED","verification_note":"Pass"}'),'maintenance_independent_verifier');
 perform set_config('request.jwt.claim.sub',verifier::text,true);
 perform public.change_maintenance_request(f,r,'verify','{"result":"RESOLVED","verification_note":"Production trial stable"}',7,gen_random_uuid());
 detail:=public.maintenance_page(f,'{"status":"VERIFIED"}',1,r);
 perform pg_temp.mr_assert(detail->'detail'->>'status'='VERIFIED' and (detail->'detail'->>'verified_by')::uuid=verifier
  and detail->'detail'->>'verification_note'='Production trial stable','reload verifier and note');
 perform pg_temp.mr_assert((detail->>'history_total')::integer=8,'one audit per write with before/after');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,8,gen_random_uuid())',f,r,'cancel','{"cancellation_note":"No"}'),'maintenance_state');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select work_center_id into m from public.downtime_events where id=event;
 p:=jsonb_build_object('work_center_id',m,'downtime_id',event,'title','Downtime repair','priority','URGENT');
 r2:=public.create_maintenance_request(f,p,gen_random_uuid());
 perform pg_temp.mr_assert(public.create_maintenance_request(f,p,gen_random_uuid())=r2,'same downtime repeated clicks idempotent');
 perform pg_temp.mr_assert((select source='DOWNTIME' and downtime_id=event and line_id=(select line_id from public.downtime_events where id=event)
  from public.maintenance_requests where id=r2),'authoritative downtime machine/line link');
 detail:=public.maintenance_page(f,'{}',1,r2);
 perform pg_temp.mr_assert((detail->'detail'->'downtime'->>'id')::uuid=event,'downtime back reference');
 perform pg_temp.mr_assert((public.maintenance_downtime_context(f,event)->'event'->>'id')::uuid=event,'exact linked downtime reader');
 perform pg_temp.mr_assert((public.maintenance_machine_context(f,m)->>'total')::integer>=1,'Floor compact active context');
 perform public.change_maintenance_request(f,r2,'priority','{"priority":"LOW"}',1,gen_random_uuid());
 perform public.change_maintenance_request(f,r2,'assign',jsonb_build_object('assigned_to',actor),2,gen_random_uuid());
 perform public.change_maintenance_request(f,r2,'assign',jsonb_build_object('assigned_to',worker),3,gen_random_uuid());
 perform public.change_maintenance_request(f,r2,'assign',jsonb_build_object('assigned_to',actor),4,gen_random_uuid());
 perform public.change_maintenance_request(f,r2,'cancel','{"cancellation_note":"Duplicate problem resolved"}',5,gen_random_uuid());
 perform pg_temp.mr_assert((select status='CANCELLED' and cancelled_by=actor from public.maintenance_requests where id=r2),'cancel with audit');
 perform set_config('request.jwt.claim.sub',worker::text,true);
 delete from public.user_permissions where factory_id=f and user_id=worker and module='maintenance';
 perform pg_temp.mr_error(format('select public.maintenance_page(%L,%L,1,%L)',f,'{}',r2),'maintenance_missing');
 perform set_config('request.jwt.claim.sub',rejected::text,true);
 perform pg_temp.mr_error(format('select public.maintenance_page(%L)',f),'permission_denied');
 -- A distinct factory with a real existing user tests composite FK/command boundaries without creating users.
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.factories(name,timezone) values('Maintenance rollback factory','Asia/Qatar') returning id into foreign_factory;
 insert into public.work_center_categories(factory_id,name) values(foreign_factory,'Maintenance QA') returning id into foreign_category;
 insert into public.work_centers(factory_id,code,name,status,category_id) values(foreign_factory,'MR-QA','Foreign machine','idle',foreign_category) returning id into foreign_machine;
 update public.memberships set factory_id=foreign_factory,role_id=null,status='approved' where user_id=rejected;
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,gen_random_uuid())',f,
  jsonb_build_object('work_center_id',m,'title','Cross-factory assignee','priority','NORMAL','separate_problem',true,'assigned_to',rejected)),'maintenance_assignee');
 perform pg_temp.mr_error(format('select public.create_maintenance_request(%L,%L,gen_random_uuid())',f,
  jsonb_build_object('work_center_id',foreign_machine,'title','Cross factory','priority','NORMAL')),'maintenance_machine');
 perform pg_temp.mr_error(format('select public.maintenance_page(%L)',foreign_factory),'permission_denied');
 perform pg_temp.mr_error(format('select public.change_maintenance_request(%L,%L,%L,%L,1,gen_random_uuid())',foreign_factory,r,'start','{}'),'permission_denied');
 perform pg_temp.mr_assert(not has_table_privilege('authenticated','public.maintenance_requests','INSERT')
  and not has_table_privilege('authenticated','public.maintenance_requests','UPDATE')
  and not has_table_privilege('authenticated','public.maintenance_commands','SELECT'),'no direct writes or retry-ledger access');
 perform pg_temp.mr_assert(not has_function_privilege('anon','public.create_maintenance_request(uuid,jsonb,uuid)','EXECUTE'),'no anonymous RPC');
 perform pg_temp.mr_assert((select jsonb_agg(to_jsonb(x) order by id) from public.downtime_events x)=old_stops,'downtime immutable');
 perform pg_temp.mr_assert((select jsonb_agg(to_jsonb(x) order by id) from public.work_centers x where factory_id<>foreign_factory)=old_machines,'machines preserved');
 perform pg_temp.mr_assert((select jsonb_agg(to_jsonb(x) order by id) from public.production_transfers x)=old_transfers,'transfers unchanged');
 perform pg_temp.mr_assert((select jsonb_agg(to_jsonb(x) order by id) from public.production_loss_estimates x) is not distinct from old_loss,'loss authoritative unchanged');
 perform pg_temp.mr_assert((select jsonb_agg(to_jsonb(x) order by id) from public.production_orders x)=old_orders,'Planning/execution unchanged');
end$test$;
select set_config('request.jwt.claim.sub','90a63464-4abd-5143-b2c2-062fd16efb53',true);
set local role authenticated;
select pg_temp.mr_assert((select count(*) from public.maintenance_requests where title='QA manual')=1,'RLS allows assigned row');
select pg_temp.mr_assert((select count(*) from public.maintenance_requests where title='Downtime repair')=0,'RLS hides unrelated row');
select pg_temp.mr_error('select * from public.maintenance_commands','permission denied for table maintenance_commands');
reset role;
select 'Maintenance assertions passed' result;
rollback;
