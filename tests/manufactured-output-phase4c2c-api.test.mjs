import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
const id='11111111-1111-4111-8111-111111111111';let calls=[],failure=null,signedIn=true;
globalThis.__reconciliationAuth={authenticatedClient:async()=>{if(!signedIn)throw Error('unauthorized');return {db:{rpc:async(name,args)=>{calls.push({name,args});return {data:{output_id:id},error:failure}}}}}};
const compiled=await build({entryPoints:['src/app/api/manufactured-output/route.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'auth',namespace:'test'}));b.onLoad({filter:/.*/,namespace:'test'},()=>({contents:'export function verifyOrigin(r){if(r.headers.get("origin")!==new URL(r.url).origin)throw Error("invalid_origin");} export const {authenticatedClient}=globalThis.__reconciliationAuth;'}));}}]});
const m={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
const body=()=>({command:'reconcile_manufactured_output',args:{factory:id,target:id,finding:id,request_id:id,expected_revision:7,payload:{source_id:id,physical_confirmation:true,reason:'Actual separated source'}}});
const post=b=>m.exports.POST(new NextRequest('http://127.0.0.1/api/manufactured-output',{method:'POST',headers:{origin:'http://127.0.0.1'},body:JSON.stringify(b)}));
test('reconciliation delegates exact actor-independent intent to existing authenticated command',async()=>{
 calls=[];const b=body();assert.equal((await post(b)).status,200);assert.deepEqual(calls,[{name:b.command,args:b.args}]);
});
test('reconciliation rejects client privilege fields, missing finding, fractional revisions and unknown payload fields',async()=>{
 for(const mutate of [b=>b.args.actor=id,b=>delete b.args.finding,b=>b.args.expected_revision=2.5,b=>b.args.payload.skip_hold=true]){calls=[];const b=body();mutate(b);assert.equal((await post(b)).status,422);assert.equal(calls.length,0);}
});
test('stale reconciliation returns actionable definitive rejection',async()=>{
 try{failure={code:'P0001',message:'output_revision'};const r=await post(body());assert.equal(r.status,409);assert.equal((await r.json()).reason,'output_revision');}finally{failure=null;}
});
test('unsupported physical states preserve protected blocker',async()=>{
 try{for(const message of ['output_stock_unavailable','output_material_issued','output_allocation_retirement_required']){failure={code:'P0001',message};const r=await post(body());assert.equal(r.status,422);assert.equal((await r.json()).reason,message);}}finally{failure=null;}
});
test('unauthenticated and unauthorized reconciliation fails closed',async()=>{
 try{signedIn=false;calls=[];assert.equal((await post(body())).status,401);assert.equal(calls.length,0);signedIn=true;failure={code:'42501',message:'permission_denied'};assert.equal((await post(body())).status,403);}finally{signedIn=true;failure=null;}
});
test('unknown response retains retryable outcome instead of claiming failure or success',async()=>{
 try{failure=Error('response lost');const r=await post(body());assert.equal(r.status,503);assert.equal((await r.json()).outcome,'UNKNOWN');}finally{failure=null;}
});
