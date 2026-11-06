// Actual multi-connection reads and writes in the disposable loopback fixture only.
import {spawn} from 'node:child_process';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const [bin,port,output]=process.argv.slice(2);assert.match(port,/^\d+$/);assert.ok(resolve(output).includes('FactoryLean-Quality-Postgres-'));
function sql(text){return new Promise((done,reject)=>{const child=spawn(join(bin,'psql.exe'),['-X','-q','-A','-t','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>error+=b);child.on('error',reject);child.on('close',code=>done({code,out,error}));child.stdin.end(text);});}
async function required(text){const r=await sql(text);assert.equal(r.code,0,r.error);return r.out.trim();}
const reports=[];
await required('update private.maintenance_planning_activation set enabled=false;');
const x=JSON.parse(await required("select mp_test.fixture('reader-races')"));
const a=await required("select (clock_timestamp()+interval '2 days')::text");
const actor=`set local role authenticated;select set_config('request.jwt.claim.sub','${x.owner}',true);select set_config('request.jwt.claim.role','authenticated',true);`;
const preview=`select public.maintenance_planning_preview('${x.factory}','${x.request}','${a}',null,2,0)`;
// Read-only transaction verifies the reader call graph cannot write, even under SECURITY DEFINER.
const first=await required(`begin read only;${actor}${preview};commit;`);assert.match(first,/"capacity": "CLEAR"/);reports.push('PASS authenticated read-only preview transaction');
const pair=await Promise.all([
 sql(`begin read only;${actor}${preview};select pg_sleep(.5);commit;`),
 sql(`begin;${actor}select public.plan_product_item('${x.factory}','${x.item}','${x.line}','${a}');commit;`)
]);assert.ok(pair.every(r=>r.code===0),JSON.stringify(pair));
const later=await required(`begin read only;${actor}${preview};commit;`);assert.match(later,/"capacity": "BLOCKED"/);reports.push('PASS nonbinding preview versus concurrent production plan; subsequent preview rechecks');
await required(`begin;${actor}select public.maintenance_planning_command('${x.factory}','${x.request}','propose',jsonb_build_object('start','${a}'),0,gen_random_uuid());commit;`);
const history=`select public.maintenance_planning_history('${x.factory}','${x.request}',1,null,1)`;
const append=await Promise.all([
 sql(`begin read only;${actor}${history};select pg_sleep(.4);commit;`),
 sql(`begin;${actor}select public.maintenance_planning_command('${x.factory}','${x.request}','propose',jsonb_build_object('start','${a}','reason','Concurrent append'),1,gen_random_uuid());commit;`)
]);assert.ok(append.every(r=>r.code===0),JSON.stringify(append));
const frozen=await required(`begin read only;${actor}${history};commit;`);assert.match(frozen,/"through_revision": 1/);assert.doesNotMatch(frozen,/"revision": 2/);reports.push('PASS immutable history high-water during concurrent append');
await required(`begin read only;${actor}select public.maintenance_planning_gaps('${x.factory}','${x.request}','${a}','${a}'::timestamptz+interval '1 day',2,2);select public.maintenance_planning_history('${x.factory}','${x.request}');commit;`);
reports.push('PASS authenticated gaps/history read-only transactions');
assert.equal(await required('select enabled from private.maintenance_planning_activation'),'f');reports.push('PASS readers retain disabled gate');
await writeFile(join(output,'readers-concurrency.json'),JSON.stringify(reports,null,2));console.log(reports.join('\n'));
