import test from 'node:test';
import assert from 'node:assert/strict';
import {sumQuantities,qualityWorkSummary,qualityWorkState} from '../src/utils/quality-update-summary.mjs';

test('quantity labels retain exact decimal precision',()=>{
 assert.equal(sumQuantities(['0.1','0.2','9007199254740993']),'9007199254740993.3');
});
test('four completed-assigned meters and two replacement meters stay separate',()=>{
 assert.deepEqual(qualityWorkSummary([{choice:'COMPLETE',quantity:'4',status:'planned'}],[{mode:'ACTIVE',recorded:'0',remaining:'2'}]),{completion:'4',replacement:'2'});
});
test('transferred allowance is not counted twice and stock-only work is separate',()=>{
 assert.deepEqual(qualityWorkSummary([{choice:'REPLACE',quantity:'2',status:'planned'},{choice:'STOCK',quantity:'20',status:'planned'}],[{mode:'ACTIVE',recorded:'1',remaining:'0'}]),{completion:'0',replacement:'3'});
});
test('cancelled and superseded decisions remain history, not current allocations',()=>{
 assert.deepEqual(qualityWorkSummary([{choice:'COMPLETE',quantity:'4',status:'planned',decision_revision:{retirement:{reason:'replaced'}}},{choice:'REPLACE',quantity:'6',status:'cancelled'}]),{completion:'0',replacement:'0'});
});
test('schedule and execution completion never imply physical receiving',()=>{
 assert.equal(qualityWorkState({status:'planned',line_id:null}),'unscheduled');
 assert.equal(qualityWorkState({status:'planned',line_id:'line',start_time:'2026-10-29'}),'scheduled');
 assert.equal(qualityWorkState({status:'active'}),'active');
 assert.equal(qualityWorkState({status:'completed',quantity:'4',received_finished:'0'}),'awaiting_receipt');
 assert.equal(qualityWorkState({status:'completed',quantity:'4'}),'awaiting_receipt');
 assert.equal(qualityWorkState({status:'completed',quantity:'4',received_finished:'4'}),'received');
 assert.equal(qualityWorkState({status:'active',held:true}),'held');
});
