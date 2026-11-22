import test from'node:test';import assert from'node:assert/strict';import{qualityOperationLabels}from'../src/utils/quality-operation-labels.mjs';import{qualityRejected,inspectionDraft}from'../src/utils/quality-inspection.mjs';
import {readFileSync} from 'node:fs';
test('approved Quality inputs derive finished from actual total minus rejected and recoverable unfinished',()=>{
 for(const [total,rejected,unfinished,finished]of [['100','3','7','90'],['98','2','1','95'],['98','0','0','98'],['1.000000000000000003','.000000000000000001','.000000000000000001','1.000000000000000001']]){
  const groups=unfinished==='0'?[]:[{id:'u',quantity:unfinished,missing_operations:['step']}];const d=inspectionDraft(total,rejected,groups,'meter',[{id:'step'}],'f');assert.equal(d.error,null);assert.equal(d.finished,finished);
 }
 assert.equal(inspectionDraft('10','8',[{id:'u',quantity:'3',missing_operations:['step']}],'meter',[{id:'step'}],'f').error,'excess');
 assert.equal(inspectionDraft('10.5','0',[],'piece',[],'f').error,'whole');
});
test('compact Quality treats finished as output and retains correction reason and quick approval',()=>{
 const s=readFileSync('src/features/ManufacturedOutput.tsx','utf8');assert.doesNotMatch(s,/setAccepted|qualityRejected\(total/);assert.match(s,/value=\{rejected\} onChange=\{e=>setRejected/);assert.match(s,/draft\.finished/);assert.match(s,/Approve as Recorded/);assert.match(s,/reason\.trim\(\)\.length<3/);assert.match(s,/row\.recorded/);
});
test('same-name steps keep their exact identities and real routing positions',()=>{const ops=[{id:'b',name:'Printing',name_ar:'طباعة',work_center_id:'m'},{id:'a',name:'Printing',name_ar:'طباعة',work_center_id:'m'}],steps=[{id:'a',position:1},{id:'b',position:2}],centers=[{id:'m',name:'Printer',name_ar:'طابعة'}];const labels=qualityOperationLabels(ops,steps,centers,'en');assert.equal(labels[0].id,'b');assert.match(labels[0].label,/Step 2/);assert.match(labels[1].label,/Step 1/);assert.match(qualityOperationLabels(ops,steps,centers,'ar')[0].label,/الخطوة 2/);assert.notEqual(labels[0].label,labels[1].label);});
test('live Finished uses the unfinished target before group details are saveable',()=>{
 const groups=[{id:'u',quantity:'7',missing_operations:[]}],operations=[{id:'step'}];
 const preview=inspectionDraft('١٠٠','٣',groups,'meter',operations,'f',[],'٧');
 assert.equal(preview.finished,'90');
 assert.equal(preview.error,'operations');
 assert.equal(preview.groups,undefined);

 const edited=inspectionDraft('100','2.5',groups,'meter',operations,'f',[],'8.75');
 assert.equal(edited.finished,'88.75');
 assert.equal(edited.error,'groupTotal');
 assert.equal(edited.groups,undefined);

 const completed=[{...groups[0],missing_operations:['step']}],original=structuredClone(completed);
 const valid=inspectionDraft('100','3',completed,'meter',operations,'f',[],'7');
 assert.equal(valid.error,null);
 assert.equal(valid.finished,preview.finished);
 assert.deepEqual(valid.groups,[{...completed[0],released:'7'},{id:'f',quantity:'90',released:'90',missing_operations:[]}]);
 assert.deepEqual(completed,original);
});
test('live Finished never reports a negative or invalid piece quantity',()=>{
 for(const [total,rejected,unfinished,unit,error] of [
  ['2','1','2','meter','excess'],['2','-1','0','meter','quantity'],
  ['2','0','','meter','quantity'],['2','0','.5','piece','whole'],
 ]){
  const draft=inspectionDraft(total,rejected,[],unit,[],'f',[],unfinished);
  assert.equal(draft.error,error);
  assert.equal(draft.finished,undefined);
  assert.equal(draft.groups,undefined);
 }
 assert.equal(inspectionDraft('2','2',[],'meter',[],'f',[],'0').finished,'0');
});
test('missing sequence uses explicit identity rather than invented order',()=>{const ops=[{id:'00000001',name:'Extrusion'},{id:'00000002',name:'Extrusion'}];assert.match(qualityOperationLabels(ops,[],[],'en')[0].label,/ID 00000001/);assert.equal(qualityOperationLabels([{id:'a',name:'Printing'}],[],[],'en')[0].label,'Printing');});
test('same-name same-center operations remain distinguishable when routing position is unavailable',()=>{const labels=qualityOperationLabels([{id:'a',name:'Extrusion',work_center_id:'m'},{id:'b',name:'Extrusion',work_center_id:'m'}],[],[{id:'m',name:'Extruder'}],'en');assert.notEqual(labels[0].label,labels[1].label);});
test('98 - 94 - two explicit unfinished groups conserves three rejected units',()=>{const g=[{id:'u1',quantity:'.6',missing_operations:['a']},{id:'u2',quantity:'.4',missing_operations:['b']}],r=qualityRejected('98','94',g,'meter'),d=inspectionDraft('98',r,g,'meter',[{id:'a'},{id:'b'}],'f');assert.equal(r,'3');assert.equal(d.finished,'94');assert.equal(d.error,null);assert.deepEqual(d.groups.slice(0,2).map(x=>x.missing_operations),[['a'],['b']]);});
