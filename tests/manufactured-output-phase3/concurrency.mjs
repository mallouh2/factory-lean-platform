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
const x=JSON.parse(await required('select x from output2_test.fixture'));
async function wait(name,event){for(let n=0;n<160;n++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${quote(name)} and ${event==='Lock'?"wait_event_type='Lock'":"wait_event='PgSleep'"})`)==='t')return;await new Promise(r=>setTimeout(r,20));}throw Error(`No observed ${event}: ${name}`);}
const key=randomUUID();await required(`${actor(x)}select public.record_manufactured_output(${quote(x.factory)},output2_test.payload(${quote(JSON.stringify(x))},10),${quote(key)})`);
const h=JSON.parse(await required(`select row_to_json(h) from private.manufactured_outputs h join public.production_entries e on e.id=h.entry_id where e.request_id=${quote(key)}`));
const quality={groups:h.recorded_groups.map(g=>({...g,released:g.quantity})),rejected:'0',reason:'Receipt concurrency inspection'};
await required(`${actor(x)}select public.manufactured_output_command(${quote(x.factory)},'QUALITY',${quote(h.id)},${quote(JSON.stringify(quality))},1,${quote(randomUUID())})`);
const p={group_id:h.recorded_groups[0].id,quantity:'6',location:'Isolated receipt bay',physical_confirmation:true};
const call=(key,rev=2,payload=p)=>`select public.receive_manufactured_output(${quote(x.factory)},${quote(h.id)},${quote(JSON.stringify(payload))},${rev},${quote(key)})`;
const first=sql(`begin;set application_name='p3-a';${actor(x)}set local role authenticated;${call(randomUUID())};select pg_sleep(2);commit;`);await wait('p3-a','PgSleep');
const second=sql(`begin;set application_name='p3-b';${actor(x)}set local role authenticated;${call(randomUUID())};commit;`);await wait('p3-b','Lock');
const [a,b]=await Promise.all([first,second]);assert.equal(a.code,0,a.error);assert.notEqual(b.code,0);assert.match(b.error,/output_revision/);
assert.equal(await required(`select on_hand=6 from public.finished_goods_balances where factory_id=${quote(x.factory)} and product_id=${quote(h.product_id)}`),'t');pass('overlapping receipts serialize without over-credit');
const retry=randomUUID(),four={...p,quantity:'4'};
const one=sql(`begin;set application_name='p3-c';${actor(x)}set local role authenticated;${call(retry,3,four)};select pg_sleep(2);commit;`);await wait('p3-c','PgSleep');
const two=sql(`begin;set application_name='p3-d';${actor(x)}set local role authenticated;${call(retry,3,four)};commit;`);await wait('p3-d','Lock');
for(const r of await Promise.all([one,two]))assert.equal(r.code,0,r.error);
assert.equal(await required(`select count(*)=2 and sum(stock_delta)=10 from public.finished_goods_movements where entry_id=${quote(h.entry_id)}`),'t');pass('concurrent same UUID returns one receipt, one movement');
// Unchanged release is legal after receipt; a concurrent stale receipt cannot post.
const qa=sql(`begin;set application_name='p3-quality';${actor(x)}set local role authenticated;select public.manufactured_output_command(${quote(x.factory)},'QUALITY',${quote(h.id)},${quote(JSON.stringify(quality))},4,${quote(randomUUID())});select pg_sleep(2);commit;`);await wait('p3-quality','PgSleep');
const stale=sql(`begin;set application_name='p3-stale';${actor(x)}set local role authenticated;${call(randomUUID(),4,{...p,quantity:'1'})};commit;`);await wait('p3-stale','Lock');
assert.equal((await qa).code,0);const st=await stale;assert.notEqual(st.code,0);assert.match(st.error,/output_revision/);pass('Quality amendment and receipt share revision/lock protection');
await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.worker)},'warehouse','view'),(${quote(x.factory)},${quote(x.worker)},'warehouse','edit') on conflict do nothing`);
const hold=sql(`begin;set application_name='p3-hold';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory)},0));select pg_sleep(2);commit;`);await wait('p3-hold','PgSleep');
const denied=sql(`begin;set application_name='p3-denied';${actor({...x,owner:x.worker})}set local role authenticated;${call(randomUUID(),5,{...p,quantity:'1'})};commit;`);await wait('p3-denied','Lock');
await required(`delete from public.user_permissions where factory_id=${quote(x.factory)} and user_id=${quote(x.worker)} and module='warehouse' and action='edit'`);await hold;const d=await denied;assert.notEqual(d.code,0);assert.match(d.error,/permission_denied/);pass('receipt rechecks permission after competing lock wait');
assert.equal(await required(`select not has_function_privilege('anon','public.receive_manufactured_output(uuid,uuid,jsonb,bigint,uuid)','execute') and not has_table_privilege('authenticated','private.manufactured_output_adjustments','insert')`),'t');
assert.equal(await required(`select (select count(*) from private.manufactured_output_context)=0 and (select count(*) from private.finished_goods_pick_context)=0`),'t');pass('private grants and transaction contexts protected');
await required(`create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$`);
const disabled=await sql(`${actor(x)}set role authenticated;${call(randomUUID(),5,{...p,quantity:'1'})}`);assert.notEqual(disabled.code,0);assert.match(disabled.error,/recording_disabled/);pass('shipped disabled predicate rejects receiving');
await writeFile(join(output,'concurrency-results.json'),JSON.stringify({passed:reports.length,checks:reports},null,2));
