import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {spawn} from 'node:child_process';import {randomUUID} from 'node:crypto';
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-OperationalUX-SQL-location.txt'),'utf8').trim(),c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.databasePort,55498);
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
function sql(q){return new Promise(resolve=>{const p=spawn(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p','55498','-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';p.stdout.on('data',v=>out+=v);p.stderr.on('data',v=>error+=v);p.on('close',code=>resolve({code,out:out.trim(),error}));p.stdin.end(q);});}
async function required(q){const r=await sql(q);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select inet_server_addr()='127.0.0.1'::inet and inet_server_port()=55498 and current_database()='factory_lean_quality_local' and current_setting('data_directory')="+quote(path.join(root,'data').replaceAll('\\','/'))),'t');
const results=[];
for(const same of [true,false]){
 const x=JSON.parse(await required("select jsonb_build_object('factory',t.x->>'factory','owner',t.x->>'owner','output',h.id,'revision',(select max(revision)from private.manufactured_output_events where output_id=h.id),'groups',private.output_finding(h.factory_id,h.id)->'groups','rejected',private.output_finding(h.factory_id,h.id)->>'rejected','mass',private.output_finding(h.factory_id,h.id)->>'actual_rejected_kg','total',coalesce(private.output_finding(h.factory_id,h.id)->>'total',h.quantity::text))from ux_test.quality_context t join private.manufactured_outputs h on h.id=t.output limit 1"));
 const count=Number(await required(`select count(*)from private.manufactured_output_events where output_id=${quote(x.output)}`));
 const payload={groups:x.groups,rejected:x.rejected,total:x.total,actual_rejected_kg:x.mass,reason:'Concurrent local inspection confirmation'},key=randomUUID(),name='quality-race-'+randomUUID();
 const call=k=>`select public.manufactured_output_command(${quote(x.factory)},'QUALITY',${quote(x.output)},${quote(JSON.stringify(payload))}::jsonb,${x.revision},${quote(k)});`,auth=`select set_config('request.jwt.claim.sub',${quote(x.owner)},true);set local role authenticated;`;
 const a=sql(`begin;set application_name=${quote(name)};${auth}${call(key)}select pg_sleep(.7);commit;`);
 for(let i=0;i<100;i++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${quote(name)} and wait_event='PgSleep')`)==='t')break;if(i===99)throw Error('First inspection did not reach hold');await new Promise(r=>setTimeout(r,20));}
 const b=sql(`begin;set application_name=${quote(name+'-second')};${auth}${call(same?key:randomUUID())}commit;`);
 let observed=false;for(let i=0;i<100;i++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${quote(name+'-second')} and wait_event_type='Lock')`)==='t'){observed=true;break;}await new Promise(r=>setTimeout(r,10));}
 const [ra,rb]=await Promise.all([a,b]);assert.equal(ra.code,0,ra.error);assert.equal(rb.code,same?0:3,rb.error);if(!same)assert.match(rb.error,/output_revision/);assert.ok(observed);
 assert.equal(Number(await required(`select count(*)from private.manufactured_output_events where output_id=${quote(x.output)}`)),count+1);
 assert.equal(await required(`select not exists(select 1 from public.finished_goods_movements where factory_id=${quote(x.factory)})`),'t');results.push({sameUuid:same,observedWait:observed,oneDecision:true,noStockCredit:true});
}
fs.writeFileSync(path.join(root,'unified-quality-concurrency.json'),JSON.stringify(results,null,2));console.log(JSON.stringify(results));
