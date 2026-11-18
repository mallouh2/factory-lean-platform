export type ExecutionIntent={factory:string;item:string;operation:string;reason:string;fingerprint:string;request_id:string;output_confirmed:boolean;source_machine?:string;alternative_machine?:string;transfer_id?:string};
export type ExecutionResult={outcome:'COMMITTED';data:any;current?:any}|{outcome:'REJECTED';error:string;materials?:any}|{outcome:'UNKNOWN';error:string;current?:any};
const key=(actor:string,factory:string,item:string)=>`factory-execution-v1:${actor}:${factory}:${item}`;
export function pendingExecution(storage:Storage,actor:string,factory:string,item:string):ExecutionIntent|null{
 const raw=storage.getItem(key(actor,factory,item));if(!raw)return null;const i=JSON.parse(raw);
 if(i.factory!==factory||i.item!==item||!['START_SELECTED','RESUME','INTERRUPT','TRANSFER_LINE','RETURN_PRODUCTION'].includes(i.operation)||typeof i.reason!=='string'||typeof i.fingerprint!=='string'||typeof i.output_confirmed!=='boolean'||typeof i.request_id!=='string'||['TRANSFER_LINE','RETURN_PRODUCTION'].includes(i.operation)&&(!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(i.source_machine||'')||!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(i.alternative_machine||''))||i.operation==='RETURN_PRODUCTION'&&!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(i.transfer_id||''))throw Error('executionPendingStorage');return i;
}
export function retainExecution(storage:Storage,actor:string,i:ExecutionIntent){const k=key(actor,i.factory,i.item),prior=pendingExecution(storage,actor,i.factory,i.item);if(prior&&JSON.stringify(prior)!==JSON.stringify(i))throw Error('executionPendingConflict');storage.setItem(k,JSON.stringify(i));if(storage.getItem(k)!==JSON.stringify(i))throw Error('executionPendingStorage');}
export function clearExecution(storage:Storage,actor:string,i:ExecutionIntent){if(pendingExecution(storage,actor,i.factory,i.item)?.request_id!==i.request_id)throw Error('executionPendingConflict');storage.removeItem(key(actor,i.factory,i.item));}
const matches=(d:any,i:ExecutionIntent)=>{if(d?.factory!==i.factory||d?.item!==i.item||typeof d.fingerprint!=='string'||d.order?.id!==i.item)return false;if(i.operation==='RETURN_PRODUCTION')return d.return_transfer?.request_id===i.request_id&&d.return_transfer?.transfer_id===i.transfer_id&&d.return_transfer?.source_machine===i.source_machine&&d.return_transfer?.alternative_machine===i.alternative_machine;if(i.operation!=='TRANSFER_LINE')return true;const move=d.line_transfers?.find((m:any)=>m.request_id===i.request_id);return move?.source_machine===i.source_machine&&move?.alternative_machine===i.alternative_machine&&d.order.actual_line_id===move.destination_line;};
export async function executionOutcome(i:ExecutionIntent,fetcher:typeof fetch=fetch):Promise<ExecutionResult>{
 try{const r=await fetcher('/api/production-execution?'+new URLSearchParams({factory:i.factory,item:i.item,mode:'outcome',request_id:i.request_id}),{cache:'no-store',credentials:'same-origin',signal:AbortSignal.timeout(20000)}),b=await r.json();
  if(b.request_id!==i.request_id)return {outcome:'UNKNOWN',error:b.error||'executionOutcomeUnknown'};
  const expected={item:i.item,operation:i.operation,reason:i.reason,fingerprint:i.fingerprint,output_confirmed:i.output_confirmed,...(['TRANSFER_LINE','RETURN_PRODUCTION'].includes(i.operation)?{source_machine:i.source_machine,alternative_machine:i.alternative_machine}:{}),...(i.operation==='RETURN_PRODUCTION'?{transfer_id:i.transfer_id}:{})};
  const sameIntent=JSON.stringify(Object.keys(expected).sort().map(k=>[k,expected[k as keyof typeof expected]]))===JSON.stringify(Object.keys(expected).sort().map(k=>[k,b.intent?.[k]]));
  if(b.outcome==='REJECTED'&&!r.ok&&sameIntent)return {outcome:'REJECTED',error:b.error||'executionRejected',materials:b.materials};
  if(!r.ok)return {outcome:'UNKNOWN',error:b.error||'executionOutcomeUnknown'};
  if(b.outcome==='COMMITTED'&&matches(b.data,i)&&sameIntent)return {outcome:'COMMITTED',data:b.data,current:b.current};
  return {outcome:'UNKNOWN',error:'executionOutcomeUnknown',current:matches(b.current,i)?b.current:undefined};
 }catch{return {outcome:'UNKNOWN',error:'executionOutcomeUnknown'};}
}
export async function submitExecution(i:ExecutionIntent,fetcher:typeof fetch=fetch):Promise<ExecutionResult>{
 try{const r=await fetcher('/api/production-execution',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},cache:'no-store',body:JSON.stringify(i),signal:AbortSignal.timeout(30000)}),b=await r.json();
  if(b.request_id===i.request_id&&b.outcome==='COMMITTED'&&r.ok&&matches(b.data,i))return {outcome:'COMMITTED',data:b.data};
  if(b.request_id===i.request_id&&b.outcome==='REJECTED'&&!r.ok)return {outcome:'REJECTED',error:b.error||'executionRejected',materials:b.materials};
 }catch{/* Reconcile an ambiguous response before allowing any retry. */}
 return executionOutcome(i,fetcher);
}
