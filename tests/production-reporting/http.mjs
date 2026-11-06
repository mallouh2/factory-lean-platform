// Real route, installed Supabase client, authorization, service and protected SQL.
// Only session and HTTP/PostgREST transport are fixture adapters, not hosted proof.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {AsyncLocalStorage} from 'node:async_hooks';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {performance} from 'node:perf_hooks';
import {build} from 'esbuild';
import {createClient} from '@supabase/supabase-js';
import {NextRequest} from 'next/server.js';

const [bin,port,output]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.match(port,/^\d{4,5}$/);
function sql(text){return new Promise((resolve,reject)=>{
  const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',error='';
  p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>error+=b);p.on('error',reject);p.on('close',code=>resolve({code,out:out.trim(),error}));p.stdin.end(text);
});}
async function required(text){const r=await sql(text);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const x=JSON.parse(await required('select x from reporting_test.context;'));
await required(`create function reporting_test.api_transport(op text,args jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
 declare result jsonb;msg text;code text;begin
 if op='can_access' then result:=to_jsonb(public.can_access((args->>'factory')::uuid,args->>'module',args->>'action'));
 elsif op='production_history' then result:=public.production_history((args->>'factory')::uuid,args->'filters',coalesce(args->>'sort_key','date'),coalesce(args->>'sort_direction','desc'),coalesce((args->>'page')::int,1));
 else raise exception 'Unexpected local transport';end if;
 return jsonb_build_object('body',result::text,'error',null);
 exception when others then get stacked diagnostics msg=MESSAGE_TEXT,code=RETURNED_SQLSTATE;
 return jsonb_build_object('body',null,'error',jsonb_build_object('message',msg,'code',code));end$$;
 revoke all on function reporting_test.api_transport(text,jsonb) from public;
 grant usage on schema reporting_test to authenticated;
 grant execute on function reporting_test.api_transport(text,jsonb) to authenticated;
 insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.viewer)},'orders','view') on conflict do nothing;`);
const otherFactory=await required(`select id from public.factories where id<>${quote(x.factory)} order by id limit 1;`);
assert.match(otherFactory,/^[0-9a-f-]{36}$/);
const baseline=await required('select reporting_test.digest();');
const permissions=await required(`select md5(string_agg(to_jsonb(p)::text,'|' order by to_jsonb(p)::text)) from public.user_permissions p;`);
const gates=await required("select jsonb_agg(to_jsonb(g) order by factory_id) from private.production_recording_v3_activation g;");
const maintenance=await required("select jsonb_agg(to_jsonb(g) order by to_jsonb(g)::text) from private.maintenance_planning_activation g;");
const sessions=new Map(),owner=randomUUID(),denied=randomUUID(),ordersOnly=randomUUID(),unconfirmed=randomUUID();
sessions.set(owner,{id:x.owner,email_confirmed_at:'2026-01-01T00:00:00Z'});sessions.set(ordersOnly,{id:x.viewer,email_confirmed_at:'2026-01-01T00:00:00Z'});
sessions.set(denied,{id:x.worker,email_confirmed_at:'2026-01-01T00:00:00Z'});sessions.set(unconfirmed,{id:x.owner});
const storage=new AsyncLocalStorage(),originalFetch=globalThis.fetch;let rpcCalls=0;const rpcTimings=[];
globalThis.fetch=async(input,init)=>{
  const url=new URL(String(input));
  if(!url.pathname.startsWith('/rest/v1/rpc/'))return originalFetch(input,init);
  const user=storage.getStore();assert.ok(user);const op=url.pathname.split('/').at(-1);assert.ok(['can_access','production_history'].includes(op));
  const args=init.method==='GET'?Object.fromEntries(url.searchParams):JSON.parse(init.body);
  if(typeof args.filters==='string')args.filters=JSON.parse(args.filters);
  if(op==='production_history' && args.filters.reporting_version)assert.equal(init.method,'GET');
  rpcCalls++;const start=performance.now();
  const result=JSON.parse(await required(`begin read only;do $$begin perform set_config('request.jwt.claim.sub',${quote(user.id)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;
   set local role authenticated;select reporting_test.api_transport(${quote(op)},${quote(JSON.stringify(args))});commit;`));
  rpcTimings.push({op,ms:performance.now()-start});
  return new Response(result.error?JSON.stringify(result.error):result.body,{status:result.error?(result.error.code==='42501'?403:result.error.code==='40001'?409:400):200,headers:{'Content-Type':'application/json'}});
};
globalThis.__reportingLocalDb=async(fetcher)=>{
  const user=storage.getStore();const db=createClient('http://127.0.0.1:1','local-fixture-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:fetcher??globalThis.fetch}});
  db.auth.getUser=async()=>({data:{user:user??null},error:null});return db;
};
async function handler(path){const compiled=await build({entryPoints:[path],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'local-session-only',setup(b){b.onResolve({filter:/^\.\/supabase$/},a=>a.importer.endsWith('authorization.ts')?{path:'local-session',namespace:'fixture'}:undefined);b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const supabaseServer=globalThis.__reportingLocalDb;'}));}}]});const mod={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),mod,mod.exports);return mod.exports;}
const route=await handler('src/app/api/production-reporting/route.ts'),legacy=await handler('src/app/api/production-history/route.ts');
assert.deepEqual(Object.keys(route),['GET']);
const server=createServer(async(req,res)=>{try{
  const request=new NextRequest(`http://127.0.0.1:${server.address().port}${req.url}`,{method:req.method,headers:req.headers});
  if(req.method!=='GET'){res.writeHead(405);res.end();return;}
  const selected=req.url.startsWith('/api/production-reporting?')?route:legacy;
  const result=await storage.run(sessions.get(req.headers.authorization),()=>selected.GET(request));res.writeHead(result.status,Object.fromEntries(result.headers));res.end(await result.text());
}catch(e){console.error(e);res.writeHead(500);res.end('local fixture failure');}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`,checks=[],responses=[],timings=[];
async function check(name,action){await action();checks.push(name);}
async function request(extra='',token=owner,factory=x.factory){
  const start=performance.now(),before=rpcCalls;
  const r=await originalFetch(`${origin}/api/production-reporting?factory=${factory}&reporting_version=3${extra}`,{headers:token?{authorization:token}:{}});
  const raw=await r.text(),data=JSON.parse(raw);assert.match(r.headers.get('cache-control')??'',/private.*no-store/);
  timings.push({ms:performance.now()-start,bytes:Buffer.byteLength(raw),rpcCalls:rpcCalls-before,status:r.status});responses.push({status:r.status,error:data.error??null});
  return {status:r.status,data,raw};
}
try{
 await check('401 no authenticated session',async()=>assert.equal((await request('',null)).status,401));
 await check('401 unconfirmed account',async()=>assert.equal((await request('',unconfirmed)).status,401));
 await check('403 missing Orders permission',async()=>assert.equal((await request('',denied)).status,403));
 await check('403 real second-factory isolation',async()=>assert.equal((await request('',owner,otherFactory)).status,403));
 for(const bad of ['&page_size=101','&mode=corrections','&request='+x.item,'&cursor=bad','&from=2026-02-30'])await check('400 invalid filter '+bad,async()=>{const before=rpcCalls;assert.equal((await request(bad)).status,400);assert.equal(rpcCalls,before);});
 let current;
 await check('authorized current declarations, bounded exact fields and source identity',async()=>{
  current=await request();assert.equal(current.status,200);assert.equal(current.data.mode,'entries');assert.equal(current.data.contract_version,3);
  assert.ok(current.data.rows.some(r=>r.recording_kind==='LATE_ORDINARY'));assert.ok(current.data.rows.some(r=>r.source_id));
  for(const r of current.data.rows){assert.equal(r.factory_id,x.factory);assert.equal(typeof r.good,'string');assert.equal(typeof r.scrap_kg,'string');assert.ok(!r.effective_occurrence||!('materialized_at' in r.effective_occurrence));}
 });
 await check('pending Scrap is not reviewed Lean evidence',async()=>{
  const r=current.data.rows.find(r=>r.id===x.unreviewed);assert.equal(r.observation.status,'PENDING');assert.equal(r.lean_evidence.reviewed_scrap_kg,null);
 });
 await check('reviewed provenance retained, no comparison invented',async()=>{
  const r=current.data.rows.find(r=>r.id===x.reviewed);assert.equal(r.observation.status,'REVIEWED');assert.equal(r.lean_evidence.version,2);assert.equal(r.lean_evidence.comparison_status,'NOT_CALCULATED');
 });
 await check('Orders-only direct grant masks Lean provenance',async()=>{
  const r=await request('',ordersOnly);assert.equal(r.status,200);assert.ok(r.data.rows.every(r=>r.lean_evidence===null));
 });
 let historic;
 await check('historical overnight occurrence and exact corrected quantities',async()=>{
  const r=await request('&time_basis=production&from=2026-01-10&to=2026-01-10');assert.equal(r.status,200);assert.equal(r.data.total,1);historic=r.data.rows[0];
  assert.equal(historic.effective_occurrence.business_date,'2026-01-10');assert.match(historic.recorded_at,/^2026-01-11/);assert.equal(historic.original_good,'10.1234567890123456789');assert.equal(historic.good,'9.1234567890123456789');assert.equal(historic.scrap_kg,'0.1234567890123456789');
  assert.equal(historic.observation.precision,'SHIFT_PERIOD');assert.equal(historic.observation.occurred_at,null);
 });
 await check('recorded basis does not invent a backdated submission',async()=>assert.equal((await request('&from=2026-01-10&to=2026-01-10')).data.total,0));
 await check('correction audit exact decimals through installed client',async()=>{
  const r=await request(`&mode=corrections&entry=${historic.id}&from=2026-01-10&to=2026-01-12`);assert.equal(r.status,200);assert.equal(r.data.rows[0].entry_id,historic.id);
  assert.equal(r.data.rows[0].previous_good,'10.1234567890123456789');assert.equal(r.data.rows[0].corrected_good,'9.1234567890123456789');assert.equal(r.data.rows[0].corrected_scrap_kg,'0.1234567890123456789');
 });
 await check('dated summary counts effective output once',async()=>{
  const r=await request('&mode=summary&time_basis=production&from=2026-01-10&to=2026-01-10');assert.equal(r.status,200);assert.equal(r.data.rows[0].good,historic.good);assert.equal(r.data.rows[0].scrap_kg,historic.scrap_kg);assert.equal(r.data.rows[0].unit,'meter');
 });
 await check('partial period remains unknown with declared quantity',async()=>{
  const r=await request('&mode=summary&time_basis=production&from_at=2026-01-10T23:00:00Z&to_at=2026-01-10T23:30:00Z');assert.equal(r.status,200);assert.equal(r.data.rows[0].good,null);assert.equal(r.data.rows[0].unallocated_good,historic.good);assert.equal(r.data.rows[0].scrap_rate,null);
 });
 await check('Product, occurrence, entry and line filters retain identity',async()=>{
  const r=await request(`&time_basis=production&from=2026-01-10&to=2026-01-10&occurrence=${historic.effective_occurrence.occurrence_key}&product=${historic.product_id}&line=${historic.line_id}&entry=${historic.id}`);assert.equal(r.status,200);assert.equal(r.data.total,1);assert.equal(r.data.rows[0].item_id,historic.item_id);assert.equal(r.data.rows[0].request_id,historic.request_id);
 });
 await check('same Product on distinct lines/orders, and separate units',async()=>{
  const r=await request('&mode=summary');assert.equal(r.status,200);assert.ok(r.data.rows.some(r=>r.unit==='meter'));assert.ok(r.data.rows.some(r=>r.unit==='piece'));
  const rows=r.data.rows.filter(r=>r.product_id===x.product);assert.ok(new Set(rows.map(r=>r.line_id)).size>=2);
  const h=await request('&product='+x.product);assert.ok(new Set(h.data.rows.map(r=>r.item_id)).size>=2);
 });
 await check('legacy unknown bucket stays explicit',async()=>{
  const r=await request('&mode=summary&time_basis=production');assert.equal(r.status,200);assert.equal(r.data.allocation_complete,false);assert.ok(r.data.unknown_attribution_records>5001);assert.ok(r.data.rows.some(r=>r.occurrence_key===null && r.good===null && r.unallocated_good!==null));
 });
 await check('empty complete page',async()=>{const r=await request('&from=2020-01-01&to=2020-01-01');assert.equal(r.status,200);assert.equal(r.data.total,0);assert.deepEqual(r.data.rows,[]);assert.equal(r.data.next_cursor,null);});
 let pageCount=0,seen=new Set(),cursor=null,total;
 await check('full HTTP pagination beyond 5001 without gaps, repeats or N+1',async()=>{
  do{
   const r=await request('&page_size=100'+(cursor?'&cursor='+cursor:''));assert.equal(r.status,200);assert.ok(r.data.rows.length<=100);assert.equal(timings.at(-1).rpcCalls,2);assert.ok(timings.at(-1).bytes<650000);
   total=r.data.total;for(const row of r.data.rows){assert.ok(!seen.has(row.id));seen.add(row.id);}cursor=r.data.next_cursor;assert.equal(r.data.complete,cursor===null);pageCount++;
  }while(cursor);
  assert.ok(seen.size>5001);assert.equal(seen.size,total);assert.ok(pageCount>50);
 });
 await check('cursor query changes fail explicitly with 409 restart',async()=>{
  const first=await request('&page_size=1');const r=await request('&page_size=1&time_basis=production&cursor='+first.data.next_cursor);assert.equal(r.status,409);assert.equal(r.data.restart,true);
 });
 await check('stale source revision fails explicitly with 409',async()=>{
  const first=await request('&page_size=1');const c=JSON.parse(Buffer.from(first.data.next_cursor,'base64url'));c.source_revision='0';const r=await request('&page_size=1&cursor='+Buffer.from(JSON.stringify(c)).toString('base64url'));assert.equal(r.status,409);
 });
 await check('legacy History actual route remains available and numerically compatible',async()=>{
  // Empty page avoids the unchanged legacy mass supplement in this transport;
  // its populated supplement path is separately exercised by the Node regression.
  const r=await originalFetch(`${origin}/api/production-history?factory=${x.factory}&from=2020-01-01&to=2020-01-01`,{headers:{authorization:owner}});assert.equal(r.status,200);const data=await r.json();assert.deepEqual(data.rows,[]);assert.ok(!('contract_version' in data));
 });
 await check('GET-only route exports no write handler',async()=>{assert.deepEqual(Object.keys(route),['GET']);assert.equal((await originalFetch(origin+'/api/production-reporting',{method:'POST'})).status,405);});
 await check('read-only all-ledger, permissions and activation preservation',async()=>{
  assert.equal(await required('select reporting_test.digest();'),baseline);
  assert.equal(await required("select md5(string_agg(to_jsonb(p)::text,'|' order by to_jsonb(p)::text)) from public.user_permissions p;"),permissions);
  assert.equal(await required('select jsonb_agg(to_jsonb(g) order by factory_id) from private.production_recording_v3_activation g;'),gates);
  assert.equal(await required('select jsonb_agg(to_jsonb(g) order by to_jsonb(g)::text) from private.maintenance_planning_activation g;'),maintenance);
 });
 await writeFile(join(output,'http.json'),JSON.stringify({checks:checks.length,names:checks,rpcCalls,responses,pagination:{pageCount,uniqueRows:seen.size,total},timings,rpcTimings,beforeDigest:baseline,afterDigest:await required('select reporting_test.digest();'),limits:'Fixture Auth/HTTP transport with actual Supabase client, routes and SQL; not GoTrue/PostgREST/full Next routing.'},null,2));
 console.log(`PASS ${checks.length} HTTP/SQL scenarios; ${rpcCalls} RPC calls; ${seen.size} unique rows on ${pageCount} pages`);
}finally{sessions.clear();await new Promise(r=>server.close(r));globalThis.fetch=originalFetch;delete globalThis.__reportingLocalDb;}
