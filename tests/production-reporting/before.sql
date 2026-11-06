do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local M3A only';end if;end$$;
create schema reporting_compat;
create table reporting_compat.entries as select id,to_jsonb(e) snapshot from public.production_entries e;
create table reporting_compat.observations as select id,to_jsonb(e) snapshot from public.lean_scrap_events e;
create table reporting_compat.saved as select 'lean' kind,id,evidence snapshot from public.lean_saved_comparisons union all select 'loss',id,result from public.production_loss_estimates;
create table reporting_compat.functions as select p.oid,p.prosrc,p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname<>'production_history';
create table reporting_compat.relations as select oid,relacl,relrowsecurity,relforcerowsecurity from pg_class where relnamespace in ('public'::regnamespace,'private'::regnamespace) and relkind='r';
create table reporting_compat.policies as select to_jsonb(p) snapshot from pg_policy p;
