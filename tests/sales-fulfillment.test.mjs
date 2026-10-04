import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { build } from 'esbuild';
import en from '../src/locales/en.json' with { type: 'json' };
import ar from '../src/locales/ar.json' with { type: 'json' };
const require=createRequire(import.meta.url),react=require('react');
const bundles={};
for(const name of ['SalesOrders','Warehouse','WarehouseReceiving','SalesPlanningGuidance']) bundles[name]=(await build({entryPoints:[`src/${name==='SalesPlanningGuidance'?'components':'features'}/${name}.tsx`],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'read-fixture',setup(b){b.onResolve({filter:/useFulfillment$/},()=>({path:'test:read',external:true}));}}]})).outputFiles[0].text;
const delivery=(await build({entryPoints:['src/components/DeliveryContext.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'})).outputFiles[0].text;
const snapshot={factory:{id:'F',timezone:'UTC',delivery_buffer_days:2},tables:{products:[{id:'P',name:'QA pipe',name_ar:'أنبوب اختبار',stage:'finished'},{id:'P2',name:'QA fitting',stage:'finished'}],production_orders:[],production_requests:[],unfinished_lots:[],work_centers:[],memberships:[]}};
for(const lang of ['en','ar']) for(const state of ['achievable','tight','unachievable','insufficient']) test(`Planning drawer makes ${state} guidance and signed proposal margin explicit in ${lang}`,()=>{
 const h=harness('SalesPlanningGuidance',null,()=>true,async()=>{},lang),w=lang==='ar'?ar:en;
 Object.assign(h.props,{factory:'F',item:'I',fetchedAt:'stamp',zone:'UTC',proposal:{finish:Date.parse('2026-10-12T15:00Z')}});
 h.nodes();h.states[0]={key:'F:I:stamp',data:{state,requested_delivery:'2026-10-10T14:30Z',target_ready:'2026-10-08T14:30Z',safety_buffer_days:2,suggestion:state==='achievable'||state==='tight'?{start:'2026-10-08T13:00Z',finish:'2026-10-08T14:30Z',minutes:90}:null}};
 const html=h.html();assert.ok(html.includes(w['target_'+state]));assert.ok(html.includes(w.proposalMeetsTarget));assert.ok(html.includes(w.no));assert.ok(html.includes(w.targetMargin));assert.match(html,/-/);
 if(state==='achievable'||state==='tight')assert.ok(html.includes(lang==='ar'?'١ س ٣٠ د':'1 h 30 min'));
});
test('Planning drawer with no customer date displays no suggested target or margin',()=>{
 const h=harness('SalesPlanningGuidance',null);Object.assign(h.props,{factory:'F',item:'I',fetchedAt:'stamp',proposal:null});h.nodes();h.states[0]={key:'F:I:stamp',data:{requested_delivery:null,state:'no_target'}};
 const html=h.html();assert.ok(html.includes(en.noCustomerTarget));assert.ok(!html.includes(en.suggestedStart));assert.ok(!html.includes(en.targetMargin));
});

test('Sales creates an order without a requested date or promise payload',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[],total:0},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][1].payload.requested_delivery,null);assert.ok(!Object.hasOwn(calls[0][1].payload,'promised_delivery'));
});
test('Sales editing clears the optional target without altering a historical promise',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[order],total:1},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.edit).props.onClick();
 h.nodes().find(n=>n.type==='input'&&n.props.type==='datetime-local').props.onChange({target:{value:''}});
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][1].payload.requested_delivery,null);assert.ok(!Object.hasOwn(calls[0][1].payload,'promised_delivery'));
});
test('Native customer-date input survives another field change and submits in the factory timezone',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[],total:0},()=>true,async(...args)=>calls.push(args));h.props.snapshot.factory.timezone='Asia/Qatar';
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 h.nodes().find(n=>n.type==='input'&&n.props.type==='datetime-local').props.onInput({currentTarget:{value:'2026-10-15T15:00'}});
 h.nodes().find(n=>n.type==='input'&&n.props.maxLength===200).props.onChange({target:{value:'Customer target'}});
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][1].payload.requested_delivery,'2026-10-15T12:00:00.000Z');assert.ok(!Object.hasOwn(calls[0][1].payload,'promised_delivery'));
});
test('Undated Sales has no risk/deadline message; external and hybrid shortages stay explicit',()=>{
 const html=harness('SalesOrders',{rows:[{...order,requested_delivery:null,target_ready:null,estimated_ready:null,risk:'none',lines:[{...line,external_shortage:25,source_decision_quantity:10}]}],total:1}).html();
 assert.ok(!html.includes(en.targetReady));assert.ok(!html.includes(en.deliveryRisk_none));assert.ok(html.includes(en.externalReplenishment));assert.ok(html.includes(en.sourcingDecision));assert.ok(html.includes(en.readinessPending));
});
for(const source of ['EXTERNAL','BOTH']) test(`Warehouse ${source} displays authoritative replenishment state`,()=>{
 const row={product_id:'P',name:'QA item',unit:'piece',on_hand:5,reserved:0,available:5,incoming:0,projected:5,supply_source:source,supply_mode:'MAKE_TO_STOCK',minimum_stock:20,maximum_stock:50};
 const data={rows:[{...row,id:'P',entity:'finished',row_key:'P:piece',item_type:'FINISHED_GOOD',minimum_status:'AT_OR_BELOW_MIN',replenishment_status:source==='EXTERNAL'?'EXTERNAL_REQUIRED':'SOURCING_REQUIRED'}],orders:[],total:1,orders_total:0,materials:[]},key=source==='EXTERNAL'?'inventory_EXTERNAL_REQUIRED':'inventory_SOURCING_REQUIRED';
 assert.ok(harness('Warehouse',data).html().includes(en[key]));
 const html=harness('Warehouse',{...data,rows:[{...data.rows[0],on_hand:30,available:30,projected:30,minimum_status:'ABOVE_MIN',replenishment_status:'OK'}]}).html();assert.ok(html.includes(en.inventory_OK));assert.ok(!html.includes(en[key]));
});
for(const lang of ['en','ar']) test(`Warehouse receiving respects per-person grants and raw stock units in ${lang}`,()=>{
 const h=harness('WarehouseReceiving',null,(_m,a='view')=>a==='view',async()=>{},lang),w=lang==='ar'?ar:en;
 h.props.materials=[{id:'M',name:'Resin',name_ar:'راتنج',code:'R',unit:'kg',inventory_kind:'RAW_MATERIAL',on_hand:100,reserved:20}];h.props.refresh=()=>{};
 const html=h.html();assert.ok(html.includes(w.RAW_MATERIAL));assert.ok(html.includes(w.kg));assert.ok(html.includes('80'));assert.ok(!html.includes('>'+w.receiveStock+'</button>'));assert.ok(!html.includes('>'+w.openingStock+'</button>'));assert.ok(html.includes(w.stockMovements));
});
for(const lang of ['en','ar']) test(`Movement history separates reservation changes from physical stock in ${lang}`,()=>{
 const h=harness('WarehouseReceiving',null,()=>true,async()=>{},lang),w=lang==='ar'?ar:en;
 h.props.refresh=()=>{};h.props.materials=[];h.props.snapshot.tables.products[0].stock_unit='meter';
 h.nodes().find(n=>n.type==='button'&&n.props.children===w.stockMovements).props.onClick();
 h.nodes().find(n=>n.type==='select'&&n.props.required).props.onChange({target:{value:'P'}});
 h.nodes();h.states[15]={rows:[{id:'R',kind:'reservation',quantity:0,reserved_delta:100,unit:'meter',created_at:'2026-10-03T12:00Z',actor_name:'Warehouse person'}],total:1};
 const html=h.html();assert.ok(html.includes(w.stockMovementDelta));assert.ok(html.includes(w.reservedMovementDelta));assert.ok(html.includes((100).toLocaleString(lang)));assert.ok(html.includes('Warehouse person'));
});
for(const source of ['external_receipt','opening_balance']) test(`Warehouse ${source} sends configured unit with no client actor/time or production command`,async()=>{
 const calls=[],h=harness('WarehouseReceiving',null,()=>true,async(...args)=>calls.push(args));h.props.refresh=()=>{};h.props.materials=[];h.props.snapshot.tables.products[0].stock_unit='meter';
 h.nodes().find(n=>n.type==='button'&&n.props.children===en[source==='opening_balance'?'openingStock':'receiveStock']).props.onClick();
 const select=h.nodes().find(n=>n.type==='select'&&n.props.required);select.props.onChange({target:{value:'P'}});
 h.nodes().find(n=>n.type==='input'&&n.props.type==='number').props.onChange({target:{value:'2500'}});
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][0],'receive_warehouse_stock');const args=calls[0][1];assert.equal(args.unit,'meter');assert.equal(args.quantity,2500);assert.equal(args.source,source);assert.ok(args.request_id);assert.ok(!Object.hasOwn(args,'created_by'));assert.ok(!Object.hasOwn(args,'created_at'));
});
const line={id:'L',product_id:'P',product_name:'QA pipe',product_name_ar:'أنبوب اختبار',quantity:100,unit:'meter',reserved_quantity:40,incoming_quantity:60,production_required:60,dispatched_quantity:0,release_when_ready:false,ready:false,dispatch_allowed:false};
const order={id:'S',code:'SO-0000001',customer_reference:'QA customer',requested_delivery:'2026-10-10T14:30:00Z',promised_delivery:'2026-10-11T14:30:00Z',estimated_ready:'2026-10-10T15:00:00Z',earliest_feasible:'2026-10-10T15:00:00Z',safety_buffer_days:2,target_ready:'2026-10-09T14:30:00Z',status:'approved',fulfillment_status:'approved',risk:'at_risk',requested_feasible:false,delay_days:0,notes:'',lines:[line],dispatch_allowed:false};
function harness(name,data,can=()=>true,command=async()=>{},lang='en'){
 const states=[];let index=0;const dictionary=lang==='ar'?ar:en;const mod={exports:{}};
 new Function('require','module','exports',bundles[name])(n=>n==='test:read'?{useFulfillment:(_s,_m,_p,enabled)=>({data:enabled?data:null,busy:false,error:'',refresh(){}})}:n==='react'?{...react,useState(initial){const i=index++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useEffect(){},useRef:()=>({current:null})}:require(n),mod,mod.exports);
 const props={snapshot:structuredClone(snapshot),can,command,lang,t:k=>dictionary[k]||k};
 function tree(){index=0;return mod.exports.default(props);}
 function all(n){if(!n||typeof n!=='object')return[];if(Array.isArray(n))return n.flatMap(all);return[n,...all(n.props?.children)];}
 return{nodes:()=>all(tree()),html:()=>renderToStaticMarkup(tree()),states,props};
}
for(const lang of ['en','ar']){
 test(`Sales separates requested/promised/estimated, stock and incoming in ${lang}`,()=>{
 const h=harness('SalesOrders',{rows:[order],total:1},()=>true,async()=>{},lang);const before=JSON.stringify(h.props.snapshot);const html=h.html(),w=lang==='ar'?ar:en;
 for(const k of ['customerRequested','historicalPromise','estimatedReady','earliestFeasible','stockReserved','stockIncoming','productionRequired','holdCompleteOrder','requestedNotFeasible']) assert.ok(html.includes(w[k]),k);
 assert.match(html,/SO-0000001/);assert.ok(html.includes(lang==='ar'?'أنبوب اختبار':'QA pipe'));assert.match(html,/data-risk="at_risk"/);assert.match(html,new RegExp(`dir="${lang==='ar'?'rtl':'ltr'}"`));assert.equal(JSON.stringify(h.props.snapshot),before);
 });
 test(`Warehouse holds incomplete order and presents typed balances in ${lang}`,()=>{
 const h=harness('Warehouse',{rows:[{product_id:'P',name:'QA pipe',name_ar:'أنبوب اختبار',unit:'meter',on_hand:100,reserved:40,available:60,incoming:60,projected:120,supply_mode:'MAKE_TO_STOCK',minimum_stock:50,maximum_stock:150}],orders:[order],total:1,orders_total:1},()=>true,async()=>{},lang),html=h.html(),w=lang==='ar'?ar:en;
 for(const k of ['stock_on_hand','stock_reserved','stock_available','warehouseHoldHelp']) assert.ok(html.includes(w[k]),k);
 assert.ok(!html.includes('>'+w.dispatchOrder+'</button>'));assert.ok(!html.includes('>'+w.dispatchProductLine+'</button>'));
 });
}
test('Sales approval is per-person, not a job title or preview role',()=>{
 const h=harness('SalesOrders',{rows:[{...order,status:'draft',fulfillment_status:'draft'}],total:1},(m,a='view')=>a==='view');const html=h.html();assert.ok(!html.includes('>'+en.salesApprove+'</button>'));assert.ok(!html.includes('>'+en.salesCreate+'</button>'));
});
for(const lang of ['en','ar']) test(`Warehouse top actions and request directions stay distinct in ${lang}`,()=>{
 const h=harness('Warehouse',{rows:[],orders:[],total:0},()=>true,async()=>{},lang),w=lang==='ar'?ar:en,html=h.html();
 for(const k of ['warehouseStockSettings','receiveStock','addMaterial','warehouseInventoryMovements','purchaseCreate','warehouseProductionMaterialRequests','warehouseProductionMaterialHelp','warehouseProductionMaterialDirection','warehousePurchaseRequests','warehousePurchaseHelp','warehousePurchaseDirection'])assert.ok(html.includes(w[k]),k);
 assert.ok(!html.includes(w.supplierDirectory));assert.equal(h.nodes().filter(n=>n.props?.className==='warehouse-request-section').length,2);
 assert.equal(h.nodes().some(n=>n.type==='button'&&[w.finishedProducts,w.unfinishedProducts,w.adjustStock,w.configureStock].includes(n.props.children)),false);
});
test('Configuring a historical stock-unit row preserves current catalogue unit and Min/Max',()=>{
 const h=harness('Warehouse',{rows:[],orders:[],total:0,orders_total:0},()=>true);
 Object.assign(h.props.snapshot.tables.products[0],{stock_unit:'meter',minimum_stock:70,maximum_stock:300,supply_mode:'MAKE_TO_STOCK',supply_source:'MANUFACTURED'});
 h.nodes().find(n=>typeof n.props?.onConfigure==='function').props.onConfigure({id:'P',name:'QA pipe',unit:'piece',minimum_stock:null,maximum_stock:null,supply_source:'MANUFACTURED'});
 const nodes=h.nodes();assert.ok(nodes.some(n=>n.type==='select'&&n.props.value==='meter'));assert.ok(nodes.some(n=>n.type==='input'&&n.props.value==='70'));assert.ok(nodes.some(n=>n.type==='input'&&n.props.value==='300'));
});
test('Warehouse dispatch availability follows complete order or explicit complete product line',()=>{
 const full={...order,fulfillment_status:'ready',dispatch_allowed:true,lines:[{...line,ready:true,reserved_quantity:100,dispatch_allowed:true}]};
 assert.match(harness('Warehouse',{rows:[],orders:[full],total:0,orders_total:1}).html(),/Dispatch Complete Order/);
 const early={...order,lines:[{...line,ready:true,reserved_quantity:100,release_when_ready:true,dispatch_allowed:true}]};
 const html=harness('Warehouse',{rows:[],orders:[early],total:0,orders_total:1}).html();assert.match(html,/Dispatch Complete Product Line/);assert.ok(!html.includes('>'+en.dispatchOrder+'</button>'));
 assert.ok(!harness('Warehouse',{rows:[],orders:[full],total:0,orders_total:1},(_m,a='view')=>a!=='issue').html().includes('>'+en.dispatchOrder+'</button>'));
});
test('Physical dispatch submits no arbitrary partial quantity',async()=>{
 const calls=[],prior=globalThis.confirm;globalThis.confirm=()=>true;
 try{const h=harness('Warehouse',{rows:[],orders:[{...order,dispatch_allowed:true}],total:0,orders_total:1},()=>true,async(...args)=>calls.push(args));
 const action=h.nodes().find(n=>n.type==='button'&&n.props.children===en.dispatchOrder);action.props.onClick();assert.equal(calls.length,0);h.nodes().find(n=>n.type==='button'&&n.props.children===en.confirmDispatch).props.onClick();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][0],'dispatch_sales_order');assert.equal(calls[0][1].sales_order,'S');assert.equal(calls[0][1].factory,'F');assert.ok(calls[0][1].request_id);assert.ok(!Object.hasOwn(calls[0][1],'quantity'));}finally{globalThis.confirm=prior;}
});
test('Create Sales preserves typed unit, exact optional customer time and hold default, without a promise writer',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[],total:0},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 const change=(find,value)=>h.nodes().find(find).props.onChange({target:{value}});
 change(n=>n.type==='input'&&n.props.type==='datetime-local','2026-10-10T14:30');
 assert.equal(h.nodes().filter(n=>n.type==='input'&&n.props.type==='datetime-local').length,1);
 assert.ok(!h.nodes().find(n=>n.type==='input'&&n.props.type==='datetime-local').props.required);
 change(n=>n.type==='select'&&n.props.children?.[1]?.length,'P');
 change(n=>n.type==='input'&&n.props.type==='number'&&n.props.step==='any','100');
 change(n=>n.type==='select'&&n.props.children.flat(Infinity).some(child=>child?.props?.value==='meter'),'meter');
 const event={preventDefault(){}};h.nodes().find(n=>n.type==='form').props.onSubmit(event);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][0],'create_sales_order');const p=calls[0][1].payload;assert.equal(p.requested_delivery,'2026-10-10T14:30:00.000Z');assert.ok(!Object.hasOwn(p,'promised_delivery'));assert.equal(p.lines[0].unit,'meter');assert.equal(p.lines[0].quantity,100);assert.equal(p.lines[0].release_when_ready,false);
});
test('Product-line early release is explicit and defaults off',()=>{
 const h=harness('SalesOrders',{rows:[],total:0});h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();const check=h.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox');assert.equal(check.props.checked,false);check.props.onChange({target:{checked:true}});assert.equal(h.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox').props.checked,true);
});
test('Draft has one optional customer date and cannot edit buffer without approve permission',()=>{
 const h=harness('SalesOrders',{rows:[],total:0},(_m,a='view')=>a!=='approve');h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 assert.equal(h.nodes().filter(n=>n.type==='input'&&n.props.type==='datetime-local').length,1);assert.equal(h.nodes().find(n=>n.type==='input'&&n.props.max==='90').props.disabled,true);
});
test('Approved Sales edits require approval permission in addition to edit',()=>{
 const html=harness('SalesOrders',{rows:[order],total:1},(_m,a='view')=>a!=='approve').html();assert.ok(!html.includes('>'+en.edit+'</button>'));
});
test('Sales cancellation requires an explicit confirmation and preserves its audit reason',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[order],total:1},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.edit).props.onClick();
 const reasonField=h.nodes().find(n=>n.type==='textarea'&&n.props.required);
 reasonField.props.onChange({target:{value:'Customer cancelled QA demand'}});
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCancel).props.onClick();
 assert.equal(calls.length,0);assert.ok(h.html().includes(en.salesCancelConfirm));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCancel).props.onClick();
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][0],'change_sales_order');assert.deepEqual(calls[0][1].payload,{cancel:true});
 assert.equal(calls[0][1].reason,'Customer cancelled QA demand');assert.equal(calls[0][1].sales_order,'S');
});
test('Delivery context distinguishes stock replenishment and linked Sales risk without altering product identity',()=>{
 const mod={exports:{}};new Function('require','module','exports',delivery)(require,mod,mod.exports);
 for(const [lang,w] of [['en',en],['ar',ar]]){const html=renderToStaticMarkup(createElement(mod.exports.default,{rows:[{item_id:'I',request_type:'STOCK_REPLENISHMENT',sales_order_id:'S',sales_order_code:'SO-1',target_ready:order.target_ready,requested_delivery:order.requested_delivery,promised_delivery:order.promised_delivery,risk:'late'}],item:'I',lang,t:k=>w[k]||k,zone:'UTC'}));assert.ok(html.includes(w.stockReplenishment));assert.ok(html.includes(w.deliveryRisk_late));assert.match(html,/dir="ltr"/);assert.match(html,/SO-1/);assert.doesNotMatch(html,/product-surface/);}
});
test('Lazy reader aborts a previous factory read and hides stale factory data',async()=>{
 const code=(await build({entryPoints:['src/features/useFulfillment.ts'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'})).outputFiles[0].text;
 const states=[];let idx=0;let effect;const mod={exports:{}};
 new Function('require','module','exports',code)(n=>n==='react'?{useState(initial){const i=idx++;if(!(i in states))states[i]=initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useEffect(fn){effect=fn;}}:require(n),mod,mod.exports);
 const reads=[],prior=globalThis.fetch;globalThis.fetch=(url,options)=>new Promise(resolve=>reads.push({url,options,resolve}));
 try{function render(factory){idx=0;return mod.exports.useFulfillment({factory:{id:factory},fetchedAt:'fresh'},'sales',2,true);}render('F');const cleanup=effect();assert.match(reads[0].url,/factory=F/);assert.match(reads[0].url,/page=2/);cleanup();render('G');effect();reads[0].resolve({ok:true,json:async()=>({rows:['stale']})});reads[1].resolve({ok:true,json:async()=>({rows:['current']})});await new Promise(resolve=>setImmediate(resolve));assert.deepEqual(render('G').data,{rows:['current']});assert.equal(render('F').data,null);assert.equal(reads[0].options.signal.aborted,true);}finally{globalThis.fetch=prior;}
});
import { permissionModule, previewPermissions } from '../src/utils/permission-preview.mjs';
test('Sales navigation uses its actual permission module and cannot bounce to overview',()=>{
 assert.equal(permissionModule('sales'),'sales_orders');const permissions=['sales_orders:view'];assert.ok(permissions.includes(`${permissionModule('sales')}:view`));assert.equal(permissions.includes(`${permissionModule('dashboard')}:view`),false);
});
test('Sales preview exposes Sales only when the person actually possesses those grants',()=>{
 assert.deepEqual(previewPermissions(['sales_orders:view','warehouse:view','warehouse:issue'],'sales'),['sales_orders:view','warehouse:view']);assert.deepEqual(previewPermissions(['orders:view'],'sales'),['orders:view']);
});
test('Frozen Planning and Product pages retain the orders permission module',()=>{
 for(const page of ['planning','products','unfinishedProducts'])assert.equal(permissionModule(page),'orders');assert.equal(permissionModule('warehouse'),'warehouse');
});
