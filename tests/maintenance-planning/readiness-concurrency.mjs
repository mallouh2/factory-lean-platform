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
  await writeFile(join(results,'readiness-concurrency-progress.json'),JSON.stringify(report,null,2));
 }finally{if(!holder.child.stdin.writableEnded)holder.child.stdin.end('rollback;');}
}

const report=[];
async function fixture(label,verify=true,other=false){return JSON.parse(await required(`select mp_test.released('ready-${label}',false,${other},${verify})`));}
const start=x=>`select public.start_product_item('${x.factory}','${x.item}')`;
const status=(x,value,m=x.machine)=>`select public.change_status('${x.factory}','${m}','${value}')`;
const stop=(x,m=x.machine)=>`select public.stop_machine('${x.factory}','${m}','planned',null,'inspection','Local race')`;
{
 const x=await fixture('restart');await required(`begin;${actor(x)}${stop(x)};commit;`);
 await race(x,status(x,'running'),start(x),null,'physical restart commits before waiting Start; RUNNING permitted');
}
{
 const x=await fixture('stop');await race(x,stop(x),start(x),/execution_physical_not_ready/,'physical stop commits first; waiting Start blocked');
 assert.equal(await required(`select actual_start is null from public.production_orders where id='${x.item}'`),'t');
}
{
 const x=await fixture('start-first');await race(x,start(x),stop(x),null,'Start linearizes before later physical stop; no auto-restart');
 assert.equal(await required(`select o.actual_start<d.started_at from public.production_orders o join public.downtime_events d on d.factory_id=o.factory_id and d.work_center_id='${x.machine}' and d.ended_at is null where o.id='${x.item}'`),'t');
}
{
 const x=await fixture('verify',false);
 await race(x,`select public.change_maintenance_request('${x.factory}','${x.request}','verify','{"result":"RESOLVED","verification_note":"Independent check"}',4,gen_random_uuid())`,start(x),null,'verification release commits before Start; IDLE preparation permitted');
}
{
 const x=await fixture('failed-verify',false);
 await race(x,`select public.change_maintenance_request('${x.factory}','${x.request}','verify','{"result":"REWORK_REQUIRED","verification_note":"Further repair"}',4,gen_random_uuid())`,start(x),/maintenance_capacity_reserved/,'failed verification commits first; retained hold blocks Start');
}
{
 const x=await fixture('two-starts');await race(x,start(x),start(x),/execution_already_started/,'two Starts: only one actual start');
}
{
 const x=await fixture('permission');
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values('${x.factory}','${x.viewer}','orders','edit');`);
 await race(x,`select private.maintenance_planning_lock('${x.factory}');delete from public.user_permissions where factory_id='${x.factory}' and user_id='${x.viewer}' and module='orders' and action='edit'`,start(x),/permission_denied/,'authority revoked during actual lock wait rechecked',{privileged:true,user:x.viewer});
}
async function borrowingFixture(label){
 const x=await fixture(label,true,true);
 const request=await required(`begin;${actor(x)}select public.create_production_request('${x.factory}','Local borrower','normal',null,'Isolated fixture','[{"product_id":"${x.product}","quantity":10,"unit":"meter"}]');commit;`);
 x.borrower=await required(`select id from public.production_orders where request_id='${request}'`);
 await required(`begin;${actor(x)}select public.plan_product_item('${x.factory}','${x.borrower}','${x.other_line}',clock_timestamp()+interval '1 hour');select public.start_product_item('${x.factory}','${x.borrower}');${stop(x,x.other_machine)};select public.configure_center_alternatives('${x.factory}','${x.other_machine}',array['${x.machine}'::uuid]);commit;`);
 return x;
}
const transfer=x=>`select public.transfer_production('${x.factory}','${x.other_machine}','${x.machine}','Local approved alternative')`;
{
 const x=await borrowingFixture('transfer-first');
 await race(x,transfer(x),start(x),/execution_physical_not_ready/,'OPEN alternative assignment commits first; home Start cannot steal it');
 assert.equal(await required(`select count(*) from public.production_transfers where factory_id='${x.factory}' and ended_at is null`),'1');
}
{
 const x=await borrowingFixture('home-first');
 await race(x,start(x),transfer(x),/incompatible_alternative/,'home Start commits first; existing transfer ownership validation protects active item');
}
{
 const x=await borrowingFixture('stopped-borrower');await required(`begin;${actor(x)}${transfer(x)};commit;`);
 await race(x,stop(x),start(x),/execution_physical_not_ready/,'stopped borrowed alternative remains assigned; Start denied');
 assert.equal(await required(`select count(*) from public.production_transfers where factory_id='${x.factory}' and ended_at is null`),'1');
 await required(`begin;${actor(x)}${status(x,'running',x.other_machine)};commit;`);
 assert.equal(await required(`select status from public.work_centers where id='${x.machine}'`),'stopped');
 const denied=await sql(`begin;${actor(x)}${start(x)};commit;`);assert.match(denied.error,/execution_physical_not_ready/);
 report.push('PASS explicit transfer return preserves manually stopped alternative; physical guard still blocks');
}
{
 const x=await borrowingFixture('return');await required(`begin;${actor(x)}${transfer(x)};commit;`);
 await race(x,status(x,'running',x.other_machine),start(x),null,'explicit OPEN transfer return commits first; legitimate home preparation allowed');
}
{
 const x=await fixture('snapshot');
 const read=JSON.parse(await required(`begin read only;${actor(x)}select public.production_start_readiness('${x.factory}','${x.item}');commit;`));assert.equal(read.physical.ready,true);report.push('PASS scoped readiness works in a read-only transaction');
 const r=await sql(`begin isolation level repeatable read;${actor(x)}${start(x)};commit;`);
 assert.match(r.error,/execution_readiness_stale/);report.push('PASS old transaction snapshot rejected');
}
assert.equal(await required('select enabled from private.maintenance_planning_activation'),'f');
await writeFile(join(results,'readiness-concurrency.json'),JSON.stringify({report,actualRaces:11,gate:false},null,2));
console.log(report.join('\n'));
