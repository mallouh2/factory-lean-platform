// Real Next handlers + authorization + SQL. Fixture session/transport only;
// not GoTrue, PostgREST, a browser login, or the full Next HTTP router.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {AsyncLocalStorage} from 'node:async_hooks';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';
const [bin,port,output]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.match(port,/^\d{4,5}$/);
function sql(text){return new Promise((done,reject)=>{const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1']);let out='',error='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>done({code,out:out.trim(),error}));p.stdin.end(text);});}
async function required(text){const r=await sql(text);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const x=JSON.parse(await required('select x from late_test.context;'));
const actorSql=()=>`do $$begin perform set_config('request.jwt.claim.sub',${quote(x.owner)},false);perform set_config('request.jwt.claim.role','authenticated',false);end$$;`;
await required(`update private.production_recording_v3_activation set enabled=true,schema_contract_version=3 where factory_id=${quote(x.factory)};
 create function late_test.transport(op text,args jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$declare result jsonb;msg text;code text;begin
 if op='can_access' then result:=to_jsonb(public.can_access((args->>'factory')::uuid,args->>'module',args->>'action'));
 elsif op='record_lean_production' then result:=public.record_lean_production((args->>'factory')::uuid,args->'payload',(args->>'request_id')::uuid);
 elsif op='production_recording_request_status' then result:=public.production_recording_request_status((args->>'factory')::uuid,(args->>'request_id')::uuid);
 else raise exception 'Unexpected test transport';end if;return jsonb_build_object('data',result,'error',null);
 exception when others then get stacked diagnostics msg=MESSAGE_TEXT,code=RETURNED_SQLSTATE;return jsonb_build_object('data',null,'error',jsonb_build_object('message',msg,'code',code));end$$;
 grant usage on schema late_test to authenticated;grant execute on function late_test.transport(text,jsonb) to authenticated;`);
const sessions=new Map(),owner=randomUUID(),viewer=randomUUID();sessions.set(owner,{id:x.owner,email_confirmed_at:'2026-01-01T00:00:00Z'});sessions.set(viewer,{id:x.viewer,email_confirmed_at:'2026-01-01T00:00:00Z'});
const storage=new AsyncLocalStorage();let rpcCalls=0;
globalThis.__lateLocalDb=async()=>{const user=storage.getStore();return {auth:{getUser:async()=>({data:{user:user??null},error:null})},rpc:async(name,args)=>{
 assert.ok(user);assert.ok(['can_access','record_lean_production','production_recording_request_status'].includes(name));rpcCalls++;
 return JSON.parse(await required(`begin ${name==='record_lean_production'?'':'read only'};do $$begin perform set_config('request.jwt.claim.sub',${quote(user.id)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;
 set local role authenticated;select late_test.transport(${quote(name)},${quote(JSON.stringify(args))});commit;`));
 }};};
async function handler(path){const compiled=await build({entryPoints:[path],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'fixture-session-only',setup(b){b.onResolve({filter:/^\.\/supabase$/},a=>a.importer.endsWith('authorization.ts')?{path:'fixture-session',namespace:'fixture'}:undefined);b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const supabaseServer=globalThis.__lateLocalDb;'}));}}]});const mod={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),mod,mod.exports);return mod.exports;}
const read=await handler('src/app/api/production-recording-status/route.ts'),write=await handler('src/app/api/data/route.ts');
const server=createServer(async(req,res)=>{try{const chunks=[];for await(const b of req)chunks.push(b);const url=`http://127.0.0.1:${server.address().port}${req.url}`;const request=new NextRequest(url,{method:req.method,headers:req.headers,...(req.method==='POST'?{body:Buffer.concat(chunks)}:{})});const result=await storage.run(sessions.get(req.headers.authorization),()=>req.method==='POST'?write.POST(request):read.GET(request));if(req.headers['x-local-drop-response']==='1'){res.destroy();return;}res.writeHead(result.status,Object.fromEntries(result.headers));res.end(await result.text());}catch{res.writeHead(500);res.end('local harness failure');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`,reports=[];
// NextRequest normalizes loopback IP URLs to localhost. Use the application's
// real configured-origin contract, scoped only to this local test process.
const previousOrigin=process.env.APP_ORIGIN;process.env.APP_ORIGIN=origin;
async function request(path,token,body){const response=await fetch(origin+path,{method:body?'POST':'GET',headers:{...(token?{authorization:token}:{}),...(body?{'content-type':'application/json',origin}:{})},...(body?{body:JSON.stringify(body)}:{})});const data=await response.json();assert.match(response.headers.get('cache-control')??'',/private.*no-store/);reports.push({status:response.status,error:data.error??null,outcome:data.outcome??data.data?.outcome??null});return {status:response.status,data};}
try{
 const p=JSON.parse(await required(`begin;select set_config('request.jwt.claim.sub',${quote(x.owner)},true) where false;do $$begin perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);end$$;select late_test.payload(${quote(JSON.stringify(x))},1);commit;`));
 const r=randomUUID(),body={command:'record_lean_production',args:{factory:x.factory,request_id:r,payload:p}},status=`/api/production-recording-status?factory=${x.factory}&request_id=${r}`;
 assert.equal((await request(status)).status,401);
 assert.equal((await request(status,viewer)).status,403);
 assert.equal((await request('/api/data',undefined,body)).status,401);
 assert.equal((await request('/api/data',viewer,body)).status,403);
 assert.equal((await request(status,owner)).data.outcome,'UNKNOWN');
 const first=await request('/api/data',owner,body);assert.equal(first.status,200);assert.equal(first.data.data.outcome,'COMMITTED');
 const retry=await request('/api/data',owner,body);assert.equal(retry.data.data.replayed,true);assert.equal(retry.data.data.entry_id,first.data.data.entry_id);
 assert.equal((await request(status,owner)).data.receipt.entry_id,first.data.data.entry_id);
 assert.equal((await request('/api/data',owner,{...body,args:{...body.args,payload:{...p,good:9}}})).status,409);
 assert.equal((await request(status+'&actor='+x.viewer,owner)).status,422);
 assert.equal(await required(`select count(*) from public.production_entries where factory_id=${quote(x.factory)} and request_id=${quote(r)}`),'1');
 const lostId=randomUUID(),fresh=JSON.parse(await required(`${actorSql()}select late_test.payload(${quote(JSON.stringify(x))},1);`));
 const lostBody={command:'record_lean_production',args:{factory:x.factory,request_id:lostId,payload:fresh}};
 await assert.rejects(fetch(origin+'/api/data',{method:'POST',headers:{authorization:owner,'content-type':'application/json',origin,'x-local-drop-response':'1'},body:JSON.stringify(lostBody)}));
 const recovered=await request(`/api/production-recording-status?factory=${x.factory}&request_id=${lostId}`,owner);
 assert.equal(recovered.data.outcome,'COMMITTED');
 assert.equal((await request('/api/data',owner,lostBody)).data.data.entry_id,recovered.data.receipt.entry_id);
 await required(`update private.production_recording_v3_activation set enabled=false where factory_id=${quote(x.factory)}`);
 assert.equal((await request('/api/data',owner,body)).data.data.entry_id,first.data.data.entry_id);
 await writeFile(join(output,'http.json'),JSON.stringify({checks:15,rpcCalls,reports,lostResponse:'COMMITTED recovered through status, same UUID replay',limits:'Actual handlers and SQL with fixture session/transport; not GoTrue/PostgREST.'},null,2));console.log('PASS 15 HTTP/SQL checks including lost-response recovery');
}finally{sessions.clear();await new Promise(r=>server.close(r));delete globalThis.__lateLocalDb;if(previousOrigin===undefined)delete process.env.APP_ORIGIN;else process.env.APP_ORIGIN=previousOrigin;}
