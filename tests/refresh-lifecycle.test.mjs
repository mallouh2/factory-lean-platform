import test from 'node:test';import assert from 'node:assert/strict';
import {build} from 'esbuild';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),flush=()=>new Promise(resolve=>setImmediate(resolve));
async function harness(file,name){
 const source=(await build({entryPoints:[file],bundle:true,platform:'node',format:'cjs',packages:'external',write:false})).outputFiles[0].text;
 const states=[],effects=[];let at=0,ea=0,pending=[];
 const react={useState(initial){const i=at++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},
  useEffect(run,deps){const i=ea++,old=effects[i];if(!old||deps.some((v,n)=>!Object.is(v,old.deps[n]))){pending.push(()=>{old?.cleanup?.();effects[i]={deps,cleanup:run()};});}}};
 const mod={exports:{}};new Function('require','module','exports',source)(n=>n==='react'?react:require(n),mod,mod.exports);
 return{render(...args){at=0;ea=0;const value=mod.exports[name](...args);for(const effect of pending.splice(0))effect();return value;},dispose(){effects.forEach(e=>e.cleanup?.());}};
}
for(const [file,name] of [['src/features/useFulfillment.ts','useFulfillment'],['src/features/useSupply.ts','useSupply']])
 test(name+' keeps loaded data during real refetch lifecycle, aborts stale queries and clears denied data',async()=>{
  const oldFetch=globalThis.fetch,requests=[];globalThis.fetch=(url,options)=>new Promise(resolve=>requests.push({url,options,resolve}));
  const h=await harness(file,name);let snapshot={user:{id:'owner'},factory:{id:'factory'},fetchedAt:'1'};
  const render=()=>h.render(snapshot,'inventory',1,true);
  try{
   render();let v=render();assert.equal(v.loading,true);assert.equal(v.refreshing,false);assert.equal(requests.length,1);
   requests[0].resolve({ok:true,json:async()=>({rows:[{id:'retained'}]})});await flush();const first=render().data;assert.equal(first.rows[0].id,'retained');
   snapshot={...snapshot,fetchedAt:'2'};render();v=render();assert.equal(v.data,first);assert.equal(v.loading,false);assert.equal(v.busy,true);assert.equal(v.refreshing,true);assert.equal(requests.length,2);assert.equal(requests[0].options.signal.aborted,true);
   requests[1].resolve({ok:false,json:async()=>({error:'dataWarning'})});await flush();v=render();assert.equal(v.data,first);assert.equal(v.error,'dataWarning');
   snapshot={...snapshot,fetchedAt:'3'};render();requests[2].resolve({ok:false,json:async()=>({error:'permissionError'})});await flush();v=render();assert.equal(v.data,null);assert.equal(v.error,'permissionError');
   snapshot={...snapshot,factory:{id:'other'},fetchedAt:'4'};assert.equal(render().data,null);assert.equal(requests[2].options.signal.aborted,true);
  }finally{h.dispose();globalThis.fetch=oldFetch;assert.equal(requests.at(-1).options.signal.aborted,true);}
 });

test('Planning metadata keeps old rows during refresh, blocks partial sets, aborts on scope change and clears denial',async()=>{
 const oldFetch=globalThis.fetch,requests=[];globalThis.fetch=(url,options)=>new Promise(resolve=>requests.push({url,options,resolve}));
 const h=await harness('src/features/usePlanningWork.ts','usePlanningWork');let props={snapshot:{user:{id:'owner'},factory:{id:'factory'},fetchedAt:'1'},can:()=>true};
 const render=()=>h.render(props),item={item_id:'10000000-0000-0000-0000-000000000001',choice:'COMPLETE',held:false,retired:false,capable_lines:[]};
 const page={available:true,work:[item],total:1,context_hash:'fixed',has_more:false};
 try{render();assert.equal(render().complete,false);requests[0].resolve({ok:true,json:async()=>page});await flush();const loaded=render();assert.equal(loaded.complete,true);assert.equal(loaded.data.length,1);
 props={...props,snapshot:{...props.snapshot,fetchedAt:'2'}};render();const pending=render();assert.equal(pending.complete,false);assert.equal(pending.data,loaded.data);assert.equal(requests.length,2);
 requests[1].resolve({ok:false,json:async()=>({error:'permissionError'})});await flush();assert.deepEqual(render().data,[]);assert.equal(render().complete,false);
 props={...props,snapshot:{...props.snapshot,factory:{id:'other'}}};assert.deepEqual(render().data,[]);assert.equal(requests[1].options.signal.aborted,true);
 }finally{h.dispose();globalThis.fetch=oldFetch;assert.equal(requests.at(-1).options.signal.aborted,true);}
});
