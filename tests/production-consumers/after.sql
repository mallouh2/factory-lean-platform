do $$declare saved record;a record;expected text;begin
 for saved in select * from m3c_test.functions loop
  if (saved.nspname='private' and saved.proname in ('lean_read','production_reporting_history')) then continue;end if;
  select p.prosrc,p.proacl into a from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=case when saved.nspname='public' and saved.proname='quality_read' then 'private' else saved.nspname end
  and p.proname=case when saved.nspname='public' and saved.proname='quality_read' then 'quality_read_before_m3c' when saved.nspname='private' and saved.proname='lean_command' then 'lean_command_before_m3c' else saved.proname end and pg_get_function_identity_arguments(p.oid)=saved.args;
  expected:=saved.prosrc;
  if saved.nspname='private' and saved.proname='lean_command' then
   -- Only the separately approved baseline bounds and current-review filter.
   expected:=replace(expected,'select min(o.occurred_at),max(greatest(o.ended_at,o.occurred_at)) into baseline_start,baseline_end',
    'select min(case when o.time_precision=''SHIFT_PERIOD'' then o.period_start else o.occurred_at end),max(case when o.time_precision=''SHIFT_PERIOD'' then o.period_end else greatest(o.ended_at,o.occurred_at) end) into baseline_start,baseline_end');
   expected:=replace(expected,'and o.product_id=(p->>''product_id'')::uuid;','and o.product_id=(p->>''product_id'')::uuid and (o.mechanism<>''scrap'' or o.review_current);');
   if expected=saved.prosrc then raise exception 'Approved baseline replacement not verified';end if;
  end if;
  if replace(a.prosrc,E'\r','') is distinct from replace(expected,E'\r','') then raise exception 'Changed existing body %.%',saved.nspname,saved.proname;end if;
  if saved.proname not in ('quality_read','lean_command') and a.proacl is distinct from saved.proacl then raise exception 'Changed grant %.%',saved.nspname,saved.proname;end if;
 end loop;
 perform m3c_test.ok(not exists(select 1 from m3c_test.security b join pg_namespace n on n.nspname=b.nspname join pg_class c on c.relnamespace=n.oid and c.relname=b.relname where row(c.relacl,c.relrowsecurity,c.relforcerowsecurity) is distinct from row(b.relacl,b.relrowsecurity,b.relforcerowsecurity)),'all table grants/RLS unchanged');
 perform m3c_test.ok(not exists(select * from m3c_test.policies except select * from pg_policies where schemaname in ('public','private')),'existing policies unchanged');
 perform m3c_test.ok(not exists(select * from m3c_test.gates except (select 'maintenance',to_jsonb(g) from private.maintenance_planning_activation g union all select 'recording',to_jsonb(g) from private.production_recording_v3_activation g)),'migration preserves complete activation rows before any fixture gate tests');
 perform m3c_test.ok(not exists(select 1 from m3c_test.prior_rows b where b.data is distinct from case b.kind when 'entry' then (select to_jsonb(e) from public.production_entries e where e.id=b.id) when 'observation' then (select to_jsonb(e) from public.lean_scrap_events e where e.id=b.id) else (select to_jsonb(e) from public.production_entry_corrections e where e.id=b.id) end),'migration preserves existing production/observation/correction rows');
end$$;
select count(*) as preserved_function_contracts from m3c_test.functions where not(nspname='private' and proname in ('lean_read','production_reporting_history'));
