import test from 'node:test';import assert from 'node:assert/strict';
import {receiptQuantity} from '../src/utils/manufactured-receiving.mjs';
test('partial and exact remaining receipt, no floating rounding',()=>{assert.equal(receiptQuantity('92','95','meter'),'92');assert.equal(receiptQuantity('0.1234567890123456789','0.1234567890123456789','meter'),'0.1234567890123456789');});
test('zero, negative, excess and fractional pieces rejected',()=>{for(const q of ['0','-1','NaN','Infinity','96'])assert.throws(()=>receiptQuantity(q,'95','meter'));assert.throws(()=>receiptQuantity('1.5','2','piece'));});
test('Arabic decimal input normalizes before exact receipt validation',()=>{assert.equal(receiptQuantity('٣٫٢٥','4','meter'),'3.25');});
