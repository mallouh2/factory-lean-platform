import { useEffect, useState } from 'react';
import { Field, formatTime, localName } from '@/components/ui';
import ProductIdentity from '@/components/ProductIdentity';
import { historyQuery, parseHistoryQuery, selectedHistoryValues } from '@/utils/production-history.mjs';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
export type HistoryResult={rows:Row[];total:number;page:number;page_size:number;totals:Row[];highest:Row[];shift_totals?:Row[];unknown_unit_records?:number};
const empty:HistoryResult={rows:[],total:0,page:1,page_size:50,totals:[],highest:[]};
export default function ProductionHistory({snapshot:s,t,lang,can,onCorrect,initial}:FeatureProps & {onCorrect:(entry:Row)=>void;initial?:HistoryResult}){
  const [filters,setFilters]=useState<Record<string,string>>({}),[sort,setSort]=useState('date'),[direction,setDirection]=useState('desc'),[page,setPage]=useState(1);
  const [menu,setMenu]=useState(''),[draft,setDraft]=useState<Record<string,string>>({}),[menuError,setMenuError]=useState('');
  const [search,setSearch]=useState(''),[valuesPage,setValuesPage]=useState(1);
  const [values,setValues]=useState<{query:string;rows:Row[];total:number}|null>(null);
  const [position,setPosition]=useState({left:12,top:80});
  const [selectedNames,setSelectedNames]=useState<Record<string,string>>({});
  const factory=String(s.factory?.id || ''),zone=String(s.factory?.timezone || 'UTC');
  const query=historyQuery(factory,filters,sort,direction,page);
  const [optionState,setOptions]=useState<{factory:string;rows:Record<string,Row[]>}>({factory,rows:{}});
  const [response,setResult]=useState<{query:string;data:HistoryResult}|null>(initial?{query,data:initial}:null),[busy,setBusy]=useState(!initial),[error,setError]=useState(''),[retry,setRetry]=useState(0);
  // Keep the same query's DOM mounted during refresh, but never show another query/factory's rows.
  const loaded=response?.query===query,result=loaded?response.data:empty;
  const options=optionState.factory===factory?optionState.rows:{};
  useEffect(()=>{
    const controller=new AbortController();
    fetch(`/api/production-history?${new URLSearchParams({factory,options:'1'})}`,{signal:controller.signal,cache:'no-store'})
      .then(async r=>{if(!r.ok)throw Error('permissionError');return r.json();}).then(rows=>{if(!controller.signal.aborted)setOptions({factory,rows});}).catch(e=>{if(!controller.signal.aborted)setError(e.message);});
    return ()=>controller.abort();
  },[factory,s.fetchedAt,retry]);
  useEffect(()=>{
    const controller=new AbortController();setBusy(true);setError('');
    fetch(`/api/production-history?${query}`,{signal:controller.signal,cache:'no-store'})
      .then(async r=>{if(!r.ok)throw Error('error');return r.json();}).then(data=>{if(!controller.signal.aborted)setResult({query,data});}).catch(e=>{if(!controller.signal.aborted)setError(e.message);}).finally(()=>{if(!controller.signal.aborted)setBusy(false);});
    return ()=>controller.abort();
  },[query,s.fetchedAt,retry]);
  const valueQuery=new URLSearchParams({factory,field:menu,search,values_page:String(valuesPage)}).toString();
  useEffect(()=>{
    if(!['request','product','unit','technician','shift'].includes(menu))return;
    const controller=new AbortController();
    fetch('/api/production-history?'+valueQuery,{signal:controller.signal,cache:'no-store'}).then(async r=>{if(!r.ok)throw Error('dataWarning');return r.json();})
      .then(data=>{if(!controller.signal.aborted)setValues({query:valueQuery,...data});}).catch(e=>{if(!controller.signal.aborted)setMenuError(e.message);});
    return()=>controller.abort();
  },[valueQuery,menu]);
  const q=(value:unknown)=>Number(value).toLocaleString(lang);
  const unit=(value:unknown)=>t(value==='meter'?'meterShort':value==='piece'?'pieceShort':'legacyUnit');
  const name=(row:Row,key:string)=>String(row[lang==='ar'?`${key}_name_ar`:`${key}_name`] || row[`${key}_name`] || t('shiftNotRecorded'));
  const shiftName=(id:unknown)=>{const row=(options.shifts || s.tables.production_shifts || []).find(x=>x.id===id);return row?localName(row,lang):t('shiftNotRecorded');};
  function change(key:string,value:string){setDraft(x=>({...x,[key]:value}));setMenuError('');}
  function openMenu(key:string,event:React.MouseEvent<HTMLButtonElement>){
    setMenu(key);setDraft(filters);setSearch('');setValuesPage(1);setMenuError('');
    const rect=event.currentTarget.getBoundingClientRect();
    setPosition({left:Math.max(12,Math.min(window.innerWidth-352,lang==='ar'?rect.right-340:rect.left)),top:Math.max(12,Math.min(window.innerHeight-380,rect.bottom+4))});
  }
  function clearFilter(key:string){setFilters(old=>{
    const next={...old};for(const k of key==='date'?['from','to']:['good','scrap','unfinished'].includes(key)?[key,key+'_op',key+'_min',key+'_max',...(key==='scrap'?['minimum_scrap','scrap_metric','scrap_scope']:[])]:[key])delete next[k];
    if(!['good','scrap','unfinished'].some(k=>next[k+'_op']))delete next.measurement_unit;
    return next;});setPage(1);}
  const filterColumns=[['date','date'],['shift','productionShift'],['unit','recordingUnit'],['request','historyOrder'],['product','product'],['technician','recordingTechnician'],['good','recordingGood'],['scrap','recordingScrap'],['unfinished','unfinishedQuantity'],['corrected','historyCorrections']];
  const active=(key:string)=>key==='date'?Boolean(filters.from||filters.to):['good','scrap','unfinished'].includes(key)?Boolean(filters[key+'_op']||filters[key]==='has'||filters.minimum_scrap):Boolean(filters[key]&&filters[key]!=='all');
  const popoverId='history-column-filter-'+factory;
  const sources:Record<string,string>={request:'requests',product:'products',unit:'units',technician:'technicians',shift:'shifts'};
  const categorical=Boolean(sources[menu]);
  const valueRows=values?.query===valueQuery?values.rows:!search&&valuesPage===1?(options[sources[menu]] || []):[];
  const corrected=(row:Row)=>Boolean(row.corrected);
  function details(row:Row){
    const corrections=(row.corrections || []) as unknown as Row[];
    return <details><summary>{t('view')}{corrected(row)?` · ${t('historyCorrected')}`:''}</summary>
      <p>{t('recordingSubmittedBy')}: {String(row.submitter_name || t('shiftNotRecorded'))}</p>
      <p dir="auto">{String(row.notes || '')}</p>
      <p>{t('recordingOriginal')}: {q(row.good_quantity)} / {q(row.scrap_quantity)} / {q(row.unfinished_quantity || 0)} · {shiftName(row.original_shift_id)}</p>
      {row.shift_assignment_mode==='manual' && <div className="history-shift-override"><p>{t('shiftAutoDetected')}: {shiftName(row.automatic_shift_id)} → {shiftName(row.original_shift_id)}</p>
        <p dir="auto">{t('shiftOverrideReason')}: {String(row.shift_override_reason || '')}</p>
        <p>{String(s.tables.production_technicians?.find(x=>x.user_id===row.shift_override_by)?.display_name || row.submitter_name || t('notAvailable'))} · {formatTime(row.shift_override_at,lang,zone)}</p></div>}
      {Boolean(row.input_lot_id) && <p>{t('unfinishedInputSource')}: {t('unfinishedProduct')} · <span title={String(row.input_lot_id)}>{t('unfinishedLotReference')}: <bdi>{String(row.input_lot_id).slice(0,8)}</bdi></span> · {t('unfinishedProcess')}: {q(row.input_quantity)} {unit(row.unit)}</p>}
      {Boolean(row.remaining_work) && <p dir="auto">{t('recordingOriginal')} · {t('unfinishedRemainingWork')}: {String(row.remaining_work)}</p>}
      {Boolean(row.effective_remaining_work) && <p dir="auto">{t('unfinishedRemainingWork')}: {String(row.effective_remaining_work)}</p>}
      <p>{t('historyScrapPercentage')}: {row.scrap_percentage==null?'—':q(row.scrap_percentage)+'%'}</p>
      <p>{t('recordingRunningTotal')}: {row.running_good==null?'—':q(row.running_good)} {unit(row.unit)} · {t('recordingRemainingAtEntry')}: {row.remaining_quantity==null?'—':q(row.remaining_quantity)} {unit(row.unit)}</p>
      <ol>{corrections.map(c=><li key={String(c.id)}>{formatTime(c.created_at,lang,zone)} · {q(c.previous_good)} / {q(c.previous_scrap)} / {q(c.previous_unfinished || 0)} → {q(c.corrected_good)} / {q(c.corrected_scrap)} / {q(c.corrected_unfinished || 0)}
        {c.shift_changed && <p>{shiftName(c.previous_shift_id)} → {shiftName(c.corrected_shift_id)}</p>}
        {c.previous_remaining_work!==c.corrected_remaining_work && <p dir="auto">{t('unfinishedRemainingWork')}: {String(c.previous_remaining_work || '—')} → {String(c.corrected_remaining_work || '—')}</p>}
        <p dir="auto">{String(c.reason)} · {String(s.tables.production_technicians?.find(x=>x.user_id===c.created_by)?.display_name || t('notAvailable'))}</p></li>)}</ol>
      {can('orders','edit') && <button type="button" disabled={busy} onClick={()=>onCorrect(row)}>{t('recordingCorrect')}</button>}
    </details>;
  }
  const columns=[['date','date'],['time',''],['productionShift','shift'],['recordingUnit','unit'],['historyOrder','request'],['product','product'],['recordingTechnician','technician'],['recordingGood','good'],['recordingScrap','scrap'],['unfinishedQuantity','unfinished'],['unit',''],['recordingRunningTotal',''],['recordingRemainingAtEntry',''],['recordingSubmittedBy',''],['historyCorrections','corrected'],['action','']];
  return <section className="production-history" aria-labelledby="production-history-heading" dir={lang==='ar'?'rtl':'ltr'}>
    <h4 id="production-history-heading">{t('productionHistory')}</h4>
    <div className="history-active-filters">{filterColumns.filter(([key])=>active(key)).map(([key,label])=><button key={key} onClick={()=>clearFilter(key)}>{t(label)} · {t('historyFilterActive')} ×</button>)}{filterColumns.some(([key])=>active(key)) && <button onClick={()=>{setFilters({});setPage(1);}}>{t('historyClear')}</button>}</div>
    <button className="history-mobile-filter" popoverTarget={popoverId} popoverTargetAction="show" onClick={e=>openMenu('date',e)}>{t('historyFilters')} ▼</button>
    <div id={popoverId} popover="auto" role="dialog" aria-label={t('historyFilters')} className="history-column-popover" style={{left:position.left,top:position.top,maxHeight:`calc(100dvh - ${position.top+12}px)`}} onToggle={e=>{if((e.nativeEvent as ToggleEvent).newState==='open')e.currentTarget.querySelector<HTMLInputElement|HTMLSelectElement>('input,select')?.focus();}}>
      <div className="row-actions"><strong>{t(filterColumns.find(([key])=>key===menu)?.[1] || 'historyFilters')}</strong><button popoverTarget={popoverId} popoverTargetAction="hide" aria-label={t('close')}>×</button></div>
      <Field label={t('historyColumn')}><select value={menu} onChange={e=>{setMenu(e.target.value);setSearch('');setValuesPage(1);setMenuError('');}}>{filterColumns.map(([key,label])=><option key={key} value={key}>{t(label)}</option>)}</select></Field>
      {categorical && <><Field label={t('search')}><input type="search" maxLength={120} value={search} onChange={e=>{setSearch(e.target.value);setValuesPage(1);}}/></Field>
        <Field label={t(filterColumns.find(([key])=>key===menu)?.[1] || menu)}><select multiple size={5} value={(draft[menu] || '').split(',').filter(Boolean)} onChange={e=>{
          const selected=Array.from(e.target.selectedOptions,x=>x.value),visible=[...valueRows.map(x=>String(x.id)),...(['technician','shift'].includes(menu)?['unknown']:[])];
          setSelectedNames(old=>({...old,...Object.fromEntries(Array.from(e.target.selectedOptions,x=>[factory+':'+menu+':'+x.value,x.textContent || t('historySelected')]))}));
          change(menu,selectedHistoryValues((draft[menu] || '').split(',').filter(Boolean),visible,selected).join(','));
        }}>
          {['technician','shift'].includes(menu) && <option value="unknown">{t('shiftNotRecorded')}</option>}
          {valueRows.map(row=><option key={String(row.id)} value={String(row.id)}>{localName(row,lang)}{row.archived?' · '+t('archived'):''}</option>)}</select></Field>
        <small>{t('historySelected')}: {(draft[menu] || '').split(',').filter(Boolean).length}</small>
        <div className="history-active-filters">{(draft[menu] || '').split(',').filter(Boolean).map(id=><button key={id} onClick={()=>change(menu,(draft[menu] || '').split(',').filter(x=>x!==id).join(','))}>{id==='unknown'?t('shiftNotRecorded'):selectedNames[factory+':'+menu+':'+id] || localName(valueRows.find(x=>x.id===id) || {},lang) || t('historySelected')} ×</button>)}</div>
        <div className="row-actions"><button disabled={valuesPage===1} onClick={()=>setValuesPage(x=>x-1)}>{t('previous')}</button><span>{valuesPage}</span><button disabled={values?.query!==valueQuery || valuesPage*50>=values.total} onClick={()=>setValuesPage(x=>x+1)}>{t('next')}</button></div></>}
      {menu==='corrected' && <Field label={t('historyCorrections')}><select multiple size={2} value={(draft.corrected || '').split(',').filter(x=>x&&x!=='all')} onChange={e=>change('corrected',Array.from(e.target.selectedOptions,x=>x.value).join(','))}><option value="no">{t('historyUncorrected')}</option><option value="yes">{t('historyCorrected')}</option></select></Field>}
      {menu==='date' && <><Field label={t('historyFrom')}><input type="date" value={draft.from || ''} max={draft.to || undefined} onChange={e=>change('from',e.target.value)}/></Field><Field label={t('historyTo')}><input type="date" value={draft.to || ''} min={draft.from || undefined} onChange={e=>change('to',e.target.value)}/></Field><small><bdi>{zone}</bdi></small></>}
      {['good','scrap','unfinished'].includes(menu) && <>
        <Field label={t('unit')}><select required value={draft.measurement_unit || ''} onChange={e=>change('measurement_unit',e.target.value)}><option value="">{t('historyChooseMeasurementUnit')}</option><option value="meter">{t('meterShort')}</option><option value="piece">{t('pieceShort')}</option></select></Field>
        {menu==='scrap' && <><Field label={t('historyMetric')}><select value={draft.scrap_metric || 'quantity'} onChange={e=>change('scrap_metric',e.target.value)}><option value="quantity">{t('historyScrapQuantity')}</option><option value="percentage">{t('historyScrapPercentage')}</option></select></Field>
          {draft.scrap_metric==='percentage' && <><Field label={t('historyScope')}><select value={draft.scrap_scope || 'row'} onChange={e=>change('scrap_scope',e.target.value)}><option value="row">{t('historyPerEntry')}</option><option value="shift">{t('historyPerShift')}</option></select></Field><small>{t('historyScrapFormula')}</small></>}</>}
        <Field label={t('historyCondition')}><select value={draft[menu+'_op'] || ''} onChange={e=>change(menu+'_op',e.target.value)}><option value="">{t('all')}</option>{['eq','gte','lte','between'].map(op=><option key={op} value={op}>{t('historyOperator_'+op)}</option>)}</select></Field>
        {draft[menu+'_op'] && <><Field label={t(draft[menu+'_op']==='between'?'historyMinimum':'historyValue')+(menu==='scrap'&&draft.scrap_metric==='percentage'?' (%)':' ('+unit(draft.measurement_unit)+')')}><input type="number" min="0" step="any" value={draft[menu+'_min'] || ''} onChange={e=>change(menu+'_min',e.target.value)}/></Field>{draft[menu+'_op']==='between' && <Field label={t('historyMaximum')}><input type="number" min={draft[menu+'_min'] || 0} step="any" value={draft[menu+'_max'] || ''} onChange={e=>change(menu+'_max',e.target.value)}/></Field>}</>}
      </>}
      {menuError && <p role="alert">{t(menuError)}</p>}
      <div className="row-actions"><button className="primary" onClick={()=>{try{parseHistoryQuery(new URLSearchParams(historyQuery(factory,draft,sort,direction,1)));setFilters(draft);setPage(1);document.getElementById(popoverId)?.hidePopover();}catch(e){setMenuError(e instanceof Error&&e.message==='history_unit_required'?'historyUnitRequired':'historyFilterInvalid');}}}>{t('historyApply')}</button><button onClick={()=>{clearFilter(menu);document.getElementById(popoverId)?.hidePopover();}}>{t('historyClearColumn')}</button></div>
    </div>
    <div className="history-sort-controls"><Field label={t('historySort')}><select value={sort} onChange={e=>{setSort(e.target.value);setPage(1);}}>{[['date','date'],['good','recordingGood'],['scrap','recordingScrap'],['unfinished','unfinishedQuantity'],['unit','recordingUnit'],['technician','recordingTechnician'],['shift','productionShift']].map(([key,label])=><option key={key} value={key}>{t(label)}</option>)}</select></Field>
      <button onClick={()=>{setDirection(x=>x==='desc'?'asc':'desc');setPage(1);}}>{t(direction==='desc'?'historyDescending':'historyAscending')}</button></div>
    {error && <p role="alert">{t(error)} <button onClick={()=>setRetry(x=>x+1)}>{t('refresh')}</button></p>}
    <p className="history-load-status muted" role="status">{busy?t('historyLoading'):''}</p>
    {loaded && <><div className="history-summary" role="status"><strong>{t('historyRecords')}: {q(result.total)}</strong>
      {Boolean(result.unknown_unit_records) && <span>{t('historyUnknownUnits')}: {q(result.unknown_unit_records)}</span>}
      {result.totals.map(x=><span key={String(x.measurement_unit)}>{t('recordingGood')}: <b>{q(x.good)}</b> · {t('recordingScrap')}: <b>{q(x.scrap)}</b> · {t('unfinishedQuantity')}: <b>{q(x.unfinished || 0)}</b> {unit(x.measurement_unit)} · {t('historyScrapPercentage')}: {x.scrap_percentage==null?'—':q(x.scrap_percentage)+'%'}</span>)}
      {(result.shift_totals || []).map(x=><span key={String(x.shift_id)+':'+String(x.measurement_unit)}>{name(x,'shift')} · {unit(x.measurement_unit)} · {t('historyScrapPercentage')}: {x.scrap_percentage==null?'—':q(x.scrap_percentage)+'%'}</span>)}
      {result.highest.map(x=><span key={`${x.measurement_unit}:${x.kind}`}>{t(x.kind==='unit'?'historyHighestUnit':x.kind==='shift'?'historyHighestShift':'historyHighestTechnician')}: {x.name || x.name_ar ? localName(x,lang) : t('shiftNotRecorded')} · {q(x.scrap)} {unit(x.measurement_unit)}</span>)}
    </div>
    {!result.rows.length && <p>{t('historyNoMatches')}</p>}
    <div className="history-desktop table-wrap"><table><caption className="sr-only">{t('productionHistory')}</caption><thead><tr>{columns.map(([label,key],i)=><th key={i} scope="col" aria-sort={key&&key===sort?(direction==='asc'?'ascending':'descending'):undefined}>{t(label)}{key&&filterColumns.some(([k])=>k===key) && <button type="button" className="history-filter-arrow" aria-label={t('historyFilterColumn')+' '+t(label)} aria-haspopup="dialog" popoverTarget={popoverId} popoverTargetAction="show" onClick={e=>openMenu(key,e)}>{active(key)?'● ':''}▼</button>}</th>)}</tr></thead>
      <tbody>{result.rows.map(row=><tr key={String(row.id)}><td>{new Intl.DateTimeFormat(lang,{timeZone:zone,dateStyle:'medium'}).format(new Date(String(row.created_at)))}</td><td>{new Intl.DateTimeFormat(lang,{timeZone:zone,timeStyle:'short'}).format(new Date(String(row.created_at)))}</td>
        <td>{name(row,'shift')}</td><td dir="auto">{name(row,'unit')}</td><td><bdi>{String(row.request_code || row.item_code)}</bdi></td><td dir="auto"><ProductIdentity productId={row.product_id} productItemId={row.order_id}>{name(row,'product')}</ProductIdentity></td><td>{String(row.technician_name || t('shiftNotRecorded'))}</td>
        <td className="history-number">{q(row.effective_good)}</td><td className="history-number">{q(row.effective_scrap)}</td><td className="history-number">{q(row.effective_unfinished || 0)}</td><td>{unit(row.unit)}</td><td className="history-number">{row.running_good==null?'—':q(row.running_good)}</td><td className="history-number">{row.remaining_quantity==null?'—':q(row.remaining_quantity)}</td>
        <td>{String(row.submitter_name || t('shiftNotRecorded'))}</td><td>{t(corrected(row)?'historyCorrected':'historyUncorrected')}</td><td>{details(row)}</td></tr>)}</tbody></table></div>
    <div className="history-mobile">{result.rows.map(row=><article key={String(row.id)}><div><time>{formatTime(row.created_at,lang,zone)}</time> · {name(row,'shift')}</div>
      <strong><bdi>{String(row.request_code || row.item_code)}</bdi> · <ProductIdentity productId={row.product_id} productItemId={row.order_id}>{name(row,'product')}</ProductIdentity></strong><p>{name(row,'unit')} · {String(row.technician_name || t('shiftNotRecorded'))}</p>
      <dl className="recording-figures"><div><dt>{t('recordingGood')}</dt><dd>{q(row.effective_good)} {unit(row.unit)}</dd></div><div><dt>{t('recordingScrap')}</dt><dd>{q(row.effective_scrap)} {unit(row.unit)}</dd></div><div><dt>{t('unfinishedQuantity')}</dt><dd>{q(row.effective_unfinished || 0)} {unit(row.unit)}</dd></div><div><dt>{t('recordingRemainingAtEntry')}</dt><dd>{row.remaining_quantity==null?'—':q(row.remaining_quantity)} {unit(row.unit)}</dd></div></dl>{details(row)}</article>)}</div>
    <nav className="history-pagination" aria-label={t('historyPages')}><button disabled={busy || page<=1} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{q(page)} / {q(Math.max(1,Math.ceil(result.total/50)))}</span><button disabled={busy || page*50>=result.total} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav></>}
  </section>;
}
