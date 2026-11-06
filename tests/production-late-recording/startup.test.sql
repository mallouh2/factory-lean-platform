begin;
create function late_test.startup_delay() returns trigger language plpgsql as $$begin
 if new.notes='M2 startup rollback' and old.original_scrap_kg is null and new.original_scrap_kg is not null then
 perform pg_sleep(greatest(0,extract(epoch from ((select ends_at from private.production_shift_occurrences where factory_id=new.factory_id and occurrence_key=new.original_occurrence_key)-clock_timestamp())))+.2);
 end if;return new;end$$;
create trigger zzz_startup_rollback after update on public.production_entries for each row execute function late_test.startup_delay();
do $$declare x jsonb;f uuid;p jsonb;s uuid:=gen_random_uuid();r uuid:=gen_random_uuid();receipt jsonb;again jsonb;begin
 x:=late_test.new_context('m2-startup');f:=(x->>'factory')::uuid;
 update private.production_recording_v3_activation set enabled=true,schema_contract_version=3 where factory_id=f;
 p:=late_test.payload(x,1)||jsonb_build_object('startup_id',s,'startup_at',(select actual_start from public.production_orders where id=(x->>'item')::uuid),'startup_kg',.25,'scrap_kg',.25);
 receipt:=public.record_lean_production(f,p,r);
 update public.products set unit_weight_kg=1 where id=(x->>'product')::uuid;
 again:=public.record_lean_production(f,p,r);
 perform late_test.ok(receipt-'replayed'=again-'replayed','startup replay returns immutable configuration snapshot');
 perform late_test.ok((select count(*)=1 from public.lean_startups where factory_id=f),'startup UUID replay creates one startup');
 perform late_test.ok((select weight_kg_per_unit=.5 and original_scrap_kg=.25 from public.production_entries where id=(receipt->>'id')::uuid),'replay never refreshes original weight/KG');
 x:=late_test.new_context('m2-startup-expiry',6);f:=(x->>'factory')::uuid;s:=gen_random_uuid();r:=gen_random_uuid();
 update private.production_recording_v3_activation set enabled=true,schema_contract_version=3 where factory_id=f;
 p:=late_test.payload(x,1)||jsonb_build_object('startup_id',s,'startup_at',(select actual_start from public.production_orders where id=(x->>'item')::uuid),'startup_kg',.25,'scrap_kg',.25,'notes','M2 startup rollback');
 perform late_test.fails(format('select public.record_lean_production(%L,%L,%L)',f,p,r),'recording_shift_expired');
 perform late_test.ok(not exists(select 1 from public.lean_startups where factory_id=f),'expiry rolls startup back');
 perform late_test.ok(not exists(select 1 from public.production_entries where factory_id=f) and not exists(select 1 from public.finished_goods_sources where factory_id=f),'expiry rolls entry/source back');
 perform late_test.ok(public.production_recording_request_status(f,r)->>'outcome'='UNKNOWN','rolled-back UUID honestly UNKNOWN');
end$$;
select count(*) as total_assertions from late_test.checks;
rollback;
