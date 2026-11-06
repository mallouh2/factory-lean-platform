import test from 'node:test';import assert from 'node:assert/strict';
import {recordingBody,prepareIntent} from '../src/utils/production-recording-intent.mjs';
import {recordingFetch} from '../src/utils/production-recording-v3.mjs';
import {outputGroups} from '../src/utils/manufactured-output.mjs';
const id='11111111-1111-4111-8111-111111111111';
test('recovery intent retains exact input, discarded units and independent Scrap KG',()=>{
 const raw=recordingBody(id,id,{good:'0.1234567890123456789',discarded_quantity:'0.1',scrap_kg:'0.05',input_lot:id,input_quantity:'0.2234567890123456789',output_groups:[{id,quantity:'0.1234567890123456789',missing_operations:[]}]});
 assert.match(raw,/"input_quantity":0\.2234567890123456789/);assert.match(raw,/"discarded_quantity":0\.1/);assert.match(raw,/"scrap_kg":0\.05/);assert.equal(JSON.parse(raw).args.payload.input_lot,id);
});
test('unfinished-only output canonicalizes remaining operations without fabricated Good',()=>{
 const rows=outputGroups('0',[{id,quantity:'4',missing_operations:['print','cut']}],[{id:'cut'},{id:'print'}],'meter','unused');
 assert.equal(rows.length,1);assert.equal(rows[0].quantity,'4');assert.deepEqual(rows[0].missing_operations,['cut','print']);
});
test('recovery retry cannot replace retained source or quantity',()=>{
 const map=new Map(),storage={getItem:k=>map.get(k)||null,setItem:(k,v)=>map.set(k,v)},payload={input_lot:id,input_quantity:'4',good:'4',output_groups:[]};
 const one=prepareIntent(storage,id,id,payload,{request:id});assert.deepEqual(prepareIntent(storage,id,id,payload),one);
 assert.throws(()=>prepareIntent(storage,id,id,{...payload,input_quantity:'6'}),/prv3Unresolved/);
});
test('completion reader and writer preserve database numeric precision',async()=>{
 for(const rpc of ['manufactured_completion_read','plan_manufactured_completion']){
 const fetcher=recordingFetch(async()=>new Response('{"quantity":0.1234567890123456789,"available":true}'));
 const r=await fetcher('http://127.0.0.1:4299/rest/v1/rpc/'+rpc);assert.deepEqual(await r.json(),{quantity:'0.1234567890123456789',available:true});
 }
});
