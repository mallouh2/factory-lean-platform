import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
import {collectMaintenancePages,maintenanceQueueView,maintenanceOccupancy,maintenanceSlots,maintenanceVisualWindow} from '../src/utils/maintenance-planning-view.mjs';
import {sortedLineSchedule,lineCapacity,freeGaps,proposeSchedule,suggestPlanningSlots,previewPlacement} from '../src/utils/planning.mjs';
const at=Date.parse('2030-01-01T08:00:00Z'),hour=3600000,stamp=n=>new Date(at+n*hour).toISOString();
const schedule={id:'S',state:'CONFIRMED',planned_start:stamp(1),planned_end:stamp(2),hold_started_at:null,actual_hold:false,resources:[{machine_id:'M'},{line_id:'L'}]};
const line={id:'L'},centers=[{id:'M',line_id:'L'}],caps=[{work_center_id:'M',product_id:'P',rate:10,rate_unit:'piece'}];
const order={id:'O',product_id:'P',status:'planned',unit:'piece',target_quantity:10};
test('paged reader includes 100+ rows and rejects duplicate, missing, shifting or oversized pages',async()=>{
 const rows=Array.from({length:123},(_,i)=>({id:String(i)}));
 assert.equal((await collectMaintenancePages(async p=>({total:123,rows:rows.slice((p-1)*50,p*50)}),50)).rows.length,123);
 for(const reader of [async()=>({total:501,rows:[]}),async()=>({total:1,rows:[]}),async()=>({total:2,rows:[{id:'same'},{id:'same'}]}),async p=>({total:p===1?51:50,rows:rows.slice((p-1)*50,p*50)})])
   await assert.rejects(collectMaintenancePages(reader,50),/maintenancePlanningIncomplete/);
});
test('repair lifecycle and real schedule state determine queue views without fake bookings',()=>{
 assert.equal(maintenanceQueueView({status:'OPEN'},null,at),'needs');
 assert.equal(maintenanceQueueView({status:'OPEN'},{...schedule,state:'PROPOSED'},at),'proposed');
 assert.equal(maintenanceQueueView({status:'OPEN'},schedule,at),'confirmed');
 assert.equal(maintenanceQueueView({status:'OPEN'},schedule,at+3*hour),'due');
 assert.equal(maintenanceQueueView({status:'OPEN'},{...schedule,state:'INVALIDATED'},at),'due');
 assert.equal(maintenanceQueueView({status:'IN_PROGRESS'},schedule,at),'progress');
 assert.equal(maintenanceQueueView({status:'COMPLETED'},schedule,at),'completed');
});
test('proposals never reserve, and machine/line resources count once',()=>{
 const occupied=maintenanceOccupancy([schedule,{...schedule,id:'proposal',state:'PROPOSED'}],centers,[],[],at);
 const slots=maintenanceSlots(occupied,line);
 assert.equal(slots.length,1);assert.equal(lineCapacity(slots,at,at+4*hour).bookedMinutes,60);
 assert.deepEqual(freeGaps(slots,at,at+4*hour).gaps,[{start:at,finish:at+hour},{start:at+2*hour,finish:at+4*hour}]);
});
test('capacity union avoids counting production overlap and maintenance twice',()=>{
 const occupied=maintenanceOccupancy([schedule],centers,[],[],at);
 const slots=sortedLineSchedule(line,[{...order,line_id:'L',start_time:stamp(.5),expected_finish:stamp(1.5)}],centers,caps,null,null,'UTC',occupied);
 assert.equal(lineCapacity(slots,at,at+4*hour).bookedMinutes,90);
});
test('holds, missed windows and invalidation retain indefinite capacity; release removes occupancy',()=>{
 for(const s of [{...schedule,actual_hold:true,hold_started_at:stamp(.5)},{...schedule,state:'INVALIDATED'},schedule]) {
  const slots=maintenanceSlots(maintenanceOccupancy([s],centers,[],[],at+3*hour),line);
  assert.equal(slots[0].finish,Infinity);assert.deepEqual(freeGaps(slots,at+3*hour,at+6*hour).gaps,[]);
  assert.equal(lineCapacity(slots,at+3*hour,at+6*hour).bookedMinutes,180);
 }
 assert.deepEqual(maintenanceOccupancy([{...schedule,state:'RELEASED'}],centers,[],[],at),[]);
});
test('independent routing and actual OPEN transfer ownership affect only matching resources',()=>{
 const independent={...schedule,resources:[{machine_id:'I'}]};
 const occupied=maintenanceOccupancy([independent],[...centers,{id:'I',line_id:null}],
  [{alternative_id:'I',order_id:'B',ended_at:null}],[{kind:'work_center',work_center_id:'I',product_id:'P'}],at,[{id:'B',line_id:'BORROW'}]);
 assert.equal(maintenanceSlots(occupied,line).length,0);assert.equal(maintenanceSlots(occupied,line,'P').length,1);
 assert.equal(maintenanceSlots(occupied,{id:'BORROW'}).length,1);assert.equal(maintenanceSlots(occupied,line,'OTHER').length,0);
 const ended=maintenanceOccupancy([independent],[],[{alternative_id:'I',order_id:'B',ended_at:stamp(0)}],[],at,[{id:'B',line_id:'BORROW'}]);
 assert.equal(maintenanceSlots(ended,{id:'BORROW'}).length,0);
});
test('placement, Smart Slot and drag share maintenance occupancy and preserve adjacent half-open boundary',()=>{
 const occupied=maintenanceOccupancy([schedule],centers,[],[],at);
 assert.equal(proposeSchedule(order,line,at+hour,[],centers,caps,at,null,'UTC',occupied).error,'planningOverlap');
 assert.equal(proposeSchedule(order,line,at+2*hour,[],centers,caps,at,null,'UTC',occupied).finish,at+3*hour);
 const suggestion=suggestPlanningSlots(order,{},[line],[],centers,caps,{now:at+hour,maintenance:occupied});
 assert.equal(suggestion.suggestions[0].start,at+2*hour);
 assert.ok(previewPlacement(order,line,at+hour,[],centers,caps,{now:at,from:at,until:at+4*hour,maintenance:occupied}).error);
});
test('overrun drawing extends actual elapsed time while retaining original planned end',()=>{
 const s={...schedule,actual_hold:true,hold_started_at:stamp(1),overrun:true};
 assert.equal(maintenanceVisualWindow(s,at+3*hour).finish,at+3*hour);assert.equal(maintenanceVisualWindow(s,at+3*hour).plannedEnd,at+2*hour);
 assert.equal(s.planned_end,stamp(2));
});
const require=createRequire(import.meta.url),bundle=(await build({entryPoints:['src/app/api/maintenance-planning/route.ts'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'auth-reader-fixture',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}}]})).outputFiles[0].text;
const id='10000000-0000-0000-0000-000000000001';
function api(denied=false,oversized=false) {
 const calls=[],mod={exports:{}};
 new Function('require','module','exports',bundle)(n=>n==='fixture:auth'?{authenticatedClient:async()=>({db:{rpc:async(name,args)=>{
  calls.push({name,args});const rows=name==='maintenance_page'?[{id:'R'}]:[{id:'S',maintenance_request_id:'R'}];
  return {data:{active:false,rows,total:oversized?501:1}};
 }}}),authorize:async()=>{if(denied)throw Error('permission_denied');}}:require(n),mod,mod.exports);
 return {...mod.exports,calls};
}
const request=new NextRequest(`http://localhost/api/maintenance-planning?factory=${id}&view=board`);
test('bounded board API uses only existing protected RPCs and reports missing preview/history explicitly',async()=>{
 const r=api(),response=await r.GET(request);assert.equal(response.status,200);
 const body=await response.json();assert.equal(body.requests.length,1);assert.equal(body.schedules.length,1);
 assert.equal(body.preview_available,false);assert.equal(body.history_available,false);assert.equal(body.active,false);
 assert.deepEqual(r.calls.map(c=>c.name),['maintenance_planning_read','maintenance_page']);assert.match(response.headers.get('Cache-Control'),/no-store/);
});
test('denied and oversized board readers fail closed without disclosure or writes',async()=>{
 const denied=api(true);assert.equal((await denied.GET(request)).status,403);assert.equal(denied.calls.length,0);
 const large=api(false,true),response=await large.GET(request);assert.equal(response.status,503);assert.deepEqual(await response.json(),{error:'maintenancePlanningIncomplete'});
});
