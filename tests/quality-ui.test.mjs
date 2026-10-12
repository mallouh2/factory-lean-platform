import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {renderToStaticMarkup} from 'react-dom/server';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
const require=createRequire(import.meta.url),react=require('react');
test('WIP conservation instructions distinguish discarded production units from Scrap KG in EN/AR',()=>{
 for(const key of ['unfinishedConservationHelp','unfinishedConservation']){
  assert.match(en[key],/Good \+ discarded production quantity \+ Unfinished/);
  assert.match(en[key],/Scrap kg is recorded separately/);
  assert.match(ar[key],/الكمية الإنتاجية المستبعدة/);
  assert.match(ar[key],/وزن التوالف بالكيلوغرام بشكل منفصل/);
 }
});
const bundle=(await build({entryPoints:['src/features/Quality.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'quality-fixture',setup(b){
 b.onResolve({filter:/useSupply$/},()=>({path:'fixture:supply',external:true}));
 b.onResolve({filter:/components\/ui$/},()=>({path:'fixture:ui',external:true}));
}}]})).outputFiles[0].text;
const row={id:'entry',source_id:'source',unit:'meter',recorded_good:'100',current_good:'100',accepted:'100',rejected:'0',eligible:'100',physical_label:'PIPE-A-01',weight_kg_per_unit:'.35',product_name:'Pipe',product_name_ar:'أنبوب',product_code:'P-25',request_code:'PR-44',item_code:'PI-44',line_name:'Line 1',line_name_ar:'الخط ١',created_at:'2026-10-10T03:00:00Z',shift_name:'Night',shift_name_ar:'ليل',shift_date:'2026-10-09'};
function harness(exportName,{lang='en',can=()=>true,success=true,weight='.35',unit='meter',reasonRows=null,reasonsBusy=false,scrap=undefined}={}){
 const states=[],calls=[],queries=[];let cursor=0;
 const fixtureRow={...row,unit,weight_kg_per_unit:weight,scrap};
 const dictionary=lang==='ar'?ar:en,mod={exports:{}};
 const hooks={useSupply:(_s,mode,extra,enabled)=>{queries.push({mode,extra,enabled});
  const all=reasonRows||[{id:'reason',name:'Dimensional defect',name_ar:'عيب في الأبعاد',active:true},{id:'other',name:'Other',name_ar:'أخرى',is_other:true,active:true}];
  const matching=all.filter(r=>r.active&&!r.is_other&&[r.name,r.name_ar].some(n=>(n||'').toLowerCase().includes((extra?.search||'').toLowerCase())));
  const paged=matching.slice((Number(extra?.page||1)-1)*100,Number(extra?.page||1)*100);
  const rows=[...paged,...all.filter(r=>r.active&&(r.is_other||r.id===extra?.selected)&&!paged.includes(r))];
  return{busy:mode==='reasons'&&reasonsBusy,error:'',refresh(){},data:mode==='reasons'?{rows,total:matching.length}:{rows:[fixtureRow],total:1}};
 },useSupplyCommand:()=>({busy:false,error:'',clearError(){},async run(operation,payload){calls.push({operation,payload});return success;}})};
 new Function('require','module','exports',bundle)(n=>n==='fixture:supply'?hooks:n==='fixture:ui'?{Dialog:({children})=>react.createElement('div',null,children),Field:({label,children})=>react.createElement('label',null,label,children),formatTime:()=> '10 Oct 2026'}:n==='react'?{...react,useState(initial){const i=cursor++;if(!(i in states))states[i]=initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];}}:require(n),mod,mod.exports);
 const props={snapshot:{factory:{id:'factory',timezone:'Asia/Riyadh'},user:{id:'actor'},fetchedAt:'now',tables:{products:[],production_lines:[],production_shifts:[]}},t:k=>dictionary[k]||k,lang,can,command:async()=>{},row:{...row,unit,weight_kg_per_unit:weight},onClose(){},onChanged(){calls.push('changed');}};
 const tree=()=>{cursor=0;return mod.exports[exportName](props);};
 const walk=n=>!n||typeof n!=='object'?[]:Array.isArray(n)?n.flatMap(walk):[n,...walk(n.props?.children)];
 return{props,states,calls,queries,nodes:()=>walk(tree()),html:()=>renderToStaticMarkup(tree())};
}
const input=h=>h.nodes().find(n=>n.type==='input'&&n.props.type==='number');
const confirm=h=>h.nodes().find(n=>n.type==='button'&&n.props.className==='primary');
const combo=h=>h.nodes().find(n=>n.props?.role==='combobox');
function choose(h,id){combo(h).props.onFocus();const choice=h.nodes().find(n=>n.props?.role==='option'&&(id==='other'?String(n.props.children)===(h.props.lang==='ar'?ar.other:en.other):id==='reason'?String(n.props.children)===(h.props.lang==='ar'?'عيب في الأبعاد':'Dimensional defect'):String(n.props.children).endsWith(id.slice(1).padStart(3,'0'))));assert.ok(choice,'reason option exists');choice.props.onClick();}
function complete(h,quantity='20'){
 input(h).props.onChange({target:{value:quantity}});
 choose(h,'reason');
 h.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox').props.onChange({target:{checked:true}});
}
for(const lang of ['en','ar'])test(`Quality rejection draft, exact kg and physical confirmation in ${lang}`,async()=>{
 const h=harness('RejectionDrawer',{lang}),d=lang==='ar'?ar:en;
 assert.equal(confirm(h).props.disabled,true);complete(h);assert.equal(confirm(h).props.disabled,false);
 assert.ok(h.html().includes(d.qualityAccepted));assert.ok(h.html().includes('PIPE-A-01'));
 await h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});
 assert.equal(h.calls[0].payload.actual_scrap_kg,'7');assert.equal(h.calls[0].payload.quantity,'20');assert.equal(h.calls[0].payload.physically_identified,true);
 assert.ok(h.html().includes(`dir="${lang==='ar'?'rtl':'ltr'}"`));
});
test('Actual kg override and failed command preserve draft',async()=>{
 const h=harness('RejectionDrawer',{success:false});complete(h);
 h.nodes().filter(n=>n.type==='input'&&n.props.type==='number')[1].props.onChange({target:{value:'7.40'}});
 await h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});
 assert.equal(h.calls[0].payload.actual_scrap_kg,'7.40');assert.equal(input(h).props.value,'20');assert.equal(h.calls.includes('changed'),false);
});
test('Missing weight blocks until positive manual kg; fractional Piece blocks regardless of mass',()=>{
 const h=harness('RejectionDrawer',{weight:null});complete(h);assert.equal(confirm(h).props.disabled,true);
 h.nodes().filter(n=>n.type==='input'&&n.props.type==='number')[1].props.onChange({target:{value:'.8'}});assert.equal(confirm(h).props.disabled,false);
 const piece=harness('RejectionDrawer',{unit:'piece',weight:'.25'});complete(piece,'0.5');assert.equal(confirm(piece).props.disabled,true);
});
test('Other requires a description and only authorized people see reusable reason approval',()=>{
 const h=harness('RejectionDrawer',{can:m=>m!=='quality_reasons'});complete(h);choose(h,'other');
 assert.equal(confirm(h).props.disabled,true);assert.equal(h.nodes().filter(n=>n.type==='input'&&n.props.type==='checkbox').length,1);
 h.nodes().find(n=>n.type==='textarea'&&n.props.required).props.onChange({target:{value:'Socket alignment'}});assert.equal(confirm(h).props.disabled,false);
});
test('Rework omits Scrap kg and preserves exact production-unit quantity',async()=>{
 const h=harness('RejectionDrawer');complete(h,'10');h.nodes().find(n=>n.type==='select'&&!n.props.required).props.onChange({target:{value:'REWORK'}});
 assert.equal(h.nodes().filter(n=>n.type==='input'&&n.props.type==='number').length,1);
 await h.nodes().find(n=>n.type==='form').props.onSubmit({preventDefault(){}});assert.equal(h.calls[0].payload.actual_scrap_kg,null);assert.equal(h.calls[0].payload.disposition,'REWORK');
});
for(const lang of ['en','ar'])test(`Quality board separates gross and acceptance, with per-person actions in ${lang}`,()=>{
 const h=harness('default',{lang,can:(_m,a='view')=>a==='view'}),html=h.html(),d=lang==='ar'?ar:en;
 for(const key of ['qualityRecorded','qualityRejected','qualityAccepted','qualityShiftDate'])assert.ok(html.includes(d[key]));
 assert.ok(!html.includes(d.qualityRecordRejection));assert.ok(html.includes('2026-10-09'));assert.equal(h.queries[0].mode,'board');
});
const manyReasons=[...Array.from({length:105},(_,n)=>({id:'r'+n,name:'Reason '+String(n).padStart(3,'0'),name_ar:'سبب '+String(n).padStart(3,'0'),active:true})),
 ...Array.from({length:110},(_,n)=>({id:'a'+n,name:'Archived '+n,name_ar:'مؤرشف '+n,active:false})),{id:'other',name:'Other',name_ar:'أخرى',is_other:true,active:true}];
for(const lang of ['en','ar'])test(`Active reason paging/search retains Other and selection beyond 100 in ${lang}`,()=>{
 const h=harness('RejectionDrawer',{lang,reasonRows:manyReasons}),d=lang==='ar'?ar:en;
 combo(h).props.onFocus();
 const options=()=>h.nodes().filter(n=>n.props?.role==='option');
 assert.equal(options().length,101);assert.ok(options().some(n=>n.props.children===d.other));assert.ok(!h.html().includes('Archived'));
 choose(h,'r0'); combo(h).props.onFocus();
 h.nodes().find(n=>n.type==='button'&&n.props.children===d.next).props.onClick();
 assert.equal(options().length,7);assert.ok(options().some(n=>n.props.children===d.other));assert.ok(options().some(n=>String(n.props.children).endsWith('104')));assert.ok(options().some(n=>String(n.props.children).endsWith('000')));
 combo(h).props.onChange({target:{value:lang==='ar'?'سبب 104':'Reason 104'}});
 assert.equal(options().length,2);assert.equal(h.queries.at(-1).extra.active_only,'true');assert.equal(h.queries.at(-1).extra.page,'1');assert.equal(h.queries.at(-1).extra.selected,undefined);
});
test('Exactly 100 active ordinary reasons need no extra page; pending reason refresh blocks submission',()=>{
 const h=harness('RejectionDrawer',{reasonRows:[...manyReasons.slice(0,100),manyReasons.at(-1)]});
 combo(h).props.onFocus();assert.equal(h.nodes().find(n=>n.type==='button'&&n.props.children===en.next).props.disabled,true);
 const busy=harness('RejectionDrawer',{reasonsBusy:true});input(busy).props.onChange({target:{value:'20'}});busy.states[1]='reason';busy.nodes().find(n=>n.type==='input'&&n.props.type==='checkbox').props.onChange({target:{checked:true}});assert.equal(confirm(busy).props.disabled,true);
});

for(const lang of ['en','ar'])test('Single reason input keyboard, Other text and invalid draft in '+lang,async()=>{
 const h=harness('RejectionDrawer',{lang});const d=lang==='ar'?ar:en;
 assert.equal(h.nodes().filter(n=>n.props?.role==='combobox').length,1);
 assert.equal(h.nodes().filter(n=>n.type==='select'&&n.props.required).length,0);
 combo(h).props.onClick();assert.equal(combo(h).props['aria-expanded'],true);
 combo(h).props.onChange({target:{value:'Novel alignment issue'}});
 assert.equal(combo(h).props['aria-invalid'],true);assert.equal(confirm(h).props.disabled,true);
 const other=h.nodes().find(n=>n.props?.role==='option');assert.ok(String(other.props.children).includes(d.qualityUseAsOther));other.props.onClick();
 assert.equal(h.nodes().find(n=>n.type==='textarea'&&n.props.required).props.value,'Novel alignment issue');
 combo(h).props.onFocus();combo(h).props.onKeyDown({key:'Escape',preventDefault(){},stopPropagation(){}});assert.equal(combo(h).props['aria-expanded'],false);
 combo(h).props.onFocus();combo(h).props.onKeyDown({key:'ArrowDown',preventDefault(){},currentTarget:{ownerDocument:{getElementById(){return null;}}}});
 assert.ok(combo(h).props['aria-activedescendant']);combo(h).props.onKeyDown({key:'Enter',preventDefault(){}});assert.equal(combo(h).props['aria-expanded'],false);
 combo(h).props.onFocus();combo(h).props.onKeyDown({key:'Tab'});assert.equal(combo(h).props['aria-expanded'],false);
});

for(const lang of ['en','ar'])test('Actual Quality board warning, allowance and unknown states in '+lang,()=>{
 const d=lang==='ar'?ar:en,base={version:1,product_id:'P',line_id:'L',unit:'meter',production_scrap_kg:'2',quality_scrap_kg:'1',produced_kg:'100',weight_kg_per_unit:'.5',running_standard_percent:'2',standard_revision:1,startup_context_complete:true,startup_allowance_kg:'0',above_running_standard:true,running_excess_kg:'1'};
 const high=harness('default',{lang,scrap:base}).html();
 assert.ok(high.includes('<tr class="high-scrap">'));assert.ok(high.includes(d.qualityHighScrap));assert.ok(high.includes('⚠'));
 for(const key of ['qualityActualScrapRate','qualityNormalScrapRate','qualityScrapAllowance','qualityExcessScrap'])assert.ok(high.includes(d[key]));
 assert.ok(high.includes(`dir="${lang==='ar'?'rtl':'ltr'}"`));assert.ok(high.includes('<bdi>'));
 const normal=harness('default',{lang,scrap:{...base,production_scrap_kg:'1',above_running_standard:false,running_excess_kg:'0'}}).html();
 assert.ok(!normal.includes('class="high-scrap"'));assert.ok(!normal.includes(d.qualityHighScrap));
 const missingStandard=harness('default',{lang,scrap:{...base,running_standard_percent:null,standard_revision:null,startup_context_complete:false}}).html();
 assert.ok(missingStandard.includes(d.qualityStandardMissing));assert.ok(missingStandard.includes(d.qualityActualScrapRate));assert.ok(missingStandard.includes('<bdi>3%</bdi>'));
 assert.ok(!missingStandard.includes(d.qualityCalculationUnavailable));assert.ok(!missingStandard.includes(d.qualityHighScrap));
 const missingContext=harness('default',{lang,scrap:{...base,line_id:null}}).html();
 assert.ok(missingContext.includes(d.qualityActualScrapRate));assert.ok(missingContext.includes(d.qualityCalculationUnavailable));
 const unavailable=harness('default',{lang,scrap:{...base,produced_kg:null}}).html();
 assert.ok(unavailable.includes(d.qualityCalculationUnavailable));assert.ok(!unavailable.includes(d.qualityHighScrap));
});
