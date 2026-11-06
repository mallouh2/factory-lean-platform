import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {NextRequest} from 'next/server.js';
import {correctionCommand,correctionQuery,correctionResponse,correctionFailure} from '../src/utils/production-corrections.mjs';
const f='11111111-1111-4111-8111-111111111111',id='22222222-2222-4222-8222-222222222222';
const body=()=>({factory:f,operation:'submit',request_id:id,payload:{entry:id,good:'10.1234567890123456789',discarded_quantity:'0',scrap_kg:'0.1234567890123456789',reason:'Measured again after checking the coil',expected_revision:0}});
test('exact quantities and edited/custom reasons are accepted',()=>{
 for(const reason of ['Measurement error, checked again','Fully custom explanation','سبب مخصص لتصحيح القياس']){const input=body();input.payload.reason=reason;assert.deepEqual(correctionCommand(input),input);}
});
for(const [label,change] of [
 ['missing reason',{reason:undefined}],['empty reason',{reason:''}],['whitespace reason',{reason:'   '}],['short reason',{reason:'x'}],['long reason',{reason:'x'.repeat(2001)}],
 ['floating Good',{good:10.1234567890123456789}],['negative Good',{good:'-1'}],['invalid KG',{scrap_kg:'NaN'}],['infinite KG',{scrap_kg:'Infinity'}],['number KG',{scrap_kg:0.123}],
 ['bad entry',{entry:'other'}],['forged approval',{approved_by:id}],['forged status',{status:'APPROVED'}],['missing revision',{expected_revision:undefined}],['negative revision',{expected_revision:-1}],
 ['unsafe revision',{expected_revision:9007199254740992}],['string flag',{change_shift:'true'}],['bad dated proof',{corrected_occurrence_key:'today'}],['wrong allocations',{allocations:{}}],
 ['zero allocation',{allocations:[{source_id:null,quantity:'0'}]}],['extra allocation key',{allocations:[{source_id:null,quantity:'1',approved:true}]}]])
 test('reject '+label,()=>{const input=body();Object.assign(input.payload,change);assert.throws(()=>correctionCommand(input),e=>e.code==='22023');});
test('approval and rejection have narrow payloads',()=>{
 for(const [operation,payload] of [['approve',{id}],['reject',{id,reason:'Please check the measurement'}]])assert.equal(correctionCommand({...body(),operation,payload}).operation,operation);
 for(const [operation,payload] of [['approve',{id,reason:'extra'}],['reject',{id,reason:''}],['approve',{id,good:'100'}]])assert.throws(()=>correctionCommand({...body(),operation,payload}));
});
test('queue query defaults and strict filters',()=>assert.deepEqual(correctionQuery(new URLSearchParams({factory:f})),{factory:f,query:{page_size:50}}));
for(const extra of ['page_size=0','page_size=101','page_size=1.5','status=OTHER','entry=bad','cursor=bad','actor='+id,'factory='+f])test('reject queue query '+extra,()=>assert.throws(()=>correctionQuery(new URLSearchParams('factory='+f+'&'+extra))));
const cursor={version:1,factory:f,actor:id,query_hash:'a'.repeat(64),revision:'55:57:9007199254740993',after_at:'2026-10-19T12:00:00+00:00',after_id:id};
test('cursor retains exact revision and identity',()=>{
 const value=Buffer.from(JSON.stringify(cursor)).toString('base64url');assert.equal(correctionQuery(new URLSearchParams({factory:f,cursor:value})).query.cursor.revision,cursor.revision);
});
for(const change of [{factory:id},{actor:'bad'},{version:2},{revision:'wrong'},{extra:true},{after_at:'today'}])test('reject forged cursor '+Object.keys(change)[0],()=>assert.throws(()=>correctionQuery(new URLSearchParams({factory:f,cursor:Buffer.from(JSON.stringify({...cursor,...change})).toString('base64url')}))));
const values=()=>({entry_id:id,item_id:id,unit:'meter',original_good:'10',original_scrap_kg:'0.25',original_wip:'0',good:'10',discarded_quantity:'0',scrap_kg:'0.25',startup_kg:'0',unfinished:'0',quality_rejected:'0',correction_revision:'0'});
const pending=()=>({contract_version:1,id,entry_id:id,status:'PENDING',revision:1,requested_by:id,requested_at:'2026-10-19T12:00:00Z',reviewed_by:null,reviewed_at:null,correction_id:null,original_values:values(),proposed:{...body().payload,entry:id,startup_kg:'0',unfinished:'0'},applied_values:null,rejection_reason:null});
test('pending contract cannot pretend to have official applied values',()=>{
 const row=pending();assert.equal(correctionResponse(row,body()).status,'PENDING');assert.throws(()=>correctionResponse({...row,applied_values:values()},body()));
 assert.throws(()=>correctionResponse({...row,status:'APPROVED'},body()));
});
test('approved self-correction keeps exact proposed and applied quantities',()=>{
 const row={...pending(),status:'APPROVED',revision:2,reviewed_by:id,reviewed_at:'2026-10-19T12:01:00Z',correction_id:id,applied_values:{...values(),good:body().payload.good}};
 assert.equal(correctionResponse(row,body()).applied_values.good,'10.1234567890123456789');assert.throws(()=>correctionResponse({...row,applied_values:{...values(),good:10.123}},body()));
});
test('queue does not invent zero for missing totals',()=>{
 const args={factory:f,query:{page_size:50}},data={contract_version:1,factory_id:f,total:0,page_size:50,complete:true,next_cursor:null,rows:[]};
 assert.equal(correctionResponse(data,args,true).total,0);
 for(const total of [null,undefined,'',9007199254740992])assert.throws(()=>correctionResponse({...data,total},args,true));
});

test('My Requests uses a strict server-side self filter, not a supplied actor identity',()=>{
 assert.deepEqual(correctionQuery(new URLSearchParams({factory:f,mine:'1'})),{factory:f,query:{page_size:50,mine:true}});
 for(const query of ['mine=true','mine=0','mine=1&mine=1','mine=1&requested_by='+id])assert.throws(()=>correctionQuery(new URLSearchParams('factory='+f+'&'+query)));
});
for(const [error,status] of [[Error('unauthorized'),401],[{code:'42501'},403],[{code:'40001'},409],[{message:'request_conflict'},409],[{message:'source_unavailable'},409],[{message:'quality_weight'},422],[{code:'22023'},422],[{code:'P0002'},404],[Error('connection lost'),503]])
 test('bounded error classification '+status+' '+JSON.stringify(error),()=>{const result=correctionFailure(error,true);assert.equal(result.status,status);assert.equal(result.body.outcome,status===503?'UNKNOWN':undefined);});
let allowed=true,approvalAllowed=true,sessionError=null,rpcError=null,rpcCalls=[],rpcData=null,metadataCalls=[];
globalThis.__correctionAuth={verifyOrigin:r=>{if(r.headers.get('origin')!=='http://localhost')throw Error('invalid_origin');},authenticatedClient:async()=>{if(sessionError)throw Error(sessionError);return {db:{rpc:async(...args)=>{rpcCalls.push(args);return {data:rpcData||pending(),error:rpcError};},from:table=>({select:fields=>({eq:(key,value)=>({in:async(idKey,ids)=>{metadataCalls.push({table,fields,key,value,idKey,ids});return {data:[{id,name:'Pipe',code:'PO-TEST'}],error:null};}})})})}};},authorize:async(_factory,_module,action)=>{if(!allowed||action==='approve'&&!approvalAllowed)throw Error('permission_denied');}};
const compiled=await build({entryPoints:['src/app/api/production-corrections/route.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',plugins:[{name:'test-auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const {verifyOrigin,authenticatedClient,authorize}=globalThis.__correctionAuth;'}));}}]});
const m={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
const post=(input=body(),origin='http://localhost')=>new NextRequest('http://localhost/api/production-corrections',{method:'POST',headers:{origin,'content-type':'application/json'},body:JSON.stringify(input)});
test('actual POST accepts pending status without claiming applied quantities',async()=>{
 rpcCalls=[];const r=await m.exports.POST(post());assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'private, no-store');assert.equal((await r.json()).status,'PENDING');assert.equal(rpcCalls.length,1);assert.equal(rpcCalls[0][0],'production_correction_command');
});
test('actual POST denies origin, identity and authority before business call',async()=>{
 for(const mode of ['origin','identity','authority']){rpcCalls=[];sessionError=mode==='identity'?'unauthorized':null;allowed=mode!=='authority';try{const r=await m.exports.POST(post(body(),mode==='origin'?'http://other':'http://localhost'));assert.equal(r.status,mode==='identity'?401:403);assert.equal(rpcCalls.length,0);}finally{sessionError=null;allowed=true;}}
});
test('actual POST uncertain failure retains same-UUID recovery instruction',async()=>{
 rpcError={code:'PGRST000',message:'internal connection details'};try{const r=await m.exports.POST(post());assert.equal(r.status,503);const d=await r.json();assert.equal(d.outcome,'UNKNOWN');assert.equal(d.retry_same_request,true);assert.ok(!JSON.stringify(d).includes('internal'));}finally{rpcError=null;}
});

test('context GET is a single protected read with exact decimal strings',async()=>{rpcCalls=[];rpcData={id,good:'10.1234567890123456789',startup_kg:'0.25',unfinished:'2',remaining_work:'Finish cooling',correction_revision:'3'};try{const response=await m.exports.GET(new NextRequest('http://localhost/api/production-corrections?factory='+f+'&context_entry='+id));assert.equal(response.status,200);assert.equal((await response.json()).good,'10.1234567890123456789');assert.deepEqual(rpcCalls[0],['production_correction_context',{factory:f,entry:id},{get:true}]);}finally{rpcData=null;}});
test('context query and authority fail closed before SQL',async()=>{for(const suffix of ['&context_entry=bad','&context_entry='+id+'&other=1']){rpcCalls=[];assert.equal((await m.exports.GET(new NextRequest('http://localhost/api/production-corrections?factory='+f+suffix))).status,400);assert.equal(rpcCalls.length,0);}try{allowed=false;rpcCalls=[];assert.equal((await m.exports.GET(new NextRequest('http://localhost/api/production-corrections?factory='+f+'&context_entry='+id))).status,403);assert.equal(rpcCalls.length,0);}finally{allowed=true;}});
test('queue metadata uses only the returned IDs and same-factory RLS reads',async()=>{const row={...pending(),factory_id:f,current_values:{...values(),request_id:id,product_id:id}};rpcData={contract_version:1,factory_id:f,total:1,page_size:50,complete:true,next_cursor:null,rows:[row]};metadataCalls=[];try{const response=await m.exports.GET(new NextRequest('http://localhost/api/production-corrections?factory='+f));assert.equal(response.status,200);const data=await response.json();assert.equal(data.metadata.products[0].name,'Pipe');assert.equal(metadataCalls.length,3);for(const call of metadataCalls){assert.equal(call.key,'factory_id');assert.equal(call.value,f);assert.deepEqual(call.ids,[id]);}}finally{rpcData=null;}});


test('pending count is approval-protected, bounded, factory-scoped and discloses only total',async()=>{
 rpcData={contract_version:1,factory_id:f,total:3,page_size:1,complete:true,next_cursor:null,rows:[]};rpcCalls=[];metadataCalls=[];
 try{const response=await m.exports.GET(new NextRequest('http://localhost/api/production-corrections?factory='+f+'&pending_count=1'));assert.equal(response.status,200);assert.deepEqual(await response.json(),{total:3});assert.equal(response.headers.get('cache-control'),'private, no-store');assert.deepEqual(rpcCalls,[['production_correction_read',{factory:f,query:JSON.stringify({page_size:1,status:'PENDING'})},{get:true}]]);assert.deepEqual(metadataCalls,[]);
 approvalAllowed=false;rpcCalls=[];const denied=await m.exports.GET(new NextRequest('http://localhost/api/production-corrections?factory='+f+'&pending_count=1'));assert.equal(denied.status,403);assert.deepEqual(await denied.json(),{error:'permissionError'});assert.deepEqual(rpcCalls,[]);
 }finally{approvalAllowed=true;rpcData=null;}
});
test('count mode rejects combined, duplicate and malformed parameters before reading',async()=>{
 for(const suffix of ['&pending_count=0','&pending_count=1&status=PENDING','&pending_count=1&pending_count=1']){rpcCalls=[];const response=await m.exports.GET(new NextRequest('http://localhost/api/production-corrections?factory='+f+suffix));assert.equal(response.status,400);assert.deepEqual(rpcCalls,[]);}
});
