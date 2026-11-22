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
export function inspectionDraft(total,rejected,unfinished,unit,operations,finishedId,existingFinished=[],unfinishedTarget){
 /** @type {{total?:string,rejected?:string,unfinished?:string,finished?:string|null}} */
 let quantities={};
 try{
  total=recordingNumber(total);rejected=recordingNumber(rejected);
  const unfinishedQuantity=recordingNumber(unfinishedTarget??outputTotal(unfinished));
  quantities={total,rejected,unfinished:unfinishedQuantity};
  if(unit==='piece'&&[total,rejected,unfinishedQuantity].some(q=>q.includes('.')))return {...quantities,error:'whole'};
  const finished=decimalSubtract(decimalSubtract(total,rejected),unfinishedQuantity);
  if(decimalCompare(finished,'0')<0)return {...quantities,error:'excess'};
  quantities={...quantities,finished};
  // The amount is visible while the inspector completes the group details.
  // Only a fully validated allocation supplies groups to the save command.
  if(outputTotal(unfinished)!==unfinishedQuantity)return {...quantities,error:'groupTotal'};
  for(const g of unfinished){
   if(recordingNumber(g.quantity)==='0')return {...quantities,error:'quantity'};
   if(!g.missing_operations.length)return {...quantities,error:'operations'};
  }
  // Separate received/allocated group identities cannot be redistributed by a
  // form calculation. Keep them intact or require the existing reconciliation.
  if(existingFinished.length>1&&decimalCompare(finished,outputTotal(existingFinished))!==0)return {...quantities,error:'group_scope'};
  const groups=[...unfinished.map(g=>({...g,quantity:recordingNumber(g.quantity),released:recordingNumber(g.quantity)})),
   ...(existingFinished.length>1?existingFinished.map(g=>({...g,released:g.quantity})):finished==='0'?[]:[{id:finishedId,quantity:finished,released:finished,missing_operations:[]}])];
  if(!inspectionValid(groups,rejected,total,unit,operations))return {...quantities,error:'quantity'};
  return {...quantities,groups,error:null};
 }catch{return {...quantities,error:'quantity'};}
}
