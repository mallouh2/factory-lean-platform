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
async function fixture(){
 const x=JSON.parse(await required(`select output4_test.context(${q('Finding race '+reports.length)})`));
 const payload={group_id:x.group,quantity:'10',choice:'COMPLETE',operations:[x.step1],reason:'Controlled recovery allocation'};
 const w=JSON.parse((await required(`begin;${actor(x.owner)}select public.plan_manufactured_completion(${q(x.factory)},${q(x.output)},${q(JSON.stringify(payload))},4,${q(randomUUID())});commit;`)).split('\n').at(-1));
 const p=JSON.parse(await required(`select output4c_test.amendment(${q(JSON.stringify(x))},'operations')`));return{x,w,p};
}
const command=(v,body,user=v.x.owner)=>`begin;${actor(user)}${body};commit;`;
const publish=(v,id=randomUUID(),user=v.x.owner)=>command(v,`select public.manufactured_output_command(${q(v.x.factory)},'QUALITY',${q(v.x.output)},${q(JSON.stringify(v.p))},5,${q(id)})`,user);
const issue=v=>command(v,`select public.supply_command(${q(v.x.factory)},'material_change',${q(JSON.stringify({id:v.w.material_request_id,revision:1,action:'issue',reason:'Controlled material issue'}))},${q(randomUUID())})`);
const start=v=>command(v,`select public.start_product_item(${q(v.x.factory)},${q(v.w.item_id)})`);
const plan=v=>command(v,`select public.plan_product_item(${q(v.x.factory)},${q(v.w.item_id)},${q(v.x.line)},date_trunc('day',clock_timestamp())+interval '5 days')`);
async function race(first,second,expected){
 const name='finding-'+reports.length,a=sql(first.replace('begin;',`begin;set application_name=${q(name+'a')};`).replace('commit;','select pg_sleep(1.3);commit;'));
 await wait(name+'a','PgSleep');const b=sql(second.replace('begin;',`begin;set application_name=${q(name+'b')};`));await wait(name+'b','Lock');
 const ar=await a;assert.equal(ar.code,0,ar.error);const r=await b;if(expected){assert.notEqual(r.code,0);assert.match(r.error,expected);}else assert.equal(r.code,0,r.error);
}
let v=await fixture(),key=randomUUID();await race(publish(v,key),publish(v,key));
assert.equal(await required(`select count(*)=2 from private.manufactured_output_events where factory_id=${q(v.x.factory)} and operation='QUALITY'`),'t');pass('same UUID commits exactly one new finding/notification');
v=await fixture();await race(publish(v),publish(v),/output_revision/);pass('competing UUID amendments reject stale source revision');
v=await fixture();await race(publish(v),issue(v),/output_quality_hold/);pass('finding winning issue race prevents movement');
v=await fixture();await race(issue(v),publish(v));
assert.equal(await required(`select quantity_available=10 and warehouse_quantity=0 from public.unfinished_lots where id=${q(v.x.lot)}`),'t');pass('issue winning race preserves physical issue then holds its work');
v=await fixture();await required(plan(v));await required(issue(v));await race(publish(v),start(v),/output_quality_hold/);pass('finding winning Start race blocks stale execution');
v=await fixture();await required(plan(v));await required(issue(v));await race(start(v),publish(v));
assert.equal(await required(`select status='active' from public.production_orders where id=${q(v.w.item_id)}`),'t');
const denied=await sql(command(v,`select public.record_manufactured_output(${q(v.x.factory)},${q(await required(`do $$begin perform set_config('request.jwt.claim.sub',${q(v.x.owner)},false);end$$;select (output2_test.payload(${q(JSON.stringify({...v.x,item:v.w.item_id}))},10)||jsonb_build_object('input_lot',${q(v.x.lot)},'input_quantity',10))::text`))},${q(randomUUID())})`));
assert.notEqual(denied.code,0);assert.match(denied.error,/output_quality_hold/);pass('Start winning race stays historical but subsequent consumption is denied');
async function sales(v){
 const s=JSON.parse(await required(`do $$begin perform set_config('request.jwt.claim.sub',${q(v.x.owner)},false);end$$;select jsonb_build_object('source',output4c_test.identify(${q(JSON.stringify(v.x))}));`));
 const ids=JSON.parse(await required(`with so as (insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(${q(v.x.factory)},${q(v.x.owner)},${q(v.x.owner)},0,'approved') returning id),sl as (insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) select ${q(v.x.factory)},id,${q(v.x.product)},90,'meter' from so returning id,order_id) select jsonb_build_object('line',id,'order',order_id) from sl`));
 await required(`do $$begin perform set_config('request.jwt.claim.sub',${q(v.x.owner)},false);perform private.reserve_finished(${q(v.x.factory)},${q(ids.line)},90);end$$;`);
 return{...s,...ids};
}
const reserve=(v,s)=>command(v,`select public.source_stock_command(${q(v.x.factory)},'reserve',${q(JSON.stringify({sales_line_id:s.line}))},${q(JSON.stringify([{source_id:s.source,quantity:'90'}]))},${q(randomUUID())})`);
const dispatch=(v,s)=>command(v,`select public.source_stock_command(${q(v.x.factory)},'dispatch',${q(JSON.stringify({sales_order:s.order,line:s.line}))},${q(JSON.stringify([{source_id:s.source,sales_line_id:s.line,quantity:'90'}]))},${q(randomUUID())})`);
v=await fixture();let s=await sales(v);v.p=JSON.parse(await required(`select output4c_test.amendment(${q(JSON.stringify(v.x))})`));
await race(reserve(v,s),publish(v));assert.equal(await required(`select quantity=90 from public.finished_goods_source_reservations where source_id=${q(s.source)}`),'t');pass('source reservation winning race retained and held without redistribution');
v=await fixture();s=await sales(v);v.p=JSON.parse(await required(`select output4c_test.amendment(${q(JSON.stringify(v.x))})`));await race(publish(v),reserve(v,s),/output_quality_hold/);pass('finding winning source assignment race rejects held selection');
v=await fixture();s=await sales(v);await required(reserve(v,s));v.p=JSON.parse(await required(`select output4c_test.amendment(${q(JSON.stringify(v.x))})`));await race(publish(v),dispatch(v,s),/output_quality_hold/);pass('finding winning dispatch race rolls back dispatch and reservation release');
v=await fixture();s=await sales(v);await required(reserve(v,s));v.p=JSON.parse(await required(`select output4c_test.amendment(${q(JSON.stringify(v.x))})`));await race(dispatch(v,s),publish(v));
assert.equal(await required(`select on_hand=0 and reserved=0 from public.finished_goods_balances where factory_id=${q(v.x.factory)}`),'t');pass('dispatch winning race remains immutable; finding never restores shipped stock');
async function draft(v){return JSON.parse(await required(`with so as (insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(${q(v.x.factory)},${q(v.x.owner)},${q(v.x.owner)},0,'draft') returning id),sl as (insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) select ${q(v.x.factory)},id,${q(v.x.product)},5,'meter' from so returning id,order_id) select jsonb_build_object('line',id,'order',order_id) from sl`));}
const approve=(v,s)=>command(v,`select public.approve_sales_order(${q(v.x.factory)},${q(s.order)},${q(randomUUID())})`);
v=await fixture();s=await draft(v);v.p=JSON.parse(await required(`select output4c_test.amendment(${q(JSON.stringify(v.x))})`));await race(approve(v,s),publish(v));
assert.equal(await required(`select reserved=5 and on_hand=90 from public.finished_goods_balances where factory_id=${q(v.x.factory)}`),'t');pass('Sales approval winning race preserves its five-unit pooled commitment');
v=await fixture();s=await draft(v);v.p=JSON.parse(await required(`select output4c_test.amendment(${q(JSON.stringify(v.x))})`));await race(publish(v),approve(v,s));
assert.equal(await required(`select reserved=0 and on_hand=90 from public.finished_goods_balances where factory_id=${q(v.x.factory)}`),'t');pass('finding winning Sales approval race prevents new held-stock reservation');
v=await fixture();await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${q(v.x.factory)},${q(v.x.worker)},'quality','view'),(${q(v.x.factory)},${q(v.x.worker)},'quality','edit')`);
const hold=sql(`begin;set application_name='finding-revoke';select pg_advisory_xact_lock(hashtextextended(${q(v.x.factory)},0));select pg_sleep(2);commit;`);await wait('finding-revoke','PgSleep');
const pending=sql(publish(v,randomUUID(),v.x.worker).replace('begin;',"begin;set application_name='finding-denied';"));await wait('finding-denied','Lock');
await required(`delete from public.user_permissions where factory_id=${q(v.x.factory)} and user_id=${q(v.x.worker)} and module='quality' and action='edit'`);assert.equal((await hold).code,0);const no=await pending;assert.notEqual(no.code,0);assert.match(no.error,/permission_denied/);pass('Quality edit revoked during observed lock wait denies publication');
await required("create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$");
const off=await sql(publish(v));assert.notEqual(off.code,0);assert.match(off.error,/recording_disabled/);
assert.equal(await required('select count(*)=0 from private.manufactured_output_context'),'t');pass('shipped disabled behavior and zero leaked transaction contexts');
assert.equal(await required('select not exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0)'),'t');
await writeFile(join(output,'concurrency-results.json'),JSON.stringify({passed:reports.length,checks:reports},null,2));
