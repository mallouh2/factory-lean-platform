import test from 'node:test';
import assert from 'node:assert/strict';
import {evaluateFlow} from '../src/utils/production-flow.mjs';
const line=[{id:'root',line_id:'line',position:1,status:'stopped',dependency_mode:'blocking',impact_scope:'whole_line'},
 {id:'peer',line_id:'line',position:2,status:'running',dependency_mode:'blocking',impact_scope:'whole_line'}];
test('a captured noncritical stop continues flow after later role changes',()=>{
 const flow=evaluateFlow(line,[{work_center_id:'root',blocking_at_start:false,impact_scope_at_start:'none',started_at:'2026-11-11T00:00:00Z'}],[]);
 assert.equal(flow.peer.state,'clear');
});
test('captured critical process impact cannot become harmless through current configuration',()=>{
 const centers=line.map(c=>c.id==='root'?{...c,dependency_mode:'non_blocking',impact_scope:'none'}:c);
 const flow=evaluateFlow(centers,[{work_center_id:'root',blocking_at_start:true,impact_scope_at_start:'whole_line',started_at:'2026-11-11T00:00:00Z'}],[]);
 assert.equal(flow.peer.state,'blocked');assert.equal(flow.peer.source,'root');
});
