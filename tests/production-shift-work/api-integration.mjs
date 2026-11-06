// Actual GET + authorization + PostgreSQL over loopback HTTP. Only the session/
// Supabase transport is adapted to local fixtures; this is not GoTrue/PostgREST.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {AsyncLocalStorage} from 'node:async_hooks';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {join, resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';

const [bin,port,output]=process.argv.slice(2);
assert.match(port,/^\d+$/);
assert.ok(resolve(output).includes('FactoryLean-Shift-M1-'));
const quote=x=>"'"+String(x).replaceAll("'","''")+"'";
async function sql(text) {
 return new Promise((done,reject)=>{
  const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});
  let out='',error='';p.stdout.on('data',x=>out+=x);p.stderr.on('data',x=>error+=x);
  p.on('error',reject);p.on('close',code=>done({code,out:out.trim(),error}));
  p.stdin.end('\\set VERBOSITY verbose\n'+text);
 });
}
async function required(text){const r=await sql(text);assert.equal(r.code,0,r.error);return r.out;}
assert.equal(await required("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const x=JSON.parse(await required('select x from shift_test.context;'));
const baseline=JSON.parse(await required('select x from shift_test.baseline;'));

// Fixture writes are complete before the HTTP read-only checks. Jobs use the
// installed Planning and protected Start/Finish contracts, without backdating.
await required(`begin;
 do $$declare z jsonb;f uuid;s timestamptz;old_item uuid;active_item uuid;zero_item uuid;
  member uuid;entry uuid;retry uuid:=gen_random_uuid();receipt_retry uuid:=gen_random_uuid();payload jsonb;begin
  perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  zero_item:=shift_test.new_job(${quote(JSON.stringify(x))},254,${quote(x.other_line)},false);
  update shift_test.context set x=x||jsonb_build_object('zero_entry_active',zero_item);
  z:=mp_test.fixture('http-boundaries');f:=(z->>'factory')::uuid;
  perform public.update_settings(f,'HTTP boundary fixture','UTC',null);
  perform public.configure_working_calendar(f,127,'00:00','23:59');
  perform public.configure_center_capabilities(f,(z->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',z->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
  old_item:=shift_test.new_job(z,1);
  s:=clock_timestamp()+interval '.3 seconds';
  perform public.configure_production_shift(f,'HTTP current shift','وردية محلية',s::time,(s+interval '4 hours')::time);
  perform pg_sleep(.4);
  active_item:=shift_test.new_job(z,2,null,false);
  select id into member from public.memberships where factory_id=f and user_id=(z->>'owner')::uuid;
  payload:=jsonb_build_object('unit_kind','line','production_unit',z->>'line','item',active_item,'technician',member,
   'good',2,'discarded_quantity',0,'scrap_kg',.25,'unfinished',0,'input_quantity',0);
  entry:=(public.record_lean_production(f,payload,retry)->>'id')::uuid;
  if (public.record_lean_production(f,payload,retry)->>'id')::uuid<>entry then raise exception 'Legacy recording retry duplicated';end if;
  perform public.supply_command(f,'acknowledge_good',jsonb_build_object('entry',entry),receipt_retry);
  perform public.supply_command(f,'acknowledge_good',jsonb_build_object('entry',entry),receipt_retry);
  create table shift_test.http_boundary(x jsonb);
  insert into shift_test.http_boundary values(z||jsonb_build_object('previous_only',old_item,'current',active_item,'entry',entry));
  insert into public.user_permissions(factory_id,user_id,module,action) values(${quote(x.factory)},${quote(x.viewer)},'orders','view');
 end$$;set constraints all immediate;commit;`);
const context=JSON.parse(await required('select x from shift_test.context;'));
const boundary=JSON.parse(await required('select x from shift_test.http_boundary;'));
const sessions=new Map();
const session=(id,confirmed=true)=>{const token=randomUUID();sessions.set(token,{id,email_confirmed_at:confirmed?'2026-01-01T00:00:00Z':null});return token;};
const owner=session(x.owner),viewer=session(x.viewer),worker=session(x.worker),boundaryOwner=session(boundary.owner),unconfirmed=session(x.owner,false);
const storage=new AsyncLocalStorage();
let sqlCalls=0;
globalThis.__shiftWorkLocalDb=async()=>{
 const user=storage.getStore();
 return {auth:{getUser:async()=>({data:{user:user??null},error:user?null:Error('local_session_missing')})},
  rpc:async(name,args)=>{
   assert.ok(user,'SQL requested without a local fixture session');
   assert.ok(['can_access','production_shift_work'].includes(name),'Unexpected RPC in read-only handler');
   sqlCalls++;
   const expression=name==='can_access'
    ? `to_jsonb(public.can_access(${quote(args.factory)}::uuid,${quote(args.module)},${quote(args.action)}))`
    : `public.production_shift_work(${quote(args.factory)}::uuid,${args.cursor?quote(JSON.stringify(args.cursor))+'::jsonb':'null'},${args.page_size})`;
   const r=await sql(`begin transaction read only;
    do $$begin perform set_config('request.jwt.claim.sub',${quote(user.id)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;
    set local role authenticated;select ${expression};commit;`);
   if(r.code)return {data:null,error:{code:r.error.match(/ERROR:\s+([A-Z0-9]{5}):/)?.[1]??'P0001',message:r.error}};
   return {data:JSON.parse(r.out),error:null};
  }};
};
const compiled=await build({entryPoints:['src/app/api/production-shift-work/route.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',
 plugins:[{name:'local-fixture-transport',setup(b){
  b.onResolve({filter:/^\.\/supabase$/},a=>a.importer.endsWith('authorization.ts')?{path:'local-fixture',namespace:'fixture'}:undefined);
  b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const supabaseServer=globalThis.__shiftWorkLocalDb;'}));
 }}]});
const mod={exports:{}};
new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),mod,mod.exports);
const server=createServer(async(req,res)=>{
 try{
  const token=/\blocal_session=([^;]+)/.exec(req.headers.cookie??'')?.[1];
  const request=new NextRequest('http://127.0.0.1'+req.url,{headers:req.headers});
  const response=await storage.run(sessions.get(token),()=>mod.exports.GET(request));
  res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text());
 }catch{res.writeHead(500,{'content-type':'application/json'});res.end('{"error":"local_harness_failure"}');}
});
const results=[];
const ok=(condition,label)=>{assert.ok(condition,label);results.push(label);};
const tables=['production_orders','production_entries','production_entry_corrections','finished_goods_balances','finished_goods_movements','finished_goods_sources','finished_goods_source_allocations','finished_goods_reservations','unfinished_lots','unfinished_movements','maintenance_requests','maintenance_schedules','downtime_events','production_loss_estimates'];
const digestSql='select md5(jsonb_build_array('+tables.map(t=>`(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') from public.${t} t)`).concat([
 "(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') from private.production_shift_schedule_revisions t)",
 "(select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]') from private.production_shift_occurrences t)"
]).join(',')+')::text)';
const before=await required(digestSql);
await new Promise((done,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',done);});
const base='http://127.0.0.1:'+server.address().port+'/api/production-shift-work';
const evidence=[];
async function request(params={},token=owner){
 const q=new URLSearchParams({factory:x.factory,...params});
 const r=await fetch(base+'?'+q,{headers:token?{cookie:'local_session='+token}:{}});
 const body=await r.json();
 assert.equal(r.headers.get('cache-control'),'private, no-store');
 evidence.push({status:r.status,error:body.error??null,reason:body.reason??null,total:body.total??null});
 return {status:r.status,body};
}
try{
 const legacy=JSON.parse(await required(`select jsonb_build_object(
  'kg',(select effective_scrap_kg=.25 and effective_good=2 from public.production_entries where id=${quote(boundary.entry)}),
  'stock',(select on_hand=2 from public.finished_goods_balances where factory_id=${quote(boundary.factory)} and unit='meter'),
  'sources',(select quantity_credited=2 and quantity_identified=0 and physical_label is null from public.finished_goods_sources where entry_id=${quote(boundary.entry)}),
  'receipts',(select count(*)=1 from public.production_receipt_acknowledgments where entry_id=${quote(boundary.entry)}),
  'entries',(select count(*)=1 from public.production_entries where factory_id=${quote(boundary.factory)}),
  'movements',(select count(*)=1 from public.finished_goods_movements where factory_id=${quote(boundary.factory)}))`));
 ok(legacy.kg&&legacy.stock,'ordinary positive Scrap remains KG and never becomes finished stock');
 ok(legacy.entries&&legacy.movements,'ordinary recording retry creates one Good entry and credit');
 ok(legacy.sources&&legacy.receipts&&legacy.stock,'Warehouse acknowledgement retry never double-credits or invents physical identification');
 let r=await request({},null);ok(r.status===401,'HTTP anonymous request denied');
 r=await request({},'invalid-local-session');ok(r.status===401,'HTTP invalid local session denied');
 r=await request({},unconfirmed);ok(r.status===401,'real authentication guard rejects unconfirmed fixture identity');
 r=await request({},worker);ok(r.status===403,'real authorization guard denies missing Orders view');
 r=await request({factory:baseline.factory});ok(r.status===403&&!r.body.rows,'cross-factory request denied without rows');
 r=await request();ok(r.status===200&&r.body.contract_version===3,'actual GET returns real protected PostgreSQL reader');
 const first=r.body;
 ok(first.total===254&&!first.complete&&first.rows.length===50,'HTTP bounded first page reports complete dataset total');
 ok(first.rows[0].status==='active'&&first.rows[1].status==='active','HTTP active work precedes completed work');
 ok(new Set(first.rows.slice(0,2).map(v=>v.line_id)).size===2,'same Product on distinct capable lines remains separate');
 ok(first.occurrence.factory_id===x.factory&&first.occurrence.timezone==='UTC'&&Date.parse(first.expires_at)>Date.now(),'current frozen occurrence and expiry are returned');
 const zero=first.rows.find(v=>v.item_id===context.zero_entry_active);
 ok(zero&&zero.can_record&&zero.remaining_quantity===100&&zero.unit==='meter','started zero-entry item is eligible with exact unit/remaining');
 const good=first.rows.find(v=>v.item_id===x.active);
 ok(good&&good.accepted_good===2&&good.remaining_quantity===98,'accepted Good and remaining use authoritative existing quantities');
 const seen=[];let page=first,pages=1;
 for(;;){seen.push(...page.rows);if(page.complete)break;const next=await request({cursor:page.next_cursor});assert.equal(next.status,200);page=next.body;pages++;assert.ok(pages<=10);}
 ok(pages===6&&seen.length===254&&new Set(seen.map(v=>v.item_id)).size===254,'six HTTP pages contain every execution once');
 ok(new Set(seen.map(v=>v.request_id)).size===254,'same Product under separate orders keeps distinct request identities');
 ok(seen.some(v=>v.item_id===x.completed&&v.status==='completed'&&v.blocked_reason==='PHASE1_READ_ONLY'),'completed current-shift work is preview only');
 ok(!seen.some(v=>v.item_id===x.item),'scheduled-only item is excluded');
 ok(seen.every(v=>v.late_recording_available===false)&&first.late_recording_available===false,'HTTP response never enables completed-job late writes');
 const micros=s=>BigInt(Date.parse(s))*1000n+BigInt(((/\.(\d+)/.exec(s)?.[1]??'').padEnd(6,'0')).slice(3,6));
 const tuples=seen.map(v=>[v.status==='active'?0:1,-micros(v.actual_start),v.item_id]);
 ok(tuples.every((t,i)=>!i||t[0]>tuples[i-1][0]||(t[0]===tuples[i-1][0]&&(t[1]>tuples[i-1][1]||(t[1]===tuples[i-1][1]&&t[2]>tuples[i-1][2])))),'HTTP keyset ordering is stable');
 r=await request({},viewer);ok(r.status===200&&!r.body.can_edit&&r.body.rows.every(v=>!v.can_record),'direct view-only grant reads without recording capability');
 const oldCursor=JSON.parse(Buffer.from(first.next_cursor,'base64url'));oldCursor.revision=String(BigInt(oldCursor.revision)+1n);
 r=await request({cursor:Buffer.from(JSON.stringify(oldCursor)).toString('base64url')});ok(r.status===409&&r.body.restart===true,'real SQL stale-context response maps to HTTP409');
 r=await request({page_size:'101'});ok(r.status===400,'HTTP oversized page rejected');
 r=await request({factory:boundary.factory},boundaryOwner);
 ok(r.status===200&&r.body.total===1&&r.body.rows[0].item_id===boundary.current,'actual current-shift execution included in boundary fixture');
 ok(!r.body.rows.some(v=>v.item_id===boundary.previous_only),'actual previous-shift-only completed execution excluded');
 const baselineOwner=session(baseline.owner);
 r=await request({factory:baseline.factory},baselineOwner);ok(r.status===200&&r.body.reason==='OCCURRENCE_NOT_READY'&&r.body.rows.length===0,'initial prospective fence returns honest unavailable context');
 await required(`begin;do $$declare pkg uuid;begin
  perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);perform set_config('request.jwt.claim.role','authenticated',true);
  select id into pkg from public.permission_packages where factory_id=${quote(x.factory)} and template_key='planning_engineer';
  perform public.set_member_permission_packages(${quote(x.factory)},${quote(x.worker)},array[pkg],array[]::uuid[]);
 end$$;commit;`);
 r=await request({},worker);ok(r.status===200,'package permission authorizes actual HTTP/SQL read');
 await required(`begin;do $$declare pkg uuid;begin
  perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);perform set_config('request.jwt.claim.role','authenticated',true);
  select id into pkg from public.permission_packages where factory_id=${quote(x.factory)} and template_key='planning_engineer';
  perform public.set_member_permission_packages(${quote(x.factory)},${quote(x.worker)},array[]::uuid[],array[pkg]);
 end$$;commit;`);
 r=await request({},worker);ok(r.status===403,'revoked package is rechecked on next HTTP request');
 ok(await required(digestSql)===before,'HTTP reads preserve production, stock, WIP, Maintenance, downtime, Loss and frozen shift data');
 ok(await required('select enabled from private.maintenance_planning_activation')==='f','local Maintenance activation remains unchanged');
 await writeFile(join(output,'api-integration.json'),JSON.stringify({checks:results.length,results,http:evidence,sqlCalls,limits:'Actual GET/authorization + local PostgreSQL over HTTP; local session/transport adapter, not Supabase GoTrue/PostgREST.'},null,2));
 console.log(`PASS ${results.length} HTTP/SQL integration checks; ${sqlCalls} real read-only SQL RPC calls. GoTrue/PostgREST not tested.`);
}finally{await new Promise(done=>server.close(done));sessions.clear();delete globalThis.__shiftWorkLocalDb;}
