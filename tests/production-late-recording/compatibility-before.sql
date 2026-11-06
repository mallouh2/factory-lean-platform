do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local only';end if;end$$;
create schema late_compat;
create table late_compat.entries as select id,to_jsonb(e) snapshot from public.production_entries e;
create table late_compat.functions as select p.oid,p.prosrc,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('private','public') and p.proname not in ('record_production','record_lean_production','correct_lean_production','source_movement','source_stock_command','maintenance_recording_guard');
create table late_compat.relations as select oid,relacl,relrowsecurity,relforcerowsecurity from pg_class where relnamespace in ('public'::regnamespace,'private'::regnamespace) and relkind='r';
create table late_compat.policies as select to_jsonb(p) snapshot from pg_policy p;
