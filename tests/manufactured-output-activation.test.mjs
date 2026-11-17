import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
import {recordingFailure} from '../src/utils/production-recording-v3.mjs';
const id='11111111-1111-4111-8111-111111111111';
test('Unsupported carryover explains that physical quantities did not change',()=>assert.deepEqual(recordingFailure({code:'23514',message:'output_carryover_unsupported'}),{status:422,error:'outputCarryoverUnsupported',reason:'output_carryover_unsupported',outcome:'REJECTED'}));
for(const [reason,key]of [['output_paused','outputPaused'],['output_enrollment_required','outputEnrollmentRequired']]){
 test('Definitive admission rejection preserves actionable recovery: '+reason,()=>{
  assert.deepEqual(recordingFailure({code:'55000',message:reason}),{status:409,error:key,reason,outcome:'REJECTED'});
 });
}
for(const path of ['src/app/api/data/route.ts','src/app/api/manufactured-output/route.ts'])for(const [reason,code,status,key]of [['output_paused','55000',409,'outputPaused'],['output_carryover_unsupported','23514',422,'outputCarryoverUnsupported']]){
 test('Actual route returns actionable '+reason+': '+path,async()=>{
  globalThis.__activationDb=async()=>({auth:{getUser:async()=>({data:{user:{id,email_confirmed_at:'2026-01-01'}},error:null})},rpc:async(name)=>name==='can_access'?{data:true,error:null}:{data:null,error:{code,message:reason}}});
  const b=await build({entryPoints:[path],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'local-auth',setup(t){t.onResolve({filter:/^\.\/supabase$/},a=>a.importer.endsWith('authorization.ts')?{path:'fixture',namespace:'fixture'}:undefined);t.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const supabaseServer=globalThis.__activationDb;'}));}}]});
  const m={exports:{}};new Function('require','module','exports',b.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
  const old=process.env.APP_ORIGIN;process.env.APP_ORIGIN='http://127.0.0.1:29670';
  try{
   const manufactured=path.includes('manufactured-output'),body={command:manufactured?'record_manufactured_output':'record_lean_production',args:{factory:id,request_id:id,payload:{unit_kind:'line',production_unit:id,item:id,technician:id,good:1,discarded_quantity:0,scrap_kg:0}}};
   const response=await m.exports.POST(new NextRequest('http://127.0.0.1:29670/api/local',{method:'POST',headers:{origin:process.env.APP_ORIGIN,'Content-Type':'application/json'},body:JSON.stringify(body)}));
   assert.equal(response.status,status);assert.deepEqual(await response.json(),{error:key,reason,outcome:'REJECTED'});
  }finally{if(old===undefined)delete process.env.APP_ORIGIN;else process.env.APP_ORIGIN=old;delete globalThis.__activationDb;}
 });
}
