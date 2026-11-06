import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {maintenancePreviewCurrent} from '../src/utils/maintenance-planning.mjs';
const require=createRequire(import.meta.url),react=require('react');
const source=(await build({entryPoints:['src/features/MaintenancePlanning.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'})).outputFiles[0].text;
const a=new Date(Math.floor(Date.now()/60000)*60000+3600000).toISOString(),b=new Date(Date.parse(a)+1800000).toISOString();
const preview={factory_id:'F',request_id:'R',request_revision:2,schedule_revision:1,start:a,end:b,timezone:'UTC',evaluated_at:new Date().toISOString(),context_hash:'a'.repeat(64),capacity:'CLEAR',eligible:true,occupancy_complete:true,scope:{machine_id:'M'},activation_enabled:true,confirmation_available:true};
function fixture({active=true,proof=preview,state='PROPOSED',reason='',denied='',lang='en'}={}) {
 let index=0;const calls=[],values={2:reason,10:proof},mod={exports:{}};
 const fake={...react,useState:initial=>{const n=index++;return [n in values?values[n]:typeof initial==='function'?initial():initial,()=>{}];},useEffect(){},useRef:value=>({current:value})};
 new Function('require','module','exports',source)(name=>name==='react'?fake:require(name),mod,mod.exports);
 const board={active,requests:[],schedules:[]},request={id:'R',revision:2,status:'OPEN',maintenance_kind:'PLANNED',estimated_duration_minutes:30,code:'MR',title:'Local fixture'},schedule={id:'S',revision:1,state,planned_start:a,planned_end:b,resources:[]};
 const tree=mod.exports.MaintenancePlanningDrawer({snapshot:{factory:{id:'F',timezone:'UTC'},tables:{work_centers:[]}},t:key=>key,lang,can:(m,act)=>`${m}:${act}`!==denied,command:async(name,args)=>calls.push({name,args}),request,schedule,board,onClose(){},onChanged(){}});
 const nodes=[];function walk(x){if(!x||typeof x!=='object')return;if(Array.isArray(x)){x.forEach(walk);return;}nodes.push(x);walk(x.props?.children);}walk(tree);
 return {button:nodes.find(x=>x.type==='button'&&x.props.children===(state==='PROPOSED'?'mpConfirm':'mpReschedule')),calls,board,nodes};
}
test('activation flags must be strict true; advisory preview remains available while inactive',()=>{
 const target={factory:'F',request:'R',requestRevision:2,scheduleRevision:1,start:a,end:b,timezone:'UTC',requireActivation:true};
 assert.equal(maintenancePreviewCurrent(preview,target),true);
 for(const value of [false,null,undefined,'true',1])for(const key of ['activation_enabled','confirmation_available'])assert.equal(maintenancePreviewCurrent({...preview,[key]:value},target),false);
 assert.equal(maintenancePreviewCurrent({...preview,activation_enabled:false,confirmation_available:false},{...target,requireActivation:false}),true);
});
test('actual drawer enables valid confirmation and submits only the existing proof contract',async()=>{
 const x=fixture();assert.equal(x.button.props.disabled,false);x.button.props.onClick();await Promise.resolve();
 assert.equal(x.calls.length,1);assert.equal(x.calls[0].args.operation,'confirm');assert.equal(x.calls[0].args.payload.context_hash,preview.context_hash);assert.equal(x.calls[0].args.payload.request_revision,2);assert.equal(x.calls[0].args.expected_revision,1);assert.ok(x.calls[0].args.request_id);
});
test('inactive/unknown board, failed proof, edited proposal, expired proof and denied grants disable and guard the handler',()=>{
 for(const opts of [{active:false},{active:null,proof:null},{proof:null},{proof:{...preview,confirmation_available:false}},{proof:{...preview,context_hash:'bad'}},{proof:{...preview,request_revision:3}},{proof:{...preview,start:new Date(Date.parse(a)+60000).toISOString()}},{proof:{...preview,evaluated_at:new Date(Date.now()-61000).toISOString()}},...['factory:view','maintenance:view','orders:view','orders:edit'].map(denied=>({denied}))]){
  const x=fixture(opts);if(x.button){assert.equal(x.button.props.disabled,true,JSON.stringify(opts));x.button.props.onClick();}assert.equal(x.calls.length,0);
 }
});
test('confirmed rescheduling requires a reason and current activated preview in EN/AR',()=>{
 for(const lang of ['en','ar']){
  const noReason=fixture({state:'CONFIRMED',lang});assert.equal(noReason.button.props.disabled,true);
  const x=fixture({state:'CONFIRMED',reason:'Reviewed new window',lang});assert.equal(x.button.props.disabled,false);x.button.props.onClick();assert.equal(x.calls[0].args.operation,'reschedule');assert.equal(x.calls[0].args.payload.reason,'Reviewed new window');assert.equal(x.calls[0].args.payload.start,a);
  x.board.active=false;x.button.props.onClick();assert.equal(x.calls.length,1,'changed activation cannot reuse handler to submit');
 }
});
