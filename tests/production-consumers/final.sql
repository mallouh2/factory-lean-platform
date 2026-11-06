do $$begin
 perform m3c_test.ok(not exists(select 1 from m3c_test.saved b where b.data is distinct from case b.kind when 'lean' then (select to_jsonb(s) from public.lean_saved_comparisons s where id=b.id) else (select to_jsonb(s) from public.production_loss_estimates s where id=b.id) end),'historical approved Lean/Loss snapshots byte-equivalent');
 perform m3c_test.ok(not exists(select kind,data-'schema_contract_version' from m3c_test.gates except (select 'maintenance',to_jsonb(g) from private.maintenance_planning_activation g union all select 'recording',to_jsonb(g)-'schema_contract_version' from private.production_recording_v3_activation g)),'existing activation state retained; isolated M2 readiness fixtures may clean schema3 back to0');
 perform m3c_test.ok(not exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0),'all local V3 gates FALSE/schema0');
 perform m3c_test.ok(not exists(select 1 from public.finished_goods_balances where on_hand<reserved or on_hand<0),'stock conservation and commitments intact');
end$$;
select count(*) as final_consumer_assertions from m3c_test.checks;
