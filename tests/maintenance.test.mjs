import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {build} from 'esbuild';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {NextRequest} from 'next/server.js';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
import {maintenanceActions,maintenanceCommandValid,maintenanceStates,maintenancePriorities} from '../src/utils/maintenance.mjs';
import {floorSnapshot} from './fixtures/factory-floor.mjs';
const require=createRequire(import.meta.url);
const bundle=async path => (await build({entryPoints:[path],bundle:true,platform:'node',format:'cjs',packages:'external',
 external:['@/services/authorization'],write:false,logLevel:'silent'})).outputFiles[0].text;
const ui=await bundle('src/features/MaintenanceRequest.tsx'),post=await bundle('src/app/api/data/route.ts'),get=await bundle('src/app/api/maintenance/route.ts');
function load(code,resolver=require){const m={exports:{}};new Function('require','module','exports',code)(resolver,m,m.exports);return m.exports;}
const body=load(ui).MaintenanceDetailBody;
const uuid='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a';
const req={id:uuid,code:'MR-0000012',work_center_id:uuid,line_id:uuid,title:'Coupling vibration',description:'Observe under load',
 priority:'URGENT',source:'DOWNTIME',status:'COMPLETED',revision:4,requested_by:'requester',requested_by_name:'Requester',
 requested_at:'2026-10-03T07:00:00Z',assigned_to:'worker',assigned_at:'2026-10-03T07:01:00Z',started_at:'2026-10-03T07:02:00Z',
 completed_at:'2026-10-03T07:03:00Z',completed_by:'worker',completer_name:'Technician',work_note:'Coupling replaced',
 verified_at:null,verified_by:null,verification_result:null,machine_name:'Extruder',machine_name_ar:'الباثق',machine_code:'M-02',
 line_name:'Line 1',line_name_ar:'الخط ١',assignee_name:'Technician',downtime_id:uuid,
 downtime:{id:uuid,started_at:'2026-10-03T06:00:00Z',ended_at:null,reason_name:'Mechanical failure',reason_name_ar:'عطل ميكانيكي'},
 saved_loss:{effective_loss_minutes:90}};
test('assigned employees progress only their own work without manager permissions',()=>{
 assert.deepEqual(maintenanceActions({...req,status:'ASSIGNED'},'worker',false),['start']);
 assert.deepEqual(maintenanceActions({...req,status:'IN_PROGRESS'},'worker',false),['note','complete']);
 for(const status of maintenanceStates)assert.deepEqual(maintenanceActions({...req,status},'unrelated',false),[]);
 assert.deepEqual(maintenanceActions(req,'worker',false),[]);
});
test('manager verification is separate from completion and cannot verify an own repair',()=>{
 assert.ok(maintenanceActions(req,'manager',true).includes('verify'));
 for(const actor of ['worker','completer'])assert.ok(!maintenanceActions({...req,completed_by:'completer'},actor,true).includes('verify'));
 for(const status of ['OPEN','ASSIGNED','IN_PROGRESS'])assert.ok(!maintenanceActions({...req,status},'manager',true).includes('verify'));
 for(const status of ['VERIFIED','CANCELLED'])assert.deepEqual(maintenanceActions({...req,status},'manager',true),[]);
});
test('EN/AR detail renders authoritative source, actor, completion and downtime separately from verification',()=>{
 for(const [lang,dictionary] of [['en',en],['ar',ar]]){
  const snapshot=floorSnapshot();snapshot.factory.timezone='Asia/Qatar';const before=structuredClone(req);
  const html=renderToStaticMarkup(createElement(body,{snapshot,lang,t:key=>dictionary[key]||key,request:req,can:()=>true,command:()=>{throw Error('read only');}}));
  for(const key of ['maintenanceState_COMPLETED','maintenanceAwaitingVerification','maintenanceLinkedDowntime','maintenanceOpenDowntime','maintenanceReadOnly','maintenanceWorkDone'])assert.ok(html.includes(dictionary[key]),key);
  for(const text of ['MR-', 'Coupling replaced','Requester','Mechanical failure'].filter(t=>t!=='MR-' && (lang==='en'||t!=='Mechanical failure')))assert.ok(html.includes(text),text);
  assert.ok(html.includes(lang==='en'?'Extruder':'الباثق'));assert.deepEqual(req,before);
  assert.ok(html.includes(lang==='en'?'1 h 30 min':'١ س ٣٠ د'));
 }
});
test('verified detail records verification identity and note rather than inferring from completion',()=>{
 const html=renderToStaticMarkup(createElement(body,{snapshot:floorSnapshot(),lang:'en',t:key=>en[key]||key,can:()=>true,
  request:{...req,status:'VERIFIED',verified_at:'2026-10-03T07:05:00Z',verifier_name:'Manager',checked_at:'2026-10-03T07:05:00Z',
   checker_name:'Manager',verification_result:'RESOLVED',verification_note:'Stable load trial'}}));
 assert.ok(html.includes('Stable load trial'));assert.ok(html.includes('Manager'));assert.ok(!html.includes(en.maintenanceAwaitingVerification));
});
const valid={factory:uuid,request_id:uuid,payload:{work_center_id:uuid,title:'Repair',priority:'NORMAL'}};
test('command contract rejects browser actors/timestamps/status and arbitrary mutation operations',()=>{
 for(const extra of [{requested_by:'forged'},{created_at:'2000-01-01'},{verified_by:'forged'},{source:'LEAN'},{status:'VERIFIED'}]){
  assert.equal(maintenanceCommandValid('create_maintenance_request',{...valid,payload:{...valid.payload,...extra}}),false);
 }
 assert.equal(maintenanceCommandValid('create_maintenance_request',valid),true);
 assert.equal(maintenanceCommandValid('create_maintenance_request',{...valid,user_id:'forged'}),false);
 assert.equal(maintenanceCommandValid('change_maintenance_request',{...valid,maintenance_request:uuid,operation:'delete',expected_revision:1}),false);
 assert.equal(maintenanceCommandValid('change_maintenance_request',{...valid,maintenance_request:uuid,operation:'start',expected_revision:0,payload:{}}),false);
});
function api({allowed=true,error=null}={}){
 const calls=[],authorizations=[];const context={db:{rpc:async(name,args)=>{calls.push({name,args});return{data:uuid,error};}},user:{id:'authenticated'}};
 const auth={authenticatedClient:async()=>context,authorize:async(f,m,a)=>{authorizations.push([f,m,a]);if(!allowed)throw Error('permission_denied');return context;},
  verifyOrigin:()=>{},safeError:e=>({error:e.message==='permission_denied'?'permissionError':'error'})};
 const resolver=name=>name==='@/services/authorization'?auth:require(name);
 return {calls,authorizations,post:async(command,args)=>load(post,resolver).POST({headers:{get:()=>null},json:async()=>({command,args})}),
  get:async query=>load(get,resolver).GET(new NextRequest(`http://localhost:3000/api/maintenance?${query}`))};
}
test('manual API requires explicit create permission and does not forward forged identity',async()=>{
 const denied=api({allowed:false});assert.equal((await (await denied.post('create_maintenance_request',valid)).json()).error,'permissionError');assert.equal(denied.calls.length,0);
 const forged=api();assert.equal((await forged.post('create_maintenance_request',{...valid,payload:{...valid.payload,requested_by:'forged'}})).status,400);assert.equal(forged.calls.length,0);
 const accepted=api();assert.equal((await accepted.post('create_maintenance_request',valid)).status,200);
 assert.deepEqual(accepted.authorizations,[[uuid,'factory','view'],[uuid,'maintenance','create']]);assert.deepEqual(accepted.calls,[{name:'create_maintenance_request',args:valid}]);
});
test('progress API preserves the assignee authorization path and lets the RPC reject verification',async()=>{
 const args={factory:uuid,maintenance_request:uuid,request_id:uuid,expected_revision:2,operation:'start',payload:{}};
 const accepted=api();assert.equal((await accepted.post('change_maintenance_request',args)).status,200);
 assert.deepEqual(accepted.authorizations,[[uuid,'factory','view']]);assert.deepEqual(accepted.calls,[{name:'change_maintenance_request',args}]);
 const denied=api({error:{code:'42501',message:'permission_denied'}});
 assert.equal((await (await denied.post('change_maintenance_request',{...args,operation:'verify',payload:{result:'RESOLVED',verification_note:'Pass'}})).json()).error,'permissionError');
});
test('dedicated list uses server filters and bounded paging instead of factory_snapshot',async()=>{
 const read=api();const response=await read.get(`factory=${uuid}&status=COMPLETED&priority=URGENT&source=DOWNTIME&mine=true&page=2`);
 assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'private, no-store');
 assert.deepEqual(read.calls,[{name:'maintenance_page',args:{factory:uuid,filters:{status:'COMPLETED',priority:'URGENT',source:'DOWNTIME',mine:'true'},page:2,selected:null,history_page:1}}]);
});
test('machine context and exact downtime readers retain factory scope and reject malformed identifiers',async()=>{
 for(const [query,rpc,key] of [['context_machine','maintenance_machine_context','machine'],['downtime','maintenance_downtime_context','event']]){
  const read=api();assert.equal((await read.get(`factory=${uuid}&${query}=${uuid}`)).status,200);assert.deepEqual(read.calls,[{name:rpc,args:{factory:uuid,[key]:uuid}}]);
 }
 const invalid=api();assert.equal((await invalid.get('factory=forged')).status,400);assert.equal(invalid.calls.length,0);
 const page=api();assert.equal((await page.get(`factory=${uuid}&page=-1`)).status,400);assert.equal(page.calls.length,0);
});
test('page failures stay local and never expose SQL internals',async()=>{
 for(const [code,status,key] of [['42501',403,'permissionError'],['P0002',404,'noResults'],['57014',503,'dataWarning']]){
  const read=api({error:{code,message:'private table detail'}});const response=await read.get(`factory=${uuid}`);
  assert.equal(response.status,status);assert.deepEqual(await response.json(),{error:key});
 }
});
test('all new Maintenance copy, lifecycle and priorities have complete English/Arabic localization',async()=>{
 for(const path of ['Maintenance.tsx','MaintenanceRequest.tsx','DowntimeReference.tsx']){
  const code=await readFile(`src/features/${path}`,'utf8');
  for(const match of code.matchAll(/t\('([^']+)'\)/g))for(const dict of [en,ar])assert.ok(dict[match[1]],`${path}: ${match[1]}`);
 }
 for(const dict of [en,ar])for(const key of [...maintenanceStates.map(s=>'maintenanceState_'+s),...maintenancePriorities.map(p=>'maintenancePriority_'+p)])assert.ok(dict[key]);
});
