import fs from 'node:fs';import assert from 'node:assert/strict';import {randomUUID}from'node:crypto';
import {root,sql,rpc,quote as q,claims,contexts,context,payload,activate,revision,save}from'./local.mjs';
const progress=fs.existsSync(root+'/operational-acceptance.json')?JSON.parse(fs.readFileSync(root+'/operational-acceptance.json')):[];
const persist=()=>save('operational-acceptance',progress);
async function step(name,fn){if(progress.some(x=>x.name===name&&x.passed))return;try{const evidence=await fn();progress.push({name,passed:true,evidence});persist();console.log('PASS '+name);}catch(e){progress.push({name,passed:false,error:e.stack});persist();throw e;}}
function denied(fn,pattern){try{fn();assert.fail('Unexpected success');}catch(e){assert.match(e.message,pattern);return e.message;}}
function state(x){return JSON.parse(sql(`select jsonb_build_object('stock',(select coalesce(jsonb_agg(to_jsonb(t)),'[]')from public.finished_goods_balances t where factory_id=${q(x.factory)}),'entries',(select count(*)from public.production_entries where factory_id=${q(x.factory)}),'outputs',(select count(*)from private.manufactured_outputs where factory_id=${q(x.factory)}),'events',(select count(*)from private.manufactured_output_events where factory_id=${q(x.factory)}),'followups',(select count(*)from private.production_quality_followup_events where factory_id=${q(x.factory)}),'movements',(select count(*)from public.finished_goods_movements where factory_id=${q(x.factory)}),'destinations',(select count(*)from private.receipt_warehouses where factory_id=${q(x.factory)}),'lots',(select coalesce(jsonb_agg(to_jsonb(t)),'[]')from public.unfinished_lots t where factory_id=${q(x.factory)}),'contexts',(select count(*)from private.manufactured_output_context where factory_id=${q(x.factory)}))`));}
function factory(name){return context(name+'-'+randomUUID().slice(0,8));}
function setup(name){const x=factory(name);activate(x,true);const p=payload(x),key=randomUUID(),r=rpc(x.owner,'record_manufactured_output',{factory:x.factory,payload:p,request_id:key}),h=JSON.parse(sql(`select to_jsonb(t)from private.manufactured_outputs t where entry_id=${q(r.entry_id)}`));return{x,p,key,r,h};}
function inspect(t,total=100,finished=80,unfinished=15,rejected=5){const groups=t.h.recorded_groups.map(g=>({...g,quantity:g.missing_operations.length?String(unfinished):String(finished),released:g.missing_operations.length?String(unfinished):String(finished)}));const args={factory:t.x.factory,target:t.h.id,operation:'QUALITY',expected_revision:revision(t.h.id),request_id:randomUUID(),payload:{groups,total:String(total),rejected:String(rejected),actual_rejected_kg:String(rejected*.5),reason:'Independent measured Quality determination'}};return {args,result:rpc(t.x.worker,'manufactured_output_command',args),groups};}
const receive=(t,g,quantity,key=randomUUID(),rev=revision(t.h.id))=>{const args={factory:t.x.factory,target:t.h.id,payload:{group_id:g.id,quantity:String(quantity),physical_confirmation:true,warehouse_id:g.missing_operations.length?t.x.unfinished_warehouse:t.x.finished_warehouse},expected_revision:rev,request_id:key};return {args,result:rpc(t.x.viewer,'receive_manufactured_output',args)};};

await step('Hard pause preserves history and immutable actor-bound recovery',()=>{
 const x=contexts().main,before=state(x),saved=Object.fromEntries(JSON.parse(sql('select json_agg(t)from activation_test.requests t')).map(r=>[r.label,r])),first=sql(`select first_activated_at::text from private.manufactured_output_activation where factory_id=${q(x.factory)}`),fresh=payload(x,1,0);
 activate(x,false);
 const options=rpc(x.owner,'manufactured_output_read',{factory:x.factory,mode:'options',target:x.item,page:0});assert.equal(options.activation_state,'PAUSED');assert.equal(options.available,false);
 const quality=rpc(x.owner,'manufactured_output_read',{factory:x.factory,mode:'entry',target:saved.output.args.entry,page:0}),warehouse=rpc(x.viewer,'manufactured_receiving_context',{factory:x.factory,target:saved.output.args.output,page:0});assert.equal(quality.rows.length,1);assert.equal(quality.rows[0].can_inspect,false);assert.equal(quality.write_enabled,false);assert.equal(warehouse.rows.length,1);assert.equal(warehouse.write_enabled,false);
 denied(()=>rpc(x.owner,'record_manufactured_output',{factory:x.factory,payload:fresh,request_id:randomUUID()}),/output_paused/);
 const legacy={...fresh};delete legacy.output_groups;denied(()=>rpc(x.owner,'record_lean_production',{factory:x.factory,payload:legacy,request_id:randomUUID()}),/output_enrollment_required/);
 const recording=rpc(x.owner,'record_manufactured_output',saved.record.args);assert.equal(recording.entry_id,saved.record.result.entry_id);assert.equal(recording.replayed,true);
 assert.deepEqual(rpc(x.viewer,'receive_manufactured_output',saved.receipt.args),saved.receipt.result);
 assert.deepEqual(rpc(x.worker,'manufactured_output_command',saved.quality.args),saved.quality.result);
 denied(()=>rpc(x.owner,'record_manufactured_output',{...saved.record.args,payload:{...saved.record.args.payload,good:91}}),/request_conflict/);
 denied(()=>rpc(x.owner,'receive_manufactured_output',saved.receipt.args),/request_conflict/);
 denied(()=>rpc(x.viewer,'receive_manufactured_output',{...saved.receipt.args,payload:{...saved.receipt.args.payload,quantity:'31'}}),/request_conflict/);
 denied(()=>rpc(x.worker,'manufactured_output_command',{...saved.quality.args,request_id:randomUUID(),expected_revision:revision(saved.output.args.output)}),/output_paused/);
 assert.deepEqual(state(x),before);
 activate(x,true);assert.equal(sql(`select first_activated_at::text from private.manufactured_output_activation where factory_id=${q(x.factory)}`),first);
 denied(()=>rpc(x.owner,'record_lean_production',{factory:x.factory,payload:legacy,request_id:randomUUID()}),/output_enrollment_required/);assert.deepEqual(state(x),before);
 return{firstActivation:first,pausedOptions:options,qualityRows:quality.rows.length,receivingRows:warehouse.rows.length,before,after:state(x)};
});

await step('Legacy credited entries, retries, corrections and acknowledgment coexist',()=>{
 const x=contexts().legacy,p=payload(x,2,0);delete p.output_groups;const key=randomUUID(),record=rpc(x.owner,'record_lean_production',{factory:x.factory,payload:p,request_id:key});
 assert.equal(state(x).stock[0].on_hand,2);activate(x,true);
 assert.equal(rpc(x.owner,'record_lean_production',{factory:x.factory,payload:p,request_id:key}).entry_id,record.entry_id);
 denied(()=>rpc(x.owner,'record_manufactured_output',{factory:x.factory,payload:payload(x,2,0),request_id:key}),/request_conflict/);
 rpc(x.owner,'production_correction_command',{factory:x.factory,operation:'submit',payload:{entry:record.entry_id,good:'3',discarded_quantity:'0',scrap_kg:'0',unfinished:'0',remaining_work:'',reason:'Legacy measured correction retains its posting path',expected_revision:0},request_id:randomUUID()});
 rpc(x.owner,'supply_command',{factory:x.factory,action:'acknowledge_good',payload:{entry:record.entry_id},request_id:randomUUID()});
 assert.equal(state(x).stock[0].on_hand,3);assert.equal(state(x).outputs,0);
 return state(x);
});

await step('Unsupported carryover cannot activate or disappear',()=>{
 const x=factory('carryover'),p=payload(x,1,2);delete p.output_groups;rpc(x.owner,'record_lean_production',{factory:x.factory,payload:p,request_id:randomUUID()});const before=state(x);
 denied(()=>activate(x,true),/output_carryover_unsupported/);assert.deepEqual(state(x),before);assert.equal(rpc(x.owner,'manufactured_output_capability',{factory:x.factory}).activation_state,'NEVER_ACTIVATED');return before;
});

await step('Quality correction before receipt preserves original measurement and has no credit',()=>{
 const t=setup('quality-amend');inspect(t);const r=inspect(t,98,78,15,5);assert.equal(r.result.total,'98');assert.equal(state(t.x).stock.length,0);
 assert.equal(sql(`select good_quantity::text||':'||effective_unfinished::text from public.production_entries where id=${q(t.r.entry_id)}`),'90:10');
 assert.equal(sql(`select quality_measurement_delta::text from public.production_orders where id=${q(t.x.item)}`),'2');return {quality:r.result,state:state(t.x)};
});

await step('Approved Production correction requires reinspection without legacy stock posting',()=>{
 const t=setup('production-correction');inspect(t);
 const r=rpc(t.x.owner,'production_correction_command',{factory:t.x.factory,operation:'submit',payload:{entry:t.r.entry_id,good:'89',discarded_quantity:'0',scrap_kg:'0',unfinished:'10',remaining_work:'Printing remains',reason:'Verified recording correction before physical receipt',expected_revision:0},request_id:randomUUID()});
 assert.equal(r.status,'APPROVED');assert.equal(sql(`select private.output_quality(${q(t.x.factory)},${q(t.h.id)})is null`),'t');assert.equal(state(t.x).stock.length,0);
 assert.equal(sql(`select good_quantity::text||':'||effective_good::text from public.production_entries where id=${q(t.r.entry_id)}`),'90:89');return {correction:r,state:state(t.x)};
});

await step('Permission failures, missing references and factory isolation make no postings',()=>{
 const x=contexts().main,foreign=contexts().foreign,before=state(x),saved=JSON.parse(sql("select args from activation_test.requests where label='receipt'"));
 denied(()=>rpc(x.worker,'receive_manufactured_output',{...saved,request_id:randomUUID()}),/permission_denied/);
 denied(()=>rpc(foreign.owner,'receive_manufactured_output',saved),/permission_denied/);
 denied(()=>rpc(foreign.owner,'manufactured_output_read',{factory:x.factory,mode:'quality',page:0}),/permission_denied/);
 const qualityArgs=JSON.parse(sql("select args from activation_test.requests where label='quality'"));
 denied(()=>rpc(foreign.owner,'manufactured_output_command',qualityArgs),/permission_denied/);
 denied(()=>rpc(foreign.owner,'record_manufactured_output',{factory:x.factory,payload:payload(x,1,0),request_id:randomUUID()}),/permission_denied/);
 denied(()=>rpc(x.owner,'receive_manufactured_output',{...saved,target:randomUUID(),request_id:randomUUID()}),/output_not_found/);
 denied(()=>sql(`begin;set local role service_role;select private.set_manufactured_output_activation(${q(x.factory)},false,3,'Denied API service activation');commit;`),/permission denied/);
 assert.deepEqual(state(x),before);return before;
});

await step('Failure after posting rolls back movement, event and destination; retry commits once',()=>{
 const t=setup('rollback'),qa=inspect(t),g=qa.groups.find(g=>!g.missing_operations.length),key=randomUUID(),rev=revision(t.h.id),p={group_id:g.id,quantity:'10',physical_confirmation:true,warehouse_id:t.x.finished_warehouse},before=state(t.x);
 denied(()=>sql(`begin;${claims(t.x.viewer)}select public.receive_manufactured_output(${q(t.x.factory)},${q(t.h.id)},${q(JSON.stringify(p))},${rev},${q(key)});select 1/0;commit;`),/division by zero/);
 assert.deepEqual(state(t.x),before);const r=receive(t,g,10,key,rev);assert.equal(state(t.x).stock[0].on_hand,10);assert.deepEqual(rpc(t.x.viewer,'receive_manufactured_output',r.args),r.result);assert.equal(state(t.x).destinations,1);return{before,after:state(t.x)};
});

await step('Post-receipt finding and physical reconciliation preserve entitlement and history',()=>{
 const t=setup('reconciliation'),qa=inspect(t),fg=qa.groups.find(g=>!g.missing_operations.length);receive(t,fg,80);
 const oldWip=qa.groups.find(g=>g.missing_operations.length),handoff={id:randomUUID(),quantity:'5',released:'5',missing_operations:[t.x.step]},groups=[{...fg,quantity:'75',released:'75'},oldWip,handoff];
 const finding=rpc(t.x.worker,'manufactured_output_command',{factory:t.x.factory,target:t.h.id,operation:'QUALITY',payload:{groups,rejected:'5',total:'100',actual_rejected_kg:'2.5',reason:'Five received meters need physical Printing reclassification'},expected_revision:revision(t.h.id),request_id:randomUUID()});
 assert.equal(state(t.x).stock[0].on_hand,80);const before=state(t.x),source=sql(`select id from public.finished_goods_sources where entry_id=${q(t.r.entry_id)}`),findingId=sql(`select id from private.manufactured_output_events where factory_id=${q(t.x.factory)}and output_id=${q(t.h.id)}and operation='QUALITY'order by revision desc limit 1`);
 const args={factory:t.x.factory,target:t.h.id,finding:findingId,payload:{source_id:source,physical_confirmation:true,reason:'Warehouse physically separated five meters for Printing'},expected_revision:revision(t.h.id),request_id:randomUUID()};
 denied(()=>rpc(t.x.viewer,'reconcile_manufactured_output',args),/output_stock_unavailable|source_unidentified|output_source_identification_required/);assert.deepEqual(state(t.x),before);
 rpc(t.x.viewer,'source_stock_command',{factory:t.x.factory,operation:'identify',payload:{source,quantity:'80',label:'Isolated inspected finished bundle',physically_identified:true},allocations:[],request_id:randomUUID()});
 args.request_id=randomUUID();const result=rpc(t.x.viewer,'reconcile_manufactured_output',args);assert.equal(state(t.x).stock[0].on_hand,75);
 const partial=receive(t,handoff,2),read=rpc(t.x.viewer,'manufactured_receiving_context',{factory:t.x.factory,target:t.h.id,page:0});assert.equal(read.rows[0].accounting.remaining_handoff,'3');receive(t,handoff,3);
 assert.equal(state(t.x).stock[0].on_hand,75);assert.equal(state(t.x).lots[0].warehouse_quantity,5);assert.equal(rpc(t.x.viewer,'manufactured_receiving_context',{factory:t.x.factory,target:t.h.id,page:0}).rows[0].accounting.pending,false);
 activate(t.x,false);assert.deepEqual(rpc(t.x.viewer,'reconcile_manufactured_output',args),result);assert.deepEqual(rpc(t.x.viewer,'receive_manufactured_output',partial.args),partial.result);return{finding,result,state:state(t.x)};
});

await step('Reserved and dispatched quantities cannot be silently reversed',()=>{
 const t=setup('committed-reversal'),qa=inspect(t),fg=qa.groups.find(g=>!g.missing_operations.length);receive(t,fg,80);
 rpc(t.x.viewer,'source_stock_command',{factory:t.x.factory,operation:'identify',payload:{source:sql(`select id from public.finished_goods_sources where entry_id=${q(t.r.entry_id)}`),quantity:'80',label:'Committed finished bundle',physically_identified:true},allocations:[],request_id:randomUUID()});
 const order=rpc(t.x.owner,'create_sales_order',{factory:t.x.factory,payload:{lines:[{product_id:t.x.product,quantity:25,unit:'meter'}]},request_id:randomUUID()});rpc(t.x.owner,'approve_sales_order',{factory:t.x.factory,sales_order:order,request_id:randomUUID()});
 const source=sql(`select id from public.finished_goods_sources where entry_id=${q(t.r.entry_id)}`),line=sql(`select id from public.sales_order_lines where order_id=${q(order)}`);
 rpc(t.x.viewer,'source_stock_command',{factory:t.x.factory,operation:'reserve',payload:{sales_line_id:line},allocations:[{source_id:source,quantity:'25'}],request_id:randomUUID()});
 rpc(t.x.viewer,'source_stock_command',{factory:t.x.factory,operation:'dispatch',payload:{sales_order:order,line},allocations:[{source_id:source,sales_line_id:line,quantity:'25'}],request_id:randomUUID()});
 const reservedOrder=rpc(t.x.owner,'create_sales_order',{factory:t.x.factory,payload:{lines:[{product_id:t.x.product,quantity:55,unit:'meter'}]},request_id:randomUUID()});rpc(t.x.owner,'approve_sales_order',{factory:t.x.factory,sales_order:reservedOrder,request_id:randomUUID()});
 const reservedLine=sql(`select id from public.sales_order_lines where order_id=${q(reservedOrder)}`);
 rpc(t.x.viewer,'source_stock_command',{factory:t.x.factory,operation:'reserve',payload:{sales_line_id:reservedLine},allocations:[{source_id:source,quantity:'55'}],request_id:randomUUID()});
 const before=state(t.x),groups=[...qa.groups.map(g=>g.missing_operations.length?g:{...g,quantity:'75',released:'75'}),{id:randomUUID(),quantity:'5',released:'5',missing_operations:[t.x.step]}];
 rpc(t.x.worker,'manufactured_output_command',{factory:t.x.factory,target:t.h.id,operation:'QUALITY',payload:{groups,total:'100',rejected:'5',actual_rejected_kg:'2.5',reason:'Do not withdraw committed finished material into Printing'},expected_revision:revision(t.h.id),request_id:randomUUID()});
 const finding=sql(`select id from private.manufactured_output_events where output_id=${q(t.h.id)}and operation='QUALITY'order by revision desc limit 1`);
 denied(()=>rpc(t.x.viewer,'reconcile_manufactured_output',{factory:t.x.factory,target:t.h.id,finding,payload:{source_id:source,physical_confirmation:true,reason:'Unavailable committed stock must not be fabricated'},expected_revision:revision(t.h.id),request_id:randomUUID()}),/output_stock_unavailable|output_reconciliation_unsupported/);
 assert.deepEqual(state(t.x).stock,before.stock);assert.equal(state(t.x).movements,before.movements);return state(t.x);
});
await step('Consumed classified WIP cannot be reversed; paused completion replay is read-only',()=>{
 const t=setup('consumed-reversal'),qa=inspect(t),fg=qa.groups.find(g=>!g.missing_operations.length),wip=qa.groups.find(g=>g.missing_operations.length);receive(t,fg,80);receive(t,wip,15);
 rpc(t.x.owner,'finish_product_item',{factory:t.x.factory,item:t.x.item});
 const args={factory:t.x.factory,target:t.h.id,payload:{group_id:wip.id,quantity:'4',choice:'COMPLETE',operations:[t.x.step],reason:'Complete four physically issued Printing meters'},expected_revision:revision(t.h.id),request_id:randomUUID()},work=rpc(t.x.owner,'plan_manufactured_completion',args);
 rpc(t.x.owner,'plan_product_item',{factory:t.x.factory,item:work.item_id,target_line:t.x.line,planned_start:new Date(Date.now()+180000).toISOString()});
 rpc(t.x.viewer,'supply_command',{factory:t.x.factory,action:'material_change',payload:{id:work.material_request_id,revision:1,action:'issue',reason:'Physically issue four meters to the linked completion'},request_id:randomUUID()});
 if(sql(`select status from public.work_centers where id=${q(t.x.machine)}`)!=='running')rpc(t.x.owner,'change_status',{factory:t.x.factory,work_center:t.x.machine,status:'running'});
 rpc(t.x.owner,'start_product_item',{factory:t.x.factory,item:work.item_id});
 const options=rpc(t.x.owner,'manufactured_output_read',{factory:t.x.factory,mode:'options',target:work.item_id,page:0}),lotId=options.recovery.lot_id;
 assert.ok(lotId);const next={...t.x,item:work.item_id},p={...payload(next,4,0),input_lot:lotId,input_quantity:4};
 rpc(t.x.owner,'record_manufactured_output',{factory:t.x.factory,payload:p,request_id:randomUUID()});
 const lot=JSON.parse(sql(`select to_jsonb(t)from public.unfinished_lots t where id=${q(lotId)}`));assert.equal(lot.quantity_available,11);assert.equal(lot.warehouse_quantity,11);assert.equal(state(t.x).stock[0].on_hand,80);
 const groups=[fg,{...wip,quantity:'10',released:'10'}];rpc(t.x.worker,'manufactured_output_command',{factory:t.x.factory,target:t.h.id,operation:'QUALITY',payload:{groups,total:'100',rejected:'10',actual_rejected_kg:'5',reason:'Consumed physical WIP cannot be retroactively removed'},expected_revision:revision(t.h.id),request_id:randomUUID()});
 const finding=sql(`select id from private.manufactured_output_events where output_id=${q(t.h.id)}and operation='QUALITY'order by revision desc limit 1`),before=state(t.x);
 // The existing reconciliation contract reports unsupported scope for this
 // consumed-lot rewrite. The four consumed meters are genuine protected work.
 denied(()=>rpc(t.x.viewer,'reconcile_manufactured_output',{factory:t.x.factory,target:t.h.id,finding,payload:{source_lot_id:lot.id,source_location:sql(`select location from private.manufactured_output_lots where lot_id=${q(lot.id)}`),identification_note:'Physical remainder after four consumed meters',physical_confirmation:true,reason:'Reject unsupported consumed-lot reversal'},expected_revision:revision(t.h.id),request_id:randomUUID()}),/output_reconciliation_scope/);
 assert.deepEqual(state(t.x),before);activate(t.x,false);assert.deepEqual(rpc(t.x.owner,'plan_manufactured_completion',args),work);assert.deepEqual(state(t.x),before);return {work,lot,state:before};
});
await step('Shared insert boundary rejects old direct RPC/table writes and preserves Scrap-only recording',()=>{
 const x=contexts().main,before=state(x);
 // These historical surfaces are already revoked. Preserve that stronger rule.
 denied(()=>rpc(x.owner,'record_output',{factory:x.factory,work_center:x.machine,production_order:x.item,produced:1,rejected:0,notes:'Old direct client must enroll',request_id:randomUUID()}),/permission denied/);
 const insert=`insert into public.production_entries(factory_id,order_id,produced,rejected,created_by,request_id)values(${q(x.factory)},${q(x.item)},1,0,${q(x.owner)},${q(randomUUID())});`;
 denied(()=>sql(`begin;${claims(x.owner)}${insert}commit;`),/permission denied/);
 // Exercise the additional shared trigger as fixture owner without changing
 // application grants. Legacy version-one rows default good_quantity to zero.
 denied(()=>sql(`begin;${insert}commit;`),/output_enrollment_required/);
 denied(()=>sql(`begin isolation level repeatable read;${insert}commit;`),/output_isolation/);
 assert.deepEqual(state(x),before);
 const p=payload(x,0,0);delete p.output_groups;p.scrap_kg=.5;
 rpc(x.owner,'record_lean_production',{factory:x.factory,payload:p,request_id:randomUUID()});
 const after=state(x);assert.deepEqual(after.stock,before.stock);assert.equal(after.movements,before.movements);assert.equal(after.outputs,before.outputs);assert.equal(after.entries,before.entries+1);
 return{before,after};
});
await step('Legacy correction remains historical; later unsupported carryover processing fails closed',()=>{
 const x=factory('later-carryover'),p=payload(x,2,0);delete p.output_groups;
 const r=rpc(x.owner,'record_lean_production',{factory:x.factory,payload:p,request_id:randomUUID()});activate(x,true);
 rpc(x.owner,'production_correction_command',{factory:x.factory,operation:'submit',payload:{entry:r.entry_id,good:'2',discarded_quantity:'0',scrap_kg:'0',unfinished:'1',remaining_work:'Legacy measured Printing remainder',reason:'Preserve an approved historical legacy correction',expected_revision:0},request_id:randomUUID()});
 const lot=JSON.parse(sql(`select to_jsonb(t)from public.unfinished_lots t where factory_id=${q(x.factory)}`));assert.equal(lot.manufactured_group_id,null);assert.equal(lot.quantity_available,1);const before=state(x),next={...payload(x,1,0),input_lot:lot.id,input_quantity:1};
 // Ordinary V3 work cannot adopt an unlinked recovery input; that existing
 // context check rejects this public request before the storage guard runs.
 const publicDenial=denied(()=>rpc(x.owner,'record_manufactured_output',{factory:x.factory,payload:next,request_id:randomUUID()}),/recording_invalid_context/);
 const storageDenial=denied(()=>sql(`begin;insert into public.production_entries(factory_id,order_id,produced,rejected,created_by,request_id,input_lot_id)values(${q(x.factory)},${q(x.item)},1,0,${q(x.owner)},${q(randomUUID())},${q(lot.id)});commit;`),/output_carryover_unsupported/);
 assert.deepEqual(state(x),before);return{lot,publicDenial,storageDenial,state:before};
});
console.log('Operational safety acceptance complete');
