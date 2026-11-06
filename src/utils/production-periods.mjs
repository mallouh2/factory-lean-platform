// Period containment only: no allocation, stock posting, flow or Lean formula.
// Microseconds are retained at window boundaries rather than rounded by Date.
import {decimalSubtract,decimalMultiply} from './quality-quantities.mjs';
const moment=value=>{
 if(typeof value!=='string'||!/(Z|[+-]\d\d:\d\d)$/.test(value))return null;
 const ms=Date.parse(value);if(!Number.isFinite(ms))return null;
 const fraction=/\.(\d{1,6})(?:Z|[+-]\d\d:\d\d)$/.exec(value)?.[1]??'';
 return BigInt(ms)*1000n+BigInt(fraction.padEnd(6,'0').slice(3));
};
export function productionScope(row,from,to,{entry=false,include_end=false}={}){
 const lo=moment(from),hi=moment(to);if(lo===null||hi===null||hi<lo)throw Error('lean_period_invalid');
 const modern=Number(row.evidence_version)===2;
 const precision=modern?(entry?row.production_precision??row.time_precision:row.time_precision):'EXACT';
 const rawPoint=entry?row.created_at:row.occurred_at;
 const point=modern?moment(rawPoint):Number.isFinite(Date.parse(rawPoint))?BigInt(Date.parse(rawPoint))*1000n:null;
 const inside=p=>p!==null&&p>=lo&&(include_end?p<=hi:p<hi);
 if(precision==='EXACT'&&point!==null)return inside(point)?'CONTAINED':'OUTSIDE';
 const a=moment(entry?row.effective_period_start:row.period_start),b=moment(entry?row.effective_period_end:row.period_end);
 if(precision==='SHIFT_PERIOD'&&a!==null&&b!==null&&b>=a){
  if(a===b)return inside(a)?'CONTAINED':'OUTSIDE';
  if(a>=hi||b<=lo)return 'OUTSIDE';
  return a>=lo&&b<=hi?'CONTAINED':'PARTIAL';
 }
 return inside(moment(row.recorded_at??row.created_at))?'UNKNOWN':'OUTSIDE';
}
export function exactQuantitySum(rows,field){
 let sum='0';
 for(const row of rows){
  const value=row[field];if(value===null||value===undefined||value==='')return null;
  const negative=decimalMultiply(value,'-1');if(negative===null)return null;
  sum=decimalSubtract(sum,negative);if(sum===null)return null;
 }
 return sum;
}
