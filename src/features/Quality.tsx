import {useTableDetails} from '@/components/useTableDetails';
import {useEffect,useId,useState,type ReactNode} from 'react';
import TableExport from '@/components/TableExport';
import {Dialog,Field,formatTime} from '@/components/ui';
import {qualityScrapState} from '@/utils/quality-ui.mjs';
import {defaultQualityColumns,qualityColumns,qualityPreferenceKey,qualityVisibleColumns,rejectionExceeded,shiftProduction} from '@/utils/quality-view.mjs';
import type {FeatureProps} from './types';
import {useSupply,useSupplyCommand,type SupplyRow} from './useSupply';
import {decimalCompare,decimalSubtract,quantityValid,scrapWeight} from '@/utils/quality-quantities.mjs';
import './quality-v2.css';
import ManufacturedOutput from './ManufacturedOutput';
const text=(value:unknown)=>String(value??'—');
const named=(row:SupplyRow,lang:string,key:string)=>text(lang==='ar'?row[key+'_ar']||row[key]:row[key]);
function QualityDialog(props:FeatureProps&{title:string;busy?:boolean;onClose:()=>void;children:ReactNode}){
 return <Dialog title={props.title} busy={props.busy} onClose={props.onClose} t={props.t} className="prv3-dialog quality-v2-dialog" headerActions={props.onLanguageChange&&<button type="button" className="prv3-language" onClick={props.onLanguageChange}>{props.lang==='ar'?'English':'العربية'}</button>}><div className="prv3-body quality-v2-body" dir={props.lang==='ar'?'rtl':'ltr'}>{props.children}</div></Dialog>;
}
function QualityFilter({rows,value,onChange,label,lang,t}: {rows:SupplyRow[];value:string;onChange:(v:string)=>void;label:string;lang:string;t:FeatureProps['t']}){
 const id=useId(),[open,setOpen]=useState(false),[query,setQuery]=useState(''),[index,setIndex]=useState(-1);
 const selected=rows.find(r=>r.id===value),options=rows.filter(r=>!query||[r.name,r.name_ar].some(v=>String(v||'').toLowerCase().includes(query.toLowerCase())));
 function choose(v:string){onChange(v);setQuery('');setOpen(false);setIndex(-1);}
 return <div className="quality-picker" onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget as Node|null))setOpen(false);}}><Field label={label}><input role="combobox" aria-expanded={open} aria-controls={id} aria-autocomplete="list" aria-activedescendant={open&&index>=0?id+'-'+index:undefined} value={open?query:selected?named(selected,lang,'name'):''} placeholder={t('all')} onFocus={()=>{setOpen(true);setQuery('');}} onClick={()=>setOpen(true)} onChange={e=>{setQuery(e.target.value);setOpen(true);setIndex(-1);}} onKeyDown={e=>{if(e.key==='Escape'){if(open){e.preventDefault();e.stopPropagation();}setOpen(false);}else if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);setIndex(i=>(i+(e.key==='ArrowDown'?1:-1)+options.length+1)%(options.length+1));}else if(e.key==='Enter'&&open){e.preventDefault();if(index>=0)choose(index===0?'':text(options[index-1]?.id));}}}/></Field>
 {open&&<div className="quality-picker-options" id={id} role="listbox" aria-label={label}>{[null,...options].map((r,i)=><button type="button" role="option" id={id+'-'+i} key={r?text(r.id):'all'} aria-selected={r?r.id===value:!value} data-active={index===i} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(r?text(r.id):'')}>{r?named(r,lang,'name'):t('all')}</button>)}</div>}</div>;
}
export default function Quality(props:FeatureProps){return <section className="quality-page" dir={props.lang==='ar'?'rtl':'ltr'}><ManufacturedOutput {...props}/><button onClick={()=>props.onProductionHistoryOpen?.('quality')}>{props.lang==='ar'?'سجل الإنتاج وقرارات الجودة':'Production History & Quality decisions'}</button></section>;}
// Historical stock rejection lookup lives only in Production History.
export function QualityHistoryLookup(props:FeatureProps){
 const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||''),scope=qualityPreferenceKey(s.user.id,factory),detailsRow=useTableDetails(),actionsId=useId(),columnsId=useId();
 const [selection,setSelection]=useState(''),[page,setPage]=useState(1),[filters,setFilters]=useState<Record<string,string>>({}),[reject,setReject]=useState<SupplyRow|null>(null),[history,setHistory]=useState<SupplyRow|null>(null),[manage,setManage]=useState(false);
 const [preference,setPreference]=useState<{scope:string|null;columns:string[]}>({scope:null,columns:defaultQualityColumns});
 const shown=qualityVisibleColumns(preference.scope===scope?preference.columns:null);
 useEffect(()=>{let columns=defaultQualityColumns;if(scope)try{columns=qualityVisibleColumns(JSON.parse(localStorage.getItem(scope)||'null'));}catch{}setPreference({scope,columns});setSelection('');},[scope]);
 function saveColumns(columns:string[]){const valid=qualityVisibleColumns(columns);setPreference({scope,columns:valid});if(scope)try{localStorage.setItem(scope,JSON.stringify(valid));}catch{}}
 const read=useSupply<{rows:SupplyRow[];total:number}>(s,'board',{page:String(page),...filters},can('quality'),'/api/quality');
 const options=useSupply<{products:SupplyRow[];lines:SupplyRow[];shifts:SupplyRow[]}>(s,'filters',{},can('quality'),'/api/quality');
 const selected=read.data?.rows.find(row=>row.id===selection),unavailable=read.busy||!!read.error||!selected;
 function filter(key:string,value:string){setFilters(old=>({...old,[key]:value}));setPage(1);setSelection('');}
 function placePopover(event:React.MouseEvent<HTMLButtonElement>,id:string){const box=event.currentTarget.getBoundingClientRect(),node=document.getElementById(id);if(node)Object.assign(node.style,{position:'fixed',inset:'auto',margin:'0',top:Math.max(16,Math.min(box.bottom+8,innerHeight-300))+'px',left:Math.max(16,Math.min(box.left,innerWidth-316))+'px'});}
 function closeMenu(){document.getElementById(actionsId)?.hidePopover();}
 function cell(row:SupplyRow,key:string):ReactNode{
  if(key==='shift')return <>{text(row.shift_date||t('qualityShiftDateUnknown'))}<small>{row.shift_name?named(row,lang,'shift_name'):t('shiftNotRecorded')}</small></>;
  if(key==='order')return <><bdi>{text(row.request_code||row.item_code)}</bdi><small><bdi>{text(row.item_code)}</bdi></small><small>{text(row.physical_label||t('sourceNotIdentified'))}</small></>;
  if(key==='product')return named(row,lang,'product_name');if(key==='line')return named(row,lang,'line_name');
  if(key==='production')return <>{shiftProduction(row)??t('notAvailable')}{shiftProduction(row)!==null&&<> {t(text(row.unit))}</>}</>;
  if(key==='rejected')return <>{text(row.rejected)} {t(text(row.unit))}</>;
  if(key==='alert'){const state=qualityScrapState(row.scrap);return state.high?<span className="qv-alert">⚠ {t('qualityHighScrap')}</span>:state.status==='MISSING_STANDARD'?<span className="qv-alert">{t('qualityStandardMissing')}</span>:state.status==='MISSING_DATA'?<span className="qv-alert">{t('qualityCalculationUnavailable')}</span>:'—';}
  if(key==='calculation')return <QualityScrapIndicator t={t} lang={lang} input={row.scrap}/>;
  if(key==='source')return text(row.physical_label||t('sourceNotIdentified'));
  return <>{text(row[key==='accepted'?'accepted':key==='recorded'?'recorded_good':'current_good'])} {t(text(row.unit))}</>;
 }
 return <section className="quality-page quality-v2" dir={lang==='ar'?'rtl':'ltr'}>
  <header className="section-head"><div><h2 className="sr-only">{t('quality')}</h2><p>{t('qvIntro')}</p></div><div className="row-actions"><button onClick={read.refresh}>{t('refresh')}</button>{can('quality_reasons','edit')&&<button onClick={()=>setManage(true)}>{t('qualityManageReasons')}</button>}</div></header>
  <div className="quality-filters"><Field label={t('qualityShiftDate')}><input type="date" value={filters.date||''} onChange={e=>filter('date',e.target.value)}/></Field>
   <QualityFilter label={t('product')} rows={options.data?.products||[]} value={filters.product||''} onChange={v=>filter('product',v)} lang={lang} t={t}/>
   <Field label={t('productionOrder')}><input type="search" maxLength={100} value={filters.order||''} onChange={e=>filter('order',e.target.value)}/></Field>
   <QualityFilter label={t('line')} rows={options.data?.lines||[]} value={filters.line||''} onChange={v=>filter('line',v)} lang={lang} t={t}/>
   <QualityFilter label={t('productionShift')} rows={options.data?.shifts||[]} value={filters.shift||''} onChange={v=>filter('shift',v)} lang={lang} t={t}/>
  </div>
  <div className="quality-toolbar"><button type="button" className="quality-actions-button" popoverTarget={actionsId} onClick={e=>placePopover(e,actionsId)} disabled={unavailable} aria-haspopup="menu">{t('historyActions')} ▾</button>
   <div id={actionsId} popover="auto" className="quality-popover" role="menu" aria-label={t('historyActions')} onToggle={e=>{if((e.nativeEvent as ToggleEvent).newState==='open')e.currentTarget.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus();}} onKeyDown={e=>{if(!['ArrowDown','ArrowUp','Home','End'].includes(e.key))return;const buttons=[...e.currentTarget.querySelectorAll<HTMLButtonElement>('button:not(:disabled)')],i=buttons.indexOf(document.activeElement as HTMLButtonElement);e.preventDefault();buttons[e.key==='Home'?0:e.key==='End'?buttons.length-1:(i+(e.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length]?.focus();}}>
    {can('quality','create')&&<button role="menuitem" disabled={unavailable||decimalCompare(selected?.eligible,'0')!==1||!selected?.physical_label} onClick={()=>{if(selected&&!unavailable){closeMenu();setReject(selected);}}}>{t('qualityRecordRejection')}</button>}
    {can('quality_history')&&<button role="menuitem" disabled={unavailable} onClick={()=>{if(selected&&!unavailable){closeMenu();setHistory(selected);}}}>{t('qualityHistory')}</button>}
   </div>
   <button type="button" popoverTarget={columnsId} onClick={e=>placePopover(e,columnsId)}>{t('historyColumns')} ▾</button><div id={columnsId} popover="auto" className="quality-popover quality-columns" role="dialog" aria-label={t('historyColumns')}>
    {qualityColumns.map(([key,label])=><label key={key}><input type="checkbox" checked={shown.includes(key)} disabled={shown.length===1&&shown.includes(key)} onChange={e=>saveColumns(e.target.checked?[...shown,key]:shown.filter(x=>x!==key))}/>{t(label)}</label>)}<button onClick={()=>saveColumns(defaultQualityColumns)}>{t('historyRestoreColumns')}</button><small>{t('historyColumnScope')}</small>
   </div>
   {can('quality')&&<TableExport factory={factory} dataset="quality-production" filters={filters} total={read.data?.total||0} language={lang} t={t} disabled={read.busy||!!read.error||!read.data}/>}
  </div>
  {selected&&(!selected.physical_label||decimalCompare(selected.eligible,'0')!==1)&&<p role="status" className="qv-warning">{t(!selected.physical_label?'sourceNotIdentified':'qvNoStock')}</p>}
  {read.error&&<p role="alert">{t(read.error)}</p>}{read.busy&&<p role="status">{t('loading')}</p>}
  <div className="quality-table-wrap"><table className="quality-table"><caption>{t('qvCaption')}</caption><thead><tr>{qualityColumns.filter(([key])=>shown.includes(key)).map(([key,label])=><th scope="col" key={key}>{t(label)}</th>)}</tr></thead><tbody>
   {read.data?.rows.map(row=><tr key={text(row.id)} id={'quality-row-'+row.id} tabIndex={0} aria-selected={selection===row.id} {...detailsRow(()=>setSelection(text(row.id)),()=>{if(can('quality_history'))setHistory(row);},read.busy||!!read.error)}>{qualityColumns.filter(([key])=>shown.includes(key)).map(([key,label])=><td key={key} data-label={t(label)}>{cell(row,key)}</td>)}</tr>)}
  </tbody></table></div>
  {!read.busy&&!read.error&&!read.data?.rows.length&&<p className="empty">{t('noResults')}</p>}
  <nav className="fulfillment-pagination" aria-label={t('quality')}><button disabled={page===1||read.busy} onClick={()=>{setPage(p=>p-1);setSelection('');}}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>{setPage(p=>p+1);setSelection('');}}>{t('next')}</button></nav>
  {reject&&<RejectionDrawer {...props} row={reject} onClose={()=>setReject(null)} onChanged={()=>{read.refresh();setReject(null);}}/>}
  {history&&<QualityHistory {...props} entry={text(history.id)} context={history} onClose={()=>setHistory(null)}/>}
  {manage&&<ManageReasons {...props} onClose={()=>setManage(false)}/>}
 </section>;
}
export function QualityScrapIndicator({t,lang,input}:{t:FeatureProps['t'];lang:string;input?:unknown}){
 const state=qualityScrapState(input);
 const number=(value:number)=>new Intl.NumberFormat(lang,{maximumFractionDigits:2}).format(value);
 return <span className={state.high?'quality-scrap-indicator high-scrap':'quality-scrap-indicator'}>
  {state.rate!==null&&<span>{t('qualityActualScrapRate')}: <bdi>{number(state.rate)}%</bdi></span>}
  {state.status==='MISSING_STANDARD'?<small>{t('qualityStandardMissing')}</small>:state.status==='MISSING_DATA'?<small>{t('qualityCalculationUnavailable')}</small>:<>
   <small>{t('qualityAdjustedScrapRate')}: <bdi>{number(state.adjustedRate!)}%</bdi> · {t('qualityNormalScrapRate')}: <bdi>{number(state.standard!)}%</bdi></small>
   <small>{t('qualityScrapAllowance')}: <bdi>{number(state.expectedKg!)} kg</bdi>{state.startupAllowanceKg!>0&&<> · {t('qualityStartupAllowance')}: <bdi>{number(state.startupAllowanceKg!)} kg</bdi></>}</small>
   {state.excessKg!>0&&<small>{t('qualityExcessScrap')}: <bdi>{number(state.excessKg!)} kg</bdi></small>}
   {state.startupExcessKg!>0&&<small>{t('qualityStartupExcess')}: <bdi>{number(state.startupExcessKg!)} kg</bdi></small>}
  </>}
  {state.high&&<small><span aria-hidden="true">⚠ </span>{t('qualityHighScrap')}</small>}
 </span>;
}
export function RejectionDrawer(props:FeatureProps&{row:SupplyRow;onClose:()=>void;onChanged:()=>void}){
 const {snapshot:s,t,lang,can}=props;
 const eligibility=useSupply(s,'board',{entry:text(props.row.id)},true,'/api/quality');
 const row=eligibility.data?.rows.find(r=>r.id===props.row.id)||(eligibility.data?{...props.row,eligible:'0'}:props.row);
 const [quantity,setQuantity]=useState(''),[reason,setReason]=useState(''),[disposition,setDisposition]=useState('SCRAP'),[actualKg,setActualKg]=useState(''),[weightEdited,setWeightEdited]=useState(false),[description,setDescription]=useState(''),[approved,setApproved]=useState(false),[note,setNote]=useState(''),[physical,setPhysical]=useState(false);
 const [reasonPage,setReasonPage]=useState(1),[reasonSearch,setReasonSearch]=useState(''),[reasonOpen,setReasonOpen]=useState(false),[reasonIndex,setReasonIndex]=useState(-1),[reasonLabel,setReasonLabel]=useState('');
 const reasons=useSupply(s,'reasons',{active_only:'true',page:String(reasonPage),search:reasonSearch,...(reason?{selected:reason}:{})},true,'/api/quality'),action=useSupplyCommand(props.command,s.factory?.id,'quality_command');
 const reasonOptions=(reasons.data?.rows||[]).filter(r=>r.active===true);
 const reasonListId='quality-reasons-'+text(props.row.id);
 function chooseReason(choice:SupplyRow){setReason(text(choice.id));setReasonLabel(named(choice,lang,'name'));setApproved(false);if(choice.is_other&&reasonSearch.trim())setDescription(reasonSearch);setReasonSearch('');setReasonOpen(false);setReasonIndex(-1);}
 const selectedReason=reasons.data?.rows.find(r=>r.id===reason),weight=scrapWeight(quantity,text(row.unit),row.weight_kg_per_unit,actualKg);
 const exceeded=rejectionExceeded(quantity,row.eligible);
 const kg=weightEdited?actualKg:weight.defaultKg||'',valid=!!eligibility.data&&!eligibility.busy&&!eligibility.error&&!reasons.busy&&!reasons.error&&quantityValid(quantity,text(row.unit),row.eligible)&&physical&&!!selectedReason&&(!selectedReason.is_other||description.trim().length>=3)&&
  (disposition==='REWORK'||scrapWeight(quantity,text(row.unit),row.weight_kg_per_unit,kg).valid);
 return <QualityDialog {...props} busy={action.busy} title={t('qualityRecordRejection')} t={t} onClose={()=>{if(!action.busy)props.onClose();}}>
  <section className="quality-drawer" dir={lang==='ar'?'rtl':'ltr'}>
   <button disabled={action.busy||eligibility.busy} onClick={eligibility.refresh}>{t('refresh')}</button>{eligibility.error&&<p role="alert">{t(eligibility.error)}</p>}
   <dl className="quality-context"><div><dt>{t('productionOrder')}</dt><dd><bdi>{text(row.request_code)} · {text(row.item_code)}</bdi></dd></div><div><dt>{t('product')}</dt><dd>{named(row,lang,'product_name')} · <bdi>{text(row.product_code)}</bdi></dd></div><div><dt>{t('line')}</dt><dd>{named(row,lang,'line_name')}</dd></div><div><dt>{t('productionShift')}</dt><dd>{row.shift_name?named(row,lang,'shift_name'):t('shiftNotRecorded')} · {row.shift_date?text(row.shift_date):t('qualityShiftDateUnknown')}</dd></div><div><dt>{t('sourceLabel')}</dt><dd>{text(row.physical_label)}</dd></div><div><dt>{t('qualityEligible')}</dt><dd>{text(row.eligible)} {t(text(row.unit))}</dd></div></dl>
   <p>{t('qvProduction')}: <strong>{shiftProduction(row)??t('notAvailable')} {shiftProduction(row)!==null?t(text(row.unit)):''}</strong></p><p className="qv-warning">{t('qvAvailable')}: <strong>{text(row.eligible)} {t(text(row.unit))}</strong></p>
   <form onSubmit={async e=>{e.preventDefault();if(!valid)return;if(await action.run('reject',{source:row.source_id,quantity,reason,disposition,actual_scrap_kg:disposition==='SCRAP'?kg:null,
    ...(selectedReason?.is_other?{description,approve_reason:approved}:{}),note,physically_identified:physical}))props.onChanged();else eligibility.refresh();}}><fieldset disabled={action.busy}>
    {exceeded&&<p role="alert" className="qv-warning">{t('qvExceeds')}</p>}<div className="form-grid"><Field label={`${t('qualityRejected')} (${t(text(row.unit))})`}><input required type="number" inputMode="decimal" min="0" step={row.unit==='piece'?'1':'any'} value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
     <Field label={t('qualityDisposition')}><select value={disposition} onChange={e=>setDisposition(e.target.value)}><option value="SCRAP">{t('qualityScrap')}</option><option value="REWORK">{t('qualityRework')}</option></select></Field></div>
    <div className="quality-reason-combobox" onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget as Node|null)){setReasonOpen(false);setReasonIndex(-1);}}}>
     <Field label={t('qualityRejectionReason')}><input role="combobox" aria-autocomplete="list" aria-expanded={reasonOpen} aria-controls={reasonListId} aria-activedescendant={reasonOpen&&reasonIndex>=0?reasonListId+'-'+reasonIndex:undefined} aria-invalid={!!reasonSearch&&!reason||!!reason&&!!reasons.data&&!selectedReason} aria-describedby={reasonListId+'-help'} autoComplete="off" maxLength={120} value={reason?(selectedReason?named(selectedReason,lang,'name'):reasonLabel):reasonSearch}
      onFocus={()=>setReasonOpen(true)} onClick={()=>setReasonOpen(true)} onChange={e=>{setReasonSearch(e.target.value);setReason('');setReasonLabel('');setApproved(false);setReasonPage(1);setReasonIndex(-1);setReasonOpen(true);}}
      onKeyDown={e=>{if(e.key==='Escape'){if(reasonOpen){e.preventDefault();e.stopPropagation();}setReasonOpen(false);setReasonIndex(-1);}
       else if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setReasonOpen(true);const next=reasonOptions.length?(reasonIndex<0?(e.key==='ArrowDown'?0:reasonOptions.length-1):(reasonIndex+(e.key==='ArrowDown'?1:-1)+reasonOptions.length)%reasonOptions.length):-1;setReasonIndex(next);if(next>=0)e.currentTarget.ownerDocument.getElementById(reasonListId+'-'+next)?.scrollIntoView({block:'nearest'});}
       else if(e.key==='Enter'&&reasonOpen){e.preventDefault();if(!reasons.busy&&!reasons.error&&reasonIndex>=0&&reasonOptions[reasonIndex])chooseReason(reasonOptions[reasonIndex]);}
       else if(e.key==='Tab'){setReasonOpen(false);setReasonIndex(-1);}}}/></Field>
     <small id={reasonListId+'-help'} className="muted">{t(reasonSearch&&!reason||reason&&reasons.data&&!selectedReason?'qualityReasonChooseMatch':'qualityReasonInputHelp')}</small>
     {reasonOpen&&<div className="quality-reason-dropdown">
      {reasons.busy&&<p role="status">{t('loading')}</p>}{reasons.error&&<p role="alert">{t(reasons.error)} <button type="button" onClick={reasons.refresh}>{t('refresh')}</button></p>}
      <div id={reasonListId} role="listbox" aria-label={t('qualityRejectionReason')} aria-busy={reasons.busy}>
       {!reasons.busy&&!reasons.error&&reasonOptions.map((choice,index)=><button type="button" role="option" tabIndex={-1} id={reasonListId+'-'+index} key={text(choice.id)} aria-selected={choice.id===reason} data-active={index===reasonIndex} onMouseDown={e=>e.preventDefault()} onClick={()=>chooseReason(choice)}>{choice.is_other&&reasonSearch.trim()?t('qualityUseAsOther')+': '+reasonSearch:named(choice,lang,'name')}</button>)}
      </div>
      {!reasons.busy&&!reasons.error&&!reasonOptions.some(r=>!r.is_other)&&<p role="status">{t('noResults')}</p>}
      <nav className="fulfillment-pagination" aria-label={t('qualityRejectionReason')}><button type="button" disabled={reasonPage===1||reasons.busy} onClick={()=>{setReasonPage(p=>p-1);setReasonIndex(-1);}}>{t('previous')}</button><span>{reasonPage}</span><button type="button" disabled={reasons.busy||reasonPage*100>=(reasons.data?.total||0)} onClick={()=>{setReasonPage(p=>p+1);setReasonIndex(-1);}}>{t('next')}</button></nav>
     </div>}
    </div>
    {selectedReason?.is_other===true&&<><Field label={t('qualityOtherDescription')}><textarea required minLength={3} maxLength={120} value={description} onChange={e=>setDescription(e.target.value)}/></Field>{can('quality_reasons','edit')&&<label className="recording-confirm"><input type="checkbox" checked={approved} onChange={e=>setApproved(e.target.checked)}/>{t('qualityApproveReason')}</label>}</>}
    {disposition==='SCRAP'&&<><p>{t('qualityDefaultKg')}: <strong>{weight.defaultKg===null?(decimalCompare(row.weight_kg_per_unit,'0')===1?'—':t('qualityWeightMissing')):weight.defaultKg+' kg'}</strong>{weight.defaultKg!==null&&<small> · {quantity} × {text(row.weight_kg_per_unit)} kg/{t(text(row.unit))}</small>}</p>
     <Field label={t('qualityActualKg')}><input required type="number" min="0" step="any" inputMode="decimal" value={kg} onChange={e=>{setActualKg(e.target.value);setWeightEdited(true);}}/></Field>{weightEdited&&weight.defaultKg!==null&&<button type="button" onClick={()=>setWeightEdited(false)}>{t('qualityUseDefault')}</button>}</>}
    <details className="prv3-details"><summary>{t('notes')}</summary><Field label={t('notes')}><textarea maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></Field></details>
    <label className="recording-confirm"><input type="checkbox" checked={physical} onChange={e=>setPhysical(e.target.checked)}/>{t('sourcePhysicalConfirm')} · <strong>{text(row.physical_label)}</strong></label>
    {quantityValid(quantity,text(row.unit),row.eligible)&&<section className="quality-confirm" aria-live="polite"><h3>{t('qualityStockEffect')}</h3><p>{t('qualityAccepted')}: {text(row.accepted)} → {decimalSubtract(row.accepted,quantity)} {t(text(row.unit))}</p><p>{t('qualitySourceRemaining')}: {text(row.eligible)} → {decimalSubtract(row.eligible,quantity)} {t(text(row.unit))}</p><p>{disposition==='SCRAP'?`${t('qualityScrap')}: +${kg||'—'} kg`:`${t('qualityRework')}: +${quantity} ${t(text(row.unit))}`}</p><p className="muted">{t(disposition==='SCRAP'?'qualityScrapEffect':'qualityReworkEffect')}</p></section>}
    {action.error&&<p role="alert">{t(action.error)}</p>}
    <div className="row-actions"><button type="button" onClick={props.onClose}>{t('cancel')}</button><button className="primary" disabled={!valid}>{t('qualityConfirmRejection')}</button></div>
   </fieldset></form>
  </section>
 </QualityDialog>;
}
function ManageReasons(props:FeatureProps&{onClose:()=>void}){
 const {snapshot:s,t,lang}=props;const [page,setPage]=useState(1),[editing,setEditing]=useState<SupplyRow|null>(null),[name,setName]=useState(''),[nameAr,setNameAr]=useState(''),[active,setActive]=useState(true);
 const read=useSupply(s,'reasons',{page:String(page)},true,'/api/quality'),action=useSupplyCommand(props.command,s.factory?.id,'quality_command');
 return <QualityDialog {...props} busy={action.busy} title={t('qualityManageReasons')} t={t} onClose={()=>{if(!action.busy)props.onClose();}}>
  <p className="muted">{t('qualityReasonHistoryHelp')}</p><div className="quality-reason-list">{read.data?.rows.map(row=><button key={text(row.id)} onClick={()=>{setEditing(row);setName(text(row.name));setNameAr(String(row.name_ar||''));setActive(row.active===true);action.clearError();}}>{named(row,lang,'name')} · {t(row.active?'active':'archived')}</button>)}</div>
  <div className="row-actions"><button disabled={page===1||read.busy} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||(read.data?.rows.length||0)<100} onClick={()=>setPage(p=>p+1)}>{t('next')}</button><button onClick={()=>{setEditing(null);setName('');setNameAr('');setActive(true);action.clearError();}}>{t('qualityNewReason')}</button></div>
  {read.error&&<p role="alert">{t(read.error)}</p>}
  <form onSubmit={async e=>{e.preventDefault();if(await action.run('reason',{...(editing?{id:editing.id}:{}),name,name_ar:nameAr,active})){read.refresh();setEditing(null);setName('');setNameAr('');}}}><fieldset disabled={action.busy}>
   <Field label={t('nameEn')}><input required maxLength={120} value={name} onChange={e=>setName(e.target.value)}/></Field><Field label={t('nameAr')}><input maxLength={120} dir="rtl" value={nameAr} onChange={e=>setNameAr(e.target.value)}/></Field>
   {editing&&<label className="recording-confirm"><input type="checkbox" disabled={editing.is_other===true} checked={active} onChange={e=>setActive(e.target.checked)}/>{t('active')}</label>}
   {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary">{t('save')}</button>
  </fieldset></form>
 </QualityDialog>;
}
function QualityHistory(props:FeatureProps&{entry:string;context?:SupplyRow;onClose:()=>void}){
 const {snapshot:s,t}=props;const [page,setPage]=useState(1),[detail,setDetail]=useState<string|null>(null),read=useSupply(s,'history',{entry:props.entry,page:String(page)},true,'/api/quality');
 if(detail)return <QualityDetail {...props} rejection={detail} onClose={()=>setDetail(null)} onChanged={read.refresh}/>;
 return <QualityDialog {...props} title={t('qualityHistory')} t={t} onClose={props.onClose}>
  {props.context&&<section className="qv-context"><strong>{named(props.context,props.lang,'product_name')} · <bdi>{text(props.context.request_code)} / {text(props.context.item_code)}</bdi></strong><p>{named(props.context,props.lang,'line_name')} · {text(props.context.shift_date)} · {named(props.context,props.lang,'shift_name')}</p><p>{t('qvProduction')}: {shiftProduction(props.context)??t('notAvailable')} {t(text(props.context.unit))}</p><p>{t('qualityAccepted')}: {text(props.context.accepted)} · {t('qualityRejected')}: {text(props.context.rejected)} {t(text(props.context.unit))}</p><details><summary>{t('qvCalculation')}</summary><QualityScrapIndicator t={t} lang={props.lang} input={props.context.scrap}/><p>{t('qualityRecorded')}: {text(props.context.recorded_good)} {t(text(props.context.unit))}</p></details></section>}
  {props.can('quality_history')&&<TableExport factory={String(s.factory?.id||'')} dataset="quality-history" filters={{entry:props.entry}} total={read.data?.total||0} language={props.lang} t={t} disabled={read.busy||!!read.error||!read.data}/>}
  {read.error&&<p role="alert">{t(read.error)}</p>}{read.busy&&<p role="status">{t('loading')}</p>}
  {!read.busy&&!read.data?.rows.length&&<p>{t('noResults')}</p>}
  {read.data?.rows.map(row=><article className="quality-history-row" key={text(row.id)}><strong>{text(row.quantity)} {t(text(row.unit))} · {t(row.disposition==='SCRAP'?'qualityScrap':'qualityRework')}</strong><p>{named(row,props.lang,'reason')} · {formatTime(row.created_at,props.lang,String(s.factory?.timezone||'UTC'))}</p><button onClick={()=>setDetail(text(row.id))}>{t('open')}</button></article>)}
  <nav className="fulfillment-pagination"><button disabled={page===1||read.busy} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></nav>
 </QualityDialog>;
}
export function QualityDetail(props:FeatureProps&{rejection:string;onClose:()=>void;onChanged?:()=>void;onPlanItem?:(id:string)=>void}){
 const {snapshot:s,t,lang,can}=props,read=useSupply<SupplyRow>(s,'detail',{rejection:props.rejection},true,'/api/quality'),row=read.data;
 const action=useSupplyCommand(props.command,s.factory?.id,'quality_command');
 const [quantity,setQuantity]=useState(''),[lot,setLot]=useState(''),[reverse,setReverse]=useState(false),[reason,setReason]=useState(''),[physical,setPhysical]=useState(false),[created,setCreated]=useState(''),[followUp,setFollowUp]=useState('');
 const lots=(row?.lots||[]) as SupplyRow[],rework=(row?.rework||[]) as SupplyRow[],selected=lots.find(l=>l.id===lot);
 async function run(operation:string,payload:Record<string,unknown>,onSuccess?:(id:unknown)=>void){if(await action.run(operation,{rejection:props.rejection,...payload},onSuccess)){read.refresh();props.onChanged?.();}}
 return <QualityDialog {...props} busy={action.busy} title={t('qualityHistory')} t={t} onClose={()=>{if(!action.busy)props.onClose();}}>
  {read.error&&<p role="alert">{t(read.error)}</p>}{read.busy&&<p role="status">{t('loading')}</p>}
  {row&&<section className="quality-detail" dir={lang==='ar'?'rtl':'ltr'}><strong><bdi>{text(row.request_code)} · {text(row.item_code)}</bdi></strong><p>{named(row,lang,'product_name')} · {named(row,lang,'line_name')} · {row.shift_name?named(row,lang,'shift_name'):t('shiftNotRecorded')} · {row.shift_date?text(row.shift_date):t('qualityShiftDateUnknown')}</p>
   <p>{t('qualityRejected')}: <strong>{text(row.quantity)} {t(text(row.unit))}</strong> · {t(row.disposition==='SCRAP'?'qualityScrap':'qualityRework')}</p><p>{named(row,lang,'reason')}{row.description?': '+text(row.description):''}</p>
   {row.disposition==='SCRAP'&&<p>{t('qualityDefaultKg')}: {text(row.default_scrap_kg)} kg · {t('qualityActualKg')}: <strong>{text(row.actual_scrap_kg)} kg</strong></p>}
   <p>{t('sourceLabel')}: {text(row.physical_label)}</p><p>{text(row.note)}</p><p>{t('qualityActor')}: {text(row.actor_name)} · {formatTime(row.created_at,lang,String(s.factory?.timezone||'UTC'))}</p><p>{t('qualityShortfallLabel')}: <strong>{text(row.shortfall)} {t(text(row.unit))}</strong></p>
   <p>{t('qualityStatus_'+text((row.notification as SupplyRow|undefined)?.status))}</p>
   {!!lots.length&&<section><h3>{t('qualityReservedLots')}</h3><p className="muted">{t('qualityReservedHelp')}</p>{lots.map(l=><p key={text(l.id)}>{text(l.remaining_work)} · {t('quantity')}: {text(l.quantity_available)} {t(text(row.unit))} · {t('warehouse')}: {text(l.warehouse_quantity)} {t(text(row.unit))} · {t('qualityFloor')}: {decimalSubtract(l.quantity_available,l.warehouse_quantity)} {t(text(row.unit))}</p>)}</section>}
   {!!rework.length&&<section><h3>{t('qualityReworkResults')}</h3>{rework.map((e,index)=><p key={index}>{formatTime(e.created_at,lang,String(s.factory?.timezone||'UTC'))} · {t('qualityAccepted')}: {text(e.good)} {t(text(row.unit))} · {t('qualityDiscarded')}: {text(e.discarded_quantity)} {t(text(row.unit))} · {t('qualityActualKg')}: {text(e.scrap_kg)} kg · {t('unfinishedProduct')}: {text(e.unfinished)} {t(text(row.unit))}</p>)}</section>}
   {row.reversal?<p>{t('qualityReversed')}</p>:<>
    {can('orders','edit')&&<div className="row-actions"><button disabled={action.busy} onClick={()=>run('acknowledge',{})}>{t('qualityAcknowledge')}</button><button disabled={action.busy||decimalCompare(row.shortfall,'0')!==0} onClick={()=>run('resolve',{})}>{t('qualityResolve')}</button></div>}
    {row.disposition==='REWORK'&&can('orders','edit')&&<button type="button" aria-expanded={followUp==='rework'} onClick={()=>{setFollowUp(followUp==='rework'?'':'rework');setQuantity('');}}>{t('qualityRequestRework')}</button>}
    {row.disposition==='REWORK'&&can('orders','edit')&&followUp==='rework'&&<form onSubmit={e=>{e.preventDefault();run('request_rework',{lot,quantity});}}><fieldset disabled={action.busy}><h3>{t('qualityRequestRework')}</h3>
     <Field label={t('unfinishedProduct')}><select required value={lot} onChange={e=>setLot(e.target.value)}><option value="">{t('select')}</option>{lots.filter(l=>decimalCompare(l.warehouse_quantity,'0')===1).map(l=><option key={text(l.id)} value={text(l.id)}>{text(l.remaining_work)} · {text(l.warehouse_quantity)} {t(text(row.unit))}</option>)}</select></Field>
     <Field label={t('quantity')}><input required type="number" min="0" step={row.unit==='piece'?'1':'any'} value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field><p className="muted">{t('qualityReservedHelp')}</p><button disabled={!selected||!quantityValid(quantity,text(row.unit),selected?.warehouse_quantity)}>{t('qualityRequestRework')}</button>
    </fieldset></form>}
    {can('orders','create')&&decimalCompare(row.shortfall,'0')===1&&<button type="button" aria-expanded={followUp==='replacement'} onClick={()=>{setFollowUp(followUp==='replacement'?'':'replacement');setQuantity('');}}>{t('qualityReplacement')}</button>}
    {can('orders','create')&&decimalCompare(row.shortfall,'0')===1&&followUp==='replacement'&&<form onSubmit={e=>{e.preventDefault();run('replacement',{quantity},id=>setCreated(text(id)));}}><fieldset disabled={action.busy}><h3>{t('qualityReplacement')}</h3><p className="muted">{t('qualityReplacementHelp')}</p>
     <Field label={t('quantity')}><input required type="number" min="0" step={row.unit==='piece'?'1':'any'} value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field><button disabled={!quantityValid(quantity,text(row.unit),row.shortfall)}>{t('qualityReplacement')}</button>
    </fieldset></form>}
    {created&&<p role="status">{t('qualityReplacementCreated')} {props.onPlanItem&&<button onClick={()=>props.onPlanItem?.(created)}>{t('planning')}</button>}</p>}
    {can('quality','edit')&&<><button disabled={action.busy} onClick={()=>setReverse(!reverse)}>{t('qualityCorrectMistake')}</button>{reverse&&<form onSubmit={e=>{e.preventDefault();run('reverse',{reason,physically_present:physical});}}><fieldset disabled={action.busy}><p>{t('qualityReversalHelp')}</p>
     <Field label={t('reason')}><textarea required minLength={3} maxLength={2000} value={reason} onChange={e=>setReason(e.target.value)}/></Field><label className="recording-confirm"><input type="checkbox" checked={physical} onChange={e=>setPhysical(e.target.checked)}/>{t('qualityReversalPhysical')}</label><button disabled={!physical||reason.trim().length<3}>{t('qualityConfirmCorrection')}</button>
    </fieldset></form>}</>}
   </>}{action.error&&<p role="alert">{t(action.error)}</p>}
  </section>}
 </QualityDialog>;
}
export function QualityNotifications(props:FeatureProps&{onPlanItem?:(id:string)=>void}){
 const {snapshot:s,t,lang}=props;const [page,setPage]=useState(1),[selected,setSelected]=useState<string|null>(null),read=useSupply(s,'notifications',{page:String(page)},props.can('orders'),'/api/quality');
 return <section className="quality-notifications"><h3>{t('qualityNotifications')}</h3>{read.error&&<p role="alert">{t(read.error)}</p>}{read.busy&&<p role="status">{t('loading')}</p>}
  {!read.busy&&!read.data?.rows.length&&<p className="muted">{t('qualityNoNotifications')}</p>}
  {read.data?.rows.map(row=><article key={text(row.id)} className="quality-history-row"><strong>{t('qualityRejected')} — <bdi>{text(row.request_code||row.item_code)}</bdi></strong><p>{named(row,lang,'product_name')} · {named(row,lang,'line_name')} · {row.shift_name?named(row,lang,'shift_name'):t('shiftNotRecorded')} · {row.shift_date?text(row.shift_date):t('qualityShiftDateUnknown')}</p><p><bdi>{text(row.item_code)}</bdi> · <span className={((row.notification as SupplyRow|undefined)?.status==='OPEN'?'badge status-maintenance':'badge status-idle')}>{t('qualityStatus_'+text((row.notification as SupplyRow|undefined)?.status))}</span></p><p>{text(row.quantity)} {t(text(row.unit))} · {t(row.disposition==='SCRAP'?'qualityScrap':'qualityRework')} {row.actual_scrap_kg?'· '+text(row.actual_scrap_kg)+' kg':''} · {named(row,lang,'reason')}</p><p>{t('qualityShortfallLabel')}: {text(row.shortfall)} {t(text(row.unit))}</p><button onClick={()=>setSelected(text(row.id))}>{t('open')}</button></article>)}
  {(read.data?.total||0)>50&&<nav className="fulfillment-pagination"><button disabled={page===1||read.busy} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></nav>}
  {selected&&<QualityDetail {...props} rejection={selected} onClose={()=>setSelected(null)} onChanged={read.refresh}/>}
 </section>;
}
