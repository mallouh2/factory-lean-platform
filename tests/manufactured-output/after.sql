do $$declare t record;d text;begin
 if exists(select 1 from output_preservation.functions b left join pg_proc p on p.oid=b.oid where p.oid is null or row(p.prosrc,p.proacl,p.proconfig) is distinct from row(b.prosrc,b.proacl,b.proconfig)) then raise exception 'Existing function/grant changed';end if;
 if exists(select 1 from output_preservation.relations b left join pg_class p on p.oid=b.oid where p.oid is null or row(p.relacl,p.relrowsecurity,p.relforcerowsecurity) is distinct from row(b.relacl,b.relrowsecurity,b.relforcerowsecurity)) then raise exception 'Existing relation security changed';end if;
 for t in select * from output_preservation.data loop
 execute 'select md5(coalesce(string_agg(v::text,''|'' order by v::text),'''')) from (select to_jsonb(t) v from '||t.name||' t) x' into d;
 if d<>t.digest then raise exception 'Existing data changed: %',t.name;end if;
 end loop;
end$$;
select 'PASS existing functions/grants',count(*) from output_preservation.functions;
select 'PASS existing tables/data',count(*) from output_preservation.data;
