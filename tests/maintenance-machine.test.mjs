import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {build} from 'esbuild';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
import {floorSnapshot} from './fixtures/factory-floor.mjs';
import {evaluateFlow} from '../src/utils/production-flow.mjs';
const require=createRequire(import.meta.url);
const bundles=await Promise.all(['FactoryFloorV2','CenterDetails','MaintenanceRequest'].map(async name =>
 (await build({entryPoints:[`src/features/${name}.tsx`],bundle:true,platform:'node',format:'cjs',packages:'external',
 external:['@/hooks/useHistoryData'],write:false,logLevel:'silent'})).outputFiles[0].text));
function fixture(index,{state='running',lang='en',create=true,rows=[],overrides={}}={}){
 const snapshot=floorSnapshot();snapshot.tables.work_centers[0].status=state;
 if(state==='stopped')snapshot.tables.downtime_events.push({id:'STOP',work_center_id:'M1',started_at:'2026-10-03T07:00:00Z'});
 const before=structuredClone(snapshot),forms=[],contexts=[];let hook=0;
 const react=require('react'),runtime=require('react/jsx-runtime'),module={exports:{}};
 const resolver=name => name==='@/hooks/useHistoryData' ? {useHistoryData:()=>({loading:false,error:'',reload:()=>{},data:{rows,total:rows.length,
 options:{machines:snapshot.tables.work_centers,lines:[],people:[]}}})}
 : name==='react' ? {...react,useState:initial=>react.useState(Object.hasOwn(overrides,++hook)?overrides[hook]:initial),
 createElement:(type,props,...children)=>{if(type?.name==='MaintenanceContext')contexts.push(props);return react.createElement(type,props,...children);}}
 : name==='react/jsx-runtime' ? Object.fromEntries(Object.entries(runtime).map(([key,value])=>[key,
 typeof value==='function' && ['jsx','jsxs'].includes(key) ? (type,props,...rest)=>{
  if(type==='form')forms.push(props);if(type?.name==='MaintenanceContext')contexts.push(props);
  return value(type,props,...rest);
 } : value])) : require(name);
 new Function('require','module','exports',bundles[index])(resolver,module,module.exports);
 const props={snapshot,lang,t:key=>(lang==='ar'?ar:en)[key]||key,
 can:(module,action='view')=>module==='maintenance'?action!=='create'||create:snapshot.permissions.includes(`${module}:${action}`),
 command:()=>{throw Error('Rendering cannot mutate production');}};
 return {snapshot,before,props,exports:module.exports,forms,contexts};
}
test('all machine states expose authorized maintenance in Floor and overview details, EN/AR',()=>{
 for(const state of ['running','idle','stopped','setup','offline'])for(const lang of ['en','ar'])for(const index of [0,1]){
  const f=fixture(index,{state,lang,overrides:index===0?{2:'M1'}:{}});
  const html=renderToStaticMarkup(createElement(f.exports.default,{...f.props,center:f.snapshot.tables.work_centers[0],onClose:()=>{}}));
  assert.ok(html.includes((lang==='ar'?ar:en).maintenanceRequestAction),`${index} ${state} ${lang}`);
  assert.equal(f.contexts.length,1);assert.equal(f.contexts[0].downtime,undefined,'machine drawer never implicitly links its stop');
  assert.deepEqual(f.snapshot,f.before);
 }
});
test('create permission is required regardless of machine state',()=>{
 for(const state of ['running','idle','stopped','setup','offline']){
  const f=fixture(0,{state,create:false,overrides:{2:'M1'}});
  const html=renderToStaticMarkup(createElement(f.exports.default,f.props));assert.ok(!html.includes(en.maintenanceRequestAction));
 }
});
test('active manual requests display while allowing a separately confirmed problem',()=>{
 const f=fixture(2,{rows:[{id:'R1',code:'MR-0000012',status:'IN_PROGRESS',can_open:true}]});
 const html=renderToStaticMarkup(createElement(f.exports.default,{...f.props,machine:f.snapshot.tables.work_centers[0]}));
 assert.ok(html.includes('MR-0000012'));assert.ok(html.includes(en.maintenanceState_IN_PROGRESS));assert.ok(html.includes(en.maintenanceRequestAction));
});
test('Downtime context suppresses only a request for that same event',()=>{
 for(const linked of ['STOP','OTHER']){
  const f=fixture(2,{rows:[{id:'R1',code:'MR-0000012',status:'OPEN',downtime_id:linked,can_open:true}]});
  const html=renderToStaticMarkup(createElement(f.exports.default,{...f.props,machine:f.snapshot.tables.work_centers[0],downtime:{id:'STOP'}}));
  assert.equal(html.includes(en.maintenanceRequestAction),linked!=='STOP');
 }
});
test('machine cards remain free of Maintenance controls',()=>{
 const f=fixture(0);const html=renderToStaticMarkup(createElement(f.exports.default,f.props));
 assert.ok(!html.includes(en.maintenanceRequestAction));assert.equal(f.contexts.length,0);
});
test('actual creation form sends manual payload without a downtime link and preserves flow inputs',async()=>{
 const f=fixture(2,{overrides:{2:'Abnormal vibration',3:'Developing issue',6:true},rows:[{id:'R1',code:'MR-0000012',status:'OPEN'}]});
 const calls=[];let created;
 const flow=evaluateFlow(f.snapshot.tables.work_centers,f.snapshot.tables.downtime_events,f.snapshot.tables.production_transfers,0);
 const html=renderToStaticMarkup(createElement(f.exports.MaintenanceCreate,{...f.props,machine:f.snapshot.tables.work_centers[0],
  command:async(name,args)=>{calls.push({name,args});return 'R2';},onClose:()=>{},onCreated:id=>{created=id;}}));
 assert.ok(html.includes(en.maintenanceSeparateProblem));
 await f.forms[0].onSubmit({preventDefault(){}});
 assert.equal(created,'R2');assert.equal(calls.length,1);assert.equal(calls[0].name,'create_maintenance_request');
 assert.equal(calls[0].args.payload.work_center_id,'M1');assert.equal(calls[0].args.payload.downtime_id,null);
 assert.equal(calls[0].args.payload.separate_problem,true);assert.equal(calls[0].args.payload.title,'Abnormal vibration');
 assert.deepEqual(f.snapshot,f.before);assert.deepEqual(evaluateFlow(f.snapshot.tables.work_centers,f.snapshot.tables.downtime_events,f.snapshot.tables.production_transfers,0),flow);
});
