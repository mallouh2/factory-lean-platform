import test from 'node:test';
import assert from 'node:assert/strict';
import {relativeAttention,recordingScrapAttention,annotateLeanAttention} from '../src/utils/lean-presentation.mjs';

test('top fifth is independent, includes ties and uses all eligible rows before paging',()=>{
 const rows=Array.from({length:50},(_,i)=>({frequency:i+1,loss_minutes:50-i,mechanism:'downtime',scrap_kg:0}));
 const before=structuredClone(rows),result=annotateLeanAttention(rows);
 assert.equal(result.filter(x=>x.attention.loss).length,10);assert.equal(result.filter(x=>x.attention.frequency).length,10);
 assert.equal(result.slice(0,25).filter(x=>x.attention.frequency).length,0);assert.equal(result.slice(25).filter(x=>x.attention.frequency).length,10);
 assert.deepEqual(rows,before);assert.equal(relativeAttention([{frequency:2},{frequency:2}],'frequency'),null);
 assert.equal(relativeAttention([{frequency:20}],'frequency'),null);assert.equal(relativeAttention([{frequency:0},{frequency:null}],'frequency'),null);
 assert.equal(relativeAttention([{frequency:9},{frequency:9},{frequency:2},{frequency:1},{frequency:1}],'frequency'),9);
});
test('multiple metric cells can receive attention and missing measurements remain unknown',()=>{
 const result=annotateLeanAttention([{mechanism:'scrap',frequency:12,loss_minutes:100,scrap_kg:15},{frequency:2,loss_minutes:1},{frequency:1,loss_minutes:null}]);
 assert.deepEqual(result[0].attention,{loss:true,frequency:true,scrap:true});assert.deepEqual(result[2].attention,{loss:false,frequency:false,scrap:false});
});
const entries=[{id:'a',created_at:'2026-10-01',lean_startup_id:'S',effective_startup_kg:6,effective_scrap_kg:6,produced_weight_kg:100,running_standard_percent:2},
 {id:'b',created_at:'2026-10-02',lean_startup_id:'S',effective_startup_kg:4,effective_scrap_kg:6,produced_weight_kg:100,running_standard_percent:2},
 {id:'c',created_at:'2026-10-03',lean_startup_id:'S',effective_startup_kg:1,effective_scrap_kg:1,produced_weight_kg:100,running_standard_percent:2}];
test('startup allowance is shared chronologically and exact running standard is not exceeded',()=>{
 const before=structuredClone(entries),result=recordingScrapAttention([...entries].reverse(),[{id:'S',standard_kg:10}]);
 assert.equal(result.get('a'),false);assert.equal(result.get('b'),false);assert.equal(result.get('c'),true);assert.deepEqual(entries,before);
 assert.equal(recordingScrapAttention([{...entries[1],lean_startup_id:null,effective_startup_kg:0,effective_scrap_kg:3}],[]).get('b'),true);
 assert.equal(recordingScrapAttention([{...entries[1],running_standard_percent:null}],[]).get('b'),false);
});
test('Downtime Scrap attention follows its approved cause, linked declaration and selected period',()=>{
 const options={entries,startups:[{id:'S',standard_kg:10}],from:'2026-10-02',to:'2026-10-04',links:[{entry_id:'c',downtime_id:'D',approved_cause_id:'C',occurred_at:'2026-10-03'}]};
 const row={mechanism:'downtime',cause_id:'C',event_ids:['D'],scrap_kg:1};
 assert.equal(annotateLeanAttention([row],options)[0].attention.scrap,true);
 assert.equal(annotateLeanAttention([{...row,cause_id:'other'}],options)[0].attention.scrap,false);
 assert.equal(annotateLeanAttention([row],{...options,from:'2026-10-04',to:'2026-10-05'})[0].attention.scrap,false);
});
