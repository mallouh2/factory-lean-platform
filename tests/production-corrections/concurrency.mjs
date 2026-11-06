import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
const [bin,port,output]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.match(port,/^\d{4,5}$/);
function sql(text,label='correction-check'){return new Promise((resolve,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>resolve({code,out:out.trim(),error}));p.stdin.end(`set application_name=${quote(label)};\n${text}`);});}
async function required(text){const r=await sql(text);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const x=JSON.parse(await required('select x from correction_test.context;')),f=x.factory,e=x.other_entry;
const claims=actor=>`do $$begin perform set_config('request.jwt.claim.sub',${quote(actor)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;`;
const command=(actor,op,payload,retry=randomUUID())=>`begin;${claims(actor)}set local role authenticated;select public.production_correction_command(${quote(f)},${quote(op)},${quote(JSON.stringify(payload))},${quote(retry)});commit;`;
async function pending(extra){const p=JSON.parse(await required(`select correction_test.payload(${quote(JSON.stringify(x))},${quote(e)},(select effective_good+${extra} from public.production_entries where id=${quote(e)}),.4,0);`));return JSON.parse(await required(command(x.worker,'submit',p)));}
async function state(){return JSON.parse(await required(`select jsonb_build_object('good',effective_good::text,'corrections',(select count(*) from public.production_entry_corrections where entry_id=${quote(e)}),'stock',(select on_hand::text from public.finished_goods_balances where factory_id=${quote(f)} and product_id=${quote(x.product)} and unit='meter')) from public.production_entries where id=${quote(e)};`));}
const checks=[];
let p=await pending('.5'),before=await state();
const pair=await Promise.all([sql(command(x.engineer,'approve',{id:p.id}),'correction-approve-a'),sql(command(x.engineer,'approve',{id:p.id}),'correction-approve-b')]);
for(const r of pair)assert.equal(r.code,0,r.error);
assert.equal(JSON.parse(pair[0].out).correction_id,JSON.parse(pair[1].out).correction_id);
let after=await state();assert.equal(after.corrections,before.corrections+1);assert.equal(Number(after.good)-Number(before.good),.5);assert.equal(Number(after.stock)-Number(before.stock),.5);checks.push('two concurrent approvals apply once');
p=await pending('.25');before=await state();
const race=await Promise.all([sql(command(x.engineer,'approve',{id:p.id}),'correction-approve'),sql(command(x.engineer,'reject',{id:p.id,reason:'Recheck measurement first'}),'correction-reject')]);
assert.equal(race.filter(r=>r.code===0).length,1);assert.equal(race.filter(r=>r.code!==0).length,1);
const decision=JSON.parse(race.find(r=>r.code===0).out);after=await state();
assert.equal(after.corrections,before.corrections+(decision.status==='APPROVED'?1:0));assert.equal(Number(after.stock)-Number(before.stock),decision.status==='APPROVED'?.25:0);checks.push('approve/reject race has one terminal result');
p=await pending('.125');before=await state();
const packageRow=JSON.parse(await required(`select jsonb_build_object('id',p.id,'revision',p.revision,'payload',jsonb_build_object('name',p.name,'name_ar',p.name_ar,'description',p.description),'permissions',(select jsonb_agg(jsonb_build_object('module',module,'action',action)) from public.permission_package_permissions where package_id=p.id and not(module='orders' and action='approve'))) from public.permission_packages p where id=${quote(x.package)};`));
const save=permissions=>`select public.save_permission_package(${quote(f)},${quote(packageRow.id)},${quote(JSON.stringify(packageRow.payload))},${quote(JSON.stringify(permissions))},(select revision from public.permission_packages where id=${quote(packageRow.id)}));`;
const revoke=sql(`begin;${claims(x.owner)}${save(packageRow.permissions)}select pg_sleep(1.5);commit;`,'correction-revoke');
async function waitFor(label,condition){for(let n=0;n<150;n++){if(await required(`select exists(select 1 from pg_stat_activity where application_name=${quote(label)} and ${condition});`)==='t')return;await new Promise(r=>setTimeout(r,10));}throw Error('Expected actual wait not observed: '+label);}
await waitFor('correction-revoke',"wait_event='PgSleep'");
const approving=sql(command(x.engineer,'approve',{id:p.id}),'correction-after-revoke');
await waitFor('correction-after-revoke',"wait_event_type='Lock'");
assert.equal((await revoke).code,0);const denied=await approving;assert.notEqual(denied.code,0);assert.match(denied.error,/permission_denied/);assert.deepEqual(await state(),before);
assert.equal(await required(`select status from private.production_correction_requests where id=${quote(p.id)}`),'PENDING');checks.push('observed grant-revocation lock wait rechecks authority');
await required(`begin;${claims(x.owner)}${save([...packageRow.permissions,{module:'orders',action:'approve'}])}commit;`);
await writeFile(join(output,'correction-concurrency.json'),JSON.stringify({checks:checks.length,names:checks,limits:'Separate localhost PostgreSQL connections; no hosted claims.'},null,2));
console.log(`PASS ${checks.length} actual correction concurrency scenarios`);
