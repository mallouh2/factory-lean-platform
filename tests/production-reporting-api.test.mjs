import test from 'node:test';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {parseReportingQuery,exactReportingJson,reportingFetch,reportingResponse} from '../src/utils/production-reporting.mjs';
import {parseHistoryQuery} from '../src/utils/production-history.mjs';
import {NextRequest} from 'next/server.js';

const f='11111111-1111-4111-8111-111111111111',entry='22222222-2222-4222-8222-222222222222';
const query=(suffix='')=>new URLSearchParams(`factory=${f}&reporting_version=3${suffix}`);
const args=(suffix='')=>parseReportingQuery(query(suffix));
const envelope=(changes={})=>({contract_version:'3',evidence_contract_version:'2',factory_id:f,mode:'entries',time_basis:'recorded',
  from_at:'2026-01-01T00:00:00+00:00',to_at:'2026-01-02T00:00:00+00:00',unknown_scope:'RECORDED_WINDOW',source_revision:'9007199254740993',
  total:'0',page_size:'50',complete:true,attribution_complete:true,allocation_complete:true,unknown_attribution_records:'0',rows:[],next_cursor:null,...changes});
const cursor={version:1,factory:f,query_hash:'a'.repeat(64),source_revision:'9007199254740993',after:'key',from_at:'2026-01-01T00:00:00+00:00',to_at:'2026-01-02T00:00:00+00:00'};
const encoded=x=>Buffer.from(JSON.stringify(x)).toString('base64url');

test('explicit opt-in, deterministic SQL defaults, normalized UUID filters',()=>{
  assert.deepEqual(args(),{factory:f,filters:{reporting_version:3,mode:'entries',time_basis:'recorded',page_size:50},sort_key:'date',sort_direction:'desc',page:1});
  assert.equal(args(`&product=${entry}&line=${entry}&entry=${entry}`).filters.entry,entry);
});
for(const suffix of ['&request='+entry,'&item='+entry,'&sort=date','&mode=unknown','&time_basis=machine','&factory='+f,'&page_size=0','&page_size=101','&page_size=1.0','&page_size=01','&product=bad','&occurrence=A'.repeat(2),'&mode=corrections','&from=2026-02-30','&from=2026-02-02&to=2026-02-01','&from=2026-01-01&to_at=2026-01-02T00:00:00Z','&from_at=2026-01-01T00:00:00','&from_at=2026-01-02T00:00:00Z&to_at=2026-01-01T00:00:00Z','&from=2020-01-01&to=2026-01-01','&cursor=%%%']) {
  test(`reject unsupported/malformed query ${suffix.slice(0,65)}`,()=>assert.throws(()=>args(suffix),e=>e.code==='22023'));
}
test('reject missing version and factory',()=>{
  for(const q of [new URLSearchParams({factory:f}),new URLSearchParams({reporting_version:'3'}),new URLSearchParams({factory:f,reporting_version:'2'})]) assert.throws(()=>parseReportingQuery(q));
});
test('bounded opaque cursor preserves exact revision',()=>assert.equal(args('&cursor='+encoded(cursor)).filters.cursor.source_revision,'9007199254740993'));
for(const change of [{factory:entry},{version:2},{source_revision:9007199254740992},{after:''},{after:'x'.repeat(1001)},{extra:true},{query_hash:'invalid'}])
  test(`invalid cursor ${Object.keys(change)[0]} ${JSON.stringify(change).slice(0,40)}`,()=>assert.throws(()=>args('&cursor='+encoded({...cursor,...change}))));

for(const value of ['0','-0','1.234567890123456789','-0.00000000000000000001','9007199254740993','1e-100','1.234567890123456789e+40'])
  test(`lexical exact number ${value}`,()=>assert.equal(JSON.parse(exactReportingJson(`{"x":${value}}`)).x,value));
test('numeric-looking labels, escaped quotes and Arabic remain strings',()=>{
  const text='{"text":"123 \\" 4","arabic":"وردية 123","list":[0,null,true]}';
  const result=JSON.parse(exactReportingJson(text));assert.equal(result.text,'123 " 4');assert.equal(result.arabic,'وردية 123');assert.deepEqual(result.list,['0',null,true]);
});
for(const raw of ['{"x":NaN}','{"x":01}','not json','{"x":1.}','[1,]'])test('invalid JSON '+raw,()=>assert.throws(()=>exactReportingJson(raw)));
test('oversized transport fails closed',()=>assert.throws(()=>exactReportingJson(' '.repeat(2097153))));
test('installed Supabase RPC client preserves raw correction decimals and bigint',async()=>{
  let called=0;
  const fetcher=reportingFetch(async(input,init)=>{called++;assert.equal(init.method,'GET');assert.match(String(input),/\/rest\/v1\/rpc\/production_history/);return new Response('{"contract_version":3,"previous_good":10.1234567890123456789,"source_revision":9007199254740993}',{status:200});});
  const db=createClient('http://127.0.0.1:1','local-fixture-key',{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:fetcher}});
  const {data,error}=await db.rpc('production_history',{filters:JSON.stringify({reporting_version:3})},{get:true});
  assert.equal(error,null);assert.equal(called,1);assert.equal(data.previous_good,'10.1234567890123456789');assert.equal(data.source_revision,'9007199254740993');
});
test('transport leaves auth, legacy readers and SQL errors unchanged',async()=>{
  for(const [url,status] of [['/auth/v1/user',200],['/rest/v1/rpc/production_history?filters=%7B%7D',200],['/rest/v1/rpc/production_history?filters=%7B%22reporting_version%22%3A3%7D',403]]){
    const raw='{"x":3}';const result=await reportingFetch(async()=>new Response(raw,{status}))('http://127.0.0.1'+url,{method:'GET'});assert.equal(await result.text(),raw);
  }
});
test('empty page retains honest completeness and exact revision',()=>{
  const result=reportingResponse(envelope(),args());assert.deepEqual(result.rows,[]);assert.equal(result.total,0);assert.equal(result.source_revision,'9007199254740993');assert.equal(result.next_cursor,null);
});
for(const change of [{contract_version:4},{factory_id:entry},{source_revision:9007199254740993},{page_size:101},{complete:false},{total:null},{rows:[{}]},{allocation_complete:null},{evidence_contract_version:null}])
  test('malformed reporting payload '+Object.keys(change)[0],()=>assert.throws(()=>reportingResponse(envelope(change),args())));
test('summary preserves unknown quantities, units and no invented zero',()=>{
  const row={occurrence_key:null,occurrence:null,product_id:entry,line_id:entry,unit:'meter',records:'1',attribution_complete:false,allocation_complete:false,unit_known:true,
    unknown_scrap_records:'0',unknown_attribution_records:'1',scrap_rate_basis:'UNKNOWN',good:null,accepted_good:null,declared_good:'10.1234567890123456789',unallocated_good:'10.1234567890123456789',declared_scrap_kg:'0.1234567890123456789',unallocated_scrap_kg:'0.1234567890123456789',scrap_kg:null,wip:'0',reviewed_scrap_kg:null,scrap_rate:null};
  const result=reportingResponse(envelope({mode:'summary',rows:[row],total:'1',attribution_complete:false,allocation_complete:false}),args('&mode=summary'));
  assert.equal(result.rows[0].good,null);assert.equal(result.rows[0].declared_good,row.declared_good);assert.equal(result.rows[0].unit,'meter');
  assert.throws(()=>reportingResponse(envelope({mode:'summary',rows:[{...row,declared_good:10.123}],total:1}),args('&mode=summary')));
});
test('continuation is opaque and query-bound metadata remains exact',()=>{
  const audit={id:entry,factory_id:f,entry_id:entry,reason:'Correction',created_by:entry,created_at:cursor.from_at,request_id:entry,overproduction_confirmed:false,shift_changed:false,previous_shift_id:null,corrected_shift_id:null,previous_remaining_work:null,corrected_remaining_work:null,previous_occurrence_key:null,corrected_occurrence_key:null,previous_period_start:null,previous_period_end:null,corrected_period_start:null,corrected_period_end:null,attribution_changed:false,previous_good:'10.1234567890123456789',previous_scrap:'0',corrected_good:'9.1234567890123456789',corrected_scrap:'0',previous_unfinished:null,corrected_unfinished:null,previous_scrap_kg:'0.1234567890123456789',corrected_scrap_kg:'0.1234567890123456789',previous_startup_kg:null,corrected_startup_kg:null,private_future_field:'must disappear'};
  const request=args('&mode=corrections&entry='+entry+'&page_size=1');
  const result=reportingResponse(envelope({mode:'corrections',page_size:'1',rows:[audit],total:'2',complete:false,next_cursor:cursor}),request);
  assert.equal(result.rows[0].previous_good,audit.previous_good);assert.ok(!('private_future_field' in result.rows[0]));assert.equal(JSON.parse(Buffer.from(result.next_cursor,'base64url')).source_revision,cursor.source_revision);
});
test('legacy parser and protected service retain existing response/supplement behavior',async()=>{
  assert.deepEqual(parseHistoryQuery(new URLSearchParams({request:entry,page:'2'})),{filters:{request:entry},sort_key:'date',sort_direction:'desc',page:2});
  const compiled=await build({entryPoints:['src/services/production-history.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external'});
  const mod={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),mod,mod.exports);
  let calls=0;const db={rpc:async()=>{calls++;return {data:{rows:[{id:entry,good:2}],total:1}};},from:()=>({select:()=>({eq:()=>({in:async()=>{calls++;return {data:[{id:entry,effective_scrap_kg:0.25}]};}})})})};
  const result=await mod.exports.readProductionHistory(db,f,{});assert.equal(calls,2);assert.equal(result.rows[0].good,2);assert.equal(result.rows[0].effective_scrap_kg,0.25);
});

let failure=null,allowed=true,authFailure=null,routeCalls=[];
globalThis.__reportingRouteTestAuth={
  authenticatedClient:async()=>{
    if(authFailure)throw Error(authFailure);
    return {user:{id:f},db:{rpc:async(...params)=>{routeCalls.push(params);return failure==='contract'?{data:{}}:{data:envelope(),error:failure};}}};
  },
  authorize:async()=>{if(!allowed)throw Error('permission_denied');},
};
const compiledRoute=await build({entryPoints:['src/app/api/production-reporting/route.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',
  plugins:[{name:'auth-fixture',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture-auth',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const {authenticatedClient,authorize}=globalThis.__reportingRouteTestAuth;'}));}}]});
const routeModule={exports:{}};new Function('require','module','exports',compiledRoute.outputFiles[0].text)(createRequire(import.meta.url),routeModule,routeModule.exports);
test('actual route uses one bounded GET RPC, no legacy supplements or write exports',async()=>{
  routeCalls=[];const response=await routeModule.exports.GET(new NextRequest('http://localhost/api/production-reporting?'+query()));
  assert.equal(response.status,200);assert.deepEqual(Object.keys(routeModule.exports),['GET']);assert.equal(routeCalls.length,1);
  assert.equal(routeCalls[0][0],'production_history');assert.equal(typeof routeCalls[0][1].filters,'string');assert.deepEqual(routeCalls[0][2],{get:true});
  assert.equal(response.headers.get('cache-control'),'private, no-store');
});
for(const [label,value,status] of [['unauthenticated','auth',401],['permission denied','permission',403],['SQL denial',{code:'42501',message:'internal secret'},403],['SQL invalid query',{code:'22023'},400],['stale cursor',{code:'40001'},409],['unavailable reader',{code:'PGRST202',message:'internal schema'},503],['incompatible payload','contract',503]])
  test('actual route fails closed: '+label,async()=>{
    failure=value==='auth'||value==='permission'?null:value;authFailure=value==='auth'?'unauthorized':null;allowed=value!=='permission';routeCalls=[];
    try{
      const r=await routeModule.exports.GET(new NextRequest('http://localhost/api/production-reporting?'+query()));assert.equal(r.status,status);assert.equal(r.headers.get('cache-control'),'private, no-store');
      const body=await r.text();assert.ok(!body.includes('internal'));if(status===401 || value==='permission')assert.equal(routeCalls.length,0);if(status===409)assert.equal(JSON.parse(body).restart,true);
    }finally{failure=null;authFailure=null;allowed=true;}
  });
