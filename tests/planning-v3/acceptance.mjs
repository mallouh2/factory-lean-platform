import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Planning-V3-location.txt'),'utf8').trim(),c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,'')),x=c.context,base='http://127.0.0.1:4222';
assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.databasePort,55496);assert.equal(c.applicationPort,4222);
const en=JSON.parse(fs.readFileSync('src/locales/en.json','utf8')),ar=JSON.parse(fs.readFileSync('src/locales/ar.json','utf8'));
const file=path.join(root,'acceptance.json'),evidence=fs.existsSync(file)?JSON.parse(fs.readFileSync(file)): {steps:[],responses:[],errors:[]};
const save=()=>fs.writeFileSync(file,JSON.stringify(evidence,null,2)),pass=(name,data={})=>{evidence.steps.push({name,...data});save();};
const browser=await chromium.launch({channel:'msedge',headless:true});let debugPage;
try{
 const context=await browser.newContext({storageState:path.join(root,'browser-owner.json'),viewport:{width:1440,height:1080}}),page=await context.newPage();
 debugPage=page;page.setDefaultTimeout(12000);await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());page.on('pageerror',err=>{evidence.errors.push(err.message);save();});
 const snapshot=()=>page.evaluate(async()=>{const r=await fetch('/api/data');return {status:r.status,body:await r.json()};});
 const api=(command,args)=>page.evaluate(async({command,args})=>{const r=await fetch('/api/data',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command,args})});return {status:r.status,body:await r.json()};},{command,args});
 const nav=async key=>{await page.locator('#factory-navigation').getByRole('button',{name:en[key],exact:true}).press('Enter');await page.locator('main').locator('button,select,input').first().focus();await page.mouse.move(1400,80);await page.waitForTimeout(250);};
 const mutation=async(command,act)=>{const wait=page.waitForResponse(r=>{try{return r.request().method()==='POST'&&r.request().postDataJSON()?.command===command;}catch{return false;}},{timeout:20000});await act();const r=await wait,body=await r.json();evidence.responses.push({command,http:r.status(),body});save();assert.equal(r.status(),200,JSON.stringify(body));return body;};
 const row=id=>page.locator('.planning-work-table tr[data-item-id="'+id+'"]');
 const open=async id=>{await row(id).getByRole('button').click();await page.locator('.planning-drawer').waitFor();};
 const close=()=>page.locator('.planning-drawer').getByRole('button',{name:en.close,exact:true}).click();
 await page.goto(base);await page.locator('.app-shell').waitFor({timeout:30000});let snap=await snapshot();assert.equal(snap.status,200);assert.equal(snap.body.user.id,x.owner);assert.equal(snap.body.factory.id,x.factory);await nav('planning');await page.locator('.planning-v3').waitFor();
 const tomorrow=new Date();tomorrow.setUTCDate(tomorrow.getUTCDate()+1);const day=tomorrow.toISOString().slice(0,10);
 const range=page.locator('.planning-support').filter({has:page.locator('.planning-board-toolbar')});await range.locator('summary').click();await range.locator('input[type=datetime-local]').fill(day+'T00:00');await range.locator('summary').click();
 await page.waitForFunction(()=>document.querySelector('[data-board-completeness="COMPLETE"]'));
 assert.ok(await row(x.recovery).count());pass('Actual protected completion work appears in unified queue',{item:x.recovery});
 snap=await snapshot();let job=snap.body.tables.production_orders.find(o=>o.id===x.form);
 if(!job.line_id){
  await open(x.form);const drawer=page.locator('.planning-drawer');await drawer.locator('.planning-field select').selectOption(x.line);
  await drawer.locator('input[type=datetime-local]').fill(day+'T08:00');assert.ok(await drawer.locator('.planning-proposal').innerText());
  await mutation('plan_product_item',()=>drawer.getByRole('button',{name:en.planningSaveSchedule,exact:true}).click());await drawer.waitFor({state:'detached'});
 }
 snap=await snapshot();job=snap.body.tables.production_orders.find(o=>o.id===x.form);assert.equal(job.line_id,x.line);assert.ok(job.expected_finish);assert.equal(await page.locator('.planning-requests-waiting tr[data-item-id="'+x.form+'"]').count(),0);assert.ok(await row(x.form).count());pass('Manual scheduling persisted and moved queue → Gantt/list',{item:x.form,start:job.start_time,finish:job.expected_finish});
 if(!evidence.steps.some(s=>s.name==='Protected invalid capability and overlap rejection')){
  const initial=snap.body.tables.production_orders.find(o=>o.id===x.drag);
  for(const [line,start,label]of [[x.invalid_line,day+'T10:00:00Z','capability'],[x.line,job.start_time,'overlap']]){
   const r=await api('plan_product_item',{factory:x.factory,item:x.drag,target_line:line,planned_start:start});evidence.responses.push({check:label,...r});save();assert.ok(r.status>=400,JSON.stringify(r));
  }
  const after=(await snapshot()).body.tables.production_orders.find(o=>o.id===x.drag);assert.equal(after.line_id,initial.line_id);assert.equal(after.start_time,initial.start_time);pass('Protected invalid capability and overlap rejection');
 }
 if(!evidence.steps.some(s=>s.name==='Replanning reason and immutable history')){
  if(!evidence.responses.some(r=>r.command==='revise_product_plan'&&r.http===200)){
  await open(x.form);const drawer=page.locator('.planning-drawer');await drawer.locator('input[type=datetime-local]').fill(day+'T10:00');await drawer.getByRole('button',{name:en.planningSaveSchedule,exact:true}).click();const reason=page.locator('.planning-reason-dialog');await reason.waitFor();assert.equal(await reason.locator('button.primary').isDisabled(),true);
  await reason.locator('select').selectOption('material_delay');await mutation('revise_product_plan',()=>reason.locator('button.primary').click());await reason.waitFor({state:'detached'});}
  await open(x.form);const history=page.locator('.planning-drawer details').filter({has:page.locator('.planning-history')});await history.locator('summary').click();await history.locator('ol li').first().waitFor();assert.ok((await history.innerText()).includes(en.planningReason_material_delay));assert.ok(await history.locator('ol li').count()>=2);await close();pass('Replanning reason and immutable history');
 }
 snap=await snapshot();job=snap.body.tables.production_orders.find(o=>o.id===x.drag);
 if(!job.line_id){
  const source=row(x.drag).getByRole('button'),lane=page.locator('.planning-lane').filter({has:page.locator('.planning-line-name').getByText('Printing line',{exact:true})}).locator('.planning-lane-track');
  const bounds=await lane.boundingBox();assert.ok(bounds);await mutation('plan_product_item',()=>source.dragTo(lane,{targetPosition:{x:Math.floor(bounds.width*.6),y:35}}));
 }
 snap=await snapshot();job=snap.body.tables.production_orders.find(o=>o.id===x.drag);assert.equal(job.line_id,x.line);assert.ok(job.expected_finish);await page.locator('.planning-requests-waiting tr[data-item-id="'+x.drag+'"]').waitFor({state:'detached'});pass('Real queue-to-Gantt drag persisted through protected SQL',{item:x.drag,start:job.start_time,finish:job.expected_finish});
 for(const [id,label]of [[x.locked,'locked'],[x.item,'completed']]){
  const before=(await snapshot()).body.tables.production_orders.find(o=>o.id===id),r=await api('revise_product_plan',{factory:x.factory,item:id,target_line:x.line,planned_start:day+'T17:00:00Z',reason_code:'material_delay',reason_note:'Local protected rejection check'});
  evidence.responses.push({check:label,...r});save();assert.ok(r.status>=400);const after=(await snapshot()).body.tables.production_orders.find(o=>o.id===id);assert.deepEqual(after,before);
 }pass('Locked/completed work remains protected with unchanged records');
 await nav('lines');assert.ok(await page.locator('[data-product-item-id="'+x.drag+'"]').count());pass('Scheduled job visible to Production');
 const prepared=page.locator('[data-product-item-id="'+x.form+'"]');
 const current=(await snapshot()).body.tables.production_orders.find(o=>o.id===x.form);
 if(current.status==='planned'){await prepared.waitFor();await mutation('start_product_item',()=>prepared.getByRole('button',{name:en.startProduction,exact:true}).click());}
 const running=(await snapshot()).body.tables.production_orders.find(o=>o.id===x.form);assert.equal(running.status,'active');assert.ok(running.actual_start);pass('Normal Production Start updates actual status without rewriting plan',{start:running.actual_start,planned:running.start_time});
 await nav('planning');await row(x.form).getByText(en.planningInProduction,{exact:true}).waitFor();pass('Planning reflects authoritative in-production state');
 await nav('planning');await open(x.recovery);await page.waitForFunction(()=>document.querySelectorAll('.planning-drawer .output-record-links button').length>=3);await page.locator('.planning-drawer .output-record-links button').first().click();
 const explorer=page.locator('.output-related-dialog');await explorer.getByText('Technician’s original recording',{exact:true}).waitFor();assert.ok((await explorer.innerText()).includes('90 meter'));
 await explorer.getByRole('button',{name:en.close,exact:true}).click();await explorer.waitFor({state:'detached'});assert.equal(await page.locator('.planning-drawer').count(),1);await close();pass('Contextual real source-record drill-through and return preserves selected order');
 await page.mouse.move(1400,80);await page.screenshot({path:path.join(root,'planning-desktop-final.png'),fullPage:true});
 await page.getByRole('button',{name:'العربية',exact:true}).click();await page.locator('.planning-v3[dir=rtl]').waitFor();await page.setViewportSize({width:390,height:844});await page.mouse.move(389,0);await page.waitForTimeout(400);
 assert.equal(await page.locator('.planning-timeline-scroll').isVisible(),true);assert.equal(await page.locator('.planning-mobile-lines').isVisible(),false);
 const widths=await page.evaluate(()=>({body:document.documentElement.scrollWidth,viewport:innerWidth,chart:document.querySelector('.planning-timeline-scroll').scrollWidth}));assert.ok(widths.body<=widths.viewport+1,JSON.stringify(widths));assert.ok(widths.chart>widths.viewport);await page.screenshot({path:path.join(root,'planning-ar-mobile.png'),fullPage:true});pass('Arabic RTL 390px real scrollable Gantt',{widths});
 await page.getByRole('button',{name:'English',exact:true}).click();await page.locator('.planning-v3[dir=ltr]').waitFor();await page.screenshot({path:path.join(root,'planning-en-mobile.png'),fullPage:true});pass('English 390px');assert.deepEqual(evidence.errors,[]);
 await context.storageState({path:path.join(root,'browser-owner-final.json')});save();console.log(JSON.stringify({steps:evidence.steps.length,errors:evidence.errors}));
}catch(error){if(debugPage){await debugPage.screenshot({path:path.join(root,'failure.png'),fullPage:true});fs.writeFileSync(path.join(root,'failure-text.txt'),await debugPage.locator('body').innerText());}throw error;}finally{await browser.close();}
