// Separate real connections, localhost only. Delays are test-only triggers/locks.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
const [bin,port,output]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.match(port,/^\d{4,5}$/);
function sql(text){return new Promise((done,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1']);let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>done({code,out:out.trim(),error}));p.stdin.end('\\set VERBOSITY verbose\n'+text);});}
async function required(text){const r=await sql(text);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const actor=x=>`do $$begin perform set_config('request.jwt.claim.sub',${quote(x.owner)},false);perform set_config('request.jwt.claim.role','authenticated',false);end$$;`;
async function fixture(label,seconds=30,completed=true){const x=JSON.parse(await required(`select late_test.new_context(${quote(label)},${seconds},${completed});`));await required(`update private.production_recording_v3_activation set enabled=true,schema_contract_version=3 where factory_id=${quote(x.factory)}`);return x;}
async function payload(x,q=2){return JSON.parse(await required(`${actor(x)}select late_test.payload(${quote(JSON.stringify(x))},${q});`));}
const command=(x,p,r=randomUUID(),name='m2-writer')=>`begin;set application_name=${quote(name)};${actor(x)}set local role authenticated;select public.record_lean_production(${quote(x.factory)},${quote(JSON.stringify(p))},${quote(r)});commit;`;
async function wait(name,event){for(let n=0;n<100;n++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${quote(name)} and ${event==='Lock'?"wait_event_type='Lock'":"wait_event='PgSleep'"})`)==='t')return;await new Promise(r=>setTimeout(r,15));}throw Error(`No observed ${event} for ${name}`);}
async function stock(x,q){assert.equal(await required(`select coalesce((select on_hand from public.finished_goods_balances where factory_id=${quote(x.factory)}),0)=${q}`),'t');}
await required(`create function late_test.delay() returns trigger language plpgsql as $$begin
 if old.original_scrap_kg is null and new.original_scrap_kg is not null then
 if new.notes='m2-test-delay' then perform pg_sleep(3);
 elsif new.notes='m2-test-expire' then perform pg_sleep(greatest(0,extract(epoch from ((select ends_at from private.production_shift_occurrences where factory_id=new.factory_id and occurrence_key=new.original_occurrence_key)-clock_timestamp())))+.2);end if;end if;return new;end$$;
 create trigger zzz_late_test_delay after update on public.production_entries for each row execute function late_test.delay();`);
const reports=[];
const append=reports.push.bind(reports);reports.push=(...rows)=>{for(const row of rows)console.log('PASS '+row);return append(...rows);};
{
 const x=await fixture('m2-identical'),p={...await payload(x),notes:'m2-test-delay'},r=randomUUID();
 const first=sql(command(x,p,r,'m2-identical-a'));await wait('m2-identical-a','PgSleep');
 const pending=await sql(`begin read only;${actor(x)}set local role authenticated;select public.production_recording_request_status(${quote(x.factory)},${quote(r)});commit;`);
 assert.equal(pending.code,0,pending.error);assert.equal(JSON.parse(pending.out).outcome,'UNKNOWN');
 const second=sql(command(x,p,r,'m2-identical-b'));await wait('m2-identical-b','Lock');
 const [a,b]=await Promise.all([first,second]);assert.equal(a.code,0,a.error);assert.equal(b.code,0,b.error);assert.equal(JSON.parse(a.out).entry_id,JSON.parse(b.out).entry_id);await stock(x,2);
 assert.equal(await required(`select count(*) from public.production_entries where factory_id=${quote(x.factory)}`),'1');
 reports.push('in-flight status is UNKNOWN; identical UUID waits, one entry/credit, same receipt');
}
{
 const x=await fixture('m2-expired-post',6),p={...await payload(x),notes:'m2-test-expire',unfinished:1,remaining_work:'Finish later'},r=randomUUID();
 const result=await sql(command(x,p,r));assert.notEqual(result.code,0);assert.match(result.error,/recording_shift_expired/);await stock(x,0);
 assert.equal(await required(`select count(*) from public.production_entries where factory_id=${quote(x.factory)}`),'0');
 assert.equal(await required(`select count(*) from public.finished_goods_sources where factory_id=${quote(x.factory)}`),'0');
 assert.equal(await required(`select count(*) from public.unfinished_lots where factory_id=${quote(x.factory)}`),'0');
 reports.push('expiry after KG/stock/WIP work rolls entire transaction back');
}
{
 const x=await fixture('m2-expired-lock',6),p=await payload(x);
 const holder=sql(`begin;set application_name='m2-structure-hold';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory+':structure')},0));select pg_sleep(greatest(0,extract(epoch from ((private.resolve_production_occurrence(${quote(x.factory)},clock_timestamp())#>>'{occurrence,ends_at}')::timestamptz-clock_timestamp())))+.2);commit;`);await wait('m2-structure-hold','PgSleep');
 const writer=sql(command(x,p,randomUUID(),'m2-structure-wait'));await wait('m2-structure-wait','Lock');
 const [a,b]=await Promise.all([holder,writer]);assert.equal(a.code,0);assert.notEqual(b.code,0);assert.match(b.error,/recording_shift_unavailable|recording_shift_expired/);await stock(x,0);
 reports.push('structure wait past shift deadline rejects without output');
}
{
 const x=await fixture('m2-replay-expiry',6),p=await payload(x),r=randomUUID();const first=await sql(command(x,p,r));assert.equal(first.code,0,first.error);
 await required(`select pg_sleep(greatest(0,extract(epoch from ((select ends_at from private.production_shift_occurrences where factory_id=${quote(x.factory)} and occurrence_key=${quote(p.recording_context.occurrence_key)})-clock_timestamp())))+.2);update private.production_recording_v3_activation set enabled=false where factory_id=${quote(x.factory)}`);
 const replay=await sql(command(x,p,r));assert.equal(replay.code,0,replay.error);assert.equal(JSON.parse(replay.out).entry_id,JSON.parse(first.out).entry_id);await stock(x,2);
 reports.push('committed replay survives actual expiry and gate disable');
}
{
 const x=await fixture('m2-disable-first'),p=await payload(x);
 const disable=sql(`begin;set application_name='m2-disable-hold';update private.production_recording_v3_activation set enabled=false where factory_id=${quote(x.factory)};select pg_sleep(2);commit;`);await wait('m2-disable-hold','PgSleep');
 const writer=sql(command(x,p,randomUUID(),'m2-disable-wait'));await wait('m2-disable-wait','Lock');const [a,b]=await Promise.all([disable,writer]);assert.equal(a.code,0);assert.match(b.error,/recording_disabled/);await stock(x,0);
 reports.push('disable-first blocks new admission in SQL');
}
{
 const x=await fixture('m2-writer-first'),p={...await payload(x),notes:'m2-test-delay'};
 const writer=sql(command(x,p,randomUUID(),'m2-gate-writer'));await wait('m2-gate-writer','PgSleep');
 const disable=sql(`begin;set application_name='m2-gate-disable';update private.production_recording_v3_activation set enabled=false where factory_id=${quote(x.factory)};commit;`);await wait('m2-gate-disable','Lock');const [a,b]=await Promise.all([writer,disable]);assert.equal(a.code,0,a.error);assert.equal(b.code,0,b.error);await stock(x,2);
 reports.push('writer-first holds shared gate through transaction; disable waits');
}
{
 const x=await fixture('m2-revoke'),p=await payload(x);
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.viewer)},'orders','view'),(${quote(x.factory)},${quote(x.viewer)},'orders','edit')`);
 const revoke=sql(`begin;set application_name='m2-revoke-hold';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory)},0));delete from public.user_permissions where factory_id=${quote(x.factory)} and user_id=${quote(x.viewer)} and module='orders';select pg_sleep(2);commit;`);await wait('m2-revoke-hold','PgSleep');
 const writer=sql(command({...x,owner:x.viewer},p,randomUUID(),'m2-revoke-wait'));await wait('m2-revoke-wait','Lock');const [a,b]=await Promise.all([revoke,writer]);assert.equal(a.code,0);assert.match(b.error,/permission_denied/);await stock(x,0);
 reports.push('permission revocation wins factory lock; waiting write reauthorizes');
}
{
 const x=await fixture('m2-support-expiry'),p=await payload(x);
 await required(`insert into public.roles(factory_id,name) values(${quote(x.factory)},'Local support fixture');
 insert into public.role_permissions(factory_id,role_id,module,action) select ${quote(x.factory)},id,'orders',a from public.roles cross join unnest(array['view','edit']) a where factory_id=${quote(x.factory)} and name='Local support fixture';
 delete from public.memberships where factory_id=${quote(x.factory)} and user_id=${quote(x.viewer)};
 insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.viewer)},'orders','view'),(${quote(x.factory)},${quote(x.viewer)},'orders','edit');
 insert into public.support_access(factory_id,user_id,role_id,mode,expires_at) values(${quote(x.factory)},${quote(x.viewer)},(select id from public.roles where factory_id=${quote(x.factory)} order by created_at,id limit 1),'temporary',clock_timestamp()+interval '2 seconds')`);
 const holder=sql(`begin;set application_name='m2-expiry-hold';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory)},0));select pg_sleep(3);commit;`);await wait('m2-expiry-hold','PgSleep');
 const writer=sql(command({...x,owner:x.viewer},p,randomUUID(),'m2-expiry-wait'));await wait('m2-expiry-wait','Lock');const [a,b]=await Promise.all([holder,writer]);assert.equal(a.code,0);assert.match(b.error,/permission_denied/);await stock(x,0);
 reports.push('temporary support expires after wait despite transaction-now grant');
}
{
 const x=await fixture('m2-finish-first',30,false),p=await payload(x);
 const finisher=sql(`begin;set application_name='m2-finish-hold';${actor(x)}set local role authenticated;select public.finish_product_item(${quote(x.factory)},${quote(x.item)});select pg_sleep(2);commit;`);await wait('m2-finish-hold','PgSleep');
 const writer=sql(command(x,p,randomUUID(),'m2-finish-wait'));await wait('m2-finish-wait','Lock');const [a,b]=await Promise.all([finisher,writer]);assert.equal(a.code,0,a.error);assert.match(b.error,/recording_stale_context/);await stock(x,0);
 const refreshed=await sql(command(x,await payload(x)));assert.equal(refreshed.code,0,refreshed.error);await stock(x,2);
 reports.push('Finish-first rejects stale active context; explicit refreshed late succeeds');
}
{
 const x=await fixture('m2-record-first',30,false),p={...await payload(x),notes:'m2-test-delay'};
 const writer=sql(command(x,p,randomUUID(),'m2-record-hold'));await wait('m2-record-hold','PgSleep');
 const finisher=sql(`begin;set application_name='m2-record-finish';${actor(x)}set local role authenticated;select public.finish_product_item(${quote(x.factory)},${quote(x.item)});commit;`);await wait('m2-record-finish','Lock');const [a,b]=await Promise.all([writer,finisher]);assert.equal(a.code,0,a.error);assert.equal(b.code,0,b.error);await stock(x,2);
 reports.push('recording-first preserves active receipt then normal Finish');
}
{
 const x=await fixture('m2-overproduction'),p={...await payload(x,99),notes:'m2-test-delay'};
 const first=sql(command(x,p,randomUUID(),'m2-limit-hold'));await wait('m2-limit-hold','PgSleep');const second=sql(command(x,p,randomUUID(),'m2-limit-wait'));await wait('m2-limit-wait','Lock');
 const [a,b]=await Promise.all([first,second]);assert.equal(a.code,0,a.error);assert.match(b.error,/recording_stale_context|recording_overproduction_confirmation/);await stock(x,99);
 reports.push('competing output rechecks accepted progress; no overproduction or double credit');
}
{
 const x=await fixture('m2-old-snapshot'),p=await payload(x);const r=await sql(command(x,p).replace('begin;','begin isolation level repeatable read;'));assert.match(r.error,/recording_isolation/);await stock(x,0);
 reports.push('unsupported stale transaction isolation fails closed');
}
{
 const x=await fixture('m2-platform-expiry'),p=await payload(x);
 await required(`insert into private.platform_admins(user_id,enabled) values(${quote(x.viewer)},true);
 insert into private.platform_scopes values(${quote(x.viewer)},${quote(x.factory)},clock_timestamp()+interval '2 seconds')`);
 const holder=sql(`begin;set application_name='m2-platform-hold';select pg_advisory_xact_lock(hashtextextended(${quote(x.factory)},0));select pg_sleep(3);commit;`);await wait('m2-platform-hold','PgSleep');
 const writer=sql(command({...x,owner:x.viewer},p,randomUUID(),'m2-platform-wait'));await wait('m2-platform-wait','Lock');const [a,b]=await Promise.all([holder,writer]);assert.equal(a.code,0);assert.match(b.error,/permission_denied/);await stock(x,0);
 await required(`insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.viewer)},'orders','view'),(${quote(x.factory)},${quote(x.viewer)},'orders','edit')`);
 const member=await sql(command({...x,owner:x.viewer},p));assert.equal(member.code,0,member.error);await stock(x,2);
 reports.push('live platform scope expiry denies; independent approved membership grant remains valid');
}
{
 const x=await fixture('m2-source-race');
 const original=await sql(command(x,await payload(x,10)));assert.equal(original.code,0,original.error);const e=JSON.parse(original.out).entry_id;
 const cp={entry:e,good:8,discarded_quantity:0,scrap_kg:0,startup_kg:0,reason:'M2 concurrent conserved correction',unfinished:0,remaining_work:''};
 const writer=sql(command(x,{...await payload(x,2),notes:'m2-test-delay'},randomUUID(),'m2-source-hold'));await wait('m2-source-hold','PgSleep');
 const correction=sql(`begin;set application_name='m2-source-correction';${actor(x)}set local role authenticated;select public.source_stock_command(${quote(x.factory)},'correct',${quote(JSON.stringify(cp))},'[ {"source_id":null,"quantity":"2"} ]',${quote(randomUUID())});commit;`);
 await wait('m2-source-correction','Lock');const [a,b]=await Promise.all([writer,correction]);assert.equal(a.code,0,a.error);assert.equal(b.code,0,b.error);await stock(x,10);
 assert.equal(await required(`select sum(quantity_credited) from public.finished_goods_sources where factory_id=${quote(x.factory)}`),'10');
 reports.push('late posting and source-backed decrease serialize and conserve net stock');
}
{
 const x=await fixture('m2-quality-race');const original=await sql(command(x,await payload(x,10)));assert.equal(original.code,0,original.error);const e=JSON.parse(original.out).entry_id;
 const src=await required(`select id from public.finished_goods_sources where entry_id=${quote(e)}`);
 const reason=await required(`select id from public.quality_reasons where factory_id=${quote(x.factory)} and name='Dimensional defect'`);
 await required(`${actor(x)}select public.source_stock_command(${quote(x.factory)},'identify',${quote(JSON.stringify({source:src,quantity:'10',label:'M2-identified-fixture',physically_identified:true}))},'[]',${quote(randomUUID())});`);
 const writer=sql(command(x,{...await payload(x,2),notes:'m2-test-delay'},randomUUID(),'m2-quality-hold'));await wait('m2-quality-hold','PgSleep');
 const rejection=sql(`begin;set application_name='m2-quality-reject';${actor(x)}set local role authenticated;select public.quality_command(${quote(x.factory)},'reject',${quote(JSON.stringify({source:src,quantity:'1',reason,disposition:'SCRAP',actual_scrap_kg:'0.5',physically_identified:true}))},${quote(randomUUID())});commit;`);
 await wait('m2-quality-reject','Lock');const [a,b]=await Promise.all([writer,rejection]);assert.equal(a.code,0,a.error);assert.equal(b.code,0,b.error);await stock(x,11);
 assert.equal(await required(`select accepted_good_quantity=11 and produced_quantity=12 and quality_rejected_quantity=1 from public.production_orders where id=${quote(x.item)}`),'t');
 reports.push('Quality rejection of identified available source and late Good conserve accepted/gross/stock');
}
{
 const x=await fixture('m2-sales-race');const original=await sql(command(x,await payload(x,10)));assert.equal(original.code,0,original.error);
 const so=await required(`${actor(x)}select public.create_sales_order(${quote(x.factory)},${quote(JSON.stringify({lines:[{product_id:x.product,quantity:8,unit:'meter'}]}))});`);
 const writer=sql(command(x,{...await payload(x,2),notes:'m2-test-delay'},randomUUID(),'m2-sales-hold'));await wait('m2-sales-hold','PgSleep');
 const reserve=sql(`begin;set application_name='m2-sales-reserve';${actor(x)}set local role authenticated;select public.approve_sales_order(${quote(x.factory)},${quote(so)});commit;`);
 await wait('m2-sales-reserve','Lock');const [a,b]=await Promise.all([writer,reserve]);assert.equal(a.code,0,a.error);assert.equal(b.code,0,b.error);await stock(x,12);
 assert.equal(await required(`select on_hand=12 and reserved=8 and on_hand-reserved=4 from public.finished_goods_balances where factory_id=${quote(x.factory)}`),'t');
 reports.push('Sales approval reservation and late Good serialize; reserved 8 / available 4 conserved');
}
await required(`drop trigger zzz_late_test_delay on public.production_entries;drop function late_test.delay();update private.production_recording_v3_activation set enabled=false,schema_contract_version=0;`);
await writeFile(join(output,'concurrency.json'),JSON.stringify({checks:reports.length,reports},null,2));console.log(`PASS ${reports.length} observed local concurrency/deadline scenarios`);
