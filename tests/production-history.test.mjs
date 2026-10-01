import test from 'node:test';
import assert from 'node:assert/strict';
import { historyQuery,parseHistoryQuery } from '../src/utils/production-history.mjs';
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
import {planningProductTones} from '../src/utils/planning.mjs';
const require=createRequire(import.meta.url);
const output=await build({entryPoints:['src/features/ProductionHistory.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'});
const module={exports:{}};new Function('require','module','exports',output.outputFiles[0].text)(require,module,module.exports);
const result={page:1,page_size:50,total:437,rows:[{id:'row',created_at:'2026-09-30T10:00:00Z',request_code:'PO-QA',product_name:'Pipe',product_name_ar:'أنبوب',unit_name:'Line 1',unit_name_ar:'الخط ١',unit:'meter',technician_name:'Operator',submitter_name:'Supervisor',effective_good:250,effective_scrap:12,good_quantity:260,scrap_quantity:10,running_good:750,remaining_quantity:250,shift_id:null,corrected:true,corrections:[{id:'correction',created_at:'2026-09-30T11:00:00Z',previous_good:260,previous_scrap:10,corrected_good:250,corrected_scrap:12,reason:'Counter reconciliation',shift_changed:true}]}],totals:[{measurement_unit:'meter',good:10000,scrap:580},{measurement_unit:'piece',good:8200,scrap:40}],highest:[{measurement_unit:'meter',kind:'unit',name:'Line 1',name_ar:'الخط ١',scrap:580},{measurement_unit:'meter',kind:'shift',name:null,scrap:580}]};
function render(lang='en',edit=true,data=result){const dictionary=lang==='ar'?ar:en;return renderToStaticMarkup(createElement(module.exports.default,{snapshot:{factory:{id:'f',timezone:'UTC'},tables:{},fetchedAt:'today'},t:k=>dictionary[k] || k,lang,can:(_,a)=>a==='edit'?edit:true,command:()=>{throw Error('render cannot write');},onCorrect:()=>{},initial:data}));}
test('History reuses full-catalog Product accents in desktop cells and mobile cards without changing history values',()=>{
 const products=[{id:'P',name:'Pipe'},{id:'Q',name:'Other'}],tone=planningProductTones(products).get('P');
 const data={...result,rows:[{...result.rows[0],product_id:'P'}]},before=JSON.stringify(data);
 for(const [lang,words] of [['en',en],['ar',ar]]){
  const html=renderToStaticMarkup(createElement(module.exports.default,{snapshot:{factory:{id:'f',timezone:'UTC'},tables:{products},fetchedAt:'today'},
   t:k=>words[k]||k,lang,can:()=>false,command:()=>{throw Error('render cannot write');},onCorrect:()=>{},initial:data}));
  assert.equal((html.match(new RegExp('--product-surface:'+tone.surface,'g'))||[]).length,2);
  assert.equal((html.match(/data-product-id="P"/g)||[]).length,2);
 }
 assert.equal(JSON.stringify(data),before);
});
for(const key of ['request','product','unit','technician','shift','from','to','scrap','minimum_scrap','corrected'])test(`server query preserves ${key} filter across pages`,()=>{const value={from:'2026-09-01',to:'2026-09-30',minimum_scrap:'2'}[key] || 'selected';const query=new URLSearchParams(historyQuery('factory',{[key]:value},'scrap','desc',3));assert.equal(parseHistoryQuery(query).filters[key],value);assert.equal(parseHistoryQuery(query).page,3);});
test('combined filters and server sorting survive pagination',()=>{const filters={request:'r',product:'p',unit:'line:l',technician:'t',shift:'s',from:'2026-09-01',to:'2026-09-30'};const parsed=parseHistoryQuery(new URLSearchParams(historyQuery('f',filters,'good','asc',2)));assert.deepEqual(parsed,{filters,sort_key:'good',sort_direction:'asc',page:2});});
test('unsupported sorting, inverted dates and invalid pages are rejected',()=>{for(const q of ['sort=sql','direction=invalid','page=0','page=1.5','page=1000001','from=invalid','from=2026-09-30&to=2026-09-01','minimum_scrap=-1'])assert.throws(()=>parseHistoryQuery(new URLSearchParams(q)));});
test('table exposes server totals across whole result and separates units',()=>{const html=render();assert.match(html,/<table>/);assert.ok(html.includes('437'));assert.ok(html.includes('10,000'));assert.ok(html.includes('8,200'));assert.ok(html.includes('580'));assert.ok(html.includes('pcs'));assert.ok(html.includes('m'));assert.ok(html.includes('1 / <!-- -->9') || html.replace(/<[^>]+>/g,'').includes('1 / 9'));});
test('NULL shift is explicit in EN/AR and corrected audit preserves original',()=>{for(const lang of ['en','ar']){const words=lang==='ar'?ar:en;const html=render(lang);assert.ok(html.includes(words.shiftNotRecorded));assert.ok(html.includes(words.historyCorrected));assert.ok(html.includes('Counter reconciliation'));assert.ok(html.includes('260'));assert.ok(html.includes('250'));assert.ok(html.includes('Supervisor'));}});
test('read-only history has no correction action',()=>{assert.ok(!render('en',false).includes(en.recordingCorrect));assert.ok(render('en',true).includes(en.recordingCorrect));});
test('mobile has compact cards and expandable audit; Arabic has explicit RTL',()=>{assert.match(render(),/history-mobile/);assert.match(render(),/<details>/);assert.match(render('ar'),/dir="rtl"/);assert.match(render('ar'),/<bdi>/);assert.ok(!render().includes('uuid'));});
test('empty results show actionable state and page actions disabled',()=>{const html=render('en',true,{...result,rows:[],total:0,totals:[],highest:[]});assert.ok(html.includes(en.historyNoMatches));assert.match(html,/<button disabled="">Previous/);assert.match(html,/<button disabled="">Next/);});

test('correction column and filter share explicit EN/AR wording and both record states',()=>{
 for(const lang of ['en','ar']){
  const words=lang==='ar'?ar:en,html=render(lang,true,{...result,rows:[...result.rows,{...result.rows[0],id:'original',corrected:false,corrections:[]}]});
  assert.ok(html.includes(`<th scope="col">${words.historyCorrections}<button`));
  assert.ok(html.includes(`<td>${words.historyCorrected}</td>`));assert.ok(html.includes(`<td>${words.historyUncorrected}</td>`));
  assert.ok(!html.includes(`<th scope="col">${words.status}</th>`));
 }
 assert.equal(en.historyCorrections,'Correction status');assert.equal(en.historyUncorrected,'Original');
 assert.equal(ar.historyCorrections,'حالة التصحيح');assert.equal(ar.historyCorrected,'مصحح');assert.equal(ar.historyUncorrected,'أصلي');
});

// Exercise the actual component's effects with deferred reads, including abort-ignoring late responses.
// Browser verification separately checks DOM identity, native details and scroll positions.
function historyHarness(){
 const react=require('react'),states=[],effects=[],pending=[],reads=[];let cursor=0,tree;
 let props={snapshot:{factory:{id:'f',timezone:'UTC'},tables:{},fetchedAt:'first'},t:k=>en[k]||k,lang:'en',can:()=>true,command:()=>{throw Error('History must not write');},onCorrect:()=>{}};
 const fakeReact={...react,useState:initial=>{const i=cursor++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;
  return [states[i],value=>{states[i]=typeof value==='function'?value(states[i]):value;}];},
  useEffect:(fn,deps)=>{const i=cursor++,old=effects[i];if(!old||deps.some((d,j)=>!Object.is(d,old.deps[j])))pending.push(()=>{old?.cleanup?.();effects[i]={deps,cleanup:fn()};});}};
 const m={exports:{}};new Function('require','module','exports',output.outputFiles[0].text)(name=>name==='react'?fakeReact:require(name),m,m.exports);
 const previousDocument=globalThis.document,previousWindow=globalThis.window;globalThis.document={getElementById:()=>({hidePopover(){}})};globalThis.window={innerWidth:1280,innerHeight:720};const previousFetch=globalThis.fetch;globalThis.fetch=(url,init)=>new Promise(resolve=>reads.push({url,signal:init.signal,resolve}));
 function draw(update){if(update)props={...props,...update};cursor=0;tree=m.exports.default(props);while(pending.length)pending.shift()();return tree;}
 function nodes(node=tree){if(!node||typeof node!=='object')return [];return[node,...[node.props?.children].flat(Infinity).flatMap(child=>child?nodes(child):[])];}
 async function settle(read,data,ok=true){read.resolve({ok,json:async()=>data});await new Promise(resolve=>setImmediate(resolve));draw();}
 return{draw,nodes,reads,settle,refresh:()=>draw({snapshot:{...props.snapshot,fetchedAt:props.snapshot.fetchedAt+'x'}}),
  open:key=>{nodes().find(n=>n.type==='button'&&n.props['aria-label']===en.historyFilterColumn+' '+en[key]).props.onClick({currentTarget:{getBoundingClientRect:()=>({left:300,right:400,bottom:150})}});draw();},
  apply:()=>{nodes().find(n=>n.type==='button'&&n.props.children===en.historyApply).props.onClick();draw();},
  field:label=>{const field=nodes().find(node=>node.props?.label===label);assert.ok(field,'missing field '+label);return nodes(field).find(node=>['select','input'].includes(node.type));},
  close:()=>{for(const effect of effects)effect?.cleanup?.();globalThis.fetch=previousFetch;globalThis.document=previousDocument;globalThis.window=previousWindow;}};
}
async function loadHistory(h){h.draw();await h.settle(h.reads[0],{shifts:[{id:'s',name:'Shift'}],requests:[{id:'r',name:'PO-QA'}]});await h.settle(h.reads[1],result);}

test('background refresh keeps loaded rows, row keys and filter options throughout pending reads',async()=>{
 const h=historyHarness();try{await loadHistory(h);h.open('productionShift');const keys=h.nodes().filter(n=>n.type==='tr').map(n=>n.key);
  h.refresh();assert.ok(h.nodes().some(n=>n.type==='table'));
  assert.deepEqual(h.nodes().filter(n=>n.type==='tr').map(n=>n.key),keys);
  assert.ok(h.nodes().some(n=>n.type==='option'&&n.props.value==='s'));
  await h.settle(h.reads.at(-1),result);assert.ok(h.nodes().some(n=>n.type==='table'));
 }finally{h.close();}
});
test('filters, sort, direction and page survive background and retry refreshes',async()=>{
 const h=historyHarness();try{await loadHistory(h);
  h.open('productionShift');h.field(en.productionShift).props.onChange({target:{selectedOptions:[{value:'s'}]}});h.draw();h.apply();await h.settle(h.reads.at(-1),result);
  h.field(en.historySort).props.onChange({target:{value:'scrap'}});h.draw();await h.settle(h.reads.at(-1),result);
  h.nodes().find(n=>n.type==='button'&&n.props.children===en.historyDescending).props.onClick();h.draw();await h.settle(h.reads.at(-1),result);
  h.nodes(h.nodes().find(n=>n.props?.className==='history-pagination')).find(n=>n.type==='button'&&n.props.children===en.next).props.onClick();h.draw();await h.settle(h.reads.at(-1),{...result,page:2});
  const expected=h.reads.at(-1).url;h.refresh();assert.equal(h.reads.at(-1).url,expected);
  assert.equal(h.field(en.productionShift).props.value.join(','),'s');assert.equal(h.field(en.historySort).props.value,'scrap');
  const query=new URL(expected,'http://localhost').searchParams;assert.equal(query.get('page'),'2');assert.equal(query.get('direction'),'asc');
  await h.settle(h.reads.at(-1),{},false);assert.ok(h.nodes().some(n=>n.type==='table'));
  h.nodes().find(n=>n.type==='button'&&n.props.children===en.refresh).props.onClick();h.draw();assert.equal(h.reads.at(-1).url,expected);
 }finally{h.close();}
});
test('changed queries and factories hide old rows immediately and ignore obsolete responses',async()=>{
 const h=historyHarness();try{await loadHistory(h);h.refresh();const obsolete=h.reads.at(-1);
  h.open('productionShift');h.field(en.productionShift).props.onChange({target:{selectedOptions:[{value:'s'}]}});h.draw();h.apply();assert.ok(!h.nodes().some(n=>n.type==='table'));
  await h.settle(obsolete,result);assert.ok(!h.nodes().some(n=>n.type==='table'));
  await h.settle(h.reads.at(-1),result);assert.ok(h.nodes().some(n=>n.type==='table'));
  h.draw({snapshot:{factory:{id:'other',timezone:'UTC'},tables:{},fetchedAt:'other'}});
  assert.ok(!h.nodes().some(n=>n.type==='table'));assert.ok(!h.nodes().some(n=>n.type==='option'&&n.props.value==='s'));
 }finally{h.close();}
});
test('background History error remains local and retains the loaded correction evidence',async()=>{
 const h=historyHarness();try{await loadHistory(h);h.refresh();await h.settle(h.reads.at(-1),{},false);
  assert.ok(h.nodes().some(n=>n.props?.role==='alert'));assert.ok(h.nodes().some(n=>n.type==='table'));
  assert.ok(h.nodes().some(n=>n.type==='li'&&n.key==='correction'));
 }finally{h.close();}
});
for(const key of ['date','productionShift','recordingUnit','historyOrder','product','recordingTechnician','recordingGood','recordingScrap','unfinishedQuantity','historyCorrections'])test(`header filter opens ${key} without a duplicate top panel`,async()=>{
 const h=historyHarness();try{await loadHistory(h);h.open(key);assert.ok(h.nodes().some(n=>n.props?.role==='dialog'));assert.ok(h.field(en.historyColumn));assert.ok(!h.nodes().some(n=>n.props?.className==='history-filters'));}finally{h.close();}
});
test('numeric header draft survives refresh; validated Apply uses full server query and Clear removes it',async()=>{
 const h=historyHarness();try{await loadHistory(h);h.open('recordingScrap');
 h.field(en.unit).props.onChange({target:{value:'piece'}});h.draw();
 h.field(en.historyMetric).props.onChange({target:{value:'percentage'}});h.draw();
 h.field(en.historyScope).props.onChange({target:{value:'shift'}});h.draw();
 h.field(en.historyCondition).props.onChange({target:{value:'gte'}});h.draw();
 h.field(en.historyValue+' (%)').props.onChange({target:{value:'5'}});h.draw();
 h.refresh();assert.equal(h.field(en.historyValue+' (%)').props.value,'5');assert.equal(h.field(en.historyScope).props.value,'shift');
 h.apply();const query=new URL(h.reads.at(-1).url,'http://localhost').searchParams;
 assert.equal(query.get('scrap_metric'),'percentage');assert.equal(query.get('scrap_scope'),'shift');assert.equal(query.get('scrap_min'),'5');assert.equal(query.get('measurement_unit'),'piece');
 await h.settle(h.reads.at(-1),result);h.open('recordingScrap');h.nodes().find(n=>n.type==='button'&&n.props.children===en.historyClearColumn).props.onClick();h.draw();
 assert.equal(new URL(h.reads.at(-1).url,'http://localhost').searchParams.has('scrap_op'),false);
 }finally{h.close();}
});
test('multi-select uses bounded searchable pages, shows selections, and Clear all removes combined filters',async()=>{
 const h=historyHarness();try{await loadHistory(h);h.open('historyOrder');h.field(en.historyOrder).props.onChange({target:{selectedOptions:[{value:'r',textContent:'PO-QA'}]}});h.draw();h.apply();await h.settle(h.reads.at(-1),result);
 h.open('product');h.field(en.product).props.onChange({target:{selectedOptions:[{value:'p',textContent:'Pipe'}]}});h.draw();h.apply();await h.settle(h.reads.at(-1),result);
 h.open('product');h.field(en.search).props.onChange({target:{value:'pipe'}});h.draw();assert.ok(h.reads.at(-1).url.includes('search=pipe'));assert.ok(h.reads.at(-1).url.includes('values_page=1'));
 assert.ok(h.nodes().some(n=>n.type==='button'&&n.props.children?.includes?.('Pipe')));
 h.nodes().find(n=>n.type==='button'&&n.props.children===en.historyClear).props.onClick();h.draw();const query=new URL(h.reads.at(-1).url,'http://localhost').searchParams;assert.ok(!query.has('product')&&!query.has('request'));
 }finally{h.close();}
});
