-- TESTING only. Every temporary permission, membership and audit change rolls back.
begin;
create function pg_temp.check_snapshot_policies(f uuid)
returns void language plpgsql as $$
declare tab text; module text; expected bigint; actual bigint; allowed boolean;
begin
 for tab,module in values ('role_permissions','roles'),('status_events','centers'),
   ('production_loss_context_snapshots','downtime'),('user_permissions','roles') loop
   allowed:=private.has_permission(f,module,'view');
   if (f = any(private.snapshot_read_factories(module))) is distinct from allowed then
     raise exception 'cached % permission differs from authority',module;
   end if;
   if tab='user_permissions' then
     select count(*) into expected from public.user_permissions p where p.factory_id=f
       and (allowed or (p.user_id=auth.uid() and private.has_permission(f,'factory','view')));
   else
     execute format('select count(*) from public.%I where factory_id=$1',tab) into expected using f;
     if not allowed then expected:=0;end if;
   end if;
   execute 'set local role authenticated';
   execute format('select count(*) from public.%I where factory_id=$1',tab) into actual using f;
   execute 'reset role';
   if actual<>expected then raise exception '% RLS changed row visibility',tab;end if;
 end loop;
end;
$$;
create function pg_temp.check_audit_read(f uuid, allowed boolean)
returns void language plpgsql as $$
declare expected bigint; actual bigint;
begin
 if private.has_permission(f,'audit','view') is distinct from allowed then
   raise exception 'fixture does not match existing permission authority';
 end if;
 if (f = any(private.audit_read_factories())) is distinct from allowed then
   raise exception 'cached audit permission differs from authority';
 end if;
 select count(*) into expected from public.audit_logs where factory_id=f;
 execute 'set local role authenticated';
 select count(*) into actual from public.audit_logs where factory_id=f;
 execute 'reset role';
 if actual <> (case when allowed then expected else 0 end) then
   raise exception 'audit RLS changed row visibility';
 end if;
 perform pg_temp.check_snapshot_policies(f);
end;
$$;
do $verify$
declare f uuid; actor uuid; role uuid; foreign_factory uuid; platform_actor uuid; person record;
begin
 select m.factory_id,m.user_id,m.role_id into f,actor,role
 from public.memberships m join public.factories x on x.id=m.factory_id
 where x.is_demo and m.status='approved'
   and not exists(select 1 from private.platform_admins p where p.user_id=m.user_id and p.enabled)
   and exists(select 1 from public.user_permissions p where p.factory_id=m.factory_id
     and p.user_id=m.user_id and p.module='audit' and p.action='view') limit 1;
 if actor is null then raise exception 'existing TESTING audit reader required'; end if;
 -- Every existing person retains exactly the existing authorizer's decision.
 for person in select user_id from public.memberships loop
   perform set_config('request.jwt.claim.sub',person.user_id::text,true);
   perform pg_temp.check_audit_read(f,private.has_permission(f,'audit','view'));
 end loop;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.factories(name) values('QA audit isolation') returning id into foreign_factory;
 insert into public.audit_logs(factory_id,action,entity) values(foreign_factory,'READ','QA snapshot');
 perform pg_temp.check_audit_read(f,true);
 perform pg_temp.check_audit_read(foreign_factory,false);
 -- Without roles:view, own grants remain readable only with factory:view.
 delete from public.user_permissions where factory_id=f and user_id=actor and module='roles' and action='view';
 perform pg_temp.check_snapshot_policies(f);
 delete from public.user_permissions where factory_id=f and user_id=actor and module='factory' and action='view';
 perform pg_temp.check_snapshot_policies(f);
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,actor,'factory','view');
 perform pg_temp.check_snapshot_policies(f);
 delete from public.user_permissions where factory_id=f and user_id=actor and module='audit' and action='view';
 perform pg_temp.check_audit_read(f,false);
 -- Role/owner titles do not replace a per-person grant.
 update public.memberships set is_owner=true where factory_id=f and user_id=actor;
 perform pg_temp.check_audit_read(f,false);
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,actor,'audit','view');
 perform pg_temp.check_audit_read(f,true);
 delete from public.support_access where factory_id=f and user_id=actor;
 update public.memberships set status='pending' where factory_id=f and user_id=actor;
 perform pg_temp.check_audit_read(f,false);
 update public.memberships set status='rejected' where factory_id=f and user_id=actor;
 perform pg_temp.check_audit_read(f,false);
 insert into public.support_access(factory_id,user_id,role_id,mode,expires_at)
 values(f,actor,role,'temporary',now()+interval '1 hour');
 perform pg_temp.check_audit_read(f,true);
 update public.support_access set expires_at=now()-interval '1 hour' where factory_id=f and user_id=actor;
 perform pg_temp.check_audit_read(f,false);
 update public.support_access set mode='permanent' where factory_id=f and user_id=actor;
 perform pg_temp.check_audit_read(f,true);
 update public.support_access set mode='disabled' where factory_id=f and user_id=actor;
 perform pg_temp.check_audit_read(f,false);
 select user_id into platform_actor from private.platform_admins where enabled limit 1;
 if platform_actor is not null then
   perform set_config('request.jwt.claim.sub',platform_actor::text,true);
   perform private.open_platform_factory(foreign_factory);
   perform pg_temp.check_audit_read(foreign_factory,true);
   update private.platform_scopes set expires_at=now()-interval '1 hour'
     where user_id=platform_actor and factory_id=foreign_factory;
   perform pg_temp.check_audit_read(foreign_factory,false);
 end if;
 perform set_config('request.jwt.claim.sub','',true);
 if cardinality(private.audit_read_factories())<>0 then raise exception 'anonymous audit scope exposed'; end if;
 if has_function_privilege('anon','private.audit_read_factories()','execute') then raise exception 'anonymous helper grant'; end if;
 if cardinality(private.snapshot_read_factories('factory'))<>0 then raise exception 'anonymous snapshot scope exposed';end if;
 if has_function_privilege('anon','private.snapshot_read_factories(text)','execute') then raise exception 'anonymous snapshot helper grant';end if;
 if (select prosecdef from pg_proc where oid='public.factory_snapshot(uuid)'::regprocedure) then raise exception 'snapshot lost invoker authorization';end if;
 if exists(select 1 from pg_class where oid in ('public.role_permissions'::regclass,
   'public.status_events'::regclass,'public.production_loss_context_snapshots'::regclass,
   'public.user_permissions'::regclass) and not relrowsecurity) then raise exception 'snapshot table RLS disabled';end if;
 if not (select relrowsecurity from pg_class where oid='public.audit_logs'::regclass) then raise exception 'audit RLS disabled'; end if;
end;
$verify$;
rollback;
