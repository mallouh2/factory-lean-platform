import test from 'node:test';
import assert from 'node:assert/strict';
import {evaluateFlow,formatDuration,rankDowntime} from '../src/utils/production-flow.mjs';
const centers=[0,1,2].map(i=>({id:String(i),line_id:'line',position:i,status:i===1?'stopped':'running',dependency_mode:'blocking',impact_scope:'downstream'}));
const stop={id:'stop',work_center_id:'1',started_at:'2026-09-16T08:00:00Z'};
const now=Date.parse('2026-09-16T09:00:00Z');
test('downstream block preserves upstream operating state',()=>{const f=evaluateFlow(centers,[stop],[],now);assert.equal(f['0'].state,'clear');assert.equal(f['2'].state,'blocked');assert.equal(centers[2].status,'running');});
test('whole-line stop affects previous and following machines',()=>{const c=structuredClone(centers);c[1].impact_scope='whole_line';const f=evaluateFlow(c,[stop],[],now);assert.ok(Object.values(f).every(x=>x.state==='blocked'));});
test('no effect and independent machines do not block the line',()=>{for(const scope of ['none']){const c=structuredClone(centers);c[1].impact_scope=scope;assert.equal(evaluateFlow(c,[stop],[],now)['2'].state,'clear');}const c=structuredClone(centers);c[1].line_id=null;assert.equal(evaluateFlow(c,[stop],[],now)['2'].state,'clear');});
test('buffer expires at its exact timestamp',()=>{const c=structuredClone(centers);c[1].dependency_mode='buffer';c[1].buffer_minutes=61;assert.equal(evaluateFlow(c,[stop],[],now)['2'].state,'clear');assert.equal(evaluateFlow(c,[stop],[],now+60000)['2'].state,'blocked');});
test('recorded running alternative restores whole-line flow, stopped alternative does not',()=>{const c=structuredClone(centers);c[1].impact_scope='whole_line';c.push({id:'alt',line_id:null,status:'running'});const transfers=[{original_id:'1',alternative_id:'alt'}];assert.equal(evaluateFlow(c,[stop],transfers,now)['0'].state,'clear');assert.equal(evaluateFlow(c,[stop],transfers,now)['1'].state,'transferred');c[3].status='stopped';assert.equal(evaluateFlow(c,[stop],transfers,now)['0'].state,'blocked');});
test('whole-minute durations omit zero units and scale through days',()=>{
  for(const [minutes,expected] of [[0,'0 min'],[1,'1 min'],[59,'59 min'],[60,'1 h'],[61,'1 h 1 min'],
    [90,'1 h 30 min'],[120,'2 h'],[300,'5 h'],[1440,'1 d'],[1500,'1 d 1 h'],[1560,'1 d 2 h']])
    assert.equal(formatDuration(minutes),expected);
  assert.equal(formatDuration(-1),'0 min');
  assert.equal(formatDuration(90.9),'1 h 30 min');
});
test('signed variance retains direction and uses the same duration units',()=>{
  assert.equal(formatDuration(90,'en',true),'+1 h 30 min');
  assert.equal(formatDuration(-30,'en',true),'-30 min');
  assert.equal(formatDuration(0,'en',true),'0 min');
  assert.equal(formatDuration(-1500,'en',true),'-1 d 1 h');
});
test('arabic durations use localized digits and compact Arabic units',()=>{
  assert.equal(formatDuration(0,'ar'),'٠ د');
  assert.equal(formatDuration(90,'ar'),'١ س ٣٠ د');
  assert.equal(formatDuration(1500,'ar'),'١ ي ١ س');
  assert.equal(formatDuration(-30,'ar',true),'-٣٠ د');
  assert.ok(!/[0-9]/.test(formatDuration(185,'ar')));
});
test('impact combines duration, frequency and blocking; unknown production is not invented',()=>{const data=[{id:'a',reason_id:'long',started_at:'2026-09-16T08:00Z',ended_at:'2026-09-16T09:00Z',blocking_at_start:true},{id:'b',reason_id:'short',started_at:'2026-09-16T08:50Z',ended_at:'2026-09-16T09:00Z'}];const r=rankDowntime(data,'2026-09-16','2026-09-17',{},now);assert.equal(r[0].reason_id,'long');assert.equal(r[0].hasEstimate,false);});
test('transferred intervals reduce estimated blocked production loss',()=>{const e={...stop,reason_id:'r',blocking_at_start:true,rate_at_start:60};const r=rankDowntime([e],'2026-09-16','2026-09-17',{},now,[{downtime_id:'stop',created_at:'2026-09-16T08:30Z'}]);assert.equal(r[0].lostUnits,30);});
