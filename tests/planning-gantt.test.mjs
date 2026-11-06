import test from 'node:test';import assert from 'node:assert/strict';
import{ganttLayout,ganttFocusStart}from'../src/utils/planning-gantt.mjs';
const at=Date.parse('2026-10-31T00:00:00Z'),minute=60000,day=1440*minute;
const job=(id,start,finish)=>({order:{id,start_time:new Date(at+start*minute).toISOString(),expected_finish:finish===null?null:new Date(at+finish*minute).toISOString()}});
test('7/15/30/60/180-minute intervals retain proportional geometry at half-day/day/week zoom',()=>{
 for(const minutes of [7,15,30,60,180])for(const span of [720,1440,10080]){
  const duration=ganttLayout([job('width',0,minutes)],at,at+span*minute,1320).jobs[0];
  assert.ok(Math.abs(duration.width/100*1320-minutes/span*1320)<1e-9);
  assert.equal(duration.compact,minutes/span*1320<168);
 }
});
test('one-minute jobs retain exact time width with a separate readable compact label',()=>{
 const x=ganttLayout([job('PO50',418,419)],at,at+day,1000).jobs[0];
 assert.equal(x.left,418/1440*100);assert.equal(x.width,1/1440*100);assert.equal(x.compact,true);assert.equal(x.track,0);
});
test('both ends clip to the viewport without changing saved evidence',()=>{
 const all=[job('a',-30,60),job('b',1380,1500)],before=structuredClone(all),x=ganttLayout(all,at,at+day);
 assert.equal(x.jobs[0].left,0);assert.equal(x.jobs[0].width,60/1440*100);assert.ok(Math.abs(x.jobs[1].left+x.jobs[1].width-100)<1e-10);assert.equal(x.jobs[1].captionEnd,true);assert.deepEqual(all,before);
});
test('unknown start or finish never fabricates an hour or an actual timestamp',()=>{
 const x=ganttLayout([job('unknown-end',60,null),{order:{id:'no-start'}}],at,at+day);
 assert.equal(x.jobs[0].width,0);assert.equal(x.jobs[0].finish,null);assert.equal(x.unknown[0].id,'no-start');
});
test('nonoverlapping jobs share one lane; adjacent short labels and real overlaps gain only needed tracks',()=>{
 assert.equal(ganttLayout([job('a',0,360),job('b',480,840)],at,at+day).tracks,1);
 assert.equal(ganttLayout([job('a',60,61),job('b',62,63)],at,at+day).tracks,2);
 assert.equal(ganttLayout([job('a',0,240),job('b',120,360)],at,at+day).tracks,2);
});
test('maintenance and production share presentation tracks without changing capacity state',()=>{
 const reservation={id:'m',state:'CONFIRMED',planned_start:new Date(at+300*minute).toISOString(),planned_end:new Date(at+480*minute).toISOString(),actual_stops:[]};
 const before=structuredClone(reservation),x=ganttLayout([job('a',0,20)],at,at+day,1000,[reservation]);
 assert.equal(x.reservations.length,1);assert.equal(x.tracks,1);assert.equal(x.reservations[0].track,0);assert.deepEqual(reservation,before);
 assert.equal(ganttLayout([job('a',250,400)],at,at+day,1000,[reservation]).tracks,2);
});
test('short annotation has a visible gap and includes the marker in collision packing',()=>{
 const x=ganttLayout([job('a',60,61),job('b',62,63)],at,at+day,1000);
 for(const y of x.jobs){assert.equal(y.a,y.left/100*1000);assert.equal(y.b,(y.left+y.width)/100*1000+12+168);}
 assert.equal(x.tracks,2);assert.equal(x.jobs[0].width,1/1440*100);
 const edge=ganttLayout([job('edge',1439,1440)],at,at+day,1000).jobs[0];
 assert.equal(edge.captionEnd,true);assert.equal(edge.a,edge.left/100*1000-12-168);assert.equal(edge.b,1000);
});
test('annotation stacking is deterministic regardless of server row order and repeated refresh',()=>{
 const jobs=[job('a',60,61),job('b',62,63),job('c',63,64)];
 assert.deepEqual(ganttLayout(jobs,at,at+day),ganttLayout([...jobs].reverse(),at,at+day));
 assert.deepEqual(ganttLayout(jobs,at,at+day),ganttLayout(structuredClone(jobs),at,at+day));
});
test('day/week and narrow/wide geometry always follows saved timestamps, not annotation width',()=>{
 for(const span of [day,7*day])for(const pixels of [700,1000,2200]){
  const x=ganttLayout([job('one',418,419)],at,at+span,pixels).jobs[0];
  assert.ok(Math.abs(x.left-418*minute/span*100)<1e-10);assert.ok(Math.abs(x.width-minute/span*100)<1e-10);
 }
});
test('off-screen jobs are absent from that window, and explicit navigation finds upcoming or latest saved work',()=>{
 assert.equal(ganttLayout([job('before',-120,-60),job('after',1500,1510)],at,at+day).jobs.length,0);
 const orders=[job('past',60,90).order,job('future',2000,2050).order],before=structuredClone(orders);
 assert.equal(ganttFocusStart(orders,at+day,day),at+2000*minute-day*.05);
 assert.equal(ganttFocusStart(orders,at+3*day,day),at+2000*minute-day*.05);assert.equal(ganttFocusStart([],at,day),null);assert.deepEqual(orders,before);
});
