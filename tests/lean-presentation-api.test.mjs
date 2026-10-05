import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
const require=createRequire(import.meta.url),factory='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const code=(await build({entryPoints:['src/app/api/lean/route.ts'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'test-auth',external:true}));}}]})).outputFiles[0].text;
async function call({params='',rows=[],events=[],entries=[],tables={},denied=false,changeRevision=false}={}){
 const calls=[],tableCalls=[],authCalls=[],m={exports:{}};
 const db={rpc:async(name,args)=>{calls.push(args);let source=args.query.mode==='problem_aggregates'?rows:args.query.mode==='analysis_occurrences'?events:args.query.mode==='entries'?entries:[];const page=args.query.page||1;return{data:{rows:source.slice((page-1)*25,page*25),total:source.length,summary:{loss_minutes:null},source_revision:changeRevision&&calls.length>1?'changed':'same'},error:null};},from(table){const q={table};const chain={select(columns){q.columns=columns;return chain;},eq(key,value){q.key=key;q.value=value;return chain;},order(key){q.order=key;return chain;},async range(start,end){tableCalls.push({...q,start,end});return{data:(tables[table]||[]).slice(start,end+1),error:null};}};return chain;}};
 new Function('require','module','exports',code)(name=>name==='test-auth'?{authenticatedClient:async()=>({db}),authorize:async(...args)=>{authCalls.push(args.slice(0,3));if(denied)throw{code:'42501'};},verifyOrigin(){}}:require(name),m,m.exports);
 const response=await m.exports.GET(new NextRequest('http://localhost:3000/api/lean?factory='+factory+'&from=2026-10-01T00:00:00Z&to=2026-10-04T00:00:00Z'+params));return{status:response.status,body:await response.json(),calls,tableCalls,authCalls};
}
const rows=Array.from({length:50},(_,i)=>({mechanism:'downtime',machine_id:'M'+i,cause_id:'C'+i,products:[],frequency:i+1,loss_minutes:50-i,scrap_kg:0,missing_scrap:0}));
test('Lean API attention uses complete eligible population on later pages, before sort/page slicing',async()=>{
 const r=await call({rows,params:'&sort=frequency&direction=asc&page=2'});assert.equal(r.status,200);assert.equal(r.body.total,50);assert.equal(r.body.rows.length,25);assert.equal(r.body.rows.filter(x=>x.attention.frequency).length,10);assert.equal(r.body.rows.filter(x=>x.attention.loss).length,0);assert.deepEqual(r.authCalls,[[factory,'lean','view']]);assert.equal(r.tableCalls.length,0);
});
test('initiative filtering precedes relative attention and leaves unknown loss unknown',async()=>{
 const r=await call({rows:rows.map((x,i)=>({...x,loss_minutes:null,initiative:i>44?{verified_at:'2026-10-03'}:null})),params:'&initiative_status=VERIFIED'});
 assert.equal(r.status,200);assert.equal(r.body.total,5);assert.equal(r.body.rows.filter(x=>x.attention.frequency).length,1);assert.equal(r.body.summary.loss_minutes,null);
});
test('linked Scrap assessment reads scoped RLS sources deterministically and preserves approved-standard behavior',async()=>{
 const row={...rows[0],cause_id:'C',scrap_kg:4,products:['P']};
 const r=await call({rows:[row],events:[{event_id:'D',mechanism:'downtime',machine_id:row.machine_id,cause_id:'C',product_id:'P',occurred_at:'2026-10-02'}],entries:[{id:'E',product_id:'P',work_center_id:row.machine_id,created_at:'2026-10-02',effective_scrap_kg:4,effective_startup_kg:0,produced_weight_kg:100,running_standard_percent:3}],tables:{lean_scrap_events:[{entry_id:'E',downtime_id:'D',approved_cause_id:'C',occurred_at:'2026-10-02'}]}});
 assert.equal(r.status,200);assert.equal(r.body.rows[0].attention.scrap,true);assert.equal(r.tableCalls.length,2);assert.ok(r.tableCalls.every(x=>x.key==='factory_id'&&x.value===factory&&x.order==='id'));
});
test('Lean presentation fails closed for denied authorization and changing sources',async()=>{
 const denied=await call({rows,denied:true});assert.equal(denied.status,403);assert.equal(denied.calls.length,0);
 const changed=await call({rows,changeRevision:true});assert.notEqual(changed.status,200);assert.ok(!changed.body.rows);
});
