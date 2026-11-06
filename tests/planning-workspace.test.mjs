import {test} from 'node:test';
import assert from 'node:assert/strict';
import {planningTiming,sortPlanningRows,planningWorkKind} from '../src/utils/planning-workspace.mjs';
const now=Date.parse('2026-10-27T12:00Z');
test('work labels use authoritative relationships and never parse a request name',()=>{
 assert.deepEqual(planningWorkKind({}, {request_type:'INTERNAL_PRODUCTION',name:'Quality replacement'},null),{type:'planningWorkStock',origin:'internalProduction'});
 assert.equal(planningWorkKind({}, {},{choice:'REPLACE'}).origin,'planningOriginQuality');
 assert.equal(planningWorkKind({}, {},{choice:'COMPLETE'}).type,'planningWorkCompletion');
 assert.equal(planningWorkKind({}, {request_type:'STOCK_REPLENISHMENT'},null).origin,'warehouse');
 assert.equal(planningWorkKind({}, {request_type:'SALES_PRODUCTION'},null).origin,'sales');
});
test('timing labels distinguish elapsed start, finish and business deadline without inventing execution',()=>{
 const job={status:'planned',start_time:'2026-10-27T11:00Z',expected_finish:'2026-10-27T13:00Z'};
 assert.equal(planningTiming(job,null,now),'planningStartOverdue');
 assert.equal(planningTiming({...job,status:'active'},null,now),null);
 assert.equal(planningTiming({...job,expected_finish:'2026-10-27T11:30Z'},null,now),'planningFinishOverdue');
 assert.equal(planningTiming(job,{required_by:'2026-10-27T11:00Z'},now),'planningDemandOverdue');
 for(const status of ['completed','cancelled'])assert.equal(planningTiming({...job,status},{required_by:'2026-10-20'},now),null);
 assert.equal(planningTiming({status:'planned'},null,now),null);
});
test('table sorting preserves priority-engine order, typed quantities and original arrays',()=>{
 const items=[{id:'a',request_id:'1',code:'PO-2',target_quantity:10,unit:'meter'}, {id:'b',request_id:'2',code:'PO-1',target_quantity:5,unit:'piece'}];
 const original=structuredClone(items),requests=[{id:'1'},{id:'2',required_by:'2026-10-29'}];
 assert.equal(sortPlanningRows(items,requests,'priority'),items);
 assert.deepEqual(sortPlanningRows(items,requests,'required').map(x=>x.id),['b','a']);
 assert.deepEqual(sortPlanningRows(items,requests,'reference').map(x=>x.id),['b','a']);
 assert.deepEqual(sortPlanningRows(items,requests,'start').map(x=>x.id),['a','b']);
 assert.deepEqual(items,original);
});
