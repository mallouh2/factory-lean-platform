import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
import {recordingFetch} from '../src/utils/production-recording-v3.mjs';
const id='11111111-1111-4111-8111-111111111111',item='22222222-2222-4222-8222-222222222222';
let calls=[],failure=null,signedIn=true;
globalThis.__completionAuth={authenticatedClient:async()=>{if(!signedIn)throw Error('unauthorized');return {db:{rpc:async(name,args)=>{calls.push({name,args});return {data:{item_id:item},error:failure}}}}}};
const compiled=await build({entryPoints:['src/app/api/manufactured-output/route.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'auth',namespace:'test'}));b.onLoad({filter:/.*/,namespace:'test'},()=>({contents:'export function verifyOrigin(r){if(r.headers.get("origin")!==new URL(r.url).origin)throw Error("invalid_origin");} export const {authenticatedClient}=globalThis.__completionAuth;'}));}}]});
const m={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
const body=()=>({command:'revise_manufactured_completion',args:{factory:id,target:item,request_id:id,expected_revision:5,payload:{action:'CANCEL',reason:'Stop unissued recovery','expected_state':{plan_revision:'2',material_revision:'1',status:'planned',line_id:null}}}});
const post=b=>m.exports.POST(new NextRequest('http://127.0.0.1/api/manufactured-output',{method:'POST',headers:{origin:'http://127.0.0.1'},body:JSON.stringify(b)}));
test('cancellation delegates exact immutable UUID and state to authenticated RPC without invented quantity',async()=>{
 calls=[];const b=body(),r=await post(b);assert.equal(r.status,200);assert.deepEqual(calls,[{name:'revise_manufactured_completion',args:b.args}]);assert.equal(r.headers.get('cache-control'),'private, no-store');assert.equal((await r.json()).data.item_id,item);
});
test('change delegates same target and explicit operations; SQL owns successor identity',async()=>{
 calls=[];const b=body();Object.assign(b.args.payload,{action:'CHANGE',choice:'COMPLETE',operations:[id]});assert.equal((await post(b)).status,200);assert.deepEqual(calls[0].args,b.args);assert.equal('successor' in calls[0].args,false);
});
test('invalid UUID, revision, action or context never reaches RPC',async()=>{
 for(const mutate of [b=>b.args.factory='other',b=>b.args.expected_revision=1.5,b=>b.args.target=null,b=>b.args.actor=id,b=>b.args.payload.action='UNDO_ISSUE',b=>b.args.payload.expected_state=[],b=>delete b.args.payload.expected_state]){
  calls=[];const b=body();mutate(b);assert.equal((await post(b)).status,422);assert.equal(calls.length,0);
 }
});
test('missing session and effective permission denial fail closed',async()=>{
 try{signedIn=false;calls=[];assert.equal((await post(body())).status,401);assert.equal(calls.length,0);signedIn=true;failure={code:'42501',message:'permission_denied'};assert.equal((await post(body())).status,403);}finally{signedIn=true;failure=null;}
});
test('stale source, lock and elapsed schedule failures are definitive rejection',async()=>{
 try{for(const message of ['output_revision','planning_locked','planning_already_started','request_conflict']){failure={code:'P0001',message};const r=await post(body());assert.equal(r.status,409);assert.equal((await r.json()).outcome,'REJECTED');}}finally{failure=null;}
});
test('issued, started, dependent and retired work errors retain actionable reason',async()=>{
 try{for(const message of ['output_material_issued','output_work_started','output_work_dependent','output_work_retired']){failure={code:'P0001',message};const r=await post(body()),v=await r.json();assert.equal(r.status,422);assert.equal(v.reason,message);assert.equal(v.outcome,'REJECTED');}}finally{failure=null;}
});
test('unknown transport/server outcome does not pretend the decision was rejected',async()=>{
 try{failure=Error('response lost');const r=await post(body());assert.equal(r.status,503);assert.equal((await r.json()).outcome,'UNKNOWN');}finally{failure=null;}
});
test('retirement receipt transport retains exact nested quantity and revision text',async()=>{
 const r=await recordingFetch(async()=>new Response('{"before":{"work":{"quantity":0.1234567890123456789}},"revision":"9007199254740993"}'))('http://127.0.0.1/rest/v1/rpc/revise_manufactured_completion');
 assert.deepEqual(await r.json(),{before:{work:{quantity:'0.1234567890123456789'}},revision:'9007199254740993'});
});
