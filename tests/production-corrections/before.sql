do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable local database required';end if;end$$;
create schema correction_test;
create table correction_test.functions as select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) args,p.prosrc,p.proacl
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f';
create table correction_test.security as select n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind in ('r','v');
create table correction_test.policies as select * from pg_policies where schemaname in ('public','private');
create table correction_test.historical as select id,to_jsonb(c) data from public.production_entry_corrections c;
create table correction_test.gates as select 'maintenance' kind,to_jsonb(g) data from private.maintenance_planning_activation g
 union all select 'recording',to_jsonb(g) from private.production_recording_v3_activation g;
create function correction_test.ok(v boolean,label text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL %',label;end if;insert into correction_test.checks values(label);end$$;
create table correction_test.checks(label text);
create function correction_test.fails(q text,expected text) returns void language plpgsql as $$begin
 begin execute q;exception when others then if sqlstate=expected or sqlerrm=expected then perform correction_test.ok(true,'denied '||expected);return;else raise;end if;end;raise exception 'Expected %',expected;end$$;
