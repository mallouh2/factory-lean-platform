// Isolated disposable PostgreSQL only. No environment variables or remote clients.
import {spawn} from 'node:child_process';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const [bin,port,results]=process.argv.slice(2);
assert.match(port,/^\d+$/);assert.ok(resolve(results).includes('FactoryLean-Quality-Postgres-'));
function sql(statement){return new Promise((done,reject)=>{
 const child=spawn(join(bin,'psql.exe'),['-X','-q','-A','-t','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});
 let output='',error='';child.stdout.on('data',v=>output+=v);child.stderr.on('data',v=>error+=v);child.on('error',reject);child.on('close',code=>done({code,output,error}));child.stdin.end(statement);
});}
async function required(statement){const r=await sql(statement);assert.equal(r.code,0,r.error);return r.output.trim();}
const wrap=(x,statement)=>`begin;set local lock_timeout='5s';set local role authenticated;select set_config('request.jwt.claim.sub','${x.owner}',true);select set_config('request.jwt.claim.role','authenticated',true);${statement};select pg_sleep(.2);commit;`;
const command=(x,op,payload,revision,id=randomUUID(),r=x.request)=>`select mp_test.command('${x.factory}','${r}','${op}','${JSON.stringify(payload)}',${revision},'${id}')`;
const report=[];
// Test-only owner of this fresh local cluster enables the protected gate.
await required('update private.maintenance_planning_activation set enabled=true;');
for(let n=1;n<=4;n++){
 const x=JSON.parse(await required(`select mp_test.fixture('concurrency-${n}')`));
 const start=await required(`select (clock_timestamp()+interval '2 days')::text`);
 await required(`select set_config('request.jwt.claim.sub','${x.owner}',false);select mp_test.plan('${JSON.stringify(x)}','${start}')`);
 let pair;
 if(n===1){const retry=randomUUID();pair=await Promise.all([sql(wrap(x,command(x,'confirm',{},1,retry))),sql(wrap(x,command(x,'confirm',{},1,retry)))]);
 assert.ok(pair.every(r=>r.code===0),JSON.stringify(pair));
 assert.equal(await required(`select count(*) from public.maintenance_commands where factory_id='${x.factory}' and operation='planning:confirm'`),'1');
 report.push('PASS concurrent identical confirmation retry: one command/history/reservation');
 }else if(n===2){
 const other=await required(`select set_config('request.jwt.claim.sub','${x.owner}',false);select public.create_maintenance_request('${x.factory}','${JSON.stringify({work_center_id:x.machine,title:'Other window',priority:'NORMAL',maintenance_kind:'PLANNED',estimated_duration_minutes:1,separate_problem:true})}',gen_random_uuid())`);
 const r=other.split('\n').at(-1);assert.match(r,/^[\da-f-]{36}$/);
 await required(`select set_config('request.jwt.claim.sub','${x.owner}',false);select mp_test.plan('${JSON.stringify({...x,request:r})}','${start}')`);
 pair=await Promise.all([sql(wrap(x,command(x,'confirm',{},1))),sql(wrap(x,command(x,'confirm',{},1,randomUUID(),r)))]);
 assert.equal(pair.filter(r=>r.code===0).length,1);assert.match(pair.find(r=>r.code!==0).error,/maintenance_capacity_reserved|maintenance_preview_stale/);
 report.push('PASS competing maintenance confirmations: exactly one confirmed');
 }else if(n===3){
 pair=await Promise.all([sql(wrap(x,command(x,'confirm',{},1))),sql(wrap(x,`select public.plan_product_item('${x.factory}','${x.item}','${x.line}','${start}')`))]);
 assert.equal(pair.filter(r=>r.code===0).length,1);assert.match(pair.find(r=>r.code!==0).error,/maintenance_capacity_reserved|maintenance_production_conflict|maintenance_preview_stale/);
 report.push('PASS production planning versus maintenance confirmation: mutual conflict, no double booking');
 }else{
 await required(`select set_config('request.jwt.claim.sub','${x.owner}',false);${command(x,'confirm',{},1)}`);
 pair=await Promise.all([sql(wrap(x,`select public.configure_center_capabilities('${x.factory}','${x.machine}','${JSON.stringify([{product_id:x.product,rate:100,rate_unit:'meter',setup_minutes:5}])}')`)),sql(wrap(x,`select public.plan_product_item('${x.factory}','${x.item}','${x.line}','${start}')`))]);
 assert.equal(pair[0].code,0,pair[0].error);assert.notEqual(pair[1].code,0);assert.ok(!pair.some(r=>/deadlock detected/.test(r.error)));
 report.push('PASS capability edit versus production planning: no deadlock, conflict remains protected');
 }
}
await writeFile(join(results,'maintenance-concurrency.json'),JSON.stringify(report,null,2));
console.log(report.join('\n'));
