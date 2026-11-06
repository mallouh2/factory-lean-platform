// Actual handlers/client/SQL with fixture Auth/transport, not hosted acceptance.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {AsyncLocalStorage} from 'node:async_hooks';
import {createRequire} from 'node:module';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {build} from 'esbuild';
import {createClient} from '@supabase/supabase-js';
import {NextRequest} from 'next/server.js';
const [bin,port,out]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
async function sql(text){return new Promise((done,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let data='',error='';p.stdout.on('data',v=>data+=v);p.stderr.on('data',v=>error+=v);p.on('error',reject);p.on('close',code=>{try{assert.equal(code,0,error);done(data.trim());}catch(e){reject(e);}});p.stdin.end(text);});}
assert.equal(await sql("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const x=JSON.parse(await sql('select x from m3c_test.context;')),f=x.factory;
await sql(`create function m3c_test.transport(op text,args jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$declare result jsonb;msg text;code text;begin
 if op='can_access' then result:=to_jsonb(public.can_access((args->>'factory')::uuid,args->>'module',args->>'action'));
 elsif op='lean_read' then result:=public.lean_read((args->>'factory')::uuid,args->'query');
 elsif op='quality_read' then result:=public.quality_read((args->>'factory')::uuid,args->'query');
 elsif op='production_history' then result:=public.production_history((args->>'factory')::uuid,args->'filters');
 elsif op='lean_command' then result:=public.lean_command((args->>'factory')::uuid,(args->>'request_id')::uuid,args->>'operation',args->'payload');
 else raise exception 'Unexpected local transport';end if;return jsonb_build_object('body',result::text,'error',null);
 exception when others then get stacked diagnostics msg=MESSAGE_TEXT,code=RETURNED_SQLSTATE;return jsonb_build_object('body',null,'error',jsonb_build_object('message',msg,'code',code));end$$;
 revoke all on function m3c_test.transport(text,jsonb) from public;grant usage on schema m3c_test to authenticated;grant execute on function m3c_test.transport(text,jsonb) to authenticated;
 insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(f)},${quote(x.worker)},'quality','view');`);
const newEntry=await sql(`begin;do $$begin perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);end$$;select public.record_lean_production(${quote(f)},late_test.payload(${quote(JSON.stringify(x))},1)||'{"scrap_kg":0.25}',gen_random_uuid())->>'id';commit;`);
const foreign=await sql(`select id from public.factories where id<>${quote(f)} order by id limit 1;`);
const sessions=new Map(),owner=randomUUID(),worker=randomUUID(),viewer=randomUUID(),storage=new AsyncLocalStorage(),originalFetch=globalThis.fetch;
sessions.set(owner,{id:x.owner,email_confirmed_at:'2026-01-01T00:00:00Z'});sessions.set(worker,{id:x.worker,email_confirmed_at:'2026-01-01T00:00:00Z'});sessions.set(viewer,{id:x.viewer,email_confirmed_at:'2026-01-01T00:00:00Z'});
let rpcCalls=0;const rpcNames=[];
globalThis.fetch=async(input,init)=>{
 const url=new URL(String(input)),actor=storage.getStore();
 if(url.pathname==='/auth/v1/user')return new Response(JSON.stringify(actor??{}),{status:actor?200:401,headers:{'Content-Type':'application/json'}});
 if(!url.pathname.startsWith('/rest/v1/rpc/'))throw Error('Unexpected network target: '+url.origin+url.pathname);
 const op=url.pathname.split('/').at(-1),args=init.method==='GET'?Object.fromEntries(url.searchParams):JSON.parse(init.body);
 for(const key of ['query','filters'])if(typeof args[key]==='string')args[key]=JSON.parse(args[key]);
 assert.ok(actor);rpcCalls++;rpcNames.push(op);
 const result=JSON.parse(await sql(`begin ${op==='lean_command'?'':'read only'};do $$begin perform set_config('request.jwt.claim.sub',${quote(actor.id)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;set local role authenticated;
 select m3c_test.transport(${quote(op)},${quote(JSON.stringify(args))});commit;`));
 return new Response(result.error?JSON.stringify(result.error):result.body,{status:result.error?(result.error.code==='42501'?403:400):200,headers:{'Content-Type':'application/json'}});
};
globalThis.__m3cDb=async(fetcher)=>{const actor=storage.getStore(),db=createClient('http://127.0.0.1:1','local-fixture-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:fetcher??globalThis.fetch}});db.auth.getUser=async()=>({data:{user:actor??null},error:null});return db;};
async function compiled(path){const result=await build({entryPoints:[path],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'session-only',setup(b){b.onResolve({filter:/^\.\/supabase$/},a=>a.importer.endsWith('authorization.ts')?{path:'session',namespace:'fixture'}:undefined);b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const supabaseServer=globalThis.__m3cDb;'}));}}]});const m={exports:{}};new Function('require','module','exports',result.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);return m.exports;}
const routes={'/api/lean':await compiled('src/app/api/lean/route.ts'),'/api/quality':await compiled('src/app/api/quality/route.ts'),'/api/production-reporting':await compiled('src/app/api/production-reporting/route.ts'),'/api/data':await compiled('src/app/api/data/route.ts')};
let edge;globalThis.Deno={env:{get:k=>k==='SUPABASE_URL'?'http://127.0.0.1:1':'local-fixture-only'},serve:handler=>{edge=handler;}};
await compiled('supabase/functions/lean-comparison/index.ts');assert.equal(typeof edge,'function');
const server=createServer(async(req,res)=>{try{const chunks=[];for await(const chunk of req)chunks.push(chunk);const request=new NextRequest(`http://127.0.0.1:${server.address().port}${req.url}`,{method:req.method,headers:req.headers,...(req.method==='POST'?{body:Buffer.concat(chunks)}:{})});
 const path=new URL(request.url).pathname,result=await storage.run(sessions.get(req.headers.authorization),()=>path==='/edge/lean-comparison'?edge(request):routes[path][req.method](request));res.writeHead(result.status,Object.fromEntries(result.headers));res.end(await result.text());
}catch(e){console.error(e);res.writeHead(500);res.end('local fixture failure');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`,prior=process.env.APP_ORIGIN;process.env.APP_ORIGIN=origin;
const checks=[],responses=[],times=[];
async function request(path,token=owner,body){const start=performance.now(),r=await originalFetch(origin+path,{method:body?'POST':'GET',headers:{...(token?{authorization:token}:{}),...(body?{origin,'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});const raw=await r.text(),data=JSON.parse(raw);times.push(performance.now()-start);responses.push({path:path.split('?')[0],status:r.status,bytes:Buffer.byteLength(raw),error:data.error??null});return {status:r.status,data};}
async function check(name,fn){await fn();checks.push(name);}
const period=`factory=${f}&from=2026-02-10T22%3A00%3A00%2B03%3A00&to=2026-02-11T01%3A00%3A00%2B03%3A00`;
try{
 const before=await sql('select reporting_test.digest();');
 await check('unauthenticated Lean denied',async()=>assert.equal((await request('/api/lean?factory='+f,null)).status,401));
 await check('Orders-only cannot read Lean evidence',async()=>assert.equal((await request('/api/lean?factory='+f+'&mode=entries',worker)).status,403));
 await check('foreign factory denied with no data',async()=>{const r=await request('/api/lean?factory='+foreign+'&mode=entries');assert.equal(r.status,403);assert.equal(r.data.rows,undefined);});
 await check('overnight reviewed period read has exact KG and null instant',async()=>{const r=await request('/api/lean?'+period+'&mode=analysis_occurrences');assert.equal(r.status,200);assert.equal(r.data.rows[0].scrap_kg,'0.1234567890123456789');assert.equal(r.data.rows[0].occurred_at,null);});
 await check('partial period is present with unknown allocated KG',async()=>{const r=await request('/api/lean?'+period.replace('22%3A00','23%3A00')+'&mode=analysis_occurrences');assert.equal(r.status,200);assert.equal(r.data.rows[0].scrap_kg,null);});
 await check('operational Quality remains available without Lean evidence',async()=>{const r=await request(`/api/quality?factory=${f}&entry=${x.entry}`,worker);assert.equal(r.status,200);assert.equal(r.data.rows[0].scrap_evidence,null);});
 await check('revoked package reviewer cannot read pending queue',async()=>assert.equal((await request('/api/lean?factory='+f+'&mode=pending',viewer)).status,403));
 await check('owner existing review queue loads',async()=>assert.equal((await request('/api/lean?factory='+f+'&mode=pending')).status,200));
 await check('History API retains precise official quantities and current review fact',async()=>{const r=await request(`/api/production-reporting?factory=${f}&reporting_version=3&entry=${x.entry}`);assert.equal(r.status,200);assert.equal(typeof r.data.rows[0].scrap_kg,'string');assert.equal(typeof r.data.rows[0].observation.review_current,'boolean');});
 await check('existing Lean problem enrichment separates known quantities from unknown runtime',async()=>{const r=await request('/api/lean?'+period+'&mode=problems');assert.equal(r.status,200);assert.equal(r.data.rows[0].scrap_kg,'0.1234567890123456789');assert.equal(r.data.rows[0].quantity_evidence_status,'READY');assert.equal(r.data.rows[0].evidence_status,'INCOMPLETE');});
 await check('read checks preserve complete operational/audit digest',async()=>assert.equal(await sql('select reporting_test.digest();'),before));
 const obs=randomUUID(),payload={id:obs,entry_id:newEntry,time_precision:'SHIFT_PERIOD',preliminary_cause_id:x.cause,observation:'Period observation through real handler',response:'Normal authorized review follows'},body={command:'lean_command',args:{factory:f,operation:'scrap_observation',request_id:randomUUID(),payload}};
 await check('ordinary authorized API accepts approved period command',async()=>{const r=await request('/api/data',worker,body);assert.equal(r.status,200);assert.equal(r.data.data.id,obs);});
 await check('period API retry remains idempotent',async()=>assert.equal((await request('/api/data',worker,body)).data.data.id,obs));
 await check('forged period rejected with no operational change',async()=>{const d=await sql('select m3c_test.operational();');const r=await request('/api/data',worker,{...body,args:{...body.args,request_id:randomUUID(),payload:{...payload,id:randomUUID(),period_start:'2026-01-01T00:00:00Z'}}});assert.equal(r.status,400);assert.equal(await sql('select m3c_test.operational();'),d);});
 const problem=await sql(`select id from public.lean_problem_settings where factory_id=${quote(f)} and mechanism='scrap' order by id limit 1;`);
 await check('actual local Edge preview returns versioned evidence without persistence',async()=>{const d=await sql('select m3c_test.operational();');const r=await request('/edge/lean-comparison',owner,{factory:f,operation:'manual',problem_id:problem,product_id:x.product,cutoff:'2026-02-11T03:00:00Z',desired_hours:1});assert.equal(r.status,200);assert.equal(r.data.evidence.version,2);assert.equal(r.data.evidence.time_basis,'production');assert.equal(await sql('select m3c_test.operational();'),d);});
 times.sort((a,b)=>a-b);await writeFile(join(out,'consumer-http.json'),JSON.stringify({checks:checks.length,names:checks,responses,rpcCalls,rpcNames,medianMs:times[Math.floor(times.length/2)],p95Ms:times[Math.floor(times.length*.95)],limits:'Actual handlers/installed client/Edge source/SQL, fixture Auth and transport; not GoTrue/PostgREST/Deno deployment or browser acceptance.'},null,2));
 console.log(`PASS ${checks.length} M3C HTTP/SQL/Edge scenarios; ${rpcCalls} RPCs; median ${Math.round(times[Math.floor(times.length/2)])}ms`);
}finally{await new Promise(r=>server.close(r));globalThis.fetch=originalFetch;delete globalThis.__m3cDb;delete globalThis.Deno;sessions.clear();if(prior===undefined)delete process.env.APP_ORIGIN;else process.env.APP_ORIGIN=prior;}
