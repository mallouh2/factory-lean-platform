import assert from 'node:assert/strict';import {randomUUID}from 'node:crypto';import fs from 'node:fs';import path from 'node:path';
import {c,root,sql,quote,rpc,audit,rejects,progress,persist,revision,step}from './lib.mjs';import {chromium,login,api}from './browser-lib.mjs';
const x=c.scenarios.C,f=x.factory,key='C5 physical stock identification and one legitimate reserved Sales meter',sales=progress.steps[key].result;
await step('Safety unfinished lots are not finished Sales stock',async()=>{
 const before=audit(x,'safety-unfinished-before'),lot=before.lots.find(l=>Number(l.quantity_available)===5);assert.ok(lot);assert.equal(lot.warehouse_quantity,5);
 for(const operation of ['reserve','dispatch'])rejects('Unfinished cannot '+operation+' as finished',()=>rpc(x.viewer,'source_stock_command',{factory:f,operation,payload:operation==='reserve'?{sales_line_id:sales.sales_line}:{sales_order:sales.sales_order,line:sales.sales_line},allocations:[{source_id:lot.id,sales_line_id:sales.sales_line,quantity:'1'}],request_id:randomUUID()}),['source_unavailable']);
 const after=audit(x,'safety-unfinished-after');for(const k of ['balance','finished_movements','unfinished_movements','entries','lots','work'])assert.deepEqual(after[k],before[k]);assert.equal(sql(`select quantity from public.finished_goods_source_reservations where factory_id=${quote(f)} and source_id=${quote(sales.source)}`),'1');assert.equal(sql(`select dispatched_quantity from public.sales_order_lines where id=${quote(sales.sales_line)}`),'0');return {reserve:'source_unavailable',dispatch:'source_unavailable',reservationUnchanged:true};
});
const browser=await chromium.launch({channel:'msedge',headless:true});try{
 await step('Safety cross-factory read and write denials disclose no data',async()=>{
 const a=c.scenarios.A,b=c.scenarios.B,session=await login(browser,a,'viewer'),target=audit(b,'cross-B-before').outputs[0];const before=audit(b,'cross-before');
 const read=await session.page.evaluate(async({factory,target})=>{const r=await fetch('/api/manufactured-output?'+new URLSearchParams({factory,mode:'receiving',target}));return {status:r.status,body:await r.json()};},{factory:b.factory,target:target.id});assert.equal(read.status,403);assert.equal(read.body.rows,undefined);
 const write=await api(session,'receive_manufactured_output',{factory:b.factory,target:target.id,payload:{group_id:target.recorded_groups[0].id,quantity:'1',physical_confirmation:true,location:'Cross-factory denied'},expected_revision:revision(b,target.id),request_id:randomUUID()});assert.equal(write.status,403);assert.equal(write.body.data,undefined);
 const foreign=await api(session,'receive_manufactured_output',{factory:a.factory,target:target.id,payload:{group_id:target.recorded_groups[0].id,quantity:'1',physical_confirmation:true,location:'Foreign target denied'},expected_revision:revision(b,target.id),request_id:randomUUID()});assert.ok(foreign.status>=400);assert.equal(foreign.body.data,undefined);const after=audit(b,'cross-after');for(const k of ['balance','entries','events','lots','work','finished_movements'])assert.deepEqual(after[k],before[k]);fs.writeFileSync(path.join(root,'cross-factory-http.json'),JSON.stringify({read,write,foreign},null,2));return {read,write,foreign};
 });
}finally{await browser.close();}
persist();console.log('Safety results recorded; no authorized stock changes in this check.');
