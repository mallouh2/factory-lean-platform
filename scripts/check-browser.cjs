// Run from the repository root against the isolated fictional testing factory.
const fs=require('fs'),{spawn}=require('child_process');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright');
fs.mkdirSync('test-results',{recursive:true});
const browserArgs=JSON.parse(process.env.CHROMIUM_ARGS || '[]');
const server=spawn(process.execPath,['node_modules/next/dist/bin/next','dev','--port','3100','--hostname','127.0.0.1'],{env:{...process.env,...require('node:util').parseEnv(fs.readFileSync('.env.testing','utf8')),BUILD_DIRECTORY:'.next-check',APP_ORIGIN:'http://localhost:3100'},stdio:['ignore','pipe','pipe']});server.stderr.on('data',d=>process.stderr.write(d));
let browser; const checks=[],errors=[];
(async()=>{try{
for(let i=0;i<80;i++){try{await fetch('http://localhost:3100');break}catch{}await new Promise(r=>setTimeout(r,250))}
browser=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE_PATH || undefined,args:browserArgs.filter(x=>x!=='--disable-web-security'),headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage();
page.on('pageerror',e=>errors.push(e.message));await page.goto('http://localhost:3100');await page.getByRole('button',{name:'Sign in',exact:true}).waitFor({timeout:60000});checks.push('Authentication form renders');
const credentials=JSON.parse(fs.readFileSync('.env.testing-users.json'));const user=credentials.owner;
await page.locator('input[name=email]').fill(user.email);await page.locator('input[name=password]').fill(user.password);await page.getByRole('button',{name:'Sign in',exact:true}).click();
await page.locator('.machine-card').first().waitFor({timeout:120000});checks.push('Test owner signs in through Supabase; floor renders');
checks.push(...await require('../tests/feature-flows.cjs')(page.request,browser,credentials,'http://localhost:3100'));await page.reload();await page.locator('.machine-card').first().waitFor({timeout:60000});
console.log('Machine cards',await page.locator('.machine-card').count());await page.screenshot({path:'test-results/dashboard-en.png',fullPage:true});
await page.locator('.machine-card').first().click();await page.locator('dialog').waitFor();checks.push('Work center detail dialog opens');await page.getByRole('button',{name:'Close',exact:true}).click();
const en=JSON.parse(fs.readFileSync('src/locales/en.json'));
for(const key of ['factory','lines','centers','orders','products','downtime','reports','employees','roles','settings','support','audit']){await page.locator('.sidebar nav').getByRole('button',{name:en[key],exact:key!=='downtime'}).click();await page.locator('main').waitFor();checks.push(key+' screen opens');}
await page.locator('.sidebar nav').getByRole('button',{name:en.reports,exact:true}).click();
for(const key of ['downtime','utilization','productionStatus','operatorActivity','lineReport','dailySummary']){await page.locator('.report-tabs').getByRole('button',{name:en[key],exact:true}).click();checks.push(key+' report opens')}
await page.screenshot({path:'test-results/reports-en.png',fullPage:true});
await page.locator('.sidebar nav').getByRole('button',{name:en.dashboard,exact:true}).click();
await page.locator('.machine-card').filter({hasText:'M-04'}).click();
const initial=await page.locator('dialog > .badge').innerText();await page.locator('.operator-actions button').filter({hasText:initial.includes(en.running)?en.idle:en.running}).click();await page.getByRole('button',{name:en.changeStatus,exact:true}).click();await page.locator('dialog').waitFor({state:'detached',timeout:120000});checks.push('Operator action persists and closes dialog');
await page.locator('.machine-card').filter({hasText:'M-04'}).click();
await page.locator('input[name=produced]').fill('5');await page.locator('input[name=rejected]').fill('1');await page.getByRole('button',{name:en.recordOutput,exact:true}).click();await page.locator('dialog').waitFor({state:'detached',timeout:120000});checks.push('Production output records through ledger');
await page.getByRole('button',{name:'العربية',exact:true}).click();if(await page.locator('html').getAttribute('dir')!=='rtl')throw new Error('RTL direction missing');
await page.locator('.sidebar nav button').first().click();await page.screenshot({path:'test-results/dashboard-ar.png',fullPage:true});checks.push('Arabic RTL dashboard renders');
await page.setViewportSize({width:390,height:844});await page.screenshot({path:'test-results/dashboard-mobile-ar.png',fullPage:true});
const overflows=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);if(overflows)throw new Error('Mobile viewport overflows');checks.push('390px Arabic layout has no page overflow');
await page.locator('.menu-button').click();await page.locator('.sidebar-close').click();checks.push('Mobile navigation opens and closes');
console.log(JSON.stringify({checks,errors},null,2));fs.writeFileSync('test-results/browser-results.json',JSON.stringify({checks,errors},null,2));
}catch(e){console.error(String(e.message||e).split('\n')[0]);if(browser){const pages=browser.contexts().flatMap(c=>c.pages());if(pages.length)await pages[pages.length-1].screenshot({path:'test-results/browser-error.png',fullPage:true}).catch(()=>{})}process.exitCode=1}finally{if(browser)await browser.close();server.kill('SIGTERM')}})();
