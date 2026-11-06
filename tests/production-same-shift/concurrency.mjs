import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {spawn} from 'node:child_process';import {randomUUID} from 'node:crypto';
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-SameShift-SQL-location.txt'),'utf8').trim(),c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,'')),q=s=>"'"+String(s).replaceAll("'","''")+"'";
assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.databasePort,55497);
function sql(input){return new Promise(resolve=>{const p=spawn(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p','55497','-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';p.stdout.on('data',v=>out+=v);p.stderr.on('data',v=>error+=v);p.on('close',code=>resolve({code,out:out.trim(),error}));p.stdin.end(input);});}
async function required(query){const r=await sql(query);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select inet_server_addr()='127.0.0.1'::inet and inet_server_port()=55497 and current_database()='factory_lean_quality_local'"),'t');
async function wait(name,event){for(let i=0;i<120;i++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${q(name)} and ${event==='Lock'?"wait_event_type='Lock'":"wait_event='PgSleep'"})`)==='t')return;await new Promise(r=>setTimeout(r,20));}throw Error('Expected wait not observed: '+name);}
const as=x=>`do $$begin perform set_config('request.jwt.claim.sub',${q(x.owner)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;set local role authenticated;`;
const results=[];
for(const same of [true,false]){
 const x=JSON.parse(await required(`select late_test.new_context(${q('same-shift-race-'+same)},3600,true)`));
 const p=JSON.parse(await required(`do $$begin perform set_config('request.jwt.claim.sub',${q(x.owner)},false);end$$;select same_shift_test.payload(${q(JSON.stringify(x))},1)`)),id=randomUUID(),call=key=>`select public.record_manufactured_output(${q(x.factory)},${q(JSON.stringify(p))},${q(key)})`;
 const first=sql(`set application_name='same-shift-first';begin;${as(x)}${call(id)};select pg_sleep(.5);commit;`);await wait('same-shift-first','Sleep');
 const second=sql(`set application_name='same-shift-second';begin;${as(x)}${call(same?id:randomUUID())};commit;`);await wait('same-shift-second','Lock');
 const a=await first,b=await second;assert.equal(a.code,0,a.error);if(same){assert.equal(b.code,0,b.error);assert.match(b.out,/"replayed": true/);}else{assert.notEqual(b.code,0);assert.match(b.error,/recording_stale_context/);}
 assert.equal(await required(`select count(*) from public.production_entries where factory_id=${q(x.factory)}`),'1');results.push({sameUuid:same,observedWait:true,oneEntry:true});
}
const x=JSON.parse(await required("select late_test.new_context('same-shift-lock-expiry',2.5,true)")),p=JSON.parse(await required(`do $$begin perform set_config('request.jwt.claim.sub',${q(x.owner)},false);end$$;select same_shift_test.payload(${q(JSON.stringify(x))},1)`));
const hold=sql(`set application_name='same-shift-expiry-hold';begin;select pg_advisory_xact_lock(hashtextextended(${q(x.factory)},0));select pg_sleep(2.8);commit;`);await wait('same-shift-expiry-hold','Sleep');
const write=sql(`set application_name='same-shift-expiring';begin;${as(x)}select public.record_manufactured_output(${q(x.factory)},${q(JSON.stringify(p))},${q(randomUUID())});commit;`);await wait('same-shift-expiring','Lock');await hold;const rejected=await write;assert.notEqual(rejected.code,0);assert.match(rejected.error,/recording_shift_unavailable|recording_shift_expired|recording_stale_context/);assert.equal(await required(`select count(*)from public.production_entries where factory_id=${q(x.factory)}`),'0');results.push({shiftExpiredDuringLockWait:true,observedWait:true,noEntries:true});
fs.writeFileSync(path.join(root,'concurrency.json'),JSON.stringify(results,null,2));console.log('PASS: three observed concurrency/deadline groups; no duplicate recording');
