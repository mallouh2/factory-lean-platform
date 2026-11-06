import {decimalCompare} from './quality-quantities.mjs';

export const historyColumns = [
  ['date','date','date'],['shift','productionShift','shift'],['line','historyLine','unit'],
  ['order','historyOrder','request'],['product','product','product'],['good','historyGood','good'],['scrap','historyScrap',''],
  ['technician','historyResponsible','technician'],['recordedBy','recordingSubmittedBy',''],
  ['submittedAt','historySubmittedAt',''],['wip','unfinishedQuantity','unfinished'],['machine','machine',''],
];
export const defaultHistoryColumns = historyColumns.slice(0,7).map(([key])=>key);
export function visibleHistoryColumns(value,allowed=historyColumns.map(([key])=>key)) {
  if(!Array.isArray(value))return defaultHistoryColumns.filter(key=>allowed.includes(key));
  const selected=historyColumns.map(([key])=>key).filter(key=>allowed.includes(key)&&value.includes(key));
  return selected.length?selected:defaultHistoryColumns.filter(key=>allowed.includes(key));
}
export function historyPreferenceKey(actor,factory) {
  return actor&&factory?`factorylean:table:v2:production-history:${encodeURIComponent(actor)}:${encodeURIComponent(factory)}`:null;
}
// Preserve decimal text for full-value inspection; formatting never changes official data.
export function historyNumber(value,language='en') {
  if(value===null||value===undefined||value==='')return null;
  const text=String(value);if(!/^-?\d+(?:\.\d+)?$/.test(text))return Number.isFinite(Number(text))?Number(text).toLocaleString(language):null;
  const [whole,fraction]=text.split('.'),integer=(whole==='-0'?'-':'')+BigInt(whole).toLocaleString(language);
  if(!fraction)return integer;
  const decimal=new Intl.NumberFormat(language).formatToParts(1.1).find(x=>x.type==='decimal')?.value||'.';
  // Edge and Node may use different default Arabic numbering systems. Match the whole part.
  const formatter=new Intl.NumberFormat(language,{useGrouping:false});
  const digits=fraction.replace(/\d/g,d=>formatter.format(Number(d)));
  return integer+decimal+digits;
}
export function productionDates(row,zone) {
  const occurrence=row.effective_occurrence;
  if(occurrence?.business_date&&/^\d{4}-\d{2}-\d{2}$/.test(occurrence.business_date))return [occurrence.business_date];
  // A genuine production period may span calendar dates; never use submitted time as a substitute.
  if(!row.effective_period_start||!row.effective_period_end)return [];
  const dates=[row.effective_period_start,row.effective_period_end].map(t=>{
    const instant=new Date(t);if(!Number.isFinite(instant.getTime()))return null;
    const p=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(instant);
    return ['year','month','day'].map(k=>p.find(x=>x.type===k)?.value).join('-');
  });
  return dates.every(Boolean)?[...new Set(dates)]:[];
}
export function historyScrapRate(row) {
  if(!['RECORDING_CONFIG','VERIFIED_HISTORICAL'].includes(row.weight_basis)||
     decimalCompare(row.produced_weight_kg,'0')!==1||decimalCompare(row.effective_scrap_kg,'0')===null||decimalCompare(row.effective_scrap_kg,'0')<0)return null;
  // Same approved History/Quality formula; denominator already includes Good + newly recorded WIP weight.
  const rate=100*Number(row.effective_scrap_kg)/Number(row.produced_weight_kg);
  return Number.isFinite(rate)?rate:null;
}
