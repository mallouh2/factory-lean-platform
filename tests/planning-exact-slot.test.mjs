import test from 'node:test';
import assert from 'node:assert/strict';
import {formatLocalInput,localDateTimeToUtc} from '../src/utils/manufacturing.mjs';
import {firstAvailable} from '../src/utils/planning.mjs';
test('busy interval boundary retains seconds and milliseconds through the scheduling input',()=>{
 const end=Date.parse('2026-11-09T06:36:52.598Z');
 const slot=firstAvailable([{start:end-3600000,finish:end}],end-1800000,29*60000,end+86400000);
 assert.equal(slot.start,end);
 const input=formatLocalInput(new Date(slot.start).toISOString(),'Asia/Qatar',true);
 assert.equal(input,'2026-11-09T09:36:52.598');
 assert.equal(Date.parse(localDateTimeToUtc(input,'Asia/Qatar')),end);
 assert.ok(Date.parse(localDateTimeToUtc(formatLocalInput(new Date(end).toISOString(),'Asia/Qatar'),'Asia/Qatar'))<end,'Minute truncation reproduces the overlap');
});
test('precise operational instants round trip across DST transitions without shifting stored UTC',()=>{
 for(const stamp of ['2026-03-08T06:59:59.125Z','2026-03-08T07:00:00.125Z','2026-11-01T07:00:01.598Z']){
  const input=formatLocalInput(stamp,'America/New_York',true);
  assert.equal(localDateTimeToUtc(input,'America/New_York'),stamp);
 }
 assert.throws(()=>localDateTimeToUtc('2026-03-08T02:30:00.125','America/New_York'),/invalidDate/);
});
