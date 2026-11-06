import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {calculateProductionLoss} from '../src/utils/production-loss-impact.mjs';
import {deliverLossReview} from '../src/utils/loss-review-delivery.mjs';
const at=n=>new Date(Date.UTC(2026,9,14,10)+n*60000).toISOString();
const event={id:'event',work_center_id:'machine',line_id:'line',stop_nature:'planned',planned_activity:'inspection',started_at:at(0),ended_at:at(40)};
const evidence={policy_version:1,event_id:'event',machine_id:'machine',operation:'LINK',association_revision:1,
  relationship:'PLANNED_MAINTENANCE',valid:true,approved_start:at(10),approved_end:at(30)};
const order=(start=0,end=40)=>({id:'order',line_id:'line',product_id:'product',status:'planned',start_time:at(start),expected_finish:at(end)});
function context(extra={}){return {maintenance_loss_context_version:1,demand_complete:true,routing_steps:[],
 centers:[{id:'machine',line_id:'line',status:'stopped',dependency_mode:'blocking',impact_scope:'whole_line',position:1}],
 stops:[{id:'event',work_center_id:'machine',started_at:at(0),ended_at:null}],transfers:[],orders:[],
 products:[{id:'product',unit:'meter'}],capabilities:[{work_center_id:'machine',product_id:'product',rate:60,rate_unit:'meter'}],
 profiles:[{work_center_id:'machine',product_id:'product',can_defer:false,scrap_expected:true,shutdown_scrap_quantity:.2,restart_scrap_quantity:.3,scrap_unit:'kg'}],
 recovery_rates:[],lines:[{id:'line'}],...extra};}
const sample=c=>[{id:1,event_id:'event',captured_at:at(0),context:c}];
const calc=(c=context(),m=evidence,e=event)=>calculateProductionLoss(e,sample(c),null,Date.parse(at(45)),[],m);
test('Approved idle interval is verified zero, separate physical/approved/outside durations',()=>{
 const r=calc();assert.equal(r.readiness,'READY');assert.equal(r.raw_stop_minutes,40);
 assert.equal(r.approved_maintenance_minutes,20);assert.equal(r.outside_window_minutes,20);
 assert.equal(r.scheduled_non_production_minutes,20);assert.equal(r.effective_loss_minutes,0);
 assert.deepEqual(r.maintenance_segments.map(x=>x.maintenance_segment),['OUTSIDE','APPROVED','OUTSIDE']);
});
test('Approved production conflict retains genuine loss and blocks review',()=>{
 const r=calc(context({orders:[order()]}));assert.equal(r.readiness,'INCOMPLETE');
 assert.equal(r.effective_loss_minutes,40);assert.equal(r.estimated_lost_output_quantity,40);
 assert.equal(r.scheduled_non_production_minutes,0);assert.match(r.missing.join(','),/conflicts/);
 assert.equal(r.estimated_total_scrap,.5);assert.equal(r.estimated_shutdown_scrap,.2);assert.equal(r.estimated_restart_scrap,.3);
});
test('Early start and overrun split original boundaries, count only intended demand',()=>{
 const r=calc(context({orders:[order(0,10),{...order(30,40),id:'second'}]}));
 assert.equal(r.readiness,'READY');assert.equal(r.effective_loss_minutes,20);assert.equal(r.estimated_lost_output_quantity,20);
 assert.equal(r.estimated_total_scrap,.5);assert.equal(r.scheduled_non_production_minutes,20);
});
test('Partial overlap retains original approved window without extension',()=>{
 const r=calc(context(),evidence,{...event,ended_at:at(15)});assert.equal(r.approved_maintenance_minutes,5);
 assert.equal(r.outside_window_minutes,10);assert.equal(r.maintenance_context.approved_end,at(30));
});
test('Contextual unplanned stop retains legacy arithmetic even during approval',()=>{
 const c=context({orders:[order()]}),e={...event,stop_nature:'unplanned'},m={...evidence,relationship:'CONTEXTUAL_UNPLANNED'};
 const r=calc(c,m,e),legacy=calculateProductionLoss(e,sample(c),null,Date.parse(at(45)));
 for(const key of Object.keys(legacy))assert.deepEqual(r[key],legacy[key]);
 assert.equal(r.approved_maintenance_minutes,null);assert.equal(r.readiness,'READY');
});
test('Unrelated event with verified NONE keeps every legacy result field',()=>{
 const c=context({orders:[order()]});const m={operation:'NONE',association_revision:0};
 const legacy=calculateProductionLoss(event,sample(c),null,Date.parse(at(45))),r=calc(c,m);
 for(const key of Object.keys(legacy))assert.deepEqual(r[key],legacy[key]);
});
for(const [name,patch] of [['unfrozen',{valid:false}],['wrong machine',{machine_id:'other'}],['wrong event',{event_id:'other'}],['missing boundary',{approved_start:null}]])
 test('Invalid association: '+name,()=>{const r=calc(context(),{...evidence,...patch});assert.equal(r.readiness,'INCOMPLETE');assert.match(r.missing.join(','),/approval/);});
for(const [name,patch] of [['missing demand',{demand_complete:false}],['legacy sample',{maintenance_loss_context_version:undefined}],['missing routing',{routing_steps:undefined}],['missing orders',{orders:undefined}]])
 test('Unknown '+name+' is INCOMPLETE, never zero',()=>{const r=calc(context(patch));assert.equal(r.readiness,'INCOMPLETE');assert.equal(r.effective_loss_minutes,null);assert.equal(r.estimated_lost_output_quantity,null);});
test('Unscheduled relevant planned demand is unknown',()=>{const r=calc(context({orders:[{...order(),start_time:null}]}));assert.equal(r.readiness,'INCOMPLETE');assert.equal(r.effective_loss_minutes,null);});
test('Active demand beyond its recorded plan never becomes fabricated scheduled idle',()=>{
 const r=calc(context({orders:[{...order(0,10),status:'active',actual_started_at:at(0)}]}));
 assert.equal(r.readiness,'INCOMPLETE');assert.equal(r.effective_loss_minutes,null);
 assert.equal(r.scheduled_non_production_minutes,null);
});
test('Actual alternative after window uses Product rate, no hypothetical mitigation',()=>{
 const c=context({orders:[order(30,40)]});c.centers.push({id:'alt',status:'running',line_id:'other',dependency_mode:'independent',impact_scope:'none'});
 c.capabilities.push({work_center_id:'alt',product_id:'product',rate:30,rate_unit:'meter'});
 c.transfers=[{original_id:'machine',alternative_id:'alt',order_id:'order',ended_at:null}];
 const r=calc(c);assert.equal(r.effective_loss_minutes,5);assert.equal(r.estimated_lost_output_quantity,5);
 c.transfers=[];assert.equal(calc(c).effective_loss_minutes,10);
 c.transfers=[{original_id:'machine',alternative_id:'alt',order_id:'foreign',ended_at:null}];
 const invalid=calc(c);assert.equal(invalid.readiness,'INCOMPLETE');assert.equal(invalid.effective_loss_minutes,10);
});
test('Known buffer expiry is reused outside approval; unknown buffer is incomplete',()=>{
 const c=context({orders:[order(0,10)]});c.centers[0].dependency_mode='buffer';c.centers[0].buffer_minutes=5;
 const r=calc(c);assert.equal(r.effective_loss_minutes,5);assert.ok(r.mitigation.includes('buffer'));
 c.centers[0].buffer_minutes=null;assert.equal(calc(c).readiness,'INCOMPLETE');
});
test('Multiple linked real stops get per-event intervals, no duration multiplication',()=>{
 const first=calc(context(),evidence,{...event,ended_at:at(15)});
 const secondEvent={...event,id:'event2',started_at:at(20),ended_at:at(40)};
 const second=calculateProductionLoss(secondEvent,[{id:2,event_id:'event2',captured_at:at(20),context:context()}],null,Date.parse(at(45)),[],{...evidence,event_id:'event2'});
 assert.equal(first.approved_maintenance_minutes+second.approved_maintenance_minutes,15);
 assert.equal(first.raw_stop_minutes+second.raw_stop_minutes,35);
});
test('Historical changed/unknown estimates never recalculate, duplicate, or calibrate',async()=>{
 for(const state of ['EVIDENCE_CHANGED_AFTER_REVIEW','EVIDENCE_COMPARISON_UNKNOWN']) {
 const saved={result:calc()},selected={event,saved,maintenance:{review_state:state}};
 const r=await deliverLossReview(selected,[],async()=>{throw Error('Historical recalculation forbidden');});
 assert.strictEqual(r.calculation,saved.result);assert.equal(r.maintenance.review_state,state);assert.deepEqual(r.suggestions,[]);
 }
});
test('Forward SQL/trusted reader use actor union, consistent locks and no remote/ledger readers',async()=>{
 const sql=await readFile(new URL('../supabase/migrations/20261014065225_maintenance_loss_context_v1.sql',import.meta.url),'utf8');
 const edge=await readFile(new URL('../supabase/functions/save-production-loss-estimate/index.ts',import.meta.url),'utf8');
 assert.match(sql,/maintenance_planning_lock\(factory\)/);assert.match(sql,/input_hash.*distinct from estimate/s);
 assert.match(sql,/require_permission\(factory,'downtime','edit'\)/);assert.doesNotMatch(sql,/public\.user_permissions/);
 assert.match(sql,/EVIDENCE_CHANGED_AFTER_REVIEW/);assert.match(sql,/EVIDENCE_COMPARISON_UNKNOWN/);
 assert.doesNotMatch(sql,/update public\.(production_loss_estimates|production_loss_context_snapshots|production_entries)/i);
 assert.doesNotMatch(edge,/async function rows|\/rest\/v1\/\$\{table\}/);assert.match(edge,/production_loss_review_inputs/);
});
