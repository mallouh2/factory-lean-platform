import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
const id='11111111-1111-4111-8111-111111111111';
async function invoke(hours,{manual=false,allowed=true}={}){
 const original=globalThis.fetch,oldDeno=globalThis.Deno,stores=[];let handler;
 globalThis.Deno={env:{get:k=>k==='SUPABASE_URL'?'http://127.0.0.1:1':'fixture-only'},serve:f=>{handler=f;}};
 globalThis.fetch=async(input,init)=>{
  const url=new URL(String(input));assert.equal(url.origin,'http://127.0.0.1:1');
  if(url.pathname==='/auth/v1/user')return Response.json({id,email_confirmed_at:'2026-01-01T00:00:00Z'});
  const op=url.pathname.split('/').at(-1),body=JSON.parse(init.body);
  if(op==='can_access')return Response.json(allowed);
  if(op==='store_lean_evidence'){stores.push(body);return Response.json({id});}
  assert.equal(op,'lean_read');
  if(body.query.mode==='detail')return Response.json({source_revision:1,evidence_version:2,problem:{id,line_id:id,mechanism:'scrap'},initiatives:[{id,product_id:id,revision:1,completed_at:'2026-01-02T00:00:00Z',baseline_evidence:{version:2,product_id:id,problem_id:id,metrics:{},runtime_hours:hours,coverage_complete:false,from:'2026-01-01T00:00:00Z',to:'2026-01-01T01:00:00Z'}}]});
  return Response.json({source_revision:1,evidence_version:2,total:0,rows:[]});
 };
 try{
  const result=await build({entryPoints:['supabase/functions/lean-comparison/index.ts'],bundle:true,write:false,format:'cjs',platform:'node',packages:'external',logLevel:'silent'}),m={exports:{}};
  new Function('require','module','exports',result.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
  const r=await handler(new Request('http://127.0.0.1/edge',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer fixture-user'},body:JSON.stringify({factory:id,operation:manual?'manual':'verify',problem_id:id,initiative_id:id,product_id:id,expected_revision:1,request_id:id,desired_hours:hours,cutoff:'2026-01-02T00:00:00Z',outcome:'INSUFFICIENT_DATA',note:'No verified operating exposure'})}));
  return {status:r.status,data:await r.json(),stores};
 }finally{globalThis.fetch=original;if(oldDeno===undefined)delete globalThis.Deno;else globalThis.Deno=oldDeno;}
}
test('actual Edge permits honest authorized verification of zero-exposure saved baseline',async()=>{
 const r=await invoke(0);assert.equal(r.status,200);assert.equal(r.data.evidence.complete,false);assert.equal(r.data.evidence.status,'INCOMPLETE');assert.equal(r.stores.length,1);assert.equal(r.stores[0].payload.outcome,'INSUFFICIENT_DATA');assert.equal(r.stores[0].evidence.before.collected_hours,'0');
});
test('null saved exposure retains incomplete verification behavior',async()=>{const r=await invoke(null);assert.equal(r.status,200);assert.equal(r.data.evidence.complete,false);});
test('manual zero-hour request remains invalid and never persists',async()=>{const r=await invoke(0,{manual:true});assert.equal(r.status,400);assert.equal(r.stores.length,0);});
test('negative saved exposure remains invalid',async()=>{const r=await invoke(-1);assert.equal(r.status,400);assert.equal(r.stores.length,0);});
test('missing effective verification authority is denied before trusted persistence',async()=>{const r=await invoke(0,{allowed:false});assert.equal(r.status,403);assert.equal(r.stores.length,0);});
