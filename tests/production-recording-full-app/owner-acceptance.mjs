// Controlled local fixture acceptance. Persist each result; never blindly replay writes.
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';import {randomUUID} from 'node:crypto';import {createRequire} from 'node:module';
import {verifyRuntime,verifyDatabase,databaseGuard,initializeOwners,quote} from './local-policy.mjs';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Planning-V3-location.txt'),'utf8').trim(),c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,'')),x=c.context;
verifyRuntime(c,fs.readFileSync(path.join(c.app,'.env.local'),'utf8'));
const dir=path.join(root,'owner-permissions-fix'),file=path.join(dir,'acceptance.json');fs.mkdirSync(dir,{recursive:true});
const evidence=fs.existsSync(file)?JSON.parse(fs.readFileSync(file)):{steps:[],requests:[],errors:[]},persist=()=>fs.writeFileSync(file,JSON.stringify(evidence,null,2));
function sql(query){const r=spawnSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(c.databasePort),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{input:query,encoding:'utf8',windowsHide:true});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
function checkTarget(){verifyDatabase(c,JSON.parse(sql("select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))")));}checkTarget();
const scalar=query=>JSON.parse(sql(query)||'null');
const before=()=>scalar(`select jsonb_build_object('users',(select count(*) from auth.users),'grants',(select count(*) from public.user_permissions where factory_id='${x.factory}' and user_id='${x.owner}'),'packages',(select count(*) from public.member_permission_packages where factory_id='${x.factory}' and user_id='${x.owner}'),'effective',(select count(*) from private.effective_person_permissions('${x.factory}','${x.owner}')),'defined',(select count(*) from public.permissions))`);
if(!evidence.initial){evidence.initial=before();persist();}
async function step(name,fn){const found=evidence.steps.find(s=>s.name===name);if(found)return found.result;const result=await fn();evidence.steps.push({name,result});persist();return result;}
const accounts=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts,browser=await chromium.launch({channel:'msedge',headless:true}),base='http://127.0.0.1:'+c.applicationPort;
const en=JSON.parse(fs.readFileSync('src/locales/en.json','utf8'));
let debugPage;
try{
 const context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),runErrors=[];await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());page.on('pageerror',e=>{runErrors.push(e.message);evidence.errors.push(e.stack);persist();});
 debugPage=page;const account=accounts.find(a=>a.id===x.owner);assert.ok(account);await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor();
 const get=url=>page.evaluate(async url=>{const r=await fetch(url);return {http:r.status,body:await r.json()};},url);
 const snapshot=async()=>{const r=await get('/api/data');assert.equal(r.http,200,JSON.stringify(r));return r.body;};
 let snap=await snapshot();assert.equal(snap.user.id,x.owner);assert.equal(snap.factory.id,x.factory);assert.equal(snap.permissions.length,evidence.initial.defined);evidence.identity={email:account.email,id:snap.user.id,factory:snap.factory.id};persist();
 async function post(command,args,endpoint='/api/data'){
  checkTarget();const row={command,args,endpoint,phase:'SUBMITTING'};evidence.requests.push(row);persist();
  const r=await page.evaluate(async({command,args,endpoint})=>{const r=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command,args})});return {http:r.status,body:await r.json()};},{command,args,endpoint});Object.assign(row,r,{phase:r.http===200?'COMMITTED':'REJECTED'});persist();assert.equal(r.http,200,JSON.stringify(r));return r.body.data;
 }
 const named=async(key,command,args,endpoint)=>{const old=evidence.requests.find(r=>r.key===key&&r.phase==='COMMITTED');if(old)return old.body.data;const result=await post(command,args,endpoint);evidence.requests.at(-1).key=key;persist();return result;};
 const sales=await step('Owner creates and confirms a real Sales order',async()=>{
  const id=await named('sales-create','create_sales_order',{factory:x.factory,payload:{customer_reference:'Local owner permission acceptance',requested_delivery:new Date(Date.now()+7*86400000).toISOString(),lines:[{product_id:x.product,quantity:1,unit:'meter'}]},request_id:randomUUID()});
  await named('sales-approve','approve_sales_order',{factory:x.factory,sales_order:id,request_id:randomUUID()});return {id,line:sql(`select id from public.sales_order_lines where factory_id='${x.factory}' and order_id='${id}'`)};
 });
 const internal=await step('Owner creates an eligible internal Production Request',async()=>{
  const id=await named('internal-create','create_production_request',{factory:x.factory,request_name:'Local owner permissions — internal',request_priority:'normal',request_required_by:new Date(Date.now()+8*86400000).toISOString(),request_notes:'Controlled local fixture',request_items:[{product_id:x.product,quantity:2,unit:'meter'}]});return {request:id,item:sql(`select id from public.production_orders where factory_id='${x.factory}' and request_id='${id}'`)};
 });
 await step('Planning V3 browser form schedules the new internal job',async()=>{
  // API-driven fixture creation does not run FactoryApp.command's snapshot reload.
  await page.reload();await page.locator('.app-shell').waitFor();
  await page.locator('#factory-navigation').getByRole('button',{name:en.planning,exact:true}).press('Enter');await page.locator('.planning-filters select').first().focus();await page.mouse.move(1400,80);
  await page.locator('.planning-requests-waiting tr[data-item-id="'+internal.item+'"]').getByRole('button').click();const d=page.locator('.planning-drawer');await d.locator('.planning-field select').selectOption(x.line);
  const time=new Date(Date.now()+6*86400000);time.setUTCHours(8,0,0,0);await d.locator('input[type=datetime-local]').fill(time.toISOString().slice(0,16));checkTarget();
  const wait=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/api/data')&&r.request().postDataJSON()?.command==='plan_product_item');await d.getByRole('button',{name:en.planningSaveSchedule,exact:true}).click();const r=await wait,body=await r.json();assert.equal(r.status(),200,JSON.stringify(body));await d.waitFor({state:'detached'});return scalar(`select jsonb_build_object('item',id,'line',line_id,'start',start_time,'finish',expected_finish) from public.production_orders where id='${internal.item}'`);
 });
 await step('Owner replans permitted work with recorded reason',async()=>{
  const time=new Date(Date.now()+6*86400000);time.setUTCHours(10,0,0,0);await named('internal-replan','revise_product_plan',{factory:x.factory,item:internal.item,target_line:x.line,planned_start:time.toISOString(),reason_code:'material_delay',reason_note:'Explicit local test reschedule'});
  const r=scalar(`select jsonb_agg(jsonb_build_object('event',event,'reason',reason_code) order by revision_no) from public.production_plan_revisions where factory_id='${x.factory}' and item_id='${internal.item}'`);assert.ok(r.some(v=>v.reason==='material_delay'));return r;
 });
 await step('Planning V3 real drag persists through the shared adapter',async()=>{
  const request=await named('drag-request','create_production_request',{factory:x.factory,request_name:'Owner permissions — drag fixture',request_priority:'normal',request_required_by:null,request_notes:'Local drag acceptance only',request_items:[{product_id:x.product,quantity:1,unit:'meter'}]});
  const item=sql(`select id from public.production_orders where request_id='${request}' and factory_id='${x.factory}'`);
  await page.reload();await page.locator('.app-shell').waitFor();await page.locator('#factory-navigation').getByRole('button',{name:en.planning,exact:true}).press('Enter');await page.locator('.planning-filters select').first().focus();await page.mouse.move(1400,80);
  const range=page.locator('.planning-support').filter({has:page.locator('.planning-board-toolbar')});await range.locator('summary').click();const date=new Date(Date.now()+6*86400000).toISOString().slice(0,10);await range.locator('input[type=datetime-local]').fill(date+'T00:00');await range.locator('summary').click();
  const source=page.locator('.planning-requests-waiting tr[data-item-id="'+item+'"]').getByRole('button');await page.waitForFunction(id=>document.querySelector('tr[data-item-id="'+id+'"] button')?.getAttribute('draggable')==='true',item);
  // Printing has legitimately active work. Use the other existing capable line;
  // full permissions must not override occupied-capacity placement protection.
  const lane=page.locator('.planning-lane').filter({has:page.locator('.planning-line-name').getByText('Extrusion line',{exact:true})}).locator('.planning-lane-track'),bounds=await lane.boundingBox();assert.ok(bounds);checkTarget();
  // Dispatch actual browser DataTransfer events, avoiding native pointer scroll
  // instability across the tall queue/chart. No client data or eligibility override.
  const transfer=await page.evaluateHandle(()=>new DataTransfer());await source.dispatchEvent('dragstart',{dataTransfer:transfer});
  await lane.dispatchEvent('dragover',{dataTransfer:transfer,clientX:bounds.x+bounds.width*.6,clientY:bounds.y+35});
  const wait=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/api/data')&&r.request().postDataJSON()?.command==='plan_product_item');await lane.dispatchEvent('drop',{dataTransfer:transfer,clientX:bounds.x+bounds.width*.6,clientY:bounds.y+35});const response=await wait;assert.equal(response.status(),200,JSON.stringify(await response.json()));
  await page.locator('.planning-requests-waiting tr[data-item-id="'+item+'"]').waitFor({state:'detached'});return scalar(`select jsonb_build_object('item',id,'line',line_id,'start',start_time)from public.production_orders where id='${item}'`);
 });
 const recording=await step('Owner records actual permitted Good through the protected V3 writer',async()=>{
  const work=scalar(`do $$begin perform set_config('request.jwt.claim.sub','${x.owner}',false);end$$;select public.production_shift_work('${x.factory}',null,100)`),row=work.rows.find(r=>r.item_id===x.form);assert.ok(row,'Existing active item must be eligible in current shift');
  const technician=sql(`select id from public.memberships where factory_id='${x.factory}' and user_id='${x.owner}'`),payload={unit_kind:'line',production_unit:x.line,item:x.form,technician,good:2,unfinished:0,discarded_quantity:0,scrap_kg:0,remaining_work:'',confirm_overproduction:false,recording_context:{version:3,execution_key:row.execution_key,occurrence_key:work.occurrence.occurrence_key,context_hash:row.context_hash,current_shift_quantity_confirmed:true},output_groups:[{id:randomUUID(),quantity:'2',missing_operations:[]}]};
  const r=await named('good-record','record_manufactured_output',{factory:x.factory,payload,request_id:randomUUID()},'/api/manufactured-output');return scalar(`select jsonb_build_object('entry',entry_id,'output',id,'groups',recorded_groups) from private.manufactured_outputs where entry_id='${r.entry_id}'`);
 });
 await step('Owner performs valid Quality inspection and physical Warehouse receipt',async()=>{
  await named('quality','manufactured_output_command',{factory:x.factory,target:recording.output,operation:'QUALITY',payload:{groups:recording.groups.map(g=>({...g,released:g.quantity})),rejected:'0',reason:'Physically inspected two-meter local owner test bundle'},expected_revision:1,request_id:randomUUID()},'/api/manufactured-output');
  await named('receive','receive_manufactured_output',{factory:x.factory,target:recording.output,payload:{group_id:recording.groups[0].id,quantity:'2',location:'Owner test separately labelled finished bundle',physical_confirmation:true},expected_revision:2,request_id:randomUUID()},'/api/manufactured-output');return {output:recording.output,quantity:'2'};
 });
 await step('Owner identifies physical source and reserves one eligible Sales meter',async()=>{
  const source=sql(`select id from public.finished_goods_sources where factory_id='${x.factory}' and entry_id='${recording.entry}'`);assert.match(source,/^[a-f0-9-]{36}$/);
  await named('identify','source_stock_command',{factory:x.factory,operation:'identify',payload:{source,quantity:'2',label:'Owner acceptance — physically separate 2m bundle',physically_identified:true},allocations:[],request_id:randomUUID()});
  await named('reserve','source_stock_command',{factory:x.factory,operation:'reserve',payload:{sales_line_id:sales.line},allocations:[{source_id:source,quantity:'1'}],request_id:randomUUID()});return {source,reserved:'1',sales:sales.id};
 });
 await step('Owner opens protected administration and saves a valid existing setting',async()=>{
  const packages=await get('/api/permission-packages?factory='+x.factory);assert.equal(packages.http,200,JSON.stringify(packages));
  snap=await snapshot();await named('settings-save','update_settings',{factory:x.factory,name:snap.factory.name,timezone:snap.factory.timezone,logo:snap.factory.logo_url||null});return {packagesHttp:packages.http,settingsSaved:true};
 });
 await context.storageState({path:path.join(dir,'owner-session.json')});evidence.lastRunErrors=runErrors;assert.deepEqual(runErrors,[]);evidence.currentPermissions=before();evidence.status='PASS';if(evidence.failure){evidence.previousFailures??=[];evidence.previousFailures.push(evidence.failure);delete evidence.failure;}persist();console.log(JSON.stringify({owner:account.email,steps:evidence.steps.length,permissions:evidence.currentPermissions,currentErrors:runErrors}));
}catch(error){evidence.failure=error.message;persist();if(debugPage){await debugPage.screenshot({path:path.join(dir,'failure.png'),fullPage:true});fs.writeFileSync(path.join(dir,'failure-text.txt'),await debugPage.locator('body').innerText());}throw error;}finally{await browser.close();}
