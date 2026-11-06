// Actual Next handlers, authorization and protected SQL. Fixture sessions and
// PostgREST transport are adapted; this is not GoTrue/hosted acceptance.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {AsyncLocalStorage} from 'node:async_hooks';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {build} from 'esbuild';
import {createClient} from '@supabase/supabase-js';
import {NextRequest} from 'next/server.js';
const [bin,port,output]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.match(port,/^\d{4,5}$/);
async function sql(text){return new Promise((done,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',err='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);p.on('error',reject);p.on('close',code=>{try{assert.equal(code,0,err);done(out.trim());}catch(e){reject(e);}});p.stdin.end(text);});}
assert.equal(await sql("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const x=JSON.parse(await sql('select x from correction_test.context;'));
await sql(`create function correction_test.transport(op text,args jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$declare result jsonb;msg text;code text;begin
 if op='can_access' then result:=to_jsonb(public.can_access((args->>'factory')::uuid,args->>'module',args->>'action'));
 elsif op='production_correction_command' then result:=public.production_correction_command((args->>'factory')::uuid,args->>'operation',args->'payload',(args->>'request_id')::uuid);
 elsif op='production_correction_read' then result:=public.production_correction_read((args->>'factory')::uuid,args->'query');
 elsif op='production_history' then result:=public.production_history((args->>'factory')::uuid,args->'filters');
 else raise exception 'Unexpected fixture transport';end if;return jsonb_build_object('body',result::text,'error',null);
 exception when others then get stacked diagnostics msg=MESSAGE_TEXT,code=RETURNED_SQLSTATE;return jsonb_build_object('body',null,'error',jsonb_build_object('message',msg,'code',code));end$$;
 grant usage on schema correction_test to authenticated;grant execute on function correction_test.transport(text,jsonb) to authenticated;`);
const storage=new AsyncLocalStorage(),sessions=new Map(),tech=randomUUID(),engineer=randomUUID(),denied=randomUUID(),fetchOriginal=globalThis.fetch;
sessions.set(tech,{id:x.worker,email_confirmed_at:'2026-01-01T00:00:00Z'});sessions.set(engineer,{id:x.engineer,email_confirmed_at:'2026-01-01T00:00:00Z'});
sessions.set(denied,{id:JSON.parse(await sql('select x from reporting_test.context;')).viewer,email_confirmed_at:'2026-01-01T00:00:00Z'});
let rpcCalls=0;
globalThis.fetch=async(input,init)=>{
 const url=new URL(String(input));if(!url.pathname.startsWith('/rest/v1/rpc/'))return fetchOriginal(input,init);
 const op=url.pathname.split('/').at(-1),args=init.method==='GET'?Object.fromEntries(url.searchParams):JSON.parse(init.body),user=storage.getStore();assert.ok(user);
 for(const k of ['query','filters'])if(typeof args[k]==='string')args[k]=JSON.parse(args[k]);rpcCalls++;
 const result=JSON.parse(await sql(`begin ${op==='production_correction_command'?'':'read only'};do $$begin perform set_config('request.jwt.claim.sub',${quote(user.id)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;set local role authenticated;
 select correction_test.transport(${quote(op)},${quote(JSON.stringify(args))});commit;`));
 return new Response(result.error?JSON.stringify(result.error):result.body,{status:result.error?400:200,headers:{'Content-Type':'application/json'}});
};
globalThis.__correctionDb=async(fetcher)=>{const user=storage.getStore(),db=createClient('http://127.0.0.1:1','fixture-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:fetcher??globalThis.fetch}});db.auth.getUser=async()=>({data:{user:user??null},error:null});return db;};
async function load(path){const b=await build({entryPoints:[path],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'session-only',setup(t){t.onResolve({filter:/^\.\/supabase$/},a=>a.importer.endsWith('authorization.ts')?{path:'fixture',namespace:'fixture'}:undefined);t.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const supabaseServer=globalThis.__correctionDb;'}));}}]});const m={exports:{}};new Function('require','module','exports',b.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);return m.exports;}
const route=await load('src/app/api/production-corrections/route.ts'),history=await load('src/app/api/production-reporting/route.ts');
const server=createServer(async(req,res)=>{try{const chunks=[];for await(const b of req)chunks.push(b);const request=new NextRequest(`http://127.0.0.1:${server.address().port}${req.url}`,{method:req.method,headers:req.headers,...(req.method==='POST'?{body:Buffer.concat(chunks)}:{})});
 const selected=req.url.startsWith('/api/production-reporting')?history:route;
 const response=await storage.run(sessions.get(req.headers.authorization),()=>selected[req.method](request));
 if(req.headers['x-drop-response']==='1'){res.destroy();return;}res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text());
}catch(e){console.error(e);res.writeHead(500);res.end('local fixture error');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`,priorOrigin=process.env.APP_ORIGIN;process.env.APP_ORIGIN=origin;
const responses=[],checks=[];
async function request(path,token,body){const r=await fetchOriginal(origin+path,{method:body?'POST':'GET',headers:{...(token?{authorization:token}:{}),...(body?{origin,'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});assert.match(r.headers.get('cache-control')??'',/private.*no-store/);const data=await r.json();responses.push({status:r.status,error:data.error??null});return {status:r.status,data};}
async function check(name,fn){await fn();checks.push(name);}
const get=`/api/production-corrections?factory=${x.factory}`,hist=`/api/production-reporting?factory=${x.factory}&reporting_version=3&entry=${x.other_entry}`;
async function payload(delta){return JSON.parse(await sql(`select correction_test.payload(${quote(JSON.stringify(x))},${quote(x.other_entry)},(select effective_good+${delta} from public.production_entries where id=${quote(x.other_entry)}),.4,0);`));}
try{
 await check('unauthenticated GET denied',async()=>assert.equal((await request(get)).status,401));
 await check('missing factory authority denied',async()=>assert.equal((await request(get,denied)).status,403));
 let body={factory:x.factory,operation:'submit',payload:await payload('.125'),request_id:randomUUID()},pending,approved;
 await check('unauthenticated write denied',async()=>assert.equal((await request('/api/production-corrections',null,body)).status,401));
 const before=(await request(hist,engineer)).data.rows[0];
 await check('technician submits pending proposal',async()=>{const r=await request('/api/production-corrections',tech,body);assert.equal(r.status,200);pending=r.data;assert.equal(pending.status,'PENDING');});
 await check('pending proposal does not change effective History',async()=>{const row=(await request(hist,engineer)).data.rows[0];assert.equal(row.good,before.good);assert.equal(row.correction_count,before.correction_count);});
 await check('same UUID pending retry',async()=>assert.equal((await request('/api/production-corrections',tech,body)).data.id,pending.id));
 await check('unauthorized approval denied without changing request',async()=>{assert.equal((await request('/api/production-corrections',tech,{factory:x.factory,operation:'approve',payload:{id:pending.id},request_id:randomUUID()})).status,403);assert.equal((await request(get+'&id='+pending.id,tech)).data.rows[0].status,'PENDING');});
 const decision={factory:x.factory,operation:'approve',payload:{id:pending.id},request_id:randomUUID()};
 await check('engineer approves via server and existing posting pipeline',async()=>{const r=await request('/api/production-corrections',engineer,decision);assert.equal(r.status,200);approved=r.data;assert.equal(approved.status,'APPROVED');assert.equal(approved.requested_by,x.worker);assert.equal(approved.reviewed_by,x.engineer);});
 await check('approved History uses new quantity exactly once',async()=>{const row=(await request(hist,engineer)).data.rows[0];assert.equal(row.good,approved.applied_values.good);assert.equal(row.correction_count,before.correction_count+1);assert.equal(row.original_good,before.original_good);});
 await check('approval retry has same immutable correction',async()=>assert.equal((await request('/api/production-corrections',engineer,decision)).data.correction_id,approved.correction_id));
 await check('mandatory reason and forged fields rejected',async()=>{for(const p of [{...body.payload,reason:''},{...body.payload,approved_by:x.engineer}])assert.equal((await request('/api/production-corrections',tech,{...body,payload:p,request_id:randomUUID()})).status,422);});
 body={factory:x.factory,operation:'submit',payload:await payload('.125'),request_id:randomUUID()};
 await check('engineer auto-approval and lost-response recovery',async()=>{
  await assert.rejects(fetchOriginal(origin+'/api/production-corrections',{method:'POST',headers:{origin,authorization:engineer,'content-type':'application/json','x-drop-response':'1'},body:JSON.stringify(body)}));
  const recovered=await request(get+'&request_id='+body.request_id,engineer);assert.equal(recovered.status,200);assert.equal(recovered.data.total,1);assert.equal(recovered.data.rows[0].status,'APPROVED');
  const retry=await request('/api/production-corrections',engineer,body);assert.equal(retry.data.correction_id,recovered.data.rows[0].correction_id);
 });
 await writeFile(join(output,'correction-http.json'),JSON.stringify({checks:checks.length,names:checks,responses,rpcCalls,limits:'Actual handlers/client/authorization/SQL with fixture sessions and transport, not hosted GoTrue/PostgREST.'},null,2));console.log(`PASS ${checks.length} correction HTTP/SQL scenarios, ${rpcCalls} RPC calls`);
}finally{sessions.clear();await new Promise(r=>server.close(r));globalThis.fetch=fetchOriginal;delete globalThis.__correctionDb;if(priorOrigin===undefined)delete process.env.APP_ORIGIN;else process.env.APP_ORIGIN=priorOrigin;}
