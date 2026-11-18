import {useEffect,useRef,useState} from 'react';
import {formatTime,localName} from '@/components/ui';
import type {Row} from '@/types';
import type {FeatureProps} from './types';
import {pendingExecution,retainExecution,clearExecution,submitExecution,executionOutcome,type ExecutionIntent,type ExecutionResult} from '@/services/production-execution-client';

type Operation='INTERRUPT'|'RESUME'|'START_SELECTED'|'HISTORY';
type Run={id:string;line_id:string;started_at:string;ended_at:string|null;state:string;reason:string|null;start_reason?:string|null;start_actor:string|null;end_actor:string|null;planned:{start:string;finish:string};recorded_after:Row|null};
type Context={factory:string;item:string;fingerprint:string;order:Row;remaining:string;history:Run[];reason_required?:boolean;bypassed_order?:{id:string;code:string}|null;return_transfers?:{request_id:string;actor:string;reason:string;returned_at:string;mode:string;source_machine:string;alternative_machine:string}[];line_transfers?:{request_id:string;actor:string;reason:string;started_at:string;source_line:string;destination_line:string;source_machine:string;alternative_machine:string}[]};
const labels:Record<Operation,string>={INTERRUPT:'f34PauseRelease',RESUME:'f34Resume',START_SELECTED:'startProduction',HISTORY:'f34History'};
export default function ProductionExecutionActions({props,item,allowDispatch=false,dispatchBlocked=false,historyOnly=false,onOutcome}:{props:FeatureProps;item:Row;allowDispatch?:boolean;dispatchBlocked?:boolean;historyOnly?:boolean;onOutcome?:(key:string)=>void}){
 const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||''),actorId=String(s.user?.id||''),id=String(item.id),zone=String(s.factory?.timezone||'UTC');
 const [operation,setOperation]=useState<Operation|null>(null),[context,setContext]=useState<Context|null>(null),[reason,setReason]=useState(''),[confirmed,setConfirmed]=useState(false);
 const [busy,setBusy]=useState(false),[loading,setLoading]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const [shortages,setShortages]=useState<{name:string;name_ar?:string;missing:string;unit:string}[]>([]),[materialReason,setMaterialReason]=useState('');
 const [legacy,setLegacy]=useState<{name:string;name_ar?:string;held:string;unit:string}[]>([]);
 const [hasPending,setHasPending]=useState(false);
 const [rejected,setRejected]=useState(false);
 const dialog=useRef<HTMLDialogElement>(null),submitting=useRef(false),starting=useRef(false),prepared=useRef<Context|null>(null),retry=useRef<ExecutionIntent|null>(null),epoch=useRef(0);
 const editable=!historyOnly&&can('orders','edit')&&can('orders','view');
 const needsReason=operation==='INTERRUPT'||context?.reason_required!==false;
 useEffect(()=>{try{setHasPending(Boolean(pendingExecution(localStorage,actorId,factory,id)));}catch{setError('executionPendingStorage');}},[actorId,factory,id]);
 async function load(){const token=++epoch.current;setLoading(true);setContext(null);
  try{const r=await fetch('/api/production-execution?'+new URLSearchParams({factory,item:id}),{cache:'no-store',signal:AbortSignal.timeout(20000)}),b=await r.json();
   if(!r.ok)throw Error(b.error||'dataWarning');if(b.data?.factory!==factory||b.data?.item!==id)throw Error('dataWarning');
   if(operation!=='HISTORY'&&b.data?.order?.line_id!==item.line_id)throw Error('execution_context_changed');if(token===epoch.current){setContext(b.data);return b.data as Context;}return null;
  }catch(e){if(token===epoch.current)setError(e instanceof Error?e.message:'dataWarning');return null;}finally{if(token===epoch.current)setLoading(false);}}
 useEffect(()=>{if(!operation)return;const d=dialog.current;d?.showModal();void(async()=>{if(prepared.current){setContext(prepared.current);prepared.current=null;}else await load();if(retry.current&&operation!=='HISTORY')await recover();})();return()=>{epoch.current++;d?.close();};
 // The selected item/factory defines this dialog; parent refresh must not discard its reason or retry identity.
 // eslint-disable-next-line react-hooks/exhaustive-deps
 },[operation,factory,id]);
 function open(value:Operation){try{prepared.current=null;const pending=value==='HISTORY'?null:pendingExecution(localStorage,actorId,factory,id);retry.current=pending;setOperation((pending?.operation as Operation)||value);setReason(pending?.reason||'');setConfirmed(pending?.output_confirmed||false);setRejected(false);setError('');setNotice('');setShortages([]);setLegacy([]);setMaterialReason('');}catch{setError('executionPendingStorage');}}
 function close(){if(!submitting.current)setOperation(null);}
 async function result(value:ExecutionResult,intent:ExecutionIntent){
  if(value.outcome==='UNKNOWN'){setRejected(false);setError(['permissionError','signIn'].includes(value.error)?value.error:'executionOutcomeUnknown');if(value.current)setContext(value.current);return;}
  try{clearExecution(localStorage,actorId,intent);setHasPending(false);retry.current=null;}catch{setError('executionPendingStorage');if(value.outcome!=='COMMITTED')return;}
  if(value.outcome==='REJECTED'){
   setRejected(true);setShortages(value.materials?.rows||[]);setLegacy(value.materials?.legacy||[]);setMaterialReason(value.materials?.reason||'');await load();setError(t(value.error)!==value.error?value.error:'executionRejected');return;
  }
  setOperation(null);const key=intent.operation==='RETURN_PRODUCTION'?'f48Returned':intent.operation==='TRANSFER_LINE'?'f20Transferred':intent.operation==='INTERRUPT'?'executionPaused':intent.operation==='RESUME'?'executionResumed':'executionStarted';setNotice(key);onOutcome?.(key);
  try{if(await props.refreshSnapshot?.()===false){setNotice('executionRefreshAfterSuccess');onOutcome?.('executionRefreshAfterSuccess');}}catch{setNotice('executionRefreshAfterSuccess');onOutcome?.('executionRefreshAfterSuccess');}
 }
 async function recover(){if(submitting.current||!retry.current)return;submitting.current=true;setBusy(true);try{await result(await executionOutcome(retry.current),retry.current);}finally{submitting.current=false;setBusy(false);}}
 async function submit(next=operation,current=context,explanation=reason,outputConfirmed=confirmed){if(submitting.current||!next||!current)return;
  submitting.current=true;setBusy(true);setRejected(false);setError('');setShortages([]);setLegacy([]);setMaterialReason('');
  try{
   if(!actorId)throw Error('permissionError');
   const previous=pendingExecution(localStorage,actorId,factory,id);if(previous)retry.current=previous;
   if(!retry.current)retry.current={factory,item:id,operation:next,reason:explanation.trim(),fingerprint:current.fingerprint,request_id:crypto.randomUUID(),output_confirmed:outputConfirmed};
   retainExecution(localStorage,actorId,retry.current);setHasPending(true);
   if(previous){const checked=await executionOutcome(previous);if(checked.outcome==='COMMITTED'){await result(checked,previous);return;}}
   await result(await submitExecution(retry.current),retry.current);
  }catch(e){const key=e instanceof Error?e.message:'executionOutcomeUnknown';setError(t(key)!==key?key:'executionOutcomeUnknown');}
  finally{submitting.current=false;setBusy(false);}
 }
 async function reviewPending(){try{retry.current=pendingExecution(localStorage,actorId,factory,id);if(retry.current){setHasPending(true);await recover();}}catch{setError('executionPendingStorage');}}
 async function startFromCard(){
  if(starting.current||submitting.current||dispatchBlocked)return;
  starting.current=true;setBusy(true);setError('');setNotice('');setRejected(false);setShortages([]);setLegacy([]);setMaterialReason('');
  try{
   const pending=pendingExecution(localStorage,actorId,factory,id);
   if(pending){retry.current=pending;setHasPending(true);await recover();return;}
   retry.current=null;setHasPending(false);
   const current=await load();if(!current)return;
   if(current.order.status!=='planned'){setError('execution_context_changed');return;}
   if(typeof current.reason_required!=='boolean'||current.reason_required&&!current.bypassed_order?.code){setError('dataWarning');return;}
   const next=current.order.execution_interrupted_at?'RESUME':'START_SELECTED';
   if(current.reason_required){prepared.current=current;setReason('');setConfirmed(false);setOperation(next);return;}
   await submit(next,current,'',false);
  }catch(e){const key=e instanceof Error?e.message:'dataWarning';setError(t(key)!==key?key:'dataWarning');}
  finally{starting.current=false;setBusy(false);}
 }
 const actor=(value:string|null)=>value?s.tables.memberships?.find(m=>m.user_id===value)?.display_name||t('f34RecordedActor'):t('f34UnknownActor');
 const missing=shortages.filter(r=>/^\d+(\.\d+)?$/.test(String(r.missing))&&/[1-9]/.test(String(r.missing)));
 return <div className="production-execution-actions">
  <div className="ff2-row-actions">
   {editable&&hasPending&&<button type="button" disabled={busy||loading} onClick={()=>void reviewPending()}>{t('executionCheckOutcome')}</button>}
   {editable&&item.status==='active'&&<button type="button" disabled={busy||loading||hasPending} onClick={()=>open('INTERRUPT')}>{t('f34PauseRelease')}</button>}
   {editable&&allowDispatch&&item.status==='planned'&&item.line_id&&<button type="button" className="primary" disabled={dispatchBlocked||busy||loading||hasPending} aria-busy={busy||loading} onClick={()=>void startFromCard()}>{t(busy||loading?'updating':item.execution_interrupted_at?'f34Resume':'startProduction')}</button>}
   {can('orders','view')&&item.actual_start&&<button type="button" onClick={()=>open('HISTORY')}>{t('f34History')}</button>}
  </div>
  {notice&&!onOutcome&&<p role="status">{t(notice)}</p>}
  {!operation&&<div className="execution-inline-outcome" aria-live="polite">
   {error&&<p role="alert">{t(error)}</p>}{materialReason&&<p>{t(materialReason)}</p>}
   {!!missing.length&&<><p>{t('executionStartShortages')}</p><ul>{missing.map((r,n)=><li key={n}><span dir="auto">{lang==='ar'?r.name_ar||r.name:r.name}</span>: <bdi>{r.missing} {t(r.unit)}</bdi></li>)}</ul></>}
   {!!legacy.length&&<><p>{t('psLegacyOrderHelp')}</p><ul>{legacy.map((r,n)=><li key={n}><span dir="auto">{lang==='ar'?r.name_ar||r.name:r.name}</span>: {t('psLegacyHeld')} <bdi>{r.held} {t(r.unit)}</bdi></li>)}</ul></>}
   {hasPending&&!busy&&<p role="status">{t('executionOutcomeUnknown')}</p>}
  </div>}
  {operation&&<dialog ref={dialog} className="production-execution-dialog" aria-labelledby={`execution-title-${id}`} onCancel={e=>{e.preventDefault();close();}}>
   <div className="ff2-queue-job-head"><h3 id={`execution-title-${id}`}>{t(labels[operation])}</h3><button type="button" onClick={close} disabled={busy} aria-label={t('close')}>×</button></div>
   <p><bdi>{String(item.code||'')}</bdi> · {t(item.execution_interrupted_at?'f34Interrupted':String(item.status))}</p>
   {loading&&<p role="status">{t('loading')}</p>}
   {context&&operation!=='HISTORY'&&<form onSubmit={e=>{e.preventDefault();void submit();}}>
    <p>{t(operation==='INTERRUPT'?'f34PauseHelp':'f34DispatchHelp')}</p>
    <p>{t('recordingRemaining')}: <bdi>{context.remaining} {t(String(context.order.unit))}</bdi></p>
    {operation!=='INTERRUPT'&&context.bypassed_order&&<p>{t('executionBypassedOrder')}: <bdi>{context.bypassed_order.code}</bdi></p>}
    {(needsReason||Boolean(retry.current?.reason))&&<label>{t('f34Reason')}<textarea required={needsReason} minLength={3} maxLength={240} value={reason} disabled={busy||Boolean(retry.current)} onChange={e=>setReason(e.target.value)} /></label>}
    {operation==='INTERRUPT'&&<label className="f34-confirm"><input type="checkbox" checked={confirmed} disabled={busy||Boolean(retry.current)} onChange={e=>setConfirmed(e.target.checked)} />{t('f34OutputConfirmed')}</label>}
    <div className="ff2-row-actions"><button type="button" onClick={close} disabled={busy}>{t('cancel')}</button>{retry.current&&<button type="button" disabled={busy} onClick={()=>void recover()}>{t('executionCheckOutcome')}</button>}<button className="primary" disabled={busy||loading||!retry.current&&(needsReason&&reason.trim().length<3||operation==='INTERRUPT'&&!confirmed||operation!=='INTERRUPT'&&dispatchBlocked)}>{t(busy?'updating':retry.current?'f34Retry':labels[operation])}</button></div>
   </form>}
   {rejected&&<p role="status">{t('executionNotApplied')}</p>}
   {error&&<p role="alert">{t(error)}</p>}
   {materialReason&&<p>{t(materialReason)}</p>}
   {!!missing.length&&<><p>{t('executionShortages')}</p><ul>{missing.map((r,n)=><li key={n}>{lang==='ar'?r.name_ar||r.name:r.name}: <bdi>{r.missing} {t(r.unit)}</bdi></li>)}</ul></>}
   {!!legacy.length&&<><p>{t('psLegacyOrderHelp')}</p><ul>{legacy.map((r,n)=><li key={n}>{lang==='ar'?r.name_ar||r.name:r.name}: {t('psLegacyHeld')} <bdi>{r.held} {t(r.unit)}</bdi></li>)}</ul></>}
   {retry.current&&!busy&&<p role="status">{t('f34RetryHelp')}</p>}
   {!context&&!loading&&<button type="button" onClick={()=>void load()}>{t('refresh')}</button>}
   {context&&<details open={operation==='HISTORY'}><summary>{t('f34History')}</summary>{!context.history.length?<p>{t('f34NoHistory')}</p>:context.history.map(run=><section key={run.id} className="f34-run">
    <strong>{t('f34Run_'+run.state)}</strong><p>{localName(s.tables.production_lines?.find(l=>l.id===run.line_id),lang)} · <bdi>{formatTime(run.started_at,lang,zone)} — {run.ended_at?formatTime(run.ended_at,lang,zone):t('active')}</bdi></p>
    <p>{t('f34PlannedWindow')}: <bdi>{formatTime(run.planned.start,lang,zone)} — {formatTime(run.planned.finish,lang,zone)}</bdi></p>
    <p>{t('f34StartedBy')}: {String(actor(run.start_actor))}{run.end_actor&&<> · {t('f34EndedBy')}: {String(actor(run.end_actor))}</>}</p>
    {run.start_reason&&<p dir="auto">{t('f341StartReason')}: {run.start_reason}</p>}
    {run.reason&&run.reason!==run.start_reason&&<p dir="auto">{t('f34Reason')}: {run.reason}</p>}
   </section>)}{!!context.line_transfers?.length&&<><h4>{t('f20TransferHistory')}</h4>{context.line_transfers.map(move=><section className="f34-run" key={move.request_id}><strong>{localName(s.tables.production_lines?.find(l=>l.id===move.source_line),lang)} → {localName(s.tables.production_lines?.find(l=>l.id===move.destination_line),lang)}</strong><p>{localName(s.tables.work_centers?.find(c=>c.id===move.source_machine),lang)} → {localName(s.tables.work_centers?.find(c=>c.id===move.alternative_machine),lang)}</p><p>{String(actor(move.actor))} · {formatTime(move.started_at,lang,zone)}</p><p dir="auto">{move.reason}</p></section>)}</>}{!!context.return_transfers?.length&&<><h4>{t('f48History')}</h4>{context.return_transfers.map(move=><section className="f34-run" key={move.request_id}><strong>{localName(s.tables.work_centers?.find(c=>c.id===move.alternative_machine),lang)} → {localName(s.tables.work_centers?.find(c=>c.id===move.source_machine),lang)}</strong><p>{String(actor(move.actor))} · {formatTime(move.returned_at,lang,zone)}</p><p dir="auto">{move.reason}</p></section>)}</>}</details>}
  </dialog>}
 </div>;
}
