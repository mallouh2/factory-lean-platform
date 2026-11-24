import {useTableDetails,TableDetailsAction} from '@/components/useTableDetails';
import { useState } from 'react';
import { Field, localName } from '@/components/ui';
import { formatDuration } from '@/utils/production-flow.mjs';
import { useHistoryData } from '@/hooks/useHistoryData';
import HistoryQueryState from '@/components/HistoryQueryState';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
import LeanProblem from './LeanProblem';
import LeanLibraries from './LeanLibraries';
import PlanActual from './PlanActual';
export type LeanRow=Record<string,any>; // Nested reader evidence is distinct from flat snapshot rows.
export const typedMetric=(values:Record<string,number|null>|undefined,lang:string)=>Object.entries(values||{}).filter(([,v])=>v!=null).map(([unit,value])=>Number(value).toLocaleString(lang)+' '+unit).join(' · ')||'—';
export default function LeanAnalysis({onDowntime,...props}:FeatureProps & {onDowntime?:()=>void}){
 const {snapshot:s,t,lang,command,can}=props,factory=String(s.factory?.id||'');
 const detailsRow=useTableDetails(),[selection,setSelection]=useState('');
 const [days,setDays]=useState('30'),[initialAnchor]=useState(()=>new Date().toISOString()),[customFrom,setCustomFrom]=useState(''),[customTo,setCustomTo]=useState('');
 const anchor=Number.isFinite(Date.parse(String(s.fetchedAt)))?new Date(s.fetchedAt).toISOString():initialAnchor;
 const [filters,setFilters]=useState<Record<string,string>>({}),[sort,setSort]=useState('loss_minutes'),[direction,setDirection]=useState('desc'),[page,setPage]=useState(1);
 const [selected,setSelected]=useState<LeanRow|null>(null),[libraries,setLibraries]=useState(false),[notice,setNotice]=useState(''),[opening,setOpening]=useState(false);
 const [planActual,setPlanActual]=useState(()=>typeof window!=='undefined'&&new URLSearchParams(window.location.search).get('report')==='plan-actual');
 const showPlanActual=planActual&&can('orders','view')&&can('lean','view');
 const openPlanActual=(open:boolean)=>{
  setPlanActual(open);
  const url=new URL(window.location.href);
  if(open)url.searchParams.set('report','plan-actual');
  else url.searchParams.delete('report');
  window.history.replaceState(window.history.state,'',url);
 };
 const from=days==='custom'&&customFrom?new Date(customFrom).toISOString():new Date(Date.parse(anchor)-Number(days==='custom'?30:days)*86400000).toISOString();
 const to=days==='custom'&&customTo?new Date(customTo).toISOString():anchor;
 const url='/api/lean?'+new URLSearchParams({factory,from,to,sort,direction,page:String(page),...Object.fromEntries(Object.entries(filters).filter(([,v])=>v))});
 const identity=JSON.stringify({factory,days,customFrom,customTo,filters,sort,direction,page});
 const data=useHistoryData<{rows:LeanRow[];total:number;summary:LeanRow;open_initiatives:number;overdue_actions:number;sales_at_risk?:number;loss_ranking?:{id:string;name:string;name_ar?:string;minutes:number;cumulative:number}[]}>(!showPlanActual&&can('lean','view')?url:null,String(s.fetchedAt),identity);
 const library=useHistoryData<{causes:Row[]}>(showPlanActual?null:'/api/lean?'+new URLSearchParams({factory,mode:'library'}),String(s.fetchedAt));
 const change=(key:string,value:string)=>{setFilters(x=>({...x,[key]:value}));setPage(1);};
 const name=(table:string,id:unknown)=>localName(s.tables[table]?.find(x=>x.id===id),lang)||t('notAvailable');
 const q=(v:unknown)=>v==null?'—':Number(v).toLocaleString(lang,{maximumFractionDigits:2});
 const selector=(key:string,label:string,rows:Row[]) => <Field label={t(label)}><select value={filters[key]||''} onChange={e=>change(key,e.target.value)}><option value="">{t('all')}</option>{rows.map(x=><option key={String(x.id)} value={String(x.id)}>{localName(x,lang)}</option>)}</select></Field>;
 if(showPlanActual)return <PlanActual {...props} onBack={()=>openPlanActual(false)}/>;
 if(libraries)return <LeanLibraries {...props} onBack={()=>{setLibraries(false);data.reload();library.reload();}}/>;
 if(selected)return <LeanProblem {...props} row={selected} from={from} to={to} refreshIdentity={identity} onBack={()=>{setSelected(null);data.reload();}}/>;
 async function open(row:LeanRow){setOpening(true);setNotice('');try{
  let id=row.problem_id;
  if(!id){
   if(!can('lean','edit')&&!can('lean','create')){setSelected(row);return;}
   const result=await command('lean_command',{factory,request_id:crypto.randomUUID(),operation:'problem',payload:{mechanism:row.mechanism,machine_id:row.machine_id,line_id:row.line_id,product_id:row.product_id,cause_id:row.cause_id,monitor_only:false,threshold_percent:10,expected_revision:0}}) as {id:string};id=result.id;
  }
  setSelected({...row,problem_id:id});
 }catch(e){setNotice(e instanceof Error?e.message:'error');}finally{setOpening(false);}}
 const rows=data.data?.rows||[];
 const ranking=data.data?.loss_ranking||[];
 const summary=data.data?.summary;
 const incomplete=t('leanDataInsufficient');
 const duration=(value:unknown)=>value==null?incomplete:formatDuration(Number(value),lang);
 const summaries=[
  {label:'leanEffectiveLoss',value:summary?.loss_minutes==null?null:duration(summary.loss_minutes),tone:'loss'},
  {label:'leanRecurring',value:summary?.recurring==null?null:q(summary.recurring),tone:'blue'},
  {label:'leanOpenInitiatives',value:data.data?.open_initiatives==null?null:q(data.data.open_initiatives),tone:'teal'},
  {label:'leanOverdue',value:data.data?.overdue_actions==null?null:q(data.data.overdue_actions),tone:'warning'},
 ].filter(metric=>metric.value!==null);
 const keyFor=(row:LeanRow)=>row.problem_id||[row.mechanism,row.machine_id,row.line_id,row.product_id,row.cause_id].join(':');
 const causeFor=(row:LeanRow)=>lang==='ar'?row.cause_ar||row.cause:row.cause;
 const labels=['leanProblemReason','leanEquipmentLine','leanFrequency','leanEffectiveLoss','leanLostOutput','status'];
 const stale=data.loading||!!data.error||opening;
 const filterCount=Object.entries(filters).filter(([key,value])=>key!=='line_id'&&value).length;
 const pct=new Intl.NumberFormat(lang,{style:'percent',maximumFractionDigits:1});
 const cells=(row:LeanRow)=>{
  const lines=(row.line_id?[row.line_id]:row.lines||[]).map((id:string)=>name('production_lines',id)).join(' · ');
  const knownOutput=row.mechanism==='downtime'&&Object.values(row.lost_output_by_unit||{}).some(value=>value!=null);
  const status=row.display_status||(row.initiative?.verified_at?'VERIFIED':row.initiative?.completed_at?'AWAITING_VERIFICATION':row.initiative?'IN_PROGRESS':'OCCURRENCE');
  const verified=status==='VERIFIED'&&row.initiative?.outcome&&row.initiative.outcome!=='INSUFFICIENT_DATA';
  const tone=verified?'teal':status==='OCCURRENCE'?'blue':'warning';
  return [
   <><button className="lean-problem-link" disabled={stale} onClick={()=>void open(row)}>{causeFor(row)}</button><small>{t(row.mechanism==='scrap'?'leanHighScrap':'leanApprovedCause')}</small></>,
   <>{row.machine_id?<><strong>{name('work_centers',row.machine_id)}</strong>{lines&&<small>{lines}</small>}</>:lines||t('notAvailable')}</>,
   <><strong>{row.frequency==null?incomplete:q(row.frequency)}</strong>{row.frequency>=2&&<small className="lean-tag blue">{t('leanRecurringLabel')}</small>}</>,
   <><strong className={row.attention?.loss?'lean-value-loss':undefined}>{duration(row.loss_minutes)}</strong>
    {row.loss_minutes==null||row.missing_loss>0?<small>{t('leanMissingLoss')}</small>:null}</>,
   <>{knownOutput?<><strong>{typedMetric(row.lost_output_by_unit,lang)}</strong><small>{t(row.output_measured?'leanMeasuredOutput':'leanOutputBasisUnknown')}</small></>:<>{row.mechanism==='scrap'?t('leanOutputNotApplicable'):incomplete}{row.mechanism==='downtime'&&<small>{t('leanNoOutputEvidence')}</small>}</>}</>,
   <><span className={'lean-tag '+tone}>{t(row.monitor_only?'leanMonitorOnly':status==='OCCURRENCE'?'leanOccurrence':status==='VERIFIED'&&!verified?'leanDataInsufficient':'lean'+status)}</span>
    {verified&&<small>{t('leanOutcome_'+row.initiative.outcome)}</small>}
    {row.runtime_missing&&<small>{t('leanInsufficientExposure')}</small>}</>,
  ];
 };
 return <section className="lean-page lean-overview" dir={lang==='ar'?'rtl':'ltr'} aria-label={t('lean')}>
  <div className="lean-overview-intro"><p>{t('leanHelp')}</p><div>
   {onDowntime&&<button type="button" onClick={onDowntime}>{t('leanReviewDowntime')}</button>}
   {can('orders','view')&&can('lean','view')&&<button type="button" onClick={()=>openPlanActual(true)}>{t('f37Title')}</button>}
   {(can('lean','edit')||can('lean_standards','edit'))&&<button type="button" onClick={()=>setLibraries(true)}>{t('leanLibraries')}</button>}
  </div></div>
  <section className="lean-filter-area" aria-label={t('leanFilters')}>
   <div className="lean-filter-primary">
    <Field label={t('leanPeriod')}><select value={days} onChange={e=>{setDays(e.target.value);setPage(1);}}>{['7','30','90'].map(d=><option key={d} value={d}>{d} {t('planningDays')}</option>)}<option value="custom">{t('leanCustom')}</option></select></Field>
    {selector('line_id','line',s.tables.production_lines||[])}
    {days==='custom'&&<>
     <Field label={t('from')}><input type="datetime-local" value={customFrom} onChange={e=>{setCustomFrom(e.target.value);setPage(1);}}/></Field>
     <Field label={t('to')}><input type="datetime-local" value={customTo} onChange={e=>{setCustomTo(e.target.value);setPage(1);}}/></Field>
    </>}
   </div>
   <details className="lean-more-filters"><summary>{t('leanMoreFilters')}{filterCount>0&&<> ({q(filterCount)})</>}</summary>
    <div className="lean-filters">
     {selector('machine_id','machine',s.tables.work_centers||[])}
     {selector('product_id','product',s.tables.products||[])}
     {selector('shift_id','productionShift',s.tables.production_shifts||[])}
     {selector('cause_id','leanApprovedCause',library.data?.causes||[])}
     <Field label={t('historySort')}><select value={sort} onChange={e=>{setSort(e.target.value);setPage(1);}}>{['loss_minutes','scrap_kg','frequency','loss_rate'].map(k=><option key={k} value={k}>{t('leanSort_'+k)}</option>)}</select></Field>
     <Field label={t('leanRecurring')}><select value={filters.recurring||''} onChange={e=>change('recurring',e.target.value)}><option value="">{t('all')}</option><option value="true">{t('leanRecurringOnly')}</option></select></Field>
     <Field label={t('status')}><select value={filters.initiative_status||''} onChange={e=>change('initiative_status',e.target.value)}><option value="">{t('all')}</option>{['OCCURRENCE','IN_PROGRESS','AWAITING_VERIFICATION','VERIFIED'].map(status=><option key={status} value={status}>{t(status==='OCCURRENCE'?'leanOccurrence':'lean'+status)}</option>)}</select></Field>
     <Field label={t('leanFrequency')+' · '+t('historyMinimum')}><input type="number" min="0" value={filters.min_frequency||''} onChange={e=>change('min_frequency',e.target.value)}/></Field>
     <Field label={t('recordingScrap')+' kg · '+t('historyMinimum')}><input type="number" min="0" step="any" value={filters.min_scrap||''} onChange={e=>change('min_scrap',e.target.value)}/></Field>
     <Field label={t('leanFilterPrioritization')}><select value={filters.monitor_only||''} onChange={e=>change('monitor_only',e.target.value)}><option value="">{t('all')}</option><option value="true">{t('leanMonitorOnly')}</option><option value="false">{t('leanPrioritized')}</option></select></Field>
    </div>
    <div className="lean-filter-actions">
     <button type="button" onClick={()=>{setDirection(x=>x==='desc'?'asc':'desc');setPage(1);}}>{t(direction==='desc'?'historyDescending':'historyAscending')}</button>
     <button type="button" onClick={()=>{setFilters({});setDays('30');setCustomFrom('');setCustomTo('');setSort('loss_minutes');setDirection('desc');setPage(1);}}>{t('leanClearFilters')}</button>
     {data.data?.sales_at_risk!=null&&<span>{t('leanSalesRisk')} · {q(data.data.sales_at_risk)} <small>{t('leanFactoryWide')}</small></span>}
    </div>
   </details>
  </section>
  <HistoryQueryState {...data} t={t}/>{notice&&<p role="alert">{t(notice)}</p>}
  {summaries.length>0&&<dl className="lean-stat-strip">{summaries.map(metric=><div key={metric.label} className={metric.tone}>
   <dt>{t(metric.label)}</dt><dd><bdi>{metric.value}</bdi></dd>
   {['leanOpenInitiatives','leanOverdue'].includes(metric.label)&&<small>{t('leanFactoryWide')}</small>}
   {metric.label==='leanEffectiveLoss'&&Number(summary?.missing_loss)>0&&<small>{t('leanPartialShort')}</small>}
  </div>)}</dl>}
  {data.data&&<section className="lean-overview-panel lean-ranking" aria-labelledby="lean-ranking-title">
   <h2 id="lean-ranking-title">{t('leanTopLosses')}</h2>
   {ranking.length>0?<><p>{t('leanTopLossesHelp')}</p>
    <ol>{ranking.map(cause=><li key={cause.id}>
     <button type="button" className="lean-ranked-reason" aria-pressed={filters.cause_id===cause.id}
      onClick={()=>change('cause_id',filters.cause_id===cause.id?'':cause.id)}>{lang==='ar'?cause.name_ar||cause.name:cause.name}</button>
     <span className="lean-loss-track" aria-hidden="true"><span style={{inlineSize:(cause.minutes/ranking[0].minutes*100)+'%'}}/></span>
     <span className="lean-rank-value"><bdi>{duration(cause.minutes)}</bdi><small>{t('leanCumulativeShare')} <bdi>{pct.format(cause.cumulative)}</bdi></small></span>
    </li>)}</ol></>:<div className="lean-quiet-state"><strong>{t(summary?.loss_minutes===0&&Number(summary.missing_loss||0)===0?'leanNoRecordedLoss': 'leanDataInsufficient')}</strong><p>{t('leanRankingEmpty')}</p></div>}
   {!!Number(summary?.missing_loss)&&<p className="lean-evidence-note">{t('leanMissingLoss')} · {q(summary?.missing_loss)}</p>}
  </section>}
  {data.data&&<section className="lean-overview-panel lean-problem-list" aria-labelledby="lean-problems-title">
   <header><div><h2 id="lean-problems-title">{t('leanProblems')}</h2><p>{t('leanProblemsHelp')}</p></div>
    <button type="button" onClick={data.reload}>{t('refresh')}</button></header>
   {!rows.length?<p className="lean-list-empty">{t('leanNoProblems')}</p>:<>
    <div className="lean-mobile-problems">{rows.map(row=>{
     const values=cells(row);
     return <article key={keyFor(row)} className="lean-mobile-problem"><h3>{values[0]}</h3><p>{values[1]}</p>
      <dl>{values.slice(2).map((value,i)=><div key={labels[i+2]}><dt>{t(labels[i+2])}</dt><dd>{value}</dd></div>)}</dl></article>;
    })}</div>
    <div className="table-wrap lean-table"><table><caption className="sr-only">{t('leanProblems')}</caption>
     <thead><tr>{labels.map(label=><th scope="col" key={label}>{t(label)}</th>)}</tr></thead>
     <tbody>{rows.map(row=><tr key={keyFor(row)} tabIndex={row.problem_id?0:undefined} aria-selected={!!row.problem_id&&selection===row.problem_id}
      {...detailsRow(()=>setSelection(row.problem_id),()=>setSelected(row),!row.problem_id||stale||!can('lean','view'))}>
      {cells(row).map((cell,i)=><td key={labels[i]}>{cell}</td>)}
     </tr>)}</tbody>
    </table></div>
    <div className="lean-list-footer">
     {selection&&<TableDetailsAction t={t} disabled={stale||!rows.some(row=>row.problem_id===selection)} onOpen={()=>{const row=rows.find(row=>row.problem_id===selection);if(row)setSelected(row);}}/>}
     <nav className="history-pagination" aria-label={t('leanProblems')}><button disabled={stale||page<=1} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{q(page)} / {q(Math.max(1,Math.ceil(data.data.total/25)))}</span><button disabled={stale||page*25>=data.data.total} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></nav>
    </div>
   </>}
  </section>}
 </section>;
}
