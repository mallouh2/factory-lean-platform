import {decimalCompare,decimalMultiply,decimalSubtract} from './quality-quantities.mjs';

export function materialSuggested(row,operation,limit){
 const value=row.suggested?.[operation];
 return value!=null&&limit!=null&&decimalCompare(value,'0')===1?(decimalCompare(value,limit)<=0?value:limit):'';
}
export function materialVariance(row,operation,quantity){
 if(!['RESERVE','ISSUE'].includes(operation)||!row.material||decimalCompare(quantity,'0')!==1)return null;
 let expected=decimalSubtract(row.quantity,decimalSubtract(row.issued,row.returned||'0'));
 if(operation==='RESERVE')expected=decimalSubtract(expected,row.reserved);
 if(decimalCompare(expected,'0')===-1)expected='0';
 const difference=decimalSubtract(quantity,expected),over=decimalCompare(difference,'0')===1;
 const magnitude=over?difference:decimalSubtract('0',difference),threshold=decimalMultiply(expected,decimalMultiply(row.deviation_percent||'0','0.01'));
 return{expected,difference,over,significant:decimalCompare(magnitude,threshold)===1,remaining:decimalCompare(quantity,expected)===-1?decimalSubtract(expected,quantity):'0'};
}
export function materialReconcileValid(quantity,limit){return decimalCompare(quantity,'0')!==null&&decimalCompare(quantity,'0')>=0&&decimalCompare(quantity,limit)!==null&&decimalCompare(quantity,limit)<=0;}
