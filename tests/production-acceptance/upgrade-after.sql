do $$declare row record;actual jsonb;x jsonb;f uuid;n bigint;begin
 for row in select * from acceptance_test.historical loop
  actual:=case row.kind when 'entry' then (select to_jsonb(t) from public.production_entries t where id=row.id)
   when 'order' then (select to_jsonb(t) from public.production_orders t where id=row.id)
   when 'source' then (select to_jsonb(t) from public.finished_goods_sources t where id=row.id)
   when 'correction' then (select to_jsonb(t) from public.production_entry_corrections t where id=row.id)
   when 'comparison' then (select to_jsonb(t) from public.lean_saved_comparisons t where id=row.id)
   else (select to_jsonb(t) from public.lean_scrap_events t where id=row.id) end;
  -- Additive nullable/provenance columns are permitted, previous values immutable.
  perform acceptance_test.ok(actual @> row.data,'pre-V3 values preserved: '||row.kind);
 end loop;
 select t.x into x from acceptance_test.legacy t;f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform acceptance_test.ok((select attribution_version is null and effective_occurrence_key is null from public.production_entries where id=(x->>'entry')::uuid),'upgrade never invents a historical dated production period');
 select count(*) into n from private.production_correction_requests;
 perform acceptance_test.ok(public.correct_lean_production(f,x->'payload',(x->>'retry')::uuid)=(x->>'correction')::uuid,'pre-V3 correction retry retains original committed UUID');
 perform acceptance_test.ok((select count(*) from private.production_correction_requests)=n,'upgrade retry creates no retrospective approval');
 perform acceptance_test.ok((select on_hand=3 and reserved=0 from public.finished_goods_balances where factory_id=f),'pre-V3 stock preserved through five V3 migrations');
end$$;
select count(*) as acceptance_assertions from acceptance_test.checks;
