do $$begin
 if exists(select 1 from late_compat.entries b join public.production_entries e using(id) where to_jsonb(e) is distinct from to_jsonb(jsonb_populate_record(null::public.production_entries,b.snapshot)))
 or (select count(*) from late_compat.entries)<>(select count(*) from public.production_entries)
 then raise exception 'Pre-M2 entry mutation';end if;
 if exists(select 1 from late_compat.functions b left join pg_proc p on p.oid=b.oid where row(b.prosrc,b.proacl) is distinct from row(p.prosrc,p.proacl)) then raise exception 'Unrelated function/grant mutation';end if;
 if exists(select 1 from late_compat.relations b join pg_class p on p.oid=b.oid where row(b.relacl,b.relrowsecurity,b.relforcerowsecurity) is distinct from row(p.relacl,p.relrowsecurity,p.relforcerowsecurity)) then raise exception 'Existing relation security mutation';end if;
 if exists(select snapshot from late_compat.policies except select to_jsonb(p) from pg_policy p) then raise exception 'Existing policy mutation';end if;
 if to_regprocedure('public.factory_export_page(uuid,text,integer)') is not null then raise exception 'Export Reader must be absent';end if;
 raise notice 'PASS % existing entries preserved; % unrelated function/grant contracts preserved; existing security preserved', (select count(*) from late_compat.entries),(select count(*) from late_compat.functions);
end$$;
