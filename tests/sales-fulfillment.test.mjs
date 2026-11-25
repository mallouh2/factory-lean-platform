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
for(const name of ['SalesOrders','Warehouse','WarehouseReceiving','WarehouseInventory','WarehouseMovements','SalesPlanningGuidance']) bundles[name]=(await build({entryPoints:[`src/${name==='SalesPlanningGuidance'?'components':'features'}/${name}.tsx`],bundle:true,loader:{'.css':'empty','.module.css':'empty'},platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'read-fixture',setup(b){b.onResolve({filter:/useFulfillment$/},()=>({path:'test:read',external:true}));b.onResolve({filter:/WarehouseDefinitions$/},()=>({path:'test:warehouses',external:true}));b.onResolve({filter:/useSupply$/},()=>({path:'test:supply',external:true}));}}]})).outputFiles[0].text;
const delivery=(await build({entryPoints:['src/components/DeliveryContext.tsx'],bundle:true,loader:{'.css':'empty'},platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'})).outputFiles[0].text;
const snapshot={user:{id:'local-owner'},factory:{id:'F',timezone:'UTC',delivery_buffer_days:2},tables:{products:[{id:'P',name:'QA pipe',name_ar:'أنبوب اختبار',stage:'finished',product_kind:'FINISHED_PRODUCT',stock_unit:'meter',unit_weight_kg:0.5},{id:'P2',name:'QA fitting',stage:'finished'}],production_orders:[],production_requests:[],unfinished_lots:[],work_centers:[],memberships:[]}};
for(const lang of ['en','ar']) for(const state of ['achievable','tight','unachievable','insufficient']) test(`Planning drawer makes ${state} guidance and signed proposal margin explicit in ${lang}`,()=>{
 const h=harness('SalesPlanningGuidance',null,()=>true,async()=>{},lang),w=lang==='ar'?ar:en;
 Object.assign(h.props,{factory:'F',item:'I',fetchedAt:'stamp',zone:'UTC',proposal:{finish:Date.parse('2026-10-12T15:00Z')}});
 h.nodes();h.states[0]={key:'F:I',data:{state,requested_delivery:'2026-10-10T14:30Z',target_ready:'2026-10-08T14:30Z',safety_buffer_days:2,suggestion:state==='achievable'||state==='tight'?{start:'2026-10-08T13:00Z',finish:'2026-10-08T14:30Z',minutes:90}:null}};
 const html=h.html();assert.ok(html.includes(w['target_'+state]));assert.ok(html.includes(w.proposalMeetsTarget));assert.ok(html.includes(w.no));assert.ok(html.includes(w.targetMargin));assert.match(html,/-/);
 if(state==='achievable'||state==='tight')assert.ok(html.includes(lang==='ar'?'١ س ٣٠ د':'1 h 30 min'));
});
test('Planning drawer with no customer date displays no suggested target or margin',()=>{
 const h=harness('SalesPlanningGuidance',null);Object.assign(h.props,{factory:'F',item:'I',fetchedAt:'stamp',proposal:null});h.nodes();h.states[0]={key:'F:I',data:{requested_delivery:null,state:'no_target'}};
 const html=h.html();assert.ok(html.includes(en.noCustomerTarget));assert.ok(!html.includes(en.suggestedStart));assert.ok(!html.includes(en.targetMargin));
});

test('Sales creates an order without a requested date or promise payload',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[],total:0},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 {const picker=h.nodes().find(n=>n.props?.options?.some(o=>o.id==='P'));if(picker&& !picker.props.value){picker.props.onChange('P');const qty=h.nodes().find(n=>n.type==='input'&&n.props.step==='any');if(qty&&!qty.props.value)qty.props.onChange({target:{value:'10'}});}}
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][1].payload.requested_delivery,null);assert.ok(!Object.hasOwn(calls[0][1].payload,'promised_delivery'));
});
test('Sales editing clears the optional target without altering a historical promise',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[order],total:1},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.edit).props.onClick();
 h.nodes().find(n=>n.type==='input'&&n.props.type==='datetime-local').props.onChange({target:{value:''}});
 {const picker=h.nodes().find(n=>n.props?.options?.some(o=>o.id==='P'));if(picker&& !picker.props.value){picker.props.onChange('P');const qty=h.nodes().find(n=>n.type==='input'&&n.props.step==='any');if(qty&&!qty.props.value)qty.props.onChange({target:{value:'10'}});}}
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][1].payload.requested_delivery,null);assert.ok(!Object.hasOwn(calls[0][1].payload,'promised_delivery'));
});
test('Native customer-date input survives another field change and submits in the factory timezone',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[],total:0},()=>true,async(...args)=>calls.push(args));h.props.snapshot.factory.timezone='Asia/Qatar';
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 h.nodes().find(n=>n.type==='input'&&n.props.type==='datetime-local').props.onInput({currentTarget:{value:'2026-10-15T15:00'}});
 h.nodes().find(n=>n.type==='input'&&n.props.maxLength===200).props.onChange({target:{value:'Customer target'}});
 {const picker=h.nodes().find(n=>n.props?.options?.some(o=>o.id==='P'));if(picker&& !picker.props.value){picker.props.onChange('P');const qty=h.nodes().find(n=>n.type==='input'&&n.props.step==='any');if(qty&&!qty.props.value)qty.props.onChange({target:{value:'10'}});}}
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][1].payload.requested_delivery,'2026-10-15T12:00:00.000Z');assert.ok(!Object.hasOwn(calls[0][1].payload,'promised_delivery'));
});
test('Undated Sales has no risk/deadline message; external and hybrid shortages stay explicit',()=>{
 const html=harness('SalesOrders',{rows:[{...order,requested_delivery:null,target_ready:null,estimated_ready:null,risk:'none',lines:[{...line,external_shortage:25,source_decision_quantity:10}]}],total:1}).html();
 assert.ok(!html.includes(en.targetReady));assert.ok(!html.includes(en.deliveryRisk_none));assert.ok(html.includes(en.externalReplenishment));assert.ok(html.includes(en.sourcingDecision));assert.ok(html.includes(en.readinessPending));
});
for(const source of ['EXTERNAL','BOTH']) test('Inventory displays authoritative '+source+' replenishment without inventing incoming',()=>{const row={id:'P',row_key:'P:piece',entity:'finished',name:'QA item',item_type:'FINISHED_GOOD',unit:'piece',on_hand:5,reserved:0,available:5,incoming:0,in_production:0,projected:5,supply_source:source,minimum_stock:20,maximum_stock:50,minimum_status:'AT_OR_BELOW_MIN',replenishment_status:source==='EXTERNAL'?'EXTERNAL_REQUIRED':'SOURCING_REQUIRED'};const key=source==='EXTERNAL'?'inventory_EXTERNAL_REQUIRED':'inventory_SOURCING_REQUIRED';assert.ok(harness('WarehouseInventory',{rows:[row],total:1}).html().includes(en[key]));const html=harness('WarehouseInventory',{rows:[{...row,on_hand:30,available:30,projected:30,minimum_status:'ABOVE_MIN',replenishment_status:'OK'}],total:1}).html();assert.ok(!html.includes(en[key]));assert.match(html,/30/);assert.ok(!html.includes('data-low="true"'));});
for(const lang of ['en','ar']) test(`Warehouse receiving respects per-person grants and raw stock units in ${lang}`,()=>{
 const h=harness('WarehouseReceiving',null,(_m,a='view')=>a==='view',async()=>{},lang),w=lang==='ar'?ar:en;
 h.props.materials=[{id:'M',name:'Resin',name_ar:'راتنج',code:'R',unit:'kg',inventory_kind:'RAW_MATERIAL',on_hand:100,reserved:20}];h.props.refresh=()=>{};
 const html=h.html();assert.ok(html.includes(w.RAW_MATERIAL));assert.ok(html.includes(w.kg));assert.ok(html.includes('80'));assert.ok(!html.includes('>'+w.receiveStock+'</button>'));assert.ok(!html.includes('>'+w.openingStock+'</button>'));assert.ok(html.includes(w.stockMovements));
});
for(const lang of ['en','ar']) test('Movement history separates reservation changes from physical stock in '+lang,()=>{const h=harness('WarehouseMovements',{rows:[{id:'R',kind:'reservation',quantity:'0',reserved_delta:'100',unit:'meter',created_at:'2026-10-03T12:00Z',actor_name:'Warehouse person'}],total:1},()=>true,async()=>{},lang),w=lang==='ar'?ar:en;h.props.initialItem={id:'P',entity:'finished',unit:'meter',name:'QA pipe',code:'P'};h.props.snapshot.tables.products[0].stock_unit='meter';const html=h.html();assert.match(html,/movement-neutral/);assert.ok(html.includes(w.reservedMovementDelta));assert.ok(html.includes((100).toLocaleString(lang)));assert.ok(html.includes('Warehouse person'));assert.ok(html.includes(lang==='ar'?'دون تغيير المخزون الفعلي':'No physical stock change'));});
for(const source of ['external_receipt','opening_balance']) test('Warehouse '+source+' uses protected receipt API with configured unit and no client actor/time',async()=>{const calls=[],requests=[],h=harness('WarehouseReceiving',null,()=>true,async(...args)=>calls.push(args));h.props.refresh=()=>{};h.props.materials=[];h.props.snapshot.tables.products[0].stock_unit='meter';h.nodes().find(n=>n.type==='button'&&n.props.children===en[source==='opening_balance'?'openingStock':'receiveStock']).props.onClick();h.nodes().find(n=>Array.isArray(n.props?.options)&&n.props.label===en.item).props.onChange('P');h.nodes().find(n=>n.type==='input'&&n.props.type==='number').props.onChange({target:{value:'2500'}});const prior=globalThis.fetch;globalThis.fetch=async(url,options)=>{requests.push({url,body:JSON.parse(options.body)});return{ok:true,json:async()=>({})};};try{{const picker=h.nodes().find(n=>n.props?.options?.some(o=>o.id==='P'));if(picker&& !picker.props.value){picker.props.onChange('P');const qty=h.nodes().find(n=>n.type==='input'&&n.props.step==='any');if(qty&&!qty.props.value)qty.props.onChange({target:{value:'10'}});}}
 h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(r=>setImmediate(r));}finally{globalThis.fetch=prior;}assert.equal(requests.length,1);assert.equal(requests[0].url,'/api/warehouses');const body=requests[0].body;assert.equal(body.operation,'RECEIVE_STOCK');assert.equal(body.factory,'F');assert.ok(body.request_id);assert.equal(body.payload.unit,'meter');assert.equal(body.payload.quantity,2500);assert.equal(body.payload.source,source);assert.equal(body.payload.warehouse_id,'W');assert.ok(!Object.hasOwn(body.payload,'created_by'));assert.ok(!Object.hasOwn(body.payload,'created_at'));assert.equal(calls.length,0);});
const line={id:'L',product_id:'P',product_name:'QA pipe',product_name_ar:'أنبوب اختبار',quantity:100,unit:'meter',reserved_quantity:40,incoming_quantity:60,production_required:60,dispatched_quantity:0,release_when_ready:false,ready:false,dispatch_allowed:false};
const order={id:'S',code:'SO-0000001',customer_reference:'QA customer',requested_delivery:'2026-10-10T14:30:00Z',promised_delivery:'2026-10-11T14:30:00Z',estimated_ready:'2026-10-10T15:00:00Z',earliest_feasible:'2026-10-10T15:00:00Z',safety_buffer_days:2,target_ready:'2026-10-09T14:30:00Z',status:'approved',fulfillment_status:'approved',risk:'at_risk',requested_feasible:false,delay_days:0,notes:'',lines:[line],dispatch_allowed:false};
function harness(name,data,can=()=>true,command=async()=>{},lang='en'){
 const states=[];let index=0;const dictionary=lang==='ar'?ar:en;const mod={exports:{}};
 new Function('require','module','exports',bundles[name])(n=>n==='test:read'?{useFulfillment:(_s,_m,_p,enabled)=>({data:enabled?(_m==='pool'?data.pool:_m==='confirmation'?data.confirmation:data):null,busy:false,error:'',refresh(){}})}:n==='test:warehouses'?{__esModule:true,default:()=>null,useWarehouses:()=>({ready:true,rows:[{id:'W',active:true,storage_class:'FINISHED',name:'Finished store'},{id:'R',active:true,storage_class:'RAW',name:'Raw store'}]}),WarehouseSelector:()=>null}:n==='test:supply'?{useSupply:()=>({data:{recent:[],rows:[],total:0},busy:false,error:'',refresh(){}}),useSupplyCommand:()=>({run:async()=>true,busy:false,error:'',clearError(){}})}:n==='react'?{...react,useState(initial){const i=index++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useId:()=> 'sales-fixture',useEffect(){},useRef:()=>({current:null})}:require(n),mod,mod.exports);
 const props={snapshot:structuredClone(snapshot),can,command,lang,t:k=>dictionary[k]||k,onChanged(){},onConfigure(){},onReceive(){}};
 function tree(){index=0;return mod.exports.default(props);}
 function all(n){if(!n||typeof n!=='object')return[];if(Array.isArray(n))return n.flatMap(all);return[n,...all(n.props?.children)];}
 return{nodes:()=>all(tree()),html:()=>renderToStaticMarkup(tree()),states,props};
}
for(const lang of ['en','ar']){
 test(`Sales separates requested/promised/estimated, stock and incoming in ${lang}`,()=>{
 const h=harness('SalesOrders',{rows:[order],total:1},()=>true,async()=>{},lang);const before=JSON.stringify(h.props.snapshot);const html=h.html(),w=lang==='ar'?ar:en;
 for(const k of ['customerRequested','historicalPromise','estimatedReady','earliestFeasible','stockReserved','salesExpectedIncoming','productionRequired','salesWarehouseDispatch','requestedNotFeasible']) assert.ok(html.includes(w[k]),k);
 assert.match(html,/SO-0000001/);assert.ok(html.includes(lang==='ar'?'أنبوب اختبار':'QA pipe'));assert.match(html,/data-risk="at_risk"/);assert.match(html,new RegExp(`dir="${lang==='ar'?'rtl':'ltr'}"`));assert.equal(JSON.stringify(h.props.snapshot),before);
 });
 test('Warehouse Requests opens the existing pooled dispatch drawer in '+lang,()=>{const h=harness('Warehouse',{rows:[],orders:[order],total:0,orders_total:1,pool:{rows:[{id:'L',ordered:'100',reserved:'40',dispatched:'0',outstanding:'100',dispatchable:'40'}]}},()=>true,async()=>{},lang),w=lang==='ar'?ar:en;h.nodes().find(n=>n.props?.role==='tab'&&n.props.id?.endsWith('-requests-tab')).props.onClick();const requests=h.nodes().find(n=>typeof n.props?.onDispatch==='function');assert.equal(requests.props.active,true);requests.props.onDispatch(order,line);const html=h.html();assert.ok(html.includes(w.stockReserved));assert.ok(html.includes(w.stockDispatched));assert.ok(html.includes(w.confirmDispatch));assert.ok(html.includes(lang==='ar'?'المتاح للإرسال الآن':'Dispatchable now'));assert.ok(!h.nodes().some(n=>n.type?.name==='SourceAllocationFields'));});
}
test('Sales approval is per-person, not a job title or preview role',()=>{
 const h=harness('SalesOrders',{rows:[{...order,status:'draft',fulfillment_status:'draft'}],total:1},(m,a='view')=>a==='view');const html=h.html();assert.ok(!html.includes('>'+en.salesApprove+'</button>'));assert.ok(!html.includes('>'+en.salesCreate+'</button>'));
});
for(const lang of ['en','ar']) test('Warehouse keeps two workspaces and contextual management in '+lang,()=>{const h=harness('Warehouse',{rows:[],orders:[],total:0},()=>true,async()=>{},lang),w=lang==='ar'?ar:en,html=h.html();assert.ok(html.includes(w.receiveStock));assert.ok(html.includes(w.whManagementRecords.replaceAll('&','&amp;')));assert.ok(html.includes(w.whItemStockSettings.replaceAll('&','&amp;')));assert.equal(h.nodes().filter(n=>n.props?.role==='tab').length,2);h.nodes().find(n=>n.props?.id?.endsWith('-requests-tab')).props.onClick();assert.equal(h.nodes().find(n=>typeof n.props?.onDispatch==='function').props.active,true);assert.ok(!html.includes(w.supplierDirectory));assert.ok(!h.nodes().some(n=>n.type==='button'&&[w.adjustStock,w.configureStock].includes(n.props.children)));});
test('Configuring a historical stock-unit row preserves current catalogue unit and Min/Max',()=>{
 const h=harness('Warehouse',{rows:[],orders:[],total:0,orders_total:0},()=>true);
 Object.assign(h.props.snapshot.tables.products[0],{stock_unit:'meter',minimum_stock:70,maximum_stock:300,supply_mode:'MAKE_TO_STOCK',supply_source:'MANUFACTURED'});
 h.nodes().find(n=>typeof n.props?.onConfigure==='function').props.onConfigure({id:'P',name:'QA pipe',unit:'piece',minimum_stock:null,maximum_stock:null,supply_source:'MANUFACTURED'});
 const nodes=h.nodes();assert.ok(nodes.some(n=>n.type==='select'&&n.props.value==='meter'));assert.ok(nodes.some(n=>n.type==='input'&&n.props.value==='70'));assert.ok(nodes.some(n=>n.type==='input'&&n.props.value==='300'));
});
test('Warehouse dispatch treats read access separately from protected issue authority',async()=>{for(const allowed of[true,false]){let applied=0;const h=harness('Warehouse',{rows:[],orders:[order],total:0,orders_total:1,pool:{rows:[{id:'L',ordered:'100',reserved:'40',dispatched:'0',outstanding:'100',dispatchable:'40'}]}},(_m,a='view')=>a!=='issue'||allowed,async name=>{assert.equal(name,'dispatch_sales_quantity');if(!allowed)throw Error('permissionError');applied++;});h.nodes().find(n=>n.props?.id?.endsWith('-requests-tab')).props.onClick();h.nodes().find(n=>typeof n.props?.onDispatch==='function').props.onDispatch(order,line);h.nodes().find(n=>n.type==='button'&&n.props.children===en.confirmDispatch).props.onClick();await new Promise(r=>setImmediate(r));assert.equal(applied,allowed?1:0);if(!allowed)assert.ok(h.html().includes(en.permissionError));}});
test('Physical pooled dispatch submits the selected partial quantity without source picks',async()=>{const calls=[],h=harness('Warehouse',{rows:[],orders:[order],total:0,orders_total:1,pool:{rows:[{id:'L',ordered:'100',reserved:'40',dispatched:'0',outstanding:'100',dispatchable:'40',source_assigned:'0'}]}},()=>true,async(...args)=>calls.push(args));h.nodes().find(n=>n.props?.id?.endsWith('-requests-tab')).props.onClick();h.nodes().find(n=>typeof n.props?.onDispatch==='function').props.onDispatch(order,line);assert.ok(!h.nodes().some(n=>n.type?.name==='SourceAllocationFields'));h.nodes().find(n=>n.type==='input'&&n.props.inputMode==='decimal').props.onChange({target:{value:'41'}});assert.equal(h.nodes().find(n=>n.type==='button'&&n.props.children===en.confirmDispatch).props.disabled,true);h.nodes().find(n=>n.type==='input'&&n.props.inputMode==='decimal').props.onChange({target:{value:'20'}});const button=h.nodes().find(n=>n.type==='button'&&n.props.children===en.confirmDispatch);assert.equal(button.props.disabled,false);button.props.onClick();await new Promise(r=>setImmediate(r));assert.equal(calls[0][0],'dispatch_sales_quantity');assert.equal(calls[0][1].quantity,'20');assert.equal(calls[0][1].line,'L');assert.equal(calls[0][1].factory,'F');assert.ok(calls[0][1].request_id);});
test('Create Sales preserves typed unit, exact optional customer time and hold default, without a promise writer',async()=>{
 const calls=[],h=harness('SalesOrders',{rows:[],total:0},()=>true,async(...args)=>calls.push(args));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.salesCreate).props.onClick();
 const change=(find,value)=>h.nodes().find(find).props.onChange({target:{value}});
 change(n=>n.type==='input'&&n.props.type==='datetime-local','2026-10-10T14:30');
 assert.equal(h.nodes().filter(n=>n.type==='input'&&n.props.type==='datetime-local').length,1);
 assert.ok(!h.nodes().find(n=>n.type==='input'&&n.props.type==='datetime-local').props.required);
 h.nodes().find(n=>n.props?.options?.some(o=>o.id==='P')).props.onChange('P');
 change(n=>n.type==='input'&&n.props.type==='number'&&n.props.step==='any','100');
 change(n=>n.type==='select'&&n.props.children.flat(Infinity).some(child=>child?.props?.value==='meter'),'meter');
 const event={preventDefault(){}};h.nodes().find(n=>n.type==='form').props.onSubmit(event);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls[0][0],'create_sales_order');const p=calls[0][1].payload;assert.equal(p.requested_delivery,'2026-10-10T14:30:00.000Z');assert.ok(!Object.hasOwn(p,'promised_delivery'));assert.equal(p.lines[0].unit,'meter');assert.equal(p.lines[0].quantity,'100');assert.equal(p.lines[0].release_when_ready,false);
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
 const code=(await build({entryPoints:['src/features/useFulfillment.ts'],bundle:true,loader:{'.css':'empty'},platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'})).outputFiles[0].text;
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

for(const lang of ['en','ar'])test('Completed Sales shows confirmed delivery rather than pending instructions '+lang,()=>{const h=harness('SalesOrders',{rows:[{...order,status:'completed',lines:[{...line,quantity:1030,dispatched_quantity:1030}]}],total:1},()=>true,async()=>{},lang),w=lang==='ar'?ar:en,html=h.html();assert.ok(html.includes(w.salesDeliveryConfirmed));assert.ok(!html.includes(w.salesWarehouseDispatch));assert.ok(html.includes('1030'));});
