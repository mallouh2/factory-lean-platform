do $$declare changed text;begin
 select string_agg(b.signature,', ') into changed from shift_compat.functions b
 left join pg_proc p on p.oid=b.oid
 where p.oid is null or pg_get_functiondef(p.oid) is distinct from b.definition or p.proacl::text is distinct from b.acl;
 if changed is not null then raise exception 'M1 changed inherited functions/grants: %',changed;end if;
 if exists(select 1 from shift_compat.relations b left join pg_class c on c.oid=b.oid
 where c.oid is null or (c.relacl::text,c.relrowsecurity,c.relforcerowsecurity) is distinct from (b.acl,b.relrowsecurity,b.relforcerowsecurity))
 then raise exception 'M1 changed existing table permissions/RLS';end if;
 if exists((select * from shift_compat.policies except select * from pg_policies where schemaname in ('public','private'))
 union all (select * from pg_policies where schemaname in ('public','private') except select * from shift_compat.policies))
 then raise exception 'M1 changed existing RLS policies';end if;
 if to_regprocedure('public.factory_export_page(uuid,text,integer)') is not null then raise exception 'Export Reader must remain excluded';end if;
 raise notice 'PASS % inherited function definitions/grants, table security and policies unchanged; Export Reader absent', (select count(*) from shift_compat.functions);
end$$;
