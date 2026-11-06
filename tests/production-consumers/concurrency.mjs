import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
const [bin,port,out]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
function sql(text,label='m3c-check'){return new Promise((done,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let data='',error='';p.stdout.on('data',v=>data+=v);p.stderr.on('data',v=>error+=v);p.on('error',reject);p.on('close',code=>{try{assert.equal(code,0,error);done(data.trim());}catch(e){reject(e);}});p.stdin.end(`set application_name=${quote(label)};${text}`);});}
assert.equal(await sql("select inet_server_addr()='127.0.0.1'::inet and current_database()='factory_lean_quality_local'"),'t');
const x=JSON.parse(await sql('select x from m3c_test.context')),f=x.factory,e=x.entry;
const claims=actor=>`do $$begin perform set_config('request.jwt.claim.sub',${quote(actor)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;set local role authenticated;`;
const command=(actor,op,payload,id=randomUUID())=>`begin;${claims(actor)}select public.production_correction_command(${quote(f)},${quote(op)},${quote(JSON.stringify(payload))},${quote(id)});commit;`;
const snapshot=`select jsonb_build_object('good',e.effective_good::text,'kg',e.effective_scrap_kg::text,'original',e.good_quantity::text,
 'view_good',v.effective_good::text,'quality_good',(public.quality_read(${quote(f)},jsonb_build_object('mode','board','entry',e.id))#>>'{rows,0,current_good}'),
 'review_current',private.production_scrap_review_current(${quote(f)},e.id,v.scrap_reviewed_at))
 from public.production_entries e join private.production_reporting_entries v on v.id=e.id and v.factory_id=e.factory_id where e.id=${quote(e)};`;
async function current(){return JSON.parse(await sql(`begin read only;do $$begin perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);end$$;${snapshot}commit;`));}
async function submit(delta){const p=JSON.parse(await sql(`select m3c_test.payload(${quote(e)},(select effective_good+${delta} from public.production_entries where id=${quote(e)}),2.234567890123456789);`));return JSON.parse(await sql(command(x.worker,'submit',p)));}
async function review(){await sql(`begin;${claims(x.owner)}select public.lean_command(${quote(f)},${quote(randomUUID())},'scrap_review',jsonb_build_object('id',${quote(x.observation)},'approved_cause_id',${quote(x.cause)},'note','Rechecked current source','expected_revision',(select revision from public.lean_scrap_events where id=${quote(x.observation)})));commit;`);}
async function waitFor(label,condition){for(let n=0;n<150;n++){if(await sql(`select exists(select 1 from pg_stat_activity where application_name=${quote(label)} and ${condition})`)==='t')return;await new Promise(r=>setTimeout(r,10));}throw Error('No observed barrier '+label);}
const checks=[];
await review();let pending=await submit('.125'),before=await current();
const approving=sql(`begin;${claims(x.owner)}select public.production_correction_command(${quote(f)},'approve',${quote(JSON.stringify({id:pending.id}))},${quote(randomUUID())});select pg_sleep(1.5);commit;`,'m3c-approval-held');
await waitFor('m3c-approval-held',"wait_event='PgSleep'");
const during=await current();assert.deepEqual(during,before);await approving;
let after=await current();assert.equal(after.good,after.view_good);assert.equal(after.good,after.quality_good);assert.notEqual(after.good,before.good);assert.equal(after.original,before.original);assert.equal(after.review_current,false);checks.push('uncommitted approval cannot leak partial values into concurrent reads');
pending=await submit('.125');before=await current();
const repeated=sql(`begin isolation level repeatable read read only;do $$begin perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);end$$;${snapshot}select pg_sleep(1.5);${snapshot}commit;`,'m3c-reader-held');
await waitFor('m3c-reader-held',"wait_event='PgSleep'");
await sql(command(x.owner,'approve',{id:pending.id}));const lines=(await repeated).split('\n').filter(v=>v.startsWith('{')).map(JSON.parse);assert.equal(lines.length,2);assert.deepEqual(lines[0],lines[1]);assert.deepEqual(lines[0],before);after=await current();assert.notEqual(after.good,before.good);checks.push('read snapshot remains coherent while approval commits');
pending=await submit('.125');
const blocking=sql(`begin;${claims(x.owner)}select public.production_correction_command(${quote(f)},'approve',${quote(JSON.stringify({id:pending.id}))},${quote(randomUUID())});select pg_sleep(1.5);commit;`,'m3c-review-writer-held');
await waitFor('m3c-review-writer-held',"wait_event='PgSleep'");
const reviewCommand=sql(`begin;${claims(x.owner)}select public.lean_command(${quote(f)},${quote(randomUUID())},'scrap_review',jsonb_build_object('id',${quote(x.observation)},'approved_cause_id',${quote(x.cause)},'note','Review after correction lock','expected_revision',(select revision from public.lean_scrap_events where id=${quote(x.observation)})));commit;`,'m3c-review-wait');
await waitFor('m3c-review-wait',"wait_event_type='Lock'");await blocking;await reviewCommand;assert.equal((await current()).review_current,true);checks.push('existing review waits for correction and then qualifies only final official quantities');
await writeFile(join(out,'consumer-concurrency.json'),JSON.stringify({checks:checks.length,names:checks,limits:'Actual loopback PostgreSQL connections and observed waits; not hosted.'},null,2));
console.log(`PASS ${checks.length} actual M3C concurrency scenarios`);
