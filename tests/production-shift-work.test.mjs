import test from 'node:test';
import assert from 'node:assert/strict';
import {parseShiftWorkQuery,shiftWorkResponse} from '../src/utils/production-shift-work.mjs';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';

const factory='11111111-1111-4111-8111-111111111111';
const cursor={version:1,factory,occurrence:'a'.repeat(64),as_of:'2026-10-18T07:00:00+00:00',revision:1,schedule_revision:2,page_size:50,context:'b'.repeat(64),last_state:1,last_start:'2026-10-18T06:00:00Z',last_id:factory};
const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const query=extra=>new URLSearchParams({factory,...extra});

test('shift work query defaults and opaque cursor preserve full context',()=>{
 assert.deepEqual(parseShiftWorkQuery(query()),{factory,cursor:null,page_size:50});
 assert.deepEqual(parseShiftWorkQuery(query({cursor:encode(cursor)})).cursor,cursor);
 assert.equal(parseShiftWorkQuery(query({page_size:'100'})).page_size,100);
});
for(const [label,value] of [['missing factory',new URLSearchParams()],['invalid factory',query({factory:'other'})],['unknown filter',query({as_of:'yesterday'})],['zero size',query({page_size:'0'})],['oversize',query({page_size:'101'})],['fractional size',query({page_size:'1.5'})],['garbage cursor',query({cursor:'%%%%'})],['incomplete cursor',query({cursor:encode({version:1})})],['wrong factory',query({cursor:encode({...cursor,factory:'22222222-2222-4222-8222-222222222222'})})],['duplicate parameter',new URLSearchParams('factory='+factory+'&factory='+factory)]]) {
 test('shift work rejects '+label,()=>assert.throws(()=>parseShiftWorkQuery(value),e=>e.code==='22023'));
}
test('read response publishes coherent server capability and fails closed on unknown or inconsistent state',()=>{
 const data={contract_version:3,rows:[{late_recording_available:false}],total:1,complete:false,next_cursor:cursor,late_recording_available:false};
 assert.equal(shiftWorkResponse(data).next_cursor,encode(cursor));
 assert.throws(()=>shiftWorkResponse({...data,late_recording_available:true}));
 assert.throws(()=>shiftWorkResponse({...data,rows:[{late_recording_available:true}]}));
 const enabled={...data,available:true,can_edit:true,late_recording_available:true,rows:[{status:'completed',can_record:true,policy_late_eligible:true,late_recording_available:true}]};
 assert.equal(shiftWorkResponse(enabled).rows[0].can_record,true);
 for(const change of [{late_recording_available:null},{can_edit:false},{available:false},{rows:[{...enabled.rows[0],policy_late_eligible:false}]},{rows:[{...enabled.rows[0],status:'active'}]}])
  assert.throws(()=>shiftWorkResponse({...enabled,...change}));
});

// Exercise the actual handler, replacing only the session/database boundary.
let sessionError=null,allowed=true,rpcError=null,calls=[];
const data={contract_version:3,rows:[],total:0,complete:true,next_cursor:null,late_recording_available:false};
globalThis.__shiftWorkTestAuth={
 authenticatedClient:async()=>{if(sessionError)throw Error(sessionError);return {db:{rpc:async(name,args)=>{calls.push([name,args]);return {data,error:rpcError};}}};},
 authorize:async()=>{if(!allowed)throw Error('permission_denied');},
};
const bundle=await build({entryPoints:['src/app/api/production-shift-work/route.ts'],bundle:true,platform:'node',format:'cjs',write:false,packages:'external',logLevel:'silent',
 plugins:[{name:'test-session',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'session',namespace:'test'}));b.onLoad({filter:/.*/,namespace:'test'},()=>({contents:'export const {authenticatedClient,authorize}=globalThis.__shiftWorkTestAuth;'}));}}]});
const mod={exports:{}};new Function('require','module','exports',bundle.outputFiles[0].text)(createRequire(import.meta.url),mod,mod.exports);
const request=()=>new NextRequest('http://localhost/api/production-shift-work?factory='+factory);
test('actual GET is authenticated, factory-scoped, private and read only',async()=>{
 calls=[];const res=await mod.exports.GET(request());assert.equal(res.status,200);assert.equal(res.headers.get('cache-control'),'private, no-store');
 assert.equal((await res.json()).late_recording_available,false);assert.deepEqual(calls,[['production_shift_work',{factory,cursor:null,page_size:50}]]);
});
test('actual GET accepts protected enabled capability without a client activation parameter',async()=>{
 Object.assign(data,{available:true,can_edit:true,late_recording_available:true});
 try{const res=await mod.exports.GET(request());assert.equal(res.status,200);assert.equal((await res.json()).late_recording_available,true);}
 finally{data.late_recording_available=false;delete data.available;delete data.can_edit;}
});
test('actual GET denies missing session before RPC',async()=>{
 sessionError='unauthorized';calls=[];try{assert.equal((await mod.exports.GET(request())).status,401);assert.equal(calls.length,0);}finally{sessionError=null;}
});
test('actual GET denies missing view permission before RPC',async()=>{
 allowed=false;calls=[];try{assert.equal((await mod.exports.GET(request())).status,403);assert.equal(calls.length,0);}finally{allowed=true;}
});
test('actual GET maps SQL denial, stale and unavailable backend without leaking errors',async()=>{
 try{
  rpcError={code:'42501',message:'private details'};let res=await mod.exports.GET(request());assert.equal(res.status,403);assert.doesNotMatch(JSON.stringify(await res.json()),/private details/);
  rpcError={code:'40001'};res=await mod.exports.GET(request());assert.equal(res.status,409);assert.equal((await res.json()).restart,true);
  rpcError={code:'PGRST202'};assert.equal((await mod.exports.GET(request())).status,503);
 }finally{rpcError=null;}
});
