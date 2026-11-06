import {decimalCompare,decimalSubtract,quantityValid} from './quality-quantities.mjs';
// Preview only: eligibility comes from the protected reader; SQL recalculates on save.
export function productionDistribution(total,eligible){
 if(!eligible||!quantityValid(total,'kg')||decimalCompare(eligible.rejected_available,'0')===null||decimalCompare(eligible.unfinished_available,'0')===null)return null;
 const min=(a,b)=>decimalCompare(a,b)<=0?a:b,positive=q=>decimalCompare(q,'0')>0?q:'0';
 const rejected=min(total,eligible.rejected_available),left=decimalSubtract(total,rejected),unfinished=min(left,eligible.unfinished_available);
 return {rejected,unfinished,stock:decimalSubtract(left,unfinished),uncovered:positive(decimalSubtract(decimalSubtract(eligible.rejected_available,rejected),decimalSubtract(unfinished,eligible.unfinished_available)))};
}
