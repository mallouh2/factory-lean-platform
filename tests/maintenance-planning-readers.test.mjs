import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';
import {maintenanceReaderArgs} from '../src/utils/maintenance-planning-readers.mjs';
const id='10000000-0000-0000-0000-000000000001';
const query=(mode='preview',extra={})=>new URLSearchParams({factory:id,request:id,mode,start:'2030-01-01T08:00:00Z',request_revision:'2',schedule_revision:'0',...extra});
test('preview validates exact identifiers, timezone-aware dates and revisions',()=>{
 const r=maintenanceReaderArgs(query());assert.equal(r.args.expected_request_revision,2);assert.equal(r.args.candidate_end,null);
 for(const extra of [{factory:'guess'},{request_revision:'1.5'},{schedule_revision:'-1'},{start:'2030-01-01T08:00'},{end:'2029-01-01T08:00:00Z'},{context_hash:'guess'},{force:'true'}])assert.throws(()=>maintenanceReaderArgs(query('preview',extra)));
});
test('gaps enforce 31 days, 20 results and context-bound cursors',()=>{
 const p=query('gaps',{end:'2030-01-02T08:00:00Z'});assert.equal(maintenanceReaderArgs(p).args.result_limit,10);
 for(const extra of [{end:'2030-02-02T08:00:00Z'},{limit:'21'},{window_minutes:'0'},{after_start:'2030-01-01T09:00:00Z'},{context_hash:'a'.repeat(64),after_start:'2029-12-31T00:00:00Z'}])assert.throws(()=>maintenanceReaderArgs(query('gaps',{end:'2030-01-02T08:00:00Z',...extra})));
});
test('history has bounded descending revision inputs without production parameters',()=>{
 const p=new URLSearchParams({factory:id,request:id,mode:'history',limit:'50',before_revision:'5',through_revision:'8'});
 assert.equal(maintenanceReaderArgs(p).args.page_size,50);p.set('limit','51');assert.throws(()=>maintenanceReaderArgs(p));p.set('limit','25');p.set('start','2030-01-01T00:00:00Z');assert.throws(()=>maintenanceReaderArgs(p));
});
const require=createRequire(import.meta.url),bundle=(await build({entryPoints:['src/app/api/maintenance-planning/route.ts'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'protected-auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}}]})).outputFiles[0].text;
function api({denied=null,error=null,unauth=false,data={binding:false,capacity:'CLEAR',confirmation_available:false}}={}){const mod={exports:{}},calls=[],grants=[];
 new Function('require','module','exports',bundle)(n=>n==='fixture:auth'?{authenticatedClient:async()=>{if(unauth)throw Error('unauthorized');return {db:{rpc:async(name,args)=>{calls.push({name,args});return {data,error};}}};},authorize:async(f,m,a)=>{grants.push([m,a]);if(m===denied)throw Error('permission_denied');}}:require(n),mod,mod.exports);
 return {...mod.exports,calls,grants};}
const req=p=>new NextRequest('http://localhost/api/maintenance-planning?'+p);
test('preview checks all three individual grants and calls only the read RPC',async()=>{
 const r=api(),response=await r.GET(req(query()));assert.equal(response.status,200);assert.deepEqual(r.grants,[['maintenance','view'],['factory','view'],['orders','view']]);assert.equal(r.calls[0].name,'maintenance_planning_preview');assert.match(response.headers.get('Cache-Control'),/no-store/);
 assert.equal((await response.json()).confirmation_available,false);
});
test('history does not require Orders view, gaps do',async()=>{
 const r=api({denied:'orders'});const history=new URLSearchParams({factory:id,request:id,mode:'history'});assert.equal((await r.GET(req(history))).status,200);
 const denied=api({denied:'orders'});assert.equal((await denied.GET(req(query('gaps',{end:'2030-01-02T08:00:00Z'})))).status,403);assert.equal(denied.calls.length,0);
});
test('unauthorized/malformed readers disclose no operational data and invoke no RPC',async()=>{
 for(const denied of ['factory','maintenance','orders']){const r=api({denied});const response=await r.GET(req(query()));assert.equal(response.status,403);assert.equal(r.calls.length,0);assert.deepEqual(await response.json(),{error:'permissionError'});}
 const r=api({unauth:true});assert.equal((await r.GET(req(query()))).status,401);assert.equal(r.calls.length,0);
 const invalid=api();assert.equal((await invalid.GET(req(query('preview',{request:'invalid'})))).status,400);assert.equal(invalid.calls.length,0);
});
test('RPC stale/missing/unavailable errors map to safe status without raw details',async()=>{
 for(const [code,status,key] of [['40001',409,'mpPreviewStale'],['P0002',404,'noResults'],['22008',400,'maintenanceInvalid'],['PGRST202',503,'dataWarning']]){
  const r=api({error:{code,message:'private secret SQL'}}),response=await r.GET(req(query()));assert.equal(response.status,status);assert.deepEqual(await response.json(),{error:key});
 }
});
test('incomplete evaluation remains structured but returns 503 with no suggestions',async()=>{
 const r=api({data:{capacity:'INCOMPLETE',occupancy_complete:false,suggestions:[]}}),response=await r.GET(req(query('gaps',{end:'2030-01-02T08:00:00Z'})));
 assert.equal(response.status,503);const body=await response.json();assert.equal(body.error,'mpIncomplete');assert.deepEqual(body.suggestions,[]);
});
test('new migration preserves command signatures, private scope and disabled activation',()=>{
 const sql=readFileSync('supabase/migrations/20261012085636_maintenance_planning_readers_v1.sql','utf8');
 assert.doesNotMatch(sql,/update\s+private\.maintenance_planning_activation|create.*function public\.maintenance_planning_command/i);
 assert.match(sql,/range_start,range_end,10001/);assert.match(sql,/statement_timestamp\(\)/);assert.match(sql,/prev\.revision=h\.revision-1/);
 assert.match(sql,/revoke all on function private\.maintenance_occupancy/);
});
test('the Planning drawer requires bookable maintenance, capacity proof and activation',()=>{
 const ui=readFileSync('src/features/MaintenancePlanning.tsx','utf8'),readers=readFileSync('src/features/MaintenancePlanningReaders.tsx','utf8');
 assert.match(ui,/maintenanceKindCanBook\(request\)/);assert.doesNotMatch(ui,/MaintenancePlanningReaders|onSubmit=\{saveDetails\}/);assert.match(ui,/disabled=\{busy \|\| !board\.active \|\| !proofCurrent/);
 assert.match(readers,/previewKey===identity&&!preview.loading&&!preview.error&&!expired/);assert.match(readers,/context_hash:preview.data.context_hash/);
 for(const lang of ['en','ar']){const d=JSON.parse(readFileSync(`src/locales/${lang}.json`));for(const key of ['mpCapacity_CLEAR','mpCapacity_BLOCKED','mpCapacity_UNKNOWN','mpCapacity_INCOMPLETE','mpPreviewStale','mpEvidenceMissing'])assert.ok(d[key]);}
});
