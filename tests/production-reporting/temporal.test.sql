-- Fixed fictional frozen facts test the reader, not historical writer admission.
-- All production/source/KG/tenant constraints and operational triggers stay enabled.
create function reporting_test.historical(x jsonb,day date,qty numeric,kg numeric) returns uuid language plpgsql as $$
declare f uuid:=(x->>'factory')::uuid;rev uuid;shift uuid:=(x->>'shift')::uuid;k text;origin public.production_entries;
 j jsonb;id uuid:=gen_random_uuid();request uuid:=gen_random_uuid();a timestamptz;b timestamptz;recorded timestamptz;begin
 a:=(day::timestamp at time zone 'UTC')+interval '22 hours';b:=a+interval '8 hours';recorded:=a+interval '3 hours';
 select r.id into rev from private.production_shift_schedule_revisions r where r.factory_id=f order by r.revision_no limit 1;
 k:=encode(sha256(convert_to(f::text||day::text,'UTF8')),'hex');
 insert into private.production_shift_occurrences(factory_id,occurrence_key,schedule_revision_id,shift_id,business_date,timezone,name,name_ar,starts_at,ends_at)
 values(f,k,rev,shift,day,'UTC','Fictional historical night','وردية ليلية للاختبار',a,b) on conflict do nothing;
 select * into origin from public.production_entries where factory_id=f and attribution_version=1 order by created_at limit 1;
 j:=to_jsonb(origin)||jsonb_build_object('id',id,'request_id',request,'created_at',recorded,'accepted_at',recorded,
  'recording_kind','ACTIVE_ORDINARY','execution_started_at',a,'execution_finished_at',null,
  'original_occurrence_key',k,'effective_occurrence_key',k,'original_period_start',a,'original_period_end',recorded,
  'effective_period_start',a,'effective_period_end',recorded,
  'good_quantity',qty,'effective_good',qty,'produced',qty,'rejected',0,'scrap_quantity',0,'effective_scrap',0,
  'unfinished_quantity',0,'effective_unfinished',0,'original_scrap_kg',kg,'effective_scrap_kg',kg,'original_startup_kg',0,'effective_startup_kg',0,
  'produced_weight_kg',qty*origin.weight_kg_per_unit,'lean_startup_id',null,
  'request_payload',jsonb_build_object('actor',x->>'owner','factory',f),
  'request_receipt',jsonb_build_object('entry_id',id,'request_id',request,'outcome','COMMITTED','accepted_at',recorded));
 insert into public.production_entries select (jsonb_populate_record(null::public.production_entries,j)).*;
 update public.production_orders set produced_quantity=produced_quantity+qty where production_orders.id=origin.order_id;
 return id;
end$$;
do $$declare x jsonb;f uuid;first uuid;second uuid;q jsonb;h jsonb;s jsonb;row jsonb;obs uuid:=gen_random_uuid();before_digest text;z jsonb;begin
 select t.x into x from reporting_test.context t;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 first:=reporting_test.historical(x,'2026-01-10',10.1234567890123456789,.1234567890123456789);
 second:=reporting_test.historical(x,'2026-01-11',2,.05);
 set constraints all immediate;set constraints all deferred;
 q:='{"reporting_version":3,"time_basis":"production","from":"2026-01-10","to":"2026-01-10"}';
 h:=public.production_history(f,q);s:=public.production_history(f,q||'{"mode":"summary"}');
 perform reporting_test.ok(h->>'total'='1','business-date includes overnight once');
 perform reporting_test.ok(h#>>'{rows,0,effective_occurrence,business_date}'='2026-01-10' and (h#>>'{rows,0,recorded_at}')::date='2026-01-11','submission date distinct from frozen night date');
 perform reporting_test.ok((h#>>'{rows,0,good}')::numeric=10.1234567890123456789,'Good decimal precision');
 perform reporting_test.ok((h#>>'{rows,0,scrap_kg}')::numeric=.1234567890123456789,'Scrap KG decimal precision');
 perform reporting_test.ok(s#>>'{rows,0,allocation_complete}'='true','whole overnight business occurrence is allocated');
 h:=public.production_history(f,q||'{"to":"2026-01-11","mode":"summary"}');
 perform reporting_test.ok(h->>'total'='2','recurring shift on two dates remains two groups');
 h:=public.production_history(f,'{"reporting_version":3,"time_basis":"recorded","from":"2026-01-10","to":"2026-01-10"}');
 perform reporting_test.ok(h->>'total'='0','recorded date does not backdate late submission');
 h:=public.production_history(f,'{"reporting_version":3,"time_basis":"production","mode":"summary","from_at":"2026-01-10T23:00:00Z","to_at":"2026-01-10T23:30:00Z"}');
 perform reporting_test.ok(h#>>'{rows,0,good}' is null and h#>>'{rows,0,allocation_complete}'='false','partial period not prorated or zeroed');
 perform reporting_test.ok((h#>>'{rows,0,unallocated_good}')::numeric=10.1234567890123456789,'partial declared quantity visible separately');
 select * into row from jsonb_array_elements(public.production_history(f,q)->'rows') limit 1;
 insert into public.lean_scrap_events(id,factory_id,entry_id,line_id,product_id,occurred_at,observation,response,created_by,time_precision,occurrence_key,period_start,period_end)
 select obs,f,e.id,e.line_id,(x->>'product')::uuid,null,'Period-only fixture','Await independent review',(x->>'owner')::uuid,'SHIFT_PERIOD',e.effective_occurrence_key,e.effective_period_start,e.effective_period_end from public.production_entries e where e.id=first;
 perform reporting_test.ok((select occurred_at is null and time_precision='SHIFT_PERIOD' and reviewed_at is null from public.lean_scrap_events where id=obs),'period relationship stores no fictional exact time or approval');
 perform reporting_test.fails(format('update public.lean_scrap_events set period_end=period_end+interval ''1 second'' where id=%L',obs),'23514');
 perform reporting_test.fails(format('update public.lean_scrap_events set occurred_at=clock_timestamp() where id=%L',obs),'23514');
 perform reporting_test.fails(format('insert into public.lean_scrap_events(id,factory_id,entry_id,line_id,product_id,observation,response,created_by,time_precision,occurrence_key,period_start,period_end) select gen_random_uuid(),factory_id,id,line_id,%L,''Invalid period fixture'',''Invalid period response'',created_by,''SHIFT_PERIOD'',effective_occurrence_key,effective_period_start-interval ''1 second'',effective_period_end from public.production_entries where id=%L',x->>'product',second),'23514');
 h:=public.production_history(f,q);
 perform reporting_test.ok(h#>>'{rows,0,observation,precision}'='SHIFT_PERIOD' and h#>>'{rows,0,observation,occurred_at}' is null,'read exposes period-only observation honestly');
 perform public.source_stock_command(f,'correct',jsonb_build_object('entry',first,'good',9.1234567890123456789,'discarded_quantity',0,
  'scrap_kg',.1234567890123456789,'startup_kg',0,'reason','Historical fixture quantity correction','unfinished',0,'remaining_work',''),
  '[{"source_id":null,"quantity":"1"}]',gen_random_uuid());
 h:=public.production_history(f,q);
 perform reporting_test.ok((h#>>'{rows,0,good}')::numeric=9.1234567890123456789 and (h#>>'{rows,0,original_good}')::numeric=10.1234567890123456789,'historical correction changes effective only');
 perform reporting_test.ok((select period_end=timestamp '2026-01-11 01:00:00' at time zone 'UTC' from public.lean_scrap_events where id=obs),'observation retains its frozen evidence relationship after correction');
 -- Two separate capable lines/jobs with zero quantity records use the existing M1 work reader.
 z:=late_test.new_context('m3a-zero',60,false);
 perform reporting_test.ok(public.production_shift_work((z->>'factory')::uuid)->>'total'='1','zero-entry active execution remains visible as work');
 perform reporting_test.ok(public.production_history((z->>'factory')::uuid,'{"reporting_version":3}')->>'total'='0','zero-entry work does not invent a quantity row');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
end$$;
select count(*) as cumulative_assertions from reporting_test.checks;
