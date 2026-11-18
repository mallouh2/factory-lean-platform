const uuid=value=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value||'');
const stamp=value=>typeof value==='string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d{1,6})?)?(Z|[+-]\d\d:\d\d)$/.test(value) && Number.isFinite(Date.parse(value));
export function operationalBoardArgs(params) {
 const allowed=['factory','view','start','end','line','machine','domain','after_kind','after_id','context_hash','evaluated_at'];
 if(params.get('view')!=='operational'||[...params.keys()].some(k=>!allowed.includes(k)||params.getAll(k).length!==1))throw {code:'22023'};
 const f=params.get('factory'),a=params.get('start'),b=params.get('end'),l=params.get('line'),w=params.get('machine'),domain=params.get('domain')||'all';
 if(!uuid(f)||!stamp(a)||!stamp(b)||Date.parse(b)<=Date.parse(a)||Date.parse(b)-Date.parse(a)>31*86400000||l&&!uuid(l)||w&&!uuid(w)||!['all','maintenance','production_plan'].includes(domain))throw {code:'22023'};
 const kind=params.get('after_kind'),id=params.get('after_id'),hash=params.get('context_hash'),at=params.get('evaluated_at');
 if([kind,id,hash,at].some(Boolean)&&(!['PRODUCTION','MAINTENANCE','REQUEST'].includes(kind)||!uuid(id)||!/^[a-f0-9]{64}$/.test(hash||'')||!stamp(at)))throw {code:'22023'};
 return {factory:f,range_start:a,range_end:b,line_id:l,machine:w,domain,page_size:100,after_kind:kind,after_id:id,expected_hash:hash,evaluated_at:at};
}
const ms=value=>value===null?null:Date.parse(value);
function assemble(page,records,complete) {
 const requests=new Map(),productionRequests=new Map(),orders=[],schedules=[],reservations=[];
 for(const row of records){const p=row.payload;
  if(row.kind==='PRODUCTION'){
   orders.push({...p.order,...p.occupancy?{operational_occupancy:p.occupancy}:{}});
   productionRequests.set(p.request.id,p.request);
  }else{
   requests.set(p.request.id,p.request);
   if(p.schedule){schedules.push(p.schedule);const o=p.schedule.occupancy;
    if(o.reserved)reservations.push({...o,start:ms(o.start)??-Infinity,finish:ms(o.finish)??Infinity});
   }
  }
 }
 return {active:page.active===true,requests:[...requests.values()],production_requests:[...productionRequests.values()],orders,schedules,reservations,
  read_at:page.evaluated_at,valid_until:page.valid_until,preview_available:page.preview_available===true,history_available:page.history_available===true,
  completeness:/** @type {'COMPLETE'|'INCOMPLETE'} */ (complete&&page.scope_complete?'COMPLETE':'INCOMPLETE'),reason:complete&&page.scope_complete?null:complete?page.reason:'PAGES_PENDING',total:page.total,loaded:records.length};
}
/** Pages are bounded and identity/revision-bound. Partial records are display-only. */
export async function collectOperationalBoard(read,scope,onPartial=(_partial)=>{},now=()=>Date.now()) {
 const records=[],keys=new Set();let first,lastKey='';
 for(let page=0;page<=100;page++){
  const data=await read(first?{after_kind:first.next.kind,after_id:first.next.id,expected_hash:first.context_hash,evaluated_at:first.evaluated_at}:{});
  if(!data||data.factory!==scope.factory||Date.parse(data.start)!==Date.parse(scope.range_start)||Date.parse(data.end)!==Date.parse(scope.range_end)||
   data.domain!==scope.domain||(data.line||null)!==(scope.line_id||null)||(data.machine||null)!==(scope.machine||null)||
   !Array.isArray(data.rows)||data.rows.length>100||!['COMPLETE','INCOMPLETE'].includes(data.completeness)||!stamp(data.evaluated_at)||!stamp(data.valid_until)||
   now()>=Date.parse(data.valid_until)||!/^[a-f0-9]{64}$/.test(data.context_hash||''))throw Error('mpBoardChanged');
  if(data.total===null&&!data.scope_complete&&!data.has_more&&data.rows.length===0)return assemble(data,[],true);
  if(!Number.isSafeInteger(data.total)||data.total<0||data.total>10000)throw Error('mpBoardIncomplete');
  if(first&&(data.context_hash!==first.context_hash||data.total!==first.total||data.evaluated_at!==first.evaluated_at||data.valid_until!==first.valid_until||data.scope_complete!==first.scope_complete))throw Error('mpBoardChanged');
  for(const row of data.rows){const key=row.kind+':'+row.id,p=row.payload;
   if(!['PRODUCTION','MAINTENANCE','REQUEST'].includes(row.kind)||!uuid(row.id)||keys.has(key)||key<=lastKey||!p||!p.request||p.request.factory_id!==scope.factory||
    (row.kind==='PRODUCTION'?p.order?.id!==row.id||p.order?.factory_id!==scope.factory:
      row.kind==='MAINTENANCE'?!p.schedule||p.schedule.id!==row.id||p.schedule.factory_id!==scope.factory||p.schedule.maintenance_request_id!==p.request.id:
        p.request.id!==row.id))throw Error('mpBoardIncomplete');
   if(row.uncertain&&data.scope_complete)throw Error('mpBoardIncomplete');
   if(p.schedule&&(!Array.isArray(p.schedule.actual_stops)||p.schedule.actual_stops.length>100||!Array.isArray(p.schedule.line_ids)||
     !p.schedule.occupancy||!stamp(p.schedule.occupancy.start)||p.schedule.occupancy.finish!==null&&!stamp(p.schedule.occupancy.finish)))throw Error('mpBoardIncomplete');
   keys.add(key);records.push(row);lastKey=key;
  }
  if(records.length>data.total||data.has_more&&(!data.next||data.rows.length!==100||data.next.id!==data.rows.at(-1)?.id||data.next.kind!==data.rows.at(-1)?.kind))throw Error('mpBoardIncomplete');
  if(data.completeness==='COMPLETE'&&data.rows.length!==data.total)throw Error('mpBoardIncomplete');
  if(!data.has_more){if(records.length!==data.total)throw Error('mpBoardIncomplete');return assemble(data,records,true);}
  onPartial(assemble(data,records,false));first=data;
 }
 throw Error('mpBoardIncomplete');
}
