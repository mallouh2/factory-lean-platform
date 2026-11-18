const object=x=>x&&typeof x==='object'&&!Array.isArray(x);
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(x);
export function productionDelayState(row,now=Date.now()){
 const finish=Date.parse(row?.planned_finish||''),live=row?.status==='active'&&!row.actual_finish;
 const delayed=live&&Number.isFinite(finish)&&now>finish,seconds=delayed?Math.floor((now-finish)/1000):0;
 const boundaries=[60000-now%60000];if(Number.isFinite(finish)){if(finish>=now)boundaries.push(finish-now+1);const due=finish+Number(row?.grace_minutes)*60000;if(due>now)boundaries.push(due-now);}
 return {delayed,seconds,pending:delayed&&now>=finish+row.grace_minutes*60000&&!row.last,
  unknown:live&&!Number.isFinite(finish),estimateExpired:!!row?.last?.estimated_finish&&Date.parse(row.last.estimated_finish)<=now,
  nextTick:Math.max(1,Math.min(...boundaries))};
}
export function affectedPlannedWork(row,orders,now=Date.now()){
 return orders.filter(o=>o.id!==row.item&&o.status==='planned'&&o.line_id===row.actual_line&&
  Number.isFinite(Date.parse(o.start_time))&&Date.parse(o.expected_finish)>now)
  .sort((a,b)=>Date.parse(a.start_time)-Date.parse(b.start_time)||String(a.id).localeCompare(String(b.id)));
}
export function validDelayCommand(a){
 if(!object(a)||Object.keys(a).some(k=>!['factory','operation','payload','request_id'].includes(k))||!uuid(a.factory)||!uuid(a.request_id)||!object(a.payload)||JSON.stringify(a).length>10000)return false;
 const p=a.payload;
 if(a.operation==='POLICY')return Object.keys(p).length===1&&Number.isInteger(p.grace_minutes)&&p.grace_minutes>=0&&p.grace_minutes<=2147483647;
 return a.operation==='REASON'&&Object.keys(p).length===4&&Object.keys(p).every(k=>['item','reason','estimated_finish','fingerprint'].includes(k))&&uuid(p.item)&&typeof p.reason==='string'&&p.reason.trim().length>=3&&p.reason.length<=500&&/^[a-f0-9]{64}$/.test(p.fingerprint)&&
  (p.estimated_finish===null||typeof p.estimated_finish==='string'&&/T.*(Z|[+-]\d\d:\d\d)$/.test(p.estimated_finish)&&Number.isFinite(Date.parse(p.estimated_finish)));
}
const canonical=x=>JSON.stringify(x,(_k,v)=>object(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
export async function delayOutcome(intent,fetcher=fetch){
 try{const r=await fetcher('/api/production-delay?'+new URLSearchParams({factory:intent.factory,request_id:intent.request_id}),{cache:'no-store'}),b=await r.json();
  if(r.ok&&b.receipt?.request_id===intent.request_id&&uuid(b.receipt.id)&&canonical(b.receipt.intent)===canonical({operation:intent.operation,payload:intent.payload}))return {outcome:'COMMITTED',id:b.receipt.id};
 }catch{/* Preserve the exact intent until its outcome is known. */}
 return {outcome:'UNKNOWN',error:'f46OutcomeUnknown'};
}
export async function submitDelay(intent,fetcher=fetch){
 try{const r=await fetcher('/api/production-delay',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(intent),signal:AbortSignal.timeout(25000)}),b=await r.json();
  if(r.ok&&uuid(b.id))return {outcome:'COMMITTED',id:b.id};
  if(r.status>=400&&r.status<500&&typeof b.error==='string')return {outcome:'REJECTED',error:b.error};
 }catch{/* RPC/HTTP transport failure is ambiguous, not a safe fresh retry. */}
 return delayOutcome(intent,fetcher);
}
