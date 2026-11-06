// Reused approved portable PostgreSQL only. Calculator output is persisted through
// the actual service-only RPC; no hosted service, token or table-write shortcut.
import {spawn} from 'node:child_process';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {calculateProductionLoss} from '../../src/utils/production-loss-impact.mjs';
const [bin,port,results]=process.argv.slice(2);
assert.match(port,/^\d+$/);assert.ok(resolve(results).includes('FactoryLean-Quality-Postgres-'));
const lit=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
function connection(name='maintenance-loss') {
 const child=spawn(join(bin,'psql.exe'),['-X','-q','-A','-t','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});
 let output='',error='',mark;
 const marked=new Promise(done=>mark=done),done=new Promise((done,reject)=>{
  child.stdout.on('data',b=>{output+=b;if(output.includes('LOSS_HELD'))mark();});
  child.stderr.on('data',b=>error+=b);child.on('error',reject);child.on('close',code=>done({code,output,error}));
 });
 child.stdin.write(`set application_name=${lit(name)};set lock_timeout='8s';set statement_timeout='15s';`);
 return {child,marked,done};
}
async function sql(statement){const c=connection();c.child.stdin.end(statement);return c.done;}
async function required(statement){const r=await sql(statement);assert.equal(r.code,0,r.error);return r.output.trim().split('\n').at(-1);}
const actor=(x,user=x.owner)=>`set local role authenticated;select set_config('request.jwt.claim.sub',${lit(user)},true);select set_config('request.jwt.claim.role','authenticated',true);`;
async function fail(statement,expected){const r=await sql(statement);assert.notEqual(r.code,0);assert.match(r.error,expected);}
async function fixture(label){return JSON.parse(await required(`select mp_test.released(${lit('loss-'+label)})`));}
async function input(x,user=x.owner){return JSON.parse(await required(`begin;${actor(x,user)}select public.production_loss_review_inputs(${lit(x.factory)},${lit(x.event)});commit;`));}
function calculation(i){const e={...i.event,stop_nature:i.correction?.stop_nature||i.event.stop_nature,planned_activity:i.correction?.planned_activity||i.event.planned_activity};
 const r=calculateProductionLoss(e,i.samples,i.actual,Date.now(),[],i.maintenance);assert.equal(r.readiness,'READY',JSON.stringify(r.missing));return {...r,input_hash:i.input_hash};}
const persist=(x,r,user=x.owner)=>`set local role service_role;select public.persist_production_loss_estimate(${lit(x.factory)},${lit(x.event)},${lit(user)},${lit(JSON.stringify(r))}::jsonb,${lit(r.maintenance_context.classification_revision)});`;
const unlink=x=>`select public.correct_maintenance_stop(${lit(x.factory)},${lit(x.event)},${lit(x.schedule)},2,'UNLINK','Local correction after closed stop',1,gen_random_uuid())`;
const classify=x=>`select public.correct_downtime_classification(${lit(x.factory)},${lit(x.event)},'planned',null,'cleaning','Local classification correction')`;
const report=[],races=[];
async function race(x,first,second,expected,label){
 const holder=connection('loss-holder'),name='loss-wait-'+randomUUID();holder.child.stdin.write(`begin;${actor(x)}${first};select 'LOSS_HELD';\n`);
 try {
  await Promise.race([holder.marked,holder.done.then(r=>{throw Error('Holder failed: '+r.error)}),new Promise((_,bad)=>setTimeout(()=>bad(Error('Holder timeout')),15000))]);
  const waiting=connection(name);waiting.child.stdin.end(`begin;${actor(x)}${second};commit;`);
  let blocked=false;for(let n=0;n<80;n++){
   if(await required(`select exists(select 1 from pg_stat_activity where application_name=${lit(name)} and wait_event_type='Lock')`)==='t'){blocked=true;break;}
   await new Promise(done=>setTimeout(done,20));
  }
  assert.ok(blocked,'actual protected lock wait required');holder.child.stdin.end('commit;');
  const pair=await Promise.all([holder.done,waiting.done]);assert.equal(pair[0].code,0,pair[0].error);
  if(expected){assert.notEqual(pair[1].code,0);assert.match(pair[1].error,expected);}else assert.equal(pair[1].code,0,pair[1].error);
  assert.ok(pair.every(r=>!r.error.includes('deadlock detected')));races.push(label);report.push('PASS '+label);
 }finally{if(!holder.child.stdin.writableEnded)holder.child.stdin.end('rollback;');}
}
async function state(x){return JSON.parse(await required(`begin;${actor(x)}select public.production_loss_maintenance_context(${lit(x.factory)},${lit(x.event)});commit;`));}
// Positive inventory baseline uses the existing protected Good/WIP test workflow.
await required("select quality_test.make_fixture('loss-conservation','meter',.35,10,5)");
const stockSQL=`select jsonb_build_object('entries',(select jsonb_agg(to_jsonb(x) order by x.id) from public.production_entries x),
 'balances',(select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.finished_goods_balances x),
 'sources',(select jsonb_agg(to_jsonb(x) order by x.id) from public.finished_goods_sources x),
 'movements',(select jsonb_agg(to_jsonb(x) order by x.id) from public.finished_goods_movements x),
 'allocations',(select jsonb_agg(to_jsonb(x) order by x.id) from public.finished_goods_source_allocations x),
 'wip',(select jsonb_agg(to_jsonb(x) order by x.id) from public.unfinished_lots x),
 'wip_moves',(select jsonb_agg(to_jsonb(x) order by x.id) from public.unfinished_movements x))`;
const beforeStock=await required(stockSQL);
{
 const x=await fixture('immutable');
 await required(`begin;${actor(x)}select public.approve_planned_downtime(${lit(x.factory)},${lit(x.event)},'Synthetic planned approval');commit;`);
 assert.equal(await required(`select count(*) from private.lean_occurrences where factory_id=${lit(x.factory)} and event_id=${lit(x.event)}`),'0');
 const i=await input(x),r=calculation(i);
 const beforeEvent=await required(`select to_jsonb(d) from public.downtime_events d where id=${lit(x.event)}`);
 const id=await required(`begin;${persist(x,r)}commit;`),saved=await required(`select result from public.production_loss_estimates where id=${lit(id)}`);
 assert.equal((await state(x)).review_state,'CURRENT');assert.equal(await required(`begin;${persist(x,r)}commit;`),id);
 await fail(`update public.production_loss_estimates set result='{}' where id=${lit(id)}`,/loss_estimate_locked/);
 await required(`begin;${actor(x)}${unlink(x)};commit;`);assert.equal((await state(x)).review_state,'EVIDENCE_CHANGED_AFTER_REVIEW');
 assert.equal(await required(`select result from public.production_loss_estimates where id=${lit(id)}`),saved);
 assert.equal(await required(`begin;${persist(x,r)}commit;`),id); // exact original actor/proof retry
 assert.equal(await required(`select to_jsonb(d) from public.downtime_events d where id=${lit(x.event)}`),beforeEvent);
 assert.equal(await required(`select count(*) from public.production_loss_estimates where event_id=${lit(x.event)}`),'1');
 assert.equal(await required(`select count(*) from private.lean_occurrences where factory_id=${lit(x.factory)} and event_id=${lit(x.event)}`),'0');
 report.push('PASS actual calculator zero-loss persistence, immutable history, original retry, frozen warning and unchanged physical event');
}
{
 const x=JSON.parse(await required("select mp_test.fixture('loss-unplanned-occurrence')"));
 const cause=await required(`select id from public.downtime_reasons where factory_id=${lit(x.factory)} and private.current_downtime_reason(factory_id,id) order by id limit 1`);
 assert.match(cause,/^[0-9a-f-]{36}$/);
 await required(`begin;${actor(x)}select public.configure_production_loss_profile(${lit(x.factory)},${lit(x.other_machine)},${lit(x.product)},false,true,.2,.3,'kg');select public.plan_product_item(${lit(x.factory)},${lit(x.item)},${lit(x.other_line)},clock_timestamp()+interval '.3 seconds');select public.change_status(${lit(x.factory)},${lit(x.other_machine)},'running');commit;`);
 await required('select pg_sleep(.35)');
 x.event=await required(`begin;${actor(x)}select public.stop_machine(${lit(x.factory)},${lit(x.other_machine)},'unplanned',${lit(cause)},null,'Local real stop');commit;`);
 await required(`begin;${actor(x)}select public.change_status(${lit(x.factory)},${lit(x.other_machine)},'idle');select public.approve_downtime_cause(${lit(x.factory)},${lit(x.event)},${lit(cause)},'Approved synthetic breakdown');commit;`);
 const r=calculation(await input(x));assert.equal(r.maintenance_context.operation,'NONE');assert.equal(r.estimated_total_scrap,.5);assert.ok(r.effective_loss_minutes>0);
 const id=await required(`begin;${persist(x,r)}commit;`);assert.equal(await required(`begin;${persist(x,r)}commit;`),id);
 assert.equal(await required(`select count(*) from private.lean_occurrences where factory_id=${lit(x.factory)} and event_id=${lit(x.event)}`),'1');
 report.push('PASS real unplanned legacy loss and once-only Scrap, one positive Lean occurrence after persistence/retry');
}
{
 const x=await fixture('rollback'),r=calculation(await input(x));
 const abort=`create function pg_temp.abort_loss() returns trigger language plpgsql as $$begin raise exception 'forced_loss_failure';end$$;create trigger local_abort_loss after insert on public.production_loss_estimates for each row execute function pg_temp.abort_loss();`;
 await fail(`begin;${abort}${persist(x,r)}commit;`,/forced_loss_failure/);
 assert.equal(await required(`select count(*) from public.production_loss_estimates where event_id=${lit(x.event)}`),'0');
 assert.ok(await required(`begin;${persist(x,r)}commit;`));report.push('PASS forced persistence failure rolls back, retry succeeds once');
}
for(const [label,first] of [['association',unlink],['classification',classify],['actuals',x=>`select public.record_production_loss_actuals(${lit(x.factory)},${lit(x.event)},.5,'kg',null,.2,.3,null,null,null)`],
 ['closed-event approval',x=>`select public.approve_planned_downtime(${lit(x.factory)},${lit(x.event)},'Concurrent planned approval')`]]) {
 const x=await fixture(label),r=calculation(await input(x));await race(x,first(x),persist(x,r),/loss_estimate_context_mismatch/,label+' first rejects stale persistence');
 assert.equal(await required(`select count(*) from public.production_loss_estimates where event_id=${lit(x.event)}`),'0');
}
{
 const x=await fixture('persist-first'),r=calculation(await input(x));await race(x,persist(x,r),unlink(x),null,'persistence first retains result then marks correction warning');
 assert.equal((await state(x)).review_state,'EVIDENCE_CHANGED_AFTER_REVIEW');
}
{
 const x=await fixture('retry'),r=calculation(await input(x));await race(x,persist(x,r),persist(x,r),null,'two identical actor/proof retries produce one result');
 assert.equal(await required(`select count(*) from public.production_loss_estimates where event_id=${lit(x.event)}`),'1');
}
{
 const x=await fixture('permissions');
 await required(`begin;${actor(x)}select public.set_user_permissions(${lit(x.factory)},${lit(x.worker)},'[{"module":"factory","action":"view"},{"module":"downtime","action":"view"},{"module":"downtime","action":"edit"}]'::jsonb);commit;`);
 const r=calculation(await input(x,x.worker));
 await race(x,`reset role;select private.maintenance_planning_lock(${lit(x.factory)});delete from public.user_permissions where factory_id=${lit(x.factory)} and user_id=${lit(x.worker)} and module='downtime'`,persist(x,r,x.worker),/permission_denied/,'authority revoked during actual wait rechecked');
}
{
 const x=await fixture('package');
 await required(`begin;${actor(x)}select public.save_permission_package(${lit(x.factory)},'${x.pkg=randomUUID()}','{"name":"Local Loss package"}','[{"module":"downtime","action":"view"},{"module":"downtime","action":"edit"}]',0);select public.set_member_permission_packages(${lit(x.factory)},${lit(x.worker)},array['${x.pkg}']::uuid[],'{}');commit;`);
 const r=calculation(await input(x,x.worker));assert.ok(await required(`begin;${persist(x,r,x.worker)}commit;`));
 await fail(`begin;${persist({...x,factory:randomUUID()},r,x.worker)}commit;`,/permission_denied/);
 await fail(`begin;${actor(x,x.viewer)}select public.production_loss_review_inputs(${lit(x.factory)},${lit(x.event)});commit;`,/permission_denied/);
 report.push('PASS package-only persistence, actor/factory isolation and unauthorized reads');
}
{
 const x=await fixture('old-snapshot'),r=calculation(await input(x));
 await fail(`begin isolation level repeatable read;${persist(x,r)}commit;`,/loss_estimate_context_mismatch/);report.push('PASS old transaction snapshots fail closed');
 // A pre-policy saved result has an explicit unknown comparison state, never a guessed comparison.
 await required(`insert into public.production_loss_estimates(factory_id,event_id,model_version,result,recorded_by) values(${lit(x.factory)},${lit(x.event)},1,'{"readiness":"READY","model_version":1,"assumptions":[]}',${lit(x.owner)})`);
 assert.equal((await state(x)).review_state,'EVIDENCE_COMPARISON_UNKNOWN');report.push('PASS legacy saved estimate comparison is explicitly unknown');
}
assert.equal(await required(stockSQL),beforeStock);report.push('PASS nonempty Good/Scrap/WIP/source movement and allocation conservation');
assert.equal(await required('select enabled from private.maintenance_planning_activation'),'f');
await writeFile(join(results,'loss-concurrency.json'),JSON.stringify({actualRaces:races.length,races,checks:report,activation:false},null,2));
console.log(report.join('\n'));
