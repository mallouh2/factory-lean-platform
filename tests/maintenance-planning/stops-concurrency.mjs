// Disposable localhost PostgreSQL only. Real concurrent transactions, no hosted clients.
import {spawn} from 'node:child_process';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const [bin,port,results]=process.argv.slice(2);
assert.match(port,/^\d+$/);assert.ok(resolve(results).includes('FactoryLean-Quality-Postgres-'));
function connection(name='mp-contract') {
 const child=spawn(join(bin,'psql.exe'),['-X','-q','-A','-t','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});
 let output='',error='',mark;
 const marked=new Promise(done=>mark=done),done=new Promise((done,reject)=>{
  child.stdout.on('data',b=>{output+=b;if(output.includes('CONTRACT_HELD'))mark();});
  child.stderr.on('data',b=>error+=b);child.on('error',reject);child.on('close',code=>done({code,output,error}));
 });
 child.stdin.write(`set application_name='${name}';set lock_timeout='8s';set statement_timeout='15s';`);
 return {child,marked,done};
}
async function sql(statement){const c=connection();c.child.stdin.end(statement);return c.done;}
async function required(statement){const r=await sql(statement);assert.equal(r.code,0,r.error);return r.output.trim().split('\n').at(-1);}
const actor=(x,user=x.owner)=>`set local role authenticated;select set_config('request.jwt.claim.sub','${user}',true);select set_config('request.jwt.claim.role','authenticated',true);`;
async function waiterBlocked(name){for(let i=0;i<80;i++){
 if(await required(`select exists(select 1 from pg_stat_activity where application_name='${name}' and wait_event_type='Lock')`)==='t')return;
 await new Promise(done=>setTimeout(done,20));
 }throw Error('Expected scheduling lock wait not observed');}
async function race(x,write,wait,expected,label,{privileged=false,user=x.owner}={}){
 const holder=connection('mp-contract-holder'),name='mp-contract-waiter-'+randomUUID();
 holder.child.stdin.write(`begin;${privileged?'':actor(x)}${write};select 'CONTRACT_HELD';\n`);
 try {
  await Promise.race([holder.marked,holder.done.then(r=>{throw Error('Holder failed: '+r.error);}),new Promise((_,fail)=>setTimeout(()=>fail(Error('Holder timeout')),15000))]);
  const second=connection(name);second.child.stdin.end(`begin;${actor(x,user)}${wait};commit;`);
  await waiterBlocked(name);holder.child.stdin.end('commit;');
  const pair=await Promise.all([holder.done,second.done]);assert.equal(pair[0].code,0,pair[0].error);
  if(expected){assert.notEqual(pair[1].code,0);assert.match(pair[1].error,expected);}else assert.equal(pair[1].code,0,pair[1].error);
  assert.ok(pair.every(r=>!r.error.includes('deadlock detected')));report.push('PASS '+label);
  await writeFile(join(results,'stops-concurrency-progress.json'),JSON.stringify(report,null,2));
 }finally{if(!holder.child.stdin.writableEnded)holder.child.stdin.end('rollback;');}
}

const report=[];
const stop=(x,retry=randomUUID(),userRevision=2)=>`select public.stop_machine_for_maintenance('${x.factory}','${x.machine}','planned',null,'inspection','Local race','${x.schedule}',2,${userRevision},'${retry}')`;
const correct=(x,retry=randomUUID())=>`select public.correct_maintenance_stop('${x.factory}','${x.event}','${x.schedule}',2,'UNLINK','Closed stop correction',1,'${retry}')`;
async function fixture(label){
 const x=JSON.parse(await required(`select mp_test.fixture('stops-${label}')`));
 const start=await required(`select (clock_timestamp()+interval '1 second')::text`);
 await required(`begin;${actor(x)}select public.maintenance_planning_command('${x.factory}','${x.request}','propose',jsonb_build_object('start','${start}','end','${start}'::timestamptz+interval '30 minutes'),0,gen_random_uuid());select mp_test.command('${x.factory}','${x.request}','confirm','{}',1,gen_random_uuid());select public.change_status('${x.factory}','${x.machine}','running');commit;`);
 x.schedule=await required(`select id from public.maintenance_schedules where factory_id='${x.factory}'`);
 await required(`select pg_sleep(1.1)`);return x;
}
await required('update private.maintenance_planning_activation set enabled=true;');
{
 const x=await fixture('retry'),command=stop(x);
 await race(x,command,command,null,'identical stop retry: one event, one link');
 assert.equal(await required(`select count(*) from public.downtime_events where factory_id='${x.factory}'`),'1');
 assert.equal(await required(`select count(*) from public.maintenance_stop_associations where factory_id='${x.factory}'`),'1');
}
{
 const x=await fixture('competing');
 await race(x,stop(x),stop(x),/status_unchanged/,'two distinct stop submissions: no duplicate event');
}
{
 const x=await fixture('release');
 await race(x,stop(x),`select mp_test.command('${x.factory}','${x.request}','unschedule','{"reason":"Concurrent release"}',2,gen_random_uuid())`,/maintenance_active_stop/,'stop versus unschedule: active reservation retained');
}
{
 const x=await fixture('closed-correction');
 x.event=await required(`begin;${actor(x)}${stop(x)};commit;`);
 await required(`begin;${actor(x)}select public.change_status('${x.factory}','${x.machine}','idle');commit;`);
 await race(x,correct(x),correct(x),/maintenance_stop_conflict/,'competing corrections: one current revision');
 assert.equal(await required(`select count(*) from public.maintenance_stop_associations where factory_id='${x.factory}'`),'2');
}
{
 const x=await fixture('correction-retry');
 x.event=await required(`begin;${actor(x)}${stop(x)};commit;`);
 await required(`begin;${actor(x)}select public.change_status('${x.factory}','${x.machine}','idle');commit;`);
 const command=correct(x);
 await race(x,command,command,null,'identical correction retry: one immutable correction');
}
{
 const x=await fixture('approval-change');
 await race(x,`select mp_test.command('${x.factory}','${x.request}','unschedule','{"reason":"Removed approval"}',2,gen_random_uuid())`,stop(x),/maintenance_stop_conflict/,'approval changed during wait: no physical stop');
 assert.equal(await required(`select count(*) from public.downtime_events where factory_id='${x.factory}'`),'0');
}
{
 const x=await fixture('permission-wait');
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values('${x.factory}','${x.worker}','machine_status','edit'),('${x.factory}','${x.worker}','maintenance','view');`);
 await race(x,`select private.maintenance_planning_lock('${x.factory}');delete from public.user_permissions where factory_id='${x.factory}' and user_id='${x.worker}' and module='machine_status'`,stop(x),/permission_denied/,'revoked stop authority rechecked after actual lock wait',{privileged:true,user:x.worker});
 assert.equal(await required(`select count(*) from public.downtime_events where factory_id='${x.factory}'`),'0');
}
await required('update private.maintenance_planning_activation set enabled=false;');
assert.equal(await required('select enabled from private.maintenance_planning_activation'),'f');
await writeFile(join(results,'stops-concurrency.json'),JSON.stringify(report,null,2));
console.log(report.join('\n'));
