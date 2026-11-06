import fs from'node:fs';import assert from'node:assert/strict';import{spawn}from'node:child_process';import{randomUUID}from'node:crypto';import{sql,root,c,guard,quote}from'./local.mjs';
const prefix=fs.readFileSync('tests/e2e-consolidated/measurement.sql','utf8').split('do $$declare x jsonb;f uuid;i uuid;before_jobs')[0];
if(sql("select to_regnamespace('measurement_test') is not null")==='f')sql(guard+prefix+'commit;');
const actor=c.context.owner,reports=[];
function connection(query){return new Promise((resolve,reject)=>{const p=spawn(c.bin+'/psql.exe',['-X','-qAt','-h','127.0.0.1','-p',String(c.databasePort),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>resolve({code,out,error}));p.stdin.end(query);});}
async function wait(name,type){for(let i=0;i<20;i++){if(sql('select exists(select 1 from pg_stat_activity where application_name='+quote(name)+' and '+(type==='Lock'?"wait_event_type='Lock'":"wait_event='PgSleep'")+')')==='t')return;await new Promise(r=>setTimeout(r,20));}throw Error('Expected '+type+' '+name);}
const begin=name=>'begin;'+guard+'set application_name='+quote(name)+';set local request.jwt.claim.sub='+quote(actor)+';set local role authenticated;';
for(const kind of['same UUID','different UUID','late original recording']){
 const x=JSON.parse(sql('begin;'+guard+"select measurement_test.fixture('race-"+randomUUID().slice(0,8)+"',true);commit;"));
 sql('begin;'+guard+"select set_config('request.jwt.claim.sub',"+quote(actor)+",true);select measurement_test.quality("+quote(JSON.stringify(x))+",58,58);commit;");
 const f=x.factory,o=x.output,key=randomUUID(),revision=sql('select max(revision) from private.manufactured_output_events where output_id='+quote(o));
 const command=k=>'select public.plan_measurement_makeup('+quote(f)+','+quote(o)+','+quote(JSON.stringify({quantity:'2',recording_complete_confirmation:true}))+','+revision+','+quote(k)+');';
 const recording=kind==='late original recording'?sql('begin;'+guard+"select set_config('request.jwt.claim.sub',"+quote(actor)+",true);select output2_test.payload("+quote(JSON.stringify(x))+',2);commit;').split('\n').at(-1):null;
 const a=connection(begin('measurement-a')+command(key)+'select pg_sleep(8);commit;');await wait('measurement-a','Sleep');
 const competing=kind==='late original recording'?'select public.record_manufactured_output('+quote(f)+','+quote(recording)+','+quote(randomUUID())+');':command(kind==='same UUID'?key:randomUUID());
 const b=connection(begin('measurement-b')+competing+'commit;');await wait('measurement-b','Lock').catch(async e=>{console.log(await b);throw e;});const [one,two]=await Promise.all([a,b]);assert.equal(one.code,0,one.error);
 if(kind==='same UUID')assert.equal(two.code,0,two.error);else{assert.notEqual(two.code,0);assert.match(two.error,kind==='different UUID'?/output_measurement_unavailable/:/output_measurement_work_committed|recording_context|recording_stale/);}
 assert.equal(sql('select count(*) from private.production_compensation where output_id='+quote(o)+" and source_kind='MEASUREMENT'"),'1');assert.equal(sql('select count(*) from public.production_entries where order_id='+quote(x.item)),'1');
 reports.push({kind,observedLock:true,makeupJobs:1,originalEntries:1});
}
fs.writeFileSync(root+'/measurement-concurrency.json',JSON.stringify(reports,null,2));console.log(reports);
