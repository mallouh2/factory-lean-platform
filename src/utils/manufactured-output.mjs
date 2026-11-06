import {recordingNumber} from './production-recording-intent.mjs';
import {decimalSubtract,decimalCompare} from './quality-quantities.mjs';
export const outputTotal=groups=>groups.reduce((sum,g)=>decimalSubtract(sum,'-'+recordingNumber(g.quantity)),'0');
/** @param {{lot_id:string,input_quantity:string|number,discarded_quantity:string|number,scrap_kg:string|number}|null} [recovery] */
export function outputGroups(good,unfinished,operations,unit,finishedId,recovery=null){
 const groups=[];good=recordingNumber(good);
 if(good!=='0')groups.push({id:finishedId,quantity:good,missing_operations:[]});
 for(const g of unfinished){
  const quantity=recordingNumber(g.quantity),ids=[...g.missing_operations].sort();
  if(quantity==='0'||!ids.length||new Set(ids).size!==ids.length||ids.some(id=>!operations.some(o=>o.id===id)))throw Error('prv3WipRequired');
  groups.push({id:g.id,quantity,missing_operations:ids});
 }
 if(unit==='piece'&&groups.some(g=>g.quantity.includes('.')))throw Error('prv3InvalidQuantity');
 if(!groups.length){
  if(!recovery?.lot_id)throw Error('prv3EmptyQuantity');
  const input=recordingNumber(recovery.input_quantity),discarded=recordingNumber(recovery.discarded_quantity),kg=recordingNumber(recovery.scrap_kg);
  if(input==='0'||discarded!==input||(unit==='piece'&&input.includes('.')))throw Error('prv3InvalidQuantity');
  if(kg==='0')throw Error('prv3InvalidScrap');
 }
 return groups;
}
export function inspectionValid(groups,rejected,total,unit,operations){
 try{
  const ids=new Set();for(const g of groups){
   if(ids.has(g.id)||recordingNumber(g.quantity)==='0'||new Set(g.missing_operations).size!==g.missing_operations.length||g.missing_operations.some(id=>!operations.some(o=>o.id===id)))return false;
   ids.add(g.id);if(decimalCompare(recordingNumber(g.released),recordingNumber(g.quantity))===1)return false;
   if(unit==='piece'&&[g.quantity,g.released].some(q=>recordingNumber(q).includes('.')))return false;
  }
  if(unit==='piece'&&recordingNumber(rejected).includes('.'))return false;
  return decimalCompare(outputTotal([...groups,{quantity:rejected}]),total)===0;
 }catch{return false;}
}
