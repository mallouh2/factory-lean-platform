// Explicit disposable loopback fixture only. Creates one pending proposal for UI rejection.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
const root=fs.readFileSync(path.join(os.tmpdir(),'FactoryLean-Phase4B-FIX-runtime-location.txt'),'utf8').trim();
const runtime=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
assert.equal(runtime.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(runtime.databaseHost,'127.0.0.1');
assert.equal(runtime.applicationPort,4207);assert.equal(runtime.databasePort,55476);
const base='http://127.0.0.1:4207',factory=runtime.context.factory;
const accounts=JSON.parse(fs.readFileSync(path.join(root,'local-credentials.json'))).accounts;
const output=fs.readFileSync(path.join(os.tmpdir(),'FactoryLean-Table-UX-location.txt'),'utf8').trim();
async function session(role){
 const account=accounts.find(x=>x.role===role),response=await fetch(base+'/api/auth',{method:'POST',headers:{origin:base,'content-type':'application/json'},body:JSON.stringify({action:'signin',email:account.email,password:account.password})});
 assert.equal(response.status,200);const cookies=response.headers.getSetCookie().map(x=>x.split(';')[0]).join('; ');assert.ok(cookies);
 return async(url,body)=>fetch(base+url,{method:body?'POST':'GET',headers:{cookie:cookies,origin:base,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
}
const worker=await session('worker'),owner=await session('owner'),count='/api/production-corrections?'+new URLSearchParams({factory,pending_count:'1'});
const denied=await worker(count);assert.equal(denied.status,403);assert.deepEqual(await denied.json(),{error:'permissionError'});
const before=await owner(count);assert.equal(before.status,200);const baseline=await before.json();assert.deepEqual(Object.keys(baseline),['total']);
const entry='56a3a91f-096c-4fc8-a884-0259678ca5d6',contextUrl='/api/production-corrections?'+new URLSearchParams({factory,context_entry:entry});
const contextResponse=await worker(contextUrl);assert.equal(contextResponse.status,200);const current=await contextResponse.json();
const payload={entry,expected_revision:Number(current.correction_revision),good:current.good,scrap_kg:current.scrap_kg==='0.32'?'0.33':'0.32',discarded_quantity:current.discarded_quantity,startup_kg:current.startup_kg,unfinished:current.unfinished,remaining_work:current.remaining_work||'',reason:'Local table UX acceptance: pending alert only; reject without posting.',allocations:[],confirm_overproduction:false};
const response=await worker('/api/production-corrections',{factory,operation:'submit',request_id:crypto.randomUUID(),payload});assert.equal(response.status,200);const pending=await response.json();assert.equal(pending.status,'PENDING');assert.equal(pending.correction_id,null);
const after=await owner(count);assert.equal(after.status,200);assert.deepEqual(await after.json(),{total:baseline.total+1});
const unchanged=await worker(contextUrl);assert.deepEqual(await unchanged.json(),current);
fs.writeFileSync(path.join(output,'http-fixture.json'),JSON.stringify({factory,entry,id:pending.id,before:baseline.total,after:baseline.total+1,official:current,workerDenied:403,ownerCount:200},null,2));
console.log('PASS local HTTP: worker count403/no data; owner count200; pending proposal raises count by one; official context unchanged. Proposal '+pending.id);
