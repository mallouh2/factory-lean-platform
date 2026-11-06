import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
const [bin,port,output]=process.argv.slice(2),q=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.equal(port,'55491');
function sql(text){return new Promise((resolve,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>resolve({code,out:out.trim(),error}));p.stdin.end(text);});}
async function required(s){const r=await sql(s);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet and inet_server_port()=55491"),'t');
async function wait(name,event){for(let n=0;n<150;n++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${q(name)} and ${event==='Lock'?"wait_event_type='Lock'":"wait_event='PgSleep'"})`)==='t')return;await new Promise(r=>setTimeout(r,20));}throw Error('Expected observed '+event+': '+name);}
const reports=[];
for(const sameUUID of [true,false]){
 const x=JSON.parse(await required("select output4_test.context('All-Scrap race')")),actor=`select set_config('request.jwt.claim.sub',${q(x.owner)},false);set local role authenticated;`;
 const w=JSON.parse((await required(`select set_config('request.jwt.claim.sub',${q(x.owner)},false);select output4_test.decision(${q(JSON.stringify(x))},'COMPLETE',10)`)).split('\n').at(-1));
 const y=JSON.parse((await required(`select set_config('request.jwt.claim.sub',${q(x.owner)},false);select output4_test.start(${q(JSON.stringify(x))},${q(JSON.stringify(w))})`)).split('\n').at(-1));
 const payload=JSON.parse((await required(`select set_config('request.jwt.claim.sub',${q(x.owner)},false);select output2_test.payload(${q(JSON.stringify(y))},0)||jsonb_build_object('input_lot',${q(x.lot)},'input_quantity',10,'discarded_quantity',10,'scrap_kg',0.75)`)).split('\n').at(-1));
 const key=randomUUID(),record=k=>`select public.record_manufactured_output(${q(x.factory)},${q(JSON.stringify(payload))},${q(k)})`;
 if(sameUUID){const denied=await sql(`begin;select set_config('request.jwt.claim.sub',${q(x.viewer)},false);set local role authenticated;${record(randomUUID())};commit;`);assert.notEqual(denied.code,0);assert.match(denied.error,/permission_denied/);assert.equal(await required(`select quantity_available=10 and warehouse_quantity=0 from public.unfinished_lots where id=${q(x.lot)}`),'t');}
 const a=sql(`begin;set application_name='p4a-first';${actor}${record(key)};select pg_sleep(2);commit;`);await wait('p4a-first','PgSleep');
 const b=sql(`begin;set application_name='p4a-second';${actor}${record(sameUUID?key:randomUUID())};commit;`);await wait('p4a-second','Lock');
 assert.equal((await a).code,0);const result=await b;if(sameUUID)assert.equal(result.code,0,result.error);else{assert.notEqual(result.code,0);assert.match(result.error,/output_input_quantity/);}
 assert.equal(await required(`select quantity_available=0 and warehouse_quantity=0 from public.unfinished_lots where id=${q(x.lot)}`),'t');
 assert.equal(await required(`select count(*)=1 and sum(effective_scrap_kg)=0.75 and sum(input_quantity)=10 and sum(effective_good)=0 and sum(effective_unfinished)=0 from public.production_entries where factory_id=${q(x.factory)} and order_id=${q(w.item_id)}`),'t');
 assert.equal(await required(`select private.output_demand_received(${q(x.factory)},${q(x.item)})=90 and (select count(*)=1 from public.unfinished_movements where factory_id=${q(x.factory)} and lot_id=${q(x.lot)} and kind='consumed')`),'t');
 reports.push(sameUUID?'concurrent same UUID replays one consumption and measured Scrap entry':'different concurrent UUID cannot consume exhausted source or duplicate Scrap');
 console.log('PASS '+reports.at(-1));
}
assert.equal(await required('select count(*)=0 from private.manufactured_output_context'),'t');
await required("create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$");
assert.equal(await required('select private.manufactured_output_enabled(gen_random_uuid())'),'f');
await writeFile(join(output,'concurrency-results.json'),JSON.stringify({passed:reports.length,checks:reports},null,2));
