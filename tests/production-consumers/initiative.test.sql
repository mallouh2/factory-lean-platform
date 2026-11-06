-- Actual protected commands on a separate disposable factory. No hosted seed,
-- invented exact time for a period, replaced view, disabled trigger or SQL mock.
create function m3c_test.observation(x jsonb,c uuid,precision_kind text,review_it boolean default true) returns jsonb language plpgsql as $$
declare f uuid:=(x->>'factory')::uuid;e uuid;s uuid:=gen_random_uuid();at_time timestamptz:=clock_timestamp();p jsonb;begin
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 e:=(public.record_lean_production(f,late_test.payload(x,1)||'{"scrap_kg":0.5}',gen_random_uuid())->>'id')::uuid;
 p:=jsonb_build_object('id',s,'entry_id',e,'preliminary_cause_id',c,'observation','Controlled baseline evidence','response','Keep the actual precision');
 if precision_kind='SHIFT_PERIOD' then p:=p||'{"time_precision":"SHIFT_PERIOD"}';
 else p:=p||jsonb_build_object('occurred_at',at_time);end if;
 perform public.lean_command(f,gen_random_uuid(),'scrap_observation',p);
 if review_it then perform public.lean_command(f,gen_random_uuid(),'scrap_review',jsonb_build_object('id',s,'approved_cause_id',c,'note','Reviewed actual fixture output','expected_revision',1));end if;
 return jsonb_build_object('entry',e,'observation',s);
end$$;
create function m3c_test.problem(x jsonb,label text,mechanism text default 'scrap') returns jsonb language plpgsql as $$
declare c uuid:=gen_random_uuid();p uuid;f uuid:=(x->>'factory')::uuid;begin
 perform public.lean_command(f,gen_random_uuid(),'cause',jsonb_build_object('id',c,'name','Baseline '||label));
 p:=(public.lean_command(f,gen_random_uuid(),'problem',jsonb_build_object('mechanism',mechanism,'line_id',case when mechanism='scrap' then x->>'line' end,
  'machine_id',case when mechanism='downtime' then x->>'machine' end,'product_id',case when mechanism='scrap' then x->>'product' end,'cause_id',c,'expected_revision',0))->>'id')::uuid;
 return jsonb_build_object('cause',c,'problem',p);
end$$;
create function m3c_test.no_baseline(x jsonb,p uuid,label text) returns void language plpgsql as $$
declare f uuid:=(x->>'factory')::uuid;n bigint;digest text;begin
 select count(*) into n from public.lean_initiatives;digest:=reporting_test.digest();
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''initiative'',%L)',f,gen_random_uuid(),
  jsonb_build_object('id',gen_random_uuid(),'problem_id',p,'product_id',x->>'product','title',label)),'lean_baseline_missing');
 perform m3c_test.ok((select count(*) from public.lean_initiatives)=n and reporting_test.digest()=digest,label||' fails closed without initiative, retry, audit or operational changes');
end$$;

do $$declare x jsonb;f uuid;pr jsonb;ev jsonb;exact_ev jsonb;other_ev jsonb;pid uuid;cause uuid;i uuid:=gen_random_uuid();r uuid:=gen_random_uuid();p jsonb;h jsonb;
 lo timestamptz;hi timestamptz;before_digest text;period_i uuid;period_p uuid;period_e uuid;period_s uuid;action_id uuid:=gen_random_uuid();
 evidence jsonb;verification jsonb;saved_i jsonb;saved_comp jsonb;saved_loss jsonb;comp uuid:=gen_random_uuid();loss_event uuid;other_product uuid;decision jsonb;rev integer;ack_retry uuid:=gen_random_uuid();begin
 x:=late_test.new_context('m3c-baseline',3600,false);f:=(x->>'factory')::uuid;
 perform public.lean_command(f,gen_random_uuid(),'standard',jsonb_build_object('id',gen_random_uuid(),'line_id',x->>'line','product_id',x->>'product','running_percent',1,'startup_kg',0,'expected_revision',0));

 -- Period-only: bounds are copied from authoritative production, never occurred_at.
 pr:=m3c_test.problem(x,'period');pid:=(pr->>'problem')::uuid;cause:=(pr->>'cause')::uuid;
 ev:=m3c_test.observation(x,cause,'SHIFT_PERIOD');period_p:=pid;period_e:=(ev->>'entry')::uuid;period_s:=(ev->>'observation')::uuid;
 select effective_period_start,effective_period_end into lo,hi from public.production_entries where id=period_e;
 p:=jsonb_build_object('id',i,'problem_id',pid,'product_id',x->>'product','title','Reviewed period baseline');
 h:=public.lean_command(f,r,'initiative',p);period_i:=i;
 perform m3c_test.ok(h->>'id'=i::text and (select baseline_from=lo and baseline_to=hi from public.lean_initiatives where id=i),'period-only initiative uses actual reviewed production bounds');
 perform m3c_test.ok((select occurred_at is null and period_start=lo and period_end=hi from public.lean_scrap_events where id=period_s),'initiative never invents or rewrites period timing precision');
 before_digest:=reporting_test.digest();
 perform m3c_test.ok(public.lean_command(f,r,'initiative',p)=h and reporting_test.digest()=before_digest and (select count(*) from public.lean_initiatives where id=i)=1,'initiative UUID retry returns same result with no duplicate or audit change');
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''initiative'',%L)',f,r,p||'{"title":"Different intent"}'),'40001');
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 perform m3c_test.fails(format('select public.lean_command(%L,%L,''initiative'',%L)',f,gen_random_uuid(),p||jsonb_build_object('id',gen_random_uuid())),'42501');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);

 -- Physical Warehouse acknowledgment must not add the already credited Good.
 before_digest:=m3c_test.operational();
 perform public.supply_command(f,'acknowledge_good',jsonb_build_object('entry',period_e),ack_retry);
 perform m3c_test.ok(m3c_test.operational()=before_digest and (select count(*) from public.production_receipt_acknowledgments where factory_id=f and entry_id=period_e)=1,'period receipt acknowledgment preserves Good, source and inventory exactly');
 before_digest:=reporting_test.digest();
 perform m3c_test.ok(public.supply_command(f,'acknowledge_good',jsonb_build_object('entry',period_e),ack_retry)=period_e and reporting_test.digest()=before_digest,'Warehouse acknowledgment retry creates no second credit or audit');

 -- Exact-only: compare the persisted bounds to the original SQL expression.
 pr:=m3c_test.problem(x,'exact');pid:=(pr->>'problem')::uuid;cause:=(pr->>'cause')::uuid;
 ev:=m3c_test.observation(x,cause,'EXACT');
 select min(occurred_at),max(greatest(ended_at,occurred_at)) into lo,hi from private.lean_occurrences where factory_id=f and cause_id=cause;
 i:=gen_random_uuid();perform public.lean_command(f,gen_random_uuid(),'initiative',jsonb_build_object('id',i,'problem_id',pid,'product_id',x->>'product','title','Existing exact baseline'));
 perform m3c_test.ok((select baseline_from=lo and baseline_to=hi from public.lean_initiatives where id=i),'exact-only initiative retains original timestamp expressions');
 perform m3c_test.ok((select time_precision='EXACT' and occurred_at is not null and period_start is null from public.lean_scrap_events where id=(ev->>'observation')::uuid),'exact evidence remains exact, not broadened to production period');

 -- Mixed observations remain two identifiable sources with one KG contribution each.
 pr:=m3c_test.problem(x,'mixed');pid:=(pr->>'problem')::uuid;cause:=(pr->>'cause')::uuid;
 ev:=m3c_test.observation(x,cause,'SHIFT_PERIOD');exact_ev:=m3c_test.observation(x,cause,'EXACT');
 select least(e.effective_period_start,s.occurred_at),greatest(e.effective_period_end,z.created_at,s.occurred_at) into lo,hi
 from public.production_entries e,public.production_entries z,public.lean_scrap_events s
 where e.id=(ev->>'entry')::uuid and z.id=(exact_ev->>'entry')::uuid and s.id=(exact_ev->>'observation')::uuid;
 other_ev:=m3c_test.observation(x,cause,'SHIFT_PERIOD',false);
 i:=gen_random_uuid();perform public.lean_command(f,gen_random_uuid(),'initiative',jsonb_build_object('id',i,'problem_id',pid,'product_id',x->>'product','title','Mixed reviewed baseline'));
 perform m3c_test.ok((select baseline_from=lo and baseline_to=hi from public.lean_initiatives where id=i),'mixed baseline envelopes authoritative period and original exact bounds');
 perform m3c_test.ok((select count(*)=2 and count(distinct event_id)=2 and sum(scrap_kg)=1 and count(*) filter(where occurred_at is null)=1 from private.lean_occurrences where factory_id=f and cause_id=cause),'mixed evidence preserves distinct precision and counts quantities exactly once');

 pr:=m3c_test.problem(x,'unreviewed');pid:=(pr->>'problem')::uuid;cause:=(pr->>'cause')::uuid;
 ev:=m3c_test.observation(x,cause,'SHIFT_PERIOD',false);
 perform m3c_test.no_baseline(x,pid,'unreviewed evidence');
 perform m3c_test.ok(not exists(select 1 from private.lean_occurrences where factory_id=f and cause_id=cause),'unreviewed period never supplies eligible baseline evidence');

 -- Ambiguous Product attribution follows the existing reviewed Loss projection.
 -- Explicit synthetic snapshot input, not execution of a Loss model.
 pr:=m3c_test.problem(x,'ambiguous','downtime');pid:=(pr->>'problem')::uuid;cause:=(pr->>'cause')::uuid;
 insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Other fixture Product','M3CB','meter','meter',.5) returning id into other_product;
 insert into public.downtime_events(factory_id,work_center_id,line_id,reason_id,approved_cause_id,approved_at,approved_by,started_at,ended_at,created_by)
 values(f,(x->>'machine')::uuid,(x->>'line')::uuid,cause,cause,clock_timestamp(),(x->>'owner')::uuid,clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute',(x->>'owner')::uuid) returning id into loss_event;
 insert into public.production_loss_estimates(factory_id,event_id,model_version,result,recorded_by) values(f,loss_event,1,
  jsonb_build_object('model_version',1,'fixture','ambiguous Product attribution','assumptions',jsonb_build_array(jsonb_build_object('product_id',x->>'product'),jsonb_build_object('product_id',other_product))),(x->>'owner')::uuid);
 perform m3c_test.ok((select product_id is null from private.lean_occurrences where factory_id=f and event_id=loss_event and cause_id=cause),'ambiguous reviewed source retains unknown Product attribution');
 perform m3c_test.no_baseline(x,pid,'ambiguous Product evidence');
 pr:=m3c_test.problem(x,'missing');perform m3c_test.no_baseline(x,(pr->>'problem')::uuid,'missing evidence');

 pr:=m3c_test.problem(x,'stale');pid:=(pr->>'problem')::uuid;cause:=(pr->>'cause')::uuid;
 ev:=m3c_test.observation(x,cause,'SHIFT_PERIOD');
 perform public.production_correction_command(f,'submit',m3c_test.payload((ev->>'entry')::uuid,1,.75),gen_random_uuid());
 perform m3c_test.ok((select not review_current from private.lean_occurrences where factory_id=f and cause_id=cause),'approved correction alone leaves old evidence ineligible');
 perform m3c_test.no_baseline(x,pid,'stale reviewed evidence');

 -- Existing trusted persistence/normal action lifecycle. Quantities are taken
 -- from this actual source; unknown runtime stays incomplete. This fixture does
 -- not claim a model-calculated or hosted human verification acceptance result.
 select jsonb_build_object('version',2,'time_basis','production','complete',false,'status','INCOMPLETE','runtime_hours',null,
  'source_revision',(select revision from private.lean_source_state where factory_id=f),'problem_id',period_p,'product_id',x->>'product',
  'entry_id',e.id,'good',e.effective_good::text,'scrap_kg',e.effective_scrap_kg::text,'precision',e.time_precision,'period_start',e.effective_period_start,'period_end',e.effective_period_end)
 into evidence from public.production_entries e where e.id=period_e;
 perform m3c_test.fails(format('select public.store_lean_evidence(%L,%L,''baseline'',%L,1,%L,''{}'',%L)',f,x->>'owner',period_i,evidence,gen_random_uuid()),'42501');
 perform set_config('request.jwt.claim.role','service_role',false);
 select revision into rev from public.lean_initiatives where id=period_i;
 perform public.store_lean_evidence(f,(x->>'owner')::uuid,'baseline',period_i,rev,evidence,'{}',gen_random_uuid());
 perform set_config('request.jwt.claim.role','authenticated',false);
 perform public.lean_command(f,gen_random_uuid(),'action',jsonb_build_object('id',action_id,'initiative_id',period_i,'title','Check material setup','action_type','PROCESS','owner_id',x->>'owner','due_date',current_date,'expected_revision',0));
 select revision into rev from public.lean_actions where id=action_id;
 perform public.lean_command(f,gen_random_uuid(),'progress',jsonb_build_object('id',action_id,'status','COMPLETED','due_date',current_date,'note','Controlled local action completed','expected_revision',rev));
 verification:=evidence||jsonb_build_object('source_revision',(select revision from private.lean_source_state where factory_id=f));
 perform set_config('request.jwt.claim.role','service_role',false);
 select revision into rev from public.lean_initiatives where id=period_i;
 perform public.store_lean_evidence(f,(x->>'owner')::uuid,'verify',period_i,rev,verification,'{"outcome":"INSUFFICIENT_DATA","note":"Runtime coverage remains unknown"}',gen_random_uuid());
 verification:=verification||jsonb_build_object('source_revision',(select revision from private.lean_source_state where factory_id=f));
 perform public.store_lean_evidence(f,(x->>'owner')::uuid,'save_comparison',period_p,0,verification,jsonb_build_object('cutoff',clock_timestamp(),'desired_hours',1),comp);
 perform set_config('request.jwt.claim.role','authenticated',false);
 select to_jsonb(s) into saved_i from public.lean_initiatives s where id=period_i;
 select to_jsonb(s) into saved_comp from public.lean_saved_comparisons s where id=comp;
 select to_jsonb(s) into saved_loss from public.production_loss_estimates s where s.event_id=loss_event;
 perform m3c_test.ok(saved_i->'baseline_evidence'=evidence and saved_i->'verification_evidence' is not null and saved_i->>'outcome'='INSUFFICIENT_DATA','existing protected lifecycle retains separate baseline, action and human verification evidence');
 decision:=public.production_correction_command(f,'submit',m3c_test.payload(period_e,2,1.5),gen_random_uuid());
 perform m3c_test.ok(decision->>'status'='APPROVED' and (select effective_good=2 and effective_scrap_kg=1.5 from public.production_entries where id=period_e),'later approved source correction updates current official quantities');
 perform m3c_test.ok((select count(*)=1 from public.production_receipt_acknowledgments where factory_id=f and entry_id=period_e)
  and (select quantity_credited=2 from public.finished_goods_sources where factory_id=f and entry_id=period_e),'approved correction preserves acknowledgment and source Good credit exactly once');
 perform m3c_test.ok(saved_i=(select to_jsonb(s) from public.lean_initiatives s where id=period_i)
  and saved_comp=(select to_jsonb(s) from public.lean_saved_comparisons s where id=comp)
  and saved_loss=(select to_jsonb(s) from public.production_loss_estimates s where s.event_id=loss_event),'same-factory saved initiative baseline/verification, Lean comparison and Loss snapshot remain byte-equivalent after correction');
 perform m3c_test.ok(evidence->>'scrap_kg'='0.5' and (select effective_scrap_kg=1.5 from public.production_entries where id=period_e)
  and not private.production_scrap_review_current(f,period_e,(select reviewed_at from public.lean_scrap_events where id=period_s)),'historical approved value remains distinct from current unreviewed correction');
 perform public.lean_command(f,gen_random_uuid(),'scrap_review',jsonb_build_object('id',period_s,'approved_cause_id',(select approved_cause_id from public.lean_scrap_events where id=period_s),'note','Separate review of new official measurement','expected_revision',2));
 perform m3c_test.ok((select scrap_kg=1.5 and review_current from private.lean_occurrences where factory_id=f and event_id=period_s)
  and saved_i=(select to_jsonb(s) from public.lean_initiatives s where id=period_i),'new reviewed current evidence never recalculates saved approved initiative');
end$$;
select count(*) as cumulative_consumer_assertions from m3c_test.checks;
