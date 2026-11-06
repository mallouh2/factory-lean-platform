import {recordingNumber} from './production-recording-intent.mjs';
import {decimalCompare} from './quality-quantities.mjs';
export function receiptQuantity(value,remaining,unit){
 const q=recordingNumber(value);
 if(q==='0'||decimalCompare(q,remaining)===1||(unit==='piece'&&q.includes('.')))throw Error('output_receipt_quantity');
 return q;
}
export function initialReceiptGroup(groups){
 const eligible=groups.filter(g=>decimalCompare(g.remaining,'0')===1);
 return eligible.find(g=>!g.missing_operations.length)||eligible[0]||groups[0];
}
