import test from 'node:test';
import assert from 'node:assert/strict';
import {productionScope,exactQuantitySum} from '../src/utils/production-periods.mjs';
import {decodeConsumerJson,consumerFetch} from '../src/utils/production-consumer-transport.mjs';
import {windowMetrics,typedTotals,baselineEvidence,compareEvidence} from '../src/utils/lean-comparison.mjs';
import {leanCommandValid} from '../src/utils/lean-contract.mjs';
const a='2026-01-10T19:00:00.000001Z',b='2026-01-11T03:00:00.000002Z',recorded='2026-01-11T04:00:00Z';
const event={evidence_version:2,event_id:'E',mechanism:'scrap',time_precision:'SHIFT_PERIOD',period_start:a,period_end:b,occurred_at:null,recorded_at:recorded,
 product_id:'P',line_id:'L',shift_id:'S',scrap_kg:'0.1234567890123456789',produced_kg:'20',lost_output:'0',output_unit:'meter',loss_minutes:'0',review_current:true};
const entry={evidence_version:2,id:'entry',product_id:'P',line_id:'L',unit:'meter',shift_id:'S',created_at:recorded,production_precision:'SHIFT_PERIOD',effective_period_start:a,effective_period_end:b,
 produced_weight_kg:'20',effective_scrap_kg:event.scrap_kg,effective_unfinished:'0',review_current:true};
const options={product_id:'P',subject_id:'L',mechanism:'scrap'};
for(const [name,from,to,wanted] of [
 ['whole overnight period',a,b,'CONTAINED'],['left clipped',a,'2026-01-10T23:00:00Z','PARTIAL'],
 ['right clipped','2026-01-10T23:00:00Z',b,'PARTIAL'],['before boundary','2026-01-09T00:00:00Z',a,'OUTSIDE'],
 ['after boundary',b,'2026-01-12T00:00:00Z','OUTSIDE'],['microsecond clip','2026-01-10T19:00:00.000002Z',b,'PARTIAL'],
 ['microsecond full','2026-01-10T19:00:00.000000Z','2026-01-11T03:00:00.000003Z','CONTAINED']])
 test(name,()=>assert.equal(productionScope(event,from,to),wanted));
test('offset and UTC bounds denote the same production period',()=>assert.equal(productionScope(event,'2026-01-10T22:00:00.000001+03:00','2026-01-11T06:00:00.000002+03:00'),'CONTAINED'));
test('entry uses production bounds, never late submission instant',()=>{
 assert.equal(productionScope(entry,a,b,{entry:true}),'CONTAINED');
 assert.equal(productionScope(entry,'2026-01-11T04:00:00Z','2026-01-11T05:00:00Z',{entry:true}),'OUTSIDE');
});
test('unknown attribution remains an explicitly scoped unknown',()=>assert.equal(productionScope({...entry,production_precision:'UNKNOWN'},recorded,'2026-01-11T05:00:00Z',{entry:true}),'UNKNOWN'));
test('missing interval cannot become a measured zero',()=>assert.equal(productionScope({...event,period_start:null},recorded,'2026-01-11T05:00:00Z'),'UNKNOWN'));
test('zero-width observation is a contained point only at its genuine boundary',()=>assert.equal(productionScope({...event,period_end:a},a,b),'CONTAINED'));
test('legacy exact assertions retain existing date parsing',()=>assert.equal(productionScope({occurred_at:'2026-01-10'},'2026-01-10T00:00:00Z','2026-01-11T00:00:00Z'),'CONTAINED'));
test('exact KG sum retains 19 decimals',()=>assert.equal(exactQuantitySum([{kg:'0.1234567890123456789'},{kg:'0.0000000000000000001'}],'kg'),'0.123456789012345679'));
for(const value of [null,undefined,'',NaN,'n/a'])test('unknown quantity is not zero: '+value,()=>assert.equal(exactQuantitySum([{kg:value}],'kg'),null));
test('measured zero is preserved',()=>assert.equal(exactQuantitySum([{kg:'0'}],'kg'),'0'));
test('complete period yields exact reviewed KG and READY',()=>{
 const m=windowMetrics([event],[entry],a,b,1,options);assert.equal(m.scrap_kg,event.scrap_kg);assert.equal(m.status,'READY');assert.equal(m.produced_kg,'20');assert.equal(m.frequency,1);assert.equal(m.shifts[0].response_minutes[0].minutes,null);
});
test('partial period yields INCOMPLETE rather than proportional KG',()=>{
 const m=windowMetrics([event],[entry],a,'2026-01-10T23:00:00Z',1,options);assert.equal(m.scrap_kg,null);assert.equal(m.produced_kg,null);assert.equal(m.scrap_rate,null);assert.equal(m.frequency,null);assert.equal(m.status,'INCOMPLETE');assert.equal(m.wip.meter,null);
});
test('correction approval cannot qualify stale reviewed quantities',()=>{
 const m=windowMetrics([{...event,review_current:false}],[{...entry,review_current:false}],a,b,1,options);assert.equal(m.scrap_kg,null);assert.equal(m.status,'INCOMPLETE');assert.equal(m.unreviewed_records,1);
});
test('empty complete source is NA',()=>assert.equal(windowMetrics([],[],a,b,1,{...options,evidence_version:2}).status,'NA'));
test('missing physical mass is INCOMPLETE while known Scrap remains visible',()=>{
 const m=windowMetrics([event],[{...entry,produced_weight_kg:null}],a,b,1,options);assert.equal(m.status,'INCOMPLETE');assert.equal(m.scrap_kg,event.scrap_kg);assert.equal(m.scrap_rate,null);assert.equal(m.unknown_weight,1);
});
test('another Product and another line never contribute',()=>{
 const m=windowMetrics([event,{...event,event_id:'other',product_id:'Other'}],[entry,{...entry,line_id:'Other',produced_weight_kg:'1000'}],a,b,1,options);assert.equal(m.scrap_kg,event.scrap_kg);assert.equal(m.produced_kg,'20');
});
test('Meter/Piece/KG quantities remain typed and exact',()=>assert.deepEqual(typedTotals([
 {evidence_version:2,unit:'meter',q:'1.1234567890123456789'},{evidence_version:2,unit:'piece',q:'2'},{evidence_version:2,unit:'kg',q:'3'}],'q'),{meter:'1.1234567890123456789',piece:'2',kg:'3'}));
test('new baseline evidence is versioned without editing old snapshots',()=>{
 const old={version:1,metrics:{scrap_kg:'7'}},copy=structuredClone(old);
 const newer=baselineEvidence({checkpoints:[],occurrences:[event],entries:[entry],problem:{id:'problem',line_id:'L',mechanism:'scrap'},initiative:{product_id:'P',baseline_from:a,baseline_to:b},as_of:recorded,evidence_version:2});
 assert.equal(newer.version,2);assert.equal(newer.time_basis,'production');assert.equal(newer.status,'INCOMPLETE');assert.deepEqual(old,copy);
});
test('incompatible saved v1 baseline never silently compares to v2',()=>{
 const baseline={version:1,problem_id:'problem',product_id:'P',runtime_hours:1,from:a,to:b,coverage_complete:true,metrics:{scrap_kg:7}},copy=structuredClone(baseline);
 const m=compareEvidence({checkpoints:[],occurrences:[event],entries:[entry],problem:{id:'problem',line_id:'L',mechanism:'scrap'},product_id:'P',cutoff:b,desired_hours:1,baseline,as_of:recorded,evidence_version:2});
 assert.equal(m.version,2);assert.equal(m.complete,false);assert.equal(m.incompatible_evidence_versions,true);assert.equal(m.changes.scrap_kg.suggestion,'INSUFFICIENT_DATA');assert.deepEqual(baseline,copy);
});
test('transport preserves exact decimals, bigint source revision and normal integer controls',()=>{
 const d=decodeConsumerJson('{"revision":2,"evidence_version":2,"total":1,"source_revision":9007199254740993,"scrap_kg":0.1234567890123456789,"ready":false}');
 assert.equal(d.revision,2);assert.equal(d.total,1);assert.equal(d.source_revision,'9007199254740993');assert.equal(d.scrap_kg,event.scrap_kg);assert.equal(d.ready,false);
});
test('unsafe integer controls fail closed',()=>assert.throws(()=>decodeConsumerJson('{"revision":9007199254740993}')));
test('consumer adapter touches only successful Lean scalar RPCs',async()=>{
 const fetcher=consumerFetch(async()=>new Response('{"scrap_kg":0.1234567890123456789}',{headers:{'content-type':'application/json'}}));
 assert.equal((await (await fetcher('http://127.0.0.1/rest/v1/rpc/lean_read',{})).json()).scrap_kg,event.scrap_kg);
 assert.equal(await (await fetcher('http://127.0.0.1/auth/v1/user',{})).text(),'{"scrap_kg":0.1234567890123456789}');
});
const u='11111111-1111-4111-8111-111111111111',p={id:u,entry_id:u,time_precision:'SHIFT_PERIOD',preliminary_cause_id:u,observation:'Measured in the verified shift',response:'Held for review'};
const valid=payload=>leanCommandValid('lean_command',{factory:u,request_id:u,operation:'scrap_observation',payload});
test('period command retains existing observation and response requirements',()=>assert.equal(valid(p),true));
for(const extra of [{occurred_at:a},{downtime_id:u},{period_start:a},{approved_cause_id:u},{response:''},{time_precision:'EXACT'}])test('period command rejects unapproved shape '+JSON.stringify(extra),()=>assert.equal(valid({...p,...extra}),false));
