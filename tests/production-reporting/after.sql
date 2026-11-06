do $$begin
 if exists(select 1 from reporting_compat.entries b left join public.production_entries e using(id) where to_jsonb(e) is distinct from b.snapshot) then raise exception 'M3A changed entry';end if;
 if exists(select 1 from reporting_compat.observations b left join public.lean_scrap_events e using(id) where to_jsonb(e)-array['time_precision','occurrence_key','period_start','period_end'] is distinct from b.snapshot) then raise exception 'M3A changed observation';end if;
 if exists(select 1 from reporting_compat.saved b where b.snapshot is distinct from case when b.kind='lean' then (select evidence from public.lean_saved_comparisons where id=b.id) else (select result from public.production_loss_estimates where id=b.id) end) then raise exception 'M3A changed saved evidence';end if;
 if exists(select 1 from reporting_compat.functions b left join pg_proc p using(oid) where row(b.prosrc,b.proacl) is distinct from row(p.prosrc,p.proacl)) then raise exception 'M3A changed unrelated function/grants';end if;
 if exists(select 1 from reporting_compat.relations b left join pg_class p using(oid) where row(b.relacl,b.relrowsecurity,b.relforcerowsecurity) is distinct from row(p.relacl,p.relrowsecurity,p.relforcerowsecurity)) then raise exception 'M3A changed ACL/RLS';end if;
 if exists(select snapshot from reporting_compat.policies except select to_jsonb(p) from pg_policy p) then raise exception 'M3A changed policy';end if;
 if to_regprocedure('public.factory_export_page(uuid,text,integer)') is not null then raise exception 'Export Reader applied';end if;
 raise notice 'Preserved % entries, % observations, % saved estimates, % unrelated functions and existing security', (select count(*) from reporting_compat.entries),(select count(*) from reporting_compat.observations),(select count(*) from reporting_compat.saved),(select count(*) from reporting_compat.functions);
end$$;
