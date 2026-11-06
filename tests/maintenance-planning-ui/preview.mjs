// Loopback-only synthetic READ fixture. No credentials, remote clients or writable database.
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {tmpdir} from 'node:os';
import {build} from 'esbuild';
const output=resolve(tmpdir(),'FactoryLean-Maintenance-UI-20261012');await mkdir(output,{recursive:true});
await build({entryPoints:['tests/maintenance-planning-ui/fixture.tsx'],bundle:true,platform:'browser',jsx:'automatic',outfile:join(output,'fixture.js'),logLevel:'silent'});
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const time=n=>new Date(Date.now()+n*3600000).toISOString();
const requests=Array.from({length:32},(_,n)=>({id:id(100+n),factory_id:id(1),code:`MR-QA-${n+1}`,title:n===0?'Inspect barrel heater':'Service request '+(n+1),description:'Synthetic fixture only',
 work_center_id:id(n===4?5:3),line_id:n===4?null:id(4),machine_code:n===4?'IN-1':'EX-1',machine_name:n===4?'Independent printer':'Extruder',machine_name_ar:n===4?'الطابعة المستقلة':'ماكينة البثق',
 line_name:n===4?null:'QA extrusion line',line_name_ar:n===4?null:'خط البثق التجريبي',status:n===3?'IN_PROGRESS':n===5?'VERIFIED':'OPEN',maintenance_kind:'PLANNED',
 estimated_duration_minutes:30,preferred_start:time(1),preferred_end:time(5),revision:1,priority:'NORMAL',source:'MANUAL'}));
const make=(n,state,start,end,independent=false)=>({id:id(200+n),factory_id:id(1),maintenance_request_id:requests[n].id,work_center_id:requests[n].work_center_id,code:requests[n].code,
 state,revision:1,planned_start:time(start),planned_end:time(end),hold_started_at:n===3?time(-2):null,released_at:n===5?time(-.5):null,
 actual_hold:n===3,overrun:n===3,missed_window:false,resources:[{resource_kind:'MACHINE',machine_id:id(independent?5:3),line_id:null,impact_reason:'Persisted fixture scope'},
 ...independent?[]:[{resource_kind:'LINE',machine_id:null,line_id:id(4),impact_reason:'Conservative whole line'}]]});
const schedules=[make(1,'PROPOSED',1,2),make(2,'CONFIRMED',4,5),make(3,'CONFIRMED',-2,-1),make(4,'PROPOSED',2,3,true),make(5,'RELEASED',-3,-1)];
const board={active:false,requests,schedules,preview_available:false,history_available:false,read_at:new Date().toISOString()};
const html='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Isolated Maintenance component verification</title><link rel="stylesheet" href="/styles.css"><link rel="stylesheet" href="/fixture.css"></head><body><div id="root"></div><script src="/fixture.js"></script></body></html>';
const server=createServer(async(req,res)=>{
 try {
  const url=new URL(req.url,'http://127.0.0.1:4205');
  if(url.pathname==='/fixture.css'){res.setHeader('Content-Type','text/css');res.end(await readFile(join(output,'fixture.css')));return;}
  if(url.pathname==='/api/production-readiness'){
   res.setHeader('Content-Type','application/json');res.end(JSON.stringify({factory:id(1),item:id(8),queue_ready:true,
    physical:{applicable:true,ready:true,reason:null,machine:{id:id(3),code:'EX-1',name:'Extruder',name_ar:'ماكينة البثق',status:'idle'}},maintenance_block:null}));return;
  }
  if(url.pathname==='/api/maintenance' && (url.searchParams.has('actual_stop_machine') || url.searchParams.has('actual_stop_request'))){
   res.setHeader('Content-Type','application/json');
   if(url.searchParams.has('actual_stop_machine')){res.end(JSON.stringify({factory:id(1),machine:id(3),eligible:[{id:id(200),revision:2,request_revision:3,code:'MR-QA-1',title:'Inspect barrel heater',planned_start:time(-.5),planned_end:time(.5)}]}));return;}
   const current=[{id:id(400),schedule_id:id(200),event_id:id(500),revision:1,relationship:'PLANNED_MAINTENANCE',approval_revision:2,started_at:time(-1),ended_at:time(-.5)},
    {id:id(401),schedule_id:id(200),event_id:id(501),revision:1,relationship:'CONTEXTUAL_UNPLANNED',approval_revision:2,started_at:time(-.4),ended_at:null}];
   res.end(JSON.stringify({factory:id(1),request:id(100),current,history:current.map(row=>({...row,operation:'LINK',reason:'Explicit synthetic scheduled stop',recorded_at:row.started_at,actor_name:'Local engineer',reviewed_evidence:row.ended_at?[{id:id(600)}]:[]})),history_total:27}));return;
  }
  if(req.method!=='GET'){res.writeHead(405);res.end();return;}
  if(url.pathname==='/favicon.ico'){res.writeHead(204);res.end();return;}
  if(url.pathname==='/api/maintenance-planning'){
   res.setHeader('Content-Type','application/json');const mode=url.searchParams.get('mode');
   if(url.searchParams.get('view')==='operational'){
    const from=url.searchParams.get('start'),to=url.searchParams.get('end'),domain=url.searchParams.get('domain')||'all';
    const rows=requests.map(r=>{const s=schedules.find(s=>s.maintenance_request_id===r.id);
     if(!s)return {kind:'REQUEST',id:r.id,uncertain:false,payload:{request:r}};
     const line_ids=s.resources.some(x=>x.line_id)?[id(4)]:[],machine_ids=[r.work_center_id];
     const occupancy={id:s.id,lineIds:line_ids,machineIds:machine_ids,productIds:[],start:s.hold_started_at||s.planned_start,
      finish:s.actual_hold?null:s.planned_end,continues:s.actual_hold,reserved:['CONFIRMED','INVALIDATED'].includes(s.state)};
     return {kind:'MAINTENANCE',id:s.id,uncertain:false,payload:{request:r,schedule:{...s,line_ids,machine_ids,actual_stops:[],occupancy}}};
    });
    if(domain==='all')rows.push({kind:'PRODUCTION',id:id(8),uncertain:false,payload:{order:{id:id(8),factory_id:id(1),request_id:id(7),product_id:id(6),status:'planned',line_id:id(4),unit:'piece',target_quantity:20,
     start_time:new Date(Date.parse(from)+3600000).toISOString(),expected_finish:new Date(Date.parse(from)+3*3600000).toISOString()},request:{id:id(7),factory_id:id(1),code:'PO-QA',name:'Synthetic planning order',priority:'normal'},
     occupancy:{reserved:true,start:new Date(Date.parse(from)+3600000).toISOString(),finish:new Date(Date.parse(from)+3*3600000).toISOString(),lineIds:[id(4)]}}});
    rows.sort((a,b)=>a.kind.localeCompare(b.kind)||a.id.localeCompare(b.id));const after=url.searchParams.get('after_id');const offset=after?rows.findIndex(r=>r.id===after)+1:0;
    const chosen=rows.slice(offset,offset+100),more=offset+100<rows.length,stamp=url.searchParams.get('evaluated_at')||new Date().toISOString();
    res.end(JSON.stringify({factory:id(1),start:from,end:to,line:url.searchParams.get('line'),machine:null,domain,rows:chosen,total:rows.length,scope_complete:true,
     completeness:rows.length>100?'INCOMPLETE':'COMPLETE',reason:rows.length>100?'PAGES_PENDING':null,has_more:more,next:more?{kind:chosen.at(-1).kind,id:chosen.at(-1).id}:null,
     context_hash:'a'.repeat(64),evaluated_at:stamp,valid_until:new Date(Date.parse(stamp)+60000).toISOString(),active:false,preview_available:true,history_available:true}));return;
   }

   if(mode==='history'){res.end(JSON.stringify({request_id:url.searchParams.get('request'),schedule_id:null,through_revision:0,has_more:false,next_before_revision:null,rows:[]}));return;}
   if(mode==='preview'||mode==='gaps'){
    const result={evaluated_at:new Date().toISOString(),timezone:'Asia/Riyadh',request_id:url.searchParams.get('request'),request_revision:1,schedule_revision:0,
     capacity:'CLEAR',eligible:true,binding:false,confirmation_available:false,factory_id:id(1),context_hash:'a'.repeat(64),configuration_hash:'b'.repeat(32),duration_minutes:30,
     start:url.searchParams.get('start'),end:url.searchParams.get('end')||time(2),slack_minutes:0,scope:{kind:'WHOLE_LINE',machine_id:id(3),line_id:id(4)},
     physical_readiness:'READY_NOW',occupancy_complete:true,conditions:{configuration_or_routing_unknown:false,open_transfer:false,duration_unknown:false},conflicts:[],conflicts_complete:true};
    if(mode==='gaps')Object.assign(result,{search_start:url.searchParams.get('start'),search_end:url.searchParams.get('end'),suggestions:[{start:time(4),end:time(4.5),gap_end:time(5)}],has_more:false,next_after_start:null,blocker_count:0,suggestions_complete:true,blockers:[],blockers_complete:true});
    res.end(JSON.stringify(result));return;
   }
   res.end(JSON.stringify(board));return;
  }
  if(url.pathname==='/api/fulfillment'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({rows:[]}));return;}
  if(url.pathname==='/styles.css'){res.setHeader('Content-Type','text/css');res.end(await readFile('src/app/globals.css'));return;}
  if(url.pathname==='/fixture.js'){res.setHeader('Content-Type','text/javascript');res.end(await readFile(join(output,'fixture.js')));return;}
  if(url.pathname.startsWith('/api/')){res.writeHead(404,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'dataWarning'}));return;}
  res.setHeader('Content-Type','text/html');res.end(html);
 }catch{res.writeHead(500);res.end();}
});
server.listen(4205,'127.0.0.1',()=>console.log('Isolated Maintenance fixture: http://127.0.0.1:4205'));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
