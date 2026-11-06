create schema output_preservation;
create table output_preservation.functions as select p.oid,p.prosrc,p.proacl,p.proconfig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private');
create table output_preservation.relations as select oid,relacl,relrowsecurity,relforcerowsecurity from pg_class where relnamespace in ('public'::regnamespace,'private'::regnamespace) and relkind='r';
create table output_preservation.data(name text primary key,digest text);
do $$declare t record;d text;begin
 for t in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
 execute format('select md5(coalesce(string_agg(v::text,''|'' order by v::text),'''')) from (select to_jsonb(t) v from %I.%I t) x',t.schemaname,t.tablename) into d;
 insert into output_preservation.data values(format('%I.%I',t.schemaname,t.tablename),d);
 end loop;
end$$;
