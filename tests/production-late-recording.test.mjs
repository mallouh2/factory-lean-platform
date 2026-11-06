import test from 'node:test';
import assert from 'node:assert/strict';
import {recordingContextValid,parseRecordingStatusQuery,recordingFailure} from '../src/utils/production-recording-v3.mjs';
import {leanCommandValid} from '../src/utils/lean-contract.mjs';
import {sourceCommandValid} from '../src/utils/quality-contract.mjs';
const id='11111111-1111-4111-8111-111111111111';
const context={version:3,execution_key:'a'.repeat(64),occurrence_key:'b'.repeat(64),context_hash:'c'.repeat(64),current_shift_quantity_confirmed:false};
const args={factory:id,request_id:id,payload:{good:2,scrap_kg:.25,discarded_quantity:0,recording_context:context}};
test('bounded exact V3 context accepted without invented mode/timestamps',()=>assert.equal(recordingContextValid(context),true));
for(const [name,value] of Object.entries({null:null,array:[],version:{...context,version:4},extra:{...context,late:true},hash:{...context,execution_key:'X'.repeat(64)},declaration:{...context,current_shift_quantity_confirmed:'true'},missing:{version:3}}))
 test(`context rejects ${name}`,()=>assert.equal(recordingContextValid(value),false));
test('existing recording command accepts additive V3 context',()=>assert.equal(leanCommandValid('record_lean_production',args),true));
test('WIP cannot borrow ordinary late context',()=>assert.equal(leanCommandValid('record_lean_production',{...args,payload:{...args.payload,input_lot:id}}),false));
test('legacy active/WIP payload shape remains accepted',()=>assert.equal(leanCommandValid('record_lean_production',{...args,payload:{good:2,scrap_kg:.25,discarded_quantity:0,input_lot:id}}),true));
test('dated correction requires bounded identity in both command paths',()=>{
 const payload={entry:id,good:1,discarded_quantity:0,scrap_kg:0,corrected_occurrence_key:'a'.repeat(64)};
 assert.equal(leanCommandValid('correct_lean_production',{...args,payload}),true);
 assert.equal(sourceCommandValid({...args,operation:'correct',payload,allocations:[]}),true);
 assert.equal(sourceCommandValid({...args,operation:'correct',payload:{...payload,corrected_occurrence_key:'invalid'},allocations:[]}),false);
});
test('status query is exact actor-session scope with normalized UUIDs',()=>assert.deepEqual(parseRecordingStatusQuery(new URLSearchParams({factory:id,request_id:id})),{factory:id,request_id:id}));
for(const q of [`factory=${id}`,`factory=${id}&request_id=${id}&actor=${id}`,`factory=${id}&request_id=${id}&request_id=${id}`,'factory=bad&request_id=bad'])
 test(`invalid status query rejected: ${q.slice(0,24)}`,()=>assert.throws(()=>parseRecordingStatusQuery(new URLSearchParams(q))));
for(const [error,status,outcome] of [[{code:'40001',message:'request_conflict'},409,'REJECTED'],[{code:'22023'},422,'REJECTED'],[{code:'55000'},503,'REJECTED'],[{code:'42501'},403,undefined],[new Error('unauthorized'),401,undefined],[new Error('network'),503,'UNKNOWN']])
 test(`failure ${error.code??error.message} keeps committed uncertainty explicit`,()=>assert.deepEqual([recordingFailure(error).status,recordingFailure(error).outcome],[status,outcome]));
test('disabled gate has a clear completed-work message and retains a definite SQL rejection',()=>{
 assert.deepEqual(recordingFailure({code:'55000',message:'recording_disabled'}),{status:503,error:'prv3LateDisabled',outcome:'REJECTED'});
});
