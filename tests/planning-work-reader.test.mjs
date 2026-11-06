import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {collectPlanningWork} from '../src/utils/planning-work-reader.mjs';
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const row=n=>({item_id:id(n),choice:'COMPLETE',origin_code:'PO-original',held:false,retired:false,capable_lines:[id(999)]});
const all=Array.from({length:205},(_,n)=>row(n));
const page=(offset,extra={})=>({available:true,work:all.slice(offset,offset+100),context_hash:'same',total:205,has_more:offset+100<205,...extra});
test('all205 active completion/replacement metadata rows load independently of source pages',async()=>{
 const cursors=[];let n=0;const work=await collectPlanningWork(async after=>{cursors.push(after);return page(n++*100);});
 assert.deepEqual(work,all);assert.deepEqual(cursors,[null,id(99),id(199)]);
});
for(const [name,change] of [
 ['changing context',d=>({...d,context_hash:'changed'})],['changing count',d=>({...d,total:204})],
 ['duplicate cursor',d=>({...d,work:[row(99)]})],['truncated last page',d=>({...d,work:[],has_more:false})],
 ['unknown work kind',d=>({...d,work:[{...row(100),choice:'UNKNOWN'}]})],
 ['missing hold state',d=>({...d,work:[{...row(100),held:undefined}]})]
])test(name+' never becomes a complete usable metadata set',async()=>{
 let n=0;await assert.rejects(collectPlanningWork(async()=>n++===0?page(0):change(page(100))));
});
test('disabled gate is explicit and cannot disguise partial work',async()=>{
 assert.deepEqual(await collectPlanningWork(async()=>({available:false,work:[],total:0,context_hash:'disabled',has_more:false})),[]);
 await assert.rejects(collectPlanningWork(async()=>page(0,{available:false})));
});
const require=createRequire(import.meta.url),{NextRequest}=require('next/server');
const bundle=(await build({entryPoints:['src/app/api/manufactured-output/route.ts'],bundle:true,platform:'node',format:'cjs',write:false,packages:'external',plugins:[{name:'auth',setup(b){b.onResolve({filter:/^@\/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}}]})).outputFiles[0].text;
function api(error){const calls=[],mod={exports:{}};new Function('require','module','exports',bundle)(n=>n==='fixture:auth'?{authenticatedClient:async()=>({db:{rpc:async(name,args)=>{calls.push({name,args});return error?{error}:{data:page(0)};}}})}:require(n),mod,mod.exports);return{...mod.exports,calls};}
test('metadata API uses only protected reader and private no-store',async()=>{
 const a=api(),r=await a.GET(new NextRequest('http://local/api/manufactured-output?'+new URLSearchParams({factory:id(1),mode:'planning',after:id(3)})));
 assert.equal(r.status,200);assert.deepEqual(a.calls,[{name:'manufactured_planning_work_read',args:{factory:id(1),after_id:id(3)}}]);assert.match(r.headers.get('Cache-Control'),/private, no-store/);
});
test('metadata API rejects invalid mixed parameters before reaching SQL',async()=>{
 for(const extra of[{target:id(3)},{work:id(3)},{page:'1'},{after:'invalid'}]){
  const a=api(),r=await a.GET(new NextRequest('http://local/api/manufactured-output?'+new URLSearchParams({factory:id(1),mode:'planning',...extra})));
  assert.equal(r.status,422);assert.equal(a.calls.length,0);
 }
});
test('metadata permission denial discloses no work',async()=>{
 const r=await api({code:'42501'}).GET(new NextRequest('http://local/api/manufactured-output?factory='+id(1)+'&mode=planning'));
 assert.equal(r.status,403);assert.equal((await r.json()).work,undefined);
});
