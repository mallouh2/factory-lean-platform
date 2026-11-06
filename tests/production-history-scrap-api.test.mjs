import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
const factory='11111111-1111-4111-8111-111111111111',entry='22222222-2222-4222-8222-222222222222';
let allowed=true,signedIn=true,failure=false,calls=[];
globalThis.__historyScrapAuth={
 authenticatedClient:async()=>{if(!signedIn)throw Error('unauthorized');return {db:{rpc:async(name,args)=>{calls.push({name,args});return {data:{scrap_kg:'15.1234567890123456789'},error:failure?Error('unavailable'):null};}}};},
 authorize:async(f,module,action)=>{assert.equal(f,factory);assert.equal(module,'orders');assert.equal(action,'view');if(!allowed)throw Error('permission_denied');},
 safeError:()=>({error:'denied'}),
};
const compiled=await build({entryPoints:['src/app/api/production-history/route.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',logLevel:'silent',plugins:[{name:'auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'auth',namespace:'test'}));b.onLoad({filter:/.*/,namespace:'test'},()=>({contents:'export const {authenticatedClient,authorize,safeError}=globalThis.__historyScrapAuth;'}));}}]});
const m={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
const get=(id=entry)=>m.exports.GET(new NextRequest(`http://localhost/api/production-history?factory=${factory}&scrap_total_entry=${id}&page=9&product=unrelated`));
test('scoped total is one authorized read, ignores table filters/pages, preserves exact decimal text',async()=>{
 calls=[];const response=await get();assert.equal(response.status,200);assert.equal((await response.json()).scrap_kg,'15.1234567890123456789');assert.equal(response.headers.get('cache-control'),'private, no-store');assert.deepEqual(calls,[{name:'production_history_product_scrap',args:{factory,entry}}]);assert.deepEqual(Object.keys(m.exports),['GET']);
});
test('invalid entry cannot reach SQL',async()=>{calls=[];assert.equal((await get('not-a-uuid')).status,403);assert.equal(calls.length,0);});
test('missing session and denied Orders view disclose nothing and never call the aggregate',async()=>{
 try{calls=[];signedIn=false;assert.equal((await get()).status,403);signedIn=true;allowed=false;assert.equal((await get()).status,403);assert.equal(calls.length,0);}finally{signedIn=true;allowed=true;}
});
test('unavailable reader fails closed without fallback to table totals',async()=>{try{failure=true;const response=await get();assert.equal(response.status,403);assert.ok(!JSON.stringify(await response.json()).includes('scrap_kg'));}finally{failure=false;}});
