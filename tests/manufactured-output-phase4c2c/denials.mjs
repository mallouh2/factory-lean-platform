import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';import {createRequire} from 'node:module';import {execFileSync} from 'node:child_process';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Output-P4C2C-Preview-location.txt'),'utf8').trim(),c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.databasePort,55493);
const base='http://127.0.0.1:4219',account=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts.find(a=>a.role==='worker');
const sql=q=>execFileSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p','55493','-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1','-c',q],{encoding:'utf8',windowsHide:true}).trim();
const state=()=>sql("select jsonb_build_object('events',(select md5(coalesce(string_agg(to_jsonb(e)::text,'' order by id),'')) from private.manufactured_output_events e),'lots',(select md5(coalesce(string_agg(to_jsonb(l)::text,'' order by id),'')) from public.unfinished_lots l),'balances',(select md5(coalesce(string_agg(to_jsonb(b)::text,'' order by product_id),'')) from public.finished_goods_balances b),'work',(select md5(coalesce(string_agg(to_jsonb(w)::text,'' order by item_id),'')) from private.manufactured_completion_work w))");
const before=state(),browser=await chromium.launch({channel:'msedge',headless:true}),context=await browser.newContext(),page=await context.newPage(),results=[];
await context.route('**/*',r=>new URL(r.request().url()).origin===base?r.continue():r.abort());
try{
 await page.goto(base);await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor({timeout:60000});
 const common={factory:c.context.factory,target:c.context.output,expected_revision:1};
 for(const body of [
  {command:'manufactured_output_command',args:{...common,operation:'QUALITY',payload:{groups:[],rejected:'0',reason:'Unauthorized finding attempt'}}},
  {command:'reconcile_manufactured_output',args:{...common,finding:c.context.output,payload:{reason:'Unauthorized physical adjustment'}}},
  {command:'plan_manufactured_completion',args:{...common,payload:{quantity:'1',group_id:c.context.group,choice:'COMPLETE',operations:[],reason:'Unauthorized allocation attempt'}}}
 ]){
  body.args.request_id=crypto.randomUUID();const r=await page.evaluate(async body=>{const r=await fetch('/api/manufactured-output',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};},body);results.push({command:body.command,...r});assert.equal(r.status,403);assert.equal(r.body.error,'permissionError');
 }
 assert.equal(state(),before);fs.writeFileSync(path.join(root,'denials.json'),JSON.stringify({results,operationalStateUnchanged:true},null,2));console.log('PASS three authenticated HTTP 403 denials; events, lots, balances and work unchanged');
}finally{await browser.close();}
