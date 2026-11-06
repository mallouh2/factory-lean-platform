-- Fixed fictional frozen facts test the reader, not historical writer admission.
-- All production/source/KG/tenant constraints and operational triggers stay enabled.
create function m3c_test.historical(x jsonb,day date,qty numeric,kg numeric,zone text default 'Asia/Riyadh') returns uuid language plpgsql as $$
declare f uuid:=(x->>'factory')::uuid;rev uuid;shift uuid:=(x->>'shift')::uuid;k text;origin public.production_entries;
 j jsonb;id uuid:=gen_random_uuid();request uuid:=gen_random_uuid();a timestamptz;b timestamptz;recorded timestamptz;begin
 a:=((day::timestamp+interval '22 hours') at time zone zone);b:=a+interval '8 hours';recorded:=a+interval '3 hours';
 select r.id into rev from private.production_shift_schedule_revisions r where r.factory_id=f order by r.revision_no limit 1;
 k:=encode(sha256(convert_to(f::text||day::text,'UTF8')),'hex');
 insert into private.production_shift_occurrences(factory_id,occurrence_key,schedule_revision_id,shift_id,business_date,timezone,name,name_ar,starts_at,ends_at)
 values(f,k,rev,shift,day,zone,'Fictional historical night','وردية ليلية للاختبار',a,b) on conflict do nothing;
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

do $$declare x jsonb;f uuid;e uuid;obs uuid:=gen_random_uuid();h jsonb;s jsonb;q jsonb;before_digest text;begin
 select t.x into x from m3c_test.context t;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 e:=m3c_test.historical(x,'2026-02-10',2.1234567890123456789,.1234567890123456789);
 set constraints all immediate;set constraints all deferred;
 perform public.lean_command(f,gen_random_uuid(),'scrap_observation',jsonb_build_object('id',obs,'entry_id',e,'time_precision','SHIFT_PERIOD','preliminary_cause_id',x->>'cause','observation','Fictional overnight reader evidence','response','Keep physical period distinct from submission'));
 perform public.lean_command(f,gen_random_uuid(),'scrap_review',jsonb_build_object('id',obs,'approved_cause_id',x->>'cause','note','Reviewed constrained period fixture','expected_revision',1));
 h:=public.production_history(f,jsonb_build_object('reporting_version',3,'entry',e,'time_basis','production','from','2026-02-10','to','2026-02-10'));
 perform m3c_test.ok(h#>>'{rows,0,effective_occurrence,business_date}'='2026-02-10' and h#>>'{rows,0,effective_occurrence,timezone}'='Asia/Riyadh','frozen factory-local night business date retained');
 perform m3c_test.ok((h#>>'{rows,0,recorded_at}')::timestamptz at time zone 'Asia/Riyadh'=timestamp '2026-02-11 01:00','submission on next local date does not move production date');
 perform m3c_test.ok(h#>>'{rows,0,scrap_kg}'='0.1234567890123456789','period history exact KG transport');
 q:=jsonb_build_object('mode','analysis_occurrences','from','2026-02-10T22:00:00+03:00','to','2026-02-11T01:00:00+03:00');
 h:=public.lean_read(f,q);
 perform m3c_test.ok(h->>'total'='1' and h#>>'{rows,0,allocation_status}'='CONTAINED' and h#>>'{rows,0,occurred_at}' is null,'whole reviewed overnight period reaches existing Lean reader');
 perform m3c_test.ok((h#>>'{rows,0,scrap_kg}')::numeric=.1234567890123456789 and h#>>'{rows,0,evidence_version}'='2','new Lean provenance and exact numeric preserved in SQL');
 h:=public.lean_read(f,q||'{"from":"2026-02-10T23:00:00+03:00","to":"2026-02-11T00:00:00+03:00"}');
 perform m3c_test.ok(h->>'total'='1' and h#>>'{rows,0,allocation_status}'='PARTIAL' and h#>>'{rows,0,scrap_kg}' is null,'partial period visible with unknown allocated Scrap, never zero or prorated');
 h:=public.lean_read(f,q||'{"mode":"problems","from":"2026-02-10T23:00:00+03:00","to":"2026-02-11T00:00:00+03:00"}');
 perform m3c_test.ok(h->>'total'='1' and h#>>'{rows,0,frequency}' is null and h#>>'{rows,0,scrap_kg}' is null,'partial period problem aggregate cannot fabricate frequency/KG');
 h:=public.lean_read(f,q||'{"mode":"entries"}');
 perform m3c_test.ok(h->>'total'='1' and h#>>'{rows,0,machine_ids}'='[]' and h#>>'{rows,0,allocation_status}'='CONTAINED','historical line evidence does not infer present machine ownership');
 before_digest:=reporting_test.digest();
 perform public.lean_read(f,q);perform public.quality_read(f,jsonb_build_object('mode','board','entry',e));
 perform m3c_test.ok(reporting_test.digest()=before_digest,'overnight consumer reads have no side effects');
 perform m3c_test.fails(format('update public.lean_scrap_events set period_start=period_start+interval ''1 minute'' where id=%L',obs),'23514');
end$$;
select count(*) as cumulative_consumer_assertions from m3c_test.checks;

do $$declare x jsonb;f uuid;e uuid;h jsonb;v jsonb;begin
 select t.x into x from m3c_test.context t;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 e:=(public.record_lean_production(f,(late_test.payload(x,1)-'recording_context')||'{"scrap_kg":0}',gen_random_uuid())->>'id')::uuid;
 h:=public.lean_read(f,jsonb_build_object('mode','entries','from',clock_timestamp()-interval '1 day','to',clock_timestamp()));
 select value into v from jsonb_array_elements(h->'rows') where value->>'id'=e::text;
 perform m3c_test.ok(v->>'allocation_status'='UNKNOWN' and v->>'production_precision'='UNKNOWN' and (v->>'effective_scrap_kg')::numeric=0,'legacy actual recording remains unknown in production time, with genuine zero KG distinct');
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''scrap_observation'',%L)',f,gen_random_uuid(),jsonb_build_object('id',gen_random_uuid(),'entry_id',e,'time_precision','SHIFT_PERIOD','preliminary_cause_id',x->>'cause','observation','No historical period can be guessed','response','Keep unknown evidence explicit')),'22023');
end$$;
