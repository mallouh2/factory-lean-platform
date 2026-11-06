import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
const bundle=await build({entryPoints:['src/features/ProductionStartReadiness.tsx'],bundle:true,platform:'node',format:'cjs',jsx:'automatic',write:false,external:['react','react-dom'],logLevel:'silent'});
const module={exports:{}};new Function('require','module','exports',bundle.outputFiles[0].text)(createRequire(import.meta.url),module,module.exports);
const Control=module.exports.default,en=JSON.parse(readFileSync('src/locales/en.json')),ar=JSON.parse(readFileSync('src/locales/ar.json'));
test('unverified readiness renders a disabled Start, not an optimistic physically-ready claim',()=>{
 for(const [lang,words] of [['en',en],['ar',ar]]) {
  const html=renderToStaticMarkup(createElement(Control,{item:'item',busy:false,onStart:async()=>{},lang,t:k=>words[k]||k,
   snapshot:{factory:{id:'factory'},fetchedAt:'now'},can:()=>true}));
  assert.match(html,/disabled=""/);assert.ok(!html.includes(words.productionPhysicallyReady));assert.match(html,/role="status"/);
 }
});
test('view-only staff receive readiness information without a Start action',()=>{
 const html=renderToStaticMarkup(createElement(Control,{item:'item',busy:false,onStart:async()=>{},lang:'en',t:k=>en[k]||k,
   snapshot:{factory:{id:'factory'},fetchedAt:'now'},can:()=>false}));
 assert.ok(!html.includes(en.startProduction));assert.match(html,/role="status"/);
});
test('shared readiness reader is scoped to exact factory/item and checks again after Start',()=>{
 const code=readFileSync('src/features/ProductionStartReadiness.tsx','utf8');
 assert.match(code,/read.data\?\.factory===s.factory\?\.id && read.data\?\.item===item/);
 assert.match(code,/finally\{read.reload\(\);\}/);assert.match(code,/!data.queue_ready \|\| Boolean\(blocker\)/);
});
test('Floor separates queue readiness and uses protected preparation control',()=>{
 const code=readFileSync('src/features/FactoryFloorV2.tsx','utf8');assert.match(code,/t\("productionQueueReady"\)/);assert.match(code,/<ProductionStartReadiness/);
 assert.match(code,/onStart=\{\(\)=>executeItem\("start_product_item",String\(item.id\)\)\}/);
});
test('readiness labels and explicit blocker reasons have EN/AR parity',()=>{
 for(const k of Object.keys(en).filter(k=>k.startsWith('productionReadiness') || k==='productionQueueReady' || k==='productionPhysicallyReady')) {
  assert.ok(ar[k],k);assert.notEqual(en[k],ar[k],k);
 }
});
