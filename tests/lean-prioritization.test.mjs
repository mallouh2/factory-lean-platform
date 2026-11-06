import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {renderToStaticMarkup} from 'react-dom/server';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
const require=createRequire(import.meta.url),react=require('react');
const code=(await build({entryPoints:['src/features/LeanProblem.tsx'],bundle:true,platform:'node',format:'cjs',
 packages:'external',write:false,logLevel:'silent',plugins:[{name:'reader',setup(b){
 b.onResolve({filter:/hooks\/useHistoryData$/},()=>({path:'priority-reader',external:true}));
 }}]})).outputFiles[0].text;
const problem=(monitor_only=true,revision=1)=>({id:'P',monitor_only,revision,threshold_percent:0});
function harness({initial=problem(),loading=false,error='',lang='en',save=async()=>({id:'P'})}={}){
 const state=[],writes=[];let cursor=0,tree,reloads=0;const words=lang==='ar'?ar:en;
 const fake={...react,useState(init){const i=cursor++;if(!(i in state))state[i]=typeof init==='function'?init():init;
 return[state[i],v=>state[i]=typeof v==='function'?v(state[i]):v];},
 useRef(init){const i=cursor++;return state[i]??={current:init};}};
 const m={exports:{}};new Function('require','module','exports',code)(n=>n==='react'?fake:n==='priority-reader'?{}:require(n),m,m.exports);
 const props={problem:initial,loading,error,busy:false,t:k=>words[k]||k,
 onSave:async values=>{writes.push(values);return save(values);},onReload(){reloads++;}};
 function draw(){cursor=0;tree=m.exports.LeanPrioritization(props);return tree;}
 function nodes(n=tree){if(!n||typeof n!=='object')return[];return[n,...[n.props?.children].flat(Infinity).flatMap(child=>child?nodes(child):[])];}
 function input(name){return nodes().find(n=>n.type==='input'&&n.props.name===name);}
 function button(label){return nodes().find(n=>n.type==='button'&&n.props.children===words[label]);}
 function change(name,value){input(name).props.onChange({target:name==='monitor'?{checked:value}:{value}});draw();}
 async function submit(){await tree.props.onSubmit({preventDefault(){}});draw();}
 draw();return{props,draw,nodes,input,button,change,submit,writes,get reloads(){return reloads;}};
}
test('delayed authoritative details disable input and Save, then synchronize true and zero threshold',async()=>{
 const h=harness({initial:null,loading:true});assert.equal(h.input('monitor').props.disabled,true);
 await h.submit();assert.equal(h.writes.length,0);
 h.props.problem=problem();h.props.loading=false;h.draw();
 assert.equal(h.input('monitor').props.checked,true);assert.equal(h.input('threshold').props.value,'0');
 assert.equal(h.input('monitor').props.disabled,false);assert.equal(h.button('save').props.disabled,true);
});
test('false initial state and untouched Save never issue a command or audit update',async()=>{
 for(const value of [false,true]){const h=harness({initial:problem(value)});assert.equal(h.input('monitor').props.checked,value);
 await h.submit();assert.equal(h.writes.length,0);}
});
test('intentional changes work in both directions, retain the base revision and await authoritative refresh',async()=>{
 for(const value of [false,true]){
 const h=harness({initial:problem(value,4)});h.change('monitor',!value);await h.submit();
 assert.deepEqual(h.writes,[{monitor_only:!value,threshold_percent:0,expected_revision:4}]);
 assert.equal(h.input('monitor').props.checked,!value);assert.equal(h.button('save').props.disabled,true);
 await h.submit();assert.equal(h.writes.length,1);
 h.props.loading=true;h.draw();assert.equal(h.input('monitor').props.disabled,true);
 h.props.loading=false;h.props.problem=problem(!value,5);h.draw();
 assert.equal(h.input('monitor').props.checked,!value);assert.equal(h.button('save').props.disabled,true);
 await h.submit();assert.equal(h.writes.length,1);
 }
});
test('unrelated threshold Save preserves monitor_only; toggling back is a no-op',async()=>{
 const h=harness();h.change('threshold','12');await h.submit();assert.equal(h.writes[0].monitor_only,true);
 const untouched=harness();untouched.change('monitor',false);untouched.change('monitor',true);
 await untouched.submit();assert.equal(untouched.writes.length,0);
});
test('background and stale responses cannot overwrite an edited value or advance its expected revision',async()=>{
 const h=harness({initial:problem(true,4),save:async()=>null});h.change('monitor',false);
 h.props.problem=problem(true,5);h.draw();assert.equal(h.input('monitor').props.checked,false);
 await h.submit();assert.equal(h.writes[0].expected_revision,4);
 assert.equal(h.input('monitor').props.checked,false);
 h.props.problem=problem(true,3);h.draw();assert.equal(h.input('monitor').props.checked,false);
});
test('failed save keeps edits; cancel explicitly discards and requests fresh authoritative data',async()=>{
 const h=harness({save:async()=>null});h.change('monitor',false);await h.submit();
 assert.equal(h.input('monitor').props.checked,false);h.button('cancel').props.onClick();h.draw();
 assert.equal(h.input('monitor').props.checked,true);assert.equal(h.reloads,1);
});
test('successful save ignores an older refresh and blocks duplicates until a newer revision arrives',async()=>{
 const h=harness({initial:problem(true,4)});h.change('monitor',false);await h.submit();
 h.props.problem=problem(true,3);h.draw();assert.equal(h.input('monitor').props.checked,false);
 assert.equal(h.input('monitor').props.disabled,true);await h.submit();assert.equal(h.writes.length,1);
 h.props.problem=problem(false,5);h.draw();h.change('monitor',true);await h.submit();
 assert.equal(h.writes[1].expected_revision,5);
});

test('failed refresh after rejected stale save preserves the draft and requires explicit discard before a fresh edit',async()=>{
 const h=harness({initial:problem(true,4),save:async()=>null});
 h.change('monitor',false);await h.submit();
 h.props.problem=problem(true,5);h.props.error='dataWarning';h.draw();
 assert.equal(h.input('monitor').props.checked,false);
 assert.equal(h.input('monitor').props.disabled,true);
 await h.submit();assert.equal(h.writes.length,1);
 h.button('cancel').props.onClick();h.props.loading=true;h.draw();
 assert.equal(h.reloads,1);assert.equal(h.button('save').props.disabled,true);
 h.props.loading=false;h.props.error='';h.draw();
 assert.equal(h.input('monitor').props.checked,true);
 assert.equal(h.button('save').props.disabled,true);
 h.change('monitor',false);await h.submit();
 assert.equal(h.writes[1].expected_revision,5);
});
test('immediate concurrent submissions produce one command',async()=>{
 let release;const h=harness({save:()=>new Promise(resolve=>release=resolve)});
 h.change('monitor',false);const first=h.submit();await h.submit();assert.equal(h.writes.length,1);
 release({id:'P'});await first;
});
test('errors, busy and malformed authoritative values fail closed',async()=>{
 for(const update of [{error:'permissionDenied'},{busy:true},{loading:true},{problem:null},
 {problem:{...problem(),monitor_only:'true'}},{problem:{...problem(),revision:undefined}},
 {problem:{...problem(),threshold_percent:null}}]){
 const h=harness();h.change('monitor',false);Object.assign(h.props,update);h.draw();
 assert.equal(h.input('monitor').props.disabled,true);await h.submit();assert.equal(h.writes.length,0);
 }
});
test('fresh problem instances initialize independently and use their own revision',async()=>{
 const a=harness({initial:problem(true,7)});a.change('monitor',false);
 const b=harness({initial:{...problem(false,2),id:'Q'}});assert.equal(b.input('monitor').props.checked,false);
 b.change('monitor',true);await b.submit();assert.equal(b.writes[0].expected_revision,2);
});
test('EN/AR render the same labelled controlled controls and preserve native numeric validation',()=>{
 for(const lang of ['en','ar']){const h=harness({lang}),html=renderToStaticMarkup(h.draw());
 assert.ok(html.includes((lang==='ar'?ar:en).leanMonitorOnly));assert.match(html,/type="checkbox"/);
 assert.match(html,/checked=""/);assert.match(html,/name="threshold"/);assert.match(html,/required=""/);
 assert.match(html,/min="0"/);assert.match(html,/max="100"/);}
});
test('detail status uses refreshed monitor state without changing initiative or verification evidence',()=>{
 const current={id:'I',revision:1,title:'Keep initiative',verified_at:'2026-10-01',outcome:'IMPROVED',verification_evidence:{frozen:true}};
 const detail={problem:problem(false,2),initiatives:[current],actions:[]};
 const before=JSON.stringify(detail),m={exports:{}};
 new Function('require','module','exports',code)(n=>n==='priority-reader'?{useHistoryData:()=>({data:detail,loading:false,error:'',reload(){}})}:require(n),m,m.exports);
 const row={problem_id:'P',mechanism:'downtime',monitor_only:true,cause:'Cause',cause_id:'C',products:[]};
 const html=renderToStaticMarkup(react.createElement(m.exports.default,{row,from:'2026-10-01',to:'2026-10-02',
 snapshot:{factory:{id:'F'},user:{id:'U'},tables:{}},lang:'en',can:()=>false,t:k=>en[k]||k,command:async()=>{}}));
 assert.ok(html.includes(en.leanVERIFIED));assert.ok(!html.includes('<strong>'+en.leanMonitorOnly+'</strong>'));
 assert.equal(JSON.stringify(detail),before);
});
