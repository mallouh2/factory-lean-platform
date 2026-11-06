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
async function fixture(withSales=false){return JSON.parse(await required(`select output4cb_test.context(${q('Reconciliation race '+reports.length)},true,5,${withSales?80:0})`));}
const command=(v,body,user=v.owner)=>`begin;${actor(user)}${body};commit;`;
const reconcile=(v,k=randomUUID(),user=v.owner)=>command(v,`select public.reconcile_manufactured_output(${q(v.factory)},${q(v.output)},${q(v.finding)},${q(JSON.stringify({source_id:v.source,physical_confirmation:true,reason:'Actual source selected for reclassification'}))},6,${q(k)})`,user);
const receive=(v,amount,rev,k=randomUUID())=>command(v,`select public.receive_manufactured_output(${q(v.factory)},${q(v.output)},${q(JSON.stringify({group_id:v.handoff,quantity:amount,physical_confirmation:true,location:'Reclassified material bay'}))},${rev},${q(k)})`);
async function race(first,second,expected){
 const name='reconciliation-'+reports.length,a=sql(first.replace('begin;',`begin;set application_name=${q(name+'a')};`).replace('commit;','select pg_sleep(1.3);commit;'));
 await wait(name+'a','PgSleep');const b=sql(second.replace('begin;',`begin;set application_name=${q(name+'b')};`));await wait(name+'b','Lock');
 const ar=await a;assert.equal(ar.code,0,ar.error);const r=await b;if(expected){assert.notEqual(r.code,0);assert.match(r.error,expected);}else assert.equal(r.code,0,r.error);
}
let v=await fixture(),key=randomUUID();await race(reconcile(v,key),reconcile(v,key));
assert.equal(await required(`select on_hand=85 and (select count(*)=1 from private.manufactured_output_events where factory_id=${q(v.factory)} and operation='RECONCILE') from public.finished_goods_balances where factory_id=${q(v.factory)}`),'t');pass('same UUID concurrent reconciliation posts one five-unit withdrawal');
v=await fixture();await race(reconcile(v),reconcile(v),/output_revision/);pass('different UUID competing reconciliation rejects stale attempt');
v=await fixture();await required(reconcile(v));key=randomUUID();await race(receive(v,'2',7,key),receive(v,'2',7,key));
assert.equal(await required(`select quantity_available=2 and warehouse_quantity=2 from public.unfinished_lots where factory_id=${q(v.factory)} and manufactured_group_id=${q(v.handoff)}`),'t');pass('same UUID concurrent handoff receipt credits two exactly once');
await race(receive(v,'3',8),receive(v,'3',8),/output_revision/);
assert.equal(await required(`select sum(warehouse_quantity)=15 from public.unfinished_lots where factory_id=${q(v.factory)}`),'t');pass('competing final handoff receipts cannot duplicate stored stock');
async function sales(v){
 return {line:v.sales_line,order:v.sales_order};
}
const reserve=(v,s)=>command(v,`select public.source_stock_command(${q(v.factory)},'reserve',${q(JSON.stringify({sales_line_id:s.line}))},${q(JSON.stringify([{source_id:v.source,quantity:'80'}]))},${q(randomUUID())})`);
const dispatch=(v,s)=>command(v,`select public.source_stock_command(${q(v.factory)},'dispatch',${q(JSON.stringify({sales_order:s.order,line:s.line}))},${q(JSON.stringify([{source_id:v.source,sales_line_id:s.line,quantity:'80'}]))},${q(randomUUID())})`);
function expectedHold(v,sqlText){
 const body=sqlText.slice(sqlText.indexOf('select public.'),sqlText.lastIndexOf(';commit;'));
 // Keep a lock in the outer test transaction: the denied command's own
 // subtransaction correctly rolls back all of its locks and writes.
 return sqlText.slice(0,sqlText.indexOf('select public.'))+`select pg_advisory_xact_lock(hashtextextended(${q(v.factory)},0));do $$declare denied boolean:=false;begin begin ${body};exception when raise_exception then if sqlerrm<>'output_quality_hold' then raise;end if;denied:=true;end;if not denied then raise exception 'Expected held operation denial';end if;end$$;commit;`;
}
v=await fixture(true);let s=await sales(v);await race(reconcile(v),reserve(v,s));
assert.equal(await required(`select on_hand=85 and reserved=80 from public.finished_goods_balances where factory_id=${q(v.factory)}`),'t');pass('reconciliation winning reservation race leaves eighty committed and five available');
v=await fixture(true);s=await sales(v);await race(expectedHold(v,reserve(v,s)),reconcile(v));
assert.equal(await required(`select count(*)=0 from public.finished_goods_source_reservations where source_id=${q(v.source)}`),'t');pass('source assignment attempted before withdrawal stays denied by original hold');
v=await fixture(true);s=await sales(v);await race(reconcile(v),dispatch(v,s));
assert.equal(await required(`select on_hand=5 and reserved=0 from public.finished_goods_balances where factory_id=${q(v.factory)}`),'t');pass('dispatch after withdrawal can use only the eighty legitimately remaining units');
v=await fixture(true);s=await sales(v);await race(expectedHold(v,dispatch(v,s)),reconcile(v));
assert.equal(await required(`select on_hand=85 and reserved=80 from public.finished_goods_balances where factory_id=${q(v.factory)}`),'t');pass('dispatch before withdrawal remains held and preserves commitments');
const publish=v=>command(v,`select public.manufactured_output_command(${q(v.factory)},'QUALITY',${q(v.output)},${q(JSON.stringify(v.finding_payload))},6,${q(randomUUID())})`);
v=await fixture();await race(reconcile(v),publish(v),/output_revision/);pass('reconciliation winning inspection race invalidates stale amendment');
v=await fixture();await race(publish(v),reconcile(v),/output_revision/);
assert.equal(await required(`select on_hand=90 from public.finished_goods_balances where factory_id=${q(v.factory)}`),'t');pass('new Quality finding winning race prevents obsolete withdrawal');
v=await fixture();await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${q(v.factory)},${q(v.worker)},'warehouse','view'),(${q(v.factory)},${q(v.worker)},'warehouse','edit')`);
const hold=sql(`begin;set application_name='reconcile-revoke';select pg_advisory_xact_lock(hashtextextended(${q(v.factory)},0));select pg_sleep(2);commit;`);await wait('reconcile-revoke','PgSleep');
const pending=sql(reconcile(v,randomUUID(),v.worker).replace('begin;',"begin;set application_name='reconcile-denied';"));await wait('reconcile-denied','Lock');
await required(`delete from public.user_permissions where factory_id=${q(v.factory)} and user_id=${q(v.worker)} and module='warehouse' and action='edit'`);assert.equal((await hold).code,0);const no=await pending;assert.notEqual(no.code,0);assert.match(no.error,/permission_denied/);pass('Warehouse edit revoked during observed lock wait denies physical mutation');
await required("create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$");
const off=await sql(reconcile(v));assert.notEqual(off.code,0);assert.match(off.error,/recording_disabled/);
assert.equal(await required('select count(*)=0 from private.manufactured_output_context'),'t');assert.equal(await required('select not exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0)'),'t');pass('manufactured/late activation disabled and transaction context cleaned');
await writeFile(join(output,'concurrency-results.json'),JSON.stringify({passed:reports.length,checks:reports},null,2));
