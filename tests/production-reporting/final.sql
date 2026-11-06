do $$declare before_digest text;f uuid;begin
 select (x->>'factory')::uuid into f from reporting_test.context;
 perform set_config('request.jwt.claim.sub',(select x->>'owner' from reporting_test.context),false);
 before_digest:=reporting_test.digest();
 perform public.production_history(f,'{"reporting_version":3}');
 perform public.production_history(f,'{"reporting_version":3,"mode":"summary"}');
 perform reporting_test.ok(before_digest=reporting_test.digest(),'final all-ledger/read-only digest unchanged');
 perform reporting_test.ok(not exists(select 1 from private.production_recording_v3_activation where enabled),'late gate remains disabled after tests');
 perform reporting_test.ok((select count(*)=1 from public.lean_saved_comparisons where factory_id=f and evidence->>'version'='1'),'original saved Lean still present');
 perform reporting_test.ok((select count(*)=1 from public.production_loss_estimates where factory_id=f and result->>'fixture'='saved reviewed evidence'),'original saved Loss still present');
 perform reporting_test.ok(not exists(select 1 from reporting_test.saved b where b.snapshot is distinct from case when b.kind='lean' then (select to_jsonb(s) from public.lean_saved_comparisons s where s.id=b.id) else (select to_jsonb(s) from public.production_loss_estimates s where s.id=b.id) end),'saved evidence bytes unchanged after correction and all readers');
end$$;
select count(*) as final_reporting_assertions from reporting_test.checks;
