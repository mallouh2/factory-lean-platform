import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
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
  if(path==='./useSupply')return{useSupply:(_s,mode,extra,enabled=true)=>{reads.push({mode,enabled});return{data:enabled?{rows:[],total:0}:null,busy:false,error:'',refresh(){}};},useSupplyCommand:()=>({run:async(...args)=>calls.push(args),busy:false,error:'',clearError(){}})};
  if(path==='./WarehouseDefinitions')return{__esModule:true,default:stub('WarehouseDefinitions'),useWarehouses:()=>({ready:true,rows:[{id:'W',active:true,storage_class:'FINISHED'},{id:'R',active:true,storage_class:'RAW'}]}),WarehouseSelector:stub('WarehouseSelector')};
  if(path==='./WarehouseUi')return{WarehouseDialog:stub('Dialog'),WarehousePicker:stub('Picker')};
  if(path==='./SourceStock')return{SourceAllocationFields:stub('SourceAllocationFields'),SourceIdentityDialog:stub('SourceIdentityDialog')};
  if(path==='@/components/useTableDetails')return{useTableDetails:()=>()=>({}),TableDetailsAction:stub('TableDetailsAction')};
  if(path==='@/components/ui')return{Dialog:stub('Dialog'),Field:stub('Field'),localName:r=>r.name,formatTime:x=>x};
  if(path.startsWith('./')||path.startsWith('@/components/'))return{__esModule:true,default:stub(path.slice(2))};
  return require(path);
 },mod,mod.exports);
 const all=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(all):[n,...all(n.props?.children)];
 const nodes=()=>{index=0;return all(mod.exports.default(props));};
 return{props,calls,reads,nodes,component:label=>nodes().find(n=>n.type?.displayName===label),tab:i=>nodes().filter(n=>n.props?.role==='tab')[i]};
}
for(const lang of ['en','ar'])test('Exactly two workspaces retain current operational boundaries without sending commands '+lang,()=>{const h=harness('Warehouse',lang);assert.equal(h.nodes().filter(n=>n.props?.role==='tab').length,2);assert.ok(h.component('WarehouseReceiving'));assert.ok(h.component('WarehouseInventory'));for(let i=0;i<2;i++){h.tab(i).props.onClick();assert.equal(h.tab(i).props['aria-selected'],true);assert.equal(h.nodes().filter(n=>n.props?.role==='tab'&&n.props.tabIndex===0).length,1);assert.ok(h.nodes().filter(n=>n.props?.role==='tabpanel'&&!n.props.hidden).length===1);if(i===1)assert.equal(h.component('WarehouseRequests').props.active,true);assert.equal(h.component('Purchasing'),undefined);}assert.equal(h.calls.length,0);});
for(const [lang,key]of[['en','ArrowRight'],['ar','ArrowLeft']])test('Workspace keyboard navigation follows reading direction and Home/End '+lang,()=>{const h=harness('Warehouse',lang);let focused=-1;const event=key=>({key,preventDefault(){},currentTarget:{parentElement:{querySelectorAll:()=>Array.from({length:2},(_,i)=>({focus(){focused=i;}}))}}});h.tab(0).props.onKeyDown(event(key));assert.equal(h.tab(1).props['aria-selected'],true);assert.equal(focused,1);h.tab(1).props.onKeyDown(event('End'));assert.equal(h.tab(1).props['aria-selected'],true);h.tab(1).props.onKeyDown(event(key));assert.equal(h.tab(0).props['aria-selected'],true);h.tab(0).props.onKeyDown(event('Home'));assert.equal(h.tab(0).props['aria-selected'],true);assert.equal(h.calls.length,0);});
test('Stored unfinished inventory remains separate from finished stock and does not process material while browsing',()=>{const h=harness('Warehouse');const filter=h.component('WarehouseInventory').props.inventoryFilter;react.Children.toArray(filter.props.children).find(n=>n.type==='select').props.onChange({target:{value:'wip'}});assert.ok(h.component('StoredUnfinishedInventory'));assert.equal(h.component('WarehouseInventory'),undefined);h.tab(1).props.onClick();assert.equal(h.component('WarehouseRequests').props.active,true);assert.equal(h.calls.length,0);const viewer=harness('Warehouse','en',(_m,a='view')=>a==='view');assert.equal(viewer.component('WarehouseReceiving').props.settingsAction,false);assert.equal(viewer.calls.length,0);});
for(const [mode,good,wip] of [['good',true,false],['wip',false,true],[undefined,true,true]])test('Receipt view reads only its matching dataset; default product compatibility '+mode,()=>{
 const h=harness('WarehouseOutputs');h.props.mode=mode;h.nodes();assert.deepEqual(h.reads,[{mode:'lots',enabled:wip},{mode:'outputs',enabled:good}]);
 if(good)assert.ok(h.nodes().some(n=>n.props?.children===en.warehouseGoodAlreadyCredited));
 h.props.product='P';h.props.mode=undefined;h.reads.length=0;h.nodes();assert.deepEqual(h.reads,[{mode:'lots',enabled:true},{mode:'outputs',enabled:false}]);assert.equal(h.calls.length,0);
});
test('Approved adjustment labels/help retain required reason and signed protected commands',async()=>{
 for(const lang of ['en','ar']){const h=harness('Warehouse',lang),words=lang==='ar'?ar:en;h.component('WarehouseReceiving').props.settingsAction.props.onClick();h.nodes().find(n=>n.type==='button'&&n.props.children===words.adjustStock).props.onClick();
  const field=h.nodes().find(n=>n.type?.displayName==='Field'&&n.props.label===words.stockAdjustmentDifference);assert.ok(field);assert.equal(field.props.children.props.step,'any');assert.equal(field.props.children.props.min,undefined);
  assert.ok(h.nodes().some(n=>n.props?.children===words.stockAdjustmentHelp));assert.equal(h.nodes().find(n=>n.type==='textarea').props.required,true);
  field.props.children.props.onChange({target:{value:'-2'}});const sources=h.component('SourceAllocationFields');assert.ok(sources);sources.props.onChange([{source:'S',quantity:'2'}],true);
  h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(r=>setImmediate(r));assert.equal(h.calls[0][0],'source_stock_command');assert.equal(h.calls[0][1].payload.quantity,'-2');
 }
 assert.equal(ar.stockAdjustmentDifference,'فرق المخزون (+/−)');assert.equal(ar.stockAdjustmentHelp,'أدخل كمية موجبة (+) لإضافة مخزون، أو سالبة (−) لخصمه، مع توضيح سبب التعديل. لا يمكن خصم أكثر من الكمية غير المحجوزة.');
});

for(const lang of['en','ar'])test('Purchasing has one authorized create entry outside Warehouse workspaces '+lang,()=>{const w=lang==='ar'?ar:en,h=harness('Purchasing',lang);const entries=h.nodes().filter(n=>n.type==='button'&&n.props.children===w.purchaseCreate);assert.equal(entries.length,1);entries[0].props.onClick();assert.equal(h.component('Dialog').props.title,w.purchaseCreate);h.component('Dialog').props.onClose();const viewer=harness('Purchasing',lang,(_m,a='view')=>a==='view');assert.ok(!viewer.nodes().some(n=>n.type==='button'&&n.props.children===w.purchaseCreate));const warehouse=harness('Warehouse',lang);for(let i=0;i<2;i++){warehouse.tab(i).props.onClick();assert.equal(warehouse.component('Purchasing'),undefined);}assert.equal(h.calls.length,0);});
function content(n){return typeof n==='string'?n:!n||typeof n!=='object'?'':Array.isArray(n)?n.map(content).join(''):content(n.props?.children);}
for(const lang of['en','ar'])test('Inventory management opens current receipt/history/settings paths and protects editing '+lang,()=>{const w=lang==='ar'?ar:en,h=harness('WarehouseReceiving',lang);h.props.compactActions=true;h.props.settingsAction=react.createElement('button',null,w.warehouseStockSettings);assert.ok(h.nodes().find(n=>n.props?.className==='warehouse-inventory-tools'));assert.equal(h.nodes().filter(n=>n.type==='button'&&n.props.children===w.receiveStock).length,1);const button=label=>h.nodes().find(n=>n.type==='button'&&content(n).startsWith(label));button(w.receiveStock).props.onClick();assert.equal(h.component('Dialog').props.title,w.receiveStock);h.component('Dialog').props.onClose();button(w.stockMovements).props.onClick();assert.ok(h.component('WarehouseMovements'));h.component('WarehouseMovements').props.onClose();button(w.whItemStockSettings).props.onClick();assert.equal(h.component('Dialog').props.title,w.whItemStockSettings);button(w.addMaterial).props.onClick();assert.equal(h.component('Dialog').props.title,w.addMaterial);assert.equal(h.calls.length,0);const viewer=harness('WarehouseReceiving',lang,(_m,a='view')=>a==='view');viewer.props.compactActions=true;assert.ok(viewer.nodes().find(n=>n.type==='button'&&content(n).startsWith(w.stockMovements)));assert.ok(!viewer.nodes().some(n=>n.type==='button'&&[w.receiveStock,w.addMaterial].includes(content(n))));assert.ok(!viewer.nodes().some(n=>n.type==='button'&&content(n).startsWith(w.whItemStockSettings)));});
test('Purchasing stock header hosts supplied create action once without exposing separate Purchasing creation',()=>{
 const h=harness('Purchasing');h.props.stock=true;h.props.headerAction=react.createElement('button',null,en.purchaseCreate);assert.equal(h.nodes().filter(n=>n.type==='button'&&n.props.children===en.purchaseCreate).length,1);assert.equal(h.calls.length,0);
 delete h.props.headerAction;assert.equal(h.nodes().filter(n=>n.type==='button'&&n.props.children===en.purchaseCreate).length,0);
});
