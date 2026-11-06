import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {transformSync} from 'esbuild';
import {calculateProductionLoss} from '../src/utils/production-loss-impact.mjs';
const source=await readFile(new URL('../supabase/functions/save-production-loss-estimate/index.ts',import.meta.url),'utf8');
const code=transformSync(source.replace(/import \{ calculateProductionLoss \} from "[^"]+";/,''),{loader:'ts',target:'es2022'}).code;
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const at=n=>new Date(Date.UTC(2026,9,14,10,n)).toISOString();
const input={event:{id:id(2),factory_id:id(1),work_center_id:id(3),line_id:id(4),loss_model_version:1,stop_nature:'planned',planned_activity:'inspection',started_at:at(0),ended_at:at(30)},
 correction:null,actual:null,observations:[],input_hash:'a'.repeat(64),maintenance:{event_id:id(2),machine_id:id(3),operation:'LINK',valid:true,relationship:'PLANNED_MAINTENANCE',approved_start:at(0),approved_end:at(30)},
 samples:[{id:1,event_id:id(2),captured_at:at(0),context:{maintenance_loss_context_version:1,demand_complete:true,routing_steps:[],orders:[],centers:[{id:id(3),line_id:id(4),status:'stopped',dependency_mode:'blocking',impact_scope:'whole_line'}],transfers:[],stops:[],profiles:[],capabilities:[],products:[]}}]};
async function run(mode='',body={factory:id(1),event:id(2)}){
 let handler;const calls=[];
 const Deno={env:{get:key=>({SUPABASE_URL:'https://synthetic.invalid',SUPABASE_ANON_KEY:'synthetic-public',SUPABASE_SERVICE_ROLE_KEY:'synthetic-service'})[key]},serve:h=>handler=h};
 const fetch=async(url,options={})=>{
  const path=new URL(url).pathname;calls.push({path,options});
  if(path==='/auth/v1/user')return Response.json({id:id(5),email_confirmed_at:at(0)});
  if(path.endsWith('/can_access'))return Response.json(mode!=='denied');
  if(path.endsWith('/production_loss_review_inputs')){
   if(mode==='reader-denied')return Response.json({message:'permission_denied'},{status:403});
   const data=structuredClone(input);if(mode==='wrong-scope')data.event.factory_id=id(8);
   if(mode==='missing')data.samples[0].context.demand_complete=false;
   return Response.json(data);
  }
  if(path.endsWith('/persist_production_loss_estimate')){
   if(mode==='stale')return Response.json({message:'loss_estimate_context_mismatch',code:'40001'},{status:400});
   if(mode==='locked')return Response.json({message:'loss_estimate_locked'},{status:400});
   return Response.json(id(6));
  }
  throw Error('Unbounded ledger read attempted');
 };
 new Function('Deno','fetch','calculateProductionLoss',code)(Deno,fetch,calculateProductionLoss);
 const response=await handler(new Request('https://synthetic.invalid/function',{method:'POST',headers:{Authorization:'Bearer synthetic-user', 'Content-Type':'application/json'},body:JSON.stringify(body)}));
 return {status:response.status,body:await response.json(),calls};
}
test('Trusted handler calculates frozen zero-loss from scoped bundle; service key used only for persistence',async()=>{
 const r=await run();assert.equal(r.status,200);assert.deepEqual(r.body,{id:id(6)});
 assert.deepEqual(r.calls.map(x=>x.path),['/auth/v1/user','/rest/v1/rpc/can_access','/rest/v1/rpc/production_loss_review_inputs','/rest/v1/rpc/persist_production_loss_estimate']);
 for(const call of r.calls.slice(0,-1))assert.equal(call.options.headers.apikey,'synthetic-public');
 const saved=JSON.parse(r.calls.at(-1).options.body);assert.equal(saved.actor,id(5));assert.equal(saved.estimate.input_hash,input.input_hash);
 assert.equal(saved.estimate.effective_loss_minutes,0);assert.equal(saved.estimate.approved_maintenance_minutes,30);
 assert.equal(saved.estimate.maintenance_context.event_id,id(2));assert.equal(r.calls.at(-1).options.headers.apikey,'synthetic-service');
});
test('Browser arithmetic is rejected before any input or persistence call',async()=>{
 const r=await run('',{factory:id(1),event:id(2),estimate:{readiness:'READY'}});assert.equal(r.status,400);assert.deepEqual(r.calls,[]);
});
for(const [mode,status,error] of [['denied',403,'permission_denied'],['reader-denied',403,'permission_denied'],['wrong-scope',422,'downtime_not_reviewable'],['missing',422,'loss_estimate_incomplete']])
 test(mode+' cannot invoke trusted persistence',async()=>{const r=await run(mode);assert.equal(r.status,status);assert.equal(r.body.error,error);assert.ok(r.calls.every(x=>!x.path.endsWith('/persist_production_loss_estimate')));});
for(const [mode,error] of [['stale','loss_estimate_context_mismatch'],['locked','loss_estimate_locked']])
 test(mode+' returns explicit HTTP409 without blind retry',async()=>{const r=await run(mode);assert.equal(r.status,409);assert.equal(r.body.error,error);assert.equal(r.calls.filter(x=>x.path.endsWith('/persist_production_loss_estimate')).length,1);});
