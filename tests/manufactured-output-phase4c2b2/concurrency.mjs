import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
const [bin,port,output]=process.argv.slice(2),q=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.equal(port,'55491');
function sql(text){return new Promise((resolve,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>resolve({code,out:out.trim(),error}));p.stdin.end(text);});}
async function required(s){const r=await sql(s);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const reports=[],pass=s=>{reports.push(s);console.log('PASS '+s);};
async function wait(name,event){for(let n=0;n<200;n++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${q(name)} and ${event==='Lock'?"wait_event_type='Lock'":"wait_event='PgSleep'"})`)==='t')return;await new Promise(r=>setTimeout(r,20));}throw Error('Expected observed '+event+': '+name);}
const actor=id=>`do $$begin perform set_config('request.jwt.claim.sub',${q(id)},true);end$$;set local role authenticated;`;
async function fixture(kind='reduction'){return JSON.parse(await required(`select output4cb2_test.context(${q('Allocated race '+reports.length)},${q(kind)})`));}
const command=(v,body,user=v.owner)=>`begin;${actor(user)}${body};commit;`;
async function cancel(v){await required(cancelSQL(v));v.expected=7;return v;}
const cancelSQL=(v,user=v.owner)=>command(v,`select public.revise_manufactured_completion(${q(v.factory)},${q(v.work.item_id)},${q(JSON.stringify(v.cancel_payload))},6,${q(randomUUID())})`,user);
async function prepared(kind='reduction'){
 const v=await fixture(kind);v.cancel_payload=JSON.parse(await required(`select output4b_test.payload(${q(JSON.stringify(v))},${q(JSON.stringify(v.work))})`));return v;
}
const reconcile=(v,k=randomUUID(),user=v.owner)=>command(v,`select public.reconcile_manufactured_output(${q(v.factory)},${q(v.output)},${q(v.finding)},${q(JSON.stringify({source_lot_id:v.lot,source_location:v.source_location,physical_confirmation:true,identification_note:'The separately identifiable source is physically segregated',reason:'Confirmed stored source correction'}))},${v.expected},${q(k)})`,user);
const issue=v=>command(v,`select public.supply_command(${q(v.factory)},'material_change',${q(JSON.stringify({id:v.work.material_request_id,revision:1,action:'issue',reason:'Controlled issue race'}))},${q(randomUUID())})`);
const publish=v=>command(v,`select public.manufactured_output_command(${q(v.factory)},'QUALITY',${q(v.output)},${q(JSON.stringify(v.new_finding))},${v.expected},${q(randomUUID())})`);
const receive=(v,g,amount,rev)=>command(v,`select public.receive_manufactured_output(${q(v.factory)},${q(v.output)},${q(JSON.stringify({group_id:g,quantity:amount,physical_confirmation:true,location:'Corrected material bay'}))},${rev},${q(randomUUID())})`);
async function race(first,second,expected){
 const name='allocated-'+reports.length,a=sql(first.replace('begin;',`begin;set application_name=${q(name+'a')};`).replace('commit;','select pg_sleep(1.3);commit;'));
 await wait(name+'a','PgSleep');const b=sql(second.replace('begin;',`begin;set application_name=${q(name+'b')};`));await wait(name+'b','Lock');
 const ar=await a;assert.equal(ar.code,0,ar.error);const r=await b;if(expected){assert.notEqual(r.code,0);assert.match(r.error,expected);}else assert.equal(r.code,0,r.error);
}
function deniedFirst(v,sqlText,error){
 const index=sqlText.indexOf('select public.'),body=sqlText.slice(index,sqlText.lastIndexOf(';commit;'));
 return sqlText.slice(0,index)+`select pg_advisory_xact_lock(hashtextextended(${q(v.factory)},0));do $$declare denied boolean:=false;begin begin ${body};exception when raise_exception then if sqlerrm<>${q(error)} then raise;end if;denied:=true;end;if not denied then raise exception 'Expected denial';end if;end$$;commit;`;
}
let v=await prepared();await race(cancelSQL(v),issue(v),/supply_state|supply_conflict|output_work_retired/);
assert.equal(await required(`select warehouse_quantity=10 from public.unfinished_lots where id=${q(v.lot)}`),'t');pass('cancellation winning issue race preserves stored ten');
v=await prepared();await race(deniedFirst(v,issue(v),'output_quality_hold'),cancelSQL(v));pass('held issue attempt cannot beat protected cancellation');
v=await prepared();await race(cancelSQL(v),reconcile(v),/output_revision/);v.expected=7;await required(reconcile(v));pass('cancellation changes revision; stale Warehouse command cannot partially apply');
v=await prepared();await race(deniedFirst(v,reconcile(v),'output_allocation_retirement_required'),cancelSQL(v));pass('Warehouse cannot move allocated stock before separate Planning cancellation');
v=await cancel(await prepared());let key=randomUUID();await race(reconcile(v,key),reconcile(v,key));
assert.equal(await required(`select warehouse_quantity=6 and (select count(*)=1 from private.manufactured_output_adjustments where factory_id=${q(v.factory)}) from public.unfinished_lots where id=${q(v.lot)}`),'t');pass('same UUID concurrent unfinished withdrawal commits once');
v=await cancel(await prepared());await race(reconcile(v),reconcile(v),/output_revision/);pass('distinct UUIDs cannot withdraw same source twice');
v=await cancel(await prepared());v.new_finding=JSON.parse(await required(`select output4cb2_test.finding(${q(JSON.stringify(v))},'reduction')`));await race(reconcile(v),publish(v),/output_revision/);pass('reconciliation winning amendment race rejects stale finding');
v=await cancel(await prepared());v.new_finding=JSON.parse(await required(`select output4cb2_test.finding(${q(JSON.stringify(v))},'reduction')`));await race(publish(v),reconcile(v),/output_revision/);
assert.equal(await required(`select warehouse_quantity=10 from public.unfinished_lots where id=${q(v.lot)}`),'t');pass('new amendment winning race leaves old physical correction unapplied');
v=await cancel(await prepared('split_new'));const r=JSON.parse((await required(reconcile(v))).split('\n').at(-1)),hands=r.handoffs;
await race(receive(v,hands[0].group_id,hands[0].quantity,8),receive(v,hands[1].group_id,hands[1].quantity,8),/output_revision/);
assert.equal(await required(`select (private.output_accounting(${q(v.factory)},${q(v.output)})->>'pending')::boolean`),'t');
await required(receive(v,hands[1].group_id,hands[1].quantity,9));
assert.equal(await required(`select sum(warehouse_quantity)=10 from public.unfinished_lots where factory_id=${q(v.factory)}`),'t');pass('split receipts preserve all ten and hold incomplete sibling until confirmation');
v=await cancel(await prepared());const applied=JSON.parse((await required(reconcile(v))).split('\n').at(-1)),hand=applied.handoffs[0];await required(receive(v,hand.group_id,hand.quantity,8));
const allocate=v=>command(v,`select public.plan_manufactured_completion(${q(v.factory)},${q(v.output)},${q(JSON.stringify({group_id:v.group,quantity:'6',choice:'COMPLETE',operations:[v.step1],reason:'Explicit six after reconciliation'}))},9,${q(randomUUID())})`);
await race(allocate(v),allocate(v),/output_revision|output_allocation_unavailable/);
assert.equal(await required(`select assigned=6 from private.output_work_allocations(${q(v.factory)},${q(v.lot)})`),'t');pass('competing explicit decisions cannot allocate corrected six twice');
async function sale(v){
 return JSON.parse(await required(`do $$begin perform set_config('request.jwt.claim.sub',${q(v.owner)},false);end$$;with so as (insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(${q(v.factory)},${q(v.owner)},${q(v.owner)},0,'approved') returning id),sl as (insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) select ${q(v.factory)},id,${q(v.product)},80,'meter' from so returning id,order_id),s as (select id from public.finished_goods_sources where factory_id=${q(v.factory)}) select jsonb_build_object('line',sl.id,'order',sl.order_id,'source',s.id) from sl cross join s`));
}
async function dispatchFixture(){
 const v=await cancel(await prepared());const s=await sale(v);
 await required(`do $$begin perform set_config('request.jwt.claim.sub',${q(v.owner)},false);perform private.reserve_finished(${q(v.factory)},${q(s.line)},80);perform public.source_stock_command(${q(v.factory)},'identify',${q(JSON.stringify({source:s.source,quantity:'90',label:'Separately identified finished source',physically_identified:true}))},'[]',${q(randomUUID())});end$$;`);
 const r=JSON.parse((await required(reconcile(v))).split('\n').at(-1));return{v,s,hand:r.handoffs[0]};
}
const dispatch=(v,s)=>command(v,`select public.source_stock_command(${q(v.factory)},'dispatch',${q(JSON.stringify({sales_order:s.order,line:s.line}))},${q(JSON.stringify([{source_id:s.source,sales_line_id:s.line,quantity:'80'}]))},${q(randomUUID())})`);
let delivery=await dispatchFixture();await race(receive(delivery.v,delivery.hand.group_id,'4',8),dispatch(delivery.v,delivery.s));
assert.equal(await required(`select on_hand=14 and reserved=0 from public.finished_goods_balances where factory_id=${q(delivery.v.factory)}`),'t');pass('receipt winning Sales dispatch race conserves shipped eighty plus stock fourteen');
delivery=await dispatchFixture();await race(dispatch(delivery.v,delivery.s),receive(delivery.v,delivery.hand.group_id,'4',8));
assert.equal(await required(`select private.output_demand_received(${q(delivery.v.factory)},${q(delivery.v.item)})=94 and (select sum(warehouse_quantity)=6 from public.unfinished_lots where factory_id=${q(delivery.v.factory)})`),'t');pass('Sales dispatch winning receipt race does not double fulfillment or unfinished stock');
v=await cancel(await prepared());await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${q(v.factory)},${q(v.worker)},'warehouse','view'),(${q(v.factory)},${q(v.worker)},'warehouse','edit')`);
const hold=sql(`begin;set application_name='allocated-revoke';select pg_advisory_xact_lock(hashtextextended(${q(v.factory)},0));select pg_sleep(2);commit;`);await wait('allocated-revoke','PgSleep');
const pending=sql(reconcile(v,randomUUID(),v.worker).replace('begin;',"begin;set application_name='allocated-denied';"));await wait('allocated-denied','Lock');
await required(`delete from public.user_permissions where factory_id=${q(v.factory)} and user_id=${q(v.worker)} and module='warehouse' and action='edit'`);assert.equal((await hold).code,0);const denied=await pending;assert.notEqual(denied.code,0);assert.match(denied.error,/permission_denied/);pass('Warehouse permission revoked during observed wait denies adjustment');
await required("create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$");
const off=await sql(reconcile(v));assert.notEqual(off.code,0);assert.match(off.error,/recording_disabled/);
assert.equal(await required('select count(*)=0 from private.manufactured_output_context'),'t');assert.equal(await required('select not exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0)'),'t');pass('shipped gates disabled and contexts cleaned');
await writeFile(join(output,'concurrency-results.json'),JSON.stringify({passed:reports.length,checks:reports},null,2));
