create table m3c_test.context(x jsonb);
create function m3c_test.operational() returns text language plpgsql stable as $$
declare tab text;part text;result text:='';begin
 foreach tab in array array['production_orders','production_entries','production_entry_corrections','finished_goods_balances','finished_goods_sources','finished_goods_movements','finished_goods_entry_receipts','finished_goods_reservations','finished_goods_source_reservations','sales_incoming_allocations','quality_rejections','quality_notifications','unfinished_lots','unfinished_movements','lean_scrap_events','lean_saved_comparisons','production_loss_estimates','downtime_events','production_transfers','maintenance_schedules'] loop
  execute format('select md5(coalesce(string_agg(to_jsonb(t)::text,''|'' order by to_jsonb(t)::text),'''')) from public.%I t',tab) into part;result:=result||tab||part;
 end loop;return md5(result);end$$;
create function m3c_test.payload(e uuid,g numeric,kg numeric) returns jsonb language sql stable as $$
 select jsonb_build_object('entry',e,'good',g::text,'discarded_quantity','0','scrap_kg',kg::text,'unfinished','0','reason','Verified measurement correction',
 'expected_revision',(select count(*) from public.production_entry_corrections where entry_id=e))
$$;
do $$declare x jsonb;f uuid;e uuid;obs uuid:=gen_random_uuid();cause uuid:=gen_random_uuid();p jsonb;r uuid:=gen_random_uuid();pending jsonb;h jsonb;row jsonb;before_digest text;stock numeric;decision jsonb;prior_review jsonb;before_saved jsonb;gate jsonb;late_entry uuid;begin
 x:=late_test.new_context('m3c-policy',3600,false);f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform public.lean_command(f,gen_random_uuid(),'cause',jsonb_build_object('id',cause,'name','Controlled consumer cause','name_ar','سبب اختبار التكامل'));
 perform public.lean_command(f,gen_random_uuid(),'standard',jsonb_build_object('id',gen_random_uuid(),'line_id',x->>'line','product_id',x->>'product','running_percent',1,'startup_kg',0,'expected_revision',0));
 e:=(public.record_lean_production(f,late_test.payload(x,10)||'{"scrap_kg":1}',gen_random_uuid())->>'id')::uuid;
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'worker')::uuid,'orders','view'),(f,(x->>'worker')::uuid,'orders','edit');
 p:=jsonb_build_object('id',obs,'entry_id',e,'time_precision','SHIFT_PERIOD','preliminary_cause_id',cause,'observation','Measured Scrap in the supported shift','response','Held the evidence for review');
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 before_digest:=reporting_test.digest();
 h:=public.lean_command(f,r,'scrap_observation',p);
 perform m3c_test.ok(h->>'id'=obs::text,'period observation uses existing protected command');
 perform m3c_test.ok(public.lean_command(f,r,'scrap_observation',p)=h,'period observation exact UUID retry');
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''scrap_observation'',%L)',f,r,p||'{"response":"Another intent"}'),'40001');
 perform m3c_test.ok((select s.occurred_at is null and s.occurrence_key=pe.effective_occurrence_key and s.period_start=pe.effective_period_start and s.period_end=pe.effective_period_end from public.lean_scrap_events s join public.production_entries pe on pe.id=s.entry_id where s.id=obs),'server copies authoritative period; no fabricated instant');
 perform m3c_test.ok((select effective_good=10 and effective_scrap_kg=1 from public.production_entries where id=e),'observation does not change production quantities');
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''scrap_observation'',%L)',f,gen_random_uuid(),p||jsonb_build_object('id',gen_random_uuid(),'occurred_at',clock_timestamp())),'22023');
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''scrap_observation'',%L)',f,gen_random_uuid(),p||jsonb_build_object('id',gen_random_uuid(),'downtime_id',gen_random_uuid())),'22023');
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''scrap_observation'',%L)',f,gen_random_uuid(),p||jsonb_build_object('id',gen_random_uuid(),'period_start',clock_timestamp())),'22023');
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''scrap_review'',%L)',f,gen_random_uuid(),jsonb_build_object('id',obs,'approved_cause_id',cause,'expected_revision',1)),'42501');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 h:=public.production_history(f,jsonb_build_object('reporting_version',3,'entry',e,'to_at',clock_timestamp()+interval '.1 seconds'));
 perform m3c_test.ok(h#>>'{rows,0,observation,status}'='PENDING' and h#>>'{rows,0,lean_evidence,reviewed_scrap_kg}' is null,'pending Scrap review excluded from reviewed quantities');
 perform m3c_test.ok(not exists(select 1 from private.lean_occurrences where factory_id=f and mechanism='scrap'),'pending review creates no qualified Lean occurrence');
 perform public.lean_command(f,gen_random_uuid(),'scrap_review',jsonb_build_object('id',obs,'approved_cause_id',cause,'note','Checked against physical evidence','expected_revision',1));
 perform m3c_test.ok(exists(select 1 from private.lean_occurrences where factory_id=f and review_current and scrap_kg=1 and occurred_at is null),'reviewed period enters existing Lean projection with null exact time');
 select to_jsonb(s) into prior_review from public.lean_scrap_events s where id=obs;
 select on_hand into stock from public.finished_goods_balances where factory_id=f;
 perform set_config('request.jwt.claim.sub',x->>'worker',false);before_digest:=m3c_test.operational();
 pending:=public.production_correction_command(f,'submit',m3c_test.payload(e,11,2),gen_random_uuid());
 perform m3c_test.ok(pending->>'status'='PENDING' and m3c_test.operational()=before_digest,'pending correction changes no official/stock/WIP/Quality/Lean evidence');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 h:=public.quality_read(f,jsonb_build_object('mode','board','entry',e));
 perform m3c_test.ok(h#>>'{rows,0,current_good}'='10' and h#>>'{rows,0,scrap,production_scrap_kg}'='1','Quality ignores pending proposed quantities');
 perform public.production_correction_command(f,'approve',jsonb_build_object('id',pending->>'id'),gen_random_uuid());
 perform m3c_test.ok((select effective_good=11 and good_quantity=10 and effective_scrap_kg=2 and original_scrap_kg=1 from public.production_entries where id=e),'approved correction changes effective not original values');
 perform m3c_test.ok((select on_hand=stock+1 from public.finished_goods_balances where factory_id=f),'approved Good credit once');
 perform m3c_test.ok(prior_review=(select to_jsonb(s) from public.lean_scrap_events s where id=obs),'quantity approval does not rewrite earlier Scrap review decision');
 h:=public.production_history(f,jsonb_build_object('reporting_version',3,'entry',e,'to_at',clock_timestamp()+interval '.1 seconds'));
 perform m3c_test.ok(h#>>'{rows,0,scrap_kg}'='2' and h#>>'{rows,0,observation,status}'='REVIEWED' and h#>>'{rows,0,observation,review_current}'='false' and h#>>'{rows,0,lean_evidence,reviewed_scrap_kg}' is null,'operational correction official while reviewed evidence is stale');
 h:=public.quality_read(f,jsonb_build_object('mode','board','entry',e));
 perform m3c_test.ok(h#>>'{rows,0,scrap,production_scrap_kg}'='2' and h#>>'{rows,0,scrap_evidence,status}'='EVIDENCE_CHANGED_AFTER_REVIEW','Quality displays current KG and separate historical review status');
 perform m3c_test.ok(h#>>'{rows,0,production_attribution,precision}'='SHIFT_PERIOD','Quality has authoritative production provenance');
 h:=public.lean_read(f,'{"mode":"pending"}');
 perform m3c_test.ok(h->>'total'='1' and h#>>'{rows,0,review_current}'='false','existing review queue exposes changed evidence for another authorized review');
 perform m3c_test.ok((select scrap_kg is null and not review_current from private.lean_occurrences where factory_id=f and mechanism='scrap'),'new corrected Scrap never autoqualifies as reviewed Lean input');
 perform public.lean_command(f,gen_random_uuid(),'scrap_review',jsonb_build_object('id',obs,'approved_cause_id',cause,'note','Reviewed corrected official quantities','expected_revision',2));
 perform m3c_test.ok((select scrap_kg=2 and review_current from private.lean_occurrences where factory_id=f and mechanism='scrap'),'existing authorized re-review admits current official quantity');
 perform set_config('request.jwt.claim.sub',x->>'worker',false);before_digest:=m3c_test.operational();
 pending:=public.production_correction_command(f,'submit',m3c_test.payload(e,11,3),gen_random_uuid());
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform public.production_correction_command(f,'reject',jsonb_build_object('id',pending->>'id','reason','Measurement not supported by evidence'),gen_random_uuid());
 perform m3c_test.ok(m3c_test.operational()=before_digest,'rejected correction affects no operational/approved evidence');
 h:=public.production_correction_command(f,'submit',m3c_test.payload(e,11,2.1234567890123456789),gen_random_uuid());
 perform m3c_test.ok(h->>'status'='APPROVED' and h->>'requested_by'=h->>'reviewed_by','authorized self approval retained');
 perform m3c_test.ok((select effective_scrap_kg=2.1234567890123456789 from public.production_entries where id=e),'exact corrected Scrap KG retained');
 perform m3c_test.ok(not private.production_scrap_review_current(f,e,(select reviewed_at from public.lean_scrap_events where id=obs)),'sequential self correction does not grant Scrap evidence approval');
 perform m3c_test.fails(format('select public.production_correction_command(%L,''submit'',%L,%L)',f,m3c_test.payload(e,11,2)||'{"reason":""}',gen_random_uuid()),'22023');
 before_digest:=reporting_test.digest();
 perform public.production_history(f,jsonb_build_object('reporting_version',3,'entry',e,'to_at',clock_timestamp()+interval '.1 seconds'));
 perform public.quality_read(f,jsonb_build_object('mode','board','entry',e));
 perform public.lean_read(f,jsonb_build_object('mode','entries','from','1970-01-01T00:00:00Z','to',clock_timestamp()));
 perform public.lean_read(f,jsonb_build_object('mode','analysis_occurrences','from','1970-01-01T00:00:00Z','to',clock_timestamp()));
 perform public.lean_read(f,jsonb_build_object('mode','problems','from',clock_timestamp()-interval '1 day','to',clock_timestamp()));
 perform m3c_test.ok(reporting_test.digest()=before_digest,'all consumer reads preserve full operational/audit/gate digest');
 h:=public.lean_command(f,gen_random_uuid(),'problem',jsonb_build_object('mechanism','scrap','line_id',x->>'line','product_id',x->>'product','cause_id',cause,'expected_revision',0));
 insert into m3c_test.context values(x||jsonb_build_object('entry',e,'observation',obs,'cause',cause,'problem',h->>'id'));
 -- Real completed late admission is exercised only behind a disposable local gate.
 x:=late_test.new_context('m3c-late',3600,true);f:=(x->>'factory')::uuid;
 gate:=(select to_jsonb(g) from private.production_recording_v3_activation g where factory_id=f);
 update private.production_recording_v3_activation set enabled=true,schema_contract_version=3 where factory_id=f;
 late_entry:=(public.record_lean_production(f,late_test.payload(x,1)||'{"scrap_kg":0.1234567890123456789}',gen_random_uuid())->>'id')::uuid;
 update private.production_recording_v3_activation set enabled=false,schema_contract_version=0 where factory_id=f;
 perform m3c_test.ok((select recording_kind='LATE_ORDINARY' and effective_period_end=execution_finished_at and created_at>=effective_period_end and effective_scrap_kg=.1234567890123456789 from public.production_entries where id=late_entry),'actual guarded late Scrap preserves period versus submission and exact KG');
 perform m3c_test.ok(not exists(select 1 from private.production_recording_v3_activation where enabled),'late recording defaults remain disabled after isolated exercise');
end$$;

-- Ordinary exact observation stays supported; no new rejection/approval stage.
do $$declare x jsonb;f uuid;e uuid;obs uuid:=gen_random_uuid();begin
 select t.x into x from m3c_test.context t;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 e:=(public.record_lean_production(f,late_test.payload(x,1)||'{"scrap_kg":0.25}',gen_random_uuid())->>'id')::uuid;
 perform public.lean_command(f,gen_random_uuid(),'scrap_observation',jsonb_build_object('id',obs,'entry_id',e,'occurred_at',clock_timestamp(),'preliminary_cause_id',x->>'cause','observation','Genuinely asserted exact observation','response','Existing exact workflow'));
 perform m3c_test.ok((select time_precision='EXACT' and occurred_at is not null and period_start is null from public.lean_scrap_events where id=obs),'ordinary exact observation contract unchanged');
 perform m3c_test.ok(not exists(select 1 from private.lean_occurrences where factory_id=f and event_id=obs),'unreviewed exact evidence remains unqualified');
end$$;
select count(*) as consumer_assertions from m3c_test.checks;
