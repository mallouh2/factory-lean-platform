import assert from 'node:assert/strict';
import test from 'node:test';
import {compareHandoverCount,handoverCountValid,roundHandoverKg} from '../src/utils/shift-handover-counts.mjs';

test('raw display uses nearest whole kilogram without losing large integer precision',()=>{
  assert.equal(roundHandoverKg('76.55'),'77');
  assert.equal(roundHandoverKg('18.3'),'18');
  assert.equal(roundHandoverKg('9.5'),'10');
  assert.equal(roundHandoverKg('999999999999999999999998.5'),'999999999999999999999999');
});

test('raw counts require explicit nonnegative integers and goods keep decimal precision',()=>{
  for(const input of ['',undefined,'-1','0.1','1.0'])assert.equal(handoverCountValid(input,true),false);
  assert.equal(handoverCountValid('0',true),true);
  assert.equal(handoverCountValid('1.25'),true);
  assert.equal(compareHandoverCount('1.25','1.3','0').difference,'-0.05');
});

test('whole-kg comparisons ignore hidden fractions and retain configured discrepancy thresholds',()=>{
  assert.deepEqual(compareHandoverCount('77','76.55','0',true),{difference:'0',significant:false});
  assert.deepEqual(compareHandoverCount('76','76.55','0',true),{difference:'-1',significant:true});
  assert.deepEqual(compareHandoverCount('49','50.4','2',true),{difference:'-1',significant:false});
  assert.deepEqual(compareHandoverCount('1','0.4','20',true),{difference:'1',significant:true});
});
