import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
import {recordingFetch,exactRecordingPayload} from '../src/utils/production-recording-v3.mjs';
const id='11111111-1111-4111-8111-111111111111',decimal='0.1234567890123456789';
const context={version:3,execution_key:'a'.repeat(64),occurrence_key:'b'.repeat(64),context_hash:'c'.repeat(64),current_shift_quantity_confirmed:true};
async function post({modern=true,string=false,header=false}={}){
 let serialized;globalThis.__precisionDb=async()=>({auth:{getUser:async()=>({data:{user:{id,email_confirmed_at:'2026-01-01'}},error:null})},rpc:async(name,args)=>{if(name==='can_access')return {data:true,error:null};assert.equal(name,'record_lean_production');serialized=JSON.stringify(args.payload);return {data:{outcome:'COMMITTED'},error:null};}});
 const oldOrigin=process.env.APP_ORIGIN;process.env.APP_ORIGIN='http://127.0.0.1:4189';
 try{
  const b=await build({entryPoints:['src/app/api/data/route.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'fixture',setup(t){t.onResolve({filter:/^\.\/supabase$/},a=>a.importer.endsWith('authorization.ts')?{path:'fixture',namespace:'fixture'}:undefined);t.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const supabaseServer=globalThis.__precisionDb;'}));}}]}),m={exports:{}};
  new Function('require','module','exports',b.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
  const payload={unit_kind:'line',production_unit:id,item:id,technician:id,good:1,scrap_kg:0,discarded_quantity:0,...(modern?{recording_context:context}:{})};
  const raw=JSON.stringify({command:'record_lean_production',args:{factory:id,request_id:id,payload}}).replace('"good":1','"good":'+(string?JSON.stringify(decimal):decimal));
  const r=await m.exports.POST(new NextRequest('http://127.0.0.1:4189/api/data',{method:'POST',headers:{origin:process.env.APP_ORIGIN,'Content-Type':'application/json',...(header?{'X-Factory-Recording':'3'}:{})},body:raw}));
  return {status:r.status,serialized};
 }finally{delete globalThis.__precisionDb;if(oldOrigin===undefined)delete process.env.APP_ORIGIN;else process.env.APP_ORIGIN=oldOrigin;}
}
test('actual V3 handler retains exact numeric JSON without changing SQL payload type',async()=>{const r=await post();assert.equal(r.status,200);assert.ok(r.serialized.includes('"good":'+decimal));assert.ok(!r.serialized.includes('"good":"'));});
test('caller quantity strings remain rejected under the existing recording contract',async()=>{const r=await post({string:true});assert.equal(r.status,422);assert.equal(r.serialized,undefined);});
test('unversioned legacy request keeps existing serialization behavior',async()=>{const r=await post({modern:false});assert.equal(r.status,200);assert.ok(r.serialized.includes('"good":0.12345678901234568'));});
test('V3 UI header preserves exact legacy/WIP numeric tokens without adding a late context',async()=>{const r=await post({modern:false,header:true});assert.equal(r.status,200);assert.ok(r.serialized.includes('"good":'+decimal));assert.ok(!r.serialized.includes('recording_context'));});
test('numeric exponent and negative zero reach SQL as numeric tokens after validation',()=>{const raw='{"args":{"payload":{"good":1e-9,"scrap_kg":-0}}}',payload=JSON.parse(raw).args.payload;exactRecordingPayload(raw,payload);assert.equal(JSON.stringify(payload),'{"good":1e-9,"scrap_kg":-0}');});
test('receipt and recovery keep exact quantities and typed protocol versions',async()=>{const fetcher=recordingFetch(async()=>new Response('{"contract_version":3,"outcome":"COMMITTED","receipt":{"contract_version":3,"payload":{"version":1,"good":0.1234567890123456789}},"current":{"scrap_kg":0.1234567890123456789}}'));const r=await (await fetcher('http://127.0.0.1/rest/v1/rpc/production_recording_request_status',{})).json();assert.equal(r.contract_version,3);assert.equal(r.receipt.payload.version,1);assert.equal(r.receipt.payload.good,decimal);assert.equal(r.current.scrap_kg,decimal);});
test('unrelated responses and failed recording RPCs remain untouched',async()=>{const fetcher=recordingFetch(async()=>new Response('{"good":0.1234567890123456789}'));assert.equal(await (await fetcher('http://127.0.0.1/rest/v1/rpc/quality_read',{})).text(),'{"good":0.1234567890123456789}');const denied=recordingFetch(async()=>new Response('{"code":"42501"}',{status:403}));assert.equal((await denied('http://127.0.0.1/rest/v1/rpc/record_lean_production',{})).status,403);});
