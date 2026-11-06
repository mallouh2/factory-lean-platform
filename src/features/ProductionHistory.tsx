import {useTableDetails} from '@/components/useTableDetails';
import { useEffect, useState } from 'react';
import { Dialog, Field, formatTime, localName } from '@/components/ui';
import ProductIdentity from '@/components/ProductIdentity';
import ManufacturedOutput from './ManufacturedOutput';
import { historyQuery, parseHistoryQuery, selectedHistoryValues } from '@/utils/production-history.mjs';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
import TableExport from '@/components/TableExport';
import {defaultHistoryColumns,historyColumns,historyNumber,historyPreferenceKey,historyScrapRate,productionDates,visibleHistoryColumns} from '@/utils/production-history-view.mjs';
export type HistoryResult={rows:Row[];total:number;page:number;page_size:number;totals:Row[];highest:Row[];shift_totals?:Row[];unknown_unit_records?:number};
const empty:HistoryResult={rows:[],total:0,page:1,page_size:50,totals:[],highest:[]};
export default function ProductionHistory({snapshot:s,t,lang,can,command,onCorrect,initial,onLanguageChange,onOutputRelated}:FeatureProps & {onCorrect:(entry:Row)=>void;initial?:HistoryResult}){
  const detailsRow=useTableDetails();
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
  const [selection,setSelection]=useState<{query:string;id:string}|null>(null),[showDetails,setShowDetails]=useState(false);
  const [preference,setPreference]=useState<{scope:string|null;columns:string[]}>({scope:null,columns:defaultHistoryColumns});
  const [preferenceError,setPreferenceError]=useState(false);
  const [toolPosition,setToolPosition]=useState({left:16,top:120});
  const scope=historyPreferenceKey(s.user?.id,factory);
  const allowedColumns=historyColumns.filter(([key])=>key!=='machine'||can('centers','view')).map(([key])=>key);
  const shown=visibleHistoryColumns(preference.scope===scope?preference.columns:defaultHistoryColumns,allowedColumns);
  const selectionQuery=String(scope)+'|'+query;
  const selected=selection?.query===selectionQuery?result.rows.find(row=>String(row.id)===selection.id):undefined;
  const [scrapTotal,setScrapTotal]=useState<{key:string;value:string|null;failed:boolean}|null>(null);
  const scrapKey=String(scope)+'|'+String(selected?.id)+'|'+String(s.fetchedAt)+'|'+retry;
  useEffect(()=>{
    if(!showDetails||!selected||!can('orders','view'))return;
    const controller=new AbortController();
    fetch('/api/production-history?'+new URLSearchParams({factory,scrap_total_entry:String(selected.id)}),{signal:controller.signal,cache:'no-store'})
      .then(async r=>{if(!r.ok)throw Error('error');return r.json();})
      .then(data=>{if(!controller.signal.aborted)setScrapTotal({key:scrapKey,value:typeof data.scrap_kg==='string'?data.scrap_kg:null,failed:false});})
      .catch(()=>{if(!controller.signal.aborted)setScrapTotal({key:scrapKey,value:null,failed:true});});
    return()=>controller.abort();
  },[showDetails,scrapKey,can('orders','view')]);
  const actionsId='history-actions-'+factory,columnsId='history-columns-'+factory;
  const toolStyle={left:toolPosition.left,top:toolPosition.top,right:'auto',bottom:'auto',width:260,maxHeight:`calc(100dvh - ${toolPosition.top+16}px)`};
  function placeTool(event:React.MouseEvent<HTMLButtonElement>){const rect=event.currentTarget.getBoundingClientRect();setToolPosition({left:Math.max(16,Math.min(window.innerWidth-276,lang==='ar'?rect.right-260:rect.left)),top:Math.min(rect.bottom+8,Math.max(16,window.innerHeight-280))});}
  useEffect(()=>{
    let columns=defaultHistoryColumns;
    if(scope)try{columns=visibleHistoryColumns(JSON.parse(localStorage.getItem(scope)||'null'));}catch{/* Missing or invalid preferences restore the default. */}
    setPreference({scope,columns});setPreferenceError(false);
  },[scope]);
  useEffect(()=>{if(selection&&!selected){setSelection(null);setShowDetails(false);}},[selected?.id,query,scope]);
  function saveColumns(columns:string[]){
    const next=visibleHistoryColumns(columns,allowedColumns);setPreference({scope,columns:next});
    if(scope)try{localStorage.setItem(scope,JSON.stringify(next));setPreferenceError(false);}catch{setPreferenceError(true);}
  }
  function selectRow(row:Row){setSelection({query:selectionQuery,id:String(row.id)});}
  function rowKey(event:React.KeyboardEvent,rows:Row[],index:number,prefix:string){
    if(event.key==='Enter'||event.key===' '){event.preventDefault();selectRow(rows[index]);}
    const target=event.key==='ArrowDown'?Math.min(rows.length-1,index+1):event.key==='ArrowUp'?Math.max(0,index-1):event.key==='Home'?0:event.key==='End'?rows.length-1:null;
    if(target!==null){event.preventDefault();selectRow(rows[target]);document.getElementById(prefix+String(rows[target].id))?.focus();}
  }
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
  const unit=(value:unknown)=>t(value==='meter'?'meterShort':value==='piece'?'pieceShort':value==='kg'?'kg':'legacyUnit');
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
  const filterColumns=[['date','historyRecordedDate'],['shift','productionShift'],['unit','recordingUnit'],['request','historyOrder'],['product','product'],['technician','recordingTechnician'],['good','recordingGood'],['scrap','leanDiscardedLegacy'],['unfinished','unfinishedQuantity'],['corrected','historyCorrections']];
  const active=(key:string)=>key==='date'?Boolean(filters.from||filters.to):['good','scrap','unfinished'].includes(key)?Boolean(filters[key+'_op']||filters[key]==='has'||filters.minimum_scrap):Boolean(filters[key]&&filters[key]!=='all');
  const popoverId='history-column-filter-'+factory;
  const sources:Record<string,string>={request:'requests',product:'products',unit:'units',technician:'technicians',shift:'shifts'};
  const categorical=Boolean(sources[menu]);
  const valueRows=values?.query===valueQuery?values.rows:!search&&valuesPage===1?(options[sources[menu]] || []):[];
  const corrected=(row:Row)=>Boolean(row.corrected);
  function auditDetails(row:Row){
    const corrections=(row.corrections || []) as unknown as Row[];
    return <details className="history-audit"><summary>{t('historyCorrectionHistory')}</summary>
      <ol>{corrections.map(c=><li key={String(c.id)}>{formatTime(c.created_at,lang,zone)}
        <p>{t('historyGood')}: <bdi>{quantity(c.previous_good,row.unit)} → {quantity(c.corrected_good,row.unit)}</bdi></p>
        <p>{t('historyScrap')}: <bdi>{quantity(c.previous_scrap_kg,'kg')} → {quantity(c.corrected_scrap_kg,'kg')}</bdi></p>
        <p>{t('unfinishedQuantity')}: <bdi>{quantity(c.previous_unfinished,row.unit)} → {quantity(c.corrected_unfinished,row.unit)}</bdi></p>
        {c.shift_changed && <p>{shiftName(c.previous_shift_id)} → {shiftName(c.corrected_shift_id)}</p>}
        {c.previous_remaining_work!==c.corrected_remaining_work && <p dir="auto">{t('unfinishedRemainingWork')}: {String(c.previous_remaining_work || '—')} → {String(c.corrected_remaining_work || '—')}</p>}
        <p dir="auto">{String(c.reason)} · {String(s.tables.production_technicians?.find(x=>x.user_id===c.created_by)?.display_name || t('notAvailable'))}</p></li>)}</ol>
    </details>;
  }
  const columns=historyColumns.filter(([key])=>shown.includes(key));
  const quantity=(value:unknown,measurement:unknown)=>value==null?t('notAvailable'):`${historyNumber(value,lang)??t('notAvailable')} ${unit(measurement)}`;
  function cell(row:Row,key:string):React.ReactNode{
    if(key==='date'){
      const dates=productionDates(row,zone);
      return dates.length?<span title={t(row.effective_occurrence?'historyProductionDate':'historyPeriodDate')}>
        {dates.map((date:string)=>new Intl.DateTimeFormat(lang,{timeZone:'UTC',dateStyle:'medium'}).format(new Date(date+'T12:00:00Z'))).join(' – ')}
      </span>:<span title={t('historyAttributionMissing')}>{t('notAvailable')}</span>;
    }
    if(key==='shift')return name(row,'shift');
    if(key==='line')return row.line_id===null||(!row.line_id&&row.work_center_id)?t('notAvailable'):name(row,'unit');
    if(key==='order')return <bdi>{String(row.request_code||row.item_code||t('notAvailable'))}</bdi>;
    if(key==='product')return <ProductIdentity productId={row.product_id} productItemId={row.order_id}>{name(row,'product')}</ProductIdentity>;
    if(key==='good')return <bdi title={String(row.effective_good??'')}>{quantity(row.effective_good,row.unit)}</bdi>;
    if(key==='scrap'){
      const rate=historyScrapRate(row);return <bdi title={String(row.effective_scrap_kg??t('notAvailable'))+' '+t('kg')}>
        {row.effective_scrap_kg==null?t('notAvailable'):historyNumber(row.effective_scrap_kg,lang)+' '+t('kg')} ({rate===null?'—':new Intl.NumberFormat(lang,{style:'percent',maximumFractionDigits:2}).format(rate/100)})
      </bdi>;
    }
    if(key==='technician')return String(row.technician_name||t('notAvailable'));
    if(key==='recordedBy')return String(row.submitter_name||t('notAvailable'));
    if(key==='submittedAt')return formatTime(row.created_at,lang,zone);
    if(key==='wip')return quantity(row.effective_unfinished,row.unit);
    if(key==='machine')return localName(s.tables.work_centers?.find(x=>x.id===row.work_center_id)||{},lang)||t('notAvailable');
    return t('notAvailable');
  }
  return <section className="production-history" aria-labelledby="production-history-heading" dir={lang==='ar'?'rtl':'ltr'}>
    <h4 id="production-history-heading" className="sr-only">{t('productionHistory')}</h4>
    <div className="history-active-filters">{filterColumns.filter(([key])=>active(key)).map(([key,label])=><button key={key} onClick={()=>clearFilter(key)}>{t(label)} · {t('historyFilterActive')} ×</button>)}{filterColumns.some(([key])=>active(key)) && <button onClick={()=>{setFilters({});setPage(1);}}>{t('historyClear')}</button>}</div>
    <div className="history-v2-tools">
      <button type="button" id={actionsId+'-trigger'} className="history-actions-button" disabled={!selected||busy||!!error||!can('orders','view')} popoverTarget={actionsId} onClick={placeTool} aria-haspopup="menu">{t('historyActions')} ▾</button>
      <div id={actionsId} popover="auto" role="menu" className="history-v2-popover" style={toolStyle} aria-label={t('historyActions')} onToggle={e=>{if((e.nativeEvent as ToggleEvent).newState==='open')e.currentTarget.querySelector<HTMLElement>('button')?.focus();}} onKeyDown={e=>{
        if(!['ArrowDown','ArrowUp','Home','End'].includes(e.key))return;
        const buttons=[...e.currentTarget.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')],index=buttons.indexOf(document.activeElement as HTMLButtonElement);
        const next=e.key==='Home'?0:e.key==='End'?buttons.length-1:(index+(e.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length;
        e.preventDefault();buttons[next]?.focus();
      }}>
        <button role="menuitem" type="button" onClick={()=>{if(!selected||busy||error||!can('orders','view'))return;document.getElementById(actionsId)?.hidePopover();setShowDetails(true);}}>{t('historyViewDetails')}</button>
        {selected&&(can('orders','edit')||can('orders','approve'))&&<button role="menuitem" type="button" onClick={()=>{if(!selected||busy||error||!(can('orders','edit')||can('orders','approve')))return;document.getElementById(actionsId)?.hidePopover();onCorrect(selected);}}>{t('pcRequest')}</button>}
      </div>
      <button type="button" popoverTarget={columnsId} onClick={placeTool} aria-haspopup="dialog">{t('historyColumns')} ▾</button>
      <div id={columnsId} popover="auto" role="dialog" aria-label={t('historyColumns')} style={toolStyle} className="history-v2-popover history-column-chooser">
        <strong>{t('historyColumns')}</strong>
        {historyColumns.filter(([key])=>allowedColumns.includes(key)).map(([key,label])=><label key={key}><input type="checkbox" checked={shown.includes(key)} disabled={shown.length===1&&shown.includes(key)} onChange={e=>saveColumns(e.target.checked?[...shown,key]:shown.filter(x=>x!==key))}/>{t(label)}</label>)}
        <button type="button" onClick={()=>saveColumns(defaultHistoryColumns)}>{t('historyRestoreColumns')}</button>
        <small className="muted">{t('historyColumnScope')}</small>
      </div>
      <button className="history-v2-filter" popoverTarget={popoverId} popoverTargetAction="show" onClick={e=>openMenu('date',e)}>{t('historyFilters')} ▾</button>
      {preferenceError&&<small role="status">{t('historyPreferenceUnavailable')}</small>}
    </div>
    {!selected&&<p className="muted">{t('historySelectRecord')}</p>}
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
      {menu==='date' && <><Field label={t('historyFrom')}><input type="date" value={draft.from || ''} max={draft.to || undefined} onChange={e=>change('from',e.target.value)}/></Field><Field label={t('historyTo')}><input type="date" value={draft.to || ''} min={draft.from || undefined} onChange={e=>change('to',e.target.value)}/></Field></>}
      {['good','scrap','unfinished'].includes(menu) && <>
        <Field label={t('unit')}><select required value={draft.measurement_unit || ''} onChange={e=>change('measurement_unit',e.target.value)}><option value="">{t('historyChooseMeasurementUnit')}</option><option value="meter">{t('meterShort')}</option><option value="piece">{t('pieceShort')}</option><option value="kg">{t('kg')}</option></select></Field>
        {menu==='scrap' && <><Field label={t('historyMetric')}><select value={draft.scrap_metric || 'quantity'} onChange={e=>change('scrap_metric',e.target.value)}><option value="quantity">{t('historyScrapQuantity')}</option><option value="percentage">{t('historyScrapPercentage')}</option></select></Field>
          {draft.scrap_metric==='percentage' && <><Field label={t('historyScope')}><select value={draft.scrap_scope || 'row'} onChange={e=>change('scrap_scope',e.target.value)}><option value="row">{t('historyPerEntry')}</option><option value="shift">{t('historyPerShift')}</option></select></Field><small>{t('historyScrapFormula')}</small></>}</>}
        <Field label={t('historyCondition')}><select value={draft[menu+'_op'] || ''} onChange={e=>change(menu+'_op',e.target.value)}><option value="">{t('all')}</option>{['eq','gte','lte','between'].map(op=><option key={op} value={op}>{t('historyOperator_'+op)}</option>)}</select></Field>
        {draft[menu+'_op'] && <><Field label={t(draft[menu+'_op']==='between'?'historyMinimum':'historyValue')+(menu==='scrap'&&draft.scrap_metric==='percentage'?' (%)':' ('+unit(draft.measurement_unit)+')')}><input type="number" min="0" step="any" value={draft[menu+'_min'] || ''} onChange={e=>change(menu+'_min',e.target.value)}/></Field>{draft[menu+'_op']==='between' && <Field label={t('historyMaximum')}><input type="number" min={draft[menu+'_min'] || 0} step="any" value={draft[menu+'_max'] || ''} onChange={e=>change(menu+'_max',e.target.value)}/></Field>}</>}
      </>}
      {menuError && <p role="alert">{t(menuError)}</p>}
      <div className="row-actions"><button className="primary" onClick={()=>{try{parseHistoryQuery(new URLSearchParams(historyQuery(factory,draft,sort,direction,1)));setFilters(draft);setPage(1);document.getElementById(popoverId)?.hidePopover();}catch(e){setMenuError(e instanceof Error&&e.message==='history_unit_required'?'historyUnitRequired':'historyFilterInvalid');}}}>{t('historyApply')}</button><button onClick={()=>{clearFilter(menu);document.getElementById(popoverId)?.hidePopover();}}>{t('historyClearColumn')}</button></div>
    </div>
    <div className="history-sort-controls"><Field label={t('historySort')}><select value={sort} onChange={e=>{setSort(e.target.value);setPage(1);}}>{[['date','historySubmittedAt'],['good','recordingGood'],['scrap','leanDiscardedLegacy'],['unfinished','unfinishedQuantity'],['unit','recordingUnit'],['technician','recordingTechnician'],['shift','productionShift']].map(([key,label])=><option key={key} value={key}>{t(label)}</option>)}</select></Field>
      <button onClick={()=>{setDirection(x=>x==='desc'?'asc':'desc');setPage(1);}}>{t(direction==='desc'?'historyDescending':'historyAscending')}</button>
      {can('orders')&&<TableExport factory={factory} dataset="production-history" filters={filters} sort={sort} direction={direction} total={result.total} language={lang} t={t} showScope={false} disabled={busy||!loaded||!!error}/>}</div>
    {error && <p role="alert">{t(error)} <button onClick={()=>setRetry(x=>x+1)}>{t('refresh')}</button></p>}
    <p className="history-load-status muted" role="status">{busy?t('historyLoading'):''}</p>
    {loaded && <>
    {!result.rows.length && <p>{t('historyNoMatches')}</p>}
    <div className="history-desktop table-wrap"><table><caption className="sr-only">{t('productionHistory')}</caption><thead><tr>{columns.map(([key,label,filter])=><th key={key} scope="col" aria-sort={filter&&filter===sort?(direction==='asc'?'ascending':'descending'):undefined}>{t(label)}{filter&&filterColumns.some(([k])=>k===filter)&&<button type="button" className="history-filter-arrow" aria-label={t('historyFilterColumn')+' '+t(label)} aria-haspopup="dialog" popoverTarget={popoverId} popoverTargetAction="show" onClick={e=>openMenu(filter,e)}>{active(filter)?'● ':''}▾</button>}</th>)}</tr></thead>
      <tbody>{result.rows.map((row,index)=><tr key={String(row.id)} id={'history-row-'+String(row.id)} tabIndex={0} aria-selected={selected?.id===row.id} className={selected?.id===row.id?'history-row-selected':''} {...detailsRow(()=>selectRow(row),()=>setShowDetails(true),busy||!!error||!can('orders','view'))} onKeyDown={e=>rowKey(e,result.rows,index,'history-row-')}>
        {columns.map(([key])=><td key={key} dir="auto" className={['good','scrap','wip'].includes(key)?'history-number':''}>{cell(row,key)}</td>)}
      </tr>)}</tbody></table></div>
    <div className="history-mobile" role="listbox" aria-label={t('productionHistory')} aria-multiselectable={false}>{result.rows.map((row,index)=><article key={String(row.id)} id={'history-card-'+String(row.id)} role="option" tabIndex={0} aria-selected={selected?.id===row.id} className={selected?.id===row.id?'history-row-selected':''} {...detailsRow(()=>selectRow(row),()=>setShowDetails(true),busy||!!error||!can('orders','view'))} onKeyDown={e=>rowKey(e,result.rows,index,'history-card-')}>
      <dl>{columns.map(([key,label])=><div key={key}><dt>{t(label)}</dt><dd>{cell(row,key)}</dd></div>)}</dl>
    </article>)}</div>
    <nav className="history-pagination" aria-label={t('historyPages')}><button disabled={busy || page<=1} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{t('historyRecords')}: {q(result.total)} · {q(page)} / {q(Math.max(1,Math.ceil(result.total/50)))}</span><button disabled={busy || page*50>=result.total} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav></>}
    {showDetails&&selected&&can('orders','view')&&<Dialog title={t('historyViewDetails')} t={t} onClose={()=>{setShowDetails(false);setTimeout(()=>document.getElementById(actionsId+'-trigger')?.focus(),0);}} className="history-v2-details" headerActions={onLanguageChange&&<button type="button" onClick={onLanguageChange}>{lang==='ar'?'English':'العربية'}</button>}>
      <div className="history-details-body"><header><strong><bdi>{String(selected.request_code||selected.item_code||'')}</bdi></strong>{selected.item_code&&selected.item_code!==selected.request_code&&<p className="muted"><bdi>{String(selected.item_code)}</bdi></p>}<p>{name(selected,'product')}</p></header>
      <dl className="history-operational-details">
        <div><dt>{t('historyTotalAtEntry')}</dt><dd><bdi>{quantity(selected.running_good,selected.unit)}</bdi></dd></div>
        <div><dt>{t('historyRemainingAtEntry')}</dt><dd><bdi>{quantity(selected.remaining_quantity,selected.unit)}</bdi></dd></div>
        <div><dt>{t('historyResponsible')}</dt><dd>{String(selected.technician_name||t('notAvailable'))}</dd></div>
        <div><dt>{t('recordingSubmittedBy')}</dt><dd>{String(selected.submitter_name||t('notAvailable'))}</dd></div>
        <div><dt>{t('historyWipAtEntry')}</dt><dd>{selected.effective_unfinished==null?t('notAvailable'):Number(selected.effective_unfinished)===0?t('historyNone'):quantity(selected.effective_unfinished,selected.unit)}</dd></div>
        <div><dt>{t('historyOrderScrap')}</dt><dd><bdi>{scrapTotal?.key!==scrapKey?t('historyLoading'):quantity(scrapTotal.value,'kg')}</bdi></dd></div>
      </dl>
      {scrapTotal?.key===scrapKey&&scrapTotal.value===null&&<p className="muted" role="status">{t('historyOrderScrapUnavailable')}{scrapTotal.failed&&<button onClick={()=>setRetry(x=>x+1)}>{t('refresh')}</button>}</p>}
      <ManufacturedOutput snapshot={s} t={t} lang={lang} can={can} command={command} entry={String(selected.id)} onOutputRelated={onOutputRelated} onLanguageChange={onLanguageChange}/>
      {Array.isArray(selected.corrections)&&selected.corrections.length>0&&auditDetails(selected)}</div>
    </Dialog>}
  </section>;
}
