do $$begin
 perform correction_test.ok(not exists(select 1 from correction_test.historical b join public.production_entry_corrections c using(id) where to_jsonb(c)<>b.data),'pre-policy audit rows still immutable and unchanged');
 perform correction_test.ok(not exists(select 1 from reporting_test.saved b where b.snapshot is distinct from case when b.kind='lean' then (select to_jsonb(s) from public.lean_saved_comparisons s where s.id=b.id) else (select to_jsonb(s) from public.production_loss_estimates s where s.id=b.id) end),'saved Lean/Loss snapshots unchanged');
 perform correction_test.ok(not exists(select 1 from private.production_recording_v3_activation where enabled),'recording remains disabled');
 perform correction_test.ok(not exists(select 1 from private.maintenance_planning_activation where enabled),'Maintenance remains disabled in local fixture');
 perform correction_test.ok(not exists(select 1 from private.production_correction_requests r join public.production_entry_corrections c on c.id=r.correction_id where c.factory_id<>r.factory_id or c.entry_id<>r.entry_id),'approved audit links are factory and entry consistent');
end$$;
select count(*) as final_policy_assertions from correction_test.checks;
