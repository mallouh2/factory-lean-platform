-- Capture installed contracts, not a second implementation of their behavior.
do $$begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local only';end if;
end$$;
create schema shift_compat;
create table shift_compat.functions as
select p.oid, p.oid::regprocedure::text signature, pg_get_functiondef(p.oid) definition, p.proacl::text acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('public','private') and p.prokind='f'
and not (n.nspname='public' and p.proname='configure_production_shift')
and not (n.nspname='private' and p.proname='update_settings');
create table shift_compat.relations as
select c.oid,c.relacl::text acl,c.relrowsecurity,c.relforcerowsecurity
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname in ('public','private');
create table shift_compat.policies as select * from pg_policies where schemaname in ('public','private');
