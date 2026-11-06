import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {canRecordWork} from '../src/utils/production-recording-intent.mjs';import {shiftWorkResponse} from '../src/utils/production-shift-work.mjs';
const row={status:'completed',can_record:true,policy_late_eligible:true,same_shift_recording_available:true,late_recording_available:false};
const page={contract_version:3,available:true,can_edit:true,late_recording_available:false,total:1,complete:true,rows:[row]};
test('server-authorized completed same-shift work is recordable with late activation FALSE',()=>{
 assert.equal(canRecordWork(page,row),true);assert.equal(shiftWorkResponse(page).rows[0].same_shift_recording_available,true);
 for(const patch of [{can_record:false},{policy_late_eligible:false},{same_shift_recording_available:false},{status:'planned'}])assert.equal(canRecordWork(page,{...row,...patch}),false);
 assert.equal(canRecordWork({...page,available:false},row),false);assert.equal(canRecordWork({...page,can_edit:false},row),false);
});
test('unknown capability fails closed and incoherent same-shift responses reject',()=>{
 assert.equal(canRecordWork(page,{...row,same_shift_recording_available:undefined}),false);
 for(const patch of [{can_record:false},{policy_late_eligible:false},{status:'active'},{same_shift_recording_available:'true'}])assert.throws(()=>shiftWorkResponse({...page,rows:[{...row,...patch}]}));
 assert.throws(()=>shiftWorkResponse({...page,can_edit:false}));
 assert.throws(()=>shiftWorkResponse({...page,available:false}));
});
test('same-shift explanation is translated without adding another control or input',()=>{
 const source=readFileSync('src/features/ProductionRecordingV3.tsx','utf8');assert.ok(source.includes("message('prv3CompletedSameShift','info')"));
 for(const lang of ['en','ar'])assert.ok(JSON.parse(readFileSync('src/locales/'+lang+'.json','utf8')).prv3CompletedSameShift);
});
