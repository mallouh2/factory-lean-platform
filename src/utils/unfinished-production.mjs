/** Client guidance only. The recording transaction independently checks every value.
 * @param {number|string|null} input
 * @param {number|string|null} available
 */
export function unfinishedOutputValid(good, scrap, unfinished, remainingWork, input = null, available = null) {
  const values=[good,scrap,unfinished].map(Number);
  if(values.some(x=>!Number.isFinite(x)||x<0)||values.reduce((a,b)=>a+b,0)<=0) return false;
  if(values[2]>0 && String(remainingWork || '').trim().length<3) return false;
  const total=values.reduce((a,b)=>a+b,0);
  // Browser arithmetic may represent 0.1 + 0.2 slightly above 0.3.
  // PostgreSQL numeric independently enforces exact submitted conservation.
  if(input!==null && (!Number.isFinite(Number(input)) || Number(input)<=0 || Number(input)>Number(available) || Math.abs(Number(input)-total)>Number.EPSILON*8*Math.max(1,Number(input),total)))return false;
  return true;
}
