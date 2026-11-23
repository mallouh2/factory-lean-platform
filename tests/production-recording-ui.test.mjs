import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {recordingNumber,recordingScrap,recordingBody,recordingScope,readIntent,prepareIntent,retainIntent,confirmReceipt,acknowledgeIntent,canRecordWork,sameMeasurement,startupMinuteRanges,resolveStartupMinute} from '../src/utils/production-recording-intent.mjs';
const id=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`,actor=id(1),factory=id(2),request=id(3),entry=id(4);
class MemoryStorage{map=new Map();getItem(k){return this.map.get(k)??null}setItem(k,v){this.map.set(k,String(v))}removeItem(k){this.map.delete(k)}}
const payload={item:id(5),good:'0.1234567890123456789',scrap_kg:'0.5000000000000000001',unfinished:'0',notes:'Actual measured output'};
const prepare=(storage,p=payload)=>prepareIntent(storage,actor,factory,p,{request});
const receipt={contract_version:3,outcome:'COMMITTED',request_id:request,entry_id:entry,original_payload:payload};
const bundle=await build({entryPoints:['src/services/production-recording-client.ts'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'}),m={exports:{}};
new Function('require','module','exports',bundle.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
const {postRecording,recoverRecording}=m.exports;
test('startup time uses factory-local minutes and excludes partial and future minutes',()=>{
 const zone='Asia/Qatar';
 const ranges=startupMinuteRanges([{from:'2026-11-22T10:23:34.596Z',to:'2026-11-22T11:00:00Z'}],zone,Date.parse('2026-11-22T10:25:20Z'));
 assert.deepEqual(ranges.map(({from,to})=>[from,to]),[['2026-11-22T13:24','2026-11-22T13:25']]);
 const time=minute=>resolveStartupMinute(minute,ranges,zone).at;
 assert.equal(time('13:23'),'');
 assert.equal(time('13:24'),'2026-11-22T10:24:00.000Z');
 assert.equal(time('13:26'),'');
 assert.equal(time('13:24:30'),'');
});
test('overnight startup windows resolve the day from the minute and respect gaps',()=>{
 const zone='Asia/Qatar';
 const ranges=startupMinuteRanges([{from:'2026-11-21T20:30Z',to:'2026-11-21T21:00Z'},
  {from:'2026-11-21T21:15Z',to:'2026-11-21T22:00Z'}],zone,Date.parse('2026-11-21T22:30Z'));
 assert.deepEqual(resolveStartupMinute('00:20',ranges,zone),{matches:['2026-11-22'],at:'2026-11-21T21:20:00.000Z'});
 assert.equal(resolveStartupMinute('00:10',ranges,zone).at,'');
});
test('startup is an exact subset of total scrap, including localized decimal input',()=>{
 assert.deepEqual(recordingScrap('٠٫٣','٠٫١'),{totalKg:'0.3',startupKg:'0.1',regularKg:'0.2'});
 assert.deepEqual(recordingScrap('12','0'),{totalKg:'12',startupKg:'0',regularKg:'12'});
 assert.deepEqual(recordingScrap('0','0'),{totalKg:'0',startupKg:'0',regularKg:'0'});
 assert.equal(recordingScrap('-1','0').error,'prv3InvalidScrap');
 assert.equal(recordingScrap('1','-1').error,'prv3InvalidStartupScrap');
 assert.equal(recordingScrap('0.1','0.100000000000000000001').error,'prv3InvalidStartupScrap');
 const startup=id(6),argumentsSent={...payload,scrap_kg:'0.3',startup_kg:'0.1',startup_id:startup,startup_at:'2026-11-22T08:10:00Z'};
 const body=JSON.parse(recordingBody(factory,request,argumentsSent)).args.payload;
 assert.equal(body.scrap_kg,0.3);
 assert.equal(body.startup_kg,0.1);
 assert.equal(body.startup_id,startup);
 assert.ok(!Object.hasOwn(body,'regular_kg'));
});
for(const [input,wanted] of [['0.1234567890123456789','0.1234567890123456789'],['٠٫٥٠٠٠٠٠٠٠٠٠٠٠٠٠٠٠٠٠١','0.5000000000000000001'],['1e-19','0.0000000000000000001'],['-0','0']])test(`exact measurement ${input}`,()=>assert.equal(recordingNumber(input),wanted));
for(const input of ['', '-1','Infinity','NaN','1,000','1e9999'])test(`invalid measurement ${input||'empty'}`,()=>assert.throws(()=>recordingNumber(input),/prv3InvalidQuantity/));
test('numeric JSON tokens preserve exact values and escape notes',()=>{const body=recordingBody(factory,request,{...payload,notes:'"\\\n'});assert.ok(body.includes('"good":0.1234567890123456789'));assert.ok(body.includes('"scrap_kg":0.5000000000000000001'));assert.equal(JSON.parse(body).args.payload.notes,'"\\\n');assert.ok(!body.includes('"good":"'));});
test('intent survives remount with original raw body and UUID',()=>{const s=new MemoryStorage(),a=prepare(s);assert.deepEqual(readIntent(s,actor,factory),a);assert.equal(prepare(s).request,request);assert.equal(prepare(s).body,a.body);});
test('changed physical recording cannot replace unresolved intent',()=>{const s=new MemoryStorage();prepare(s);assert.throws(()=>prepare(s,{...payload,good:'2'}),/prv3Unresolved/);assert.equal(readIntent(s,actor,factory).request,request);});
test('different users and factories cannot read another intent',()=>{const s=new MemoryStorage();prepare(s);assert.equal(readIntent(s,id(6),factory),null);assert.equal(readIntent(s,actor,id(6)),null);assert.throws(()=>recordingScope('actor',factory));});
test('quota and write-readback failures prevent submission',()=>{const s=new MemoryStorage();s.setItem=()=>{};assert.throws(()=>prepare(s),/prv3StorageUnavailable/);s.setItem=()=>{throw Error('quota')};assert.throws(()=>prepare(s),/prv3StorageUnavailable/);});
test('malformed or wrong-scope persisted record fails closed',()=>{const s=new MemoryStorage();s.setItem(recordingScope(actor,factory),'broken');assert.throws(()=>readIntent(s,actor,factory));s.setItem(recordingScope(actor,factory),JSON.stringify({...prepare(new MemoryStorage()),factory:id(9)}));assert.throws(()=>readIntent(s,actor,factory));});
test('committed receipt must match request, version and entry UUID',()=>{const intent=prepare(new MemoryStorage());assert.ok(confirmReceipt(receipt,intent));for(const r of [{...receipt,request_id:id(9)},{...receipt,contract_version:2},{...receipt,outcome:'UNKNOWN'},{...receipt,entry_id:'wrong'}])assert.ok(!confirmReceipt(r,intent));});
test('terminal acknowledgment clears payload but retains bounded minimal receipt',()=>{const s=new MemoryStorage(),intent=prepare(s);acknowledgeIntent(s,intent,receipt);assert.equal(readIntent(s,actor,factory),null);assert.deepEqual(Object.keys(JSON.parse(s.getItem(recordingScope(actor,factory)+':receipts'))[0]).sort(),['at','entry','request']);assert.ok(![...s.map.values()].join('').includes(payload.notes));});
test('unresolved old intent does not expire; receipt tombstones expire and cap',()=>{const s=new MemoryStorage(),intent=prepare(s),key=recordingScope(actor,factory)+':receipts';s.setItem(key,JSON.stringify([{request:'expired',at:0},...Array.from({length:120},(_,i)=>({request:String(i),at:Date.now()}))]));acknowledgeIntent(s,intent,receipt);assert.equal(JSON.parse(s.getItem(key)).length,100);assert.ok(!s.getItem(key).includes('expired'));const old={...prepare(s),created_at:'2020-01-01T00:00:00Z'};retainIntent(s,old);assert.equal(readIntent(s,actor,factory).created_at,old.created_at);});
test('cannot acknowledge a different tab intent or mismatched receipt',()=>{const s=new MemoryStorage(),intent=prepare(s);assert.throws(()=>acknowledgeIntent(s,{...intent,request:id(8)},receipt));assert.throws(()=>acknowledgeIntent(s,intent,{...receipt,request_id:id(8)}));assert.ok(readIntent(s,actor,factory));});
test('capability fails closed for absent, false, or partial contracts',()=>{const e={available:true,can_edit:true,late_recording_available:false},active={status:'active',can_record:true,active_recording_eligible:true},completed={status:'completed',can_record:true,policy_late_eligible:true,late_recording_available:true};assert.equal(canRecordWork(e,active),true);assert.equal(canRecordWork(e,completed),false);assert.equal(canRecordWork({...e,late_recording_available:true},completed),true);assert.equal(canRecordWork({...e,can_edit:false},active),false);assert.equal(canRecordWork(null,active),false);assert.equal(canRecordWork(e,{...active,status:'scheduled'}),false);});
test('stale completed capability shows the localized server rejection without losing original intent',async()=>{
 const intent=prepare(new MemoryStorage());
 assert.deepEqual(await postRecording(intent,async()=>new Response(JSON.stringify({outcome:'REJECTED',error:'prv3LateDisabled'}),{status:503})),{kind:'REJECTED',error:'prv3LateDisabled',reason:undefined});
});
test('similarity is exact, item-specific and advisory within 30 minutes',()=>{const row={item_id:id(5),good:payload.good,scrap_kg:payload.scrap_kg,recorded_at:new Date().toISOString()};assert.ok(sameMeasurement(row,id(5),payload.good,payload.scrap_kg));assert.ok(!sameMeasurement(row,id(6),payload.good,payload.scrap_kg));assert.ok(!sameMeasurement(row,id(5),'0.1234567890123456788',payload.scrap_kg));assert.ok(!sameMeasurement({...row,recorded_at:'2020-01-01'},id(5),payload.good,payload.scrap_kg));});
test('actual client sends only persisted body with exact transport opt-in',async()=>{const intent=prepare(new MemoryStorage());const result=await postRecording(intent,async(url,options)=>{assert.equal(url,'/api/data');assert.equal(options.body,intent.body);assert.equal(options.headers['X-Factory-Recording'],'3');assert.equal(options.credentials,'same-origin');return Response.json({data:receipt})});assert.equal(result.kind,'COMMITTED');});
for(const [name,reply] of [['lost response',()=>{throw Error('offline')}],['invalid response',()=>new Response('broken')],['auth expired',()=>Response.json({error:'unauthorized'},{status:401})],['collision',()=>Response.json({outcome:'REJECTED',error:'recordingRequestConflict'},{status:409})],['untrusted success',()=>Response.json({data:{...receipt,request_id:id(9)}})]])test(`${name} retains UNKNOWN without inventing success`,async()=>{const s=new MemoryStorage(),intent=prepare(s);assert.equal((await postRecording(intent,reply)).kind,'UNKNOWN');assert.ok(readIntent(s,actor,factory));});
test('definitive rejection is explicit and SQL details are not displayed',async()=>{const result=await postRecording(prepare(new MemoryStorage()),async()=>Response.json({outcome:'REJECTED',reason:'SHIFT_EXPIRED',error:'raw SQL internal'},{status:422}));assert.deepEqual(result,{kind:'REJECTED',reason:'SHIFT_EXPIRED',error:'dataWarning'});});
test('recovery reads matching committed result and separate corrected current values without POST',async()=>{const s=new MemoryStorage(),intent=prepare(s),calls=[];const result=await recoverRecording(intent,s,async(url,options)=>{calls.push(options.method||'GET');assert.ok(url.includes(request));return Response.json({outcome:'COMMITTED',receipt,current:{good:'2'}})});assert.equal(result.kind,'COMMITTED');assert.equal(result.receipt.original_payload.good,payload.good);assert.equal(result.current.good,'2');assert.deepEqual(calls,['GET']);assert.ok(readIntent(s,actor,factory).last_checked_at);});
test('NOT_FOUND and denied recovery cannot clear an uncertain original intent',async()=>{for(const status of [200,403]){const s=new MemoryStorage(),intent=prepare(s);assert.equal((await recoverRecording(intent,s,async()=>Response.json({outcome:'NOT_FOUND',error:'permissionError'},{status}))).kind,'UNKNOWN');assert.ok(readIntent(s,actor,factory));}});
test('stale-tab recovery cannot replace a newer unresolved intent',async()=>{const s=new MemoryStorage(),old=prepare(s);acknowledgeIntent(s,old,null);const next=prepareIntent(s,actor,factory,{...payload,good:'9'},{request:id(9)});await assert.rejects(recoverRecording(old,s,()=>{throw Error('must not fetch')}),/prv3StorageUnavailable/);assert.deepEqual(readIntent(s,actor,factory),next);});
test('all production V3 translations exist in both dictionaries',()=>{
 const source=readFileSync('src/features/ProductionRecordingV3.tsx','utf8')+readFileSync('src/services/production-recording-client.ts','utf8');
 const en=JSON.parse(readFileSync('src/locales/en.json')),ar=JSON.parse(readFileSync('src/locales/ar.json'));
 const keys=['unauthorized','permissionError',...[...source.matchAll(/['"]((?:prv3|recording)[A-Z][A-Za-z]+)['"]/g)].map(m=>m[1])];
 for(const key of keys){assert.ok(en[key],key+' EN');assert.ok(ar[key],key+' AR');}
 assert.deepEqual(Object.keys(en).filter(k=>k.startsWith('prv3')).sort(),Object.keys(ar).filter(k=>k.startsWith('prv3')).sort());
});
test('new design variables exactly reuse approved token values',()=>{const source=JSON.parse(readFileSync(new URL('./fixtures/approved-recording-tokens.json',import.meta.url),'utf8')).tokens,actual=readFileSync('src/styles/design-tokens.css','utf8'),extract=s=>[...s.matchAll(/(--fl-[\w-]+)\s*:\s*([^;]+);/g)].map(m=>[m[1],m[2].trim()]);assert.deepEqual(extract(actual),source);assert.equal(extract(actual).length,256);});
test('Floor controls retained; Finish opens shared recording and History/exact entry remain accessible',()=>{const floor=readFileSync('src/features/FactoryFloorV2.tsx','utf8'),component=readFileSync('src/features/ProductionRecordingV3.tsx','utf8');for(const key of ['ProductionRecordingV3','ProductionExecutionActions','setCompletionItem(String(item.id))'])assert.ok(floor.includes(key),key);assert.ok(component.includes('surface="history"'));assert.ok(component.includes('surface="record" exactRecording'));assert.ok(component.includes('navigator.locks.request'));assert.doesNotMatch(component,/\bNumber\(draft\./);});

for(const error of ['outputPaused','outputEnrollmentRequired','outputCarryoverUnsupported'])test('manufactured rejection retains localized recovery: '+error,async()=>{const result=await postRecording(prepare(new MemoryStorage()),async()=>Response.json({outcome:'REJECTED',error},{status:409}));assert.equal(result.kind,'REJECTED');assert.equal(result.error,error);});
