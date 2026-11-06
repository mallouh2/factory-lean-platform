do $$declare saved record;actual record;begin
 for saved in select * from correction_test.functions loop
  select p.prosrc,p.proacl into actual from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=saved.nspname and p.proname=saved.proname and pg_get_function_identity_arguments(p.oid)=saved.args;
  if saved.nspname='private' and saved.proname in ('seed_permission_packages','correct_lean_production') then continue;end if;
  if saved.nspname='private' and saved.proname='correct_production' and saved.args=pg_get_function_identity_arguments('private.correct_production(uuid,uuid,numeric,numeric,text,boolean,uuid,uuid,boolean,numeric,text)'::regprocedure) then
   perform correction_test.ok(replace(actual.prosrc,E'\r','')=replace(replace(saved.prosrc,E'\r',''),'private.require_permission(f,''orders'',''edit'')','private.require_permission(f,''orders'',''approve'')'),'quantity body authorization-only delta');
  elsif actual.prosrc is distinct from saved.prosrc or actual.proacl is distinct from saved.proacl then raise exception 'Unexpected function/security change %.%',saved.nspname,saved.proname;end if;
 end loop;
 perform correction_test.ok((select replace(prosrc,E'\r','') from pg_proc where oid='private.apply_approved_production_correction(uuid,jsonb,uuid)'::regprocedure)=
 (select replace(replace(prosrc,E'\r',''),'private.require_permission(f,''orders'',''edit'')','private.require_permission(f,''orders'',''approve'')') from correction_test.functions where nspname='private' and proname='correct_lean_production'),'M2 attribution worker authorization-only delta');
 perform correction_test.ok(not exists(select 1 from correction_test.security b join pg_namespace n on n.nspname=b.nspname join pg_class c on c.relnamespace=n.oid and c.relname=b.relname where row(c.relacl,c.relrowsecurity,c.relforcerowsecurity) is distinct from row(b.relacl,b.relrowsecurity,b.relforcerowsecurity)),'existing relation ACL/RLS unchanged');
 perform correction_test.ok(not exists(select * from correction_test.policies except select * from pg_policies where schemaname in ('public','private')),'existing RLS policies unchanged');
 perform correction_test.ok(not exists(select 1 from correction_test.historical b join public.production_entry_corrections c using(id) where to_jsonb(c)<>b.data),'historical corrections not backfilled or changed');
 perform correction_test.ok(not exists(select * from correction_test.gates except (select 'maintenance',to_jsonb(g) from private.maintenance_planning_activation g union all select 'recording',to_jsonb(g) from private.production_recording_v3_activation g)),'activation unchanged by migration');
end$$;
select count(*) as inherited_function_contracts from correction_test.functions
 where not(nspname='private' and proname in ('seed_permission_packages','correct_lean_production','correct_production'));
