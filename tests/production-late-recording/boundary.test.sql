-- Real clock and protected execution; no historical timestamp edits.
do $$declare x jsonb;f uuid;p jsonb;first_receipt jsonb;receipt jsonb;first_shift uuid;second_shift uuid;finish_at time;
 retry uuid:=gen_random_uuid();cp jsonb;begin
 x:=late_test.new_context('m2-two-shifts',1,false);f:=(x->>'factory')::uuid;first_shift:=(x->>'shift')::uuid;
 select end_time into finish_at from public.production_shifts where id=first_shift;
 second_shift:=public.configure_production_shift(f,'Second dated shift','الوردية التالية',finish_at,finish_at+interval '1 hour');
 first_receipt:=public.record_lean_production(f,late_test.payload(x,1),gen_random_uuid());
 perform pg_sleep(1.1);
 perform public.finish_product_item(f,(x->>'item')::uuid);
 update private.production_recording_v3_activation set enabled=true,schema_contract_version=3 where factory_id=f;
 p:=jsonb_set(late_test.payload(x,2),'{recording_context,current_shift_quantity_confirmed}','false');
 perform late_test.fails(format('select public.record_lean_production(%L,%L,%L)',f,p,gen_random_uuid()),'recording_shift_declaration');
 p:=jsonb_set(p,'{recording_context,current_shift_quantity_confirmed}','true');
 receipt:=public.record_lean_production(f,p,retry);
 perform late_test.ok(receipt->>'occurrence_key'<>first_receipt->>'occurrence_key','spanning execution has separate dated occurrences');
 perform late_test.ok((select original_period_start=(select starts_at from private.production_shift_occurrences where factory_id=f and occurrence_key=receipt->>'occurrence_key') and attribution_declaration from public.production_entries where id=(receipt->>'id')::uuid),'current-shift period and declaration persisted');
 cp:=jsonb_build_object('entry',receipt->>'id','good',2,'discarded_quantity',0,'scrap_kg',0,'startup_kg',0,'reason','Verified dated attribution correction',
 'change_shift',true,'shift',first_shift,'corrected_occurrence_key',first_receipt->>'occurrence_key','unfinished',0,'remaining_work','');
 perform public.correct_lean_production(f,cp,gen_random_uuid());
 perform late_test.ok((select original_occurrence_key=receipt->>'occurrence_key' and effective_occurrence_key=first_receipt->>'occurrence_key' from public.production_entries where id=(receipt->>'id')::uuid),'dated correction changes effective only');
 perform late_test.ok((select attribution_changed and previous_occurrence_key=receipt->>'occurrence_key' and corrected_occurrence_key=first_receipt->>'occurrence_key' from public.production_entry_corrections where entry_id=(receipt->>'id')::uuid),'dated correction stores before/after audit');
 perform late_test.ok((select origin_occurrence_key=receipt->>'occurrence_key' and shift_name='Second dated shift' from public.finished_goods_sources where entry_id=(receipt->>'id')::uuid),'source keeps original dated provenance after correction');
 perform late_test.ok(public.production_recording_request_status(f,retry)->'receipt'=receipt,'dated correction cannot rewrite original receipt');
 perform late_test.ok((select on_hand=3 from public.finished_goods_balances where factory_id=f),'dated correction creates no extra Good');
 update private.production_recording_v3_activation set enabled=false,schema_contract_version=0 where factory_id=f;
end$$;
select count(*) as total_assertions from late_test.checks;
