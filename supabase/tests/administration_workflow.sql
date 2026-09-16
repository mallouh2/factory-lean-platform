-- Functional acceptance, isolated fixtures, no persistent schema/data changes.
begin;
insert into auth.users(id,email,email_confirmed_at) values
('41000000-0000-4000-8000-000000000001','workflow-owner@example.test',now()),
('41000000-0000-4000-8000-000000000002','workflow-worker@example.test',now()),
('41000000-0000-4000-8000-000000000003','workflow-support@example.test',now());
select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select set_config('test.factory',public.create_factory('Administration workflow','Asia/Qatar','Test')::text,true);
select set_config('test.code',public.get_join_code(current_setting('test.factory')::uuid),true);
select set_config('test.role',public.save_record(current_setting('test.factory')::uuid,'roles',null,'{"name":"Functional viewer","name_ar":"مشاهد الاختبار"}')::text,true);
select public.set_permissions(current_setting('test.factory')::uuid,current_setting('test.role')::uuid,'[{"module":"factory","action":"view"},{"module":"centers","action":"view"}]');
select set_config('test.manager_role',(select id::text from public.roles where factory_id=current_setting('test.factory')::uuid and name='Factory Manager'),true);
reset role;
select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$begin
 if public.request_membership(current_setting('test.code'),'Workflow employee')->>'ok' is distinct from 'true' then raise exception 'Join request failed';end if;
 if (select status from public.memberships where user_id=auth.uid())<>'pending' then raise exception 'Pending status missing';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.manage_member(current_setting('test.factory')::uuid,(select id from public.memberships where user_id='41000000-0000-4000-8000-000000000002'),current_setting('test.role')::uuid,'approved');
do $$begin
 if not exists(select 1 from public.memberships where user_id='41000000-0000-4000-8000-000000000002' and status='approved' and role_id=current_setting('test.role')::uuid) then raise exception 'Approval or role assignment failed';end if;
 if (select count(*) from public.role_permissions where role_id=current_setting('test.role')::uuid)<>2 then raise exception 'Custom permission matrix mismatch';end if;
end$$;
select public.manage_member(current_setting('test.factory')::uuid,(select id from public.memberships where user_id='41000000-0000-4000-8000-000000000002'),current_setting('test.role')::uuid,'rejected');
do $$begin
 if not exists(select 1 from public.memberships where user_id='41000000-0000-4000-8000-000000000002' and status='rejected') then raise exception 'Rejection failed';end if;
end$$;
select public.set_support_by_email(current_setting('test.factory')::uuid,'workflow-support@example.test',current_setting('test.manager_role')::uuid,'temporary',now()+interval '1 hour');
reset role;
select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $$begin
 if public.factory_snapshot(current_setting('test.factory')::uuid)->'factory'->>'name' is distinct from 'Administration workflow' then raise exception 'Email-based support access failed';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.set_support_by_email(current_setting('test.factory')::uuid,'workflow-support@example.test',current_setting('test.manager_role')::uuid,'disabled',null);
select set_config('test.center',public.save_record(current_setting('test.factory')::uuid,'centers',null,'{"code":"ADMIN-TEST","name":"Workflow table","type":"assembly_table"}')::text,true);
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,'running');
select public.change_status(current_setting('test.factory')::uuid,current_setting('test.center')::uuid,'idle');
select public.save_record(current_setting('test.factory')::uuid,'centers',current_setting('test.center')::uuid,'{"archived":true}');
do $$begin
 if not exists(select 1 from public.work_centers where id=current_setting('test.center')::uuid and archived) then raise exception 'Archive failed';end if;
 if (select count(*) from public.status_events where work_center_id=current_setting('test.center')::uuid)<>2 then raise exception 'Archive lost status history';end if;
 if not exists(select 1 from public.audit_logs where factory_id=current_setting('test.factory')::uuid) then raise exception 'Audit trail missing';end if;
end$$;
rollback;
select 'PASS: factory creation, join request, custom permissions, approval/rejection, support by email, archive and retained history; all fixtures rolled back' as result;
