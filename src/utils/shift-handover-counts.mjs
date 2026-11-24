import {decimalCompare,decimalMultiply,decimalSubtract} from './quality-quantities.mjs';

const exactCount=/^[0-9]{1,24}(\.[0-9]{1,12})?$/;
const wholeCount=/^[0-9]{1,24}$/;

export function handoverCountValid(value,wholeKg=false){
  return typeof value==='string'&&(wholeKg?wholeCount:exactCount).test(value);
}

export function roundHandoverKg(value){
  if(value===undefined)return undefined;
  const exact=decimalSubtract(value,'0');
  if(exact===null)return undefined;
  const negative=exact.startsWith('-');
  const [whole,fraction]=exact.replace(/^-/,'').split('.');
  const rounded=BigInt(whole)+(fraction&&fraction[0]>='5'?1n:0n);
  return (negative?-rounded:rounded).toString();
}

export function compareHandoverCount(actual,expected,threshold,wholeKg=false){
  if(!handoverCountValid(actual,wholeKg))return {difference:null,significant:false};
  const baseline=wholeKg?roundHandoverKg(expected):expected;
  const difference=decimalSubtract(actual,baseline);
  if(difference===null||difference==='0')return {difference,significant:false};
  const boundary=decimalMultiply(baseline,threshold);
  return {difference,significant:boundary!==null&&decimalCompare(decimalMultiply(difference.replace(/^-/,''),'100'),boundary)===1};
}
