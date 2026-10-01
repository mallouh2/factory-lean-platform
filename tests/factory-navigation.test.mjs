import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {NextRequest} from 'next/server.js';
import {floorSnapshot} from './fixtures/factory-floor.mjs';

const require=createRequire(import.meta.url);
const apiBundle=await build({entryPoints:['src/app/api/data/route.ts'],bundle:true,platform:'node',format:'cjs',
  packages:'external',write:false,logLevel:'silent',plugins:[{name:'mock-auth',setup(b){
    b.onResolve({filter:/services\/authorization$/},()=>({path:'test-auth',external:true}));
  }}]});
const realAuthBundle=await build({entryPoints:['src/services/authorization.ts'],bundle:true,platform:'node',format:'cjs',
  packages:'external',write:false,logLevel:'silent'});
const appBundle=await build({entryPoints:['src/components/FactoryApp.tsx'],bundle:true,platform:'node',format:'cjs',
  packages:'external',write:false,logLevel:'silent',plugins:[{name:'ignore-css',setup(b){
    b.onLoad({filter:/\.css$/},()=>({contents:'export default {}',loader:'js'}));
  }}]});
function loadModule(bundle,resolve=require){
  const module={exports:{}};
  new Function('require','module','exports',bundle.outputFiles[0].text)(resolve,module,module.exports);
  return module.exports;
}
const realAuth=loadModule(realAuthBundle);
async function api({failure=null,stage='factory_snapshot',authError=null}={}){
  const calls=[];const warnings=[];
  const snapshot={factory:{id:'F'},membership:{status:'approved'},permissions:['orders:view'],tables:{}};
  const db={rpc:async(name,args)=>{
    calls.push([name,args]);
    if(name===stage && failure) return {data:null,error:failure};
    return {data:name==='factory_snapshot'?snapshot:{units:[{id:'L'}],technicians:[{id:'T'}]},error:null};
  },from:()=>({select:()=>({eq:()=>({order:async()=>({data:[{id:'SHIFT'}],error:stage==='production_shifts'?failure:null})})})})};
  const route=loadModule(apiBundle,name=>name==='test-auth'?{...realAuth,
    authenticatedClient:async()=>{if(authError)throw authError;return{db,user:{id:'U',email:'test@example.invalid'}};}
  }:require(name));
  const originalWarn=console.warn;
  try{
    console.warn=(...args)=>warnings.push(args);
    const response=await route.GET(new NextRequest('http://localhost:3000/api/data?factory=F'));
    return{status:response.status,body:await response.json(),calls,warnings};
  }finally{console.warn=originalWarn;}
}
test('snapshot timeout returns a refresh failure, not a permission denial or database details',async()=>{
  const result=await api({failure:{code:'57014',message:'canceling statement due to statement timeout'}});
  assert.equal(result.status,503);assert.deepEqual(result.body,{error:'dataWarning'});
  assert.deepEqual(result.calls,[['factory_snapshot',{factory:'F'}]]);
  assert.equal(result.warnings[0][1].stage,'factory_snapshot');
  assert.equal(result.warnings[0][1].code,'57014');
});
test('real database and session authorization failures still reject the read',async()=>{
  assert.deepEqual((await api({failure:{code:'42501',message:'permission_denied'}})).body,{error:'permissionError'});
  assert.equal((await api({failure:{code:'42501',message:'permission_denied'}})).status,403);
  const expired=await api({authError:new Error('unauthorized')});
  assert.equal(expired.status,401);assert.deepEqual(expired.body,{error:'unauthorized'});assert.deepEqual(expired.calls,[]);
});
test('valid snapshot retains Recording and Shift hydration and factory context',async()=>{
  const result=await api();assert.equal(result.status,200);
  assert.deepEqual(result.body.tables.production_recording_units,[{id:'L'}]);
  assert.deepEqual(result.body.tables.production_technicians,[{id:'T'}]);
  assert.deepEqual(result.body.tables.production_shifts,[{id:'SHIFT'}]);
  assert.equal(result.calls[1][0],'production_recording_units');
});
test('dependent read failures identify their stage without exposing internals',async()=>{
  for(const stage of ['production_recording_units','production_shifts']){
    const result=await api({stage,failure:{code:'XX000',message:'internal SQL detail'}});
    assert.equal(result.status,503);assert.deepEqual(result.body,{error:'dataWarning'});
    assert.equal(result.warnings[0][1].stage,stage);
  }
});
function appHarness(lang='en'){
  const snapshot=floorSnapshot('running');snapshot.permissions.push('dashboard:view','factory:view','lines:view');
  const states=[lang,false,'dashboard',snapshot,false,'',false,false,'full',false,null,'',null,null,''];
  let hook=0;let load;
  const react=require('react');
  const App=loadModule(appBundle,name=>name==='react'?{...react,
    useState:initial=>{const i=hook++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;
      return[states[i],value=>{states[i]=typeof value==='function'?value(states[i]):value;}];},
    useEffect:()=>{},useMemo:fn=>fn(),useCallback:fn=>{load=fn;return fn;}
  }:require(name)).default;
  function render(){hook=0;return App();}
  render();
  return{states,snapshot,render,refresh:()=>load()};
}
async function withFetch(response,fn){const original=globalThis.fetch;try{globalThis.fetch=async()=>response;await fn();}finally{globalThis.fetch=original;}}
test('failed refresh preserves the loaded factory and recovery clears only the load warning in EN/AR',async()=>{
  for(const lang of ['en','ar']){
    const app=appHarness(lang);app.states[5]='saved';
    await withFetch({status:503,ok:false,json:async()=>({error:'dataWarning'})},app.refresh);
    assert.equal(app.states[3],app.snapshot);assert.equal(app.states[14],'dataWarning');
    const fresh={...app.snapshot,fetchedAt:'later'};
    await withFetch({status:200,ok:true,json:async()=>fresh},app.refresh);
    assert.equal(app.states[3],fresh);assert.equal(app.states[14],'');assert.equal(app.states[5],'saved');
  }
});
test('real permission denial or expired sign-in discards the inaccessible snapshot',async()=>{
  for(const status of [401,403]){
    const app=appHarness();
    await withFetch({status,ok:false,json:async()=>({error:'permissionError'})},app.refresh);
    assert.equal(app.states[3],null);
    assert.equal(app.states[14],status===401?'':'permissionError');
  }
});
test('normal Factory Floor navigation issues no write command or snapshot request',()=>{
  const app=appHarness();
  function find(node){if(!node||typeof node!=='object')return null;
    if(node.type==='button'&&node.props?.title==='Lines & Machines')return node;
    for(const child of [node.props?.children].flat(Infinity)){const found=find(child);if(found)return found;}return null;}
  const button=find(app.render());assert.ok(button);
  const original=globalThis.fetch;
  try{globalThis.fetch=()=>{throw new Error('navigation must not call an API');};button.props.onClick();}
  finally{globalThis.fetch=original;}
  assert.equal(app.states[2],'lines');assert.equal(app.states[3],app.snapshot);
});
