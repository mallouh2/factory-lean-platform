import {recordingNumber} from './production-recording-intent.mjs';
import {correctionCommand} from './production-corrections.mjs';
import {decimalSubtract} from './quality-quantities.mjs';

export const correctionReasonSuggestions=['pcReasonEntry','pcReasonMeasurement','pcReasonGood','pcReasonScrap','pcReasonDuplicate','pcReasonOther'];
export function correctionDraft(entry){
 return {good:entry.good,scrap_kg:entry.scrap_kg??'',discarded_quantity:entry.discarded_quantity??'0',
  startup_kg:entry.startup_kg??'0',unfinished:entry.unfinished??'0',remaining_work:entry.remaining_work??'',reason:''};
}
export function correctionPayload(entry,draft,allocations=[],confirmed=false){
 const revision=Number(entry.correction_revision);
 if(!Number.isSafeInteger(revision)||revision<0)throw Error('pcStale');
 const payload={entry:entry.id,expected_revision:revision,reason:draft.reason.trim(),allocations,confirm_overproduction:confirmed};
 for(const key of ['good','scrap_kg','discarded_quantity','startup_kg','unfinished'])payload[key]=recordingNumber(draft[key]);
 payload.remaining_work=draft.remaining_work.trim();
 return payload;
}
export const correctionDifference=(proposed,current)=>decimalSubtract(proposed,current);
export const correctionStorageKey=(actor,factory)=>`factory-lean:correction:v1:${actor}:${factory}`;
export function correctionIntent(actor,factory,operation,payload,id){
 const body=correctionCommand({factory,operation,payload,request_id:id});
 return {actor,factory,body};
}
export function readCorrectionIntent(storage,actor,factory){
 const text=storage.getItem(correctionStorageKey(actor,factory));if(!text)return null;
 const intent=JSON.parse(text);
 if(intent.actor!==actor||intent.factory!==factory)throw Error('pcStorageError');
 correctionCommand(intent.body);return intent;
}
export async function postCorrection(intent,fetcher=fetch){
 try{
  const response=await fetcher('/api/production-corrections',{method:'POST',credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(20000),headers:{'Content-Type':'application/json'},body:JSON.stringify(intent.body)});
  const result=await response.json();
  if(!response.ok)return {error:result.error||'dataWarning',unknown:response.status>=500,conflict:response.status===409};
  if(!result?.id||!['PENDING','APPROVED','REJECTED'].includes(result.status))return {error:'dataWarning',unknown:true};
  return {receipt:result};
 }catch{return {error:'dataWarning',unknown:true};}
}
