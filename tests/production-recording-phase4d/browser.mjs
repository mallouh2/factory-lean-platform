// One practical Microsoft Edge pass: real local Next app, normal local accounts, original protected SQL.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const evidence=fs.readFileSync(path.join(os.tmpdir(),'FactoryLean-Phase4D-location.txt'),'utf8').trim(),root=fs.readFileSync(path.join(os.tmpdir(),'FactoryLean-Phase4B-FIX-runtime-location.txt'),'utf8').trim();
const runtime=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
assert.equal(runtime.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(runtime.databaseHost,'127.0.0.1');assert.equal(runtime.applicationPort,4207);
assert.ok(!fs.readFileSync(path.join(runtime.app,'.env.local'),'utf8').includes('https://'));
const accounts=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'))).accounts,en=JSON.parse(fs.readFileSync('src/locales/en.json')),ar=JSON.parse(fs.readFileSync('src/locales/ar.json')),base='http://127.0.0.1:4207',factory=runtime.context.factory;
const stateFile=path.join(evidence,'browser-state.json'),state=fs.existsSync(stateFile)?JSON.parse(fs.readFileSync(stateFile)):{checks:[]},errors=[],external=[];
const persist=()=>fs.writeFileSync(stateFile,JSON.stringify(state,null,2));
const browser=await chromium.launch({channel:'msedge',headless:true});let owner,worker,current;
async function login(role){const context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage();
 await context.route('**/*',route=>{const url=new URL(route.request().url());if(url.origin!==base){external.push(url.origin);return route.abort();}return route.continue();});
 page.on('pageerror',e=>errors.push(e.message));await page.goto(base+'/?view=lines');const a=accounts.find(a=>a.role===role);
 await page.locator('input[name=email]').fill(a.email);await page.locator('input[name=password]').fill(a.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});return {context,page};
}
const url=(extra={})=>'/api/production-corrections?'+new URLSearchParams({factory,...extra});
async function json(page,endpoint){const response=await page.request.get(base+endpoint);assert.equal(response.status(),200);return response.json();}
async function history(page){await page.goto(base+'/?view=productionHistory');await page.locator('.history-desktop tbody tr').first().waitFor({timeout:60000});await page.locator('.history-actions-button').waitFor();}
async function record(page,good,scrap,lost=false){await page.goto(base+'/?view=lines');await page.locator('.prv3-launch button.primary').click();const form=page.locator('#prv3-record-form');await form.locator('select option[value="'+runtime.context.item+'"]').waitFor({state:'attached',timeout:60000});await form.locator('select').first().selectOption(runtime.context.item);
 const declaration=page.getByRole('checkbox',{name:en.prv3Declare,exact:true});if(await declaration.count())await declaration.check();
 await form.locator('input[inputmode=decimal]').nth(0).fill(good);await form.locator('input[inputmode=decimal]').nth(1).fill(scrap);
 let captured,posts=0,finishRoute;const routed=new Promise(resolve=>{finishRoute=resolve;});const route=async r=>{if(r.request().method()!=='POST')return r.continue();posts++;captured=r.request().postData();const response=await r.fetch();assert.equal(response.status(),200);const body=await response.json();const entry=body.data?.entry_id||body.data?.id;assert.ok(entry);state[lost?'recovery':'normal']={entry,raw:captured,request:JSON.parse(captured).args.request_id,posts};persist();if(lost)await r.abort('failed');else await r.fulfill({response});finishRoute();};
 await page.route('**/api/data',route);await page.getByRole('button',{name:en.prv3Save,exact:true}).click();
 if(lost){await page.getByRole('heading',{name:en.prv3Unconfirmed,exact:true}).waitFor({timeout:60000});await routed;await page.getByRole('button',{name:en.prv3Check,exact:true}).waitFor({state:'visible'});await page.waitForFunction(text=>[...document.querySelectorAll('dialog button')].some(b=>b.textContent===text&&!b.disabled),en.prv3Check);await page.unroute('**/api/data',route);await page.reload();await page.locator('.prv3-launch button.primary').click();}
 await page.getByRole('heading',{name:en.prv3Saved,exact:true}).waitFor({timeout:60000});assert.equal(posts,1);await page.getByRole('button',{name:en.done,exact:true}).click();await page.locator('dialog').waitFor({state:'detached'});await page.unroute('**/api/data',route);
}
async function correction(page,entry,scrap){await history(page);await page.locator('#history-row-'+entry).click();await page.locator('.history-actions-button').click();await page.getByRole('menuitem',{name:en.pcRequest,exact:true}).click();const d=page.locator('.pc-dialog');await d.locator('.pc-quantity-grid input').nth(1).fill(scrap);await d.getByRole('button',{name:en.pcReasonMeasurement,exact:true}).click();await d.locator('textarea').fill('Phase4D local acceptance: sample weighed again, '+scrap+' KG.');return d;}
async function group(name,fn){if(state.checks.includes(name))return;try{await fn();state.checks.push(name);persist();console.log('PASS '+name);}catch(e){await current?.screenshot({path:path.join(evidence,'browser-failure.png')});throw e;}}
try{
 owner=await login('owner');current=owner.page;
 await group('Factory Floor, current eligible work, configured unit/KG, normal authoritative recording',async()=>{
  const work=await json(owner.page,'/api/production-shift-work?'+new URLSearchParams({factory,page_size:'100'}));assert.equal(work.late_recording_available,false);assert.ok(work.rows.some(row=>row.item_id===runtime.context.item&&row.unit==='meter'&&row.can_record));
  if(!state.normal)await record(owner.page,'1.25','0.05');await history(owner.page);assert.ok((await owner.page.locator('#history-row-'+state.normal.entry).innerText()).includes('1.25'));
 });
 await group('committed lost response, refresh recovery, same UUID replay and changed-intent denial',async()=>{
  if(!state.recovery)await record(owner.page,'0.1234567890123456789','0.01234567890123456789',true);
  else{ // Resume the captured original UUID; never create another recording after a harness interruption.
   await owner.page.goto(base+'/?view=lines');
   const intent={version:1,actor:runtime.context.owner,factory,request:state.recovery.request,body:state.recovery.raw,created_at:new Date().toISOString(),last_checked_at:null,phase:'UNCONFIRMED'};
   await owner.page.evaluate(intent=>localStorage.setItem('factory-lean:recording:v3:'+intent.actor+':'+intent.factory,JSON.stringify(intent)),intent);
   await owner.page.reload();await owner.page.locator('.prv3-launch button.primary').click();await owner.page.getByRole('heading',{name:en.prv3Saved,exact:true}).waitFor({timeout:60000});await owner.page.getByRole('button',{name:en.done,exact:true}).click();
  }
  const result=await owner.page.request.post(base+'/api/data',{headers:{origin:base,'X-Factory-Recording':'3','content-type':'application/json'},data:state.recovery.raw});assert.equal(result.status(),200);
  assert.ok((await result.text()).includes('0.1234567890123456789'));
  const changed=state.recovery.raw.replace('0.1234567890123456789','0.1234567890123456788');assert.notEqual(changed,state.recovery.raw);
  const denied=await owner.page.request.post(base+'/api/data',{headers:{origin:base,'X-Factory-Recording':'3','content-type':'application/json'},data:changed});assert.equal(denied.status(),409);
  const row=(await json(owner.page,'/api/production-reporting?'+new URLSearchParams({factory,reporting_version:'3',entry:state.recovery.entry}))).rows[0];assert.equal(row.good,'0.1234567890123456789');assert.equal(row.scrap_kg,'0.01234567890123456789');
 });
 await group('History exact official quantities, seven columns, six Details facts, toolbar and double-click',async()=>{
  await history(owner.page);const row=owner.page.locator('#history-row-'+state.recovery.entry);await row.click();assert.equal(await owner.page.locator('.history-desktop tr[aria-selected=true]').count(),1);assert.equal(await owner.page.locator('dialog').count(),0);await row.dblclick();await owner.page.locator('.history-v2-details').waitFor();assert.equal(await owner.page.locator('.history-operational-details>div').count(),6);await owner.page.locator('.history-v2-details').getByRole('button',{name:en.close,exact:true}).click();
  assert.equal(await owner.page.locator('.history-desktop th').count(),7);const data=await json(owner.page,'/api/production-history?factory='+factory);const exact=data.rows.find(row=>row.id===state.recovery.entry);assert.equal(String(exact.effective_good),'0.1234567890123456789');assert.equal(String(exact.effective_scrap_kg),'0.01234567890123456789');
  await owner.page.locator('.history-actions-button').click();await owner.page.getByRole('menuitem',{name:en.historyViewDetails,exact:true}).click();await owner.page.locator('.history-v2-details').waitFor();await owner.page.locator('.history-v2-details').getByRole('button',{name:en.close,exact:true}).click();await owner.page.screenshot({path:path.join(evidence,'history-desktop.png')});
 });
 worker=await login('worker');current=worker.page;
 await group('technician editable explanation, Pending Approval, request tracking and no official posting',async()=>{
  const before=await json(worker.page,url({context_entry:state.normal.entry}));state.beforeCorrection=before;persist();
  if(!state.pending){const d=await correction(worker.page,state.normal.entry,'0.075');assert.ok(await d.getByRole('button',{name:en.pcSubmit,exact:true}).isVisible());await d.locator('form button.primary').click();await d.getByText(en.pcPendingSuccess,{exact:true}).waitFor({timeout:30000});const result=await json(worker.page,url({entry:state.normal.entry,status:'PENDING'}));state.pending=result.rows.find(r=>r.proposed.reason.includes('Phase4D local acceptance')).id;persist();await d.getByRole('button',{name:en.close,exact:true}).first().click();}
  const after=await json(worker.page,url({context_entry:state.normal.entry}));assert.deepEqual(after,before);const denied=await worker.page.request.get(base+url({pending_count:'1'}));assert.equal(denied.status(),403);assert.ok(!(await denied.json()).total);
  await worker.page.goto(base+'/?view=productionCorrections');await worker.page.locator('.production-corrections tbody tr').filter({hasText:'Phase4D local acceptance'}).waitFor();assert.equal(await worker.page.locator('.pc-needs-approval').count(),0);
 });
 current=owner.page;
 await group('approver pending alert, Details, approve once, History official refresh and rejection',async()=>{
  await owner.page.goto(base+'/?view=productionCorrections');const q=owner.page.locator('.production-corrections'),r=q.locator('tbody tr').filter({hasText:'Phase4D local acceptance: sample weighed again, 0.075 KG.'});await r.waitFor();await owner.page.locator('.pc-needs-approval').waitFor();state.pendingCount=(await json(owner.page,url({pending_count:'1'}))).total;
  await r.dblclick();const d=owner.page.locator('.pc-dialog');assert.ok((await d.innerText()).includes('Local production technician'));await d.getByRole('button',{name:en.approve,exact:true}).click();await d.locator('form button.primary').click();await q.getByText(en.pcApprovedSuccess,{exact:true}).waitFor({timeout:30000});
  const approved=(await json(owner.page,url({id:state.pending}))).rows[0];assert.equal(approved.status,'APPROVED');assert.equal(approved.current_values.scrap_kg,'0.075');assert.equal((await json(owner.page,url({pending_count:'1'}))).total,state.pendingCount-1);state.approved=approved;persist();
  await history(owner.page);assert.ok((await owner.page.locator('#history-row-'+state.normal.entry).innerText()).includes('0.075'));
 });
 current=worker.page;
 await group('rejected technician proposal leaves official quantities and pending alert correct',async()=>{
  const d=await correction(worker.page,state.normal.entry,'0.09');await d.locator('form button.primary').click();await d.getByText(en.pcPendingSuccess,{exact:true}).waitFor();const result=await json(worker.page,url({entry:state.normal.entry,status:'PENDING'}));state.rejectId=result.rows.find(r=>r.proposed.scrap_kg==='0.09').id;persist();
  await owner.page.goto(base+'/?view=productionCorrections');const q=owner.page.locator('.production-corrections'),r=q.locator('tbody tr').filter({hasText:'sample weighed again, 0.09 KG.'});await r.waitFor();await r.dblclick();const review=owner.page.locator('.pc-dialog');await review.getByRole('button',{name:en.reject,exact:true}).click();await review.locator('textarea').fill('Phase4D: unsupported test proposal; official measurement remains valid.');await review.locator('form button.primary').click();await q.getByText(en.pcRejectedSuccess,{exact:true}).waitFor();assert.equal((await json(owner.page,url({context_entry:state.normal.entry}))).scrap_kg,'0.075');assert.equal((await json(owner.page,url({pending_count:'1'}))).total,state.pendingCount-1);
 });
 current=owner.page;
 await group('authorized self-approval and server-filtered My Requests',async()=>{
  const d=await correction(owner.page,state.normal.entry,'0.08');assert.ok(await d.getByRole('button',{name:en.pcSaveCorrection,exact:true}).isVisible());await d.locator('form button.primary').click();await d.getByText(en.pcApprovedSuccess,{exact:true}).waitFor();await d.getByRole('button',{name:en.close,exact:true}).first().click();
  await owner.page.goto(base+'/?view=productionCorrections');await owner.page.locator('.pc-toolbar select').selectOption('mine');const response=await json(owner.page,url({mine:'1'}));assert.ok(response.rows.length);assert.ok(response.rows.every(row=>row.requested_by===runtime.context.owner));await owner.page.locator('.production-corrections tbody tr').first().waitFor();
 });
 await group('EN/AR actual text, RTL and 390px recording/History usability',async()=>{
  await owner.page.goto(base+'/?view=lines');await owner.page.setViewportSize({width:390,height:844});await owner.page.getByRole('button',{name:'العربية',exact:true}).click();await owner.page.locator('.prv3-launch button.primary').click();await owner.page.getByRole('heading',{name:ar.prv3Record,exact:true}).waitFor();await owner.page.locator('#prv3-record-form select option[value="'+runtime.context.item+'"]').waitFor({state:'attached',timeout:60000});await owner.page.locator('#prv3-record-form select').first().selectOption(runtime.context.item);await owner.page.locator('#prv3-record-form input[inputmode=decimal]').first().waitFor();assert.ok((await owner.page.locator('dialog').innerText()).includes(ar.recordingGood));assert.ok((await owner.page.locator('dialog').innerText()).includes(ar.recordingScrap));assert.equal(await owner.page.locator('html').getAttribute('dir'),'rtl');assert.ok((await owner.page.locator('dialog').innerText()).includes(ar.prv3Work));assert.equal(await owner.page.locator('html').evaluate(e=>e.scrollWidth>innerWidth),false);await owner.page.screenshot({path:path.join(evidence,'recording-mobile-ar.png')});await owner.page.keyboard.press('Escape');await owner.page.goto(base+'/?view=productionHistory');await owner.page.locator('.history-mobile article').first().waitFor();assert.equal(await owner.page.locator('html').evaluate(e=>e.scrollWidth>innerWidth),false);
 });
 assert.deepEqual(errors,[]);assert.deepEqual(external,[]);fs.writeFileSync(path.join(evidence,'browser-results.json'),JSON.stringify({checks:state.checks,edge:browser.version(),errors,external,limits:'Loopback Auth/Data adapter; not hosted GoTrue/PostgREST or physical mobile acceptance.'},null,2));console.log('PASS '+state.checks.length+' browser groups');
}finally{await owner?.context.close();await worker?.context.close();await browser.close();}
