import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Output-P4D-Preview-location.txt'),'utf8').trim(),c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.databasePort,55494);
const base='http://127.0.0.1:4220',account=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts.find(a=>a.role==='worker');
const browser=await chromium.launch({channel:'msedge',headless:true}),context=await browser.newContext(),page=await context.newPage(),results=[];
await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());
try{
 await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});
 for(const mode of ['quality','receiving','completion','order']){
  const r=await page.evaluate(async args=>{const r=await fetch('/api/manufactured-output?'+new URLSearchParams(args));return {status:r.status,body:await r.json()};},{factory:c.context.factory,mode,target:mode==='order'?c.context.item:c.context.output});results.push({mode,...r});assert.equal(r.status,403);assert.deepEqual(r.body,{error:'permissionError'});
 }
 fs.writeFileSync(path.join(root,'denials.json'),JSON.stringify({actualRestrictedLogin:true,results},null,2));console.log('PASS independent restricted local login: four exact destination HTTP 403 denials with no disclosed data');
}finally{await browser.close();}
