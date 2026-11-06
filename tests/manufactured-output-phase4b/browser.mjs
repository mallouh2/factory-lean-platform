import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Output-P4B-Preview-location.txt'),'utf8').trim(),config=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
assert.equal(config.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(config.databaseHost,'127.0.0.1');assert.equal(config.applicationPort,4218);assert.equal(config.databasePort,55492);
const base='http://127.0.0.1:4218',account=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts.find(a=>a.role==='owner'),en=JSON.parse(fs.readFileSync('src/locales/en.json','utf8'));
const browser=await chromium.launch({channel:'msedge',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[],responses=[],checks=[],out=path.join(root,'browser');fs.mkdirSync(out,{recursive:true});
await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.url().includes('/api/'))responses.push({path:new URL(r.url()).pathname,status:r.status(),method:r.request().method()});});
async function check(name,fn){await fn();checks.push(name);fs.writeFileSync(path.join(out,'progress.json'),JSON.stringify({checks,errors,responses},null,2));console.log('PASS '+name);}
async function state(){const r=await page.evaluate(async url=>{const r=await fetch(url);return {status:r.status,data:await r.json()};},'/api/manufactured-output?'+new URLSearchParams({factory:config.context.factory,mode:'completion'}));assert.equal(r.status,200);return r.data;}
const panel=()=>page.getByRole('region',{name:'Unfinished work',exact:true});
async function waitWork(count){await assert.doesNotReject(async()=>{await page.waitForFunction(async ({factory,count})=>{const r=await fetch('/api/manufactured-output?'+new URLSearchParams({factory,mode:'completion'}));const d=await r.json();return d.work?.length===count;},{factory:config.context.factory,count},{timeout:20000});});}
try{
 await check('normal localhost owner sign-in and real Planning eligibility',async()=>{
  await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});
  await page.locator('#factory-navigation').getByRole('button',{name:en.planning,exact:true}).press('Enter');await page.getByRole('heading',{name:'Finish the remaining order',exact:true}).waitFor();assert.equal((await state()).rows[0].shortage,'10');
  await panel().getByRole('button',{name:en.historyViewDetails,exact:true}).first().click();const d=page.locator('dialog');await d.getByLabel('Quantity · '+en.meter,{exact:true}).fill('10');await d.getByLabel('Reason',{exact:true}).fill('Phase4B browser recovery fixture');await d.getByRole('button',{name:'Create work for Planning',exact:true}).click();await d.waitFor({state:'detached',timeout:20000});await waitWork(1);
  const s=await state();assert.equal(s.work[0].decision_revision.cancel_available,true);assert.equal(s.work[0].decision_revision.state.material_revision,'1');
 });
 await check('COMPLETE to REPLACE through Planning preserves ten stored and ten short',async()=>{
  await panel().getByRole('button',{name:'Change Decision',exact:true}).click();const d=page.locator('dialog');await d.getByLabel('Reason',{exact:true}).fill('Change to new replacement before any issue');await d.getByRole('button',{name:'Confirm change',exact:true}).click();await d.waitFor({state:'detached',timeout:20000});await waitWork(2);
  const s=await state();assert.equal(s.work[0].choice,'REPLACE');assert.equal(s.work[0].line_id,null);assert.equal(s.rows[0].stored,'10');assert.equal(s.rows[0].shortage,'10');assert.equal(s.work[1].decision_revision.retirement.action,'CHANGE');
  await page.screenshot({path:path.join(out,'revision-desktop.png'),fullPage:true});
 });
 await check('Arabic mobile change back to COMPLETE with real source operations',async()=>{
  await page.getByRole('button',{name:'العربية',exact:true}).click();await page.setViewportSize({width:390,height:844});
  await page.getByRole('button',{name:'تغيير القرار',exact:true}).click();const d=page.locator('dialog');assert.equal(await d.locator('input[type=checkbox]').count(),1);await d.getByLabel('السبب',{exact:true}).fill('إعادة الإكمال من المصدر المخزن قبل الصرف');
  assert.equal(await page.locator('html').getAttribute('dir'),'rtl');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await page.screenshot({path:path.join(out,'revision-ar-mobile.png'),fullPage:true});
  await d.getByRole('button',{name:'تأكيد التغيير',exact:true}).click();await d.waitFor({state:'detached',timeout:20000});await waitWork(3);const s=await state();assert.equal(s.work[0].choice,'COMPLETE');assert.equal(s.work[0].material_status,'REQUESTED');assert.equal(s.rows[0].available_to_allocate,'0');
 });
 await check('lost cancellation response survives reload and replays the same UUID once',async()=>{
  await page.getByRole('button',{name:'English',exact:true}).click();await page.setViewportSize({width:1440,height:1000});await panel().getByRole('button',{name:'Cancel Decision',exact:true}).click();const d=page.locator('dialog');await d.getByLabel('Reason',{exact:true}).fill('Cancel unissued recovery and retain shortage');
  let lost=false;await page.route('**/api/manufactured-output',async route=>{const req=route.request();if(req.method()==='POST'&&!lost&&req.postDataJSON().command==='revise_manufactured_completion'){lost=true;const r=await route.fetch();assert.equal(r.status(),200);return route.abort('failed');}return route.continue();});
  await d.getByRole('button',{name:'Confirm cancellation',exact:true}).click();await page.getByText('A decision is awaiting confirmation. Retry it before creating another.',{exact:false}).waitFor();assert.equal(lost,true);
  const retained=await page.evaluate(()=>Object.values(sessionStorage).find(x=>x.includes('revise_manufactured_completion')));assert.ok(retained);
  await page.reload();await page.locator('.app-shell').waitFor();await page.locator('#factory-navigation').getByRole('button',{name:en.planning,exact:true}).press('Enter');await panel().getByRole('button',{name:en.retry,exact:true}).click();await page.getByText('Decision cancelled. Material remains in storage and the finished shortage still needs a decision.',{exact:true}).waitFor();
  const s=await state();assert.equal(s.work.length,3);assert.ok(s.work.every(w=>w.status==='cancelled'&&w.decision_revision.retirement));assert.equal(s.rows[0].unassigned,'10');assert.equal(s.rows[0].stored,'10');assert.equal(s.rows[0].shortage,'10');assert.equal(await panel().getByRole('button',{name:'Cancel Decision',exact:true}).count(),0);
  assert.equal(await page.evaluate(()=>Object.values(sessionStorage).some(x=>x.includes('revise_manufactured_completion'))),false);await page.screenshot({path:path.join(out,'cancelled-history.png'),fullPage:true});
 });
 assert.deepEqual(errors,[]);assert.ok(responses.every(r=>r.status===200||(r.path==='/api/data'&&r.status===401)));fs.writeFileSync(path.join(out,'results.json'),JSON.stringify({checks,errors,responses},null,2));
}catch(e){await page.screenshot({path:path.join(out,'failure.png'),fullPage:true});fs.writeFileSync(path.join(out,'failure.txt'),String(e));fs.writeFileSync(path.join(out,'failure-responses.json'),JSON.stringify({checks,errors,responses},null,2));throw e;}finally{await browser.close();}
