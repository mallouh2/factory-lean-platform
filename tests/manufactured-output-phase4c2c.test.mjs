import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {reconciliationPayload,reconciliationMessage} from '../src/utils/output-reconciliation.mjs';
import {recordingFetch} from '../src/utils/production-recording-v3.mjs';
test('finished adjustment requires an actual listed source and physical confirmation',()=>{
 const a={available:true,mode:'FINISHED_TO_UNFINISHED',sources:[{id:'source'}]};
 assert.throws(()=>reconciliationPayload(a,{source:'other',reason:'Actual physical change',confirmed:true}));
 assert.throws(()=>reconciliationPayload(a,{source:'source',reason:'Actual physical change',confirmed:false}));
 assert.deepEqual(reconciliationPayload(a,{source:'source',reason:' Actual physical change ',confirmed:true}),{source_id:'source',reason:'Actual physical change',physical_confirmation:true});
});
test('unfinished action preserves exact protected lot and location, and requires physical identification',()=>{
 const a={available:true,mode:'UNFINISHED_RECLASS',source_lot_id:'lot',source_location:'Stored bay'};
 assert.throws(()=>reconciliationPayload(a,{reason:'Correction',confirmed:true}));
 assert.equal(reconciliationPayload(a,{reason:'Correction',confirmed:true,identification:'Separated and verified'}).source_location,'Stored bay');
 assert.throws(()=>reconciliationPayload({...a,available:false},{reason:'Correction',confirmed:true,identification:'Verified'}));
});
test('unchanged classification records reason only, without source or fabricated movement',()=>assert.deepEqual(reconciliationPayload({available:true,mode:'UNCHANGED'},{reason:'Same canonical operations'}),{reason:'Same canonical operations'}));
test('known and unsupported blockers have EN/AR operational feedback',()=>{
 for(const code of ['output_revision','output_quality_hold','output_allocation_retirement_required','output_work_started','output_stock_unavailable','unknown']){
  assert.ok(reconciliationMessage(code,'en').length>20);assert.match(reconciliationMessage(code,'ar'),/[\u0600-\u06ff]/);
 }
});
test('reconciliation response keeps exact numeric evidence',async()=>{
 const f=recordingFetch(async()=>new Response('{"quantity":9007199254740993.25,"revision":12}'));
 const r=await f('http://127.0.0.1/rest/v1/rpc/reconcile_manufactured_output');
 assert.deepEqual(await r.json(),{quantity:'9007199254740993.25',revision:'12'});
});
test('API forwards authenticated protected command and validates finding/revision/UUID without privileged bypass',()=>{
 const s=fs.readFileSync('src/app/api/manufactured-output/route.ts','utf8');
 assert.match(s,/body.command==='reconcile_manufactured_output'/);assert.match(s,/!uuid\(args.finding\)/);assert.match(s,/authenticatedClient\(recordingFetch\(\)\)/);assert.doesNotMatch(s,/service.role|output_reconcile\(/i);
});
