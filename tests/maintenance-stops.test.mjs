import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {maintenanceStopCommandValid} from '../src/utils/maintenance-stops.mjs';
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const stop={factory:id(1),work_center:id(2),nature:'planned',reason:null,activity:'inspection',notes:'',schedule:id(3),expected_revision:2,expected_request_revision:3,request_id:id(4)};
const correction={factory:id(1),event:id(2),schedule:id(3),approval_revision:2,operation:'UNLINK',reason:'Wrong association',expected_revision:1,request_id:id(4)};
test('linked stop boundary accepts explicit planned and contextual emergency commands',()=>{
 assert.ok(maintenanceStopCommandValid('stop_machine_for_maintenance',stop));
 assert.ok(maintenanceStopCommandValid('stop_machine_for_maintenance',{...stop,nature:'unplanned',reason:id(5),activity:null}));
});
test('linked stop rejects missing proof, cross-scope payload fields and invalid classification',()=>{
 for(const patch of [{work_center:null},{schedule:''},{expected_revision:'2'},{expected_request_revision:-1},{request_id:null},
  {actor:id(5)},{enabled:true},{started_at:'2026-01-01'},{notes:'x'.repeat(2001)},{nature:'unplanned'},{reason:id(5)},{activity:'invented'}])
  assert.equal(maintenanceStopCommandValid('stop_machine_for_maintenance',{...stop,...patch}),false,JSON.stringify(patch));
});
test('correction requires reason, event, approval revision, optimistic revision and retry',()=>{
 assert.ok(maintenanceStopCommandValid('correct_maintenance_stop',correction));
 assert.ok(maintenanceStopCommandValid('correct_maintenance_stop',{...correction,operation:'LINK'}));
 for(const patch of [{event:null},{reason:'  '},{reason:'x'.repeat(4001)},{operation:'UPDATE'},{approval_revision:null},{expected_revision:-1},{request_id:null},{result:{status:'READY'}},{factory_id:id(1)}])
  assert.equal(maintenanceStopCommandValid('correct_maintenance_stop',{...correction,...patch}),false);
});
test('association controls have English/Arabic parity and no raw diagnostic labels',()=>{
 const en=JSON.parse(readFileSync('src/locales/en.json')),ar=JSON.parse(readFileSync('src/locales/ar.json'));
 for(const key of Object.keys(en).filter(k=>/^maintenance(Stop|Actual|NoActual|NoEligible|Ordinary|Association|Relationship|Unlink|Reviewed|Approval|Active)/.test(k))) {
  assert.ok(ar[key],key);assert.notEqual(en[key],ar[key],key);
 }
});
test('Floor uses atomic RPC only for explicit selection; regular emergency path remains available',()=>{
 const code=readFileSync('src/features/FactoryFloorV2.tsx','utf8');
 assert.match(code,/linkedArgs\?'stop_machine_for_maintenance':'stop_machine'/);
 assert.match(code,/request_id:stopRetry.current!\.id/);
 assert.match(code,/setStopSchedule\(null\)/);
 const detail=readFileSync('src/features/MaintenanceActualStops.tsx','utf8');
 assert.match(detail,/can\('maintenance','edit'\) && can\('downtime','edit'\) && row.ended_at/);
 assert.match(detail,/maxLength=\{4000\}/);
});
