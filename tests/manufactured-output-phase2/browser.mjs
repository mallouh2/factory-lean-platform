import assert from 'node:assert/strict';
import fs from 'node:fs';import path from 'node:path';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Output-P2-Preview-location.txt'),'utf8').trim(),config=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
assert.equal(config.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(config.databaseHost,'127.0.0.1');assert.equal(config.applicationPort,4214);
const account=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts.find(a=>a.role==='owner'),base='http://127.0.0.1:4214';
const en=JSON.parse(fs.readFileSync('src/locales/en.json','utf8')),ar=JSON.parse(fs.readFileSync('src/locales/ar.json','utf8')),browser=await chromium.launch({channel:'msedge',headless:true}),context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[],http=[],checks=[];
const out=path.join(root,'phase2-browser');fs.mkdirSync(out,{recursive:true});
await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.url().includes('/api/manufactured-output'))http.push({status:r.status(),method:r.request().method()});});
async function check(name,fn){await fn();checks.push(name);console.log('PASS '+name);}
try{
 await check('normal local owner login and complete application',async()=>{await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});await page.goto(base+'/?view=lines');await page.locator('.prv3-launch').waitFor();});
 await check('actual recording form: 90 finished + 6 and 4 unfinished, no immediate stock',async()=>{
  const existing=await page.request.get(base+'/api/manufactured-output?'+new URLSearchParams({factory:config.context.factory}));if((await existing.json()).rows.length)return;
  await page.locator('.prv3-launch button.primary').click();const form=page.locator('#prv3-record-form');await form.locator('select').first().selectOption(config.context.item);
  await page.getByText('Local workflow preview — output awaits Quality and Warehouse.',{exact:true}).last().waitFor();
  await form.locator('input[inputmode=decimal]').nth(0).fill('90');await form.locator('input[inputmode=decimal]').nth(1).fill('0');
  const declaration=page.getByRole('checkbox',{name:en.prv3Declare,exact:true});if(await declaration.count())await declaration.check();
  await form.locator('summary').filter({hasText:en.prv3Optional}).click();await form.getByRole('checkbox',{name:en.prv3IncludeWip,exact:true}).check();
  await form.getByRole('button',{name:'Add unfinished quantity group',exact:true}).click();await form.getByRole('button',{name:'Add unfinished quantity group',exact:true}).click();
  const groups=form.locator('.prv3-details > fieldset');await groups.nth(0).locator('input[inputmode=decimal]').fill('6');await groups.nth(0).getByRole('checkbox').nth(0).check();await groups.nth(1).locator('input[inputmode=decimal]').fill('4');await groups.nth(1).getByRole('checkbox').nth(0).check();await groups.nth(1).getByRole('checkbox').nth(1).check();
  await page.screenshot({path:path.join(out,'recording-en.png'),fullPage:true});
  await page.getByRole('button',{name:en.prv3Save,exact:true}).click();await page.getByRole('heading',{name:en.prv3Saved,exact:true}).waitFor({timeout:60000});await page.getByRole('button',{name:en.done,exact:true}).click();
 });
 await check('Quality reclassification and partial handoff release through actual UI',async()=>{
  const existing=await page.request.get(base+'/api/manufactured-output?'+new URLSearchParams({factory:config.context.factory,mode:'quality'}));const existingRow=(await existing.json()).rows[0];if(existingRow?.quality){config.output=existingRow;return;}
  await page.locator('#factory-navigation').getByRole('button',{name:en.quality,exact:true}).press('Enter');await page.getByRole('heading',{name:'Quality determination',exact:true}).waitFor();
  const board=page.locator('section.quality-v2').filter({has:page.getByRole('heading',{name:'Quality determination',exact:true})}).last();await board.locator('select').first().selectOption({index:1});await board.locator('summary').first().click();await board.getByRole('button',{name:'Inspect / amend',exact:true}).click();
  const dialog=page.locator('dialog'),groups=dialog.locator('.prv3-details > fieldset');
  const initial=await groups.count();assert.equal(initial,3);let finished;
  for(let i=0;i<initial;i++)if(await groups.nth(i).locator('input[type=checkbox]:checked').count()===0)finished=groups.nth(i);
  assert.ok(finished);await finished.locator('input[inputmode=decimal]').nth(0).fill('85');await finished.locator('input[inputmode=decimal]').nth(1).fill('40');
  await dialog.getByRole('button',{name:'Add unfinished quantity group',exact:true}).click();await groups.last().locator('input[inputmode=decimal]').nth(0).fill('5');await groups.last().getByRole('checkbox').nth(0).check();
  await dialog.getByLabel('Findings and reason',{exact:true}).fill('Local inspection: five meters require the configured operation.');
  await dialog.getByRole('button',{name:'Save Quality determination',exact:true}).click();await dialog.waitFor({state:'detached',timeout:60000});
  const response=await page.request.get(base+'/api/manufactured-output?'+new URLSearchParams({factory:config.context.factory,mode:'quality'}));assert.equal(response.status(),200);const row=(await response.json()).rows[0];assert.equal(row.original.length,3);assert.equal(row.quality.groups.length,4);assert.equal(row.quality.requires_production_approval,false);config.output=row;
 });
 await check('Production notification can be marked read without a second approval',async()=>{
  const existing=await page.request.get(base+'/api/manufactured-output?'+new URLSearchParams({factory:config.context.factory,mode:'notifications'}));if((await existing.json()).rows[0]?.unread===false)return;
  await page.goto(base+'/?view=lines');const board=page.locator('section.quality-v2').filter({has:page.getByRole('heading',{name:'Quality updates',exact:true})});await board.locator('select').selectOption(config.output.id);await board.locator('summary').click();await board.getByRole('button',{name:'Mark read',exact:true}).click();await page.waitForFunction(()=>document.querySelector('section.quality-v2 button')?.disabled===false);await page.waitForTimeout(500);
  const response=await page.request.get(base+'/api/manufactured-output?'+new URLSearchParams({factory:config.context.factory,mode:'notifications'}));assert.equal((await response.json()).rows[0].unread,false);
 });
 await check('Arabic RTL 390px existing History details show original and Quality results',async()=>{
  await page.getByRole('button',{name:'العربية',exact:true}).click();await page.setViewportSize({width:390,height:844});await page.goto(base+'/?view=productionHistory');await page.locator('.production-history').waitFor();
  assert.equal(await page.locator('html').getAttribute('dir'),'rtl');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1));
  await page.locator('#history-card-'+config.output.entry_id).click();await page.locator('.history-actions-button').click();await page.getByRole('menuitem',{name:ar.historyViewDetails,exact:true}).click();
  await page.locator('dialog').getByRole('heading',{name:'قرار الجودة',exact:true,level:3}).waitFor();await page.getByText('التسجيل الأصلي للفني',{exact:true}).waitFor();
  await page.screenshot({path:path.join(out,'history-ar-mobile.png'),fullPage:true});
  const response=await page.request.get(base+'/api/manufactured-output?'+new URLSearchParams({factory:config.context.factory,mode:'entry',target:config.output.entry_id}));assert.equal(response.status(),200);assert.equal((await response.json()).rows.length,1);
 });
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(out,'results.json'),JSON.stringify({checks,http,errors},null,2));
}catch(error){await page.screenshot({path:path.join(out,'failure.png'),fullPage:true});fs.writeFileSync(path.join(out,'failure.txt'),String(error));throw error;}finally{await browser.close();}
