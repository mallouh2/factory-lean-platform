import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const output=resolve(tmpdir(),'FactoryLean-Maintenance-Readiness-20261014','browser');await mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true,channel:'msedge'}),context=await browser.newContext({viewport:{width:1280,height:900}});
await context.route('**/*',route=>route.request().url().startsWith('http://127.0.0.1:4205/')?route.continue():route.abort());
const page=await context.newPage(),errors=[],report=[];page.on('pageerror',e=>errors.push(e.message));
let state='idle',wrongScope=false,deny=false,applicable=true;
await page.route('**/api/production-readiness?*',route=>{
 const reason=['stopped','offline','setup'].includes(state)?'PHYSICAL_STATUS':state==='open'?'OPEN_LINKED_STOP':state==='transfer'?'TRANSFER_OWNERSHIP':null;
 const q=new URL(route.request().url()).searchParams;
 return route.fulfill({status:deny?403:200,contentType:'application/json',body:JSON.stringify(deny?{error:'permissionError'}:{factory:wrongScope?'foreign':q.get('factory'),item:q.get('item'),queue_ready:true,
  physical:{applicable,ready:!reason,reason,machine:{id:'machine',code:'EX-1',name:'Extruder',name_ar:'ماكينة البثق',status:['open','held','transfer'].includes(state)?(state==='held'?'idle':state==='transfer'?'running':'stopped'):state}},
  maintenance_block:state==='held'?{reason:'MAINTENANCE_HOLD',machine:{code:'EX-1',name:'Extruder',name_ar:'ماكينة البثق',status:'idle'}}:null})});
});
async function load(){await page.goto('http://127.0.0.1:4205/?view=readiness');await page.getByText('Physically ready for preparation',{exact:true}).waitFor();}
try {
 await load();const start=page.getByRole('button',{name:'Start Production',exact:true});assert.ok(await start.isEnabled());
 assert.equal(await page.getByRole('heading',{name:'Queue ready'}).count(),1);assert.match(await page.locator('.ff2-start-readiness').innerText(),/EX-1/);report.push('PASS IDLE preparation, separate queue/physical facts and exact machine');
 state='running';await page.getByRole('button',{name:'Refresh',exact:true}).click();await page.getByText('Running',{exact:false}).first().waitFor();assert.ok(await start.isEnabled());report.push('PASS RUNNING eligibility display');
 for(const value of ['stopped','offline','setup','open','transfer','held']){
  state=value;await Promise.all([page.waitForResponse(r=>r.url().includes('/api/production-readiness?')),page.getByRole('button',{name:'Refresh',exact:true}).click()]);
  await page.waitForFunction(()=>document.querySelector('.ff2-start-readiness button')?.disabled && !document.querySelector('.ff2-start-readiness button:nth-child(2)')?.disabled);
  assert.ok(await start.isDisabled());assert.match(await page.locator('.ff2-start-readiness').innerText(),/EX-1/);
  if(['stopped','offline','setup'].includes(value))await page.getByText(value==='setup'?'Setup':value==='offline'?'Offline':'Stopped',{exact:false}).first().waitFor();
  report.push('PASS '+value+' blocks preparation with machine/reason');
 }
 state='idle';await page.getByRole('button',{name:'Refresh',exact:true}).click();await page.getByText('Physically ready for preparation',{exact:true}).waitFor();
 state='stopped';await start.click();await page.getByText('Required machine is not ready',{exact:true}).waitFor();
 assert.equal((await page.evaluate(()=>window.commands)).length,1);assert.ok(await start.isDisabled());report.push('PASS Start attempt rejected by synthetic writer, authoritative refresh updates stale display');
 await page.screenshot({path:join(output,'readiness-desktop.png'),fullPage:true});
 wrongScope=true;await page.getByRole('button',{name:'Refresh',exact:true}).click();await page.getByText('Physical readiness has not been checked. Refresh before starting.').waitFor();assert.ok(await start.isDisabled());report.push('PASS wrong factory response fails closed');
 wrongScope=false;deny=true;await page.getByRole('button',{name:'Refresh',exact:true}).click();await page.getByRole('alert').waitFor();assert.ok(await start.isDisabled());report.push('PASS read denial discloses no machine');
 deny=false;state='idle';applicable=false;await page.getByRole('button',{name:'Refresh',exact:true}).click();await page.getByText('No post-maintenance restriction applies',{exact:true}).waitFor();assert.ok(await start.isEnabled());report.push('PASS ordinary no-maintenance eligibility preserved');
 state='offline';applicable=true;await page.setViewportSize({width:390,height:844});await page.goto('http://127.0.0.1:4205/?view=readiness&lang=ar');
 await page.getByText('الماكينة المطلوبة غير جاهزة',{exact:true}).waitFor();assert.equal(await page.locator('html').getAttribute('dir'),'rtl');
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:join(output,'readiness-ar-mobile.png'),fullPage:true});report.push('PASS Arabic/RTL390 and exact affected machine, without page overflow');
 await page.getByRole('button',{name:'Edit authority: on',exact:true}).click();assert.equal(await page.getByRole('button',{name:'بدء الإنتاج',exact:true}).count(),0);report.push('PASS view-only staff see readiness without a Start action');
 assert.deepEqual(errors,[]);await writeFile(join(output,'results.json'),JSON.stringify({report,errors},null,2));console.log(report.join('\n'));
}finally{await browser.close();}
