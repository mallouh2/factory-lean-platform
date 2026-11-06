import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
const {chromium}=createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE||'playwright');
const out=resolve(tmpdir(),'FactoryLean-Maintenance-Board-20261014','browser');await mkdir(out,{recursive:true});
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const iso=n=>new Date(n).toISOString();
let scenario='paged',release,gate=new Promise(done=>release=done),calls=[];
function rows(q){const from=Date.parse(q.get('start')),end=Date.parse(q.get('end')),now=Date.now();
 const make=(n,state='PROPOSED')=>{const sid=id(2000+n),rid=id(1000+n),old=['CONFIRMED','INVALIDATED'].includes(state)&&n>=2;
  const start=old?from-2*86400000:from+2*3600000,finish=old?from-86400000:from+3*3600000;
  const stop=n===2&&state==='CONFIRMED'?[{id:id(5000),work_center_id:id(3),started_at:iso(from-86400000),ended_at:null}]:n===4&&state==='RELEASED'?[{id:id(5001),work_center_id:id(3),started_at:iso(Math.min(now-7200000,from+3600000)),ended_at:iso(Math.min(now-3600000,from+7200000))}]:[];
  const hold=n===2&&state==='CONFIRMED',continued=old&&state!=='RELEASED';
  return {kind:'MAINTENANCE',id:sid,uncertain:scenario==='unknown',payload:{request:{id:rid,factory_id:id(1),work_center_id:id(3),code:'MR-QA-'+n,title:'Service '+n,status:'OPEN',maintenance_kind:'PLANNED',estimated_duration_minutes:30,priority:'NORMAL',revision:1,source:'MANUAL',machine_code:'EX-1',machine_name:'Extruder',machine_name_ar:'ماكينة البثق'},schedule:{id:sid,factory_id:id(1),maintenance_request_id:rid,work_center_id:id(3),code:'MR-QA-'+n,state,revision:2,planned_start:iso(start),planned_end:iso(finish),hold_started_at:hold?iso(from-86400000):null,released_at:n===4?iso(from+4*3600000):null,
   actual_hold:hold,overrun:hold,missed_window:continued&&!hold,resources:[{resource_kind:'MACHINE',machine_id:id(3),line_id:null},{resource_kind:'LINE',machine_id:null,line_id:id(4)}],line_ids:[id(4)],machine_ids:[id(3)],machine_code:'EX-1',actual_stops:stop,
   occupancy:{id:sid,reserved:['CONFIRMED','INVALIDATED'].includes(state),lineIds:[id(4)],machineIds:[id(3)],productIds:[],start:iso(start),finish:continued?null:iso(finish),continues:continued}}}};
 };
 if(['paged','stale'].includes(scenario))return Array.from({length:601},(_,n)=>make(n));
 const result=[make(0),make(1,'CONFIRMED'),make(2,'CONFIRMED'),make(3,'INVALIDATED'),make(4,'RELEASED')];
 if(q.get('domain')==='all')result.push({kind:'PRODUCTION',id:id(8),uncertain:false,payload:{order:{id:id(8),factory_id:id(1),request_id:id(7),product_id:id(6),code:'PI-QA',status:'planned',line_id:id(4),target_quantity:20,unit:'piece',start_time:iso(from+6*3600000),expected_finish:iso(from+8*3600000)},request:{id:id(7),factory_id:id(1),name:'Synthetic Production',code:'PO-QA',priority:'normal'},occupancy:{reserved:true,lineIds:[id(4)],start:iso(from+6*3600000),finish:iso(from+8*3600000)}}});
 return result;
}
const browser=await chromium.launch({headless:true,channel:'msedge'}),context=await browser.newContext({viewport:{width:1280,height:900}});
await context.route('**/*',r=>r.request().url().startsWith('http://127.0.0.1:4205/')?r.continue():r.abort());
const page=await context.newPage(),errors=[],report=[];page.on('pageerror',e=>errors.push(e.message));
await page.route('**/api/maintenance-planning?*',async route=>{
 const q=new URL(route.request().url()).searchParams;if(q.get('view')!=='operational')return route.continue();
 calls.push(Object.fromEntries(q));
 if(scenario==='denied')return route.fulfill({status:403,contentType:'application/json',body:JSON.stringify({completeness:'ERROR',error:'permissionError'})});
 const all=rows(q),after=q.get('after_id'),offset=after?all.findIndex(x=>x.id===after)+1:0,chosen=all.slice(offset,offset+100),more=offset+100<all.length;
 if(scenario==='paged'&&after)await gate;
 const stamp=q.get('evaluated_at')||new Date().toISOString();
 return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({factory:scenario==='wrong'?id(9):id(1),start:q.get('start'),end:q.get('end'),line:q.get('line'),machine:null,domain:q.get('domain'),active:false,
  rows:chosen,total:all.length,scope_complete:scenario!=='unknown',completeness:all.length>100||scenario==='unknown'?'INCOMPLETE':'COMPLETE',reason:scenario==='unknown'?'UNKNOWN_OCCUPANCY':all.length>100?'PAGES_PENDING':null,
  has_more:more,next:more?{kind:chosen.at(-1).kind,id:chosen.at(-1).id}:null,context_hash:scenario==='stale'&&after?'b'.repeat(64):'a'.repeat(64),evaluated_at:stamp,valid_until:new Date(Date.parse(stamp)+60000).toISOString(),preview_available:true,history_available:true})});
});
async function load(view='gantt',lang='en',extra=''){await page.goto('http://127.0.0.1:4205/?view='+view+'&lang='+lang+extra);}
try{
 await load('queue');await page.getByText(/The board is incomplete/).first().waitFor();
 await page.waitForFunction(()=>document.body.innerText.includes('100 / 601'));
 assert.equal(await page.getByText('Complete operational occupancy for this horizon',{exact:false}).count(),0);report.push('PASS first100 records remain INCOMPLETE while remaining pages wait');
 release();await page.getByText(/Complete operational occupancy for this horizon/).waitFor();assert.equal(calls.length,7);
 await page.getByRole('button',{name:/Proposed/}).click();assert.match(await page.locator('.mp-queue .mp-views').innerText(),/601/);report.push('PASS601 records, seven bounded calls, complete only after all pages');
 scenario='stale';await load('queue');await page.getByText(/The schedule changed while loading/).waitFor();assert.equal(await page.getByText(/Complete operational occupancy for this horizon/).count(),0);report.push('PASS changed snapshot refuses complete label');
 scenario='visual';await load();await page.locator('[data-board-completeness="COMPLETE"]').waitFor();
 assert.equal(await page.locator('.mp-timeline-block').count(),5);assert.equal(await page.locator('.planning-gantt-block').count(),1);assert.equal(await page.locator('.mp-timeline-block[data-state="PROPOSED"]').count(),1);
 assert.equal(await page.locator('.mp-timeline-block[data-state="RELEASED"]').count(),1);assert.ok(await page.locator('.mp-physical-stop').count()>=1);
 assert.equal(await page.locator('.planning-free-gap').count(),0);report.push('PASS proposed/confirmed/released/old holds/invalidated capacity and distinct physical strips, no false free gaps');
 assert.equal(await page.locator('[data-reservation="'+id(2002)+'"]').count(),1);report.push('PASS one machine/line block per reservation');
 await page.screenshot({path:join(out,'board-desktop.png'),fullPage:true});
 await load('gantt','en','&truncated=production_orders');await page.locator('[data-board-completeness="COMPLETE"]').waitFor();report.push('PASS capped historical production snapshot no longer limits operational occupancy');
 await load('gantt','en','&truncated=production_lines');await page.locator('[data-board-completeness="INCOMPLETE"]').waitFor();assert.equal(await page.locator('.planning-free-gap').count(),0);report.push('PASS incomplete resource context disables Gantt advice');
 scenario='unknown';await load();await page.locator('[data-board-completeness="INCOMPLETE"]').waitFor();assert.equal(await page.locator('.planning-free-gap').count(),0);report.push('PASS unknown occupancy cannot imply free capacity');
 scenario='wrong';await load();await page.locator('[data-board-completeness="ERROR"]').waitFor();assert.equal(await page.locator('.planning-free-gap').count(),0);report.push('PASS wrong-factory response rejected');
 scenario='denied';await load();await page.locator('[data-board-completeness="ERROR"]').waitFor();assert.equal(await page.locator('.mp-timeline-block').count(),0);report.push('PASS denied operational read discloses no maintenance records');
 scenario='visual';await load();await page.locator('[data-board-completeness="COMPLETE"]').waitFor();await page.getByRole('button',{name:'Edit authority: on'}).click();
 assert.equal(await page.locator('[draggable="true"]').count(),0);report.push('PASS view-only board with no draggable operations');
 await page.setViewportSize({width:390,height:844});await load('gantt','ar');await page.locator('[data-board-completeness="COMPLETE"]').waitFor();
 assert.equal(await page.locator('html').getAttribute('dir'),'rtl');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 assert.match(await page.locator('.planning-mobile-lines').innerText(),/التوقفات الفعلية المرتبطة|تجاوز/);await page.screenshot({path:join(out,'board-ar-mobile.png'),fullPage:true});report.push('PASS Arabic mobile/RTL reservation and stop information, no page overflow');
 assert.deepEqual(errors,[]);await writeFile(join(out,'results.json'),JSON.stringify({checks:report,pageErrors:errors},null,2));console.log(report.join('\n'));
}finally{release();await browser.close();}
