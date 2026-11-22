import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';
const require=createRequire(import.meta.url),id='12345678-1234-1234-1234-123456789abc';
const bundles={};
for(const name of ['quality','data','manufactured-output'])bundles[name]=(await build({entryPoints:[`src/app/api/${name}/route.ts`],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'local-auth-fixture',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}}]})).outputFiles[0].text;
function route(name,{error=null,denied=false,expired=false}={}){
 const calls=[],auth=[],mod={exports:{}};const db={rpc:async(n,args)=>{calls.push({n,args});return {data:{rows:[]},error};}};
 new Function('require','module','exports',bundles[name])(n=>n==='fixture:auth'?{authenticatedClient:async()=>{if(expired)throw Error('unauthorized');return{db,user:{id}};},verifyOrigin(){},safeError:()=>({error:'error'}),authorize:async(factory,module,action)=>{auth.push({factory,module,action});if(typeof denied==='function'?denied(module,action):denied)throw Error('permission_denied');return{db,user:{id}};}}:require(n),mod,mod.exports);
 return{...mod.exports,calls,auth};
}
test('Quality reader requires a confirmed session and preserves authentication error status',async()=>{
 const r=route('quality',{expired:true}),response=await r.GET(new NextRequest(`http://localhost/api/quality?factory=${id}`));assert.equal(response.status,401);assert.equal(r.calls.length,0);
});
test('Quality reader rejects invalid IDs/pages before calling any database RPC',async()=>{
 for(const query of [`factory=bad`,`factory=${id}&page=NaN`,`factory=${id}&page=0`,`factory=${id}&entry=other`,`factory=${id}&selected=bad`,`factory=${id}&mode=sources&product=bad`]){
  const r=route('quality'),response=await r.GET(new NextRequest('http://localhost/api/quality?'+query));assert.equal(response.status,400);assert.equal(r.calls.length,0);
 }
});
test('Reason reader forwards active-only bilingual search, page and retained selection',async()=>{
 const r=route('quality');await r.GET(new NextRequest(`http://localhost/api/quality?factory=${id}&mode=reasons&active_only=true&page=2&selected=${id}&search=${encodeURIComponent('سبب')}`));
 assert.deepEqual(r.calls,[{n:'quality_read',args:{factory:id,query:{mode:'reasons',active_only:'true',page:2,selected:id,search:'سبب'}}}]);
});
test('Source reader passes tenant, exact source context and request quantity reference to its protected RPC',async()=>{
 const r=route('quality');await r.GET(new NextRequest(`http://localhost/api/quality?factory=${id}&mode=sources&product=${id}&unit=meter&material_request=${id}`));
 assert.deepEqual(r.calls,[{n:'finished_source_stock',args:{factory:id,product:id,unit:'meter',sales_line:null,entry:null,page:1,material_request:id}}]);
});
test('Quality reader failures distinguish permission, missing context and transient failure without leaking SQL',async()=>{
 for(const [code,status]of [['42501',403],['P0002',404],['XX000',503]]){
  const r=route('quality',{error:{code,message:'private SQL and credentials must never reach browser'}}),response=await r.GET(new NextRequest(`http://localhost/api/quality?factory=${id}`));assert.equal(response.status,status);assert.ok(!JSON.stringify(await response.json()).includes('private SQL'));assert.match(response.headers.get('Cache-Control'),/no-store/);
 }
});
test('Quality POST denies missing per-person create permission before RPC',async()=>{
 const r=route('data',{denied:(module,action)=>module==='quality'&&action==='create'});const response=await r.POST(new NextRequest('http://localhost/api/data',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({command:'quality_command',args:{factory:id,request_id:id,operation:'reject',payload:{source:id,reason:id,quantity:'2',disposition:'SCRAP',actual_scrap_kg:'.7',physically_identified:true}}})}));
 assert.ok(response.status>=400);assert.equal(r.calls.length,0);
});

test('manufactured Quality approval and edit retain the protected command and exact revision',async()=>{
 for(const [revision,quantity,rejected,actual_rejected_kg] of [[1,'2','0','0'],[2,'1.75','0.25','0.5']]){
  const args={factory:id,target:id,request_id:id,operation:'QUALITY',expected_revision:revision,
   payload:{groups:[{id,quantity,released:quantity,missing_operations:[]}],total:'2',rejected,actual_rejected_kg,reason:'Measured output confirmed'}};
  const post=()=>new NextRequest('http://localhost/api/manufactured-output',{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({command:'manufactured_output_command',args})});
  const allowed=route('manufactured-output');
  assert.equal((await allowed.POST(post())).status,200);
  assert.deepEqual(allowed.calls,[{n:'manufactured_output_command',args}]);

  const denied=route('manufactured-output',{error:{code:'42501',message:'permission_denied'}});
  const response=await denied.POST(post());
  assert.equal(response.status,403);
  assert.deepEqual(await response.json(),{error:'permissionError'});
 }
});
