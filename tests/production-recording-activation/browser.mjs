// One lightweight pass on a fresh disposable application/database. Normal local sign-in only.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createRequire} from 'node:module';
import {recordingBody} from '../../src/utils/production-recording-intent.mjs';
const root=process.argv[2],r=JSON.parse(fs.readFileSync(path.join(root,'runtime.json')));
assert.equal(r.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(r.databasePort,55479);assert.equal(r.applicationPort,4211);
const {chromium}=createRequire(import.meta.url)('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const base='http://127.0.0.1:4211',x=r.context,f=x.factory,q=s=>"'"+String(s).replaceAll("'","''")+"'";
const mobileOnly=process.argv.includes('--finish-mobile');
const sql=query=>new Promise((resolve,reject)=>{const c=spawn(path.join(r.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p','55479','-U','quality_fixture','-d',r.database,'-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',err='';c.stdout.on('data',b=>out+=b);c.stderr.on('data',b=>err+=b);c.on('close',code=>code?reject(Error(err)):resolve(out.trim()));c.stdin.end(query);});
assert.equal(await sql("select inet_server_addr()='127.0.0.1'::inet and current_database()='factory_lean_quality_local'"),'t');
const gate=on=>sql(`update private.production_recording_v3_activation set enabled=${on},schema_contract_version=${on?3:0} where factory_id=${q(f)}`);
const en=JSON.parse(fs.readFileSync('src/locales/en.json')),ar=JSON.parse(fs.readFileSync('src/locales/ar.json'));
const account=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'))).accounts.find(a=>a.role==='worker');
const browser=await chromium.launch({channel:'msedge',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[],external=[],checks=[];
await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.origin!==base){external.push(u.origin);return route.abort();}return route.continue();});
page.on('pageerror',e=>errors.push(e.message));
const getWork=async()=>{const res=await page.request.get(base+'/api/production-shift-work?'+new URLSearchParams({factory:f}));assert.equal(res.status(),200);return res.json();};
async function open(){await page.goto(base+'/?view=lines');await page.locator('.prv3-launch button.primary').click();const form=page.locator('#prv3-record-form');await form.locator('select option[value="'+x.item+'"]').waitFor({state:'attached',timeout:30000});await form.locator('select').first().selectOption(x.item);return form;}
let raw,entry,request,original,resumed=false;
try{
 await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:30000});
 const prior=JSON.parse(await sql(`select coalesce(jsonb_agg(jsonb_build_object('receipt',request_receipt,'start',execution_started_at,'finish',execution_finished_at)),'[]') from public.production_entries where factory_id=${q(f)} and recording_kind='LATE_ORDINARY'`));assert.ok(prior.length<=1);
 if(prior.length){
  resumed=true;const receipt=prior[0].receipt;entry=receipt.entry_id;request=receipt.request_id;raw=fs.existsSync(path.join(root,'browser-commit.json'))?JSON.parse(fs.readFileSync(path.join(root,'browser-commit.json'))).raw:recordingBody(f,request,receipt.original_payload);original={status:'completed',actual_start:prior[0].start,actual_finish:prior[0].finish};
  const recovery=await page.request.get(base+'/api/production-recording-status?'+new URLSearchParams({factory:f,request_id:request}));assert.equal(recovery.status(),200);assert.equal((await recovery.json()).receipt.entry_id,entry);
  checks.push('Resumed original committed fixture after harness-only missing-Origin failure; no recording repeated');
 }else{
 let work=await getWork();assert.equal(work.late_recording_available,false);assert.equal(work.rows.find(w=>w.item_id===x.item).can_record,true);
 await open();assert.equal(await page.getByRole('button',{name:en.prv3Save,exact:true}).isEnabled(),true);checks.push('OFF normal active UI eligible; seeded active Good committed');
 await page.getByRole('button',{name:en.cancel,exact:true}).click();
 // Legitimate protected Finish under the existing owner identity, fixture setup only.
 await sql(`begin;select set_config('request.jwt.claim.sub',${q(x.owner)},true);select set_config('request.jwt.claim.role','authenticated',true);set local role authenticated;select public.finish_product_item(${q(f)},${q(x.item)});commit;`);
 original=JSON.parse(await sql(`select jsonb_build_object('status',status,'actual_start',actual_start,'actual_finish',actual_finish) from public.production_orders where id=${q(x.item)}`));
 await open();assert.equal(await page.getByRole('button',{name:en.prv3Save,exact:true}).isDisabled(),true);await page.getByText(en.prv3LateDisabled,{exact:true}).waitFor();checks.push('OFF completed selection blocked with clear message');
 await page.getByRole('button',{name:en.cancel,exact:true}).click();await gate(true);
 const form=await open();work=await getWork();assert.equal(work.late_recording_available,true);assert.equal(work.rows.find(w=>w.item_id===x.item).can_record,true);await page.locator('.prv3-work').getByText(en.prv3Completed,{exact:true}).waitFor();
 await form.locator('input[inputmode=decimal]').nth(0).fill('1.5');await form.locator('input[inputmode=decimal]').nth(1).fill('0.25');
 await form.locator('.prv3-details summary').first().click();await page.getByRole('checkbox',{name:en.prv3IncludeWip,exact:true}).check();await form.locator('input[inputmode=decimal]').nth(2).fill('1');await form.locator('input[minlength="3"]').fill('Finish local inspection');
 let finish;const intercepted=new Promise(resolve=>finish=resolve);
 const intercept=async route=>{raw=route.request().postData();const res=await route.fetch();assert.equal(res.status(),200);const body=await res.json();entry=body.data.entry_id;request=JSON.parse(raw).args.request_id;fs.writeFileSync(path.join(root,'browser-commit.json'),JSON.stringify({entry,request,raw,original,checks}));await route.abort('failed');finish();};
 await page.route('**/api/data',intercept);await page.getByRole('button',{name:en.prv3Save,exact:true}).click();await intercepted;
 await page.getByRole('heading',{name:en.prv3Unconfirmed,exact:true}).waitFor();await page.unroute('**/api/data',intercept);await gate(false);
 // Recovery of committed output is deliberately distinct from a new disabled request.
 await page.reload();await page.locator('.prv3-launch button.primary').click();await page.getByRole('heading',{name:en.prv3Saved,exact:true}).waitFor({timeout:30000});checks.push('ON technician late Good/Scrap/new WIP; lost-response recovery after gate disable');
 }
 if(!mobileOnly){const replay=await page.request.post(base+'/api/data',{data:raw,headers:{'content-type':'application/json','X-Factory-Recording':'3',origin:base}});assert.equal(replay.status(),200);
 const changed=JSON.parse(raw);changed.args.payload.good=2;const conflict=await page.request.post(base+'/api/data',{data:changed,headers:{'X-Factory-Recording':'3',origin:base}});assert.equal(conflict.status(),409);checks.push('same UUID replay200; changed intent409 without posting');
 if(!resumed)await page.getByRole('button',{name:en.done,exact:true}).click();
 await page.goto(base+'/?view=productionHistory');await page.locator('#history-row-'+entry).waitFor();const row=await page.locator('#history-row-'+entry).innerText();assert.ok(row.includes('1.5')&&row.includes('0.25'));checks.push('official History Good1.5 Meter and Scrap0.25 KG');
 // A stale enabled page cannot defeat a subsequent disable.
 await gate(true);const stale=await open();await stale.locator('input[inputmode=decimal]').nth(0).fill('2');await gate(false);await page.getByRole('button',{name:en.prv3Save,exact:true}).click();await page.getByRole('heading',{name:en.prv3Rejected,exact:true}).waitFor();await page.getByText(en.prv3LateDisabled,{exact:true}).waitFor();checks.push('stale enabled UI gets authoritative503 rejection after disable');
 await page.getByRole('button',{name:en.prv3ReviewDraft,exact:true}).click();await page.getByRole('button',{name:en.prv3Save,exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:en.prv3Save,exact:true}).isDisabled(),true);
 }else{assert.ok(resumed);await open();assert.equal(await page.getByRole('button',{name:en.prv3Save,exact:true}).isDisabled(),true);}
 await page.locator('.prv3-language').click();await page.setViewportSize({width:390,height:844});await page.getByText(ar.prv3LateDisabled,{exact:true}).waitFor();assert.equal(await page.locator('.prv3-entry').getAttribute('dir'),'rtl');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:path.join(root,'completed-off-ar.png')});checks.push('EN/AR RTL390px retains disabled action and warning');
 const after=JSON.parse(await sql(`select jsonb_build_object('status',status,'actual_start',actual_start,'actual_finish',actual_finish) from public.production_orders where id=${q(x.item)}`));assert.deepEqual(after,original);
 const balances=JSON.parse(await sql(`select jsonb_build_object('good',(select sum(effective_good) from public.production_entries where factory_id=${q(f)}),'scrap',(select sum(effective_scrap_kg) from public.production_entries where factory_id=${q(f)}),'wip',(select sum(quantity_available) from public.unfinished_lots where factory_id=${q(f)}),'stock',(select sum(on_hand) from public.finished_goods_balances where factory_id=${q(f)}),'sources',(select sum(quantity_credited) from public.finished_goods_sources where factory_id=${q(f)}),'entries',(select count(*) from public.production_entries where factory_id=${q(f)}))`));
 assert.deepEqual(balances,{good:26.5,scrap:1,wip:3,stock:26.5,sources:26.5,entries:2});assert.deepEqual(errors,[]);assert.deepEqual(external,[]);checks.push('completed timestamps preserved; stock/source/Good26.5; Scrap1KG; WIP3; two entries only');
 fs.writeFileSync(path.join(root,'browser-results.json'),JSON.stringify({checks,entry,request,balances,errors,external},null,2));console.log('PASS '+checks.length+' browser checks');
}catch(e){await page.screenshot({path:path.join(root,'browser-failure.png')});throw e;}finally{await gate(false);await browser.close();}
