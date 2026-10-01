import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';
import {collectHistoryPages,deliverLossReview} from '../src/utils/loss-review-delivery.mjs';
import {calculateProductionLoss,suggestScrapCalibration} from '../src/utils/production-loss-impact.mjs';
const require=createRequire(import.meta.url);
const factory='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const eventId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
async function bundle(path){return (await build({entryPoints:[path],bundle:true,platform:'node',format:'cjs',
  packages:'external',write:false,logLevel:'silent',plugins:[{name:'auth',setup(b){
    b.onResolve({filter:/services\/authorization$/},()=>({path:'test-auth',external:true}));
  }}]})).outputFiles[0].text;}
const auditCode=await bundle('src/app/api/audit-history/route.ts');
const lossCode=await bundle('src/app/api/loss-review/route.ts');
const hookCode=await bundle('src/hooks/useHistoryData.ts');
function load(code,resolve){const m={exports:{}};new Function('require','module','exports',code)(resolve,m,m.exports);return m.exports;}
async function call(code,path,{authError=null,rpc=async()=>({data:{rows:[],total:0,pages:1},error:null})}={}){
  const calls=[];
  const route=load(code,name=>name==='test-auth'?{authenticatedClient:async()=>{
    if(authError)throw authError;
    return {db:{rpc:async(name,args)=>{calls.push({name,args});return rpc(name,args);}}};
  }}:require(name));
  const response=await route.GET(new NextRequest('http://localhost:3000'+path));
  return {status:response.status,headers:response.headers,body:await response.json(),calls};
}
test('audit is factory-scoped, paginated, server-filtered and never cached',async()=>{
  const r=await call(auditCode,`/api/audit-history?factory=${factory}&page=2&search=old%20record`);
  assert.equal(r.status,200);
  assert.deepEqual(r.calls,[{name:'audit_history',args:{factory,page:2,search:'old record'}}]);
  assert.equal(r.headers.get('cache-control'),'private, no-store');
});
test('both history routes distinguish sign-in, permission, timeout and internal errors',async()=>{
  for(const [code,path]of[[auditCode,'audit-history'],[lossCode,'loss-review']]){
    const url=`/api/${path}?factory=${factory}`;
    const expired=await call(code,url,{authError:new Error('unauthorized')});
    assert.equal(expired.status,401);assert.equal(expired.calls.length,0);
    for(const [error,status,key]of[[{code:'42501',message:'SQL detail'},403,'permissionError'],
      [{code:'57014',message:'SQL timeout detail'},503,'dataWarning'],[{code:'XX000'},503,'dataWarning']]){
      const r=await call(code,url,{rpc:async()=>({error})});
      assert.equal(r.status,status);assert.deepEqual(r.body,{error:key});
    }
  }
});
test('invalid factory/event/page are rejected before any history query',async()=>{
  for(const url of ['/api/audit-history?factory=bad',`/api/audit-history?factory=${factory}&page=-1`,
    `/api/loss-review?factory=${factory}&event=bad`,`/api/loss-review?factory=${factory}&page=1.5`]){
    const r=await call(url.includes('audit')?auditCode:lossCode,url);
    assert.equal(r.status,400);assert.equal(r.calls.length,0);
  }
});
test('opening loss event list does not read contexts, actuals or calibration detail',async()=>{
  const r=await call(lossCode,`/api/loss-review?factory=${factory}&page=3`);
  assert.deepEqual(r.calls,[{name:'production_loss_history',args:{factory,kind:'events',event:null,page:3}}]);
});
test('loss detail reads every context page on server and returns no raw context history',async()=>{
  const record={event:{id:eventId,started_at:'2026-09-29T00:00:00Z',ended_at:'2026-09-29T01:00:00Z'},
    actual:null,saved:null,correction:null};
  const r=await call(lossCode,`/api/loss-review?factory=${factory}&event=${eventId}`,{
    rpc:async(_,args)=>({data:args.kind==='detail'?record:args.kind==='observations'?{rows:[],total:0,pages:1}:
      {rows:[{event_id:eventId,id:args.page,captured_at:'2026-09-29T00:00:00Z',context:{}}],total:2,pages:2},error:null})});
  assert.equal(r.status,200);
  assert.deepEqual(r.calls.filter(c=>c.args.kind==='contexts').map(c=>c.args.page),[1,2]);
  assert.equal(r.body.event.id,eventId);assert.ok(r.body.calculation);
  assert.ok(!('contexts'in r.body));assert.ok(!('observations'in r.body));
});
test('missing/changed historical pages fail explicitly instead of silently incomplete calibration',async()=>{
  await assert.rejects(collectHistoryPages(async p=>p===1?{rows:[1],total:2,pages:2}:{rows:[],total:2,pages:2}),/history_changed/);
  await assert.rejects(collectHistoryPages(async p=>p===1?{rows:[1],total:2,pages:2}:{rows:[2],total:3,pages:2}),/history_changed/);
});
test('server delivery equals existing estimate/confidence/calibration calculations and preserves inputs',async()=>{
  const started='2026-09-29T10:00:00Z',ended='2026-09-29T11:00:00Z',now=Date.parse(ended);
  const event={id:eventId,work_center_id:'M',line_id:'L',started_at:started,ended_at:ended,stop_nature:'unplanned'};
  const contexts=[{id:1,event_id:eventId,captured_at:started,context:{
    centers:[{id:'M',line_id:'L',status:'stopped',dependency_mode:'blocking',impact_scope:'whole_line',position:1}],
    stops:[{id:eventId,work_center_id:'M',started_at:started}],transfers:[],alternatives:[],lines:[{id:'L'}],
    orders:[{id:'O',line_id:'L',product_id:'P',status:'planned',start_time:started,expected_finish:ended}],
    products:[{id:'P',unit:'meter'}],capabilities:[{work_center_id:'M',product_id:'P',rate:500,rate_unit:'meter'}],
    profiles:[{work_center_id:'M',product_id:'P',scrap_expected:true,can_defer:false,shutdown_scrap_quantity:4,
      restart_scrap_quantity:6,scrap_unit:'kg'}],recovery_rates:[]}}];
  const estimate=calculateProductionLoss(event,contexts,null,now);
  assert.equal(estimate.readiness,'READY');
  const candidates=Array.from({length:12},(_,i)=>({event:{...event,id:'past-'+i},correction:null,
    saved:{result:estimate},actual:{recorded_at:'2026-09-28T11:00:00Z',scrap_unit:'kg',scrap_quantity:10,
      shutdown_scrap_quantity:4,restart_scrap_quantity:6}}));
  const selected={event,actual:null,saved:null,correction:null};
  const before=structuredClone({selected,candidates,contexts});
  const result=await deliverLossReview(selected,candidates,async id=>{assert.equal(id,eventId);return contexts;},now);
  const comparable=candidates.map(c=>({work_center_id:'M',recorded_at:c.actual.recorded_at,stop_nature:'unplanned',
    planned_activity:undefined,product_id:'P',readiness:'READY',scrap_unit:'kg',estimated_total_scrap:10,
    actual_scrap_quantity:10,actual_shutdown_scrap:4,actual_restart_scrap:6}));
  assert.deepEqual(result.calculation,calculateProductionLoss(event,contexts,null,now,comparable));
  assert.equal(result.calculation.confidence,'HIGH');
  assert.deepEqual(result.suggestions,['shutdown','restart'].map(p=>suggestScrapCalibration(event,estimate,comparable,p)));
  assert.deepEqual({selected,candidates,contexts},before);
});
test('legacy incomplete event, immutable saved result and corrected classification keep their semantics',async()=>{
  const selected={event:{id:eventId,work_center_id:'M',started_at:'2026-09-29T00:00:00Z',ended_at:'2026-09-29T01:00:00Z',stop_nature:'legacy_unknown'},
    correction:{stop_nature:'planned',planned_activity:'cleaning'},actual:{scrap_quantity:4},saved:{result:{assumptions:[],scrap_unit:'kg'}}};
  const result=await deliverLossReview(selected,[],async()=>[],0);
  assert.equal(result.calculation.stop_nature,'planned');assert.equal(result.calculation.readiness,'INCOMPLETE');
  assert.deepEqual(result.saved,selected.saved);assert.deepEqual(result.actual,selected.actual);
});

function hookHarness(){
  const states=[];let index=0;let effect;let cleanup;let deps;
  const hook=load(hookCode,name=>name==='react'?{
    useState:initial=>{const i=index++;if(!(i in states))states[i]=initial;
      return[states[i],next=>{states[i]=typeof next==='function'?next(states[i]):next;}];},
    useEffect:(fn,next)=>{if(!deps||next.some((v,i)=>v!==deps[i])){effect=fn;deps=next;}}
  }:require(name)).useHistoryData;
  return {render(url,revision='now'){index=0;return hook(url,revision);},run(){cleanup?.();cleanup=effect?.();effect=null;},close(){cleanup?.();}};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));
test('history hook loads lazily, masks prior factory/page data, and ignores aborted late replies',async()=>{
  const original=globalThis.fetch;const requests=[];
  try{
    globalThis.fetch=(url,options)=>new Promise(resolve=>requests.push({url,options,resolve}));
    const h=hookHarness();assert.equal(h.render('/audit?factory=A').loading,true);assert.equal(requests.length,0);
    h.run();requests[0].resolve({ok:true,json:async()=>({rows:['A']})});await tick();
    assert.deepEqual(h.render('/audit?factory=A').data,{rows:['A']});
    assert.equal(h.render('/audit?factory=B').data,null);h.run();
    h.render('/audit?factory=C');h.run();assert.equal(requests[1].options.signal.aborted,true);
    requests[2].resolve({ok:true,json:async()=>({rows:['C']})});await tick();
    requests[1].resolve({ok:true,json:async()=>({rows:['B']})});await tick();
    assert.deepEqual(h.render('/audit?factory=C').data,{rows:['C']});h.close();
  }finally{globalThis.fetch=original;}
});
test('local history failure retains its query/retry state and performs no global action',async()=>{
  const original=globalThis.fetch;let calls=0;
  try{
    globalThis.fetch=async()=>({ok:++calls>1,json:async()=>calls===1?{error:'dataWarning'}:{rows:[]}});
    const h=hookHarness();h.render('/audit');h.run();await tick();
    const failed=h.render('/audit');assert.equal(failed.error,'dataWarning');assert.equal(failed.data,null);
    failed.reload();h.render('/audit');h.run();await tick();
    assert.deepEqual(h.render('/audit').data,{rows:[]});assert.equal(h.render('/audit').error,'');h.close();
  }finally{globalThis.fetch=original;}
});
