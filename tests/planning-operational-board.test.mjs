import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {operationalBoardArgs,collectOperationalBoard} from '../src/utils/planning-operational-board.mjs';
import {maintenanceSlots,maintenanceVisualWindow} from '../src/utils/maintenance-planning-view.mjs';
import {sortedLineSchedule,freeGaps,lineCapacity} from '../src/utils/planning.mjs';
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const start='2026-10-14T00:00:00Z',end='2026-10-21T00:00:00Z',at='2026-10-14T10:00:00Z',expiry='2026-10-14T10:01:00Z';
const scope={factory:id(1),range_start:start,range_end:end,line_id:null,machine:null,domain:'all'};
const row=n=>({kind:'MAINTENANCE',id:id(1000+n),uncertain:false,payload:{request:{id:id(2000+n),factory_id:id(1)},schedule:{id:id(1000+n),maintenance_request_id:id(2000+n),factory_id:id(1),actual_stops:[],line_ids:[id(2)],occupancy:{reserved:true,lineIds:[id(2)],machineIds:[id(3)],productIds:[],start,finish:end}}}});
const data=(all,offset=0,extra={})=>({factory:id(1),start,end,line:null,machine:null,domain:'all',evaluated_at:at,valid_until:expiry,context_hash:'a'.repeat(64),
 active:false,preview_available:true,history_available:true,total:all.length,scope_complete:true,completeness:all.length>100?'INCOMPLETE':'COMPLETE',reason:all.length>100?'PAGES_PENDING':null,
 rows:all.slice(offset,offset+100),has_more:offset+100<all.length,next:offset+100<all.length?{kind:'MAINTENANCE',id:all[offset+99].id}:null,...extra});
const clock=()=>Date.parse(at);
test('601 bounded operational records load in seven snapshot-bound pages; partial callbacks never claim complete',async()=>{
 const all=Array.from({length:601},(_,n)=>row(n)),partial=[],calls=[];let offset=0;
 const result=await collectOperationalBoard(async cursor=>{calls.push(cursor);const value=data(all,offset);offset+=100;return value;},scope,x=>partial.push(x.completeness),clock);
 assert.equal(result.loaded,601);assert.equal(result.completeness,'COMPLETE');assert.equal(calls.length,7);assert.equal(calls[1].after_id,all[99].id);
 assert.deepEqual(partial,Array(6).fill('INCOMPLETE'));assert.equal(result.reservations.length,601);
});
for(const [name,change] of [['factory',d=>({...d,factory:id(9)})],['duplicate',d=>({...d,rows:[d.rows[0],d.rows[0]]})],
 ['missing schedule',d=>({...d,rows:[{...d.rows[0],payload:{request:d.rows[0].payload.request}}]})],['wrong request',d=>({...d,rows:[{...d.rows[0],payload:{...d.rows[0].payload,request:{id:id(9),factory_id:id(1)}}}]})],
 ['false complete page',d=>({...d,completeness:'COMPLETE',total:300})],['unknown disguised complete',d=>({...d,rows:[{...d.rows[0],uncertain:true}]})]])
 test(name+' fails closed',async()=>{await assert.rejects(collectOperationalBoard(async()=>change(data([row(1)])),scope,()=>{},clock),/mpBoard/);});
test('Changing page fingerprints or expiry never merge into a complete board',async()=>{
 const all=Array.from({length:101},(_,n)=>row(n));let n=0;
 await assert.rejects(collectOperationalBoard(async()=>data(all,(n++)*100,{context_hash:n===1?'a'.repeat(64):'b'.repeat(64)}),scope,()=>{},clock),/mpBoardChanged/);
 await assert.rejects(collectOperationalBoard(async()=>data([row(1)]),scope,()=>{},()=>Date.parse(expiry)),/mpBoardChanged/);
});
test('Known scope limit or unknown occupancy remains explicit INCOMPLETE',async()=>{
 for(const page of [data([] ,0,{completeness:'INCOMPLETE',scope_complete:false,total:null,reason:'SCOPE_LIMIT'}),data([row(1)],0,{completeness:'INCOMPLETE',scope_complete:false,reason:'UNKNOWN_OCCUPANCY'})]){
  const result=await collectOperationalBoard(async()=>page,scope,()=>{},clock);assert.equal(result.completeness,'INCOMPLETE');assert.ok(result.reason);
 }
});
test('Range/scope/cursor validation rejects unsafe and duplicated requests',()=>{
 const q=()=>new URLSearchParams({factory:id(1),view:'operational',start,end});assert.equal(operationalBoardArgs(q()).page_size,100);
 for(const patch of [['factory','bad'],['start','2026-10-14'],['end','2026-12-01T00:00:00Z'],['line','other'],['after_kind','MAINTENANCE'],['domain','legacy']]){const p=q();p.set(...patch);assert.throws(()=>operationalBoardArgs(p));}
 const duplicate=q();duplicate.append('factory',id(2));assert.throws(()=>operationalBoardArgs(duplicate));
 const cursor=q();cursor.set('after_kind','MAINTENANCE');cursor.set('after_id',id(3));cursor.set('context_hash','a'.repeat(64));cursor.set('evaluated_at',at);assert.equal(operationalBoardArgs(cursor).after_id,id(3));
});
test('Production Planning uses approved intervals; actual occupancy cannot indefinitely reserve future capacity',()=>{
 const order={id:'P',line_id:'L',status:'active',start_time:start,expected_finish:'2026-10-14T01:00:00Z',operational_occupancy:{start:null,finish:null}};
 const schedule=sortedLineSchedule({id:'L'},[order],[],[]);assert.equal(schedule[0].start,Date.parse(start));assert.equal(schedule[0].finish,Date.parse(order.expected_finish));
 assert.equal(freeGaps(schedule,Date.parse(start),Date.parse(end)).gaps[0].start,Date.parse(order.expected_finish));assert.equal(order.expected_finish,'2026-10-14T01:00:00Z');
 const r={id:'M',lineIds:['L'],machineIds:['C'],productIds:[],start:Date.parse(start),finish:Date.parse(end)};
 assert.equal(maintenanceSlots([r],{id:'L'}).length,1);assert.equal(lineCapacity(sortedLineSchedule({id:'L'},[order],[],[],null,null,'UTC',[r]),Date.parse(start),Date.parse(end)).percent,100);
});
test('Physical actual boundaries remain separate from proposed/approved capacity timestamps',()=>{
 const s={planned_start:'2026-10-14T10:00:00Z',planned_end:'2026-10-14T11:00:00Z',state:'RELEASED',released_at:'2026-10-14T11:10:00Z',actual_stops:[{started_at:'2026-10-14T09:50:00Z',ended_at:'2026-10-14T11:10:00Z'}]};
 const view=maintenanceVisualWindow(s);assert.equal(view.start,Date.parse(s.actual_stops[0].started_at));assert.equal(view.finish,Date.parse(s.released_at));assert.equal(s.planned_start,'2026-10-14T10:00:00Z');
});
const require=createRequire(import.meta.url);
const {NextRequest}=require('next/server');
const plugin={name:'auth-stub',setup(b){b.onResolve({filter:/^@\/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}};
const bundle=(await build({entryPoints:['src/app/api/maintenance-planning/route.ts'],bundle:true,platform:'node',format:'cjs',write:false,packages:'external',plugins:[plugin]})).outputFiles[0].text;
function api(code=null){const calls=[],mod={exports:{}};new Function('require','module','exports',bundle)(n=>n==='fixture:auth'?{
 authenticatedClient:async()=>{if(code==='unauthorized')throw Error('unauthorized');return {db:{rpc:async(name,args)=>{calls.push({name,args});return code?{error:{code}}:{data:data([])}}}};},
 authorize:async()=>{if(code==='denied')throw Error('permission_denied');}}:require(n),mod,mod.exports);return {...mod.exports,calls};}
test('Operational API uses one protected RPC per page and no-store',async()=>{const x=api(),r=await x.GET(new NextRequest('http://localhost/api/maintenance-planning?'+new URLSearchParams({factory:id(1),view:'operational',start,end})));assert.equal(r.status,200);assert.equal(x.calls.length,1);assert.equal(x.calls[0].name,'planning_operational_board');assert.match(r.headers.get('Cache-Control'),/no-store/);});
for(const [code,status] of [['denied',403],['unauthorized',401],['40001',409],['P0002',404],['XX000',503]])
 test('API failure '+code+' reports ERROR without records',async()=>{const r=await api(code).GET(new NextRequest('http://localhost/api/maintenance-planning?'+new URLSearchParams({factory:id(1),view:'operational',start,end})));assert.equal(r.status,status);const b=await r.json();assert.equal(b.completeness,'ERROR');assert.equal(b.rows,undefined);});
test('Operational readers do not alter Preview/Gaps, activation, Loss or execution contracts',async()=>{
 const sql=await readFile(new URL('../supabase/migrations/20261014074140_maintenance_operational_board_v1.sql',import.meta.url),'utf8');
 assert.doesNotMatch(sql,/create (or replace )?function (public\.maintenance_planning_(preview|gaps)|private\.maintenance_occupancy)/i);
 assert.doesNotMatch(sql,/\b(update|insert into|delete from)\b/i);assert.match(sql,/effective_end>a/);
});
