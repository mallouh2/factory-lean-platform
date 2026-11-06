import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';

// Presentation only. Eligibility and allocations still come from protected readers.
export const sumQuantities=values=>values.reduce((sum,value)=>decimalSubtract(sum,`-${value||'0'}`)??sum,'0');
export function qualityWorkSummary(work,decisions=[]){
 const live=work.filter(w=>!w.decision_revision?.retirement&&w.status!=='cancelled');
 return {
  completion:sumQuantities(live.filter(w=>w.choice==='COMPLETE').map(w=>w.quantity)),
  replacement:sumQuantities([...live.filter(w=>w.choice==='REPLACE').map(w=>w.quantity),
   ...decisions.filter(d=>d.mode==='ACTIVE').map(d=>sumQuantities([d.recorded,d.remaining]))]),
 };
}
export function qualityWorkState(w){
 if(w.decision_revision?.retirement||w.status==='cancelled')return 'cancelled';
 if(w.held)return 'held';
 if(w.status==='completed')return decimalCompare(w.received_finished,w.quantity)===0?'received':'awaiting_receipt';
 if(w.status==='active')return 'active';
 return w.line_id&&w.start_time?'scheduled':'unscheduled';
}
