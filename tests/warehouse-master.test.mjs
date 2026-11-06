import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {renderToStaticMarkup} from 'react-dom/server';
import {build} from 'esbuild';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
import {inventoryColumns,warehouseVisibleColumns,validInventoryFilters} from '../src/utils/warehouse-inventory.mjs';
import {defaultWarehouseColumns,warehouseColumnTitle,visibleWarehouseColumns,warehousePreferenceKey} from '../src/utils/warehouse-view.mjs';
const require=createRequire(import.meta.url),react=require('react');
const bundle=(await build({entryPoints:['src/features/WarehouseInventory.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'fixture',setup(b){b.onResolve({filter:/useFulfillment$/},()=>({path:'test:read',external:true}));}}]})).outputFiles[0].text;
const base={id:'P',row_key:'finished:P:meter',entity:'finished',name:'Zero pipe',name_ar:'أنبوب صفري',code:'P-0',item_type:'FINISHED_GOOD',supply_source:'MANUFACTURED',unit:'meter',on_hand:0,reserved:0,available:0,incoming:0,projected:0,minimum_stock:10,maximum_stock:50,minimum_status:'AT_OR_BELOW_MIN',replenishment_status:'PRODUCTION_REQUIRED',can_produce:true,suggested_quantity:50};
function harness(rows=[base],can=()=>true,command=async()=>{},lang='en'){
 const states=[],refs=[];let index=0,refIndex=0,lastQuery,refreshes=0;const mod={exports:{}},w=lang==='ar'?ar:en;
 new Function('require','module','exports',bundle)(n=>n==='test:read'?{useFulfillment:(_s,_m,_p,_e,query)=>{lastQuery=query;return{data:{rows,total:rows.length,units:['kg','meter','piece']},busy:false,error:'',refresh(){refreshes++;}};}}:n==='react'?{...react,useEffect(){},useId:()=>"warehouse-test",useState(initial){const i=index++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useRef(initial){const i=refIndex++;return refs[i]??(refs[i]={current:initial});},useEffect(){}}:require(n),mod,mod.exports);
 const props={snapshot:{factory:{id:'F'},tables:{},fetchedAt:'now'},t:k=>w[k]||k,lang,can,command,onChanged(){},onReceive(){},onConfigure(){}};
 function tree(){index=0;refIndex=0;return mod.exports.default(props);}
 function all(n){if(!n||typeof n!=='object')return[];if(Array.isArray(n))return n.flatMap(all);return[n,...all(n.props?.children)];}
 return{nodes:()=>all(tree()),html:()=>renderToStaticMarkup(tree()),states,props,query:()=>lastQuery,refreshes:()=>refreshes};
}
const button=(h,label)=>{let n=h.nodes().find(n=>n.type==='button'&&(n.props.children===label||n.props['aria-label']===label));if(!n){const row=h.nodes().find(n=>n.type==='tr'&&n.props['aria-selected']!==undefined);row?.props.onClick({target:{closest(){return null}},defaultPrevented:false});n=h.nodes().find(n=>n.type==='button'&&(n.props.children===label||n.props['aria-label']===label));}return n;};
const settle=()=>new Promise(resolve=>setImmediate(resolve));
for(const lang of ['en','ar']) {
 test('Zero/NULL/type/status and RTL render in '+lang,()=>{
  const w=lang==='ar'?ar:en,h=harness([{...base,item_type:'FINISHED_GOOD'}, {...base,id:'R',row_key:'R',entity:'material',item_type:'RAW_MATERIAL',supply_source:'EXTERNAL',can_produce:false,maximum_stock:null}, {...base,id:'S',row_key:'S',entity:'material',item_type:'SEMI_FINISHED',supply_source:'EXTERNAL',can_produce:false}],()=>true,async()=>{},lang),html=h.html();
  for(const key of ['FINISHED_GOOD','RAW_MATERIAL','SEMI_FINISHED','inventory_PRODUCTION_REQUIRED'])assert.ok(html.includes(w[key]));assert.ok(html.includes(w.wvItem));
  assert.ok(html.includes((0).toLocaleString(lang)));assert.match(html,new RegExp('dir="'+(lang==='ar'?'rtl':'ltr')+'"'));assert.match(html,/data-low="true"/);
 });
 test('Clean headers retain sorting and all column filters via toolbar in '+lang,()=>{const w=lang==='ar'?ar:en,h=harness([base],()=>true,async()=>{},lang);assert.equal(h.nodes().some(n=>n.props?.className==='inventory-filter-button'),false);const toolbar=h.nodes().find(n=>n.type==='button'&&Array.isArray(n.props.children)&&n.props.children[0]===w.inventoryFilters);toolbar.props.onClick();const select=h.nodes().find(n=>n.type==='select'&&n.props.value==='item_type');assert.deepEqual(select.props.children.map(n=>n.props.value),inventoryColumns.map(c=>c[0]));});
}
test('Opening dialog and cancelling creates nothing',async()=>{const calls=[],h=harness([base],()=>true,(...args)=>calls.push(args));button(h,en.inventoryCreateProduction).props.onClick();assert.equal(calls.length,0);assert.ok(h.html().includes(en.inventoryConfirmProduction));button(h,en.cancel).props.onClick();assert.equal(calls.length,0);});
test('Final confirmation sends typed authoritative preview and stock command',async()=>{
 const calls=[],h=harness([base],()=>true,async(...args)=>calls.push(args));button(h,en.inventoryCreateProduction).props.onClick();
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await settle();
 assert.equal(calls.length,1);assert.equal(calls[0][0],'confirm_warehouse_replenishment');assert.deepEqual({...calls[0][1],request_id:null},{factory:'F',product:'P',action:'produce',unit:'meter',projected:0,quantity:50,request_id:null});assert.ok(calls[0][1].request_id);
});
test('Double submission uses an immediate guard',async()=>{
 const calls=[];let release;const h=harness([base],()=>true,async(...args)=>{calls.push(args);await new Promise(r=>release=r);});
 button(h,en.inventoryCreateProduction).props.onClick();const submit=h.nodes().find(n=>n.type==='form').props.onSubmit;submit({preventDefault(){}});submit({preventDefault(){}});assert.equal(calls.length,1);release();await settle();
});
test('Failed response preserves command id for retry',async()=>{
 const calls=[],h=harness([base],()=>true,async(...args)=>{calls.push(args);throw Error('inventoryStockChanged');});button(h,en.inventoryCreateProduction).props.onClick();
 for(let i=0;i<2;i++){h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await settle();}
 assert.equal(calls[0][1].request_id,calls[1][1].request_id);assert.ok(h.refreshes()>=2);
});
test('Missing maximum requires an explicit positive quantity',async()=>{
 const calls=[],h=harness([{...base,maximum_stock:null,suggested_quantity:null}],()=>true,async(...args)=>calls.push(args));button(h,en.inventoryCreateProduction).props.onClick();
 assert.equal(button(h,en.inventoryConfirmProduction).props.disabled,true);h.nodes().find(n=>n.type==='input'&&n.props.required).props.onChange({target:{value:'17'}});
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await settle();assert.equal(calls[0][1].quantity,17);
});
test('External stock has receive and no production action',()=>{const h=harness([{...base,supply_source:'EXTERNAL',replenishment_status:'EXTERNAL_REQUIRED',can_produce:false}]);assert.ok(button(h,en.receiveStock));assert.equal(button(h,en.inventoryCreateProduction),undefined);});
test('Existing incoming stock shows requested status with no create',()=>{const h=harness([{...base,replenishment_status:'ALREADY_REQUESTED',minimum_status:'ABOVE_MIN',incoming:50,projected:50,can_produce:false}]);assert.equal(button(h,en.inventoryCreateProduction),undefined);assert.ok(h.html().includes(en.inventory_ALREADY_REQUESTED));assert.doesNotMatch(h.html(),/data-low="true"/);});
test('Hybrid internal sourcing has a second final confirmation',()=>{const calls=[],h=harness([{...base,supply_source:'BOTH',replenishment_status:'SOURCING_REQUIRED'}],()=>true,(...args)=>calls.push(args));button(h,en.inventoryChooseSource).props.onClick();button(h,en.inventoryProduceInternally).props.onClick();assert.equal(calls.length,0);assert.ok(button(h,en.inventoryConfirmProduction));});
test('Hybrid external sourcing requires final purchase confirmation and never creates Production',async()=>{const calls=[],h=harness([{...base,supply_source:'BOTH',can_purchase:true,replenishment_status:'SOURCING_REQUIRED'}],()=>true,async(...args)=>calls.push(args));button(h,en.inventoryChooseSource).props.onClick();button(h,en.inventoryPurchaseExternally).props.onClick();assert.equal(calls.length,0);h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await settle();assert.equal(calls.length,1);assert.equal(calls[0][0],'supply_command');assert.equal(calls[0][1].action,'purchase_stock');assert.equal(calls[0][1].payload.quantity,50);});
test('Warehouse viewer cannot mutate or configure inventory',()=>{const h=harness([base],(_m,a='view')=>a==='view');for(const key of ['inventoryCreateProduction','configureStock','receiveStock'])assert.equal(button(h,en[key]),undefined);});
function openColumnFilter(h,title){const key=inventoryColumns.find(([,label])=>label===title)?.[0];assert.ok(key,title);h.nodes().find(n=>n.type==='button'&&Array.isArray(n.props.children)&&n.props.children[0]===en.inventoryFilters).props.onClick();h.nodes().find(n=>n.type==='select'&&n.props.value==='item_type').props.onChange({target:{value:key}});}
const visibleTitle=title=>warehouseColumnTitle(inventoryColumns.find(([,t])=>t===title)?.[0]||title);
function numericFilter(h,title,op='eq',value=0){openColumnFilter(h,title);h.nodes().find(n=>n.type==='select'&&n.props.value==='eq').props.onChange({target:{value:op}});if(!['positive','configured','not_configured'].includes(op))h.nodes().find(n=>n.type==='input'&&n.props.type==='number').props.onChange({target:{value:String(value)}});button(h,en.inventoryApply).props.onClick();h.nodes();}
function categoryFilter(h,title,values){openColumnFilter(h,title);for(const value of values){const label=h.nodes().find(n=>n.type==='label'&&Array.isArray(n.props.children)&&n.props.children[1]===en[value]);label.props.children[0].props.onChange({target:{checked:true}});}button(h,en.inventoryApply).props.onClick();h.nodes();}
test('Column filters combine in one query and survive refresh',()=>{
 const h=harness();categoryFilter(h,'status',['inventory_AT_OR_BELOW_MIN']);numericFilter(h,'stock_reserved','positive');
 assert.deepEqual(JSON.parse(h.query().filters),{replenishment_status:['AT_OR_BELOW_MIN'],reserved:{op:'positive'}});
 h.props.revision=1;h.props.snapshot.fetchedAt='new';h.nodes();assert.deepEqual(JSON.parse(h.query().filters),{replenishment_status:['AT_OR_BELOW_MIN'],reserved:{op:'positive'}});
});
test('Zero stock column filter and clear all use the same query model',()=>{const h=harness();numericFilter(h,'stock_on_hand');assert.deepEqual(JSON.parse(h.query().filters),{on_hand:{op:'eq',value:0}});button(h,en.inventoryClearAll).props.onClick();h.nodes();assert.deepEqual(JSON.parse(h.query().filters),{});});
test('Clearing one column preserves other columns',()=>{const h=harness();numericFilter(h,'stock_on_hand');numericFilter(h,'stock_reserved','positive');openColumnFilter(h,'stock_on_hand');button(h,en.inventoryClearFilter).props.onClick();h.nodes();assert.deepEqual(JSON.parse(h.query().filters),{reserved:{op:'positive'}});});
test('Numeric column range is sent to the server before pagination',()=>{
 const h=harness();openColumnFilter(h,'stock_reserved');
 h.nodes().find(n=>n.type==='select'&&n.props.value==='eq').props.onChange({target:{value:'range'}});
 let inputs=h.nodes().filter(n=>n.type==='input'&&n.props.type==='number');inputs[0].props.onChange({target:{value:'10'}});inputs=h.nodes().filter(n=>n.type==='input'&&n.props.type==='number');inputs[1].props.onChange({target:{value:'20'}});
 button(h,en.inventoryApply).props.onClick();h.nodes();assert.deepEqual(JSON.parse(h.query().filters),{reserved:{op:'range',value:10,to:20}});
});
test('Column sorting preserves filters and toggles direction',()=>{const h=harness();numericFilter(h,'stock_on_hand');const find=()=>h.nodes().find(n=>n.type==='button'&&Array.isArray(n.props.children)&&n.props.children.length===3&&n.props.children[0]===en.stock_on_hand);find().props.onClick();h.nodes();assert.equal(h.query().sort,'on_hand');find().props.onClick();h.nodes();assert.equal(h.query().direction,'desc');assert.deepEqual(JSON.parse(h.query().filters),{on_hand:{op:'eq',value:0}});});
test('Factory change clears previous filters and modal',()=>{const h=harness();numericFilter(h,'stock_on_hand');h.props.snapshot.factory.id='G';h.nodes();h.nodes();assert.deepEqual(JSON.parse(h.query().filters),{});});
for(const invalid of [null,[],{unknown:1},{on_hand:{op:'range',value:2,to:1}},{reserved:{op:'eq',value:Infinity}},{item_type:['RAW_MATERIAL',3]}])test('Reject malformed API filter '+JSON.stringify(invalid),()=>assert.equal(validInventoryFilters(invalid),false));
const apiBundles={};
for(const mode of ['data','fulfillment'])apiBundles[mode]=(await build({entryPoints:[`src/app/api/${mode}/route.ts`],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'test:auth',external:true}));}}]})).outputFiles[0].text;
function apiHarness(mode,allowed=true){
 const calls=[],grants=[],mod={exports:{}},context={db:{rpc:async(name,args)=>{calls.push({name,args});return{data:{rows:[],total:0},error:null};}}};
 const auth={verifyOrigin(){},authenticatedClient:async()=>context,authorize:async(f,module,action)=>{grants.push([f,module,action]);if(!allowed)throw Error('permission_denied');},safeError:e=>({error:e.message==='permission_denied'?'permissionError':'error'})};
 new Function('require','module','exports',apiBundles[mode])(n=>n==='test:auth'?auth:require(n),mod,mod.exports);return{calls,grants,api:mod.exports};
}
test('Inventory API authorizes Warehouse view and sends validated filters and sorting',async()=>{
 const h=apiHarness('fulfillment'),params=new URL('http://localhost/api/fulfillment?factory=F&mode=inventory&page=2&sort=reserved&direction=desc&filters='+encodeURIComponent(JSON.stringify({item_type:['RAW_MATERIAL'],reserved:{op:'positive'}})));
 const response=await h.api.GET({nextUrl:params});assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'private, no-store');
 assert.deepEqual(h.grants,[['F','warehouse','view']]);assert.deepEqual(h.calls,[{name:'warehouse_inventory',args:{factory:'F',page:2,filters:{item_type:['RAW_MATERIAL'],reserved:{op:'positive'}},sort:'reserved',direction:'desc'}}]);
});
test('Malformed inventory API filters never reach a database reader',async()=>{
 const h=apiHarness('fulfillment');const response=await h.api.GET({nextUrl:new URL('http://localhost/api/fulfillment?factory=F&mode=inventory&filters='+encodeURIComponent('{"reserved":{"op":"eq","value":"bad"}}'))});
 assert.equal(response.status,400);assert.equal(h.calls.length,0);
});
test('Warehouse confirmation API uses Warehouse edit authority and denies a viewer',async()=>{
 const args={factory:'F',product:'P',action:'produce',unit:'meter',projected:0,quantity:50,request_id:'R'};
 for(const allowed of [true,false]){const h=apiHarness('data',allowed);const response=await h.api.POST({headers:{get:()=>null},text:async()=>JSON.stringify({command:'confirm_warehouse_replenishment',args}),json:async()=>({command:'confirm_warehouse_replenishment',args})});
 assert.deepEqual(h.grants,[['F','warehouse','edit']]);assert.equal(h.calls.length,allowed?1:0);if(allowed)assert.deepEqual(h.calls[0],{name:'confirm_warehouse_replenishment',args});else assert.equal((await response.json()).error,'permissionError');}
});

// Integration of quantity columns with the retained header-filter model.
test('Raw plus low plus Reserved positive combines with category OR',()=>{const h=harness();categoryFilter(h,'inventoryType',['RAW_MATERIAL','ACCESSORY']);categoryFilter(h,'status',['inventory_AT_OR_BELOW_MIN']);numericFilter(h,'stock_reserved','positive');assert.deepEqual(JSON.parse(h.query().filters),{item_type:['RAW_MATERIAL','ACCESSORY'],replenishment_status:['AT_OR_BELOW_MIN'],reserved:{op:'positive'}});assert.equal(h.nodes().filter(n=>n.type==='button'&&n.props.children===en.inventoryClearAll).length,1);});
test('Stored WIP and active remaining are optional, not added to on-hand',()=>{const h=harness([{...base,on_hand:60,semi_finished:20,in_production:40,reserved:10,available:50,incoming:50,projected:140}]);assert.equal(h.nodes().filter(n=>n.type==='tr'&&n.key===base.row_key).length,1);assert.deepEqual(h.nodes().filter(n=>n.type==='th').map(n=>n.key),defaultWarehouseColumns);const quantityCells=h.nodes().filter(n=>n.type==='td'&&['on_hand','reserved','available','projected'].includes(n.key));assert.equal(quantityCells.length,4);assert.ok(h.html().includes('50 meter')||h.html().includes('50 Meter'));});
test('Unknown primary units remain unavailable without guessing a balance',()=>{const h=harness([{...base,unit:null,on_hand:null,reserved:null,available:null,projected:null}]);assert.ok(h.html().includes(en.wvUnknownUnit));assert.ok(h.html().includes(en.notAvailable));assert.doesNotMatch(h.html(),/NaN|undefined/);});
test('Warehouse does not render the removed quick chips or minimum-status column',()=>{const h=harness();assert.equal(h.nodes().filter(n=>n.props?.className==='inventory-quick').length,0);assert.equal(inventoryColumns.some(([key])=>key==='minimum_status'),false);});
test('Exactly seven approved default headers; optional inventory contracts remain usable',()=>{const h=harness();assert.deepEqual(h.nodes().filter(n=>n.type==='th').map(n=>n.key),defaultWarehouseColumns);assert.equal(h.nodes().some(n=>n.type==='th'&&n.key==='actions'),false);assert.ok(h.html().includes(base.code));assert.equal(validInventoryFilters({supply_source:['BOTH'],incoming:{op:'positive'},projected:{op:'gt',value:5}}),true);});
test('One selected row drives Actions; row details are read-only',()=>{const h=harness([base,{...base,row_key:'other',id:'Q'}]);let rows=h.nodes().filter(n=>n.type==='tr'&&n.props['aria-selected']!==undefined);const click=r=>r.props.onClick({target:{closest(){return null}},defaultPrevented:false});click(rows[0]);rows=h.nodes().filter(n=>n.type==='tr'&&n.props['aria-selected']!==undefined);assert.equal(rows.filter(n=>n.props['aria-selected']).length,1);click(rows[1]);assert.equal(h.nodes().filter(n=>n.type==='tr'&&n.props['aria-selected']).length,1);assert.ok(button(h,en.historyViewDetails));});
test('Warehouse retains keyboard-scrollable region and pagination',()=>{const h=harness();assert.equal(h.nodes().find(n=>n.props?.className==='inventory-table-scroll').props.tabIndex,0);assert.ok(button(h,en.next));});
test('Warehouse preference scopes and unknown columns cannot leak across users/tables',()=>{assert.notEqual(warehousePreferenceKey('a','f'),warehousePreferenceKey('b','f'));assert.notEqual(warehousePreferenceKey('a','f'),warehousePreferenceKey('a','g'));assert.deepEqual(visibleWarehouseColumns(['reserved','evil']),['reserved']);assert.deepEqual(visibleWarehouseColumns([]),defaultWarehouseColumns);});
test('Warehouse CSS centers compact wrapping cells and pins opaque headers within a bounded scroll region',async()=>{
 const css=await readFile('src/app/globals.css','utf8');
 const rule=selector=>css.slice(css.indexOf(selector+' {'),css.indexOf('}',css.indexOf(selector+' {'))+1);
 assert.match(rule('.inventory-table th,.inventory-table td'),/text-align:center/);assert.match(rule('.inventory-table th,.inventory-table td'),/white-space:normal/);assert.match(rule('.inventory-table th,.inventory-table td'),/vertical-align:top/);
 assert.doesNotMatch(rule('.inventory-table th,.inventory-table td'),/(?:min-)?height:/);assert.match(rule('.inventory-table th'),/position:sticky/);assert.match(rule('.inventory-table th'),/background:var\(--surface\)/);
 assert.match(rule('.inventory-table-scroll'),/overflow:auto/);assert.match(rule('.inventory-table-scroll'),/max-height:/);assert.match(rule('.inventory-table'),/font-size:\.875rem/);
 assert.match(rule('.inventory-table'),/table-layout:auto/);assert.doesNotMatch(rule('.inventory-table'),/min-width:/);
 assert.match(rule('.inventory-table th>div'),/flex-wrap:nowrap/);assert.match(rule('.inventory-table th>div'),/display:inline-flex/);assert.match(rule('.inventory-table th button'),/white-space:nowrap/);
});
