import test from 'node:test';import assert from 'node:assert/strict';
import {inspectionDraft} from '../../src/utils/quality-inspection.mjs';
import {decimalMultiply} from '../../src/utils/quality-quantities.mjs';
test('909 total produces890 finished,10 unfinished,9 rejected without KG substitution',()=>{
 const d=inspectionDraft('909','9',[{id:'u',quantity:'10',missing_operations:['print'],restriction:'Store separately'}],'meter',[{id:'print'}],'f');
 assert.equal(d.finished,'890');assert.equal(d.groups[0].restriction,'Store separately');assert.equal(decimalMultiply('9','.5'),'4.5');assert.notEqual(decimalMultiply('9','.5'),'9');
});
