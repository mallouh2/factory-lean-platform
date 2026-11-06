import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';
import {maintenancePlanningCommandValid,maintenancePreviewCurrent} from '../src/utils/maintenance-planning.mjs';
const id='10000000-0000-0000-0000-000000000001',hash='a'.repeat(64),now=Date.parse('2030-01-01T00:00:00Z');
const candidate={factory:id,request:id,requestRevision:2,scheduleRevision:1,start:'2030-01-02T00:00:00Z',end:null,timezone:'UTC',now};
const preview={factory_id:id,request_id:id,request_revision:2,schedule_revision:1,start:candidate.start,end:'2030-01-02T00:30:00Z',timezone:'UTC',evaluated_at:'2030-01-01T00:00:00Z',context_hash:hash,capacity:'CLEAR',eligible:true,occupancy_complete:true,scope:{machine_id:id}};
test('confirmation and rescheduling reject missing fingerprint and request revision at API boundary',()=>{
 for(const operation of ['confirm','reschedule']){
  const args={operation,payload:{reason:'Reviewed move',context_hash:hash,request_revision:2},expected_revision:1};
  assert.ok(maintenancePlanningCommandValid(args));
  for(const change of [{context_hash:null},{context_hash:'a'.repeat(32)},{request_revision:0},{request_revision:'2'},{enabled:true}])assert.equal(maintenancePlanningCommandValid({...args,payload:{...args.payload,...change}}),false);
 }
});
test('confirmation-ready state binds factory, request, revisions and exact normalized window',()=>{
 assert.ok(maintenancePreviewCurrent(preview,candidate));
 for(const change of [{factory:'other'},{request:'other'},{requestRevision:3},{scheduleRevision:2},{start:'2030-01-02T01:00:00Z'},{end:'2030-01-02T01:00:00Z'},{timezone:'Asia/Riyadh'}])assert.equal(maintenancePreviewCurrent(preview,{...candidate,...change}),false);
});
test('stale, future, uncertain, blocked, incomplete and malformed responses are never confirmation-ready',()=>{
 for(const change of [{evaluated_at:'2029-12-31T23:58:59Z'},{evaluated_at:'2030-01-01T00:01:00Z'},{capacity:'BLOCKED'},{capacity:'UNKNOWN'},{capacity:'INCOMPLETE'},{eligible:false},{occupancy_complete:false},{context_hash:'guess'},{scope:null},{end:null}])assert.equal(maintenancePreviewCurrent({...preview,...change},candidate),false);
 assert.equal(maintenancePreviewCurrent(null,candidate),false);
});
const require=createRequire(import.meta.url),bundle=(await build({entryPoints:['src/app/api/data/route.ts'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}}]})).outputFiles[0].text;
function route(error,denied){const mod={exports:{}},grants=[],calls=[];new Function('require','module','exports',bundle)(n=>n==='fixture:auth'?{authenticatedClient:async()=>{if(denied==='unauthenticated')throw Error('unauthorized');return ({db:{rpc:async(name,args)=>{calls.push({name,args});return {data:null,error};}},user:{id}});},verifyOrigin(){},safeError:e=>({error:e.message==='unauthorized'?'unauthorized':'permissionError'}),authorize:async(f,m,a)=>{grants.push([m,a]);if(`${m}:${a}`===denied)throw Error('permission_denied');}}:require(n),mod,mod.exports);return {...mod.exports,grants,calls};}
const args={factory:id,maintenance_request:id,operation:'confirm',payload:{context_hash:hash,request_revision:2},expected_revision:1,request_id:id};
const post=(r,a=args)=>r.POST(new NextRequest('http://localhost/api/data',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:'maintenance_planning_command',args:a})}));
test('SQL stale conflict returns HTTP409 with safe structured reason and no raw details',async()=>{
 const r=route({code:'40001',message:'private SQL payload',details:'secret'}),response=await post(r);
 assert.equal(response.status,409);assert.deepEqual(await response.json(),{error:'mpPreviewStale',conflict:'STALE_CONTEXT'});assert.match(response.headers.get('Cache-Control'),/no-store/);
 assert.deepEqual(r.grants,[['factory','view'],['maintenance','view'],['orders','edit'],['orders','view']]);assert.equal(r.calls[0].args.payload.context_hash,hash);
});
test('Orders edit does not substitute for Orders view and denied call invokes no RPC',async()=>{
 const r=route(null,'orders:view'),response=await post(r);assert.equal(response.status,403);assert.deepEqual(await response.json(),{error:'permissionError'});assert.equal(r.calls.length,0);
});
test('Maintenance RPC permission denial is HTTP403 without SQL details',async()=>{
 for(const error of [{code:'42501',message:'private SQL details'},{code:'P0001',message:'permission_denied'}]){
  const response=await post(route(error));assert.equal(response.status,403);assert.deepEqual(await response.json(),{error:'permissionError'});
 }
});
test('authorized Maintenance succeeds and malformed input remains HTTP400 without RPC',async()=>{
 const allowed=route(null);assert.equal((await post(allowed)).status,200);assert.equal(allowed.calls.length,1);
 const invalid=route(null);assert.equal((await post(invalid,{...args,payload:{}})).status,400);assert.equal(invalid.calls.length,0);
});
test('EN/AR preview guidance does not claim disabled confirmation or a completed reservation',()=>{
 for(const lang of ['en','ar']){
  const copy=JSON.parse(readFileSync(`src/locales/${lang}.json`,'utf8'));
  assert.doesNotMatch(copy.mpNonBinding+' '+copy.mpPreviewReady,/disabled|معطل/);
  assert.match(copy.mpNonBinding,lang==='en'?/no reservation has been made/:/لم يتم.*حجز/);
  assert.match(copy.mpPreviewReady,lang==='en'?/checked again/:/مجدداً/);
 }
});
test('forward migration preserves public signature, activation gate, locks and all capacity checks',()=>{
 const sql=readFileSync('supabase/migrations/20261012105338_maintenance_preview_confirmation_v1.sql','utf8');
 assert.doesNotMatch(sql,/update\s+private\.maintenance_planning_activation/i);
 assert.match(sql,/maintenance_planning_command\(factory uuid,maintenance_request uuid,operation text,payload jsonb,\s*expected_revision integer,request_id uuid\)/);
 assert.ok(sql.indexOf('perform private.maintenance_planning_lock(factory)')<sql.indexOf('for update'));
 assert.match(sql,/maintenance_assert_capacity\(factory,m.line_id,null,m.id,a,b,s.id\)/);
 assert.match(sql,/sha256/);assert.match(sql,/open_ownership/);assert.match(sql,/topology/);assert.match(sql,/snapshot_isolation/);
});

test('unauthenticated Maintenance returns401 and factory permission denial returns403 without RPC',async()=>{
 for(const [denied,status]of [['unauthenticated',401],['factory:view',403]]){const r=route(null,denied),response=await post(r);assert.equal(response.status,status);assert.equal(r.calls.length,0);}
});
