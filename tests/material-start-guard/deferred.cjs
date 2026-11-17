const fs=require('fs'),{sql,q,save}=require('./qa-local.cjs'),c=require('./qa-factory.json');let s=fs.readFileSync(__dirname+'/integration.sql','utf8');const prefix=s.slice(0,s.indexOf('do $$\n#variable_conflict'));const test=`do $$
#variable_conflict use_column
declare x jsonb;f uuid;i uuid;r public.material_requests;v integer;s jsonb;context jsonb;cancelled_id uuid;before numeric;n integer;begin
 x:=qa471.make_case('deferred');f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;select *into r from public.material_requests where production_item_id=i and material_id=(x->>'additive')::uuid;
 perform public.production_material_action(f,'RESERVE',jsonb_build_object('id',r.id,'revision',r.revision,'quantity','1.6'),gen_random_uuid());
 select sum(quantity)into before from public.inventory_transactions where factory_id=f and material_id=r.material_id;
 context:=public.planning_change_context(f,i);perform public.revise_product_plan_confirmed(f,i,(x->>'line')::uuid,clock_timestamp()+interval '2 days','material_delay','Authorized isolated postponement',context->>'fingerprint',true,gen_random_uuid());
 s:=private.material_action_context(f,r.id);perform qa471.ok(s->>'state'='AWAITING_RESERVATION'and s->>'reason'='material_outside_window'and not(s->>'can_recheck')::boolean,'G: genuine future deferral has cause and cannot auto-reactivate');
 perform qa471.ok((select reserved=0 and issued=0 and awaiting from private.material_request_progress where request_id=r.id),'G: postponement releases only real unissued reservation');
 perform qa471.ok((select sum(quantity)=before from public.inventory_transactions where factory_id=f and material_id=r.material_id),'G: postponement invents no physical return');
 select revision into v from public.material_requests where id=r.id;perform qa471.fails(format('select public.production_material_action(%L,%L,%L,%L)',f,'RECHECK',jsonb_build_object('id',r.id,'revision',v),gen_random_uuid()),'material_preparation_unavailable');
 context:=public.planning_change_context(f,i);perform public.revise_product_plan_confirmed(f,i,(x->>'line')::uuid,clock_timestamp()+interval '1 minute','material_delay','Authorized isolated return to preparation window',context->>'fingerprint',true,gen_random_uuid());
 perform qa471.ok((select not awaiting and reserved=0 from private.material_request_progress where request_id=r.id),'G: protected re-entry reuses request and requires explicit re-reservation');
 perform qa471.ok((select count(*)=3 from public.material_requests where production_item_id=i),'G: no duplicate raw request after re-entry');
 -- The pre-fix reproduction is an isolated legacy active order, never owner data.
 select x into x from qa471.cases where label='legacy-active';i:=(x->>'item')::uuid;perform private.release_material_preparation(f,i);select *into r from public.material_requests where production_item_id=i and material_id=(x->>'additive')::uuid;
 s:=private.material_action_context(f,r.id);perform qa471.ok(s->>'state'='REQUESTED'and (s->>'can_recheck')::boolean and s->>'reason'='material_recheck_required','G: obsolete active deferral offers an explicit authorized recovery');
 select revision into v from public.material_requests where id=r.id;s:=public.production_material_action(f,'RECHECK',jsonb_build_object('id',r.id,'revision',v),gen_random_uuid());
 perform qa471.ok((select not awaiting and issued=0 and consumed=0 from private.material_request_progress where request_id=r.id),'G: recovery changes eligibility, never invents historical custody');
 select revision into v from public.material_requests where id=r.id;perform public.production_material_action(f,'RESERVE',jsonb_build_object('id',r.id,'revision',v,'quantity','1.6'),gen_random_uuid());
 select revision into v from public.material_requests where id=r.id;perform public.production_material_action(f,'ISSUE',jsonb_build_object('id',r.id,'revision',v,'quantity','0.6','physical_confirmation',true),gen_random_uuid());
 perform qa471.ok((select issued=0.6 and consumed=0 and reserved=1 from private.material_request_progress where request_id=r.id),'G: valid legacy active request permits current explicit fractional handover');
 perform set_config('request.jwt.claim.sub',${q(c.worker)},true);select revision into v from public.material_requests where id=r.id;
 perform qa471.fails(format('select public.production_material_action(%L,%L,%L,%L)',f,'ISSUE',jsonb_build_object('id',r.id,'revision',v,'quantity','1','physical_confirmation',true),gen_random_uuid()),'42501');
 perform qa471.fails(format('select public.production_start_readiness(%L,%L)',gen_random_uuid(),i),'42501');perform set_config('request.jwt.claim.sub',${q(c.owner)},true);
 -- Explicit manual cancellation is never reopened by reconciliation.
 x:=qa471.make_case('cancelled');i:=(x->>'item')::uuid;cancelled_id:=public.supply_command(f,'material_request',jsonb_build_object('item',x->>'additive','item_type','material','unit','kg','quantity',0.2,'production_item_id',i,'note','Isolated cancellation test'),gen_random_uuid());
 select revision into v from public.material_requests where material_requests.id=cancelled_id;perform public.supply_command(f,'material_change',jsonb_build_object('id',cancelled_id,'revision',v,'action','cancel','reason','Explicit isolated cancellation'),gen_random_uuid());perform private.reconcile_material_item(f,i);perform qa471.ok((select status='CANCELLED'from public.material_requests where material_requests.id=cancelled_id),'G: cancelled manual request remains cancelled');
 end$$;
select jsonb_build_object('assertions',count(*),'labels',jsonb_agg(label))from qa471.checks;rollback;`;
fs.writeFileSync(__dirname+'/deferred.sql',prefix+test);try{const result=JSON.parse(sql(prefix+test));save('deferred-results',result);console.log('PASS '+result.assertions+' deferred/recovery/permission SQL assertions');}catch(e){fs.writeFileSync(__dirname+'/deferred-error.txt',e.message);throw e;}
