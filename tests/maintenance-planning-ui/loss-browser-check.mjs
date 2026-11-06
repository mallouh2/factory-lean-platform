import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
import {calculateProductionLoss} from '../../src/utils/production-loss-impact.mjs';
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const output=resolve(tmpdir(),'FactoryLean-Maintenance-Loss-20261014','browser');await mkdir(output,{recursive:true});
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const at=n=>new Date(Date.UTC(2026,9,14,10)+n*60000).toISOString();
const event={id:id(9),factory_id:id(1),work_center_id:id(3),line_id:id(4),started_at:at(0),ended_at:at(40),stop_nature:'planned',planned_activity:'inspection',loss_model_version:1};
const evidence={operation:'LINK',event_id:event.id,machine_id:id(3),relationship:'PLANNED_MAINTENANCE',valid:true,approved_start:at(10),approved_end:at(30)};
const base={maintenance_loss_context_version:1,demand_complete:true,routing_steps:[],orders:[],centers:[{id:id(3),line_id:id(4),status:'stopped',dependency_mode:'blocking',impact_scope:'whole_line'}],stops:[{work_center_id:id(3),started_at:at(0),ended_at:null}],transfers:[],capabilities:[{work_center_id:id(3),product_id:id(6),rate:60,rate_unit:'meter'}],products:[{id:id(6),unit:'meter'}],profiles:[{work_center_id:id(3),product_id:id(6),scrap_expected:false,can_defer:false}],lines:[]};
const browser=await chromium.launch({headless:true,channel:'msedge'}),ctx=await browser.newContext({viewport:{width:1280,height:900}});
await ctx.route('**/*',r=>r.request().url().startsWith('http://127.0.0.1:4205/')?r.continue():r.abort());
const page=await ctx.newPage(),errors=[],report=[];page.on('pageerror',e=>errors.push(e.message));let scenario='zero';
function detail(){const context={...base,demand_complete:scenario!=='missing',orders:['changed','unknown'].includes(scenario)?[{id:id(8),line_id:id(4),product_id:id(6),status:'planned',start_time:at(0),expected_finish:at(7)}]:[]};
 const calculation=calculateProductionLoss(event,[{id:1,event_id:event.id,captured_at:at(0),context}],null,Date.parse(at(45)),[],evidence);
 const saved=['changed','unknown'].includes(scenario)?{id:id(10),result:calculation}:null;
 return {event,actual:null,correction:null,saved,calculation:saved?.result||calculation,suggestions:[],maintenance:{evidence,review_state:scenario==='changed'?'EVIDENCE_CHANGED_AFTER_REVIEW':scenario==='unknown'?'EVIDENCE_COMPARISON_UNKNOWN':'UNREVIEWED'}};}
await page.route('**/api/loss-review?*',r=>{const q=new URL(r.request().url()).searchParams;
 return r.fulfill({status:scenario==='denied'?403:200,contentType:'application/json',body:JSON.stringify(scenario==='denied'?{error:'permissionError'}:q.has('event')?detail():{rows:[event],total:1,pages:1})});});
async function load(lang='en'){await page.goto('http://127.0.0.1:4205/?view=loss&lang='+lang);}
try{
 await load();await page.getByText('Within approved maintenance window',{exact:true}).waitFor();
 assert.match(await page.locator('dl').innerText(),/40 min/);assert.match(await page.locator('dl').innerText(),/20 min/);
 assert.equal(await page.getByRole('button',{name:'Save reviewed estimate',exact:true}).count(),1);report.push('PASS physical/approved/outside/effective durations and verified zero save eligibility');
 await page.getByRole('button',{name:'Save reviewed estimate',exact:true}).click();
 assert.equal((await page.evaluate(()=>window.commands)).length,1);assert.equal((await page.evaluate(()=>window.commands))[0].name,'save_production_loss_estimate');report.push('PASS identity-only review action, synthetic write rejected');
 scenario='missing';await load();await page.getByText(/Recorded production demand or routing is incomplete/).waitFor();
 assert.equal(await page.getByRole('button',{name:'Save reviewed estimate',exact:true}).count(),0);report.push('PASS incomplete evidence fails closed');
 scenario='changed';await load();await page.getByText('Maintenance or classification evidence changed after review.',{exact:true}).waitFor();
 assert.match(await page.locator('dl').innerText(),/7 min/);assert.equal(await page.getByRole('button',{name:'Save reviewed estimate',exact:true}).count(),0);report.push('PASS historical warning and original loss retained');
 await page.screenshot({path:join(output,'loss-desktop.png'),fullPage:true});
 scenario='unknown';await load();await page.getByText(/This older estimate has insufficient evidence/).waitFor();report.push('PASS unknown historical comparison');
 scenario='zero';await load();await page.getByRole('button',{name:'Edit authority: on'}).click();
 assert.equal(await page.getByRole('button',{name:'Save reviewed estimate',exact:true}).count(),0);report.push('PASS view-only review without write controls');
 scenario='denied';await load();await page.getByText('You do not have permission for this action.',{exact:false}).first().waitFor();
 assert.equal(await page.locator('dl').count(),0);report.push('PASS denied reads disclose no loss details');
 scenario='changed';await page.setViewportSize({width:390,height:844});await load('ar');
 await page.getByText('تغيرت أدلة الصيانة أو التصنيف بعد المراجعة.',{exact:true}).waitFor();
 assert.equal(await page.locator('html').getAttribute('dir'),'rtl');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.screenshot({path:join(output,'loss-ar-mobile.png'),fullPage:true});report.push('PASS Arabic RTL mobile warning, durations and no page overflow');
 assert.deepEqual(errors,[]);await writeFile(join(output,'results.json'),JSON.stringify({checks:report,pageErrors:errors},null,2));console.log(report.join('\n'));
}finally{await browser.close();}
