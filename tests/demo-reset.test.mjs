import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {requireTarget,validateDay,seedSQL,lossSQL,TARGET} from '../scripts/demo-reset.mjs';

test('destructive CLI rejects every target except explicit TESTING before requiring credentials',()=>{
 for(const target of ['dev','prod','production','local','development','',TARGET.ref]) {
  assert.throws(()=>requireTarget(target),/Only the explicit testing target/);
  try { execFileSync(process.execPath,['scripts/demo-reset.mjs','--target',target,'--day','2026-10-05'],{encoding:'utf8',stdio:'pipe',env:{...process.env,SUPABASE_ACCESS_TOKEN:''}});assert.fail('unsafe target accepted'); }
  catch(error){assert.match(error.stderr,/Only the explicit testing target/);assert.doesNotMatch(error.stderr,/Set SUPABASE_ACCESS_TOKEN/);}
 }
});
test('demo dates reject invalid dates rather than silently rolling them forward',()=>{
 assert.equal(validateDay('2026-10-05'),'2026-10-05');
 for(const value of ['2026-02-31','2026-10-05;delete','2026-2-1','not a date'])assert.throws(()=>validateDay(value));
});
test('seed preparation is deterministic and rollback rehearsal never commits',async()=>{
 const a=await seedSQL('2026-10-05',{rollback:true}),b=await seedSQL('2026-10-05',{rollback:true});
 assert.equal(a,b);assert.match(a,/rollback;\s*$/);assert.doesNotMatch(a,/\bcommit;/i);
 assert.match(a,/pg_control_system/);assert.match(a,/Schema changed; review before reset/);
 assert.doesNotMatch(a,/\btruncate\b|disable trigger|session_replication_role/i);
});
test('missing historical source context fails before any estimate persistence SQL is emitted',()=>{
 assert.throws(()=>lossSQL([{event:{id:'fixture',started_at:'2026-09-01T00:00:00Z',ended_at:'2026-09-01T00:10:00Z',stop_nature:'unplanned'},samples:[]}]),/Incomplete fixture loss/);
});
