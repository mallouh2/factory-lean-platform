import {decimalCompare} from './quality-quantities.mjs';
export const qualityColumns=[['shift','qvDateShift'],['order','qvOrder'],['product','product'],['line','qvLine'],['production','qvProduction'],['rejected','qvRejected'],['alert','qvAlert'],['accepted','qualityAccepted'],['recorded','qualityRecorded'],['current','qualityCorrected'],['source','sourceLabel'],['calculation','leanScrapRate']];
export const defaultQualityColumns=qualityColumns.slice(0,7).map(([key])=>key);
export function qualityVisibleColumns(value){
 const keys=Array.isArray(value)?qualityColumns.map(([k])=>k).filter(k=>value.includes(k)):[];
 return keys.length?keys:defaultQualityColumns;
}
export const qualityPreferenceKey=(actor,factory)=>actor&&factory?`factorylean:table:v2:quality:${encodeURIComponent(actor)}:${encodeURIComponent(factory)}`:null;
export function shiftProduction(row){
 const q=row?.shift_quantity;
 return q?.complete===true&&q.basis==='EFFECTIVE_GOOD'&&decimalCompare(q.quantity,'0')!==null?String(q.quantity):null;
}
export const rejectionExceeded=(quantity,eligible)=>decimalCompare(quantity,eligible)===1;
