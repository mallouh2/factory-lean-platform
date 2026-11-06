import {useEffect,useRef,useState} from 'react';
import {correctionIntent,correctionStorageKey,postCorrection,readCorrectionIntent} from '@/utils/production-correction-ui.mjs';

export type CorrectionValues={entry_id:string;item_id:string;request_id:string;product_id:string;unit:string;good:string;scrap_kg:string|null;unfinished:string;correction_revision:string};
export type CorrectionRequest={id:string;entry_id:string;submission_id:string;factory_id:string;requested_by:string;requested_at:string;status:'PENDING'|'APPROVED'|'REJECTED';
 proposed:Record<string,string>;original_values:CorrectionValues;current_values:CorrectionValues;applied_values:CorrectionValues|null;reviewed_at:string|null;rejection_reason:string|null;allocations:{source_id:string|null;quantity:string}[]};
type Intent={actor:string;factory:string;body:{factory:string;request_id:string;operation:string;payload:Record<string,unknown>}};
export function useCorrectionAction(actor:string,factory:string,onReceipt:(row:CorrectionRequest)=>void){
 const [pending,setPending]=useState<Intent|null>(null),[ready,setReady]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const locked=useRef(false),hydrated=useRef(''),live=useRef({actor,factory,onReceipt});live.current={actor,factory,onReceipt};
 useEffect(()=>{hydrated.current='';setReady(false);setPending(null);setError('');try{setPending(readCorrectionIntent(sessionStorage,actor,factory));hydrated.current=actor+'|'+factory;setReady(true);}catch{setError('pcStorageError');}},[actor,factory]);
 function clear(){sessionStorage.removeItem(correctionStorageKey(actor,factory));setPending(null);}
 async function finish(intent:Intent,result:Awaited<ReturnType<typeof postCorrection>>){
  if(live.current.actor!==intent.actor||live.current.factory!==intent.factory)return;
  if(result.receipt){clear();live.current.onReceipt(result.receipt as CorrectionRequest);}
  else{setError(result.conflict?'pcStale':result.error||'dataWarning');if(!result.unknown)clear();}
 }
 async function run(operation:string,payload:Record<string,unknown>){
  if(locked.current||!ready||hydrated.current!==actor+'|'+factory)return;
  locked.current=true;setBusy(true);setError('');
  try{
   // An uncertain command must be recovered/retried, never replaced by a new intent.
   const intent=pending||correctionIntent(actor,factory,operation,payload,crypto.randomUUID());
   sessionStorage.setItem(correctionStorageKey(actor,factory),JSON.stringify(intent));setPending(intent);
   await finish(intent,await postCorrection(intent));
  }catch{setError('pcStorageError');}
  finally{locked.current=false;setBusy(false);}
 }
 async function recover(){
  if(!pending||locked.current||pending.actor!==actor||pending.factory!==factory)return;locked.current=true;setBusy(true);setError('');
  try{
   const query=new URLSearchParams({factory,...(pending.body.operation==='submit'?{request_id:pending.body.request_id}:{id:String(pending.body.payload.id)})});
   const response=await fetch('/api/production-corrections?'+query,{cache:'no-store'}),body=await response.json();
   if(!response.ok)throw Error(body.error||'dataWarning');
   const row=body.rows?.[0];
   if(row&&(pending.body.operation==='submit'||row.status!=='PENDING'))await finish(pending,{receipt:row});
   else setError('pcUncertain');
  }catch(cause){setError(cause instanceof Error?cause.message:'dataWarning');}
  finally{locked.current=false;setBusy(false);}
 }
 return {pending,ready,busy,error,run,recover};
}
