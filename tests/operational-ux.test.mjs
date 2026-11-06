import {test} from 'node:test';import assert from 'node:assert/strict';
import {inspectionDraft} from '../src/utils/quality-inspection.mjs';
import {inspectionValid} from '../src/utils/manufactured-output.mjs';
const ops=[{id:'print'},{id:'cut'}];
test('reproduces old conservation blocker and automatically derives 907 and 903',()=>{
 assert.equal(inspectionValid([{id:'f',quantity:'909',released:'907',missing_operations:[]}],'2','909','meter',ops),false);
 assert.equal(inspectionDraft('909','2',[],'meter',ops,'f').finished,'907');
 const g=[{id:'u',quantity:'4',missing_operations:['print']}];
 assert.equal(inspectionDraft('909','2',g,'meter',ops,'f').finished,'903');
 assert.equal(inspectionDraft('909','2',[...g,{id:'u2',quantity:'3',missing_operations:['cut','print']}],'meter',ops,'f').finished,'900');
});
test('exact decimals, actionable invalid states and no editable finished/release input',()=>{
 assert.equal(inspectionDraft('9007199254740993.1','.1',[],'meter',ops,'f').finished,'9007199254740993');
 assert.equal(inspectionDraft('1','2',[],'meter',ops,'f').error,'excess');
 assert.equal(inspectionDraft('10.1','0',[],'piece',ops,'f').error,'whole');
 assert.equal(inspectionDraft('10','0',[{id:'u',quantity:'1',missing_operations:[]}],'meter',ops,'f').error,'operations');
 assert.equal(inspectionDraft('bad','0',[],'meter',ops,'f').error,'quantity');
 assert.equal(inspectionDraft('10','0',[{id:'u',quantity:'1',missing_operations:['unknown']}],'meter',ops,'f').error,'quantity');
});
test('fully rejected output has no fabricated usable group; separate finished sources are preserved',()=>{
 const rejected=inspectionDraft('10','10',[],'meter',ops,'f');
 assert.equal(rejected.finished,'0');assert.deepEqual(rejected.groups,[]);
 const sources=[{id:'a',quantity:'4',missing_operations:[]},{id:'b',quantity:'6',missing_operations:[]}];
 assert.deepEqual(inspectionDraft('10','0',[],'meter',ops,'unused',sources).groups.map(g=>g.id),['a','b']);
 assert.equal(inspectionDraft('10','1',[],'meter',ops,'unused',sources).error,'group_scope');
});
