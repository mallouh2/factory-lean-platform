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
const command=(x,op,payload,revision=1,retry=randomUUID())=>`select public.maintenance_planning_command('${x.factory}','${x.request}','${op}','${JSON.stringify(payload)}',${revision},'${retry}')`;
const report=[];
async function fixture(label){const x=JSON.parse(await required(`select mp_test.fixture('contract-${label}')`));
 x.start=await required("select (clock_timestamp()+interval '2 days')::text");
 await required(`begin;${actor(x)}${command(x,'propose',{start:x.start},0)};commit;`);return x;
}
async function preview(x,revision=1,start=x.start,end=null){return JSON.parse(await required(`begin read only;${actor(x)}select public.maintenance_planning_preview('${x.factory}','${x.request}','${start}',${end?`'${end}'`:'null'},2,${revision});commit;`));}
const payload=v=>({context_hash:v.context_hash,request_revision:v.request_revision});
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
  await writeFile(join(results,'contract-concurrency-progress.json'),JSON.stringify(report,null,2));
 }finally{if(!holder.child.stdin.writableEnded)holder.child.stdin.end('rollback;');}
}
await required('update private.maintenance_planning_activation set enabled=true;');
{
 const x=await fixture('same-request'),v=await preview(x);
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values('${x.factory}','${x.viewer}','orders','view'),('${x.factory}','${x.viewer}','orders','edit');`);
 await race(x,command(x,'confirm',payload(v)),command(x,'confirm',payload(v)),/maintenance_preview_stale/,'two users same request: one confirmation',{user:x.viewer});
 assert.equal(await required(`select count(*) from public.maintenance_schedule_revisions where factory_id='${x.factory}' and event='confirm'`),'1');
}
{
 const x=await fixture('retry'),v=await preview(x),retry=randomUUID(),c=command(x,'confirm',payload(v),1,retry);
 await race(x,c,c,null,'same actor identical retry succeeds once');
 assert.equal(await required(`select count(*) from public.maintenance_commands where request_id='${retry}'`),'1');
}
for(const kind of ['production','capability','alternatives','topology','sibling','archive','routing','calendar','timezone','request','schedule','cancel','request_cancel']){
 const x=await fixture(kind),v=await preview(x);let write;
 if(kind==='production')write=`select public.plan_product_item('${x.factory}','${x.item}','${x.line}','${x.start}')`;
 if(kind==='capability')write=`select public.configure_center_capabilities('${x.factory}','${x.machine}','[{"product_id":"${x.product}","rate":101,"rate_unit":"meter","setup_minutes":5}]')`;
 if(kind==='alternatives')write=`select public.configure_center_alternatives('${x.factory}','${x.machine}',array['${x.other_machine}'::uuid])`;
 if(kind==='topology')write=`select public.save_record('${x.factory}','centers','${x.machine}','{"position":2}')`;
 if(kind==='sibling')write=`select public.save_record('${x.factory}','centers','${x.other_machine}','{"line_id":"${x.line}"}')`;
 if(kind==='archive')write=`select public.save_record('${x.factory}','centers','${x.machine}','{"archived":true}')`;
 // No application routing writer exists. This is a scoped local fixture-owner configuration mutation.
 if(kind==='routing')write=`select private.maintenance_planning_lock('${x.factory}');insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values('${x.factory}','${x.product}',1,'work_center','${x.machine}')`;
 if(kind==='calendar')write=`select public.configure_working_calendar('${x.factory}',127,'08:00'::time,'17:00'::time)`;
 if(kind==='timezone')write=`select public.update_settings('${x.factory}','Local test factory','Asia/Riyadh',null)`;
 if(kind==='request')write=command(x,'details',{maintenance_kind:'PLANNED',estimated_duration_minutes:2},2);
 if(kind==='schedule')write=command(x,'propose',{start:v.start,end:v.end,reason:'Revised draft'},1);
 if(kind==='cancel')write=command(x,'unschedule',{reason:'Explicit cancellation'},1);
 if(kind==='request_cancel')write=`select public.change_maintenance_request('${x.factory}','${x.request}','cancel','{"cancellation_note":"Explicit request cancellation"}',2,gen_random_uuid())`;
 await race(x,write,command(x,'confirm',payload(v)),/maintenance_preview_stale/,kind+' changed after preview; waiting confirmation rejected',{privileged:kind==='routing'});
 assert.equal(await required(`select count(*) from public.maintenance_commands where factory_id='${x.factory}' and operation='planning:confirm'`),'0');
}
{
 const x=await fixture('booked'),v=await preview(x);
 const other=await required(`begin;${actor(x)}select public.create_maintenance_request('${x.factory}','{"work_center_id":"${x.machine}","title":"Other booking","priority":"NORMAL","maintenance_kind":"PLANNED","estimated_duration_minutes":1,"separate_problem":true}',gen_random_uuid());commit;`);
 const y={...x,request:other};await required(`begin;${actor(x)}${command(y,'propose',{start:x.start},0)};commit;`);
 const w=await preview(y);
 await race(x,command(y,'confirm',payload(w)),command(x,'confirm',payload(v)),/maintenance_preview_stale/,'new Maintenance booking after clear preview');
}
{
 const x=await fixture('reschedule'),v=await preview(x);await required(`begin;${actor(x)}${command(x,'confirm',payload(v))};commit;`);
 const a=await required(`select ('${x.start}'::timestamptz+interval '1 day')::text`),b=await required(`select ('${a}'::timestamptz+interval '1 minute')::text`),w=await preview(x,2,a,b);
 const move=command(x,'reschedule',{...payload(w),start:a,end:b,reason:'Reviewed move'},2);
 const secondMove=command(x,'reschedule',{...payload(w),start:a,end:b,reason:'Reviewed move'},2);
 await race(x,move,secondMove,/maintenance_preview_stale/,'concurrent confirmed reschedules cannot reuse old revision');
}
{
 const x=await fixture('adjacent'),v=await preview(x);
 const other=await required(`begin;${actor(x)}select public.create_maintenance_request('${x.factory}','{"work_center_id":"${x.machine}","title":"Adjacent service","priority":"NORMAL","maintenance_kind":"PLANNED","estimated_duration_minutes":1,"separate_problem":true}',gen_random_uuid());commit;`);
 const y={...x,request:other,start:v.end};await required(`begin;${actor(x)}${command(y,'propose',{start:y.start},0)};commit;`);const w=await preview(y);
 await race(x,command(x,'confirm',payload(v)),command(y,'confirm',payload(w)),null,'valid half-open adjacent bookings both succeed');
}
{
 const x=await fixture('ownership');
 await required(`begin;${actor(x)}select public.configure_center_capabilities('${x.factory}','${x.independent}','[{"product_id":"${x.product}","rate":100,"rate_unit":"meter","setup_minutes":5}]');select public.configure_center_alternatives('${x.factory}','${x.machine}',array['${x.independent}'::uuid]);select public.plan_product_item('${x.factory}','${x.item}','${x.line}','${x.start}');select public.start_product_item('${x.factory}','${x.item}');select public.stop_machine('${x.factory}','${x.machine}','planned',null,'inspection','Explicit local stop');commit;`);
 const v=await preview(x); // Active production blocks it; the fingerprint must still bind OPEN ownership changes.
 await race(x,`select public.transfer_production('${x.factory}','${x.machine}','${x.independent}','Local ownership test')`,command(x,'confirm',payload(v)),/maintenance_preview_stale/,'actual OPEN alternative ownership changed after preview');
}
{
 const x=await fixture('authority'),v=await preview(x);
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values('${x.factory}','${x.viewer}','orders','view'),('${x.factory}','${x.viewer}','orders','edit');`);
 await race(x,`select private.maintenance_planning_lock('${x.factory}');delete from public.user_permissions where factory_id='${x.factory}' and user_id='${x.viewer}' and module='orders' and action='edit'`,command(x,'confirm',payload(v)),/permission_denied/,'permission revoked during wait rechecked',{privileged:true,user:x.viewer});
}
{
 const x=await fixture('old-snapshot'),v=await preview(x);
 const r=await sql(`begin isolation level repeatable read;${actor(x)}${command(x,'confirm',payload(v))};commit;`);
 assert.notEqual(r.code,0);assert.match(r.error,/maintenance_preview_stale/);report.push('PASS unsupported old transaction snapshot rejected');
}
await required('update private.maintenance_planning_activation set enabled=false;');
assert.equal(await required('select enabled from private.maintenance_planning_activation'),'f');
await writeFile(join(results,'contract-concurrency.json'),JSON.stringify({results:report,actualRaces:report.length-1,gate:false},null,2));
console.log(report.join('\n'));
