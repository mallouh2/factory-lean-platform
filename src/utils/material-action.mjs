import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';

// UI suggestions use the command reader's current bounds. SQL rechecks on submit.
export function materialActionLimit(row,operation,source=''){
 const bound=row.eligible?.[operation];
 if(bound==null||decimalCompare(bound,'0')===null||decimalCompare(bound,'0')===-1)return null;
 const choices=['ISSUE','RELEASE'].includes(operation)?row.reservations:row.custody;
 const pick=row.product&&source?choices?.find(x=>x.source_id===source):null;
 return decimalSubtract(pick&&decimalCompare(pick.quantity,bound)===-1?pick.quantity:bound,'0');
}
export function materialDefaultOperation(row,audience){
 if(audience!=='WAREHOUSE')return '';
 if(decimalCompare(row.issued,row.quantity)>=0)return '';
 if(decimalCompare(row.eligible?.ISSUE,'0')===1)return 'ISSUE';
 if(decimalCompare(row.eligible?.RESERVE,'0')===1)return 'RESERVE';
 return 'RESERVE';
}
export function materialAmountValid(value,limit){
 return limit!==null&&decimalCompare(value,'0')===1&&decimalCompare(value,limit)!==null&&decimalCompare(value,limit)<=0;
}
