import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { renderToStaticMarkup } from 'react-dom/server';
import { readFile } from 'node:fs/promises';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
const require=createRequire(import.meta.url),react=require('react');
const bundles={};
for(const name of ['LeanAnalysis','LeanProblem']){
 const out=await build({entryPoints:[`src/features/${name}.tsx`],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'scoped-reader',setup(b){b.onResolve({filter:/hooks\/useHistoryData$/},()=>({path:'lean-test-reader',external:true}));}}]});
 bundles[name]=out.outputFiles[0].text;
}
const row={mechanism:'scrap',problem_id:'problem',cause_id:'cause',cause:'Cooling low',cause_ar:'مياه التبريد منخفضة',line_id:'L',product_id:'P',products:['P'],frequency:2,loss_minutes:15,scrap_kg:10,scrap_rate:2,lost_output_by_unit:{piece:30,meter:12},wip_by_unit:{piece:5},shifts:[null],runtime_missing:true};
const list={rows:[row],total:1,summary:{loss_minutes:15,recurring:1},open_initiatives:1,overdue_actions:0};
const snapshot={factory:{id:'factory',timezone:'UTC'},user:{id:'owner'},fetchedAt:'first',tables:{products:[{id:'P',name:'Pipe',name_ar:'أنبوب'}],production_lines:[{id:'L',name:'Line',name_ar:'خط'}],production_shifts:[],work_centers:[],memberships:[{user_id:'owner',display_name:'Assigned person'}]}};
function harness(name,{lang='en',can=()=>true,detail={},listData=list}={}){
 const states=[],queries=[],writes=[];let cursor=0,tree;const words=lang==='ar'?ar:en;
 const fakeReact={...react,useState(initial){const i=cursor++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;return[states[i],v=>states[i]=typeof v==='function'?v(states[i]):v];},useRef(initial){const i=cursor++;return states[i]||=( {current:initial});},useEffect(){cursor++;}};
 const reader={useHistoryData(url){queries.push(url);const mode=url?new URL(url,'http://test').searchParams.get('mode'):null;return{data:mode==='library'?{causes:[],templates:[],people:[{user_id:'owner',display_name:'Assigned person'}]}:mode==='detail'?detail:listData,loading:false,error:'',reload(){}};}};
 const m={exports:{}};new Function('require','module','exports',bundles[name])(n=>n==='react'?fakeReact:n==='lean-test-reader'?reader:require(n),m,m.exports);
 const props={snapshot,t:k=>words[k]||k,lang,can,command:async(command,args)=>{writes.push({command,args});return{id:'saved'};},row,from:'2026-10-01T00:00Z',to:'2026-10-05T00:00Z',onBack(){}};
 function draw(){cursor=0;tree=m.exports.default(props);return tree;}
 function nodes(node=tree){if(!node||typeof node!=='object')return[];return[node,...[node.props?.children].flat(Infinity).flatMap(n=>n?nodes(n):[])];}
 function field(label){const f=nodes().find(n=>n.props?.label===label);assert.ok(f,'field '+label);return nodes(f).find(n=>['input','select','textarea'].includes(n.type));}
 function html(){cursor=0;return renderToStaticMarkup(react.createElement(m.exports.default,props));}
 return{draw,nodes,field,html,queries,writes,words,expand(node){return node.type(node.props);}};
}
test('Lean overview retains typed measures, explains source limits, and supports EN/AR',()=>{
 for(const lang of ['en','ar']){const h=harness('LeanAnalysis',{lang,listData:{...list,rows:[{...row,mechanism:'downtime'}]}}),html=h.html();assert.match(html,/lean-mobile-problem/);assert.match(html,/lean-table/);assert.ok(html.includes(h.words.leanRecurring));assert.ok(html.includes('30 piece · 12 meter'));assert.ok(html.includes(h.words.leanOutputBasisUnknown));assert.ok(html.includes(h.words.leanInsufficientExposure));assert.match(html,lang==='ar'?/dir="rtl"/:/dir="ltr"/);}
});
test('Lean global filters, independent sorting and pagination remain in bounded reader queries',()=>{
 const h=harness('LeanAnalysis');h.draw();h.field(en.product).props.onChange({target:{value:'P'}});h.draw();h.field(en.historySort).props.onChange({target:{value:'frequency'}});h.draw();h.nodes().find(n=>n.type==='button'&&n.props.children===en.historyDescending).props.onClick();h.draw();
 const query=new URL(h.queries.filter(x=>x&&!x.includes('mode=library')).at(-1),'http://test').searchParams;assert.equal(query.get('product_id'),'P');assert.equal(query.get('sort'),'frequency');assert.equal(query.get('direction'),'asc');assert.equal(query.get('page'),'1');assert.equal(h.writes.length,0);
});
const current={id:'I',title:'Cooling improvement',product_id:'P',revision:1,baseline_hours:40,baseline_evidence:{}};
test('action required native due date input is submitted immediately with owner and initiative',async()=>{
 const h=harness('LeanProblem',{detail:{initiatives:[current],actions:[]}});h.draw();h.field(en.title).props.onChange({target:{value:'Repair supply'}});h.draw();const due=h.field(en.leanDueDate);assert.equal(due.props.required,true);due.props.onInput({currentTarget:{value:'2026-10-12'}});h.draw();
 const form=h.nodes().find(n=>n.type==='form'&&n.props.className==='recording-form');await form.props.onSubmit({preventDefault(){}});assert.equal(h.writes[0].args.operation,'action');assert.equal(h.writes[0].args.payload.due_date,'2026-10-12');assert.equal(h.writes[0].args.payload.owner_id,'owner');assert.equal(h.writes[0].args.payload.initiative_id,'I');
});
test('action owner can update due date/progress but cannot cancel or change ownership',async()=>{
 const action={id:'A',initiative_id:'I',title:'Repair',status:'OPEN',owner_id:'owner',due_date:'2026-10-12',action_type:'MAINTENANCE',revision:1};
 const h=harness('LeanProblem',{can:(m,a)=>m==='lean'&&a==='view',detail:{initiatives:[current],actions:[action]}});h.draw();const component=h.nodes().find(n=>typeof n.type==='function'&&n.props.action?.id==='A');let card=h.expand(component);let dates=h.nodes(card).filter(n=>n.type==='input'&&n.props.type==='date');dates[0].props.onInput({currentTarget:{value:'2026-10-14'}});h.draw();card=h.expand(h.nodes().find(n=>typeof n.type==='function'&&n.props.action?.id==='A'));
 assert.ok(!h.nodes(card).some(n=>n.type==='summary'&&n.props.children===en.leanCancelAction));h.nodes(card).find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(r=>setImmediate(r));assert.equal(h.writes[0].args.operation,'progress');assert.equal(h.writes[0].args.payload.due_date,'2026-10-14');assert.ok(!('owner_id' in h.writes[0].args.payload));
});
test('saved verification metrics remain read-only and do not expose new verification controls',()=>{
 const evidence={complete:false,before:{collected_hours:40},after:{collected_hours:15,remaining_hours:25},before_metrics:{frequency:3,scrap_kg:80,produced_kg:2000,scrap_rate:4},after_metrics:{frequency:1,scrap_kg:20,produced_kg:500,scrap_rate:4},changes:{scrap_rate:{suggestion:'INSUFFICIENT_DATA'}}};
 const h=harness('LeanProblem',{detail:{initiatives:[{...current,verified_at:'2026-10-05',outcome:'INSUFFICIENT_DATA',verification_note:'Await more exposure',verification_evidence:evidence}],actions:[]},can:()=>false});const html=h.html();assert.ok(html.includes('25 h'));assert.ok(html.includes('2,000'));assert.ok(html.includes(en.leanInsufficientExposure));assert.ok(!html.includes(en.leanConfirmVerification));assert.equal(h.writes.length,0);
});
test('literal Lean workflow labels resolve in both English and Arabic dictionaries',async()=>{
 for(const file of ['LeanAnalysis','LeanProblem','LeanLibraries','LeanScrapReview']){
  const source=await readFile(`src/features/${file}.tsx`,'utf8');
  for(const match of source.matchAll(/\bt\(['"]([^'"]+)['"]\)/g)){
   if(match[1].endsWith('_')||['lean'].includes(match[1]))continue;
   assert.ok(en[match[1]],`${file}: missing English ${match[1]}`);assert.ok(ar[match[1]],`${file}: missing Arabic ${match[1]}`);
  }
 }
});
test('manual comparison disclosure keeps native open state independent of official verification mode',()=>{
 const h=harness('LeanProblem',{detail:{initiatives:[current],actions:[]}});h.draw();const details=h.nodes().find(n=>n.type==='details'&&h.nodes(n).some(x=>x.type==='summary'&&x.props.children===en.leanManualComparison));
 assert.ok(details);assert.ok(!('open' in details.props));const summary=h.nodes(details).find(n=>n.type==='summary');assert.ok(!summary.props.onClick);assert.ok(h.nodes(details).some(n=>n.type==='form'));
});
test('drill-down uses refreshed metrics rather than the stale selected table row',()=>{
 const h=harness('LeanProblem',{detail:{metrics:{frequency:4,loss_minutes:27,scrap_kg:37,scrap_rate:8.33,lost_output_by_unit:{piece:12},wip_by_unit:{piece:3},shifts:['new-shift']},initiatives:[],actions:[]}});
 const html=h.html();assert.ok(html.includes('<strong>4</strong>'));assert.ok(html.includes('37 kg'));assert.ok(html.includes('8.33%'));assert.ok(html.includes('27 min'));assert.ok(!html.includes('7.95%'));
});

test('Lean maintenance context localizes every request status in EN and AR',()=>{
 for(const lang of ['en','ar']){
  const statuses=['OPEN','ASSIGNED','IN_PROGRESS','COMPLETED','VERIFIED','CANCELLED'];
  const h=harness('LeanProblem',{lang,detail:{maintenance:statuses.map((status,i)=>({id:'M'+i,code:'MR-'+i,title:'Local service',status})),initiatives:[],actions:[]}});
  const html=h.html();
  for(const status of statuses)assert.ok(html.includes(h.words['maintenanceState_'+status]),`${lang}: ${status}`);
  assert.ok(!html.includes('maintenanceStatus_'));
  assert.equal(h.writes.length,0);
 }
});

test('one filter area contains every capability and table headers contain no filter controls',()=>{
 const h=harness('LeanAnalysis');h.draw();
 const filters=h.nodes().find(n=>n.props?.className==='lean-filter-area');assert.ok(filters);
 const headers=h.nodes().filter(n=>n.type==='th');assert.equal(headers.length,6);
 assert.ok(headers.every(n=>!h.nodes(n).some(c=>['input','select','details','button'].includes(c.type))));
 for(const label of [en.line,en.machine,en.product,en.productionShift,en.leanApprovedCause,en.status,en.historySort])assert.equal(h.nodes(filters).filter(n=>n.props?.label===label).length,1,label);
 assert.equal(h.nodes().filter(n=>n.type==='input'&&n.props.type==='number').length,2);
 h.field(en.status).props.onChange({target:{value:'VERIFIED'}});h.draw();assert.equal(new URL(h.queries.filter(x=>!x.includes('mode=library')).at(-1),'http://test').searchParams.get('initiative_status'),'VERIFIED');
});
test('specialized evidence stays in details and review-only users can open without creating',async()=>{
 const detail=harness('LeanProblem',{detail:{}}).html();assert.ok(detail.includes(en.leanSpecializedMetrics));
 const h=harness('LeanAnalysis',{can:(m,a)=>m==='lean'&&a==='view',listData:{...list,rows:[{...row,problem_id:null}]}});
 h.draw();await h.nodes().find(n=>n.props.className==='lean-problem-link').props.onClick();
 assert.equal(h.writes.length,0);
 assert.equal(h.draw().props.row.cause_id,row.cause_id);
});
