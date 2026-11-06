// All fixture writes are in-memory and local, never application or hosted data.
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import {build} from 'esbuild';
const output=resolve(tmpdir(),'FactoryLean-Phase4B-Browser-'+randomUUID());await mkdir(output,{recursive:true});
await build({entryPoints:['tests/production-recording-ui/fixture.tsx'],bundle:true,platform:'browser',jsx:'automatic',outfile:join(output,'fixture.js'),external:['/fonts/*'],logLevel:'silent'});
const id=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`,states=new Map();
function getState(key){if(!states.has(key))states.set(key,{posts:[],entries:[],receipts:new Map(),lost:false});return states.get(key)}
const html='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Isolated Phase 4B recording</title><link rel="stylesheet" href="/base.css"><link rel="stylesheet" href="/fixture.css"></head><body><div id="root"></div><script src="/fixture.js"></script></body></html>';
const server=createServer(async(req,res)=>{try{
 const url=new URL(req.url,'http://127.0.0.1:4190'),key=url.searchParams.get('fixture')||'',state=getState(key);res.setHeader('Cache-Control','private, no-store');
 const json=(data,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(data))};
 if(url.pathname==='/__fixture/state')return json({posts:state.posts,entries:state.entries});
 if(url.pathname==='/api/production-shift-work'){
  const now=Date.now(),late=key.includes('enabled'),expired=key.includes('expired');
  const row=(n,status='active')=>({item_id:id(7+n),item_code:'PI-LOCAL-'+(n+1),request_code:'PO-LOCAL-'+(n+1),product_name:'Pressure pipe',product_name_ar:'أنبوب ضغط',line_id:id(4+n),line_name:'QA line '+(n+1),line_name_ar:'الخط التجريبي '+(n+1),unit:n===1?'piece':'meter',status,actual_start:new Date(now-60000).toISOString(),actual_finish:status==='completed'?new Date(now-30000).toISOString():null,execution_key:'a'.repeat(64),context_hash:'b'.repeat(64),can_record:status==='active'||late,active_recording_eligible:status==='active',policy_late_eligible:status==='completed',late_recording_available:late});
  return json({contract_version:3,factory_id:id(1),available:true,can_edit:!key.includes('denied'),late_recording_available:late,rows:key.includes('empty')?[]:[row(0),row(1),row(2,'completed')],occurrence:{occurrence_key:'c'.repeat(64),name:'Morning shift',name_ar:'الوردية الصباحية',business_date:'2026-10-20',starts_at:new Date(now-3600000).toISOString(),ends_at:new Date(now+(expired?100:3600000)).toISOString(),timezone:'Asia/Riyadh'},server_as_of:new Date(now).toISOString(),expires_at:new Date(now+300000).toISOString(),next_cursor:null,complete:true});
 }
 if(url.pathname==='/api/production-reporting')return json({contract_version:3,factory_id:id(1),rows:state.entries.filter(e=>!url.searchParams.get('entry')||e.id===url.searchParams.get('entry')),complete:true,next_cursor:null});
 if(url.pathname==='/api/production-recording-status'){const receipt=state.receipts.get(url.searchParams.get('request_id'));return json(receipt?{outcome:'COMMITTED',receipt,current:{...receipt.original_payload,good:'2'}}:{outcome:'UNKNOWN'});}
 if(url.pathname==='/api/data'&&req.method==='POST'){
  let raw='';for await(const c of req)raw+=c;const body=JSON.parse(raw);state.posts.push({raw,request:body.args.request_id,header:req.headers['x-factory-recording']});
  if(key.includes('reject')||key.includes('overproduction')&&!body.args.payload.confirm_overproduction)return json({outcome:'REJECTED',error:'recordingValidation',reason:key.includes('overproduction')?'OVERPRODUCTION_CONFIRMATION_REQUIRED':'INVALID_PAYLOAD'},422);
  if(key.includes('unknown'))return json({outcome:'UNKNOWN'},503);
  let receipt=state.receipts.get(body.args.request_id);if(!receipt){const p=body.args.payload,quantity=k=>new RegExp('"'+k+'":([0-9.e+-]+)').exec(raw)?.[1]||'0';
   receipt={contract_version:3,outcome:'COMMITTED',entry_id:randomUUID(),request_id:body.args.request_id,original_payload:{...p,good:quantity('good'),scrap_kg:quantity('scrap_kg')},recorded_at:new Date().toISOString()};state.receipts.set(body.args.request_id,receipt);
   state.entries.unshift({id:receipt.entry_id,item_id:p.item,request_code:'PO-LOCAL-1',line_name:'QA line',line_name_ar:'الخط التجريبي',good:receipt.original_payload.good,scrap_kg:receipt.original_payload.scrap_kg,unit:p.item===id(8)?'piece':'meter',recorded_by:id(2),recorded_at:receipt.recorded_at,factory_id:id(1)});
  }
  return json({data:receipt});
 }
 if(url.pathname==='/api/unfinished')return json({rows:[{id:id(20),factory_id:id(1),product_name:'Pressure pipe WIP',product_name_ar:'أنبوب غير مكتمل',quantity_available:'10',production_available:'10',unit:'meter',remaining_work:'Finish cooling',destinations:[{unit_kind:'line',unit_id:id(4),item_id:id(7)}]}],total:1});
 if(url.pathname==='/api/lean')return json(url.searchParams.get('mode')==='recording_review'?{rows:[],total:0}:{startups:[],causes:[]});
 if(url.pathname==='/api/production-history'){
  if(url.searchParams.get('options')==='1')return json({shifts:[],requests:[],products:[],units:[],technicians:[]});
  return json({rows:[],total:0,page:1,page_size:50,totals:[],highest:[]});
 }
 if(url.pathname==='/api/data')return json({timezone:'Asia/Riyadh'});
 if(url.pathname.startsWith('/api/'))return json({error:'dataWarning'},403);
 if(url.pathname==='/fixture.js'||url.pathname==='/fixture.css'){res.setHeader('Content-Type',url.pathname.endsWith('css')?'text/css':'text/javascript');res.end(await readFile(join(output,url.pathname.slice(1))));return;}
 if(url.pathname==='/base.css'){res.setHeader('Content-Type','text/css');res.end(await readFile('src/app/globals.css'));return;}
 if(/^\/fonts\/[a-z0-9.-]+\.(woff2|txt)$/i.test(url.pathname)){res.setHeader('Content-Type','font/woff2');res.end(await readFile('public'+url.pathname));return;}
 res.setHeader('Content-Type','text/html');res.end(html);
 }catch(e){console.error(e);res.writeHead(500);res.end('Local fixture error')}});
server.listen(4190,'127.0.0.1',()=>console.log('Isolated Phase4B browser fixture http://127.0.0.1:4190; output '+output));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
