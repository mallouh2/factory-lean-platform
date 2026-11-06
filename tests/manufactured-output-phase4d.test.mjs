import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {outputDestinationAllowed,outputRelatedTargets} from '../src/utils/output-navigation.mjs';
import {recordingFetch} from '../src/utils/production-recording-v3.mjs';
const f='11111111-1111-4111-8111-111111111111',e='22222222-2222-4222-8222-222222222222',o='33333333-3333-4333-8333-333333333333';
test('related destinations retain exact factory, entry, output, item and work identities',()=>{
 const result=outputRelatedTargets(f,{entry_id:e,output_id:o,item_id:e,work_id:o});assert.equal(result.length,5);assert.equal(result.find(x=>x.view==='quality').entry,e);assert.equal(result.find(x=>x.view==='warehouse').output,o);assert.equal(result.find(x=>x.view==='planning').work,o);assert.equal(result.find(x=>x.view==='order').item,e);
});
test('display names and product references cannot be used as destinations',()=>{
 for(const d of outputRelatedTargets(f,{entry_id:'PO-001',output_id:'Pipe',item_id:'Same product'}))assert.equal(outputDestinationAllowed(d,f,()=>true),false);
});
test('destinations fail closed across factories and independent effective permissions',()=>{
 for(const d of outputRelatedTargets(f,{entry_id:e,output_id:o,item_id:e})){assert.equal(outputDestinationAllowed(d,e,()=>true),false);assert.equal(outputDestinationAllowed(d,f,()=>false),false);assert.equal(outputDestinationAllowed(d,f,()=>true),true);}
 const qualityOnly=(m,a)=>m==='quality'&&a==='view';assert.equal(outputDestinationAllowed({factory:f,view:'quality',entry:e},f,qualityOnly),true);assert.equal(outputDestinationAllowed({factory:f,view:'production',entry:e},f,qualityOnly),false);
});
test('invalid view, absent identity or malformed work fails closed',()=>{
 for(const d of [{view:'admin'},{view:'quality'},{view:'planning',output:o,work:'not-a-uuid'}])assert.equal(outputDestinationAllowed({factory:f,...d},f,()=>true),false);
});
test('all scoped readers retain exact nested quantities',async()=>{
 for(const name of ['manufactured_receiving_context','manufactured_completion_context','manufactured_output_order_read']){const r=await recordingFetch(async()=>new Response('{"quantity":0.1234567890123456789,"version":3}'))('http://127.0.0.1/rest/v1/rpc/'+name);assert.deepEqual(await r.json(),{quantity:'0.1234567890123456789',version:3});}
});
test('legacy history default columns untouched; integration is in Details',()=>{
 const s=fs.readFileSync('src/features/ProductionHistory.tsx','utf8');assert.match(s,/entry=\{String\(selected.id\)\} onOutputRelated=/);assert.match(s,/defaultHistoryColumns/);
 const p=fs.readFileSync('src/features/ManufacturedCompletion.tsx','utf8');assert.doesNotMatch(p,/<th>\{t\('actions'\)\}<\/th>/);assert.match(p,/Retired decisions/);assert.match(p,/detailsRow\(/);
});
