import {confirmReceipt,readIntent,retainIntent} from '@/utils/production-recording-intent.mjs';
export type CompletionTarget={item:string;actual_start:string};
export type RecordingIntent={version:number;actor:string;factory:string;request:string;body:string;created_at:string;last_checked_at:string|null;phase:string;completion?:CompletionTarget};
export type RecordingReceipt={contract_version:number;outcome:string;request_id:string;entry_id:string;recorded_at:string;original_payload:Record<string,unknown>;needs_review?:boolean;weight_missing?:boolean;standard_missing?:boolean};
export type RecordingResult={kind:'COMMITTED';receipt:RecordingReceipt;current?:Record<string,unknown>}|{kind:'REJECTED';error:string;reason?:string}|{kind:'UNKNOWN';error:string};
const knownErrors=new Set(['recordingContextChanged','recordingRequestConflict','recordingValidation','recordingUnavailable','permissionError','unauthorized','prv3Expired','prv3LateDisabled','outputPaused','outputEnrollmentRequired','outputCarryoverUnsupported','compActiveRequired']);
const errorKey=(body:Record<string,unknown>)=>typeof body.error==='string'&&knownErrors.has(body.error)?body.error:'dataWarning';
export async function postRecording(intent:RecordingIntent,fetcher:typeof fetch=fetch):Promise<RecordingResult>{
 try{
  const output=JSON.parse(intent.body).command==='record_manufactured_output';
  const response=await fetcher(output?'/api/manufactured-output':'/api/data',{method:'POST',credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(20000),headers:{'Content-Type':'application/json','X-Factory-Recording':'3'},body:intent.body});
  const body=await response.json();
  if(response.ok&&confirmReceipt(body.data,intent))return {kind:'COMMITTED',receipt:body.data};
  // A collision must never discard the original intent. Auth failure cannot
  // prove whether an earlier attempted request committed before access changed.
  if(!response.ok&&body.outcome==='REJECTED'&&body.error!=='recordingRequestConflict')return {kind:'REJECTED',error:errorKey(body),reason:typeof body.reason==='string'?body.reason:undefined};
  return {kind:'UNKNOWN',error:errorKey(body)};
 }catch{return {kind:'UNKNOWN',error:'dataWarning'}}
}
export async function recoverRecording(intent:RecordingIntent,storage:Storage,fetcher:typeof fetch=fetch):Promise<RecordingResult>{
 try{
  if(readIntent(storage,intent.actor,intent.factory)?.request!==intent.request)throw Error('prv3StorageUnavailable');
  retainIntent(storage,{...intent,last_checked_at:new Date().toISOString()});
  const output=JSON.parse(intent.body).command==='record_manufactured_output';
  const url=output?'/api/manufactured-output?'+new URLSearchParams({factory:intent.factory,mode:'status',target:intent.request}):'/api/production-recording-status?'+new URLSearchParams({factory:intent.factory,request_id:intent.request});
  const response=await fetcher(url,{credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(20000)});
  const body=await response.json();
  if(response.ok&&body.outcome==='COMMITTED'&&confirmReceipt(body.receipt,intent))return {kind:'COMMITTED',receipt:body.receipt,current:body.current};
  return {kind:'UNKNOWN',error:response.ok?'prv3Unconfirmed':errorKey(body)};
 }catch(error){if(error instanceof Error&&error.message==='prv3StorageUnavailable')throw error;return {kind:'UNKNOWN',error:'dataWarning'}}
}
