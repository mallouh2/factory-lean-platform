// Real components; isolated, labelled synthetic READ responses. Every write remains rejected.
import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const output=resolve(tmpdir(),'FactoryLean-Maintenance-Readers-20261012','proof');await mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true,channel:'msedge'}),context=await browser.newContext({viewport:{width:1440,height:1000}});
await context.route('**/*',route=>route.request().url().startsWith('http://127.0.0.1:4205/')?route.continue():route.abort());
const page=await context.newPage(),errors=[],results=[];page.on('pageerror',error=>errors.push(error.message));
const shot=name=>page.screenshot({path:join(output,name+'.png')});
try {
 await page.goto('http://127.0.0.1:4205/');await page.locator('.mr-open').first().click();const dialog=page.getByRole('dialog');
 await dialog.getByRole('button',{name:'Check candidate window',exact:true}).click();await dialog.getByText('Capacity clear in this read',{exact:true}).waitFor();
 assert.equal(await dialog.getByRole('button',{name:'Confirm reservation',exact:true}).isDisabled(),true);await shot('readers-desktop');results.push('Clear read is nonbinding and confirmation disabled');
 const start=dialog.getByLabel('Proposed start · Asia/Riyadh',{exact:true});await start.fill('2030-01-01T09:00');
 assert.equal(await dialog.getByText('Capacity clear in this read',{exact:true}).count(),0);await dialog.getByText(/factory scheduling context changed/).waitFor();results.push('Edited input hides obsolete CLEAR');
 await dialog.locator('summary').filter({hasText:'Find available maintenance windows'}).click();await dialog.getByRole('button',{name:'Find available maintenance windows',exact:true}).click();
 await dialog.getByRole('button',{name:/^Use suggestion and check preview:/}).click();assert.equal(await page.evaluate(()=>window.commands?.length||0),0);results.push('Server suggestion fills draft fields without creating a reservation');
 await page.route('**/api/maintenance-planning?*mode=preview*',async route=>{const response=await route.fetch(),body=await response.json();await route.fulfill({response,json:{...body,capacity:'BLOCKED',conflicts:[{code:'maintenanceProductionConflict',reference_id:'10000000-0000-0000-0000-000000000008',kind:'PRODUCTION',state:'planned',unknown_end:false}]}});});
 await dialog.getByRole('button',{name:'Check candidate window',exact:true}).click();await dialog.getByText('Capacity blocked / no eligible opening',{exact:true}).waitFor();
 await dialog.getByText(/This maintenance window conflicts with production/).waitFor();results.push('Backend conflict code is presented with safe reference');
 await page.setViewportSize({width:768,height:1024});await shot('readers-tablet');
 await page.keyboard.press('Escape');await page.getByRole('button',{name:'English / العربية',exact:true}).click();await page.setViewportSize({width:390,height:844});
 await page.locator('.mr-open').first().click();await page.getByRole('dialog').getByRole('button',{name:'التحقق من الفترة المقترحة',exact:true}).scrollIntoViewIfNeeded();await shot('readers-arabic-mobile');
 assert.equal(await page.evaluate(()=>document.querySelector('dialog').scrollWidth>document.querySelector('dialog').clientWidth),false);assert.equal(await page.evaluate(()=>document.documentElement.dir),'rtl');results.push('Desktop/tablet/Arabic RTL/390px controls fit');
 await page.keyboard.press('Escape');await page.getByRole('button',{name:'Edit authority: on',exact:true}).click();await page.locator('.mr-open').first().click();
 assert.equal(await page.getByRole('dialog').getByRole('button',{name:'حفظ الاقتراح',exact:true}).count(),0);results.push('Reader access does not grant command authority');
 assert.deepEqual(errors,[]);await writeFile(join(output,'browser-results.json'),JSON.stringify({results,errors,scope:'Isolated components and synthetic reads. No hosted or database persistence evidence.'},null,2));console.log(JSON.stringify({results,errors}));
}finally{await browser.close();}
