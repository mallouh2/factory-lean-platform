-- 5,001 genuine local ledger entries; no disabled constraints/triggers.
do $$declare x jsonb;f uuid;e public.production_entries;j jsonb;n integer;h jsonb;q jsonb:='{"reporting_version":3,"page_size":100}';c jsonb;seen uuid[]:='{}';r jsonb;begin
 select t.x into x from reporting_test.context t;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 select * into e from public.production_entries where factory_id=f and order_id=(x->>'item')::uuid order by created_at desc limit 1;
 j:=to_jsonb(e)||jsonb_build_object('attribution_version',null,'recording_kind',null,'execution_key',null,'execution_started_at',null,'execution_finished_at',null,
 'original_occurrence_key',null,'effective_occurrence_key',null,'original_period_start',null,'original_period_end',null,'effective_period_start',null,'effective_period_end',null,'time_precision',null,
 'request_payload_version',null,'request_payload',null,'request_receipt',null,'accepted_at',null,
 'good_quantity',0,'effective_good',0,'produced',0,'scrap_quantity',0,'effective_scrap',0,'rejected',0,
 'unfinished_quantity',0,'effective_unfinished',0,'original_scrap_kg',.000000001,'effective_scrap_kg',.000000001,'original_startup_kg',0,'effective_startup_kg',0,'produced_weight_kg',0,'lean_startup_id',null);
 for n in 1..5001 loop
  insert into public.production_entries select (jsonb_populate_record(null::public.production_entries,j||jsonb_build_object('id',gen_random_uuid(),'request_id',gen_random_uuid(),'created_at',clock_timestamp()))).*;
 end loop;
 set constraints all immediate;set constraints all deferred;
 q:=q||jsonb_build_object('to_at',clock_timestamp());
 h:=public.production_history(f,q||'{"time_basis":"production","mode":"summary"}');
 perform reporting_test.ok((h->>'unknown_attribution_records')::int=5002 and h->>'allocation_complete'='false','5,001 Scrap-only plus one genuine legacy Good entry explicitly surfaced');
 perform reporting_test.ok(exists(select 1 from jsonb_array_elements(h->'rows') v where v->>'occurrence_key' is null and v->>'good' is null and (v->>'unallocated_good')::numeric=.000001)
  and exists(select 1 from jsonb_array_elements(h->'rows') v where v->>'occurrence_key' is null and v->>'scrap_kg' is null and (v->>'unallocated_scrap_kg')::numeric=.000005001),'unknown quantities stay separate by Product line unit without invented allocation');
 c:=null;n:=0;
 loop
  h:=public.production_history(f,q||case when c is null then '{}' else jsonb_build_object('cursor',c) end);
  for r in select * from jsonb_array_elements(h->'rows') loop
   if (r->>'id')::uuid=any(seen) then raise exception 'Duplicate page entry';end if;seen:=array_append(seen,(r->>'id')::uuid);
  end loop;n:=n+1;exit when (h->>'complete')::boolean;c:=h->'next_cursor';
 end loop;
 perform reporting_test.ok(cardinality(seen)=(h->>'total')::int and cardinality(seen)>5001 and n>50,'complete large-history traversal');
 perform reporting_test.ok((select bool_and(on_hand>=reserved and on_hand>=0) from public.finished_goods_balances where factory_id=f),'reader dataset stock remains conserved');
end$$;
analyze public.production_entries;
explain(analyze,buffers) select id from public.production_entries where factory_id=(select (x->>'factory')::uuid from reporting_test.context) and created_at>=statement_timestamp()-interval '30 days' order by created_at,id limit 100;
explain(analyze,buffers) select public.production_history((select (x->>'factory')::uuid from reporting_test.context),'{"reporting_version":3,"page_size":100}');
select count(*) as cumulative_assertions from reporting_test.checks;
