// Exact client intent/recovery only. SQL remains posting and admission truth.
import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';
import {validCompletion} from './production-completion.mjs';
const quantities=new Set(['good','scrap_kg','discarded_quantity','unfinished','input_quantity','startup_kg']);
const uuid=v=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export function recordingNumber(value){
 const text=String(value??'').trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace('٫','.');
 const result=decimalSubtract(text,'0');
 if(result===null||decimalCompare(result,'0')===-1)throw Error('prv3InvalidQuantity');
 return result;
}
export function recordingBody(factory,request,payload){
 if(!uuid(factory)||!uuid(request)||!payload||typeof payload!=='object')throw Error('prv3InvalidQuantity');
 const fields=Object.entries(payload).map(([key,value])=>JSON.stringify(key)+':'+(quantities.has(key)?recordingNumber(value):JSON.stringify(value)));
 const command=Object.hasOwn(payload,'output_groups')?'record_manufactured_output':'record_lean_production';
 const body=`{"command":${JSON.stringify(command)},"args":{"factory":${JSON.stringify(factory)},"request_id":${JSON.stringify(request)},"payload":{${fields.join(',')}}}}`;
 if(body.length>95000)throw Error('prv3StorageUnavailable');
 return body;
}
export const recordingScope=(actor,factory)=>{
 if(!uuid(actor)||!uuid(factory))throw Error('permissionError');
 return `factory-lean:recording:v3:${actor.toLowerCase()}:${factory.toLowerCase()}`;
};
function storageError(){return Error('prv3StorageUnavailable')}
export function readIntent(storage,actor,factory){
 try{
  const value=storage.getItem(recordingScope(actor,factory));if(!value)return null;
  if(value.length>110000)throw storageError();const intent=JSON.parse(value);
  if(intent.version!==1||intent.actor!==actor||intent.factory!==factory||!uuid(intent.request)||typeof intent.body!=='string'||!Number.isFinite(Date.parse(intent.created_at)))throw storageError();
  const args=JSON.parse(intent.body).args;
  if(args.factory!==factory||args.request_id!==intent.request)throw storageError();
  if(intent.completion!==undefined&&!validCompletion(intent.completion,args.payload?.item))throw storageError();
  return intent;
 }catch{throw storageError()}
}
export function retainIntent(storage,intent){
 try{const key=recordingScope(intent.actor,intent.factory),raw=JSON.stringify(intent);storage.setItem(key,raw);if(storage.getItem(key)!==raw)throw storageError();return intent}catch{throw storageError()}
}
/** @param {{request?:string,now?:string,completion?:{item:string,actual_start:string}}} [options] */
export function prepareIntent(storage,actor,factory,payload,options={}){
 const {request=crypto.randomUUID(),now=new Date().toISOString(),completion}=options;
 if(completion!==undefined&&!validCompletion(completion,payload?.item))throw storageError();
 const previous=readIntent(storage,actor,factory);
 if(previous){if(recordingBody(factory,previous.request,payload)!==previous.body||JSON.stringify(previous.completion)!==JSON.stringify(completion))throw Error('prv3Unresolved');return previous}
 return retainIntent(storage,{version:1,actor,factory,request,body:recordingBody(factory,request,payload),created_at:now,last_checked_at:null,phase:'UNCONFIRMED',...(completion?{completion}:{})});
}
export function confirmReceipt(receipt,intent){
 return !!receipt&&receipt.contract_version===3&&receipt.outcome==='COMMITTED'&&receipt.request_id===intent.request&&uuid(receipt.entry_id);
}
// Only confirmed outcomes are acknowledged. Unknown attempted intents never expire.
export function acknowledgeIntent(storage,intent,receipt,now=Date.now()){
 const key=recordingScope(intent.actor,intent.factory),current=readIntent(storage,intent.actor,intent.factory);
 if(current?.request!==intent.request)throw storageError();
 if(receipt&&!confirmReceipt(receipt,intent))throw storageError();
 try{
  const tombstoneKey=key+':receipts';let rows=[];
  try{rows=JSON.parse(storage.getItem(tombstoneKey)||'[]')}catch{rows=[]}
  rows=Array.isArray(rows)?rows.filter(r=>Number.isFinite(r.at)&&now-r.at<30*86400000):[];
  if(receipt)rows=[{request:intent.request,entry:receipt.entry_id,at:now},...rows.filter(r=>r.request!==intent.request)].slice(0,100);
  storage.setItem(tombstoneKey,JSON.stringify(rows));storage.removeItem(key);
  if(storage.getItem(key)!==null)throw storageError();
 }catch{throw storageError()}
}
export function canRecordWork(envelope,row){
 if(envelope?.available!==true||envelope?.can_edit!==true||row?.can_record!==true)return false;
 return row.status==='active'&&row.active_recording_eligible===true || row.status==='completed'&&row.policy_late_eligible===true&&
  (row.same_shift_recording_available===true || envelope.late_recording_available===true&&row.late_recording_available===true);
}
export function sameMeasurement(entry,item,good,scrap,now=Date.now()){
 return entry.item_id===item&&Number.isFinite(Date.parse(entry.recorded_at))&&now-Date.parse(entry.recorded_at)>=0&&now-Date.parse(entry.recorded_at)<30*60000&&decimalCompare(entry.good,good)===0&&decimalCompare(entry.scrap_kg,scrap)===0;
}
