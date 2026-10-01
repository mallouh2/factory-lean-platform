import { useEffect, useState } from 'react';
import { Field, formatTime, localName } from '@/components/ui';
import { historyQuery } from '@/utils/production-history.mjs';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
export type HistoryResult={rows:Row[];total:number;page:number;page_size:number;totals:Row[];highest:Row[];unknown_unit_records?:number};
const empty:HistoryResult={rows:[],total:0,page:1,page_size:50,totals:[],highest:[]};
export default function ProductionHistory({snapshot:s,t,lang,can,onCorrect,initial}:FeatureProps & {onCorrect:(entry:Row)=>void;initial?:HistoryResult}){
  const [filters,setFilters]=useState<Record<string,string>>({}),[sort,setSort]=useState('date'),[direction,setDirection]=useState('desc'),[page,setPage]=useState(1);
  const [options,setOptions]=useState<Record<string,Row[]>>({}),[result,setResult]=useState(initial || empty),[busy,setBusy]=useState(!initial),[error,setError]=useState(''),[retry,setRetry]=useState(0);
  const factory=String(s.factory?.id || ''),zone=String(s.factory?.timezone || 'UTC');
  useEffect(()=>{
    const controller=new AbortController();
    setOptions({});
    fetch(`/api/production-history?${new URLSearchParams({factory,options:'1'})}`,{signal:controller.signal,cache:'no-store'})
      .then(async r=>{if(!r.ok)throw Error('permissionError');return r.json();}).then(setOptions).catch(e=>{if(e.name!=='AbortError')setError(e.message);});
    return ()=>controller.abort();
  },[factory,s.fetchedAt,retry]);
  useEffect(()=>{
    const controller=new AbortController();setBusy(true);setError('');setResult(empty);
    fetch(`/api/production-history?${historyQuery(factory,filters,sort,direction,page)}`,{signal:controller.signal,cache:'no-store'})
      .then(async r=>{if(!r.ok)throw Error('error');return r.json();}).then(setResult).catch(e=>{if(e.name!=='AbortError')setError(e.message);}).finally(()=>{if(!controller.signal.aborted)setBusy(false);});
    return ()=>controller.abort();
  },[factory,filters,sort,direction,page,s.fetchedAt,retry]);
  const q=(value:unknown)=>Number(value).toLocaleString(lang);
  const unit=(value:unknown)=>t(value==='meter'?'meterShort':value==='piece'?'pieceShort':'legacyUnit');
  const name=(row:Row,key:string)=>String(row[lang==='ar'?`${key}_name_ar`:`${key}_name`] || row[`${key}_name`] || t('shiftNotRecorded'));
  const shiftName=(id:unknown)=>{const row=(options.shifts || s.tables.production_shifts || []).find(x=>x.id===id);return row?localName(row,lang):t('shiftNotRecorded');};
  function change(key:string,value:string){setFilters(x=>({...x,[key]:value}));setPage(1);}
  function sortBy(key:string){setSort(key);setDirection(sort===key && direction==='desc'?'asc':'desc');setPage(1);}
  const corrected=(row:Row)=>Boolean(row.corrected);
  function details(row:Row){
    const corrections=(row.corrections || []) as unknown as Row[];
    return <details><summary>{t('view')}{corrected(row)?` · ${t('historyCorrected')}`:''}</summary>
      <p>{t('recordingSubmittedBy')}: {String(row.submitter_name || t('shiftNotRecorded'))}</p>
      <p dir="auto">{String(row.notes || '')}</p>
      <p>{t('recordingOriginal')}: {q(row.good_quantity)} / {q(row.scrap_quantity)} · {shiftName(row.original_shift_id)}</p>
      <p>{t('recordingRunningTotal')}: {row.running_good==null?'—':q(row.running_good)} {unit(row.unit)} · {t('recordingRemainingAtEntry')}: {row.remaining_quantity==null?'—':q(row.remaining_quantity)} {unit(row.unit)}</p>
      <ol>{corrections.map(c=><li key={String(c.id)}>{formatTime(c.created_at,lang,zone)} · {q(c.previous_good)} / {q(c.previous_scrap)} → {q(c.corrected_good)} / {q(c.corrected_scrap)}
        {c.shift_changed && <p>{shiftName(c.previous_shift_id)} → {shiftName(c.corrected_shift_id)}</p>}
        <p dir="auto">{String(c.reason)} · {String(s.tables.production_technicians?.find(x=>x.user_id===c.created_by)?.display_name || t('notAvailable'))}</p></li>)}</ol>
      {can('orders','edit') && <button type="button" disabled={busy} onClick={()=>onCorrect(row)}>{t('recordingCorrect')}</button>}
    </details>;
  }
  const columns=[['date','date'],['time',''],['productionShift','shift'],['recordingUnit','unit'],['historyOrder',''],['product',''],['recordingTechnician','technician'],['recordingGood','good'],['recordingScrap','scrap'],['unit',''],['recordingRunningTotal',''],['recordingRemainingAtEntry',''],['recordingSubmittedBy',''],['status',''],['action','']];
  return <section className="production-history" aria-labelledby="production-history-heading" dir={lang==='ar'?'rtl':'ltr'}>
    <h4 id="production-history-heading">{t('productionHistory')}</h4>
    <details className="history-filter-panel" open><summary>{t('historyFilters')}</summary><div className="history-filters">
      <Field label={t('historyFrom')}><input type="date" value={filters.from || ''} max={filters.to || undefined} onChange={e=>change('from',e.target.value)}/></Field>
      <Field label={t('historyTo')}><input type="date" value={filters.to || ''} min={filters.from || undefined} onChange={e=>change('to',e.target.value)}/></Field>
      {([['request','requests','historyOrder'],['product','products','product'],['unit','units','recordingUnit'],['technician','technicians','recordingTechnician'],['shift','shifts','productionShift']] as const).map(([key,source,label])=><Field key={key} label={t(label)}><select value={filters[key] || ''} onChange={e=>change(key,e.target.value)}>
        <option value="">{t('all')}</option>{['technician','shift'].includes(key) && <option value="unknown">{t('shiftNotRecorded')}</option>}
        {(options[source] || []).map(row=><option key={String(row.id)} value={String(row.id)}>{localName(row,lang)}{row.archived?` · ${t('archived')}`:''}</option>)}</select></Field>)}
      <Field label={t('recordingScrap')}><select value={filters.scrap || 'all'} onChange={e=>change('scrap',e.target.value)}><option value="all">{t('all')}</option><option value="has">{t('historyHasScrap')}</option></select></Field>
      <Field label={t('historyMinimumScrap')}><input type="number" min="0" step="any" value={filters.minimum_scrap || ''} onChange={e=>change('minimum_scrap',e.target.value)}/></Field>
      <Field label={t('historyCorrections')}><select value={filters.corrected || 'all'} onChange={e=>change('corrected',e.target.value)}><option value="all">{t('all')}</option><option value="yes">{t('historyCorrected')}</option><option value="no">{t('historyUncorrected')}</option></select></Field>
      <button onClick={()=>{setFilters({});setPage(1);}}>{t('historyClear')}</button>
    </div></details>
    <div className="history-sort-controls"><Field label={t('historySort')}><select value={sort} onChange={e=>{setSort(e.target.value);setPage(1);}}>{[['date','date'],['good','recordingGood'],['scrap','recordingScrap'],['unit','recordingUnit'],['technician','recordingTechnician'],['shift','productionShift']].map(([key,label])=><option key={key} value={key}>{t(label)}</option>)}</select></Field>
      <button onClick={()=>{setDirection(x=>x==='desc'?'asc':'desc');setPage(1);}}>{t(direction==='desc'?'historyDescending':'historyAscending')}</button></div>
    {error && <p role="alert">{t(error)} <button onClick={()=>setRetry(x=>x+1)}>{t('refresh')}</button></p>}
    {busy && <p role="status">{t('loading')}</p>}
    {!busy && !error && <><div className="history-summary" role="status"><strong>{t('historyRecords')}: {q(result.total)}</strong>
      {Boolean(result.unknown_unit_records) && <span>{t('historyUnknownUnits')}: {q(result.unknown_unit_records)}</span>}
      {result.totals.map(x=><span key={String(x.measurement_unit)}>{t('recordingGood')}: <b>{q(x.good)}</b> · {t('recordingScrap')}: <b>{q(x.scrap)}</b> {unit(x.measurement_unit)}</span>)}
      {result.highest.map(x=><span key={`${x.measurement_unit}:${x.kind}`}>{t(x.kind==='unit'?'historyHighestUnit':x.kind==='shift'?'historyHighestShift':'historyHighestTechnician')}: {x.name || x.name_ar ? localName(x,lang) : t('shiftNotRecorded')} · {q(x.scrap)} {unit(x.measurement_unit)}</span>)}
    </div>
    {!result.rows.length && <p>{t('historyNoMatches')}</p>}
    <div className="history-desktop table-wrap"><table><caption className="sr-only">{t('productionHistory')}</caption><thead><tr>{columns.map(([label,key],i)=><th key={i} scope="col" aria-sort={key===sort?(direction==='asc'?'ascending':'descending'):undefined}>{key?<button onClick={()=>sortBy(key)}>{t(label)}{sort===key?(direction==='desc'?' ↓':' ↑'):''}</button>:t(label)}</th>)}</tr></thead>
      <tbody>{result.rows.map(row=><tr key={String(row.id)}><td>{new Intl.DateTimeFormat(lang,{timeZone:zone,dateStyle:'medium'}).format(new Date(String(row.created_at)))}</td><td>{new Intl.DateTimeFormat(lang,{timeZone:zone,timeStyle:'short'}).format(new Date(String(row.created_at)))}</td>
        <td>{name(row,'shift')}</td><td dir="auto">{name(row,'unit')}</td><td><bdi>{String(row.request_code || row.item_code)}</bdi></td><td dir="auto">{name(row,'product')}</td><td>{String(row.technician_name || t('shiftNotRecorded'))}</td>
        <td className="history-number">{q(row.effective_good)}</td><td className="history-number">{q(row.effective_scrap)}</td><td>{unit(row.unit)}</td><td className="history-number">{row.running_good==null?'—':q(row.running_good)}</td><td className="history-number">{row.remaining_quantity==null?'—':q(row.remaining_quantity)}</td>
        <td>{String(row.submitter_name || t('shiftNotRecorded'))}</td><td>{corrected(row)?t('historyCorrected'):'—'}</td><td>{details(row)}</td></tr>)}</tbody></table></div>
    <div className="history-mobile">{result.rows.map(row=><article key={String(row.id)}><div><time>{formatTime(row.created_at,lang,zone)}</time> · {name(row,'shift')}</div>
      <strong><bdi>{String(row.request_code || row.item_code)}</bdi> · {name(row,'product')}</strong><p>{name(row,'unit')} · {String(row.technician_name || t('shiftNotRecorded'))}</p>
      <dl className="recording-figures"><div><dt>{t('recordingGood')}</dt><dd>{q(row.effective_good)} {unit(row.unit)}</dd></div><div><dt>{t('recordingScrap')}</dt><dd>{q(row.effective_scrap)} {unit(row.unit)}</dd></div><div><dt>{t('recordingRemainingAtEntry')}</dt><dd>{row.remaining_quantity==null?'—':q(row.remaining_quantity)} {unit(row.unit)}</dd></div></dl>{details(row)}</article>)}</div>
    <nav className="history-pagination" aria-label={t('historyPages')}><button disabled={busy || page<=1} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{q(page)} / {q(Math.max(1,Math.ceil(result.total/50)))}</span><button disabled={busy || page*50>=result.total} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav></>}
  </section>;
}
