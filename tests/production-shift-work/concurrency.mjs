import {spawn} from 'node:child_process';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const [bin,port,output]=process.argv.slice(2);
assert.match(port,/^\d+$/);assert.ok(resolve(output).includes('FactoryLean-Shift-M1-'));
const quote=x=>"'"+String(x).replaceAll("'","''")+"'";
function sql(text){return new Promise((done,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>done({code,out:out.trim(),error}));p.stdin.end(text);});}
async function required(t){const r=await sql(t);assert.equal(r.code,0,r.error);return r.out;}
const x=JSON.parse(await required('select x from shift_test.context;'));
const actor=`do $$begin perform set_config('request.jwt.claim.sub','${x.owner}',true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;`;
const reports=[];
const page=JSON.parse(await required(`begin read only;${actor}set local role authenticated;select public.production_shift_work('${x.factory}');commit;`));
const cursor=page.next_cursor;
// Genuine separate connections: read-only snapshot versus normal protected finish.
const pair=await Promise.all([
 sql(`begin read only;${actor}set local role authenticated;select public.production_shift_work('${x.factory}');select pg_sleep(.3);commit;`),
 sql(`begin;${actor}set local role authenticated;select public.finish_product_item('${x.factory}','${x.active}');commit;`)
]);
assert.ok(pair.every(r=>r.code===0),JSON.stringify(pair));
const stale=await sql(`begin;${actor}set local role authenticated;select public.production_shift_work('${x.factory}',${quote(JSON.stringify(cursor))});commit;`);
assert.notEqual(stale.code,0);assert.match(stale.error,/shift_work_stale/);
reports.push('PASS concurrent read/finish is snapshot-safe; subsequent cursor restarts');
// Block configuration behind the established structure lock, then require its
// server timestamp to be sampled after the wait (not before acquiring the lock).
const holding=sql(`begin;set application_name='m1-structure-holder';select private.maintenance_planning_lock('${x.factory}');select pg_sleep(1.5);commit;`);
for(let k=0;k<50;k++){
 if(await required("select count(*) from pg_stat_activity where application_name='m1-structure-holder' and wait_event='PgSleep'")==='1')break;
 if(k===49)throw Error('lock holder did not become ready');
 await new Promise(r=>setTimeout(r,20));
}
const before=await required('select clock_timestamp()::text;');
const configured=sql(`begin;${actor}set local role authenticated;select public.configure_production_shift('${x.factory}','Concurrent rename','تعديل متزامن',${quote(page.occurrence.starts_at)}::timestamptz::time,${quote(page.occurrence.ends_at)}::timestamptz::time,'${x.shift}');commit;`);
const both=await Promise.all([holding,configured]);assert.ok(both.every(r=>r.code===0),JSON.stringify(both));
assert.equal(await required(`select recorded_at>${quote(before)}::timestamptz+interval '.5 seconds' and effective_from=${quote(page.occurrence.ends_at)}::timestamptz from private.production_shift_schedule_revisions where factory_id='${x.factory}' order by revision_no desc limit 1;`),'t');
reports.push('PASS configuration serializes on existing structure lock; timestamp after wait and current end preserved');
const descriptor=quote(JSON.stringify(page.occurrence));
const materials=await Promise.all([sql(`select private.materialize_production_occurrence('${x.factory}',${descriptor});`),sql(`select private.materialize_production_occurrence('${x.factory}',${descriptor});`)]);
assert.ok(materials.every(r=>r.code===0),JSON.stringify(materials));assert.equal(materials[0].out,materials[1].out);
assert.equal(await required(`select count(*) from private.production_shift_occurrences where factory_id='${x.factory}';`),'1');
reports.push('PASS concurrent private materialization yields one identical immutable occurrence');
assert.equal(await required('select enabled from private.maintenance_planning_activation'),'f');
reports.push('PASS existing Maintenance activation stays disabled in isolated tests');
await writeFile(join(output,'concurrency.json'),JSON.stringify(reports,null,2));console.log(reports.join('\n'));
