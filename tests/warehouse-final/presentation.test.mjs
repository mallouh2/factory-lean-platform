import test from 'node:test';import assert from 'node:assert/strict';import{createRequire}from'node:module';import{build}from'esbuild';
import{projectedQuantity}from'../../src/utils/warehouse-presentation.mjs';
import{warehouseRequestRows}from'../../src/utils/warehouse-request-rows.mjs';
import en from '../../src/locales/en.json'with{type:'json'};import ar from '../../src/locales/ar.json'with{type:'json'};
const require=createRequire(import.meta.url),react=require('react');
const bundle=async file=>(await build({entryPoints:[file],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'fixture',setup(b){b.onResolve({filter:/^\.\/ManufacturedOutput$/},()=>({path:'notice-details',external:true}));b.onResolve({filter:/^@\/components\//},args=>({path:args.path,external:true}));}}]})).outputFiles[0].text;
const code=await bundle('src/features/QualityUpdateButton.tsx');
const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];
function notice(lang='en',count=0){let index=0;const states=[],refs=[],m={exports:{}},words=lang==='ar'?ar:en;
 new Function('require','module','exports',code)(name=>name==='react'?{...react,useEffect(){},useRef:v=>refs[index]??=( {current:v}),useState:v=>{const i=index++;if(!(i in states))states[i]=v;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];}}:name==='notice-details'?{OutputDetails:()=>null}:name.startsWith('@/components/')?{__esModule:true,default:()=>null,Dialog:()=>null,formatTime:x=>x}:require(name),m,m.exports);
 const props={snapshot:{factory:{id:'F',timezone:'UTC'},user:{id:'U'}},t:key=>words[key]||key,lang,can:()=>true};
 const nodes=()=>{index=0;return walk(m.exports.default(props));};nodes();
 states[0]={available:true,rows:[{id:'O',revision:'2',notification_revision:'2',unread:true,item_code:'PO-1',product_name:'Pipe',unit:'meter',history:[],recorded:[{quantity:'10',missing_operations:[]}],quality:{groups:[{quantity:'9',missing_operations:[]}],rejected:'1',reason:'Measured defect'}}],unread_count:count,total:1,has_more:false};states[8]=true;
 return{nodes,states};
}
for(const lang of['en','ar'])test('neutral/count-one/count-many notification state; no inline evidence '+lang,()=>{
 for(const count of[0,1,3]){const h=notice(lang,count),nodes=h.nodes(),button=nodes.find(n=>n.type==='button'&&n.props.className.startsWith('quality-updates-button'));
 assert.equal(button.props.className.includes('has-unread'),count>0);assert.equal(nodes.filter(n=>n.type==='article').length,0);button.props.onClick();assert.equal(h.states[2],true);assert.equal(h.states[3],null);assert.equal(h.states[6],'');}
});
test('opening one notice sends only its actor-scoped ACK and retains UUID on unknown response',async()=>{
 const h=notice('en',3),oldFetch=globalThis.fetch,oldStorage=globalThis.sessionStorage,store=new Map(),calls=[];
 globalThis.sessionStorage={setItem:(k,v)=>store.set(k,v),getItem:k=>store.get(k),removeItem:k=>store.delete(k)};
 try{globalThis.fetch=async(_url,init)=>{calls.push(init.body);if(calls.length===1)throw Error('network');return{ok:true,json:async()=>({data:{output_id:'O'}})};};
 h.nodes().find(n=>n.props?.className==='quality-updates-button has-unread').props.onClick();
 const article=h.nodes().find(n=>n.type==='article');walk(article).find(n=>n.type==='button').props.onClick();await new Promise(setImmediate);assert.equal(calls.length,1);
 const retained=h.states[6];assert.equal(JSON.parse(retained).args.operation,'ACKNOWLEDGE');assert.equal(JSON.parse(retained).args.target,'O');
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.retry).props.onClick();await new Promise(setImmediate);assert.equal(calls.length,2);assert.equal(calls[0],calls[1]);assert.equal(h.states[6],'');
 }finally{globalThis.fetch=oldFetch;globalThis.sessionStorage=oldStorage;}
});
test('protected lossless notification response restores only a validated unread count',async()=>{
 const oldFetch=globalThis.fetch;
 try{for(const value of ['3',3,'0',null,'-1','3.5','9007199254740992']){
  const effects=[],states=[],m={exports:{}};let index=0;
  new Function('require','module','exports',code)(name=>name==='react'?{...react,useEffect:effect=>effects.push(effect),useRef:v=>({current:v}),useState:v=>{const i=index++;states[i]=v;return[v,v=>states[i]=v];}}:name==='notice-details'?{OutputDetails:()=>null}:name.startsWith('@/components/')?{__esModule:true,default:()=>null,Dialog:()=>null,formatTime:x=>x}:require(name),m,m.exports);
  globalThis.fetch=async()=>({ok:true,json:async()=>({available:true,rows:[],unread_count:value})});
  m.exports.default({snapshot:{factory:{id:'F'},user:{id:'U'}},lang:'en',t:k=>k});effects[1]();await new Promise(setImmediate);
  if(['3','0',3].includes(value)){assert.equal(states[0].unread_count,Number(value));assert.equal(states[4],'');}
  else{assert.equal(states[0],null);assert.equal(states[4],'dataWarning');}
 }}finally{globalThis.fetch=oldFetch;}
});
test('negative forecast displays a positive shortage without changing the source value',()=>{
 const source=-60;assert.deepEqual(projectedQuantity(source),{shortage:true,quantity:'60'});assert.equal(source,-60);assert.deepEqual(projectedQuantity(null),{shortage:false,quantity:null});assert.deepEqual(projectedQuantity(0),{shortage:false,quantity:'0'});assert.equal(projectedQuantity('-0.1234567890123456789').quantity,'0.1234567890123456789');
});
test('request projection preserves holds and excludes new-workflow receipts from legacy acknowledgement',()=>{
 const rows=warehouseRequestRows({t:k=>k,legacy:[{id:'old',manufactured:false,code:'PO-old',effective_good:4,unit:'meter'},{id:'new',manufactured:true,effective_good:4}],receipts:[{id:'held',order:'PO-held',accounting:{pending:true,stage:'PENDING'},groups:[{remaining:'0',missing_operations:[]}],unit:'meter'}]});
 assert.equal(rows.length,2);assert.equal(rows.find(r=>r.id==='held').available,'0');assert.equal(rows.find(r=>r.id==='old').kind,'acknowledge');assert.ok(!rows.some(r=>r.id==='new'));
});
test('outstanding request quantities use decimal ordering for number or exact-string readers',()=>{
 const row=warehouseRequestRows({t:k=>k,orders:[{id:'SO',code:'SO-1',lines:[{id:'L',quantity:'100.123456789012345678',dispatched_quantity:'20',product_name:'Pipe',unit:'meter'}]}]})[0];
 assert.equal(row.quantity,'80.123456789012345678');assert.equal(row.available,'—');
});
