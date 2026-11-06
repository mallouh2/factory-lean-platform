import assert from 'node:assert/strict';import {randomUUID} from 'node:crypto';import fs from 'node:fs';import path from 'node:path';
import {c,root,quote,sql,rpc,payload,output,revision,audit,step,command,rejects,progress,persist} from './lib.mjs';
import {chromium,login,api,record,inspect,receive,decide,schedule,nav,en} from './browser-lib.mjs';
const x=c.scenarios.A,f=x.factory,browser=await chromium.launch({channel:'msedge',headless:true});
const owner=await login(browser,x,'owner'),quality=await login(browser,x,'worker'),warehouse=await login(browser,x,'viewer');
async function rejected(label,session,name,args,expected){const before=audit(x,'A-negative-before'),r=await api(session,name,args);assert.ok(r.status>=400,label);if(expected)assert.ok(expected.includes(r.body.reason)||expected.includes(r.body.error),JSON.stringify(r.body));const after=audit(x,'A-negative-after');for(const k of ['balance','entries','events','lots','work'])assert.deepEqual(after[k],before[k],label+' changes '+k);progress.safety.push({label,status:r.status,body:r.body});persist();}
try{
 await step('A1 normal preparation, physical Running, guarded Start',async()=>{
  const before=audit(x,'A-zero');assert.equal(before.entries.length,0);assert.equal(before.stored,'0');assert.equal(before.balance?.on_hand||0,0);
  if(sql(`select status from public.work_centers where id=${quote(x.machine)}`)!=='running')command(x.owner,'change_status',{factory:f,work_center:x.machine,status:'running'});
  command(x.owner,'plan_product_item',{factory:f,item:x.item,target_line:x.line,planned_start:new Date(Date.now()+120000).toISOString()});
  const ready=rpc(x.owner,'production_start_readiness',{factory:f,item:x.item});assert.equal(ready.queue_ready,true);assert.equal(ready.physical.ready,true);assert.equal(ready.quality_hold,false);
  command(x.owner,'start_product_item',{factory:f,item:x.item});return {readiness:ready,initial:audit(x,'A-before-record')};
 });
 const initial=await step('A2 browser records 90 finished and 10 Printing unfinished, exact UUID replay',async()=>{
  const r=await record(owner,x.item,90,10),h=output(x,r.data.entry_id);assert.equal(h.item_id,x.item);assert.equal(h.unit,'meter');
  const replay=await api(owner,'record_manufactured_output',r.args);assert.equal(replay.status,200);assert.equal(replay.body.data.entry_id,r.data.entry_id);
  const a=audit(x,'A-recorded');assert.equal(a.entries.length,1);assert.equal(a.finished_movements.length,0);assert.equal(a.stored,'0');assert.equal(a.demand_received,'0');assert.equal(a.entries[0].shift_id,x.shift);assert.equal(a.entries[0].line_id,x.line);assert.equal(a.entries[0].order_id,x.item);
  return {record:r,header:h,finished:h.recorded_groups.find(g=>!g.missing_operations.length).id,unfinished:h.recorded_groups.find(g=>g.missing_operations.length).id};
 });
 await step('A3 server denies uninspected receiving and unauthorized Quality',async()=>{
  await rejected('Uninspected output cannot be received',warehouse,'receive_manufactured_output',{factory:f,target:initial.header.id,payload:{group_id:initial.finished,quantity:'1',physical_confirmation:true,location:'Uninspected denied'},expected_revision:1,request_id:randomUUID()},['output_quality_required']);
  await rejected('Warehouse cannot make a Quality determination',warehouse,'manufactured_output_command',{factory:f,target:initial.header.id,operation:'QUALITY',payload:{groups:initial.header.recorded_groups,rejected:'0',reason:'Denied unauthorized inspection'},expected_revision:1,request_id:randomUUID()},['permissionError']);return true;
 });
 await step('A4 independent Quality inspection, unreleased receipt denial, then release',async()=>{
  const first=revision(x,initial.header.id)>1?{data:progress.requests.find(r=>r.step===progress.current&&r.status==='COMMITTED').result.data}:await inspect(quality,initial.header.id,{releaseWip:false,reason:'Finished 90 verified; unfinished ten awaits final Printing release'});assert.equal(first.data.requires_production_approval,false);
  if(!progress.safety.some(r=>r.label==='Unreleased unfinished cannot be received'))await rejected('Unreleased unfinished cannot be received',warehouse,'receive_manufactured_output',{factory:f,target:initial.header.id,payload:{group_id:initial.unfinished,quantity:'1',physical_confirmation:true,location:'Unreleased denied'},expected_revision:revision(x,initial.header.id),request_id:randomUUID()},['output_receipt_quantity']);
  if(!progress.safety.some(r=>r.label==='Quality cannot perform Warehouse receipt'))await rejected('Quality cannot perform Warehouse receipt',quality,'receive_manufactured_output',{factory:f,target:initial.header.id,payload:{group_id:initial.finished,quantity:'1',physical_confirmation:true,location:'Wrong authority'},expected_revision:revision(x,initial.header.id),request_id:randomUUID()},['permissionError']);
  const second=await inspect(quality,initial.header.id,{releaseWip:true,reason:'Ten meters physically inspected and released as recoverable Printing material'});const a=audit(x,'A-quality-released');assert.equal(a.finished_movements.length,0);assert.equal(a.stored,'0');return second;
 });
 const receipts=await step('A5 Warehouse physically receives 90 finished and 10 unfinished exactly once',async()=>{
  const r=await receive(warehouse,initial.header.id,initial.finished,90,'Finished A');const replay=await api(warehouse,'receive_manufactured_output',r.args);assert.equal(replay.status,200);assert.equal(audit(x,'A-finished-replay').balance.on_hand,90);
  await rejected('Over-receipt cannot add stock',warehouse,'receive_manufactured_output',{factory:f,target:initial.header.id,payload:{group_id:initial.finished,quantity:'1',physical_confirmation:true,location:'Over-receipt denied'},expected_revision:revision(x,initial.header.id),request_id:randomUUID()},['output_receipt_quantity']);
  const u=await receive(warehouse,initial.header.id,initial.unfinished,10,'Printing A');const a=audit(x,'A-initial-received');assert.equal(a.balance.on_hand,90);assert.equal(a.stored,'10');assert.equal(a.demand_received,'90');assert.equal(a.demand_remaining,'10');assert.equal(a.lots.length,1);
  command(x.owner,'finish_product_item',{factory:f,item:x.item});return {finished:r,unfinished:u,lot:a.lots[0].id};
 });
 const work=await step('A6 browser COMPLETE decision and genuine Planning schedule',async()=>{
  const saved=progress.requests.find(v=>v.step===progress.current&&v.name==='plan_manufactured_completion'&&v.status==='COMMITTED');const r=saved?{data:saved.result.data}:await decide(owner,x,'COMPLETE');if(saved)await nav(owner,'planning');const earliest=sql(`select greatest(expected_finish+interval '2 minutes',clock_timestamp()+interval '3 minutes') from public.production_orders where id=${quote(x.item)}`),date=new Date(earliest).toISOString().slice(0,16);await schedule(owner,x,r.data,date);
  const a=audit(x,'A-completion-planned');assert.equal(a.demand_received,'90');assert.equal(a.work.length,1);assert.equal(a.work[0].quantity,10);return r.data;
 });
 await step('A7 Warehouse issue, issued/started cancellation denial and protected Start',async()=>{
  const issueArgs={factory:f,action:'material_change',payload:{id:work.material_request_id,revision:1,action:'issue',reason:'Physically issue ten Printing meters for the linked completion'},request_id:randomUUID()};const r=await api(warehouse,'supply_command',issueArgs,'/api/data');assert.equal(r.status,200,JSON.stringify(r.body));const replay=await api(warehouse,'supply_command',issueArgs,'/api/data');assert.equal(replay.status,200);
  const a=audit(x,'A-issued');assert.equal(a.stored,'0');assert.equal(a.unfinished_remaining,'10');assert.equal(a.consumed,'0');
  function denyCancel(label){const w=rpc(x.owner,'manufactured_completion_context',{factory:f,target:initial.header.id,work_id:work.item_id}).work[0];return rejects(label,()=>rpc(x.owner,'revise_manufactured_completion',{factory:f,target:work.item_id,payload:{action:'CANCEL',reason:'Prove physical work cannot be reversed',expected_state:w.decision_revision.state},expected_revision:Number(w.decision_revision.revision),request_id:randomUUID()}),['output_material_issued','output_work_started']);}
  denyCancel('Cancellation after actual issue denied');const ready=rpc(x.owner,'production_start_readiness',{factory:f,item:work.item_id});assert.equal(ready.queue_ready,true);assert.equal(ready.physical.ready,true);command(x.owner,'start_product_item',{factory:f,item:work.item_id});denyCancel('Cancellation after actual Start denied');
  const bad=payload({...x,item:work.item_id},10);Object.assign(bad,{input_lot:x.other_machine,input_quantity:10});rejects('Invalid recovery source denied',()=>rpc(x.owner,'record_manufactured_output',{factory:f,payload:bad,request_id:randomUUID()}));return {issue:r,readiness:ready};
 });
 const recovered=await step('A8 browser consumes ten once and records ten finished without stock credit',async()=>{
  const r=await record(owner,work.item_id,10,0,10),h=output(x,r.data.entry_id);const replay=await api(owner,'record_manufactured_output',r.args);assert.equal(replay.status,200);assert.equal(replay.body.data.entry_id,r.data.entry_id);
  const a=audit(x,'A-recovery-recorded');assert.equal(a.consumed,'10');assert.equal(a.unfinished_remaining,'0');assert.equal(a.balance.on_hand,90);assert.equal(a.demand_received,'90');assert.equal(a.scrap_kg,'0');
  const again=payload({...x,item:work.item_id},10);Object.assign(again,{input_lot:receipts.lot,input_quantity:10});rejects('New UUID cannot consume exhausted input again',()=>rpc(x.owner,'record_manufactured_output',{factory:f,payload:again,request_id:randomUUID()}));return {record:r,header:h};
 });
 await step('A9 final Quality and physical receipt fulfill original one hundred',async()=>{
  await inspect(quality,recovered.header.id,{reason:'Recovered ten meters passed final finished-product inspection'});const before=audit(x,'A-final-released');assert.equal(before.balance.on_hand,90);assert.equal(before.demand_received,'90');
  const r=await receive(warehouse,recovered.header.id,recovered.header.recorded_groups[0].id,10,'Finished recovered A');const replay=await api(warehouse,'receive_manufactured_output',r.args);assert.equal(replay.status,200);command(x.owner,'finish_product_item',{factory:f,item:work.item_id});
  const a=audit(x,'A-final');assert.equal(a.balance.on_hand,100);assert.equal(a.demand_received,'100');assert.equal(a.demand_remaining,'0');assert.equal(a.unfinished_remaining,'0');assert.equal(a.stored,'0');assert.equal(a.consumed,'10');assert.equal(a.finished_movements.filter(m=>Number(m.stock_delta)>0).length,2);assert.equal(a.contexts,0);
  await warehouse.page.screenshot({path:path.join(root,'A-final.png'),fullPage:true});return {status:'PASS',source:initial.header.id,recovered:recovered.header.id,lot:receipts.lot,work:work.item_id,final:{finished:100,unfinished:0,consumed:10,demand_received:100,remaining:0}};
 });
}catch(e){for(const [i,s]of [owner,quality,warehouse].entries()){fs.writeFileSync(path.join(root,'A-failure-'+i+'.txt'),await s.page.locator('body').innerText());await s.page.screenshot({path:path.join(root,'A-failure-'+i+'.png'),fullPage:true});}throw e;}finally{await browser.close();}
