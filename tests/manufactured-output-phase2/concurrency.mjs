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
const p=JSON.parse((await required(`${actor(x)}select output2_test.payload(${quote(JSON.stringify(x))},5,0)`)).split('\n').at(-1));
const key=randomUUID(),call=`select public.record_manufactured_output(${quote(x.factory)},${quote(JSON.stringify(p))},${quote(key)})`;
const first=sql(`begin;set application_name='output2-first';${actor(x)}set local role authenticated;${call};select pg_sleep(2);commit;`);
await wait('output2-first','PgSleep');
const second=sql(`begin;set application_name='output2-second';${actor(x)}set local role authenticated;${call};commit;`);await wait('output2-second','Lock');
for(const r of await Promise.all([first,second]))assert.equal(r.code,0,r.error);
assert.equal(await required(`select count(*)=1 from public.production_entries where factory_id=${quote(x.factory)} and request_id=${quote(key)}`),'t');
pass('two concurrent identical recording UUIDs create one physical output and no stock');
const h=JSON.parse(await required(`select row_to_json(h) from private.manufactured_outputs h join public.production_entries e on e.id=h.entry_id where e.request_id=${quote(key)}`));
const quality={groups:h.recorded_groups.map(g=>({...g,released:g.quantity})),rejected:'0',reason:'Concurrent inspection'};
const qc=k=>`select public.manufactured_output_command(${quote(x.factory)},'QUALITY',${quote(h.id)},${quote(JSON.stringify(quality))},1,${quote(k)})`;
const a=sql(`begin;set application_name='output2-qa';${actor(x)}set local role authenticated;${qc(randomUUID())};select pg_sleep(2);commit;`);await wait('output2-qa','PgSleep');
const b=sql(`begin;set application_name='output2-qb';${actor(x)}set local role authenticated;${qc(randomUUID())};commit;`);await wait('output2-qb','Lock');
const [ar,br]=await Promise.all([a,b]);assert.equal(ar.code,0,ar.error);assert.notEqual(br.code,0);assert.match(br.error,/output_revision/);
pass('concurrent Quality decisions serialize; stale inspection cannot overwrite');
await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.worker)},'quality','view'),(${quote(x.factory)},${quote(x.worker)},'quality','edit') on conflict do nothing`);
const blocker=sql(`begin;set application_name='output2-block';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory)},0));select pg_sleep(2);commit;`);await wait('output2-block','PgSleep');
const denied=sql(`begin;set application_name='output2-denied';${actor({...x,owner:x.worker})}set local role authenticated;select public.manufactured_output_command(${quote(x.factory)},'QUALITY',${quote(h.id)},${quote(JSON.stringify(quality))},2,${quote(randomUUID())});commit;`);await wait('output2-denied','Lock');
await required(`delete from public.user_permissions where factory_id=${quote(x.factory)} and user_id=${quote(x.worker)} and module='quality' and action='edit'`);await blocker;
const dr=await denied;assert.notEqual(dr.code,0);assert.match(dr.error,/permission_denied/);pass('permission revoked during lock wait denies amendment');
const cross=await sql(`${actor({...x,owner:x.viewer})}set role authenticated;select public.manufactured_output_read(${quote(x.factory)},'quality')`);assert.notEqual(cross.code,0);assert.match(cross.error,/permission_denied/);
assert.equal(await required(`select not exists(select 1 from public.finished_goods_movements where factory_id=${quote(x.factory)}) and not exists(select 1 from private.manufactured_output_context)`),'t');
const direct=await sql(`${actor(x)}set role authenticated;select * from private.manufactured_outputs`);assert.notEqual(direct.code,0);pass('authenticated grants, private-table denial and zero stock/context leakage');
const gatePayload=JSON.parse((await required(`${actor(x)}select output2_test.payload(${quote(JSON.stringify(x))},1,0)`)).split('\n').at(-1));
const gateBlock=sql(`begin;set application_name='output2-gate-block';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory)},0));select pg_sleep(2);commit;`);await wait('output2-gate-block','PgSleep');
const gateAttempt=sql(`begin;set application_name='output2-gate-attempt';${actor(x)}set local role authenticated;select public.record_manufactured_output(${quote(x.factory)},${quote(JSON.stringify(gatePayload))},${quote(randomUUID())});commit;`);await wait('output2-gate-attempt','Lock');
await required("create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$");await gateBlock;
const ga=await gateAttempt;assert.notEqual(ga.code,0);assert.match(ga.error,/recording_disabled/);pass('gate changed during observed wait is rechecked inside protected transaction');
const off=await sql(`${actor(x)}set role authenticated;select public.record_manufactured_output(${quote(x.factory)},${quote(JSON.stringify(p))},${quote(randomUUID())})`);assert.notEqual(off.code,0);assert.match(off.error,/recording_disabled/);
assert.equal((await required(`${actor(x)}select public.manufactured_output_capability(${quote(x.factory)})->>'available'`)).split('\n').at(-1),'false');
pass('shipped disabled predicate blocks writer; production capability remains FALSE');
await writeFile(join(output,'concurrency-results.json'),JSON.stringify({passed:reports.length,checks:reports},null,2));
