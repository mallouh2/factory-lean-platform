import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';
import {maintenancePlanningCommandValid,maintenancePlanningPermissions} from '../src/utils/maintenance-planning.mjs';
import {maintenanceCommandValid} from '../src/utils/maintenance.mjs';
import {readFileSync} from 'node:fs';
const id='12345678-1234-1234-1234-123456789abc';
const args={factory:id,maintenance_request:id,operation:'propose',payload:{start:'2030-01-01T00:00:00Z'},expected_revision:0,request_id:id};
test('initial scheduling proposal uses revision zero and no caller resource allocation',()=>{
 assert.ok(maintenancePlanningCommandValid(args));
 assert.equal(maintenancePlanningCommandValid({...args,payload:{...args.payload,line_id:id}}),false);
 assert.equal(maintenancePlanningCommandValid({...args,actor:id}),false);
});
test('scheduling rejects invalid operations, revision and forced activation',()=>{
 for(const change of [{operation:'activate'},{operation:'transfer'},{expected_revision:-1},{expected_revision:.5},{payload:[]},{payload:{enabled:true}}])assert.equal(maintenancePlanningCommandValid({...args,...change}),false);
});
test('details and capacity changes reuse the exact per-person grants',()=>{
 assert.deepEqual(maintenancePlanningPermissions('details'),[['maintenance','edit']]);
 for(const op of ['propose','unschedule'])assert.deepEqual(maintenancePlanningPermissions(op),[['maintenance','view'],['orders','edit']]);
});
test('confirmation requires Orders view as well as existing edit permission',()=>{for(const op of ['confirm','reschedule'])assert.deepEqual(maintenancePlanningPermissions(op),[['maintenance','view'],['orders','edit'],['orders','view']]);});

test('new request input preserves MANUAL/DOWNTIME origins without accepting scheduling or physical state',()=>{
 const a={factory:id,request_id:id,payload:{work_center_id:id,title:'Service',priority:'NORMAL',maintenance_kind:'PLANNED',estimated_duration_minutes:30}};
 assert.ok(maintenanceCommandValid('create_maintenance_request',a));
 for(const key of ['state','confirmed_at','status','planned_start','enabled'])assert.equal(maintenanceCommandValid('create_maintenance_request',{...a,payload:{...a.payload,[key]:'forged'}}),false);
});
const require=createRequire(import.meta.url),bundles={};
for(const name of ['data','maintenance-planning'])bundles[name]=(await build({entryPoints:[`src/app/api/${name}/route.ts`],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'local-auth-fixture',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}}]})).outputFiles[0].text;
function route(name,denied){const auth=[],calls=[],mod={exports:{}};
 const db={rpc:async(n,args)=>{calls.push({n,args});return{data:{active:false,rows:[]}};}};
 new Function('require','module','exports',bundles[name])(n=>n==='fixture:auth'?{authenticatedClient:async()=>({db,user:{id}}),verifyOrigin(){},safeError:()=>({error:'error'}),authorize:async(f,m,a)=>{auth.push([m,a]);if(denied?.(m,a))throw Error('permission_denied');}}:require(n),mod,mod.exports);
 return{...mod.exports,auth,calls};}
const post=(r,a)=>r.POST(new NextRequest('http://localhost/api/data',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:'maintenance_planning_command',args:a})}));
test('scheduling POST checks both maintenance view and Orders edit before the RPC',async()=>{
 const r=route('data');assert.equal((await post(r,args)).status,200);
 assert.deepEqual(r.auth,[['factory','view'],['maintenance','view'],['orders','edit']]);assert.equal(r.calls[0].n,'maintenance_planning_command');
});
test('denied scheduling calls return no data and perform no database command',async()=>{
 for(const grant of ['maintenance','orders']){const r=route('data',m=>m===grant);assert.equal((await post(r,args)).status,403);assert.equal(r.calls.length,0);}
});
test('forged command payload is rejected before authorization or RPC',async()=>{
 const r=route('data');assert.equal((await post(r,{...args,payload:{force:true}})).status,400);assert.equal(r.calls.length,0);
});
test('planning reader is protected, paginated and explicitly reports inactive status',async()=>{
 const r=route('maintenance-planning');const response=await r.GET(new NextRequest(`http://localhost/api/maintenance-planning?factory=${id}&page=2`));
 assert.equal(response.status,200);assert.equal((await response.json()).active,false);assert.match(response.headers.get('Cache-Control'),/no-store/);
 assert.deepEqual(r.calls,[{n:'maintenance_planning_read',args:{factory:id,page:2}}]);
 const denied=route('maintenance-planning',()=>true);assert.equal((await denied.GET(new NextRequest(`http://localhost/api/maintenance-planning?factory=${id}`))).status,403);assert.equal(denied.calls.length,0);
});
test('conflict errors are localized in EN and AR',()=>{
 const keys=['maintenancePlanningInactive','maintenanceCapacityReserved','maintenanceProductionConflict','maintenanceUnknownWindow','maintenanceConfigurationUnknown','maintenanceConfigurationChanged','maintenanceTransferUnresolved','maintenanceApprovalRequired','maintenanceEarlyStart','maintenanceLateStart','maintenanceMachineNotReady','maintenanceUnscheduleRequired'];
 for(const lang of ['en','ar']){const d=JSON.parse(readFileSync(`src/locales/${lang}.json`));for(const k of keys)assert.ok(d[k],k);}
});
