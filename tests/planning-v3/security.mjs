import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {spawnSync} from 'node:child_process';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require('C:/Users/Temp/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Planning-V3-location.txt'),'utf8').trim(),c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,'')),x=c.context;
assert.equal(c.databasePort,55496);assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');
function sql(input){const r=spawnSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p','55496','-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{input,encoding:'utf8',windowsHide:true});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
assert.equal(sql("select inet_server_addr()='127.0.0.1'::inet and inet_server_port()=55496 and current_database()='factory_lean_quality_local'"),'t');
const foreign=JSON.parse(sql('select x from late_test.context limit 1'));
const state=()=>sql(`select md5(coalesce((select jsonb_agg(t order by id)::text from public.production_orders t),'')||coalesce((select jsonb_agg(t order by id)::text from public.production_plan_revisions t),''))`);
const before=state(),accounts=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'),'utf8')).accounts,browser=await chromium.launch({channel:'msedge',headless:true}),evidence=[];
try{
 for(const role of ['viewer','owner']){
  const account=accounts.find(a=>a.id===x[role]),context=await browser.newContext(),page=await context.newPage();await context.route('**/*',r=>new URL(r.request().url()).origin==='http://127.0.0.1:4222'?r.continue():r.abort());
  await page.goto('http://127.0.0.1:4222');await page.locator('input[name=email]').fill(account.email);await page.locator('input[name=password]').fill(account.password);await page.locator('form button.primary').click();await page.locator('.app-shell').waitFor();
  const result=await page.evaluate(async({factory,item,line})=>{const identity=await(await fetch('/api/data')).json();const r=await fetch('/api/data',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:'plan_product_item',args:{factory,item,target_line:line,planned_start:new Date(Date.now()+86400000).toISOString()}})});return {user:identity.user.id,http:r.status,body:await r.json()};},role==='viewer'?{factory:x.factory,item:x.recovery,line:x.line}:{factory:foreign.factory,item:foreign.item,line:foreign.line});
  assert.equal(result.user,x[role]);assert.equal(result.http,400,JSON.stringify(result));assert.equal(result.body.error,'permissionError');
  const headers={apikey:'local-preview-public-not-a-hosted-key','Content-Type':'application/json'};
  const auth=await fetch('http://127.0.0.1:4304/auth/v1/token?grant_type=password',{method:'POST',headers,body:JSON.stringify({email:account.email,password:account.password})});assert.equal(auth.status,200);const session=await auth.json();
  const denied=await fetch('http://127.0.0.1:4304/rest/v1/rpc/plan_product_item',{method:'POST',headers:{...headers,Authorization:'Bearer '+session.access_token},body:JSON.stringify({factory:role==='viewer'?x.factory:foreign.factory,item:role==='viewer'?x.recovery:foreign.item,target_line:role==='viewer'?x.line:foreign.line,planned_start:new Date(Date.now()+86400000).toISOString()})});const sqlBody=await denied.json();assert.equal(denied.status,403,JSON.stringify(sqlBody));assert.equal(sqlBody.code,'42501');
  evidence.push({sqlHttp:denied.status,sqlBody,role,check:role==='viewer'?'No effective Orders edit':'Known other local factory',...result});await context.close();
 }
 assert.equal(state(),before,'Rejected API writes must not change any production item or revision');
 const gates=JSON.parse(sql(`do $$begin perform set_config('request.jwt.claim.sub','${x.owner}',false);end$$;select jsonb_build_object('manufactured_public',public.manufactured_output_capability('${x.factory}'),'late_enabled',(select coalesce(bool_or(enabled or schema_contract_version<>0),false) from private.production_recording_v3_activation))`));assert.equal(gates.manufactured_public.available,false);assert.equal(gates.late_enabled,false);
 fs.writeFileSync(path.join(root,'security.json'),JSON.stringify({evidence,unchanged:true,gates},null,2));console.log('Two real separate-login denials; all Production/Planning state unchanged; shipped gates FALSE');
}finally{await browser.close();}
