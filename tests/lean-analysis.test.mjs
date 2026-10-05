import test from 'node:test';
import assert from 'node:assert/strict';
import { leanProblemIdentity, producedWeight, scrapRate, startupPerformance, abnormalScrap, initiativeStatus,
  recurrenceAfterVerification, metricChange, comparableExposure, operatingRuntime } from '../src/utils/lean-analysis.mjs';
import { runtimeByShift } from '../src/utils/lean-analysis.mjs';
import { windowMetrics, baselineEvidence, compareEvidence, typedTotals } from '../src/utils/lean-comparison.mjs';
import { leanCommandValid, leanRequiredPermission } from '../src/utils/lean-contract.mjs';

test('worked baseline 40 h: 3 occurrences, 95 min, 80 kg / 2000 kg = 4%',()=>{
 const events=[0,1,2].map(i=>({event_id:'E'+i,product_id:'P',occurred_at:`2026-10-01T0${i+1}:00:00Z`,ended_at:`2026-10-01T0${i+1}:30:00Z`,loss_minutes:[30,30,35][i],scrap_kg:[20,30,30][i],lost_output:100,output_unit:'piece',shift_id:i<2?'A':'B'}));
 const entries=[{product_id:'P',line_id:'L',created_at:'2026-10-01T10:00:00Z',produced_weight_kg:2000,effective_unfinished:20,unit:'piece',shift_id:'A'}];
 const result=windowMetrics(events,entries,'2026-10-01T00:00:00Z','2026-10-03T00:00:00Z',40,{product_id:'P',subject_id:'L',mechanism:'scrap'});
 assert.equal(result.frequency,3);assert.equal(result.loss_minutes,95);assert.equal(result.scrap_kg,80);assert.equal(result.scrap_rate,4);assert.equal(result.loss_minutes_per_hour,2.375);assert.equal(result.occurrences_per_hour,.075);assert.equal(result.shifts[0].frequency,2);assert.equal(result.shifts[1].frequency,1);assert.deepEqual(result.wip,{piece:20});
});
test('problem mass denominator includes normal production, excludes another Product and subject',()=>{
 const events=[{event_id:'E',product_id:'P',occurred_at:'2026-10-01T02:00Z',ended_at:'2026-10-01T03:00Z',loss_minutes:10,scrap_kg:10}];
 const entry=(product_id,line_id,kg)=>({product_id,line_id,created_at:'2026-10-01T04:00Z',produced_weight_kg:kg,effective_unfinished:0,unit:'piece'});
 const result=windowMetrics(events,[entry('P','L',100),entry('P','L',900),entry('OTHER','L',999),entry('P','OTHER',999)],'2026-10-01T00:00Z','2026-10-02T00:00Z',12,{product_id:'P',subject_id:'L',mechanism:'scrap'});
 assert.equal(result.produced_kg,1000);assert.equal(result.scrap_rate,1);
});
test('linked rows from one physical event count once; unlike lost-output units stay separate',()=>{
 const rows=[{event_id:'SAME',product_id:'P',occurred_at:'2026-10-01T01:00Z',ended_at:'2026-10-01T02:00Z',loss_minutes:20,scrap_kg:3,lost_output:100,output_unit:'piece'}, {event_id:'SAME',product_id:'P',occurred_at:'2026-10-01T02:00Z',ended_at:'2026-10-01T03:00Z',loss_minutes:10,scrap_kg:2,lost_output:50,output_unit:'meter'}];
 const result=windowMetrics(rows,[],'2026-10-01T00:00Z','2026-10-02T00:00Z',4,{product_id:'P',subject_id:'L',mechanism:'scrap'});
 assert.equal(result.frequency,1);assert.deepEqual(result.lost_output,{piece:100,meter:50});assert.equal(result.scrap_rate,null);
});
test('unknown legacy mass and loss cannot become zero or a complete scrap rate',()=>{
 const result=windowMetrics([{event_id:'E',product_id:'P',occurred_at:'2026-10-01T01:00Z',ended_at:'2026-10-01T02:00Z',loss_minutes:null,scrap_kg:null}],[],'2026-10-01T00:00Z','2026-10-02T00:00Z',4,{product_id:'P',subject_id:'L',mechanism:'scrap'});
 assert.equal(result.loss_minutes,null);assert.equal(result.scrap_kg,null);assert.equal(result.scrap_rate,null);assert.equal(result.unknown_loss,1);
});
test('baseline predating immutable runtime capture remains insufficient, never inferred from calendar',()=>{
 const result=baselineEvidence({checkpoints:[],occurrences:[],entries:[],problem:{id:'X',line_id:'L',mechanism:'scrap'},initiative:{product_id:'P',baseline_from:'2026-10-01T00:00Z',baseline_to:'2026-10-02T00:00Z'},as_of:'2026-10-03T00:00Z'});
 assert.equal(result.coverage_complete,false);assert.equal(result.runtime_hours,null);
});
test('manual comparison does not alter initiative/actions and enforces same Product',()=>{
 const problem={id:'X',line_id:'L',product_id:'P',mechanism:'scrap'},before=structuredClone(problem);
 const input={checkpoints:[],occurrences:[],entries:[],problem,product_id:'P',cutoff:'2026-10-02T00:00Z',desired_hours:40,as_of:'2026-10-03T00:00Z'};
 const result=compareEvidence(input);assert.equal(result.complete,false);assert.equal(result.after.remaining_hours,40);assert.deepEqual(problem,before);
 assert.throws(()=>compareEvidence({...input,product_id:'OTHER'}),/comparison_product/);
});

test('unknown official baseline has no invented runtime target or remaining exposure',()=>{
 const baseline={product_id:'P',problem_id:'X',runtime_hours:null,coverage_complete:false,metrics:{scrap_kg:20}};
 const result=compareEvidence({checkpoints:[],occurrences:[],entries:[],problem:{id:'X',line_id:'L',product_id:'P',mechanism:'scrap'},product_id:'P',cutoff:'2026-10-02T00:00Z',desired_hours:null,baseline,as_of:'2026-10-03T00:00Z'});
 assert.equal(result.complete,false);assert.equal(result.before.collected_hours,null);assert.equal(result.after.desired_hours,null);assert.equal(result.after.remaining_hours,null);
});

test('mixed Product saved loss stays unattributed in Product-specific comparisons',()=>{
 const result=windowMetrics([{event_id:'MIXED',product_id:null,occurred_at:'2026-10-01T01:00Z',ended_at:'2026-10-01T02:00Z',loss_minutes:60,scrap_kg:10,loss_details:{assumptions:[{product_id:'P'},{product_id:'OTHER'}]}}],[],'2026-10-01T00:00Z','2026-10-02T00:00Z',4,{product_id:'P',subject_id:'L',mechanism:'scrap'});
 assert.equal(result.product_attribution_missing,true);assert.equal(result.loss_minutes,null);assert.equal(result.scrap_kg,null);assert.equal(result.frequency,null);
});
test('immutable shift boundaries correctly split overnight exposure without employee attribution',()=>{
 const checkpoints=[{captured_at:'2026-10-01T00:00Z',context:{timezone:'UTC',shifts:[{id:'A',start_time:'06:00:00',end_time:'18:00:00'},{id:'B',start_time:'18:00:00',end_time:'06:00:00'}]}}];
 const intervals=[{subject_id:'L',product_id:'P',started_at:'2026-10-01T17:00:00Z',ended_at:'2026-10-02T07:00:00Z'}];
 const result=runtimeByShift(intervals,checkpoints);assert.deepEqual(result.map(x=>x.shift_id),['A','B','A']);assert.deepEqual(result.map(x=>(Date.parse(x.ended_at)-Date.parse(x.started_at))/3600000),[1,12,1]);
});
test('Lean commands reject browser evidence, unsupported fields and invalid mass',()=>{
 const factory='11111111-1111-1111-1111-111111111111',request_id='22222222-2222-2222-2222-222222222222';
 assert.equal(leanCommandValid('record_lean_production',{factory,request_id,payload:{good:100,scrap_kg:10,discarded_quantity:0}}),true);
 for(const payload of [{scrap_kg:-1},{scrap_kg:Infinity},{scrap_kg:'10'},{scrap_kg:1,evidence:{}},{scrap_unit:'piece'}])assert.equal(leanCommandValid('record_lean_production',{factory,request_id,payload}),false);
 assert.equal(leanCommandValid('lean_command',{factory,request_id,operation:'verify',payload:{}}),false);
 assert.deepEqual(leanRequiredPermission('standard'),['lean_standards','edit']);assert.deepEqual(leanRequiredPermission('scrap_review'),['lean','edit']);assert.deepEqual(leanRequiredPermission('progress'),['lean','view']);
});

const downtime = { factory_id:'F', mechanism:'downtime', machine_id:'M1', approved_cause_id:'C' };
test('Machine and Approved Cause define downtime identity, independent of product/line', () => {
  assert.notEqual(leanProblemIdentity(downtime), leanProblemIdentity({...downtime,machine_id:'M2'}));
  assert.equal(leanProblemIdentity(downtime), leanProblemIdentity({...downtime,product_id:'P',line_id:'L'}));
  assert.notEqual(leanProblemIdentity(downtime), leanProblemIdentity({...downtime,factory_id:'OTHER'}));
});
test('High Scrap without downtime has Line + Product + Approved Cause identity', () => {
  const scrap={factory_id:'F',mechanism:'scrap',line_id:'L',product_id:'P',approved_cause_id:'C'};
  assert.notEqual(leanProblemIdentity(scrap),leanProblemIdentity({...scrap,product_id:'P2'}));
  assert.notEqual(leanProblemIdentity(scrap),leanProblemIdentity({...scrap,line_id:'L2'}));
  assert.throws(()=>leanProblemIdentity({...scrap,approved_cause_id:null}),/unreviewed/);
});
test('Piece output weight includes Good plus newly recorded WIP; Scrap is kg', () => {
  const kg=producedWeight({good:100,newly_recorded_wip:20,unit:'piece',weight_unit:'piece',kg_per_unit:2});
  assert.equal(kg,240);assert.equal(scrapRate(10,kg),1000/240);
});
test('Meter and kg output remain unit safe', () => {
  assert.equal(producedWeight({good:20,newly_recorded_wip:5,unit:'meter',weight_unit:'meter',kg_per_unit:.8}),20);
  assert.equal(producedWeight({good:8,newly_recorded_wip:2,unit:'kg'}),10);
  assert.equal(producedWeight({good:100,newly_recorded_wip:0,unit:'piece',weight_unit:'meter',kg_per_unit:2}),null);
  assert.equal(producedWeight({good:100,newly_recorded_wip:0,unit:'piece',weight_unit:'piece',kg_per_unit:null}),null);
});
test('Unknown weight and zero output never invent a Scrap Rate', () => {
  assert.equal(scrapRate(5,null),null);assert.equal(scrapRate(5,0),null);
  assert.throws(()=>scrapRate(-1,100),/invalid/);assert.throws(()=>scrapRate(Infinity,100),/invalid/);
});
test('One actual startup receives one allowance across multiple declarations', () => {
  const result=startupPerformance([{startup_id:'S1',scrap_kg:12},{startup_id:'S1',scrap_kg:8}],20);
  assert.deepEqual(result,{startups:1,total_kg:20,expected_kg:20,excess_kg:0,observed_kg_per_startup:20,approved_kg:20});
});
test('Multiple startups in one shift have separate allowances', () => {
  const result=startupPerformance([{startup_id:'S1',scrap_kg:25},{startup_id:'S2',scrap_kg:10}],20);
  assert.equal(result.startups,2);assert.equal(result.expected_kg,30);assert.equal(result.excess_kg,5);
});
test('Expected startup remains in total Scrap but does not open an abnormal problem', () => {
  const result=abnormalScrap({total_scrap_kg:20,produced_kg:500,startup_events:[{startup_id:'S',scrap_kg:20}],startup_standard_kg:20,running_standard_percent:1});
  assert.equal(result.startup.total_kg,20);assert.equal(result.abnormal_startup,false);assert.equal(result.abnormal_running,false);
});
test('Excess startup stays abnormal and only legitimate allowance is subtracted', () => {
  const result=abnormalScrap({total_scrap_kg:35,produced_kg:500,startup_events:[{startup_id:'S',scrap_kg:30}],startup_standard_kg:20,running_standard_percent:2});
  assert.equal(result.running_kg,5);assert.equal(result.adjusted_kg,15);assert.equal(result.running_rate,3);
  assert.equal(result.abnormal_startup,true);assert.equal(result.abnormal_running,true);
});
test('Observed startup performance never changes the approved standard', () => {
  const events=[{startup_id:'S1',scrap_kg:50},{startup_id:'S2',scrap_kg:30}],copy=structuredClone(events);
  const result=startupPerformance(events,20);assert.equal(result.observed_kg_per_startup,40);assert.equal(result.approved_kg,20);assert.deepEqual(events,copy);
});
test('Missing process standards are explicit, not inferred from observations', () => {
  const result=abnormalScrap({total_scrap_kg:30,produced_kg:100,startup_events:[{startup_id:'S',scrap_kg:30}]});
  assert.equal(result.abnormal_startup,null);assert.equal(result.abnormal_running,null);assert.ok(result.gaps.includes('startup_standard'));assert.ok(result.gaps.includes('running_standard'));
});
test('Running Scrap without startup can be evaluated independently', () => {
  const result=abnormalScrap({total_scrap_kg:4,produced_kg:100,running_standard_percent:3});
  assert.equal(result.running_rate,4);assert.equal(result.abnormal_running,true);assert.equal(result.startup.excess_kg,0);
});
test('Multiple actions derive one initiative state and require human verification', () => {
  assert.equal(initiativeStatus([]),'OPEN');assert.equal(initiativeStatus([{status:'OPEN'}]),'OPEN');
  assert.equal(initiativeStatus([{status:'COMPLETED'},{status:'IN_PROGRESS'}]),'IN_PROGRESS');
  assert.equal(initiativeStatus([{status:'COMPLETED'},{status:'CANCELLED'}]),'AWAITING_VERIFICATION');
  assert.equal(initiativeStatus([{status:'CANCELLED'}]),'AWAITING_VERIFICATION');
  assert.equal(initiativeStatus([{status:'COMPLETED'}],{confirmed_at:'2026-10-05'}),'VERIFIED');
});
const hour=3600000,cutoff=Date.parse('2026-10-05T00:00:00Z');
const interval=(from,to,product='P',subject='L')=>({started_at:cutoff+from*hour,ended_at:cutoff+to*hour,product_id:product,subject_id:subject});
const selection=(direction,desired_hours=40)=>({product_id:'P',subject_id:'L',cutoff,direction,desired_hours});
test('Equal-runtime selection skips calendar gaps and clips the final interval exactly', () => {
  const before=comparableExposure([interval(-100,-70),interval(-50,-20)],selection('before'));
  const after=comparableExposure([interval(10,30),interval(80,110)],selection('after'));
  assert.equal(before.collected_hours,40);assert.equal(after.collected_hours,40);assert.equal(before.complete,true);assert.equal(after.complete,true);
  assert.equal(after.intervals[1].ended_at,new Date(cutoff+100*hour).toISOString());
});
test('Comparable exposure excludes another Product and another subject', () => {
  const result=comparableExposure([interval(0,15),interval(20,80,'OTHER'),interval(80,150,'P','OTHER')],selection('after'));
  assert.equal(result.collected_hours,15);assert.equal(result.remaining_hours,25);assert.equal(result.complete,false);
});
test('Overlapping runtime is rejected rather than counted twice', () => {
  assert.throws(()=>comparableExposure([interval(0,10),interval(5,15)],selection('after')),/overlap/);
});
test('Independent metric changes preserve conflicting dimensions and explicit thresholds', () => {
  assert.equal(metricChange(95,70).suggestion,'IMPROVED');assert.equal(metricChange(80,95).suggestion,'WORSE');
  assert.equal(metricChange(100,90).suggestion,'NO_MEANINGFUL_CHANGE');assert.equal(metricChange(100,110).suggestion,'NO_MEANINGFUL_CHANGE');
  assert.equal(metricChange(100,94,5).suggestion,'IMPROVED');assert.equal(metricChange(null,20).suggestion,'INSUFFICIENT_DATA');
  assert.equal(metricChange(0,1).suggestion,'WORSE');assert.equal(metricChange(0,0).suggestion,'NO_MEANINGFUL_CHANGE');
});
test('Two distinct post-verification events within 30 days trigger recurrence', () => {
  const occurrences=[{event_id:'A',occurred_at:cutoff+hour},{event_id:'A',occurred_at:cutoff+hour},{event_id:'B',occurred_at:cutoff+2*hour}];
  assert.equal(recurrenceAfterVerification(occurrences.slice(0,2),cutoff,cutoff+3*hour).recurred,false);
  assert.equal(recurrenceAfterVerification(occurrences,cutoff,cutoff+3*hour).recurred,true);
});
test('Events before verification and beyond the 30-day watch do not invalidate an improvement', () => {
  const events=[{event_id:'A',occurred_at:cutoff},{event_id:'B',occurred_at:cutoff-1},{event_id:'C',occurred_at:cutoff+31*24*hour}];
  assert.equal(recurrenceAfterVerification(events,cutoff,cutoff+40*24*hour).count,0);
});
function context(status='running',paused_at=null) {
  return {centers:[{id:'M1',line_id:'L',status,dependency_mode:'blocking',impact_scope:'whole_line',position:1}],
    orders:[{id:'J',line_id:'L',product_id:'P',status:'active',actual_start:new Date(cutoff).toISOString()}],lines:[{id:'L',paused_at}],stops:[],transfers:[]};
}
const checkpoint=(id,hours,ctx)=>({id,captured_at:new Date(cutoff+hours*hour).toISOString(),context:ctx});
test('Runtime requires actual active production; planned work is never exposure', () => {
  const ctx=context();ctx.orders[0].status='planned';assert.equal(operatingRuntime([checkpoint(1,0,ctx)],cutoff+hour).length,0);
});
test('Runtime excludes blocked and paused intervals but retains exact active Product', () => {
  const blocked=context('stopped');blocked.stops=[{work_center_id:'M1',started_at:new Date(cutoff+hour).toISOString()}];
  const intervals=operatingRuntime([checkpoint(1,0,context()),checkpoint(2,1,blocked),checkpoint(3,2,context('running',new Date(cutoff+2*hour).toISOString())),checkpoint(4,3,context())],cutoff+4*hour);
  assert.equal(comparableExposure(intervals,selection('after',4)).collected_hours,2);
});
test('A running machine in a blocked line does not create runtime exposure', () => {
  const ctx=context();ctx.centers.push({id:'M2',line_id:'L',status:'stopped',dependency_mode:'blocking',impact_scope:'whole_line',position:2});
  ctx.stops=[{work_center_id:'M2',started_at:new Date(cutoff).toISOString()}];
  assert.equal(operatingRuntime([checkpoint(1,0,ctx)],cutoff+hour).length,0);
});
test('A required idle machine prevents an apparently healthy route from accumulating runtime', () => {
  const ctx=context();ctx.centers.push({id:'M2',line_id:'L',status:'idle',dependency_mode:'blocking',impact_scope:'whole_line',position:2});
  assert.equal(operatingRuntime([checkpoint(1,0,ctx)],cutoff+hour).length,0);
});
test('Shared flow resolver accounts for a running alternative and excludes its borrowed home', () => {
  const ctx=context('stopped');ctx.stops=[{work_center_id:'M1',started_at:new Date(cutoff).toISOString()}];
  ctx.centers.push({id:'ALT',line_id:'HOME',status:'running',dependency_mode:'blocking',impact_scope:'whole_line',position:1});
  ctx.transfers=[{original_id:'M1',alternative_id:'ALT',created_at:new Date(cutoff).toISOString()}];
  assert.equal(comparableExposure(operatingRuntime([checkpoint(1,0,ctx)],cutoff+hour),selection('after',1)).complete,true);
});
test('Final state at one transaction timestamp wins; runtime is not duplicated by intermediate triggers', () => {
  const result=operatingRuntime([checkpoint(1,0,context('stopped')),checkpoint(2,0,context())],cutoff+hour);
  assert.equal(comparableExposure(result,selection('after',1)).collected_hours,1);
});
test('Actual start within a captured interval is respected without dropping the entire interval', () => {
  const ctx=context();ctx.orders[0].actual_start=new Date(cutoff+hour/2).toISOString();
  assert.equal(comparableExposure(operatingRuntime([checkpoint(1,0,ctx)],cutoff+hour),selection('after',1)).collected_hours,.5);
});
test('Buffer expiry splits runtime even when no further machine transition was recorded', () => {
  const ctx=context();ctx.centers.push({id:'M2',line_id:'L',status:'stopped',dependency_mode:'buffer',buffer_minutes:30,impact_scope:'whole_line',position:2});
  ctx.stops=[{work_center_id:'M2',started_at:new Date(cutoff).toISOString()}];
  assert.equal(comparableExposure(operatingRuntime([checkpoint(1,0,ctx)],cutoff+hour),selection('after',1)).collected_hours,.5);
});

test('official baseline includes the final instantaneous occurrence and its mass declaration',()=>{
 const from='2026-10-01T01:00:00Z',to='2026-10-01T02:00:00Z';
 const events=[from,to].map((at,i)=>({event_id:'E'+i,product_id:'P',occurred_at:at,ended_at:at,loss_minutes:0,scrap_kg:5}));
 const entries=[{product_id:'P',line_id:'L',created_at:to,produced_weight_kg:100,effective_unfinished:0,unit:'piece'}];
 const result=baselineEvidence({checkpoints:[],occurrences:events,entries,problem:{id:'X',line_id:'L',mechanism:'scrap'},initiative:{product_id:'P',baseline_from:from,baseline_to:to},as_of:to});
 assert.equal(result.metrics.frequency,2);assert.equal(result.metrics.scrap_kg,10);assert.equal(result.metrics.produced_kg,100);assert.equal(result.metrics.scrap_rate,10);
 assert.equal(windowMetrics(events,entries,from,to,1,{product_id:'P',subject_id:'L',mechanism:'scrap'}).frequency,1,'ordinary adjacent windows remain half-open');
});
test('shift seconds preserve the exact operating exposure boundary',()=>{
 const checkpoints=[{captured_at:'2026-10-01T00:00:00Z',context:{timezone:'UTC',shifts:[{id:'A',start_time:'06:00:30',end_time:'18:00:30'},{id:'B',start_time:'18:00:30',end_time:'06:00:30'}]}}];
 const result=runtimeByShift([{subject_id:'L',product_id:'P',started_at:'2026-10-01T18:00:00Z',ended_at:'2026-10-01T18:01:00Z'}],checkpoints);
 assert.deepEqual(result.map(x=>x.shift_id),['A','B']);assert.equal(Date.parse(result[0].ended_at)-Date.parse(result[0].started_at),30000);
});
