import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
import {requestOriginLabel,internalReasonValid} from '../src/utils/request-origin.mjs';
const require=createRequire(import.meta.url);
const bundle=await build({entryPoints:['src/components/RequestOrigin.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'});
const mod={exports:{}};
new Function('require','module','exports',bundle.outputFiles[0].text)(require,mod,mod.exports);
test('origin labels distinguish three real origins and unknown legacy without invented history',()=>{
 assert.equal(requestOriginLabel('SALES_PRODUCTION'),'customerDemand');
 assert.equal(requestOriginLabel('STOCK_REPLENISHMENT'),'stockReplenishment');
 assert.equal(requestOriginLabel('INTERNAL_PRODUCTION'),'internalProduction');
 for(const type of [null,undefined,'unknown'])assert.equal(requestOriginLabel(type),'legacyRequest');
});
test('internal reason validation handles whitespace and the trimmed length boundary',()=>{
 for(const reason of ['', '\t\n ', 'x'.repeat(2001), null])assert.equal(internalReasonValid(reason),false);
 for(const reason of [' Trial ', 'x'.repeat(2000)])assert.equal(internalReasonValid(reason),true);
});
test('Planning inspection renders persisted internal creator, reason and server timestamp in EN/AR',()=>{
 const request={request_type:'INTERNAL_PRODUCTION',requested_by_name:'Nasser Al Kuwari',notes:'Engineering trial',created_at:'2026-10-02T15:00:00Z'};
 for(const [lang,dictionary] of [['en',en],['ar',ar]]){
  const html=renderToStaticMarkup(createElement(mod.exports.default,{request,t:key=>dictionary[key]||key,lang,zone:'UTC',details:true}));
  for(const text of [dictionary.internalProduction,dictionary.internalCreatedBy,dictionary.internalProductionReason,dictionary.internalCreatedAt,'Nasser Al Kuwari','Engineering trial'])assert.ok(html.includes(text));
  assert.ok(!html.includes(dictionary.customerDemand));
  assert.ok(!html.includes(dictionary.stockReplenishment));
 }
});

const apiBundle=await build({entryPoints:['src/app/api/data/route.ts'],bundle:true,platform:'node',format:'cjs',packages:'external',external:['@/services/authorization'],write:false,logLevel:'silent'});
function apiHarness(allowed=true){
 const calls=[];const context={user:{id:'authenticated-person'},db:{rpc:async(name,args)=>{calls.push({name,args});return {data:'request-id',error:null};}}};
 const api={exports:{}};
 const auth={verifyOrigin:()=>{},authenticatedClient:async()=>context,authorize:async()=>{if(!allowed)throw new Error('permission_denied');return context;},safeError:e=>({error:e.message==='permission_denied'?'permissionError':'error'})};
 new Function('require','module','exports',apiBundle.outputFiles[0].text)(name=>name==='@/services/authorization'?auth:require(name),api,api.exports);
 return {calls,post:args=>api.exports.POST({headers:{get:()=>null},json:async()=>({command:'create_production_request',args})})};
}
const validArgs={factory:'factory',request_name:'Trial',request_priority:'normal',request_required_by:null,request_notes:'Engineering trial',request_items:[{product_id:'product',quantity:7,unit:'meter'}]};
test('manual API rejects forged Sales/Stock origin and browser creator identity before any database call',async()=>{
 for(const extra of [{request_type:'SALES_PRODUCTION'},{request_type:'STOCK_REPLENISHMENT'},{requested_by:'forged-person'},{requested_by_name:'Forged creator'},{created_at:'2000-01-01'}]){
  const api=apiHarness();const response=await api.post({...validArgs,...extra});
  assert.equal(response.status,400);assert.equal(api.calls.length,0);
 }
});
test('manual API requires explicit person authority and preserves the authorized six-argument RPC contract',async()=>{
 const denied=apiHarness(false);const response=await denied.post(validArgs);
 assert.equal((await response.json()).error,'permissionError');assert.equal(denied.calls.length,0);
 const allowed=apiHarness();assert.equal((await allowed.post(validArgs)).status,200);
 assert.deepEqual(allowed.calls,[{name:'create_production_request',args:validArgs}]);
});
