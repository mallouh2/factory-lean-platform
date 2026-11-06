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
async function fixture(choice='COMPLETE'){
 const x=JSON.parse(await required(`select output4_test.context(${q('Revision race '+reports.length)})`));
 const p0={group_id:x.group,quantity:'10',choice,operations:choice==='REPLACE'?[]:[x.step1],reason:'Controlled concurrent decision'};
 const w=JSON.parse((await required(`begin;${actor(x.owner)}select public.plan_manufactured_completion(${q(x.factory)},${q(x.output)},${q(JSON.stringify(p0))},4,${q(randomUUID())});commit;`)).split('\n').at(-1));
 const p=JSON.parse(await required(`select output4b_test.payload(${q(JSON.stringify(x))},${q(JSON.stringify(w))})`));return{x,w,p};
}
const revise=(v,id=randomUUID(),p=v.p,user=v.x.owner)=>`begin;${actor(user)}select public.revise_manufactured_completion(${q(v.x.factory)},${q(v.w.item_id)},${q(JSON.stringify(p))},5,${q(id)});commit;`;
async function race(first,second,expected){
 const name='revision-'+reports.length,a=sql(first.replace('begin;',`begin;set application_name=${q(name+'a')};`).replace('commit;','select pg_sleep(1.5);commit;'));
 await wait(name+'a','PgSleep');const b=sql(second.replace('begin;',`begin;set application_name=${q(name+'b')};`));await wait(name+'b','Lock');
 const ar=await a;assert.equal(ar.code,0,ar.error);const r=await b;if(expected){assert.notEqual(r.code,0);assert.match(r.error,expected);}else assert.equal(r.code,0,r.error);
}
let v=await fixture(),key=randomUUID();await race(revise(v,key),revise(v,key));
assert.equal(await required(`select count(*)=1 from private.manufactured_output_events where factory_id=${q(v.x.factory)} and operation='RETIRE'`),'t');pass('same UUID concurrent cancellation commits one retirement and material release');
v=await fixture();await race(revise(v,randomUUID(),{...v.p,action:'CHANGE',choice:'REPLACE',operations:[]}),revise(v),/output_work_retired/);
assert.equal(await required(`select assigned=10 and replaced=10 and reserved=0 from private.output_work_allocations(${q(v.x.factory)},${q(v.x.lot)})`),'t');pass('competing change and cancellation leave exactly one live successor');
const issue=v=>`begin;${actor(v.x.owner)}select public.supply_command(${q(v.x.factory)},'material_change',${q(JSON.stringify({id:v.w.material_request_id,revision:1,action:'issue',reason:'Actual controlled Warehouse issue'}))},${q(randomUUID())});commit;`;
v=await fixture();await race(issue(v),revise(v),/output_material_issued/);
assert.equal(await required(`select warehouse_quantity=0 and quantity_available=10 from public.unfinished_lots where id=${q(v.x.lot)}`),'t');pass('issue winning cancellation race preserves ten issued units and no consumption');
v=await fixture();await race(revise(v),issue(v),/supply_conflict|supply_state|output_work_retired/);
assert.equal(await required(`select warehouse_quantity=10 and quantity_available=10 from public.unfinished_lots where id=${q(v.x.lot)}`),'t');pass('cancellation winning issue race leaves stored source unchanged');
const plan=v=>`begin;${actor(v.x.owner)}select public.plan_product_item(${q(v.x.factory)},${q(v.w.item_id)},${q(v.x.line)},date_trunc('day',clock_timestamp())+interval '5 days');commit;`;
const start=v=>`begin;${actor(v.x.owner)}select public.start_product_item(${q(v.x.factory)},${q(v.w.item_id)});commit;`;
v=await fixture('REPLACE');await required(plan(v));v.p=JSON.parse(await required(`select output4b_test.payload(${q(JSON.stringify(v.x))},${q(JSON.stringify(v.w))})`));
await race(start(v),revise(v),/output_work_started/);pass('Production Start winning race cannot be undone');
v=await fixture('REPLACE');await required(plan(v));v.p=JSON.parse(await required(`select output4b_test.payload(${q(JSON.stringify(v.x))},${q(JSON.stringify(v.w))})`));
await race(revise(v),start(v),/execution_|output_work_retired/);pass('retirement winning race blocks stale Production Start');
v=await fixture();await race(plan(v),revise(v),/output_revision/);pass('concurrent Planning changes invalidate expected schedule revision');
v=await fixture();await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${q(v.x.factory)},${q(v.x.worker)},'orders','view'),(${q(v.x.factory)},${q(v.x.worker)},'orders','edit'),(${q(v.x.factory)},${q(v.x.worker)},'warehouse','issue')`);
const hold=sql(`begin;set application_name='revision-revoke';select pg_advisory_xact_lock(hashtextextended(${q(v.x.factory)},0));select pg_sleep(2);commit;`);await wait('revision-revoke','PgSleep');
const denied=sql(revise(v,randomUUID(),v.p,v.x.worker).replace('begin;',"begin;set application_name='revision-denied';"));await wait('revision-denied','Lock');
await required(`delete from public.user_permissions where factory_id=${q(v.x.factory)} and user_id=${q(v.x.worker)} and module='warehouse' and action='issue'`);assert.equal((await hold).code,0);const dr=await denied;assert.notEqual(dr.code,0);assert.match(dr.error,/permission_denied/);
assert.equal(await required(`select count(*)=0 from private.manufactured_output_events where factory_id=${q(v.x.factory)} and operation='RETIRE'`),'t');pass('Warehouse authority revoked during observed wait denies cancellation');
const cross=await sql(revise(v,randomUUID(),v.p,(await fixture()).x.owner));assert.notEqual(cross.code,0);assert.match(cross.error,/permission_denied/);pass('authenticated cross-factory revision denied');
await required("create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$");
const off=await sql(revise(v));assert.notEqual(off.code,0);assert.match(off.error,/recording_disabled/);
assert.equal(await required('select count(*)=0 from private.manufactured_output_context'),'t');pass('disabled gate and transaction-context cleanup remain protected');
await writeFile(join(output,'concurrency-results.json'),JSON.stringify({passed:reports.length,checks:reports},null,2));
