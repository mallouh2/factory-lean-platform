// Final rebuilt UI: reads and view controls only. Never repeat acceptance writes.
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Planning-V3-location.txt'),'utf8').trim(),base='http://127.0.0.1:4222';
const en=JSON.parse(fs.readFileSync('src/locales/en.json','utf8')),ar=JSON.parse(fs.readFileSync('src/locales/ar.json','utf8'));
const browser=await chromium.launch({channel:'msedge',headless:true});
try{
 const context=await browser.newContext({storageState:path.join(root,'browser-owner-final.json'),viewport:{width:1440,height:1080}}),page=await context.newPage(),errors=[],responses=[];
 await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)responses.push({path:new URL(r.url()).pathname,http:r.status()});});
 await page.goto(base);await page.locator('.app-shell').waitFor();
 if(await page.getByRole('button',{name:'English',exact:true}).count())await page.getByRole('button',{name:'English',exact:true}).click();
 await page.locator('#factory-navigation').getByRole('button',{name:en.planning,exact:true}).press('Enter');await page.locator('.planning-filters select').first().focus();await page.mouse.move(1400,80);await page.waitForTimeout(300);
 await page.getByRole('button',{name:en.planningWeek,exact:true}).click();await page.waitForFunction(()=>document.querySelector('[data-board-completeness="COMPLETE"]'));
 assert.ok(await page.locator('.planning-gantt-block').count()>=2);assert.ok(await page.locator('.planning-requests-progressed tbody tr').count()>=4);
 const before=await page.locator('.planning-filters select').first().inputValue();await page.locator('.planning-requests-waiting .planning-table-select').first().focus();await page.keyboard.press('Enter');await page.locator('.planning-drawer').waitFor();await page.keyboard.press('Escape');await page.locator('.planning-drawer').waitFor({state:'detached'});assert.equal(await page.locator('.planning-filters select').first().inputValue(),before);
 await page.screenshot({path:path.join(root,'planning-desktop-final.png'),fullPage:true});
 const widths=[];
 for(const lang of ['en','ar']){
  if(lang==='ar')await page.getByRole('button',{name:'العربية',exact:true}).click();
  await page.setViewportSize({width:390,height:844});await page.locator('.planning-v3[dir='+ (lang==='ar'?'rtl':'ltr')+']').waitFor();await page.mouse.move(389,0);await page.waitForTimeout(250);
  assert.equal(await page.locator('.planning-timeline-scroll').isVisible(),true);assert.equal(await page.locator('.planning-mobile-lines').isVisible(),false);
  const size=await page.evaluate(()=>({body:document.documentElement.scrollWidth,viewport:innerWidth,chart:document.querySelector('.planning-timeline-scroll').scrollWidth,table:document.querySelector('.planning-work-table').getBoundingClientRect().width}));assert.ok(size.body<=size.viewport+1,JSON.stringify(size));assert.ok(size.chart>size.viewport);assert.ok(size.table<size.viewport);widths.push({lang,...size});
  const queue=page.locator('.planning-requests-waiting');assert.ok((await queue.innerText()).includes(lang==='ar'?ar.planningReadyToSchedule:en.planningReadyToSchedule));
  await page.screenshot({path:path.join(root,'planning-'+lang+'-mobile.png'),fullPage:true});
 }
 assert.deepEqual(errors,[]);assert.deepEqual(responses,[]);fs.writeFileSync(path.join(root,'visual-final.json'),JSON.stringify({errors,responses,widths,keyboard:'Enter opens details; Escape returns with filters unchanged',gantt:'Real persisted jobs visible at week scale'},null,2));console.log('Final desktop, keyboard and EN/AR 390px checks PASS; no page/API errors');
}finally{await browser.close();}
