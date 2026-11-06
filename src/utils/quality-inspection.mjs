import {recordingNumber} from './production-recording-intent.mjs';
import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';
import {outputTotal,inspectionValid} from './manufactured-output.mjs';

export function qualityRejected(total,accepted,unfinished,unit){
 try{total=recordingNumber(total);accepted=recordingNumber(accepted);for(const g of unfinished)recordingNumber(g.quantity);
  const value=decimalSubtract(decimalSubtract(total,accepted),outputTotal(unfinished));
  return decimalCompare(value,'0')<0||unit==='piece'&&[total,accepted,...unfinished.map(g=>recordingNumber(g.quantity))].some(v=>v.includes('.'))?null:value;
 }catch{return null;}
}

// One recording and one unit. Finished output is a result, never another input.
export function inspectionDraft(total,rejected,unfinished,unit,operations,finishedId,existingFinished=[]){
 try{
  total=recordingNumber(total);rejected=recordingNumber(rejected);
  if(unit==='piece'&&[total,rejected].some(q=>q.includes('.')))return {error:'whole'};
  for(const g of unfinished){
   if(recordingNumber(g.quantity)==='0')return {error:'quantity'};
   if(!g.missing_operations.length)return {error:'operations'};
  }
  const finished=decimalSubtract(decimalSubtract(total,rejected),outputTotal(unfinished));
  if(decimalCompare(finished,'0')<0)return {error:'excess'};
  // Separate received/allocated group identities cannot be redistributed by a
  // form calculation. Keep them intact or require the existing reconciliation.
  if(existingFinished.length>1&&decimalCompare(finished,outputTotal(existingFinished))!==0)return {error:'group_scope'};
  const groups=[...unfinished.map(g=>({...g,quantity:recordingNumber(g.quantity),released:recordingNumber(g.quantity)})),
   ...(existingFinished.length>1?existingFinished.map(g=>({...g,released:g.quantity})):finished==='0'?[]:[{id:finishedId,quantity:finished,released:finished,missing_operations:[]}])];
  if(!inspectionValid(groups,rejected,total,unit,operations))return {error:'quantity'};
  return {total,rejected,finished,groups,error:null};
 }catch{return {error:'quantity'};}
}
