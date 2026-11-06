import test from 'node:test';
import assert from 'node:assert/strict';
import {outputGroups} from '../src/utils/manufactured-output.mjs';
import {recordingBody,prepareIntent,confirmReceipt} from '../src/utils/production-recording-intent.mjs';
const id='11111111-1111-4111-8111-111111111111';
const recovery={lot_id:id,input_quantity:'10',discarded_quantity:'10',scrap_kg:'0.75'};

test('all-Scrap recovery has no fabricated output group and independent measured KG',()=>{
 assert.deepEqual(outputGroups('0',[],[],'meter',id,recovery),[]);
 const raw=recordingBody(id,id,{good:'0',unfinished:'0',...recovery,output_groups:[]});
 assert.equal(JSON.parse(raw).command,'record_manufactured_output');
 assert.match(raw,/"scrap_kg":0\.75/);assert.match(raw,/"discarded_quantity":10/);
});
test('empty output remains invalid for ordinary recording or invalid recovery evidence',()=>{
 assert.throws(()=>outputGroups('0',[],[],'meter',id),/prv3EmptyQuantity/);
 for(const bad of [{input_quantity:'0'},{discarded_quantity:'9'},{scrap_kg:'0'},{scrap_kg:''},{scrap_kg:'NaN'},{scrap_kg:'Infinity'},{scrap_kg:'-1'}])
  assert.throws(()=>outputGroups('0',[],[],'meter',id,{...recovery,...bad}));
 assert.throws(()=>outputGroups('0',[],[],'piece',id,{...recovery,input_quantity:'0.5',discarded_quantity:'0.5'}));
});
test('ordinary finished and partial unfinished output contracts are unchanged',()=>{
 assert.deepEqual(outputGroups('10',[],[],'meter',id),[{id,quantity:'10',missing_operations:[]}]);
 assert.deepEqual(outputGroups('0',[{id,quantity:'4',missing_operations:['print']}],[{id:'print'}],'meter',id),[{id,quantity:'4',missing_operations:['print']}]);
});
test('all-Scrap UUID intent and recovery preserve exact measured evidence',()=>{
 const values=new Map(),storage={getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v)};
 const payload={good:'0',unfinished:'0',...recovery,scrap_kg:'0.1234567890123456789',output_groups:[]};
 const intent=prepareIntent(storage,id,id,payload,{request:id});assert.deepEqual(prepareIntent(storage,id,id,payload),intent);
 assert.match(intent.body,/"scrap_kg":0\.1234567890123456789/);
 assert.throws(()=>prepareIntent(storage,id,id,{...payload,scrap_kg:'0.5'}),/prv3Unresolved/);
 assert.equal(confirmReceipt({contract_version:3,outcome:'COMMITTED',entry_id:id,request_id:id},intent),true);
});
