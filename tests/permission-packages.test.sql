-- TESTING only. Existing people are reused; all fixtures, grants and audit rows roll back.
begin;
create temporary table package_checks(label text);
grant insert on package_checks to authenticated;
create function pg_temp.pp_assert(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Permission packages: %',label;end if;
 insert into package_checks values(label);end$$;
create function pg_temp.pp_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlerrm=expected then insert into package_checks values(expected);return;end if;
  raise exception 'expected %, got %',expected,sqlerrm;
 end;raise exception 'expected % but succeeded',expected;end$$;
do $test$
declare f uuid:='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a';admin uuid:='d699a3ac-fab0-4faf-b958-f3902bc357ba';
 worker uuid:='90a63464-4abd-5143-b2c2-062fd16efb53';owner uuid:='c94a7c99-7833-51da-aa7c-1edd2592ce71';
 rejected uuid:='3f9d81aa-562a-54c0-bd6d-d48b85d9bdbe';production uuid;planning uuid;warehouse uuid;foreign_factory uuid;foreign_package uuid;custom uuid:=gen_random_uuid();
 baseline text;row_digest text;person record;permission record;page jsonb;role_id uuid;membership_id uuid;amount bigint;before_audit bigint;definition jsonb;
begin
 -- This existing full-administration QA person receives new feature keys only inside rollback.
 insert into public.user_permissions(factory_id,user_id,module,action) select f,admin,module,action from public.permissions where module in ('lean','lean_standards') on conflict do nothing;
 perform pg_temp.pp_assert(position('private.require_permission' in split_part(pg_get_functiondef('private.save_permission_package(uuid,uuid,jsonb,jsonb,integer)'::regprocedure),'pg_advisory_xact_lock',2))>0,'package editing rechecks authority after serialization');
 perform pg_temp.pp_assert(position('private.require_permission' in split_part(pg_get_functiondef('private.set_member_permission_packages(uuid,uuid,uuid[],uuid[])'::regprocedure),'pg_advisory_xact_lock',2))>0,'package assignment rechecks authority after serialization');
 -- Baseline authority is identical before adoption, including inactive membership guard.
 perform pg_temp.pp_assert((select count(*)=8 from public.permission_packages where factory_id=f),'eight coherent defaults');
 perform pg_temp.pp_assert(not exists(select 1 from public.member_permission_packages),'migration assigned nobody');
 for person in select * from public.memberships loop
  perform set_config('request.jwt.claim.sub',person.user_id::text,true);
  for permission in select * from public.permissions loop
   perform pg_temp.pp_assert(public.can_access(person.factory_id,permission.module,permission.action)
     = (private.platform_scope(person.factory_id) or person.status='approved' and exists(select 1 from public.user_permissions p where p.factory_id=person.factory_id and p.user_id=person.user_id and p.module=permission.module and p.action=permission.action)),
     'unchanged gate '||person.display_name||' '||permission.module||':'||permission.action);
  end loop;
 end loop;
 perform set_config('request.jwt.claim.sub',admin::text,true);
 select md5(jsonb_agg(to_jsonb(p) order by user_id,module,action)::text) into baseline from public.user_permissions p where factory_id=f;
 select id into production from public.permission_packages where factory_id=f and template_key='production_engineer';
 select id into planning from public.permission_packages where factory_id=f and template_key='planning_engineer';
 select id into warehouse from public.permission_packages where factory_id=f and template_key='warehouse';
 perform set_config('request.jwt.claim.sub',owner::text,true);
 perform public.set_member_permission_packages(f,worker,array[planning,warehouse],array[]::uuid[]);
 perform pg_temp.pp_assert((select count(*)=2 from public.member_permission_packages where factory_id=f and user_id=worker),'authorized factory owner assigns multiple packages');
 perform public.set_member_permission_packages(f,worker,array[]::uuid[],array[planning,warehouse]);
 perform set_config('request.jwt.claim.sub',admin::text,true);
 select count(*) into before_audit from public.audit_logs where factory_id=f and entity='member_permission_packages';
 perform public.set_member_permission_packages(f,worker,array[planning],array[]::uuid[]);
 perform pg_temp.pp_assert((select md5(jsonb_agg(to_jsonb(p) order by user_id,module,action)::text)=baseline from public.user_permissions p where factory_id=f),'assignment preserves every direct row');
 perform set_config('request.jwt.claim.sub',worker::text,true);
 execute 'set local role authenticated';
 perform pg_temp.pp_assert(public.can_access(f,'orders','edit'),'single package enables Planning and Execution existing gate');
 page:=public.permission_package_page(f,worker);
 perform pg_temp.pp_assert(page->'inherited' ? 'orders:edit','self can inspect inherited permission');
 perform pg_temp.pp_assert(jsonb_array_length(page->'packages')=1,'self reads only assigned package definitions');
 perform pg_temp.pp_error(format('select public.permission_package_page(%L,%L)',f,admin),'permission_denied');
 perform pg_temp.pp_error(format('select public.set_member_permission_packages(%L,%L,array[]::uuid[],array[%L]::uuid[])',f,worker,planning),'permission_denied');
 perform pg_temp.pp_error(format('select public.save_permission_package(%L,%L,%L::jsonb,%L::jsonb,0)',f,custom,'{"name":"Unauthorized"}','[]'),'permission_denied');
 perform pg_temp.pp_error(format('insert into public.member_permission_packages(factory_id,user_id,package_id) values(%L,%L,%L)',f,worker,production),'permission denied for table member_permission_packages');
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',admin::text,true);
 perform public.set_member_permission_packages(f,worker,array[planning,production,planning],array[planning]);
 perform pg_temp.pp_assert((select count(*)=2 from public.member_permission_packages where factory_id=f and user_id=worker),'duplicate assignments normalized');
 perform pg_temp.pp_assert((select count(*)=1 from private.effective_person_permissions(f,worker) where module='orders' and action='view'),'overlap and direct duplicate resolves once');
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform pg_temp.pp_assert(public.can_access(f,'centers','edit') and public.can_access(f,'orders','edit'),'Production Engineer plus Planning Engineer union');
 perform set_config('request.jwt.claim.sub',admin::text,true);
 perform public.set_member_permission_packages(f,worker,array[planning],array[planning,production]);
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform pg_temp.pp_assert(public.can_access(f,'orders','edit'),'shared grant retained after removing Production');
 perform pg_temp.pp_assert(not public.can_access(f,'centers','edit'),'Production-only inherited grant removed');
 perform set_config('request.jwt.claim.sub',admin::text,true);
 perform pg_temp.pp_error(format('select public.set_member_permission_packages(%L,%L,array[%L]::uuid[],array[]::uuid[])',f,worker,warehouse),'permission_package_conflict');
 -- Direct changes are independent, retain metadata, and reject stale saves.
 select md5(jsonb_agg(to_jsonb(p) order by module,action)::text) into row_digest from public.user_permissions p where factory_id=f and user_id=worker;
 select jsonb_agg(jsonb_build_object('module',module,'action',action)) into definition from public.user_permissions where factory_id=f and user_id=worker;
 perform public.set_member_direct_permissions(f,worker,definition||'[{"module":"maintenance","action":"view"}]',array(select module||':'||action from public.user_permissions where factory_id=f and user_id=worker));
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform pg_temp.pp_assert(public.can_access(f,'maintenance','view') and public.can_access(f,'orders','edit'),'direct additions coexist with packages');
 perform set_config('request.jwt.claim.sub',admin::text,true);
 perform pg_temp.pp_error(format('select public.set_member_direct_permissions(%L,%L,%L::jsonb,array[]::text[])',f,worker,definition),'permission_package_conflict');
 perform public.set_member_direct_permissions(f,worker,definition,array(select module||':'||action from public.user_permissions where factory_id=f and user_id=worker));
 perform pg_temp.pp_assert((select md5(jsonb_agg(to_jsonb(p) order by module,action)::text)=row_digest from public.user_permissions p where factory_id=f and user_id=worker),'direct restoration preserves original metadata');
 -- Factory isolation: identity alone cannot reference or edit another factory's package.
 insert into public.factories(name) values('Rollback permission package isolation') returning id into foreign_factory;
 select id into foreign_package from public.permission_packages where factory_id=foreign_factory and template_key='warehouse';
 perform pg_temp.pp_assert((select count(*)=8 from public.permission_packages where factory_id=foreign_factory),'future factory gets its own defaults');
 perform pg_temp.pp_error(format('select public.set_member_permission_packages(%L,%L,array[%L]::uuid[],array[%L]::uuid[])',f,worker,foreign_package,planning),'permission_denied');
 perform pg_temp.pp_error(format('select public.save_permission_package(%L,%L,%L::jsonb,%L::jsonb,1)',f,foreign_package,'{"name":"Cross factory"}','[]'),'permission_denied');
 execute 'set local role authenticated';
 select count(*) into amount from public.permission_packages where factory_id=foreign_factory;
 execute 'reset role';
 perform pg_temp.pp_assert(amount=0,'package RLS hides another factory');
 perform public.save_permission_package(f,custom,'{"name":"QA local package","name_ar":"حزمة اختبار","description":"Rollback only"}','[{"module":"warehouse","action":"view"},{"module":"warehouse","action":"view"}]',0);
 perform pg_temp.pp_assert((select count(*)=1 from public.permission_package_permissions where package_id=custom),'duplicate definition grants normalized');
 perform public.save_permission_package(f,custom,'{"name":"QA local package","name_ar":"حزمة اختبار","description":"Rollback only"}','[{"module":"warehouse","action":"view"}]',0);
 perform pg_temp.pp_assert((select revision=1 from public.permission_packages where id=custom),'identical retry is idempotent');
 perform public.save_permission_package(f,custom,'{"name":"QA local package"}','[{"module":"warehouse","action":"view"},{"module":"warehouse","action":"edit"}]',1);
 perform pg_temp.pp_error(format('select public.save_permission_package(%L,%L,%L::jsonb,%L::jsonb,1)',f,custom,'{"name":"Stale"}','[]'),'permission_package_conflict');
 perform pg_temp.pp_error(format('select public.save_permission_package(%L,%L,%L::jsonb,%L::jsonb,2)',f,custom,'{"name":"Fake permission"}','[{"module":"production","action":"manage"}]'),'invalid_input');
 perform pg_temp.pp_assert((select name='Warehouse' from public.permission_packages where id=foreign_package),'factory customization isolated');
 perform public.set_member_permission_packages(f,worker,array[custom],array[planning]);
 perform public.save_permission_package(f,custom,'{"name":"QA local package"}','[{"module":"warehouse","action":"view"}]',2);
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform pg_temp.pp_assert(public.can_access(f,'warehouse','view') and not public.can_access(f,'warehouse','edit'),'package edit updates assigned persons live');
 perform set_config('request.jwt.claim.sub',admin::text,true);
 -- Prevent package privilege escalation, even for a limited roles editor.
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,worker,'roles','edit') on conflict do nothing;
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform pg_temp.pp_error(format('select public.set_member_permission_packages(%L,%L,array[%L]::uuid[],array[%L]::uuid[])',f,worker,production,custom),'cannot_grant_higher_permissions');
 perform pg_temp.pp_error(format('select public.save_permission_package(%L,%L,%L::jsonb,%L::jsonb,3)',f,custom,'{"name":"Escalated"}','[{"module":"warehouse","action":"edit"}]'),'cannot_grant_higher_permissions');
 perform set_config('request.jwt.claim.sub',admin::text,true);
 delete from public.user_permissions where factory_id=f and user_id=worker and module='roles' and action='edit';
 -- The owner flag and job title never become an implicit authorization bypass.
 perform pg_temp.pp_error(format('select public.set_member_permission_packages(%L,%L,array[]::uuid[],array[]::uuid[])',f,owner),'invalid_member');
 update public.memberships set job_title='Factory Owner / Admin' where factory_id=f and user_id=worker;
 perform set_config('request.jwt.claim.sub',worker::text,true);
 perform pg_temp.pp_assert(not public.can_access(f,'roles','edit'),'job title grants nothing');
 update public.memberships set status='rejected' where factory_id=f and user_id=worker;
 perform pg_temp.pp_assert(not public.can_access(f,'warehouse','view'),'inactive membership cannot use packages');
 update public.memberships set status='approved' where factory_id=f and user_id=worker;
 perform set_config('request.jwt.claim.sub',admin::text,true);
 select m.id,m.role_id into membership_id,role_id from public.memberships m where m.factory_id=f and m.user_id=rejected;
 -- Approval assignment rolls back if existing membership approval fails.
 perform pg_temp.pp_error(format('select public.approve_member_packages(%L,%L,null,array[%L]::uuid[],array[]::uuid[])',f,membership_id,planning),'role_required');
 perform pg_temp.pp_assert(not exists(select 1 from public.member_permission_packages where factory_id=f and user_id=rejected),'failed approval leaves no package assignment');
 perform public.approve_member_packages(f,membership_id,role_id,array[planning,production],array[]::uuid[]);
 perform pg_temp.pp_assert((select status='approved' from public.memberships where id=membership_id),'approval plus multi-package assignment succeeds atomically');
 perform pg_temp.pp_assert((select count(*)=2 from public.member_permission_packages where factory_id=f and user_id=rejected),'approval retains multiple functions');
 -- Every major existing permission key consumes the same package resolver.
 select id into custom from public.permission_packages where factory_id=f and template_key='owner';
 perform public.set_member_permission_packages(f,worker,array[custom],array(select package_id from public.member_permission_packages where factory_id=f and user_id=worker));
 perform set_config('request.jwt.claim.sub',worker::text,true);
 for permission in select * from public.permissions loop
  perform pg_temp.pp_assert(public.can_access(f,permission.module,permission.action),'package-backed existing gate '||permission.module||':'||permission.action);
 end loop;
 execute 'set local role authenticated';
 page:=public.factory_snapshot(f);
 execute 'reset role';
 perform pg_temp.pp_assert(page->'permissions' ?& array['orders:edit','downtime:edit','maintenance:edit','warehouse:issue','purchasing:edit','sales_orders:approve','roles:edit'],'actual snapshot consumes package-backed feature and administration gates');
 perform pg_temp.pp_assert(page->'membership'->>'user_id'=worker::text,'effective admin grants do not change membership identity or position');
 perform set_config('request.jwt.claim.sub',admin::text,true);
 perform pg_temp.pp_assert((select count(*)>before_audit from public.audit_logs where factory_id=f and entity='member_permission_packages' and actor_id=admin),'assignment audit has authenticated actor');
 perform pg_temp.pp_assert(exists(select 1 from public.audit_logs where factory_id=f and entity='member_permission_packages' and action='DELETE' and actor_id=admin),'removal audited');
 perform pg_temp.pp_assert(exists(select 1 from public.audit_logs where factory_id=f and entity='permission_packages' and action='UPDATE' and actor_id=admin),'package changes audited');
 -- Existing platform scope remains the sole elevated factory authorization mechanism.
 perform set_config('request.jwt.claim.sub',owner::text,true);
 perform public.open_platform_factory(foreign_factory);
 perform public.save_permission_package(foreign_factory,foreign_package,'{"name":"Scoped platform customization"}','[{"module":"warehouse","action":"view"}]',1);
 perform pg_temp.pp_assert((select name='Scoped platform customization' from public.permission_packages where id=foreign_package),'registered platform admin may manage an explicitly opened factory');
 update private.platform_scopes set expires_at=now()-interval '1 second' where factory_id=foreign_factory and user_id=owner;
 perform pg_temp.pp_error(format('select public.save_permission_package(%L,%L,%L::jsonb,%L::jsonb,2)',foreign_factory,foreign_package,'{"name":"Expired scope"}','[]'),'permission_denied');
 set constraints all immediate;
end$test$;
select format('Permission packages: %s assertions passed; all fixtures rolled back',count(*)) result from package_checks;
rollback;
