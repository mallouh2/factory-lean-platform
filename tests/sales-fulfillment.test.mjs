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
for(const name of ['SalesOrders','Warehouse']) bundles[name]=(await build({entryPoints:[`src/features/${name}.tsx`],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'read-fixture',setup(b){b.onResolve({filter:/useFulfillment$/},()=>({path:'test:read',external:true}));}}]})).outputFiles[0].text;
const delivery=(await build({entryPoints:['src/components/DeliveryContext.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'})).outputFiles[0].text;
const snapshot={factory:{id:'F',timezone:'UTC',delivery_buffer_days:2},tables:{products:[{id:'P',name:'QA pipe',name_ar:'أنبوب اختبار',stage:'finished'},{id:'P2',name:'QA fitting',stage:'finished'}],production_orders:[],production_requests:[],unfinished_lots:[],work_centers:[],memberships:[]}};
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
 for(const k of ['customerRequested','promisedDelivery','estimatedReady','earliestFeasible','stockReserved','stockIncoming','productionRequired','holdCompleteOrder','requestedNotFeasible']) assert.ok(html.includes(w[k]),k);
 assert.match(html,/SO-0000001/);assert.ok(html.includes(lang==='ar'?'أنبوب اختبار':'QA pipe'));assert.match(html,/data-risk="at_risk"/);assert.match(html,new RegExp(`dir="${lang==='ar'?'rtl':'ltr'}"`));assert.equal(JSON.stringify(h.props.snapshot),before);
 });
 test(`Warehouse holds incomplete order and presents typed balances in ${lang}`,()=>{
 const h=harness('Warehouse',{rows:[{product_id:'P',name:'QA pipe',name_ar:'أنبوب اختبار',unit:'meter',on_hand:100,reserved:40,available:60,incoming:60,projected:120,supply_mode:'MAKE_TO_STOCK',minimum_stock:50,maximum_stock:150}],orders:[order],total:1,orders_total:1},()=>true,async()=>{},lang),html=h.html(),w=lang==='ar'?ar:en;
 for(const k of ['stock_on_hand','stock_reserved','stock_available','stock_incoming','stock_projected','warehouseHoldHelp']) assert.ok(html.includes(w[k]),k);
 assert.ok(!html.includes('>'+w.dispatchOrder+'</button>'));assert.ok(!html.includes('>'+w.dispatchProductLine+'</button>'));
 });
}
test('Sales approval is per-person, not a job title or preview role',()=>{
 const h=harness('SalesOrders',{rows:[{...order,status:'draft',fulfillment_status:'draft'}],total:1},(m,a='view')=>a==='view');const html=h.html();assert.ok(!html.includes('>'+en.salesApprove+'</button>'));assert.ok(!html.includes('>'+en.salesCreate+'</button>'));
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
test('Create Sales preserves typed unit, exact requested time, independent promise and hold default',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[],total:0},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 const change=(find,value)=>h.nodes().find(find).props.onChange({target:{value}});
 change(n=>n.type==='input'&&n.props.type==='datetime-local'&&n.props.required,'2026-10-10T14:30');
 change(n=>n.type==='input'&&n.props.type==='datetime-local'&&!n.props.required,'2026-10-11T15:45');
 change(n=>n.type==='select'&&n.props.children?.[1]?.length,'P');
 change(n=>n.type==='input'&&n.props.type==='number'&&n.props.step==='any','100');
 change(n=>n.type==='select'&&n.props.children?.[1]?.props?.value==='meter','meter');
 const event={preventDefault(){}};h.nodes().find(n=>n.type==='form').props.onSubmit(event);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][0],'create_sales_order');const p=calls[0][1].payload;assert.equal(p.requested_delivery,'2026-10-10T14:30:00.000Z');assert.equal(p.promised_delivery,'2026-10-11T15:45:00.000Z');assert.equal(p.lines[0].unit,'meter');assert.equal(p.lines[0].quantity,100);assert.equal(p.lines[0].release_when_ready,false);
});
test('Product-line early release is explicit and defaults off',()=>{
 const h=harness('SalesOrders',{rows:[],total:0});h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();const check=h.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox');assert.equal(check.props.checked,false);check.props.onChange({target:{checked:true}});assert.equal(h.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox').props.checked,true);
});
test('Draft cannot edit promise or buffer without approve permission',()=>{
 const h=harness('SalesOrders',{rows:[],total:0},(_m,a='view')=>a!=='approve');h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 assert.equal(h.nodes().find(n=>n.type==='input'&&n.props.type==='datetime-local'&&!n.props.required).props.disabled,true);assert.equal(h.nodes().find(n=>n.type==='input'&&n.props.max==='90').props.disabled,true);
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
