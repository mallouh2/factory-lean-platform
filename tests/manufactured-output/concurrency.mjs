import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
const [bin,port,output]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.match(port,/^\d{4,5}$/);
function sql(text){return new Promise((done,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1']);let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>done({code,out:out.trim(),error}));p.stdin.end(text);});}
async function required(text){const r=await sql(text);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const actor=x=>`select set_config('request.jwt.claim.sub',${quote(x.owner)},false);select set_config('request.jwt.claim.role','authenticated',false);`;
const reports=[];
function pass(s){reports.push(s);console.log('PASS '+s);}
async function fixture(label){return JSON.parse(await required(`select output_test.fixture(${quote(label)})`));}
const quality=x=>({groups:[{id:x.g1,quantity:'100',released:'100',missing_operations:[]}],rejected:'0',reason:'Inspected locally'});
async function release(x){await required(`${actor(x)}set role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(x.output)},${quote(JSON.stringify(quality(x)))},1,${quote(randomUUID())})`);}
async function wait(name,event){for(let n=0;n<160;n++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${quote(name)} and ${event==='Lock'?"wait_event_type='Lock'":"wait_event='PgSleep'"})`)==='t')return;await new Promise(r=>setTimeout(r,20));}throw Error(`No observed ${event}: ${name}`);}
const receive=(x,q,r,k,name,delay=false)=>`begin;set application_name=${quote(name)};${actor(x)}set local role authenticated;select output_test.receive(${quote(JSON.stringify(x))},${quote(x.g1)},${q},${r},${quote(k)});${delay?'select pg_sleep(2);':''}commit;`;
{
 const x=await fixture('race-over');await release(x);
 const first=sql(receive(x,70,2,randomUUID(),'output-first',true));await wait('output-first','PgSleep');
 const second=sql(receive(x,70,2,randomUUID(),'output-second'));await wait('output-second','Lock');
 const [a,b]=await Promise.all([first,second]);assert.equal(a.code,0,a.error);assert.notEqual(b.code,0);assert.match(b.error,/output_revision/);
 assert.equal(await required(`select on_hand=70 and reserved=0 from public.finished_goods_balances where factory_id=${quote(x.factory)}`),'t');
 assert.equal(await required(`select count(*)=1 from public.finished_goods_movements where factory_id=${quote(x.factory)}`),'t');
 pass('concurrent partial receipts serialize; losing ledger/source posting rolls back');
}
{
 const x=await fixture('race-retry');await release(x);const k=randomUUID();
 const a=sql(receive(x,40,2,k,'output-retry-a',true));await wait('output-retry-a','PgSleep');
 const b=sql(receive(x,40,2,k,'output-retry-b'));await wait('output-retry-b','Lock');
 const rows=await Promise.all([a,b]);rows.forEach(r=>assert.equal(r.code,0,r.error));
 assert.equal(await required(`select on_hand=40 from public.finished_goods_balances where factory_id=${quote(x.factory)}`),'t');
 assert.equal(await required(`select count(*)=1 from private.manufactured_output_events where factory_id=${quote(x.factory)} and operation='RECEIPT'`),'t');
 pass('concurrent identical UUID yields exactly one receipt and stock credit');
}
{
 const x=await fixture('race-quality');await release(x);
 const a=sql(receive(x,10,2,randomUUID(),'output-quality-a',true));await wait('output-quality-a','PgSleep');
 const b=sql(`begin;set application_name='output-quality-b';${actor(x)}set local role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(x.output)},${quote(JSON.stringify(quality(x)))},2,${quote(randomUUID())});commit;`);
 await wait('output-quality-b','Lock');const [ar,br]=await Promise.all([a,b]);assert.equal(ar.code,0,ar.error);assert.notEqual(br.code,0);assert.match(br.error,/output_revision/);
 pass('Quality amendment racing receipt cannot use stale revision');
}
{
 const x=await fixture('race-permission');await release(x);
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.worker)},'warehouse','edit')`);
 const blocker=sql(`begin;set application_name='output-revoke-lock';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory)},0));select pg_sleep(3);commit;`);await wait('output-revoke-lock','PgSleep');
 const worker={...x,owner:x.worker};const attempt=sql(receive(worker,1,2,randomUUID(),'output-revoke-worker'));await wait('output-revoke-worker','Lock');
 await required(`delete from public.user_permissions where factory_id=${quote(x.factory)} and user_id=${quote(x.worker)} and module='warehouse' and action='edit'`);
 await blocker;const denied=await attempt;assert.notEqual(denied.code,0);assert.match(denied.error,/permission_denied/);
 assert.equal(await required(`select not exists(select 1 from public.finished_goods_balances where factory_id=${quote(x.factory)} and on_hand<>0)`),'t');
 pass('permission revoked during observed lock wait prevents receipt posting');
}
{
 const x=await fixture('security'),other=await fixture('security-other');
 const denied=await sql(`${actor({...x,owner:x.worker})}set role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(x.output)},${quote(JSON.stringify(quality(x)))},1,${quote(randomUUID())})`);
 assert.notEqual(denied.code,0);assert.match(denied.error,/permission_denied/);
 const noReceipt=await sql(receive({...x,owner:x.worker},1,1,randomUUID(),'output-no-receipt'));
 assert.notEqual(noReceipt.code,0);assert.match(noReceipt.error,/permission_denied/);
 const cross=await sql(`${actor(x)}set role authenticated;select output_test.command(${quote(other.factory)},'QUALITY',${quote(other.output)},${quote(JSON.stringify(quality(other)))},1,${quote(randomUUID())})`);
 assert.notEqual(cross.code,0);assert.match(cross.error,/permission_denied/);
 const wrongOutput=await sql(`${actor(x)}set role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(other.output)},${quote(JSON.stringify(quality(other)))},1,${quote(randomUUID())})`);
 assert.notEqual(wrongOutput.code,0);assert.match(wrongOutput.error,/output_not_found/);
 assert.equal(await required("select not has_function_privilege('authenticated','private.manufactured_output_command(uuid,text,uuid,jsonb,bigint,uuid)','execute') and not has_table_privilege('authenticated','private.manufactured_outputs','select') and not has_function_privilege('anon','public.manufactured_output_capability(uuid)','execute')"),'t');
 pass('real authenticated role: unauthorized Quality, cross-factory and private direct access blocked');
 const pkg=await required(`insert into public.permission_packages(factory_id,name) values(${quote(x.factory)},'Output QA package') returning id`);
 const packageId=pkg.split('\n')[0];
 await required(`insert into public.permission_package_permissions(factory_id,package_id,module,action) values
 (${quote(x.factory)},${quote(packageId)},'quality','view'),(${quote(x.factory)},${quote(packageId)},'quality','create');
 insert into public.member_permission_packages(factory_id,user_id,package_id) values(${quote(x.factory)},${quote(x.worker)},${quote(packageId)});`);
 await required(`${actor({...x,owner:x.worker})}set role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(x.output)},${quote(JSON.stringify(quality(x)))},1,${quote(randomUUID())})`);
 const edit=await sql(`${actor({...x,owner:x.worker})}set role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(x.output)},${quote(JSON.stringify(quality(x)))},2,${quote(randomUUID())})`);
 assert.notEqual(edit.code,0);assert.match(edit.error,/permission_denied/);
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.worker)},'quality','edit')`);
 await required(`${actor({...x,owner:x.worker})}set role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(x.output)},${quote(JSON.stringify(quality(x)))},2,${quote(randomUUID())})`);
 pass('package create/view plus direct edit combine without title-based authority');
 const direct=await sql(`${actor(x)}set role authenticated;select private.manufactured_output_command(${quote(x.factory)},'QUALITY',${quote(x.output)},'{}',3,${quote(randomUUID())})`);
 assert.notEqual(direct.code,0);assert.match(direct.error,/permission denied/);
 const isolation=await sql(`begin isolation level repeatable read;${actor(x)}set local role authenticated;select output_test.command(${quote(x.factory)},'QUALITY',${quote(x.output)},'{}',3,${quote(randomUUID())});commit;`);
 assert.notEqual(isolation.code,0);assert.match(isolation.error,/output_isolation/);
 pass('direct private command blocked; stale-snapshot transaction isolation rejected');
}
await writeFile(join(output,'concurrency-summary.json'),JSON.stringify(reports,null,2));
