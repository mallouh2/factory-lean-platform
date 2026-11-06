import test from 'node:test';
import assert from 'node:assert/strict';
import {qualityColumns,defaultQualityColumns,qualityVisibleColumns,qualityPreferenceKey,rejectionExceeded,shiftProduction} from '../src/utils/quality-view.mjs';
test('exactly seven approved Quality defaults with no Actions column',()=>{
 assert.deepEqual(defaultQualityColumns,['shift','order','product','line','production','rejected','alert']);
 assert.equal(qualityColumns.some(([key])=>key==='actions'),false);
});
test('preferences are actor/factory/Quality scoped and sanitize stale keys',()=>{
 assert.notEqual(qualityPreferenceKey('a','f'),qualityPreferenceKey('b','f'));
 assert.notEqual(qualityPreferenceKey('a','f'),qualityPreferenceKey('a','g'));
 assert.deepEqual(qualityVisibleColumns(['accepted','secret','source']),['accepted','source']);
 assert.deepEqual(qualityVisibleColumns([]),defaultQualityColumns);
});
test('shift quantity requires protected complete attribution; never substitutes receipt Good',()=>{
 assert.equal(shiftProduction({current_good:'500'}),null);
 assert.equal(shiftProduction({shift_quantity:{complete:false,basis:'EFFECTIVE_GOOD',quantity:'500'}}),null);
 assert.equal(shiftProduction({shift_quantity:{complete:true,basis:'EFFECTIVE_GOOD',quantity:'500.1234567890123456789'}}),'500.1234567890123456789');
});
test('excess rejection uses exact eligible stock independently of shift total',()=>{
 assert.equal(rejectionExceeded('450','400'),true);
 assert.equal(rejectionExceeded('400','400'),false);
 assert.equal(rejectionExceeded('0.1000000000000000001','.1'),true);
});
