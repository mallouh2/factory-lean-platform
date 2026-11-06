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
async function race(x,write,wait,expected,label,{privileged=false,secondPrivileged=false,user=x.owner}={}){
 const holder=connection('mp-contract-holder'),name='mp-contract-waiter-'+randomUUID();
 holder.child.stdin.write(`begin;${privileged?'':actor(x)}${write};select 'CONTRACT_HELD';\n`);
 try {
  await Promise.race([holder.marked,holder.done.then(r=>{throw Error('Holder failed: '+r.error);}),new Promise((_,fail)=>setTimeout(()=>fail(Error('Holder timeout')),15000))]);
  const second=connection(name);second.child.stdin.end(`begin;${secondPrivileged?'':actor(x,user)}${wait};commit;`);
  await waiterBlocked(name);holder.child.stdin.end('commit;');
  const pair=await Promise.all([holder.done,second.done]);assert.equal(pair[0].code,0,pair[0].error);
  if(expected){assert.notEqual(pair[1].code,0);assert.match(pair[1].error,expected);}else assert.equal(pair[1].code,0,pair[1].error);
  assert.ok(pair.every(r=>!r.error.includes('deadlock detected')));report.push('PASS '+label);
  await writeFile(join(results,'activation-concurrency-progress.json'),JSON.stringify(report,null,2));
 }finally{if(!holder.child.stdin.writableEnded)holder.child.stdin.end('rollback;');}
}
await required('update private.maintenance_planning_activation set enabled=true;');
{
 const x=await fixture('disable-first'),v=await preview(x);
 await race(x,'update private.maintenance_planning_activation set enabled=false',command(x,'confirm',payload(v)),/maintenance_planning_inactive/,'disable commits first: stale activated preview cannot confirm',{privileged:true});
 assert.equal(await required(`select state from public.maintenance_schedules where maintenance_request_id='${x.request}'`),'PROPOSED');
}
await required('update private.maintenance_planning_activation set enabled=true;');
{
 const x=await fixture('confirm-first'),v=await preview(x);
 await race(x,command(x,'confirm',payload(v)),'update private.maintenance_planning_activation set enabled=false',null,'confirmation holds gate until commit; disable waits',{secondPrivileged:true});
 assert.equal(await required(`select state from public.maintenance_schedules where maintenance_request_id='${x.request}'`),'CONFIRMED');
 assert.equal(await required('select enabled from private.maintenance_planning_activation'),'f');
}
await writeFile(join(results,'activation-concurrency.json'),JSON.stringify(report,null,2));
process.stdout.write(report.join('\n')+'\n');
