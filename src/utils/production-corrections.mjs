const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
const object=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
const decimal=x=>typeof x==='string'&&x.length<=2048&&/^\d+(?:\.\d+)?$/.test(x);
const invalid=()=>{throw {code:'22023'};};
const invalidResponse=()=>{throw {code:'CORRECTION_CONTRACT'};};
export function correctionCommand(body){
 if(!object(body)||Object.keys(body).some(k=>!['factory','operation','payload','request_id'].includes(k))||!uuid(body.factory)||!uuid(body.request_id)||!object(body.payload)||!['submit','approve','reject'].includes(body.operation))invalid();
 const p=body.payload;
 if(body.operation==='submit'){
  const fields=['entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work','corrected_occurrence_key','expected_revision','allocations'];
  if(Object.keys(p).some(k=>!fields.includes(k))||!uuid(p.entry)||!Number.isSafeInteger(p.expected_revision)||p.expected_revision<0||
   !['good','discarded_quantity','scrap_kg'].every(k=>decimal(p[k]))||!['startup_kg','unfinished'].every(k=>p[k]===undefined||decimal(p[k]))||
   typeof p.reason!=='string'||p.reason.trim().length<3||p.reason.length>2000||
   ['confirm_overproduction','change_shift'].some(k=>p[k]!==undefined&&typeof p[k]!=='boolean')||p.shift!==undefined&&p.shift!==null&&!uuid(p.shift)||
   p.remaining_work!==undefined&&(typeof p.remaining_work!=='string'||p.remaining_work.length>2000)||
   p.corrected_occurrence_key!==undefined&&!/^[0-9a-f]{64}$/.test(p.corrected_occurrence_key))invalid();
  if(p.allocations!==undefined&&(!Array.isArray(p.allocations)||p.allocations.length>100||p.allocations.some(a=>!object(a)||Object.keys(a).sort().join(',')!=='quantity,source_id'||a.source_id!==null&&!uuid(a.source_id)||!decimal(a.quantity)||!/[1-9]/.test(a.quantity))))invalid();
 }else if(Object.keys(p).some(k=>!['id',...(body.operation==='reject'?['reason']:[])].includes(k))||!uuid(p.id)||
  body.operation==='reject'&&(typeof p.reason!=='string'||p.reason.trim().length<3||p.reason.length>2000))invalid();
 return body;
}
export function correctionQuery(params){
 const fields=['factory','id','request_id','entry','status','page_size','cursor','mine'];
 if([...params.keys()].some(k=>!fields.includes(k)||params.getAll(k).length!==1)||!uuid(params.get('factory')))invalid();
 const factory=params.get('factory').toLowerCase(),query={page_size:50};
 if(params.has('mine')){if(params.get('mine')!=='1')invalid();query.mine=true;}
 for(const k of ['id','request_id','entry'])if(params.has(k)){if(!uuid(params.get(k)))invalid();query[k]=params.get(k).toLowerCase();}
 if(params.has('status')){if(!['PENDING','APPROVED','REJECTED'].includes(params.get('status')))invalid();query.status=params.get('status');}
 if(params.has('page_size')){if(!/^(?:[1-9]|[1-9]\d|100)$/.test(params.get('page_size')))invalid();query.page_size=Number(params.get('page_size'));}
 if(params.has('cursor')){
  const encoded=params.get('cursor');if(!encoded||encoded.length>4000||!/^[A-Za-z0-9_-]+$/.test(encoded))invalid();
  try{query.cursor=JSON.parse(Buffer.from(encoded,'base64url').toString('utf8'));}catch{invalid();}
  const c=query.cursor;
  if(!object(c)||Object.keys(c).sort().join(',')!=='actor,after_at,after_id,factory,query_hash,revision,version'||c.version!==1||c.factory!==factory||!uuid(c.actor)||!uuid(c.after_id)||
   typeof c.after_at!=='string'||!/(Z|[+-]\d\d:\d\d)$/.test(c.after_at)||!Number.isFinite(Date.parse(c.after_at))||!/^\d+:\d+:\d+$/.test(c.revision)||!/^[a-f0-9]{64}$/.test(c.query_hash))invalid();
 }
 return {factory,query};
}
function values(row){
 if(!object(row)||!uuid(row.entry_id)||!uuid(row.item_id)||!['meter','piece','kg',null].includes(row.unit))invalidResponse();
 for(const k of ['original_good','original_scrap_kg','original_wip','good','discarded_quantity','scrap_kg','startup_kg','unfinished','quality_rejected'])if(row[k]!==null&&!decimal(row[k]))invalidResponse();
 if(typeof row.correction_revision!=='string'||!/^\d+$/.test(row.correction_revision))invalidResponse();
}
function requestRow(row,read){
 if(!object(row)||!uuid(row.id)||!uuid(row.entry_id)||!uuid(row.requested_by)||!['PENDING','APPROVED','REJECTED'].includes(row.status)||![1,2].includes(row.revision))invalidResponse();
 values(row.original_values);
 if(row.original_values.entry_id!==row.entry_id||!object(row.proposed)||row.proposed.entry!==row.entry_id||typeof row.proposed.reason!=='string'||row.proposed.reason.trim().length<3)invalidResponse();
 for(const k of ['good','discarded_quantity','scrap_kg','startup_kg','unfinished'])if(!decimal(row.proposed[k]))invalidResponse();
 if(row.status==='APPROVED'){
  if(!uuid(row.correction_id)||!uuid(row.reviewed_by)||!row.reviewed_at)invalidResponse();values(row.applied_values);
 }else if(row.applied_values!==null||row.correction_id!==null)invalidResponse();
 if(row.status==='PENDING'&&(row.revision!==1||row.reviewed_by!==null||row.reviewed_at!==null))invalidResponse();
 if(row.status==='REJECTED'&&(!uuid(row.reviewed_by)||!row.reviewed_at||typeof row.rejection_reason!=='string'||row.rejection_reason.trim().length<3))invalidResponse();
 if(read){values(row.current_values);if(row.current_values.entry_id!==row.entry_id)invalidResponse();}
 return row;
}
export function correctionResponse(data,args,read=false){
 if(!object(data)||data.contract_version!==1)invalidResponse();
 if(!read)return requestRow(data,false);
 if(data.factory_id!==args.factory||!Array.isArray(data.rows)||!((typeof data.total==='number'&&Number.isSafeInteger(data.total))||(typeof data.total==='string'&&/^\d+$/.test(data.total)))||!Number.isSafeInteger(Number(data.total))||Number(data.total)<0||data.page_size!==args.query.page_size||data.rows.length>data.page_size||typeof data.complete!=='boolean'||data.complete!==(data.next_cursor===null))invalidResponse();
 const rows=data.rows.map(row=>{if(row.factory_id!==args.factory)invalidResponse();return requestRow(row,true);});
 return {...data,total:Number(data.total),rows,next_cursor:data.next_cursor===null?null:Buffer.from(JSON.stringify(data.next_cursor),'utf8').toString('base64url')};
}
export function correctionFailure(error,write=false){
 const code=error&&typeof error==='object'?error.code:null,message=error&&typeof error==='object'?error.message:null;
 const status=message==='unauthorized'?401:code==='42501'||message==='permission_denied'||message==='invalid_origin'?403:
  code==='40001'||message==='request_conflict'||typeof message==='string'&&(/^source_/.test(message)||message==='unfinished_already_consumed')?409:code==='P0002'?404:
  code==='22023'||code==='23514'||['quality_weight','unfinished_conservation','recording_correction_reason','lean_invalid','recording_overproduction_confirmation'].includes(message)?422:503;
 const key=status===401?'unauthorized':status===403?'permissionError':status===409?'correctionChanged':status===404?'noResults':status===422?'invalidCorrection':'dataWarning';
 return {status,body:{error:key,...(status===409?{refresh:true}:{}),...(write&&status===503?{outcome:'UNKNOWN',retry_same_request:true}:{})}};
}
