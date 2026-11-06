// One focused Edge pass, real local Next APIs and original protected SQL.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Phase4B-FIX-runtime-location.txt'),'utf8').trim(),runtime=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
assert.equal(runtime.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(runtime.databaseHost,'127.0.0.1');
const output=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Phase4C-location.txt'),'utf8').trim(),fixture=JSON.parse(fs.readFileSync(path.join(output,'fixture.json'))),accounts=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'))).accounts;
const en=JSON.parse(fs.readFileSync('src/locales/en.json')),ar=JSON.parse(fs.readFileSync('src/locales/ar.json')),base='http://127.0.0.1:4207',browser=await chromium.launch({channel:'msedge',headless:true});
const checks=[],errors=[];let worker,owner;
async function login(role,view='productionHistory'){
 const context=await browser.newContext({viewport:{width:1440,height:1000}});await context.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());
 const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));await page.goto(base+'/?view='+view);const account=accounts.find(x=>x.role===role);
 await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});return {context,page};
}
async function correction(page){
 const row=page.locator('#history-row-'+fixture.entry);await row.waitFor({timeout:60000});await row.click();const actions=page.locator('.history-actions-button');await actions.waitFor();await actions.click();await page.getByRole('menuitem',{name:en.pcRequest,exact:true}).click();await page.locator('.pc-quantity-grid input').first().waitFor({timeout:30000});return page.locator('.pc-dialog');
}
try{
 worker=await login('worker');let dialog=await correction(worker.page);
 assert.equal(await dialog.locator('.pc-quantity-grid input').first().inputValue(),'1.5');assert.equal(await dialog.locator('.pc-quantity-grid input').nth(1).inputValue(),'0.15');
 const reason=dialog.locator('textarea');await reason.fill('   ');assert.equal(await dialog.locator('form button.primary').isEnabled(),false);await dialog.getByRole('button',{name:en.pcReasonMeasurement,exact:true}).click();assert.equal(await reason.inputValue(),en.pcReasonMeasurement);await reason.fill('Phase4C browser: sample weight checked');await dialog.locator('.pc-quantity-grid input').nth(1).fill('0.2');
 await dialog.locator('form button.primary').click();await dialog.getByText(en.pcPendingSuccess,{exact:true}).waitFor({timeout:30000});checks.push('worker request, editable suggestion, mandatory reason and explicit pending result');
 const pendingRead=await worker.page.request.get(base+'/api/production-corrections?'+new URLSearchParams({factory:runtime.context.factory,status:'PENDING'}));assert.equal(pendingRead.status(),200);const pending=(await pendingRead.json()).rows.find(r=>r.entry_id===fixture.entry);assert.equal(pending.current_values.scrap_kg,'0.15');assert.equal(pending.current_values.good,'1.5');checks.push('actual protected read: pending preserves official quantities');
 owner=await login('owner','productionCorrections');const q=owner.page.locator('.production-corrections');await q.locator('tbody tr').filter({hasText:'Phase4C browser: sample weight checked'}).waitFor({timeout:30000});assert.equal(await q.locator('thead th').count(),6);await q.locator('tbody tr').filter({hasText:'Phase4C browser: sample weight checked'}).click();await q.getByRole('button',{name:/^Actions/}).click();await owner.page.locator('#pc-actions-menu').getByRole('button',{name:en.approve,exact:true}).click();await owner.page.locator('.pc-dialog form button.primary').click();await q.getByText(en.pcApprovedSuccess,{exact:true}).waitFor({timeout:30000});checks.push('normal independent owner login and authorized queue approval');
 await owner.page.goto(base+'/?view=productionHistory');dialog=await correction(owner.page);assert.equal(await dialog.locator('.pc-quantity-grid input').nth(1).inputValue(),'0.2');await dialog.locator('.pc-quantity-grid input').nth(1).fill('0.3');await dialog.locator('textarea').fill('Phase4C browser: owner measurement correction');await dialog.locator('form button.primary').click();await dialog.getByText(en.pcApprovedSuccess,{exact:true}).waitFor({timeout:30000});checks.push('self approval and History official value refresh');
 await owner.page.screenshot({path:path.join(output,'correction-desktop-en.png')});await dialog.getByRole('button',{name:'العربية',exact:true}).click();await owner.page.setViewportSize({width:390,height:844});await dialog.getByText(ar.pcApprovedSuccess,{exact:true}).waitFor();assert.equal(await owner.page.locator('html').getAttribute('dir'),'rtl');assert.ok(await owner.page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await owner.page.screenshot({path:path.join(output,'correction-mobile-ar.png')});checks.push('Arabic RTL and 390px modal, no page overflow');
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(output,'browser-results.json'),JSON.stringify({checks,errors,edge:browser.version(),limits:'Disposable local Auth/Data protocol adapter, not hosted Supabase. SQL fixtures and this pass only.'},null,2));console.log('PASS '+checks.length+' focused browser groups; evidence '+output);
}finally{await worker?.context.close();await owner?.context.close();await browser.close();}
