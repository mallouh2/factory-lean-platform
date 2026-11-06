// Opt-in read-only acceptance against the existing disposable loopback preview.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {verifyRuntime,verifyDatabase} from './production-recording-full-app/local-policy.mjs';
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Planning-V3-location.txt'),'utf8').trim();
const c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
verifyRuntime(c,fs.readFileSync(path.join(c.app,'.env.local'),'utf8'));
assert.equal(c.applicationPort,4222);assert.equal(c.databasePort,55496);
function sql(query) {
  const r=spawnSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p','55496','-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{input:query,encoding:'utf8',windowsHide:true});
  assert.equal(r.status,0,r.stderr);return r.stdout.trim();
}
verifyDatabase(c,JSON.parse(sql("select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))")));
const accounts=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts;
const foreign=sql(`select f.id from public.factories f where f.id<>'${c.context.factory}' and not exists(select 1 from public.memberships m where m.factory_id=f.id and m.user_id in('${c.context.owner}','${c.context.viewer}'))limit 1`);
assert.match(foreign,/^[0-9a-f-]{36}$/);
const digest=()=>sql("select md5(jsonb_build_array((select jsonb_agg(t order by id)from public.production_orders t),(select jsonb_agg(t order by id)from public.production_entries t),(select jsonb_agg(t order by id)from private.manufactured_output_events t),(select jsonb_agg(t order by id)from public.sales_orders t),(select jsonb_agg(t order by id)from public.sales_order_lines t),(select jsonb_agg(t order by user_id,module,action)from public.user_permissions t))::text)");
const before=digest(),out=path.join(root,'sidebar-v2'),base='http://127.0.0.1:4222';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const browser=await chromium.launch({channel:'msedge',headless:true}),e={checks:[],errors:[],responses:[],writes:[]};
let ctx,page;
async function login(id) {
  ctx=await browser.newContext({viewport:{width:1440,height:1000},colorScheme:'light'});page=await ctx.newPage();
  await ctx.route('**/*',route=>new URL(route.request().url()).origin===base?route.continue():route.abort());
  page.on('pageerror',error=>e.errors.push(error.message));
  page.on('response',response=>{const url=new URL(response.url());if(response.status()>=400&&url.pathname.startsWith('/api/'))e.responses.push({path:url.pathname,status:response.status()});});
  page.on('request',r=>{if(!['GET','HEAD'].includes(r.method()))e.writes.push({path:new URL(r.url()).pathname,method:r.method()});});
  const account=accounts.find(a=>a.id===id);assert.ok(account,'Existing credential required');
  await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);
  await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor();
  const snapshot=await page.evaluate(async()=>await(await fetch('/api/data')).json());assert.equal(snapshot.user.id,id);return snapshot;
}
async function expand() {await page.locator('#factory-navigation').hover();await page.waitForTimeout(250);}
async function nav(id) {
  if(await page.locator('.menu-button').isVisible()) {
    if(!await page.locator('#factory-navigation').evaluate(el=>el.classList.contains('is-open')))await page.locator('.menu-button').click();
  } else await expand();
  const button=page.locator(`[data-destination="${id}"]`);
  if(!await button.isVisible())await button.locator('xpath=ancestor::section[1]').locator('.nav-group-toggle').click();
  await button.click();await page.waitForTimeout(250);
}
async function read(url) {return page.evaluate(async url=>{const r=await fetch(url,{cache:'no-store'});return{status:r.status,body:await r.json()};},url);}
async function contrast() {
  const failures=await page.locator('.operational-navigation button').evaluateAll(buttons=>{
    const rgb=s=>(s.match(/[\d.]+/g)||[]).slice(0,3).map(Number);
    const lum=s=>rgb(s).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);
    const ratio=(a,b)=>{a=lum(a);b=lum(b);return(Math.max(a,b)+.05)/(Math.min(a,b)+.05);};
    return buttons.filter(b=>b.getClientRects().length&&!b.closest('[inert]')).flatMap(b=>{
      const style=getComputedStyle(b),bg=style.backgroundColor==='rgba(0, 0, 0, 0)'?getComputedStyle(b.closest('aside')).backgroundColor:style.backgroundColor;
      const r=ratio(style.color,bg),icon=b.querySelector('.sidebar-icon');
      const ir=icon?ratio(getComputedStyle(icon).color,bg):10;
      return r<4.5||ir<3?[{label:b.getAttribute('aria-label'),textRatio:r,iconRatio:ir}]:[];
    });
  });assert.deepEqual(failures,[]);
}
try {
  await login(c.context.owner);
  await expand();
  assert.equal(await page.locator('[data-group]').count(),4);
  for(const id of ['sales','planning','quality','maintenance','lean']) {
    assert.equal(await page.locator(`[data-destination="${id}"]`).count(),1);
    assert.equal(await page.locator(`[data-destination="${id}"]`).getAttribute('aria-expanded'),null);
    await nav(id);assert.equal(new URL(page.url()).searchParams.get('view'),id);
  }
  await page.getByRole('button',{name:'Downtime',exact:true}).click();
  assert.equal(new URL(page.url()).searchParams.get('view'),'downtime');
  await page.locator('.module-navigation-back').click();assert.equal(new URL(page.url()).searchParams.get('view'),'lean');
  e.checks.push('Sales/Planning/Quality/Maintenance/Lean direct; downtime contextual navigation');
  await nav('purchasing');await nav('suppliers');assert.equal(new URL(page.url()).searchParams.get('view'),'suppliers');
  assert.equal(await page.locator('[data-group="purchasing"] [data-destination="suppliers"]').count(),1);
  await nav('myPurchaseRequests');await nav('settings');await nav('employees');await nav('roles');await nav('audit');
  e.checks.push('Purchasing primary/secondary and existing Administration destinations');
  assert.equal(await page.locator('#factory-navigation [data-destination="lines"]').count(),0);
  await nav('floor');await page.getByRole('button',{name:'Manage Lines & Machines',exact:true}).click();
  await page.locator('.line-management').waitFor();await page.getByRole('button',{name:'Back to Factory Floor',exact:true}).click();await page.locator('.ff2').waitFor();
  await nav('orders');await nav('productionHistory');await page.getByRole('button',{name:'Back',exact:true}).click();
  await page.getByRole('heading',{level:1,name:'Production orders',exact:true}).waitFor();await nav('products');
  e.checks.push('contextual authorized Lines & Machines; Production Orders/History Back/Products');
  await nav('warehouseRequests');assert.equal(await page.getByRole('tab',{name:'Warehouse Requests',exact:true}).getAttribute('aria-selected'),'true');
  await nav('warehouse');assert.equal(await page.getByRole('tab',{name:'Inventory',exact:true}).getAttribute('aria-selected'),'true');
  await page.goBack();assert.equal(await page.getByRole('tab',{name:'Warehouse Requests',exact:true}).getAttribute('aria-selected'),'true');
  await nav('sales');await nav('quality');await page.goBack();await page.getByRole('heading',{level:1,name:'Sales Orders',exact:true}).waitFor();
  e.checks.push('Warehouse distinct panels and browser Back including departments');
  await nav('floor');await expand();
  const expandedGroups=await page.locator('.nav-group[data-open="true"]:not([data-group="production"])').evaluateAll(groups=>groups.map(group=>group.dataset.group));
  for(const id of expandedGroups)await page.locator(`[data-group="${id}"] .nav-group-toggle`).click();
  await page.waitForTimeout(250);await contrast();await page.screenshot({path:path.join(out,'desktop-en.png')});
  const icons=await page.locator('[data-destination]').evaluateAll(buttons=>Object.fromEntries(buttons.map(button=>[button.dataset.destination,[...button.querySelectorAll('svg path')].map(p=>p.getAttribute('d')).join('|')])));
  const majors=['sales','warehouse','purchasing','floor','orders','productionHistory','products','planning','quality','maintenance','lean'];
  assert.equal(new Set(majors.map(key=>icons[key])).size,majors.length);e.checks.push('distinct major destination SVG shapes');
  await page.locator('.sidebar-toggle').click();await page.waitForTimeout(250);assert.ok(!await page.locator('#factory-navigation').evaluate(el=>el.classList.contains('is-expanded')));
  await page.mouse.move(1200,50);await page.locator('#factory-navigation').hover();await page.waitForTimeout(250);assert.ok(await page.locator('#factory-navigation').evaluate(el=>el.classList.contains('is-expanded')));
  await page.emulateMedia({colorScheme:'dark'});await page.waitForTimeout(250);await contrast();await page.screenshot({path:path.join(out,'desktop-dark.png')});
  e.checks.push('desktop collapse/hover expansion; light/dark text4.5:1 and icon3:1 contrast');await page.emulateMedia({colorScheme:'light'});await page.waitForTimeout(250);
  for(const lang of ['en','ar']) {
    await page.setViewportSize({width:390,height:844});
    if(lang==='ar')await page.getByRole('button',{name:'العربية',exact:true}).first().click();
    await page.locator('.menu-button').click();await page.waitForTimeout(250);
    const box=await page.locator('#factory-navigation').boundingBox();assert.ok(box.x>=0&&box.x+box.width<=390);
    assert.equal(await page.evaluate(()=>document.body.style.overflow),'hidden');
    await page.locator('.sidebar-close').press('Shift+Tab');assert.ok(await page.locator('.sidebar-footer button').evaluate(el=>el===document.activeElement));
    await page.locator('.sidebar-footer button').press('Tab');assert.ok(await page.locator('.sidebar-close').evaluate(el=>el===document.activeElement));
    await page.screenshot({path:path.join(out,`mobile-${lang}.png`)});
    await page.locator('.sidebar-close').press('Escape');await page.waitForTimeout(250);
    assert.equal(await page.locator('#factory-navigation').getAttribute('aria-modal'),null);
    assert.ok(await page.locator('.menu-button').evaluate(el=>el===document.activeElement));
    await nav('sales');assert.ok(!await page.locator('#factory-navigation').evaluate(el=>el.classList.contains('is-open')));
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  }
  await page.locator('.menu-button').click();await page.emulateMedia({reducedMotion:'reduce'});
  assert.equal(await page.locator('#factory-navigation').evaluate(el=>getComputedStyle(el).transitionDuration),'0s');
  assert.equal(await page.locator('.nav-chevron').first().evaluate(el=>getComputedStyle(el).transitionDuration),'0s');
  e.checks.push('EN/AR390 RTL drawer, focus trap/restore, Escape, close after navigation, no overflow, reduced motion');
  const foreignSnapshot=await read('/api/data?factory='+foreign);assert.equal(foreignSnapshot.status,200);assert.equal(foreignSnapshot.body.factory.id,c.context.factory);
  const deniedForeign=await read('/api/manufactured-output?factory='+foreign+'&mode=quality');assert.equal(deniedForeign.status,403);assert.ok(!deniedForeign.body.rows);e.responses.push({check:'owner foreign factory protected reader',status:deniedForeign.status},{check:'snapshot retains authorized factory',status:foreignSnapshot.status});
  await ctx.close();await login(c.context.viewer);await expand();
  assert.equal(await page.locator('[data-destination="quality"]').count(),0);assert.equal(await page.locator('[data-group="administration"]').count(),0);
  assert.equal(await page.getByRole('button',{name:'Manage Lines & Machines',exact:true}).count(),0);
  await nav('floor');await page.screenshot({path:path.join(out,'restricted-en.png')});
  const denied=await read('/api/manufactured-output?factory='+c.context.factory+'&mode=quality');assert.equal(denied.status,403);assert.ok(!denied.body.rows);e.responses.push({check:'restricted Quality',status:denied.status});
  const foreignDenied=await read('/api/manufactured-output?factory='+foreign+'&mode=quality');assert.equal(foreignDenied.status,403);assert.ok(!foreignDenied.body.rows);e.responses.push({check:'restricted foreign factory protected reader',status:foreignDenied.status});
  await page.goto(base+'/?view=settings');await page.locator('.app-shell').waitFor();assert.equal(await page.locator('[data-destination="settings"]').count(),0);
  assert.equal(digest(),before);assert.ok(e.writes.every(request=>request.path==='/api/auth'));
  assert.deepEqual(e.errors,[]);e.checks.push('restricted navigation/configuration hidden; real server403 and cross-factory403; operational/permission digest unchanged');e.status='PASS';
} catch(error) {
  e.status='FAIL';e.failure=error.message;if(page&&!page.isClosed()){await page.screenshot({path:path.join(out,'failure.png')});fs.writeFileSync(path.join(out,'failure.txt'),await page.locator('body').innerText());}throw error;
} finally {fs.writeFileSync(path.join(out,'browser.json'),JSON.stringify(e,null,2));await browser.close();console.log(JSON.stringify(e));}
