import {formatLocalInput,localDateTimeToUtc} from '@/utils/manufacturing.mjs';
import { useRef, useState } from 'react';
import { Field, formatTime, localName } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import HistoryQueryState from '@/components/HistoryQueryState';
import { formatDuration } from '@/utils/production-flow.mjs';
import { initiativeStatus } from '@/utils/lean-analysis.mjs';
import type { FeatureProps } from './types';
import type { LeanRow } from './LeanAnalysis';
import { typedMetric } from './LeanAnalysis';
type Evidence=LeanRow;
const actionTypes=['MAINTENANCE','PROCESS','QUALITY','MATERIAL','TRAINING','SETUP','OTHER'];
type PriorityValues={monitor_only:boolean;threshold_percent:string};
type PriorityDraft={base:PriorityValues;revision:number;values:PriorityValues;submitted:boolean};
export function LeanPrioritization({problem,loading,error,busy,t,onSave,onReload}:{
 problem:LeanRow|null;loading:boolean;error:string;busy:boolean;t:FeatureProps['t'];
 onSave:(values:LeanRow)=>Promise<unknown>;onReload:()=>void;
}){
 const [draft,setDraft]=useState<PriorityDraft|null>(null),saving=useRef(false);
 const ready=!!problem&&typeof problem.monitor_only==='boolean'&&Number.isInteger(problem.revision)
  &&problem.revision>=1&&problem.threshold_percent!=null&&Number.isFinite(Number(problem.threshold_percent));
 const persisted:PriorityValues={monitor_only:problem?.monitor_only===true,threshold_percent:String(problem?.threshold_percent??'')};
 // A successful write stays locked until its authoritative revision has arrived.
 // Background reads never replace an unsaved draft or its original revision.
 const edit=draft?.submitted&&ready&&problem!.revision>draft.revision?null:draft;
 const values=edit?.values||persisted,awaiting=!!edit?.submitted;
 const disabled=busy||loading||!!error||!ready||awaiting;
 const dirty=!!edit&&(values.monitor_only!==edit.base.monitor_only||Number(values.threshold_percent)!==Number(edit.base.threshold_percent));
 function change(next:Partial<PriorityValues>){
  if(disabled)return;
  setDraft({base:edit?.base||persisted,revision:edit?.revision??problem!.revision,
   values:{...values,...next},submitted:false});
 }
 return <form className="lean-controls" aria-busy={busy||loading||awaiting} onSubmit={async e=>{
  e.preventDefault();
  if(disabled||!dirty||!edit||saving.current)return;
  saving.current=true;
  try{
   const result=await onSave({...edit.values,threshold_percent:Number(edit.values.threshold_percent),expected_revision:edit.revision});
   if(result!=null)setDraft({...edit,submitted:true});
  }finally{saving.current=false;}
 }}>
  <label><input name="monitor" type="checkbox" checked={values.monitor_only} disabled={disabled}
   onChange={e=>change({monitor_only:e.target.checked})}/>{t('leanMonitorOnly')}</label>
  <Field label={t('leanThreshold')}><input name="threshold" required type="number" min="0" max="100" step="any"
   value={values.threshold_percent} disabled={disabled} onChange={e=>change({threshold_percent:e.target.value})}/></Field>
  <button disabled={disabled||!dirty}>{t('save')}</button>
  {edit&&!awaiting&&<button type="button" disabled={busy} onClick={()=>{setDraft(null);onReload();}}>{t('cancel')}</button>}
 </form>;
}
export default function LeanProblem({row,from,to,refreshIdentity,onBack,...props}:FeatureProps & {row:LeanRow;from:string;to:string;refreshIdentity?:string;onBack:()=>void}){
 const {snapshot:s,t,lang,command,can}=props,factory=String(s.factory?.id||''),zone=String(s.factory?.timezone||'UTC');
 const [page,setPage]=useState(1),[revision,setRevision]=useState(0),[shift,setShift]=useState<string|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const [title,setTitle]=useState(''),[product,setProduct]=useState(String(row.product_id||row.products?.[0]||''));
 const [action,setAction]=useState<LeanRow>({title:'',description:'',action_type:'PROCESS',owner_id:s.user.id,due_date:''});
 const [comparison,setComparison]=useState<Evidence|null>(null),[manual,setManual]=useState(false),[cutoff,setCutoff]=useState(formatLocalInput(new Date().toISOString(),String(s.factory?.timezone||'UTC'))),[hours,setHours]=useState('40');
 const [outcome,setOutcome]=useState('IMPROVED'),[note,setNote]=useState('');
 const actionRequest=useRef(crypto.randomUUID()),actionId=useRef(crypto.randomUUID()),initiativeRequest=useRef(crypto.randomUUID()),initiativeId=useRef(crypto.randomUUID());
 const query=new URLSearchParams({factory,mode:'detail',page:String(page),from,to,...(row.problem_id?{problem_id:String(row.problem_id)}:{mechanism:String(row.mechanism),cause_id:String(row.cause_id),...(row.machine_id?{machine_id:String(row.machine_id)}:{line_id:String(row.line_id),product_id:String(row.product_id)})})});
 const data=useHistoryData<LeanRow>('/api/lean?'+query,String(s.fetchedAt)+':'+revision,JSON.stringify({factory,problem:row.problem_id||[row.mechanism,row.machine_id,row.line_id,row.product_id,row.cause_id],page,period:refreshIdentity||[from,to]}));
 const library=useHistoryData<LeanRow>('/api/lean?'+new URLSearchParams({factory,mode:'library'}),String(s.fetchedAt)+':'+revision);
 const detail=data.data,initiatives:LeanRow[]=detail?.initiatives||[],actions:LeanRow[]=detail?.actions||[],current=initiatives.find(i=>!i.verified_at);
 const name=(table:string,id:unknown)=>localName(s.tables[table]?.find(x=>x.id===id),lang)||t('notAvailable');
 const q=(v:unknown)=>v==null?'—':Number(v).toLocaleString(lang,{maximumFractionDigits:2});
 const at=(v:unknown)=>formatTime(v as string,lang,zone);
 const refresh=()=>{setRevision(x=>x+1);data.reload();};
 async function run(operation:string,payload:LeanRow,request_id=crypto.randomUUID()){setBusy(true);setError('');try{const result=await command('lean_command',{factory,request_id,operation,payload});refresh();return result;}catch(e){setError(e instanceof Error?e.message:'error');return null;}finally{setBusy(false);}}
 async function calculate(operation:string,extra:LeanRow={}){setBusy(true);setError('');try{
  const isManual=['manual','save_comparison'].includes(operation);
  const response=await fetch('/api/lean',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({factory,operation,problem_id:row.problem_id,initiative_id:isManual?undefined:current?.id,product_id:isManual?product:current?.product_id||product,expected_revision:isManual?undefined:current?.revision||1,request_id:crypto.randomUUID(),...extra})});
  const body=await response.json();if(!response.ok)throw Error(body.error||'dataWarning');setComparison(operation==='baseline'?null:body.evidence);if(['verify','baseline','save_comparison'].includes(operation))refresh();return true;
 }catch(e){setError(e instanceof Error?e.message:'error');return false;}finally{setBusy(false);}}
 const events:LeanRow[]=detail?.rows||[],shiftEvents=shift===null?events:events.filter(x=>(x.shift_id||'unknown')===shift);
 const previous=initiatives.find(i=>i.verified_at);
 const recurred=detail?.recurrence_watch,metrics=detail?.metrics||row;
 const insufficient=t('leanDataInsufficient');
 const measure=(values:Record<string,number|null>|undefined)=>values&&Object.values(values).some(value=>value!=null)?typedMetric(values,lang):insufficient;
 return <section className="lean-page lean-detail" dir={lang==='ar'?'rtl':'ltr'}><header className="lean-header"><div><button onClick={onBack}>← {t('leanProblems')}</button><h2>{lang==='ar'?row.cause_ar||row.cause:row.cause}</h2><p>{row.machine_id?name('work_centers',row.machine_id):name('production_lines',row.line_id)} · {(row.products||[row.product_id]).map((id:string)=>name('products',id)).join(' · ')}</p></div>
  <div><strong>{t((detail?.problem?.monitor_only??row.monitor_only)?'leanMonitorOnly':current?'lean'+initiativeStatus(actions.filter(a=>a.initiative_id===current.id),current):previous?'leanVERIFIED':'leanOccurrence')}</strong>{recurred?.recurred&&<p role="status">{t('leanRecurred')}</p>}</div></header>
  <div className="lean-summary">{[['leanFrequency',metrics.frequency==null?insufficient:q(metrics.frequency)],['leanEffectiveLoss',metrics.loss_minutes==null?insufficient:formatDuration(Number(metrics.loss_minutes),lang)],['recordingScrap',metrics.scrap_kg==null?insufficient:q(metrics.scrap_kg)+' kg'],['leanScrapRate',metrics.scrap_rate==null?insufficient:q(metrics.scrap_rate)+'%'],['leanLostOutput',measure(metrics.lost_output_by_unit)],['unfinishedQuantity',measure(metrics.wip_by_unit)]].map(([label,value])=><div key={label}><span>{t(label)}</span><strong>{value}</strong></div>)}</div>
  <p className="muted">{t('leanEvidenceHelp')}</p><div className="lean-query-feedback"><HistoryQueryState {...data} t={t}/></div>{error&&<p className="notice" role="alert">{t(error)}</p>}
  <details className="lean-specialized">
   <summary>{t('leanSpecializedMetrics')}</summary>
   <dl>
    <div><dt>{t('line')}</dt><dd>{(row.line_id?[row.line_id]:row.lines||[]).map((id:string)=>name('production_lines',id)).join(' · ')||t('notAvailable')}</dd></div>
    <div><dt>{t('leanLossRate')}</dt><dd>{row.loss_rate==null?t('leanDataInsufficient'):q(row.loss_rate)+' '+t('leanMinPerHour')}</dd></div>
    <div><dt>{t('leanOperatingTime')}</dt><dd>{row.runtime_missing||row.runtime_hours==null?t('leanRuntimeMissing'):q(row.runtime_hours)+' '+t('hours')}</dd></div>
    <div><dt>{t('leanCustomerRisk')}</dt><dd>{row.customer_risk==null?t('leanDataInsufficient'):t(row.customer_risk?'leanDeliveryAtRisk':'leanNoLinkedRisk')}</dd></div>
   </dl>
   {row.attention?.scrap&&<p className="lean-value-loss">{t('leanAttentionScrap')}</p>}
   <h3>{t('leanTrend')}</h3>
   {row.trends?.length?row.trends.map((trend:LeanRow)=><div key={trend.product_id} className="lean-trend">
    <strong>{name('products',trend.product_id)}</strong>
    {!trend.complete?<span>{t('leanInsufficientExposure')}</span>:
     [['loss','leanEffectiveLoss'],['frequency','leanFrequency'],['scrap','recordingScrap']].map(([key,label])=>
      <span key={key}>{t(label)} · {t('leanOutcome_'+(trend[key]?.suggestion||'INSUFFICIENT_DATA'))}
       {trend[key]?.percent!=null&&<> · {q(trend[key].percent)}%</>}</span>)}
   </div>):<p>{t('leanInsufficientExposure')}</p>}
  </details>
  {can('lean','edit')&&row.problem_id&&<details><summary>{t('leanPrioritization')}</summary>
   <LeanPrioritization key={factory+':'+row.problem_id} problem={detail&&detail.problem?.id===row.problem_id?detail.problem:null}
    loading={data.loading} error={data.error} busy={busy} t={t} onReload={refresh}
    onSave={values=>run('problem',{mechanism:row.mechanism,machine_id:row.machine_id,line_id:row.line_id,product_id:row.product_id,cause_id:row.cause_id,...values})}/>
  </details>}
  <section><h3>{t('leanTimeline')}</h3><div className="lean-controls"><Field label={t('leanShiftDetails')}><select value={shift||''} onChange={e=>setShift(e.target.value||null)}><option value="">{t('all')}</option>{(metrics.shifts||[]).map((id:string|null)=><option key={id||'unknown'} value={id||'unknown'}>{id?name('production_shifts',id):t('shiftNotRecorded')}</option>)}</select></Field><button onClick={()=>setShift(shift===null?String(metrics.shifts?.[0]||'unknown'):null)}>{t('leanShiftDetails')}</button></div>
   {shift!==null&&detail?.shift_summary?.filter((x:LeanRow)=>(x.shift_id||'unknown')===shift).map((x:LeanRow)=><div key={shift} className="lean-shift-summary"><strong>{t('leanFrequency')}: {q(x.frequency)}</strong><span>{t('leanEffectiveLoss')}: {x.loss_minutes==null?'—':formatDuration(Number(x.loss_minutes),lang)}</span><span>{t('recordingScrap')}: {q(x.scrap_kg)} kg · {q(x.scrap_rate)}%</span><span>{t('leanLostOutput')}: {typedMetric(x.lost_output,lang)}</span><span>{t('leanAverageResponse')}: {x.response_minutes==null?'—':formatDuration(Number(x.response_minutes),lang)}</span></div>)}
   <div className="lean-timeline">{shiftEvents.map((e,index)=><article key={e.event_id+':'+index}><header><strong>{at(e.occurred_at)}</strong><span>{e.shift_id?name('production_shifts',e.shift_id):t('shiftNotRecorded')}</span></header><dl><div><dt>{t('leanEffectiveLoss')}</dt><dd>{e.loss_minutes==null?t('leanMissingLoss'):formatDuration(Number(e.loss_minutes),lang)} · {t('leanSource_'+e.loss_source)}</dd></div><div><dt>{t('leanResponseDuration')}</dt><dd>{formatDuration(Math.max(0,Date.parse(e.ended_at)-Date.parse(e.occurred_at))/60000,lang)}</dd></div><div><dt>{t('leanLostOutput')}</dt><dd>{q(e.lost_output)} {e.output_unit}</dd></div><div><dt>{t('leanAssociatedScrap')}</dt><dd>{q(e.scrap_kg)} kg</dd></div><div><dt>{t('leanProducedWeight')}</dt><dd>{q(e.produced_kg)} kg</dd></div></dl><p>{t('leanPreliminaryCause')}: {localName(library.data?.causes?.find((x:LeanRow)=>x.id===e.preliminary_cause_id),lang)||t('notAvailable')}</p><p dir="auto">{t('leanOriginalObservation')}: {e.observation||'—'}</p><p dir="auto">{t('leanEngineerNote')}: {e.approved_note||'—'}</p><p dir="auto">{t('leanResponse')}: {e.response||'—'}</p>{e.loss_details&&<details><summary>{t('leanSegmentedImpact')}</summary>{e.loss_details.assumptions?.map((segment:LeanRow,i:number)=><p key={i}>{at(segment.from)} – {at(segment.to)} · {String(segment.flow_state||'')} · {q(segment.effective_loss_minutes)} {t('minutesShort')} · {q(segment.lost_output)} {segment.unit}</p>)}</details>}</article>)}</div>
   <nav className="history-pagination"><button disabled={page<=1} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{page} · {q(detail?.total)} {t('leanOccurrences')}</span><button disabled={page*100>=(detail?.total||0)} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></nav>
  </section>
  <section><h3>{t('leanCustomerImpact')}</h3><p>{t('leanCustomerReadOnly')}</p>{detail?.sales==null?<p>{t('leanOpenForContext')}</p>:<><p>{t('leanAffectedSales')}: {q(detail.sales.length)}</p>{detail.sales.map((o:LeanRow)=><article key={o.id}><strong><bdi>{o.code}</bdi></strong><p>{t('leanAffectedQuantity')}: {typedMetric(o.affected_quantity,lang)} · {t('leanCustomerRisk')}: {t('deliveryRisk_'+o.risk)}</p><p>{t('leanRequestedDate')}: {at(o.requested_delivery)} · {t('leanEstimatedReady')}: {at(o.estimated_ready)}</p></article>)}</>}</section>
  <section><h3>{t('maintenance')}</h3>{detail?.maintenance?.length?detail.maintenance.map((m:LeanRow)=><details key={m.id}><summary><bdi>{m.code}</bdi> · {m.title} · {t('maintenanceState_'+m.status)}</summary><p>{m.description}</p><p>{m.work_note}</p>{m.downtime_id&&<p>{t('leanLinkedStop')}: <bdi>{m.downtime_id.slice(0,8)}</bdi></p>}</details>):<p>{t(detail?.maintenance==null?'leanOpenForContext':'noResults')}</p>}</section>
  <section><h3>{t('leanInitiative')}</h3>{!current&&can('lean','create')&&row.problem_id&&<form className="form-grid" onSubmit={async e=>{e.preventDefault();const created=await run('initiative',{id:initiativeId.current,problem_id:row.problem_id,product_id:product,title},initiativeRequest.current) as {id:string}|null;if(created){await calculate('baseline',{initiative_id:created.id,product_id:product});setTitle('');initiativeRequest.current=crypto.randomUUID();initiativeId.current=crypto.randomUUID();}}}><Field label={t('title')}><input required minLength={3} maxLength={200} value={title} onChange={e=>setTitle(e.target.value)}/></Field><Field label={t('product')}><select required value={product} onChange={e=>setProduct(e.target.value)}>{(row.products||[row.product_id]).filter(Boolean).map((id:string)=><option key={id} value={id}>{name('products',id)}</option>)}</select></Field><button className="primary" disabled={busy}>{t('leanCreateInitiative')}</button></form>}
   {current&&<><h4>{current.title} · {t('lean'+initiativeStatus(actions.filter(a=>a.initiative_id===current.id),current))}</h4><p>{t('product')}: {name('products',current.product_id)} · {t('leanBaselineExposure')}: {q(current.baseline_hours)} {t('hours')}</p>{!current.baseline_evidence&&can('lean','create')&&<button disabled={busy} onClick={()=>{setManual(false);void calculate('baseline');}}>{t('leanCaptureBaseline')}</button>}
    {actions.filter(a=>a.initiative_id===current.id).map(a=><Action key={a.id} {...props} action={a} busy={busy} onEdit={a=>{setAction({id:a.id,title:a.title,description:a.description,action_type:a.action_type,owner_id:a.owner_id,due_date:a.due_date,expected_revision:a.revision});actionRequest.current=crypto.randomUUID();}} onSave={(op,p)=>void run(op,p)}/>)}
    {can('lean','edit')&&<form className="recording-form" onSubmit={async e=>{e.preventDefault();const created=await run('action',{...action,id:action.id||actionId.current,initiative_id:current.id,expected_revision:action.expected_revision||0},actionRequest.current);if(created){setAction({title:'',description:'',action_type:'PROCESS',owner_id:s.user.id,due_date:''});actionRequest.current=crypto.randomUUID();actionId.current=crypto.randomUUID();}}}><h4>{t(action.id?'leanEditAction':'leanAddAction')}</h4><div className="form-grid"><Field label={t('leanSuggestedActions')}><select value="" onChange={e=>{const suggestion=[...(library.data?.templates||[]).filter((x:LeanRow)=>!x.archived&&(!x.cause_id||x.cause_id===row.cause_id)),...(detail?.previous_actions||[])].find(x=>x.id===e.target.value);if(suggestion)setAction({title:suggestion.title,description:suggestion.description,action_type:suggestion.action_type,owner_id:s.user.id,due_date:new Date(Date.now()+(suggestion.due_days||7)*86400000).toISOString().slice(0,10)});}}><option value="">{t('leanManualEntry')}</option>{(library.data?.templates||[]).filter((x:LeanRow)=>!x.archived&&(!x.cause_id||x.cause_id===row.cause_id)).map((x:LeanRow)=><option key={x.id} value={x.id}>{lang==='ar'?x.name_ar||x.title:x.title}</option>)}{(detail?.previous_actions||[]).map((x:LeanRow)=><option key={x.id} value={x.id}>{x.title} · {t('leanOutcome_'+(x.outcome||'UNKNOWN'))}</option>)}</select></Field>
     <Field label={t('title')}><input required minLength={3} maxLength={200} value={action.title} onChange={e=>setAction({...action,title:e.target.value})}/></Field><Field label={t('description')}><textarea maxLength={2000} value={action.description} onChange={e=>setAction({...action,description:e.target.value})}/></Field><Field label={t('leanActionType')}><select value={action.action_type} onChange={e=>setAction({...action,action_type:e.target.value})}>{actionTypes.map(k=><option key={k} value={k}>{t('leanActionType_'+k)}</option>)}</select></Field><Field label={t('leanOwner')}><select required value={action.owner_id} onChange={e=>setAction({...action,owner_id:e.target.value})}>{library.data?.people?.map((p:LeanRow)=><option key={p.user_id} value={p.user_id}>{p.display_name}</option>)}</select></Field><Field label={t('leanDueDate')}><input required type="date" value={action.due_date} onInput={e=>setAction({...action,due_date:e.currentTarget.value})} onChange={e=>setAction({...action,due_date:e.target.value})}/><small>{t('leanDueHelp')}</small></Field></div><button className="primary" disabled={busy}>{t('save')}</button></form>}
   </>}
  </section>
  <section><h3>{t('leanBeforeAfter')}</h3><p>{t('leanEqualRuntimeHelp')}</p>{current?.completed_at&&<button disabled={busy} onClick={()=>{setManual(false);setProduct(current.product_id);void calculate('preview');}}>{t('leanOfficialComparison')}</button>}
   <details><summary>{t('leanManualComparison')}</summary><form className="form-grid" onSubmit={e=>{e.preventDefault();setManual(true);void calculate('manual',{cutoff:localDateTimeToUtc(cutoff,String(s.factory?.timezone||'UTC')),desired_hours:Number(hours)});}}><Field label={t('product')}><select required value={product} onChange={e=>setProduct(e.target.value)}>{(row.products||[row.product_id]).filter(Boolean).map((id:string)=><option key={id} value={id}>{name('products',id)}</option>)}</select></Field><Field label={t('leanCutoff')}><input required type="datetime-local" value={cutoff} onInput={e=>setCutoff(e.currentTarget.value)} onChange={e=>setCutoff(e.target.value)}/></Field><Field label={t('leanDesiredHours')}><input required type="number" min="0.001" max="100000" step="any" value={hours} onChange={e=>setHours(e.target.value)}/></Field><button disabled={busy||!row.problem_id}>{t('leanCompare')}</button></form></details>
   {comparison&&<><p className={comparison.complete?'notice':'planning-warning'}>{t(comparison.complete?'leanExposureComplete':'leanInsufficientExposure')}: {t('leanBefore')} {q(comparison.before?.collected_hours)} h · {t('leanAfter')} {q(comparison.after?.collected_hours)} h · {t('leanRemaining')} {q(comparison.after?.remaining_hours)} h</p><div className="table-wrap"><table><caption>{t('leanSeparateMetrics')}</caption><thead><tr><th>{t('leanMetric')}</th><th>{t('leanBefore')}</th><th>{t('leanAfter')}</th><th>{t('leanSuggestion')}</th></tr></thead><tbody>{['frequency','occurrences_per_hour','loss_minutes','loss_minutes_per_hour','scrap_kg','produced_kg','scrap_rate'].map(k=><tr key={k}><th>{t('leanMetric_'+k)}</th><td>{q(comparison.before_metrics?.[k])}</td><td>{q(comparison.after_metrics?.[k])}</td><td>{comparison.changes?.[k]?t('leanOutcome_'+comparison.changes[k].suggestion):'—'} {comparison.changes?.[k]?.percent==null?'':q(comparison.changes[k].percent)+'%'}</td></tr>)}{['lost_output','wip'].map(k=><tr key={k}><th>{t(k==='wip'?'unfinishedQuantity':'leanLostOutput')}</th><td>{typedMetric(comparison.before_metrics?.[k],lang)}</td><td>{typedMetric(comparison.after_metrics?.[k],lang)}</td><td>{t('leanSeparateUnits')}</td></tr>)}</tbody></table></div>
    <details><summary>{t('leanShiftDetails')}</summary>{['before_metrics','after_metrics'].map(k=><section key={k}><h4>{t(k==='before_metrics'?'leanBefore':'leanAfter')}</h4>{comparison[k]?.shifts?.map((x:LeanRow)=><p key={x.shift_id||'unknown'}>{x.shift_id?name('production_shifts',x.shift_id):t('shiftNotRecorded')} · {t('leanFrequency')}: {q(x.frequency)} · {formatDuration(Number(x.loss_minutes||0),lang)} · {q(x.scrap_kg)} kg · {q(x.scrap_rate)}% · {typedMetric(x.lost_output,lang)}</p>)}</section>)}</details>
    {manual?<button disabled={busy} onClick={()=>void calculate('save_comparison',{cutoff:localDateTimeToUtc(cutoff,String(s.factory?.timezone||'UTC')),desired_hours:Number(hours)})}>{t('leanSaveComparison')}</button>:current?.completed_at&&can('lean','approve')&&<form className="form-grid" onSubmit={e=>{e.preventDefault();void calculate('verify',{outcome,note});}}><Field label={t('leanVerificationOutcome')}><select required value={outcome} onChange={e=>setOutcome(e.target.value)}>{['IMPROVED','NO_MEANINGFUL_CHANGE','WORSE','INSUFFICIENT_DATA'].map(k=><option key={k} value={k}>{t('leanOutcome_'+k)}</option>)}</select></Field><Field label={t('leanVerificationNote')}><textarea required minLength={3} maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></Field><button className="primary" disabled={busy||!comparison.complete&&outcome!=='INSUFFICIENT_DATA'}>{t('leanConfirmVerification')}</button></form>}</>}
  </section>
  <section><h3>{t('leanVerificationHistory')}</h3>{initiatives.filter(i=>i.verified_at).map(i=><details key={i.id}><summary>{i.title} · {t('leanOutcome_'+i.outcome)} · {at(i.verified_at)}</summary><p>{i.verification_note}</p><p>{t('leanBaselineExposure')}: {q(i.baseline_hours)} h</p>{i.verification_evidence&&<SavedMetrics evidence={i.verification_evidence} t={t} lang={lang}/>} {actions.filter(a=>a.initiative_id===i.id).map(a=><article key={a.id}><h4>{a.title} · {t("lean"+a.status)}</h4><p>{a.description}</p><p>{t("leanDueDate")}: {a.due_date} · {t("leanOwner")}: {String(library.data?.people?.find((p:LeanRow)=>p.user_id===a.owner_id)?.display_name||t("notAvailable"))}</p><p>{a.status==="CANCELLED"?t("leanCancellationReason")+": "+a.cancellation_reason:t("leanProgress")+": "+(a.progress_note||"—")}</p></article>)}</details>)}{(detail?.comparisons||[]).map((c:LeanRow)=><details key={c.id}><summary>{t('leanManualComparison')} · {at(c.created_at)}</summary><p>{q(c.desired_hours)} h · {at(c.cutoff)}</p><SavedMetrics evidence={c.evidence} t={t} lang={lang}/></details>)}</section>
  <details><summary>{t('audit')}</summary>{detail?.history?.map((h:LeanRow)=><p key={h.id}>{at(h.created_at)} · {h.action} · {h.entity} · {String(library.data?.people?.find((p:LeanRow)=>p.user_id===h.actor_id)?.display_name||t('notAvailable'))}</p>)}</details>
 </section>;
}
function Action({action:a,busy,onSave,onEdit,...props}:FeatureProps & {action:LeanRow;busy:boolean;onSave:(op:string,payload:LeanRow)=>void;onEdit:(action:LeanRow)=>void}){
 const {t,can,snapshot:s}=props,[status,setStatus]=useState(a.status),[date,setDate]=useState(a.due_date),[note,setNote]=useState(a.progress_note||''),[reason,setReason]=useState('');
 const editable=can('lean','edit')||a.owner_id===s.user.id;
 return <article className="lean-action"><h4>{a.title} · {t('lean'+a.status)}</h4><p>{a.description}</p><p>{t('leanOwner')}: {String(s.tables.production_technicians?.find(x=>x.user_id===a.owner_id)?.display_name||s.tables.memberships?.find(x=>x.user_id===a.owner_id)?.display_name||t('notAvailable'))} · {t('leanDueDate')}: {a.due_date} · {t('leanActionType_'+a.action_type)}</p>{a.status==='CANCELLED'?<p>{t('leanCancellationReason')}: {a.cancellation_reason}</p>:editable&&<form className="lean-controls" onSubmit={e=>{e.preventDefault();onSave('progress',{id:a.id,status,due_date:date,note,expected_revision:a.revision});}}><Field label={t('status')}><select value={status} onChange={e=>setStatus(e.target.value)}>{['OPEN','IN_PROGRESS','COMPLETED'].map(k=><option key={k} value={k}>{t('lean'+k)}</option>)}</select></Field><Field label={t('leanDueDate')}><input required type="date" value={date} onInput={e=>setDate(e.currentTarget.value)} onChange={e=>setDate(e.target.value)}/><small>{t('leanDueHelp')}</small></Field><Field label={t('leanProgress')}><input maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></Field><button disabled={busy}>{t('save')}</button></form>}
 {can('lean','edit')&&a.status!=='CANCELLED'&&<><button onClick={()=>onEdit(a)}>{t('leanEditAction')}</button><details><summary>{t('leanCancelAction')}</summary><form onSubmit={e=>{e.preventDefault();onSave('cancel_action',{id:a.id,reason,expected_revision:a.revision});}}><Field label={t('leanCancellationReason')}><textarea required minLength={3} maxLength={2000} value={reason} onChange={e=>setReason(e.target.value)}/></Field><button disabled={busy}>{t('leanCancelAction')}</button></form></details></>}</article>;
}

function SavedMetrics({evidence:e,t,lang}:{evidence:LeanRow;t:FeatureProps["t"];lang:FeatureProps["lang"]}){
 const q=(v:unknown)=>v==null?"—":Number(v).toLocaleString(lang,{maximumFractionDigits:2});
 return <div className="table-wrap"><p>{t(e.complete?"leanExposureComplete":"leanInsufficientExposure")}: {t("leanBefore")} {q(e.before?.collected_hours)} h · {t("leanAfter")} {q(e.after?.collected_hours)} h · {t("leanRemaining")} {q(e.after?.remaining_hours)} h</p><table><caption>{t("leanSeparateMetrics")}</caption><thead><tr><th>{t("leanMetric")}</th><th>{t("leanBefore")}</th><th>{t("leanAfter")}</th><th>{t("leanSuggestion")}</th></tr></thead><tbody>{["frequency","occurrences_per_hour","loss_minutes","loss_minutes_per_hour","scrap_kg","produced_kg","scrap_rate"].map(k=><tr key={k}><th>{t("leanMetric_"+k)}</th><td>{q(e.before_metrics?.[k])}</td><td>{q(e.after_metrics?.[k])}</td><td>{e.changes?.[k]?t("leanOutcome_"+e.changes[k].suggestion):"—"}</td></tr>)}{["lost_output","wip"].map(k=><tr key={k}><th>{t(k==="wip"?"unfinishedQuantity":"leanLostOutput")}</th><td>{typedMetric(e.before_metrics?.[k],lang)}</td><td>{typedMetric(e.after_metrics?.[k],lang)}</td><td>{t("leanSeparateUnits")}</td></tr>)}</tbody></table></div>;
}
