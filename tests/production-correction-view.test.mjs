import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
const require=createRequire(import.meta.url),react=require('react');
const compiled=await build({entryPoints:['src/features/ProductionCorrections.tsx'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',plugins:[{name:'reads',setup(b){b.onResolve({filter:/(useHistoryData|useCorrectionAction)$/},()=>({path:'reads',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const useHistoryData=()=>({data:null,loading:false,error:""});export const useCorrectionAction=()=>({ready:true,busy:false,error:"",pending:null});'}));}}]});
for(const language of ['en','ar'])for(const status of ['PENDING','APPROVED'])test(language+' '+status+' renders the correct comparison basis, without applying newer facts to old requests',()=>{
 const original={entry_id:'entry',item_id:'item',request_id:'order',product_id:'product',unit:'meter',good:'2',scrap_kg:'0.125',unfinished:'0'},current={...original,good:'1.5',scrap_kg:'0.3'};
 const row={id:'request',requested_by:'actor',requested_at:'2026-10-20T09:00:00Z',status,original_values:original,current_values:current,proposed:{good:'1.5',scrap_kg:'0.15',reason:'Checked sample'},applied_values:status==='APPROVED'?{...current,scrap_kg:'0.15'}:null};
 let index=0;const fake={...react,useEffect:()=>{},useState:init=>{const i=index++;return [i===0?status:i===7?{scope:'actor|factory|'+status,page:{rows:[row],total:1,next_cursor:null}}:typeof init==='function'?init():init,()=>{}];}};
 const m={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(name=>name==='react'?fake:require(name),m,m.exports);
 const words=language==='ar'?ar:en,html=renderToStaticMarkup(createElement(m.exports.default,{snapshot:{user:{id:'actor'},factory:{id:'factory',timezone:'UTC'},tables:{}},t:key=>words[key]||key,lang:language,can:()=>true}));
 assert.equal((html.match(/<th\b/g)||[]).length,6);assert.ok(!html.includes('<td>Actions'));
 if(status==='APPROVED'){assert.ok(html.includes('0.125'));assert.ok(html.includes('0.15'));assert.ok(!html.includes('0.3'));}
 else{assert.ok(html.includes('0.3'));assert.ok(html.includes('0.15'));assert.ok(!html.includes('0.125'));}
 assert.ok(html.includes(language==='ar'?'dir="rtl"':'dir="ltr"'));
});
