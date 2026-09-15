-- Run only against isolated development/testing after applying the committed migrations.
-- All fixture users, factories and history are rolled back.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERTION FAILED: %',message;end if;end$$;
insert into auth.users(id,email,email_confirmed_at) values
 ('10000000-0000-4000-8000-000000000001','tenant-a@example.test',now()),
 ('10000000-0000-4000-8000-000000000002','tenant-b@example.test',now()),
 ('10000000-0000-4000-8000-000000000003','operator@example.test',now());
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select set_config('test.factory_a',public.create_factory('Security Test A','Asia/Qatar','test')::text,true);
select set_config('test.center_a',public.save_record(current_setting('test.factory_a')::uuid,'centers',null,'{"name":"Machine A","code":"M-A"}')::text,true);
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
select set_config('test.factory_b',public.create_factory('Security Test B','Asia/Qatar','test')::text,true);
select pg_temp.assert_true((select count(*)=0 from public.work_centers where factory_id=current_setting('test.factory_a')::uuid),'factory B cannot read factory A work centers');
select pg_temp.assert_true(not public.can_access(current_setting('test.factory_a')::uuid,'centers','edit'),'factory B cannot edit factory A');
do $$begin
 begin
 perform public.change_status(current_setting('test.factory_a')::uuid,current_setting('test.center_a')::uuid,'running');
 raise exception 'ASSERTION FAILED: cross-factory RPC accepted';
 exception when insufficient_privilege then null;end;
 begin
 delete from public.audit_logs;
 raise exception 'ASSERTION FAILED: audit delete accepted';
 exception when insufficient_privilege then null;end;
 begin
 update public.status_events set notes='forged';
 raise exception 'ASSERTION FAILED: history update accepted';
 exception when insufficient_privilege then null;end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.change_status(current_setting('test.factory_a')::uuid,current_setting('test.center_a')::uuid,'running');
select pg_temp.assert_true((select count(*)=1 from public.status_events where work_center_id=current_setting('test.center_a')::uuid),'authorized status change appends one event');
select pg_temp.assert_true((select status='running' from public.work_centers where id=current_setting('test.center_a')::uuid),'current status updated atomically');
select pg_temp.assert_true((select count(*)>0 from public.audit_logs where entity='work_centers'),'work center updates are audited');
select set_config('test.old_code',public.get_join_code(current_setting('test.factory_a')::uuid),true);
select pg_temp.assert_true(public.get_join_code(current_setting('test.factory_a')::uuid,true)<>current_setting('test.old_code'),'join code changes on regeneration');
reset role;
select pg_temp.assert_true(not exists(select 1 from private.join_codes where code=current_setting('test.old_code')),'old join code invalidated');
rollback;
