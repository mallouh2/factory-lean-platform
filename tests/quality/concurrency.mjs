// Called only by run-local.ps1 while its dedicated disposable loopback cluster runs.
import {spawn} from 'node:child_process';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {setTimeout as pause} from 'node:timers/promises';
const [bin,port,results]=process.argv.slice(2);
assert.match(port,/^\d+$/);assert.ok(resolve(results).includes('FactoryLean-Quality-Postgres-'));
const psql=join(bin,'psql.exe');
function sql(statement){return new Promise((done,reject)=>{
 const child=spawn(psql,['-X','-q','-A','-t','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});
 let output='',error='';child.stdout.on('data',v=>output+=v);child.stderr.on('data',v=>error+=v);child.on('error',reject);child.on('close',code=>done({code,output,error}));child.stdin.end(statement);
});}
async function required(statement){const r=await sql(statement);assert.equal(r.code,0,r.error);return r.output.trim();}
await required(`do $$declare x quality_test.fixtures;s uuid;begin
 for i in 1..4 loop
 perform quality_test.make_fixture('concurrent-'||i,'meter',.35,case when i=4 then 200 else 100 end);
 select * into x from quality_test.fixtures where name='concurrent-'||i;
 select id into s from public.finished_goods_sources where entry_id=x.entry_id;
 perform public.source_stock_command(x.factory_id,'identify',jsonb_build_object('source',s,'quantity','100','label','CONCURRENT-'||i,'physically_identified',true),'[]',gen_random_uuid());
 end loop;end$$;`);
const fixtures=JSON.parse(await required(`select jsonb_agg(to_jsonb(x)||jsonb_build_object('source',s.id,'reason',r.id)) from quality_test.fixtures x join public.finished_goods_sources s on s.entry_id=x.entry_id join lateral(select id from public.quality_reasons where factory_id=x.factory_id and not is_other limit 1)r on true where x.name like 'concurrent-%';`));
for(const x of fixtures)for(const key of ['factory_id','actor_id','source','reason','product_id'])assert.match(x[key],/^[\da-f-]{36}$/);
const wrap=(x,statement)=>`begin; set local role authenticated;select set_config('request.jwt.claim.sub','${x.actor_id}',true);select set_config('request.jwt.claim.role','authenticated',true);${statement};select pg_sleep(.3);commit;`;
const reject=(x,qty,id)=>`select public.quality_command('${x.factory_id}','reject','${JSON.stringify({source:x.source,quantity:qty,reason:x.reason,disposition:'SCRAP',actual_scrap_kg:String(Number(qty)*.35),physically_identified:true})}'::jsonb,'${id}')`;
const transcript=[];
let x=fixtures.find(x=>x.name==='concurrent-1'),id=randomUUID();
let pair=await Promise.all([sql(wrap(x,reject(x,'60',id))),sql(wrap(x,reject(x,'60',id)))]);
assert.ok(pair.every(r=>r.code===0),JSON.stringify(pair));
assert.equal(await required(`select count(*)||':'||sum(quantity)::text from public.quality_rejections where factory_id='${x.factory_id}'`),'1:60');
assert.equal(await required(`select quantity_available::text from public.finished_goods_sources where id='${x.source}'`),'40');
transcript.push('PASS simultaneous identical retry: one rejection, one stock debit, one notification');
x=fixtures.find(x=>x.name==='concurrent-2');
pair=await Promise.all([sql(wrap(x,reject(x,'80',randomUUID()))),sql(wrap(x,reject(x,'80',randomUUID())))]);
assert.equal(pair.filter(r=>r.code===0).length,1);assert.match(pair.find(r=>r.code!==0).error,/quality_unavailable/);
assert.equal(await required(`select quantity_available::text from public.finished_goods_sources where id='${x.source}'`),'20');
transcript.push('PASS simultaneous competing rejections: one accepted, one rolled back; no overdraw');
x=fixtures.find(x=>x.name==='concurrent-3');
const out=`select public.source_stock_command('${x.factory_id}','adjust','${JSON.stringify({product:x.product_id,unit:'meter',quantity:'-60',reason:'Concurrent physical issue'})}'::jsonb,'${JSON.stringify([{source_id:x.source,quantity:'60'}])}'::jsonb,'${randomUUID()}')`;
pair=await Promise.all([sql(wrap(x,reject(x,'60',randomUUID()))),sql(wrap(x,out))]);
assert.equal(pair.filter(r=>r.code===0).length,1);assert.match(pair.find(r=>r.code!==0).error,/quality_unavailable|source_unavailable|fulfillment_insufficient|fulfillment_stock_committed/);
assert.equal(await required(`select quantity_available::text from public.finished_goods_sources where id='${x.source}'`),'40');
assert.equal(await required(`select on_hand::text from public.finished_goods_balances where factory_id='${x.factory_id}'`),'40');
transcript.push('PASS rejection versus stock out: no shared-stock double consumption');
x=fixtures.find(x=>x.name==='concurrent-4');
await required(wrap(x,`do $$declare so uuid;begin for i in 1..2 loop
 so:=public.create_sales_order('${x.factory_id}',jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id','${x.product_id}','quantity',80,'unit','meter'))));
 perform public.approve_sales_order('${x.factory_id}',so);end loop;end$$`));
const lines=JSON.parse(await required(`select jsonb_agg(id order by id) from public.sales_order_lines where factory_id='${x.factory_id}'`));
const reserve=(line,retry)=>`select public.source_stock_command('${x.factory_id}','reserve','${JSON.stringify({sales_line_id:line})}'::jsonb,'${JSON.stringify([{source_id:x.source,quantity:'80'}])}'::jsonb,'${retry}')`;
pair=await Promise.all(lines.map(line=>sql(wrap(x,reserve(line,randomUUID())))));
assert.equal(pair.filter(r=>r.code===0).length,1);assert.match(pair.find(r=>r.code!==0).error,/source_unavailable/);
assert.equal(await required(`select private.source_reserved('${x.factory_id}','${x.source}')||':'||b.on_hand||':'||b.reserved from public.finished_goods_balances b where b.factory_id='${x.factory_id}'`),'80:200:160');
assert.equal(await required(`select count(*) from public.finished_goods_source_reservations where factory_id='${x.factory_id}'`),'1');
transcript.push('PASS competing Sales source reservations: one 80 allocation, loser rolls back; pooled 160 remains valid');
const winner=await required(`select sales_line_id from public.finished_goods_source_reservations where factory_id='${x.factory_id}'`),reserveRetry=randomUUID();
pair=await Promise.all([sql(wrap(x,reserve(winner,reserveRetry))),sql(wrap(x,reserve(winner,reserveRetry)))]);
assert.ok(pair.every(r=>r.code===0),JSON.stringify(pair));
assert.equal(await required(`select count(*) from public.fulfillment_commands where factory_id='${x.factory_id}' and request_id='${reserveRetry}'`),'1');
assert.equal(await required(`select private.source_reserved('${x.factory_id}','${x.source}')`),'80');
const unavailable=await sql(wrap(x,reject(x,'21',randomUUID())));assert.notEqual(unavailable.code,0);assert.match(unavailable.error,/quality_unavailable/);
await required(wrap(x,reject(x,'20',randomUUID())));
assert.equal(await required(`select b.on_hand||':'||b.reserved||':'||s.quantity_available||':'||private.source_reserved('${x.factory_id}',s.id)||':'||u.quantity from public.finished_goods_balances b join public.finished_goods_sources s on s.factory_id=b.factory_id join private.finished_goods_unattributed u on u.factory_id=b.factory_id and u.product_id=b.product_id and u.unit=b.unit where s.id='${x.source}'`),'180:160:80:80:100');
transcript.push('PASS reservation retry and Quality free-quantity boundary: no duplicate assignment or rejection of reserved stock');
// Exercise the actual COMMIT boundary, in addition to rollback-suite SET CONSTRAINTS checks.
await required(`do $$declare f quality_test.fixtures;s uuid;r uuid;q uuid;lot uuid;mr uuid;rev integer;e uuid;begin
 perform quality_test.make_fixture('rework-commit','piece',.25,100);select * into f from quality_test.fixtures where name='rework-commit';
 select id into s from public.finished_goods_sources where entry_id=f.entry_id;select id into r from public.quality_reasons where factory_id=f.factory_id and not is_other limit 1;
 perform public.source_stock_command(f.factory_id,'identify',jsonb_build_object('source',s,'quantity','100','label','COMMIT-ORIGINAL','physically_identified',true),'[]',gen_random_uuid());
 q:=public.quality_command(f.factory_id,'reject',jsonb_build_object('source',s,'quantity','10','reason',r,'disposition','REWORK','physically_identified',true),gen_random_uuid());
 select lot_id into lot from public.quality_rejections where id=q;
 mr:=public.quality_command(f.factory_id,'request_rework',jsonb_build_object('rejection',q,'lot',lot,'quantity','10'),gen_random_uuid());select revision into rev from public.material_requests where id=mr;
 perform public.supply_command(f.factory_id,'material_change',jsonb_build_object('id',mr,'revision',rev,'action','issue'),gen_random_uuid());
 e:=(public.record_lean_production(f.factory_id,jsonb_build_object('unit_kind','line','production_unit',f.line_id,'item',f.item_id,'technician',f.technician_id,'good',10,'discarded_quantity',0,'scrap_kg',0,'unfinished',0,'input_lot',lot,'input_quantity',10),gen_random_uuid())->>'id')::uuid;
 select id into s from public.finished_goods_sources where entry_id=e;
 perform public.source_stock_command(f.factory_id,'identify',jsonb_build_object('source',s,'quantity','10','label','COMMIT-REWORK','physically_identified',true),'[]',gen_random_uuid());end$$;`);
x=JSON.parse(await required(`select to_jsonb(f)||jsonb_build_object('source',s.id,'rework_entry',s.entry_id) from quality_test.fixtures f join public.finished_goods_sources s on s.factory_id=f.factory_id join public.production_entries e on e.id=s.entry_id where f.name='rework-commit' and e.input_lot_id is not null`));
const correctionRetry=randomUUID(),correction=kg=>`select public.source_stock_command('${x.factory_id}','correct','${JSON.stringify({entry:x.rework_entry,good:7,discarded_quantity:3,scrap_kg:kg,unfinished:0,reason:'Commit-boundary rework correction'})}'::jsonb,'${JSON.stringify([{source_id:x.source,quantity:'3'}])}'::jsonb,'${correctionRetry}')`;
const invalidCommit=await sql(wrap(x,correction('0')));assert.notEqual(invalidCommit.code,0);assert.match(invalidCommit.error,/quality_weight/);
assert.equal(await required(`select b.on_hand||':'||s.quantity_available||':'||e.effective_good||':'||e.effective_scrap_kg||':'||(select count(*) from public.production_entry_corrections where entry_id=e.id)||':'||(select count(*) from public.fulfillment_commands where factory_id=e.factory_id and request_id='${correctionRetry}') from public.finished_goods_balances b join public.finished_goods_sources s on s.factory_id=b.factory_id join public.production_entries e on e.id=s.entry_id where s.id='${x.source}'`),'100:10:10:0:0:0');
await required(wrap(x,correction('0.75')));await required(wrap(x,correction('0.75')));
assert.equal(await required(`select b.on_hand||':'||s.quantity_available||':'||e.effective_good||':'||e.effective_scrap_kg||':'||(select count(*) from public.production_entry_corrections where entry_id=e.id)||':'||(select count(*) from public.finished_goods_movements where entry_id=e.id and kind='production_correction') from public.finished_goods_balances b join public.finished_goods_sources s on s.factory_id=b.factory_id join public.production_entries e on e.id=s.entry_id where s.id='${x.source}'`),'97:7:7:0.75:1:1');
assert.equal(await required(`select quantity_available from public.unfinished_lots where factory_id='${x.factory_id}' and quality_rejection_id is not null`),'0');
transcript.push('PASS deferred KG at COMMIT: invalid correction fully rolled back; valid zero-to-positive correction and replay debit once');
// Authority must be checked after waiting for the same factory transaction lock.
for(const operation of ['reject','adjust']){
 await required(`select quality_test.make_fixture('authority-${operation}','meter',.35,100);`);
 const fixture=JSON.parse(await required(`select to_jsonb(x)||jsonb_build_object('source',s.id,'reason',r.id) from quality_test.fixtures x join public.finished_goods_sources s on s.entry_id=x.entry_id join lateral(select id from public.quality_reasons where factory_id=x.factory_id and not is_other limit 1)r on true where x.name='authority-${operation}';`));
 await required(wrap(fixture,`select public.source_stock_command('${fixture.factory_id}','identify','${JSON.stringify({source:fixture.source,quantity:'100',label:'AUTHORITY',physically_identified:true})}'::jsonb,'[]','${randomUUID()}')`));
 const actor=randomUUID(),module=operation==='reject'?'quality':'warehouse',action=operation==='reject'?'create':'edit';
 await required(`insert into auth.users(id,email,email_confirmed_at) values('${actor}','${actor}@isolated.invalid',now());insert into public.memberships(factory_id,user_id,display_name,status,is_owner) values('${fixture.factory_id}','${actor}','Authority fixture','approved',false);insert into public.user_permissions(factory_id,user_id,module,action) values('${fixture.factory_id}','${actor}','factory','view'),('${fixture.factory_id}','${actor}','${module}','view'),('${fixture.factory_id}','${actor}','${module}','${action}');`);
 const name='quality-revoke-'+operation;
 const revoke=sql(`set application_name='${name}';begin;select pg_advisory_xact_lock(hashtextextended('${fixture.factory_id}',0));select pg_sleep(1.5);delete from public.user_permissions where factory_id='${fixture.factory_id}' and user_id='${actor}' and module='${module}' and action='${action}';commit;`);
 let locked=false;for(let i=0;i<40;i++){if(await required(`select exists(select 1 from pg_locks l join pg_stat_activity a on a.pid=l.pid where a.application_name='${name}' and l.locktype='advisory' and l.granted)`) === 't'){locked=true;break;}await pause(25);}
 assert.ok(locked,'revocation session acquired factory lock');
 const statement=operation==='reject'?reject(fixture,'1',randomUUID()):`select public.source_stock_command('${fixture.factory_id}','adjust','${JSON.stringify({product:fixture.product_id,unit:'meter',quantity:'-1',reason:'Revoked while waiting'})}'::jsonb,'${JSON.stringify([{source_id:fixture.source,quantity:'1'}])}'::jsonb,'${randomUUID()}')`;
 const pending=sql(wrap({...fixture,actor_id:actor},statement));assert.equal((await revoke).code,0);const denied=await pending;
 assert.notEqual(denied.code,0);assert.match(denied.error,/permission_denied/);
 assert.equal(await required(`select quantity_available::text from public.finished_goods_sources where id='${fixture.source}'`),'100');
 transcript.push(`PASS ${operation} authority revoked while waiting: post-lock check denied mutation`);
}
await writeFile(join(results,'concurrency.txt'),transcript.join('\n')+'\n');
console.log(transcript.join('\n'));
