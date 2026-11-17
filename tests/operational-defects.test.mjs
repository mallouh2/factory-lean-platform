import test from 'node:test';
import assert from 'node:assert/strict';
import {recordingRejectionKey} from '../src/utils/recording-rejection.mjs';
import {completionSummary} from '../src/utils/production-completion.mjs';
import {warehouseRequestRows} from '../src/utils/warehouse-request-rows.mjs';
test('known compensation rejection explains recovery without exposing SQL or inventing success',()=>{
 assert.equal(recordingRejectionKey('output_compensation_required','recordingValidation'),'recordingCompensationRequired');
 assert.equal(recordingRejectionKey('unknown_internal_sql','recordingValidation'),'recordingValidation');
 assert.equal(recordingRejectionKey('OVERPRODUCTION_CONFIRMATION_REQUIRED','recordingValidation'),'recordingOverproductionConfirm');
});
test('ordinary remaining and finished demand remain distinct after Quality classifies unfinished output',()=>{
 const x=completionSummary({id:'item',factory_id:'factory',target_quantity:'100',good_quantity:'90',produced_good:'80',ordinary_remaining:'0',remaining_demand:'20',unit:'meter'},'factory','item');
 assert.equal(x.produced_good,'80');assert.equal(x.recorded_good,'90');assert.equal(x.remaining,'0');assert.equal(x.remaining_demand,'20');
});
test('warehouse dispatch identity uses actual order and product references',()=>{
 const [r]=warehouseRequestRows({orders:[{id:'sales',code:'SO-22',lines:[{id:'line',product_name:'Pipe',quantity:'125',dispatched_quantity:'0',unit:'meter'}]}],t:k=>k});
 assert.equal(r.reference,'SO-22');assert.equal(r.name,'Pipe');assert.equal(r.quantity,'125');assert.equal(r.department,'navSales');assert.equal(r.unit,'meter');
});
