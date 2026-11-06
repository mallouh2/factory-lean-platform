do $$begin
 perform acceptance_test.ok(not exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0),'all disposable V3 gates end FALSE/schema0');
 perform acceptance_test.ok(not exists(select 1 from private.maintenance_planning_activation where enabled),'Maintenance gate unchanged FALSE');
 perform acceptance_test.ok(not exists(select 1 from public.finished_goods_balances where on_hand<reserved or on_hand<0),'all factory balances conserve stock and reservations');
 perform acceptance_test.ok(to_regprocedure('public.factory_export_page(uuid,text,integer)') is null,'deferred Export Reader not installed');
end$$;
select count(*) as acceptance_assertions from acceptance_test.checks;
