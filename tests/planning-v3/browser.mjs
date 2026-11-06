import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Planning-V3-location.txt'),'utf8').trim();
const c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(c.applicationPort,4222);assert.equal(c.databasePort,55496);
const base='http://127.0.0.1:4222',x=c.context;
const account=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts.find(a=>a.id===x.owner);
const en=JSON.parse(fs.readFileSync('src/locales/en.json','utf8'));
const browser=await chromium.launch({channel:'msedge',headless:true});
try {
 const context=await browser.newContext({viewport:{width:1440,height:1080}}),page=await context.newPage();
 await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());
 const errors=[],responses=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)responses.push({path:new URL(r.url()).pathname,status:r.status()});});
 await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});
 const snapshot=await page.evaluate(async()=>{const r=await fetch('/api/data');return {status:r.status,body:await r.json()};});assert.equal(snapshot.status,200);assert.equal(snapshot.body.factory.id,x.factory);assert.equal(snapshot.body.user.id,x.owner);
 await page.locator('#factory-navigation').getByRole('button',{name:en.planning,exact:true}).press('Enter');
 await page.locator('.planning-v3').waitFor();await page.locator('[data-board-completeness=COMPLETE]').waitFor({state:'attached',timeout:30000});
 await page.screenshot({path:path.join(root,'planning-desktop.png'),fullPage:true});
 fs.writeFileSync(path.join(root,'browser-initial.json'),JSON.stringify({identity:{id:x.owner,factory:x.factory},rows:await page.locator('.planning-work-table tbody tr').count(),errors,responses,text:await page.locator('.planning-v3').innerText()},null,2));
 await context.storageState({path:path.join(root,'browser-owner.json')});
 console.log(JSON.stringify({authenticated:true,rows:await page.locator('.planning-work-table tbody tr').count(),errors,responses}));
}finally{await browser.close();}
