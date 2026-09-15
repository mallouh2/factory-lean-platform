-- Transactional integration test; fixtures never survive the final rollback.
begin;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERTION FAILED: %',message;end if;end$$;
create function pg_temp.expect_denied(sql text,message text) returns void language plpgsql as $$begin
 begin execute sql;exception when insufficient_privilege then return;end;
 raise exception 'ASSERTION FAILED: %',message;end$$;
insert into auth.users(id,email,email_confirmed_at) values
('20000000-0000-4000-8000-000000000001','security-owner@example.test',now()),
('20000000-0000-4000-8000-000000000002','security-operator@example.test',now()),
('20000000-0000-4000-8000-000000000003','security-support@example.test',now());
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.factory',public.create_factory('Operations Test','Asia/Qatar','Test')::text,true);
select set_config('test.code',public.get_join_code(current_setting('test.factory')::uuid),true);
select set_config('test.operator_role',(select id::text from public.roles where factory_id=current_setting('test.factory')::uuid and name='Technician / Operator'),true);
select set_config('test.manager_role',(select id::text from public.roles where factory_id=current_setting('test.factory')::uuid and name='Factory Manager'),true);
select set_config('test.product',public.save_record(current_setting('test.factory')::uuid,'products',null,'{"name":"Test product","code":"TEST-P"}')::text,true);
select set_config('test.order',public.save_record(current_setting('test.factory')::uuid,'orders',null,jsonb_build_object('code','TEST-ORDER','product_id',current_setting('test.product'),'target_quantity',100,'status','active'))::text,true);
select set_config('test.center',public.save_record(current_setting('test.factory')::uuid,'centers',null,jsonb_build_object('code','TEST-CENTER','name','Test machine','order_id',current_setting('test.order')))::text,true);
select set_config('test.other',(select id::text from public.downtime_reasons where factory_id=current_setting('test.factory')::uuid and requires_description),true);
reset role;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true(public.request_membership('FAC-WRONG','Operator')->>'error' is not null,'invalid join code rejected');
select pg_temp.assert_true(public.request_membership(current_setting('test.code'),'Operator')->>'ok'='true','valid join request accepted');
select pg_temp.assert_true(not public.can_access(current_setting('test.factory')::uuid,'centers','view'),'pending member has no factory data');
reset role;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.manage_member(current_setting('test.factory')::uuid,(select id from public.memberships where user_id='20000000-0000-4000-8000-000000000002'),current_setting('test.operator_role')::uuid,'approved');
select public.record_output(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,current_setting('test.order')::uuid,12,2,'Test output','30000000-0000-4000-8000-000000000001');
select public.record_output(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,current_setting('test.order')::uuid,12,2,'Test output','30000000-0000-4000-8000-000000000001');
select pg_temp.assert_true((select produced_quantity=12 and rejected_quantity=2 from public.production_orders where id=current_setting('test.order')::uuid),'order totals equal immutable output ledger');
select pg_temp.assert_true((select count(*)=1 from public.production_entries where order_id=current_setting('test.order')::uuid),'output ledger appended once');
do $$begin
 begin perform public.record_output(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,current_setting('test.order')::uuid,2,3,'Invalid rejects');raise exception 'ASSERTION FAILED: excessive rejects accepted';exception when check_violation then null;end;
 begin perform public.change_status(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,'stopped',current_setting('test.other')::uuid);raise exception 'ASSERTION FAILED: Other accepted without text';exception when raise_exception then if sqlerrm<>'description_required' then raise;end if;end;
end$$;
select public.set_support(current_setting('test.factory')::uuid,'20000000-0000-4000-8000-000000000003',current_setting('test.manager_role')::uuid,'temporary',now()+interval '1 hour');
reset role;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true(public.can_access(current_setting('test.factory')::uuid,'machine_status','edit'),'operator has status controls');
select pg_temp.assert_true(not public.can_access(current_setting('test.factory')::uuid,'centers','edit'),'operator cannot edit center engineering configuration');
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,'stopped',current_setting('test.other')::uuid,null,'Test obstruction');
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,'running');
select pg_temp.assert_true((select count(*)=2 from public.status_events where work_center_id=current_setting('test.center')::uuid),'stop and resume preserve both events');
select pg_temp.assert_true((select count(*)=1 from public.downtime_events where work_center_id=current_setting('test.center')::uuid and ended_at is not null),'resume closes downtime');
select pg_temp.expect_denied(format('select public.save_record(%L::uuid,''centers'',%L::uuid,''{"name":"Tampered"}'')',current_setting('test.factory'),current_setting('test.center')),'operator engineering edit denied');
select pg_temp.expect_denied('delete from public.production_entries','output history cannot be deleted');
select pg_temp.assert_true(not public.can_access(current_setting('test.factory')::uuid,'reports','export'),'operator cannot export reports');
reset role;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000003',true);
set local role authenticated;
select pg_temp.assert_true(public.can_access(current_setting('test.factory')::uuid,'centers','view'),'temporary support grant permits scoped reads');
select pg_temp.assert_true(public.factory_snapshot(current_setting('test.factory')::uuid)->'factory'->>'name'='Operations Test','support can open explicitly authorized factory');
reset role;
select pg_temp.assert_true(exists(select 1 from public.audit_logs where actor_id='20000000-0000-4000-8000-000000000003' and action='READ'),'support application reads are audited');
update public.support_access set expires_at=now()-interval '1 second' where user_id='20000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(not public.can_access(current_setting('test.factory')::uuid,'centers','view'),'expired support access denied');
select pg_temp.assert_true((select count(*)=0 from public.work_centers),'expired support cannot read raw work center rows');
select pg_temp.expect_denied(format('select public.factory_snapshot(%L::uuid)',current_setting('test.factory')),'expired support cannot read app snapshot');
rollback;
