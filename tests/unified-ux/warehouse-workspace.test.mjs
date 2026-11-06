import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import en from '../../src/locales/en.json' with {type:'json'};
import ar from '../../src/locales/ar.json' with {type:'json'};
const require=createRequire(import.meta.url),react=require('react');
const bundles={};
for(const name of ['Warehouse','WarehouseOutputs','WarehouseReceiving','Purchasing'])bundles[name]=(await build({entryPoints:[`src/features/${name}.tsx`],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'fixture',setup(b){b.onResolve({filter:/^(?:\.\/|@\/components\/)/},args=>args.kind==='entry-point'?undefined:({path:args.path,external:true}));b.onLoad({filter:/\.css$/},()=>({contents:'',loader:'css'}));}}],loader:{'.css':'empty'}})).outputFiles[0].text;
function harness(name,lang='en',can=()=>true){
 const states=[],calls=[],reads=[],stubs={};let index=0;
 const stub=name=>stubs[name]??=(Object.assign(()=>null,{displayName:name}));
 const props={snapshot:{factory:{id:'F'},user:{id:'U'},tables:{products:[]}},materials:[],refresh(){},lang,t:k=>(lang==='ar'?ar:en)[k]||k,can,command:async(...args)=>{calls.push(args);}};
 const mod={exports:{}};
 new Function('require','module','exports',bundles[name])(path=>{
  if(path==='react')return {...react,useEffect(){},useId:()=>"warehouse-tabs",useRef:initial=>({current:initial}),useState:initial=>{const i=index++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];}};
  if(path==='./useFulfillment')return{useFulfillment:()=>({data:{rows:[],orders:[],total:0,orders_total:0,materials_total:0,materials:[]},refresh(){},busy:false})};
  if(path==='./useSupply')return{useSupply:(_s,mode,extra,enabled=true)=>{reads.push({mode,enabled});return{data:enabled?{rows:[],total:0}:null,busy:false,error:'',refresh(){}};},useSupplyCommand:()=>({run:async(...args)=>calls.push(args),busy:false})};
  if(path==='./WarehouseUi')return{WarehouseDialog:stub('Dialog'),WarehousePicker:stub('Picker')};
  if(path==='./SourceStock')return{SourceAllocationFields:stub('SourceAllocationFields'),SourceIdentityDialog:stub('SourceIdentityDialog')};
  if(path==='@/components/useTableDetails')return{useTableDetails:()=>()=>({}),TableDetailsAction:stub('TableDetailsAction')};
  if(path==='@/components/ui')return{Field:stub('Field'),localName:r=>r.name,formatTime:x=>x};
  if(path.startsWith('./')||path.startsWith('@/components/'))return{__esModule:true,default:stub(path.slice(2))};
  return require(path);
 },mod,mod.exports);
 const all=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(all):[n,...all(n.props?.children)];
 const nodes=()=>{index=0;return all(mod.exports.default(props));};
 return{props,calls,reads,nodes,component:label=>nodes().find(n=>n.type?.displayName===label),tab:i=>nodes().filter(n=>n.props?.role==='tab')[i]};
}
for(const lang of ['en','ar'])test('two daily workspaces remove duplicate bottom workflows '+lang,()=>{
 const h=harness('Warehouse',lang),w=lang==='ar'?ar:en;
 assert.equal(h.nodes().filter(n=>n.props?.role==='tab').length,2);
 h.tab(1).props.onClick();assert.ok(h.component('WarehouseRequests'));assert.equal(h.component('WarehouseInventory'),undefined);
 h.tab(0).props.onClick();assert.ok(h.component('WarehouseInventory'));assert.equal(h.component('WarehouseRequests'),undefined);
 assert.equal(h.nodes().some(n=>n.type==='button'&&n.props.children===w.purchaseCreate),false);
 assert.equal(h.component('UnfinishedProducts'),undefined);assert.equal(h.component('WarehouseOutputs'),undefined);assert.equal(h.calls.length,0);
 const viewer=harness('Warehouse',lang,(_m,a='view')=>a==='view');assert.equal(viewer.nodes().some(n=>n.type==='button'&&n.props.children===w.purchaseCreate),false);
});
for(const lang of ['en','ar'])test('keyboard switches two tabs without submitting a command '+lang,()=>{
 const h=harness('Warehouse',lang);let focused=-1;h.tab(0).props.onKeyDown({key:'End',preventDefault(){},currentTarget:{parentElement:{querySelectorAll:()=>[{focus(){focused=0;}},{focus(){focused=1;}}]}}});assert.equal(h.tab(1).props['aria-selected'],true);assert.equal(focused,1);assert.equal(h.calls.length,0);
});
test('stored unfinished filter selects its protected typed view',()=>{const h=harness('Warehouse');const picker=h.nodes().find(n=>n.type==='select'&&n.props.children.some?.(v=>v?.props?.value==='wip'));assert.ok(picker);picker.props.onChange({target:{value:'wip'}});assert.ok(h.component('StoredUnfinishedInventory'));assert.equal(h.component('WarehouseInventory'),undefined);assert.equal(h.calls.length,0);});
