import {ProductionMaterials} from './MaterialPreparation';
import PlanningChangeUpdates from './PlanningChangeUpdates';
import HistoricalProductionRecording,{HistoricalApprovalQueue} from './HistoricalProductionRecording';
import {recordingWorkMessage} from '@/utils/recording-work-state.mjs';
import QualityUpdateButton from './ProductionQualityActions';
import {useEffect,useRef,useState} from 'react';
import {Dialog,formatTime} from '@/components/ui';
import {acknowledgeIntent,canRecordWork,prepareIntent,readIntent,recordingNumber,recordingScope,sameMeasurement} from '@/utils/production-recording-intent.mjs';
import {postRecording,recoverRecording,type RecordingIntent,type RecordingResult,type CompletionTarget} from '@/services/production-recording-client';
import {readCompletion,finishRecordedExecution,type CompletionSummary} from '@/services/production-completion-client';
import {sameExecutionStart} from '@/utils/production-completion.mjs';
import {planningWorkKind} from '@/utils/planning-workspace.mjs';
import ProductionRecording from './ProductionRecording';
import type {FeatureProps} from './types';
import ManufacturedOutput,{OutputGroupsEditor,type OutputGroup,type OutputOperation} from './ManufacturedOutput';
import {outputGroups,outputTotal} from '@/utils/manufactured-output.mjs';

type Work={item_id:string;item_code:string;request_code:string;product_name:string;product_name_ar:string;line_name:string;line_name_ar:string;line_id:string;unit:string;status:string;actual_start:string;actual_finish:string|null;execution_key:string;context_hash:string;can_record:boolean;blocked_reason?:string;same_shift_recording_available?:boolean};
type Occurrence={occurrence_key:string;name:string;name_ar:string;business_date:string;starts_at:string;ends_at:string;timezone:string};
type WorkPage={reason?:string;contract_version:number;factory_id:string;available:boolean;can_edit:boolean;late_recording_available:boolean;rows:Work[];occurrence:Occurrence|null;server_as_of:string;expires_at:string;next_cursor:string|null;complete:boolean};
type Entry={id:string;item_id:string;request_code:string;line_name:string;line_name_ar:string;good:string;scrap_kg:string;unit:string;recorded_at:string;recorded_by:string;factory_id:string};
const initial={input:'',discarded:'0',good:'',scrap:'0',unfinished:'0',remaining:'',notes:'',declared:false,confirmed:false};
function Check(){return <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true"><path d="m5 12 4 4L19 6"/></svg>}
export default function ProductionRecordingV3(props:FeatureProps&{recordingItem?:string|null;completionItem?:string|null;onCompletionClose?:()=>void}){
 const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||''),actor=s.user.id;
 const [period,setPeriod]=useState<'current'|'previous'>('current');
 const [savedNotice,setSavedNotice]=useState<boolean|string>(false);
 useEffect(()=>{if(!savedNotice)return;const timer=setTimeout(()=>setSavedNotice(false),5000);return()=>clearTimeout(timer);},[savedNotice]);
 const [open,setOpen]=useState(false),[history,setHistory]=useState(false),[mode,setMode]=useState<'current'|'existing'>('current');
 const [workPage,setWorkPage]=useState<WorkPage|null>(null),[selected,setSelected]=useState(''),[query,setQuery]=useState('');
 const [draft,setDraft]=useState(initial),[hasWip,setHasWip]=useState(false),[technician,setTechnician]=useState('');
 const [outputOptions,setOutputOptions]=useState<{item:string;available:boolean;operations:OutputOperation[];work_kind?:'COMPLETE'|'REPLACE'|'STOCK'|null;replacement_allowance?:string;recovery?:{lot_id:string;remaining:string;missing_operations:string[];operations:string[];material_status:string}}|null>(null),[outputError,setOutputError]=useState(false);
 const [unfinishedGroups,setUnfinishedGroups]=useState<OutputGroup[]>([]);
 const outputDrafts=useRef(new Map<string,OutputGroup[]>());
 const [loading,setLoading]=useState(false),[workError,setWorkError]=useState(''),[error,setError]=useState(''),[retry,setRetry]=useState(0);
 const [intent,setIntent]=useState<RecordingIntent|null>(null),[result,setResult]=useState<RecordingResult|null>(null),[busy,setBusy]=useState(false);
 const [recent,setRecent]=useState<Entry[]>([]),[recentError,setRecentError]=useState(''),[unitName,setUnitName]=useState(''),[expired,setExpired]=useState(false);
 const inFlight=useRef(false),trigger=useRef<HTMLButtonElement|null>(null),returnFocus=useRef<HTMLElement|null>(null),dialogRegion=useRef<HTMLDivElement|null>(null),serverClock=useRef({at:0,tick:0});
 const drafts=useRef(new Map<string,{draft:typeof initial;hasWip:boolean}>());
 const [overproduction,setOverproduction]=useState(false),[existingMounted,setExistingMounted]=useState(false);
 const [pinned,setPinned]=useState<string|null>(null);
 const [endItem,setEndItem]=useState<string|null>(null),[endOnly,setEndOnly]=useState(false),[endState,setEndState]=useState<'idle'|'pending'|'ended'>('idle');
 const [summary,setSummary]=useState<CompletionSummary|null>(null),[summaryError,setSummaryError]=useState(false),[summaryLoading,setSummaryLoading]=useState(false);
 const defaulted=useRef(new Set<string>()),goodTouched=useRef(new Set<string>()),summaryEpoch=useRef(0);
 const name=(row:Work,key:'product'|'line')=>String(row[`${key}_name${lang==='ar'?'_ar':''}` as keyof Work]||row[`${key}_name` as keyof Work]||'');
 const unit=(value:string)=>t(value==='meter'?'meterShort':value==='piece'?'pieceShort':value==='kg'?'kg':'notAvailable');
 const row=workPage?.rows.find(x=>x.item_id===selected),occ=workPage?.occurrence;
 const currentSummary=summary?.item_id===selected?summary:null;
 const ending=!!endItem&&selected===endItem&&currentSummary?.status==='active';
 const outputMode=outputOptions?.item===selected&&outputOptions.available;
 useEffect(()=>{if(!open||!selected)return;const abort=new AbortController();setOutputOptions(null);setOutputError(false);
  fetch('/api/manufactured-output?'+new URLSearchParams({factory,mode:'options',target:selected}),{signal:abort.signal,cache:'no-store'}).then(async r=>{if(!r.ok)throw Error();const d=await r.json();if(typeof d.available!=='boolean'||(d.available&&(!Array.isArray(d.operations)||!Object.hasOwn(d,'work_kind')||(d.work_kind!==null&&!['COMPLETE','REPLACE','STOCK'].includes(d.work_kind)))))throw Error();setOutputOptions({item:selected,available:d.available,operations:d.operations||[],work_kind:d.work_kind,replacement_allowance:d.replacement_allowance,recovery:d.recovery});}).catch(e=>{if(e.name!=='AbortError')setOutputError(true);});return()=>abort.abort();
 },[factory,selected,open,retry]);
 const recovery=outputMode?outputOptions?.recovery:null;
 const workKind=currentSummary&&outputOptions?.item===selected&&(outputOptions.work_kind||currentSummary.request_type||currentSummary.replacement_original_item_id||currentSummary.quality_origin_rejection_id)
  ?planningWorkKind(currentSummary,{request_type:currentSummary.request_type},outputOptions.work_kind?{choice:outputOptions.work_kind}:null).type:'prv3Work';
 const requiresDeclaration=!!row&&!!occ&&Date.parse(row.actual_start)<Date.parse(occ.starts_at);
 const allowed=can('orders','view')&&can('orders','edit');
 const technicians=s.tables.production_technicians||[];
 useEffect(()=>{
  const target=props.completionItem||props.recordingItem;if(!target)return;
  setPeriod('current');returnFocus.current=document.activeElement as HTMLElement;setPinned(target);setEndItem(props.completionItem||null);setEndOnly(false);setEndState('idle');setMode('current');setError('');setResult(null);selectWork(target);setOpen(true);
 },[props.completionItem,props.recordingItem]);
 useEffect(()=>{
  if(!open||!selected)return;const abort=new AbortController(),epoch=++summaryEpoch.current;setSummaryLoading(true);setSummaryError(false);
  void readCompletion(factory,selected,(input,init)=>fetch(input,{...init,signal:abort.signal})).then(value=>{if(!abort.signal.aborted&&epoch===summaryEpoch.current){setSummary(value);if(intent?.completion&&sameExecutionStart(value.actual_start,intent.completion.actual_start)&&value.status==='completed'&&value.actual_finish)setEndState('ended');}}).catch(()=>{if(!abort.signal.aborted&&epoch===summaryEpoch.current)setSummaryError(true);}).finally(()=>{if(!abort.signal.aborted&&epoch===summaryEpoch.current)setSummaryLoading(false);});
  return()=>abort.abort();
 },[open,selected,factory,s.fetchedAt,retry]);
 useEffect(()=>{
  if(!open||!endItem||endItem!==selected||!currentSummary||currentSummary.status!=='active'||defaulted.current.has(selected))return;
  defaulted.current.add(selected);if(!goodTouched.current.has(selected))setDraft(value=>value.good!==''?value:{...value,good:currentSummary.remaining});
 },[open,endItem,selected,currentSummary]);
 useEffect(()=>{const current=technicians.find(x=>x.user_id===actor);if(current)setTechnician(String(current.id));},[actor,technicians]);
 useEffect(()=>{
  const inspect=()=>{try{setIntent(readIntent(localStorage,actor,factory));}catch{setError('prv3StorageUnavailable');}};
  inspect();window.addEventListener('storage',inspect);return()=>window.removeEventListener('storage',inspect);
 },[actor,factory]);
 async function loadRecent(signal?:AbortSignal){
  try{const response=await fetch('/api/production-reporting?'+new URLSearchParams({factory,reporting_version:'3',page_size:'5'}),{cache:'no-store',signal});
   if(!response.ok)throw Error('dataWarning');const data=await response.json();
   if(data.contract_version!==3||data.factory_id!==factory||!Array.isArray(data.rows)||data.rows.some((e:Entry)=>e.factory_id!==factory))throw Error('dataWarning');
   if(!signal?.aborted){setRecent(data.rows);setRecentError('');}
  }catch(e){if(!(e instanceof Error&&e.name==='AbortError'))setRecentError('prv3RecentUnavailable');}
 }
 useEffect(()=>{
  if(!open||!can('orders','view'))return;
  const controller=new AbortController();setLoading(true);setWorkError('');
  fetch('/api/production-shift-work?'+new URLSearchParams({factory,page_size:'100'}),{cache:'no-store',signal:controller.signal})
   .then(async response=>{let data=await response.json();if(!response.ok)throw Error(response.status===403||response.status===401?'permissionError':'prv3WorkUnavailable');
    if(data.contract_version!==3||data.factory_id!==factory||!Array.isArray(data.rows)||typeof data.available!=='boolean'||typeof data.can_edit!=='boolean'||typeof data.late_recording_available!=='boolean'||!Number.isFinite(Date.parse(data.server_as_of)))throw Error('prv3WorkUnavailable');
    while(pinned&&!data.rows.some((x:Work)=>x.item_id===pinned)&&data.next_cursor){
     const next=await fetch('/api/production-shift-work?'+new URLSearchParams({factory,page_size:'100',cursor:data.next_cursor}),{cache:'no-store',signal:controller.signal});const page=await next.json();if(!next.ok||page.contract_version!==3||page.factory_id!==factory||!Array.isArray(page.rows)||page.server_as_of!==data.server_as_of)throw Error('prv3WorkUnavailable');data={...page,rows:[...data.rows,...page.rows]};
    }
    if(!controller.signal.aborted){setWorkPage(data);serverClock.current={at:Date.parse(data.server_as_of),tick:performance.now()};setExpired(false);}})
   .catch(e=>{if(e.name!=='AbortError')setWorkError(e.message==='permissionError'?'permissionError':'prv3WorkUnavailable');}).finally(()=>{if(!controller.signal.aborted)setLoading(false);});
  void loadRecent(controller.signal);return()=>controller.abort();
 },[open,factory,retry,s.fetchedAt,pinned]);
 useEffect(()=>{
  if(!open||!occ)return;
  const timer=setInterval(()=>setExpired(serverClock.current.at+performance.now()-serverClock.current.tick>=Date.parse(occ.ends_at)),1000);
  return()=>clearInterval(timer);
 },[open,occ]);
 // Recover an intent retained before opening. A newly submitted intent must not
 // race its own POST with a status read or overwrite the terminal response.
 useEffect(()=>{if(open&&intent&&!inFlight.current)void checkStatus(intent);},[open]);
 useEffect(()=>{if(error)dialogRegion.current?.querySelector<HTMLElement>('#prv3-form-feedback')?.focus();},[error]);
 function close(){if(inFlight.current)return;setOpen(false);setHistory(false);props.onCompletionClose?.();setTimeout(()=>(returnFocus.current||trigger.current)?.focus(),0);}
 function show(){returnFocus.current=document.activeElement as HTMLElement;setPeriod('current');setPinned(null);setEndItem(intent?.completion?.item||null);setEndOnly(false);setEndState('idle');setError('');setResult(null);setOpen(true);}
 function selectWork(value:string){
  if(selected)outputDrafts.current.set(selected,unfinishedGroups);setUnfinishedGroups(outputDrafts.current.get(value)||[]);
  if(selected)drafts.current.set(selected,{draft,hasWip});
  const saved=drafts.current.get(value);setSelected(value);setDraft(saved?.draft||initial);setHasWip(saved?.hasWip||false);setError('');setOverproduction(false);
 }
 async function showResult(value:RecordingResult,currentIntent:RecordingIntent){
  setResult(value);setIntent(currentIntent);
  if(currentIntent.completion){setEndItem(currentIntent.completion.item);setSelected(currentIntent.completion.item);}
  if(value.kind==='COMMITTED'){
   const item=String(JSON.parse(currentIntent.body).args.payload.item);
   const matching=workPage?.rows.find(x=>x.item_id===item);if(matching)setUnitName(matching.unit);
   // The immutable receipt is the success boundary. Ordinary saves need no
   // sequential summary/report reads or a second operator confirmation.
   if(!currentIntent.completion){
    if(!navigator.locks)throw Error('prv3StorageUnavailable');
    await navigator.locks.request(recordingScope(actor,factory),()=>acknowledgeIntent(localStorage,currentIntent,value.receipt));
    drafts.current.delete(item);defaulted.current.delete(item);goodTouched.current.delete(item);outputDrafts.current.delete(item);
    setIntent(null);setResult(null);setUnfinishedGroups([]);setDraft(initial);setHasWip(false);setSavedNotice(true);setOpen(false);setHistory(false);props.onCompletionClose?.();
    setTimeout(()=>(returnFocus.current||trigger.current)?.focus(),0);
   }
   void loadRecent();void props.refreshSnapshot?.().catch(()=>setRecentError('prv3RefreshAfterSave'));
  }
 }
 async function checkStatus(pending=intent){
  if(!pending||inFlight.current)return;inFlight.current=true;setBusy(true);setError('');
  try{if(!navigator.locks)throw Error('prv3StorageUnavailable');const value=await navigator.locks.request(recordingScope(actor,factory),()=>recoverRecording(pending,localStorage));await showResult(value,pending);}catch{setError('prv3StorageUnavailable');}
  finally{inFlight.current=false;setBusy(false);}
 }
 async function submitPayload(payload:Record<string,unknown>,completion?:CompletionTarget){
  if(inFlight.current)throw Error('prv3Unresolved');
  if(!allowed)throw Error('permissionError');
  inFlight.current=true;setBusy(true);setError('');
  try{
   if(!navigator.locks)throw Error('prv3StorageUnavailable');
   const pending=await navigator.locks.request(recordingScope(actor,factory),()=>prepareIntent(localStorage,actor,factory,payload,{completion}));
   setIntent(pending);const value=await postRecording(pending);await showResult(value,pending);
   if(value.kind!=='COMMITTED')throw Error(value.kind==='REJECTED'?value.error:'prv3Unconfirmed');
   return value.receipt;
  }catch(e){if(e instanceof Error&&['prv3StorageUnavailable','prv3Unresolved'].includes(e.message))setError(e.message);throw e;}
  finally{inFlight.current=false;setBusy(false);}
 }
 async function retryIntent(){
  if(!intent||inFlight.current)return;inFlight.current=true;setBusy(true);
  let committed=false;
  try{const value=await postRecording(intent);await showResult(value,intent);committed=value.kind==='COMMITTED';}finally{inFlight.current=false;setBusy(false);}
  if(committed&&intent.completion)await completeExecution(intent.completion);
 }
 async function completeExecution(target:CompletionTarget){
  if(inFlight.current)return;inFlight.current=true;setBusy(true);setEndState('pending');setError('');
  try{const value=await finishRecordedExecution(factory,target,props.command);summaryEpoch.current++;setSummaryLoading(false);setSummary(value);setEndState('ended');drafts.current.delete(target.item);outputDrafts.current.delete(target.item);defaulted.current.delete(target.item);goodTouched.current.delete(target.item);setDraft(initial);setUnfinishedGroups([]);setHasWip(false);void props.refreshSnapshot?.().catch(()=>setRecentError('prv3RefreshAfterSave'));}
  catch(e){setError(e instanceof Error&&['permissionError','recordingContextChanged','prv3SummaryUnavailable'].includes(e.message)?e.message:'prv3FinishPending');}
  finally{inFlight.current=false;setBusy(false);}
 }
 async function acknowledge(event:React.MouseEvent<HTMLButtonElement>){
  // This button is replaced by the form's Save control after a rejection.
  // Cancel its native default before React updates the footer association.
  event.preventDefault();
  if(!intent||!result||result.kind==='UNKNOWN'||inFlight.current)return;inFlight.current=true;setBusy(true);
  if(result.kind==='COMMITTED'&&intent.completion&&endState!=='ended'){inFlight.current=false;setBusy(false);return;}
  try{if(!navigator.locks)throw Error('prv3StorageUnavailable');await navigator.locks.request(recordingScope(actor,factory),()=>acknowledgeIntent(localStorage,intent,result.kind==='COMMITTED'?result.receipt:null));setIntent(null);setResult(null);
   if(result.kind==='COMMITTED'){drafts.current.delete(selected);defaulted.current.delete(selected);goodTouched.current.delete(selected);outputDrafts.current.delete(selected);setUnfinishedGroups([]);setDraft(initial);setHasWip(false);inFlight.current=false;close();}else{if(result.reason==='OVERPRODUCTION_CONFIRMATION_REQUIRED')setOverproduction(true);setRetry(n=>n+1);}
  }catch{setError('prv3StorageUnavailable');}finally{inFlight.current=false;setBusy(false);}
 }
 async function submit(event:React.FormEvent){
  event.preventDefault();if(!row||!occ||!workPage||loading||workError||summaryLoading||summaryError||!currentSummary||!canRecordWork(workPage,row)||intent||inFlight.current)return;
  setError('');
  try{
   if(expired)throw Error('prv3Expired');
   if(currentSummary.makeup_committed)throw Error('prv3MakeupCommitted');
   if(outputError||outputOptions?.item!==selected)throw Error('recordingUnavailable');
   let good:string,scrap:string;
   try{good=recordingNumber(draft.good);if(row.unit==='piece'&&good.includes('.'))throw Error();}catch{throw Error('prv3InvalidGood');}
   try{scrap=recordingNumber(draft.scrap);}catch{throw Error('prv3InvalidScrap');}
   const newGroups=outputMode?outputGroups(good,hasWip?unfinishedGroups:[],outputOptions!.operations,row.unit,crypto.randomUUID(),recovery?{lot_id:recovery.lot_id,input_quantity:draft.input,discarded_quantity:draft.discarded,scrap_kg:scrap}:null):null;
   if(outputMode&&hasWip&&!unfinishedGroups.length)throw Error('prv3WipRequired');
   const unfinished=hasWip?(outputMode?outputTotal(unfinishedGroups):recordingNumber(draft.unfinished)):'0';
   if([good,scrap,unfinished].every(v=>v==='0'))throw Error('prv3EmptyQuantity');
   if(hasWip&&(unfinished==='0'||(!outputMode&&draft.remaining.trim().length<3)))throw Error('prv3WipRequired');
   if(!technician)throw Error('prv3Technician');
   const completion=ending?{item:row.item_id,actual_start:row.actual_start}:undefined;
   const receipt=await submitPayload({unit_kind:'line',production_unit:row.line_id,item:row.item_id,technician,good,scrap_kg:scrap,discarded_quantity:recovery?recordingNumber(draft.discarded):'0',startup_kg:'0',
    unfinished,remaining_work:hasWip?(outputMode?'Complete selected operations':draft.remaining.trim()):'',notes:draft.notes,confirm_overproduction:draft.confirmed,input_lot:recovery?.lot_id||null,input_quantity:recovery?recordingNumber(draft.input):'0',...(newGroups?{output_groups:newGroups}:{}),
    recording_context:{version:3,execution_key:row.execution_key,occurrence_key:occ.occurrence_key,context_hash:row.context_hash,current_shift_quantity_confirmed:true}},completion);
   const pending=readPending();if(completion&&pending&&typeof pending==='object'&&pending.request===receipt.request_id)await completeExecution(completion);
  }catch(e){if(!readPending())setError(e instanceof Error?e.message:'dataWarning');}
 }
 function readPending(){try{return readIntent(localStorage,actor,factory);}catch{return true;}}
 const field=(key:'input'|'discarded'|'good'|'scrap'|'unfinished'|'remaining'|'notes',value:string)=>{if(key==='good')goodTouched.current.add(selected);setDraft(d=>({...d,[key]:value}));};
 const workMessage=recordingWorkMessage(workPage,row,selected,expired);
 const identity=s.tables.production_orders?.find(x=>x.id===selected),product=s.tables.products?.find(x=>x.id===identity?.product_id),line=s.tables.production_lines?.find(x=>x.id===identity?.line_id),request=s.tables.production_requests?.find(x=>x.id===identity?.request_id);
 const quantitySummary=currentSummary?<><dl className="prv3-quantity-summary">{[['prv3Requested',currentSummary.requested],['prv3Produced',currentSummary.produced_good||currentSummary.recorded_good],['recordingRemaining',currentSummary.remaining]].map(([label,value])=><div key={label}><dt>{t(label)}</dt><dd><bdi>{value}</bdi> {unit(currentSummary.unit)}</dd></div>)}</dl>{currentSummary.produced_good&&currentSummary.produced_good!==currentSummary.recorded_good&&<details className="prv3-details"><summary>{lang==='ar'?'التسجيل الأصلي':'Original recording'}</summary><bdi>{currentSummary.recorded_good}</bdi> {unit(currentSummary.unit)}</details>}</>:null;
 const similar=row&&recent.some(e=>e.recorded_by===actor&&sameMeasurement(e,row.item_id,draft.good,draft.scrap));
 const footer=(buttons:React.ReactNode)=><footer className="prv3-footer"><span>{t(!intent&&mode==='current'?'prv3CurrentShiftOnly':'productionRecording')}</span><div>{buttons}</div></footer>;
 const message=(key:string,kind='info')=><p className={`prv3-notice ${kind}`} role={kind==='error'?'alert':'status'}>{t(key)}</p>;
 const headerActions=<button type="button" className="prv3-language" onClick={props.onLanguageChange} disabled={busy||!props.onLanguageChange} lang={lang==='ar'?'en':'ar'}>{lang==='ar'?'English':'العربية'}</button>;
 return <div className="prv3-entry" dir={lang==='ar'?'rtl':'ltr'}>
  <div className="prv3-launch">{can('orders','view')&&can('lines','view')&&<PlanningChangeUpdates props={props} audience="PRODUCTION"/>}<button ref={trigger} className="primary" onClick={show} disabled={!allowed}>{t('prv3Record')}</button><button type="button" onClick={event=>{if(props.onProductionHistoryOpen){props.onProductionHistoryOpen();return;}returnFocus.current=event.currentTarget;setHistory(true);}}>{t('productionHistory')}</button>{can('orders','view')&&<QualityUpdateButton {...props}/>}</div>
  {savedNotice&&<p className="prv3-notice success" role="status">{t(typeof savedNotice==='string'?savedNotice:'prv3Saved')}</p>}
  {intent&&!open&&<div className="prv3-notice warning"><p>{t('prv3Retained')}</p><button type="button" onClick={show}>{t('prv3Check')}</button></div>}
  {!allowed&&message('prv3NoPermission')}
  {can('orders','approve')&&<HistoricalApprovalQueue {...props}/>}
  {open&&<Dialog title={t('prv3Record')} t={t} onClose={close} busy={busy} className="prv3-dialog" headerActions={headerActions}>
   <div className="prv3-body" ref={dialogRegion} dir={lang==='ar'?'rtl':'ltr'}>

    {!intent&&<div role="group" className="prv3-period-choice" aria-label={t('historicalPeriod')}><button type="button" aria-pressed={period==='current'} disabled={busy} onClick={()=>setPeriod('current')}>{t('historicalCurrent')}</button><button type="button" aria-pressed={period==='previous'} disabled={busy||!!endItem} onClick={()=>setPeriod('previous')}>{t('historicalPrevious')}</button></div>}
    {error&&<div id="prv3-form-feedback" tabIndex={-1}>{message(error,'error')}</div>}
    {busy?message(result?'prv3Checking':'recordingSaving'):null}
    {endState==='ended'&&!intent?<section className="prv3-result" role="status"><span className="prv3-result-icon"><Check/></span><h3>{t('prv3ExecutionEnded')}</h3><p><bdi>{currentSummary?.code}</bdi></p><p>{t('prv3NoRecordingAdded')}</p>{quantitySummary}</section>
    :result?.kind==='COMMITTED'?<section className="prv3-result" role="status"><span className="prv3-result-icon"><Check/></span><h3>{t('prv3Saved')}</h3><p><bdi>{currentSummary?.code||row?.item_code}</bdi>{row?' · '+name(row,'product'):''}</p><p>{t(intent?.completion?(endState==='ended'?'prv3SavedAndEnded':'prv3SavedEndPending'):'prv3SavedHelp')}</p>
      {quantitySummary}
      <div className={`prv3-values${[result.receipt.original_payload?.good,result.receipt.original_payload?.scrap_kg].some(value=>String(value??'').length>16)?' prv3-values-precise':''}`}><div><strong><bdi>{String(result.receipt.original_payload?.good??'—')}</bdi> {unit(unitName)}</strong><p>{t('recordingGood')}</p></div><div><strong><bdi>{String(result.receipt.original_payload?.scrap_kg??'—')}</bdi> {t('kg')}</strong><p>{t('recordingScrap')}</p></div></div>
      {result.current&&<details><summary>{t('prv3CurrentValues')}</summary><p>{t('recordingGood')}: <bdi>{String(result.current.good??'—')}</bdi> {unit(unitName)} · {t('recordingScrap')}: <bdi>{String(result.current.scrap_kg??'—')}</bdi> {t('kg')}</p></details>}
      {recentError&&message(recentError,'warning')}</section>
    :intent?<section className="prv3-result"><h3>{t(result?.kind==='REJECTED'?'prv3Rejected':'prv3Unconfirmed')}</h3><p>{t(result?.kind==='REJECTED'?(result.reason==='SHIFT_EXPIRED'?'prv3Expired':result.reason==='OVERPRODUCTION_CONFIRMATION_REQUIRED'?'recordingOverproductionConfirm':result.error):'prv3UnknownHelp')}</p>
      {result?.kind==='UNKNOWN'&&result.error!=='prv3Unconfirmed'&&message(result.error,'warning')}
      <details><summary>{t('prv3SubmissionDetails')}</summary><p>{t('prv3SameIntent')}</p><bdi className="prv3-reference">{intent.request}</bdi></details></section>
    :endOnly?<section className="prv3-end-confirm"><h3>{t('prv3EndWithout')}</h3>{quantitySummary}<p>{t('prv3EndWithoutConfirm')}</p><button type="button" onClick={()=>setEndOnly(false)} disabled={busy}>{t('cancel')}</button><button type="button" className="primary" disabled={busy||!allowed||!currentSummary?.actual_start} onClick={()=>{if(currentSummary?.actual_start)void completeExecution({item:selected,actual_start:currentSummary.actual_start});}}>{t('prv3ConfirmEnd')}</button></section>
    :period==='previous'?<HistoricalProductionRecording {...props} onSucceeded={state=>{setOpen(false);setSavedNotice(state==='APPROVED'?'historicalApprovedSaved':'historicalPendingSaved');props.onCompletionClose?.();}}/>:mode==='existing'?null:<>
     {workError?message(workError,'error'):loading?message('prv3Loading'):null}
     {workError&&<button type="button" onClick={()=>setRetry(n=>n+1)}>{t('refresh')}</button>}
     {!loading&&!workError&&workMessage&&message(workMessage,'warning')}
     {summaryError&&<>{message('prv3SummaryUnavailable','error')}<button type="button" onClick={()=>setRetry(n=>n+1)}>{t('refresh')}</button></>}
     {selected&&!row&&currentSummary&&<section className="prv3-work"><h3>{String(product?.[lang==='ar'?'name_ar':'name']||product?.name||currentSummary.code)}</h3><p><bdi>{String(request?.code||currentSummary.code)}</bdi> / <bdi>{currentSummary.code}</bdi> · {String(line?.[lang==='ar'?'name_ar':'name']||line?.name||'')}</p>{quantitySummary}</section>}
     {selected&&can('lines','view')&&<details className="prv3-details"><summary>{t('materialPreparation')}</summary><ProductionMaterials props={props} item={selected} onChanged={()=>{setRetry(v=>v+1);void props.refreshSnapshot?.();}}/></details>}
     <form id="prv3-record-form" onSubmit={submit} noValidate>
      <fieldset disabled={busy||!allowed}>
       {!pinned&&(workPage?.rows.length||0)>8&&<label>{t('prv3Search')}<input type="search" value={query} onChange={e=>setQuery(e.target.value)}/></label>}
       {!pinned&&<label>{t('prv3Work')}<select value={selected} onChange={e=>selectWork(e.target.value)} disabled={loading||!!workError}>
        <option value="">{t('prv3ChooseWork')}</option>{workPage?.rows.filter(w=>w.item_id===selected||!query||[w.product_name,w.product_name_ar,w.item_code,w.request_code,w.line_name,w.line_name_ar].some(v=>String(v||'').toLowerCase().includes(query.toLowerCase()))).map(w=><option key={w.item_id} value={w.item_id}>{name(w,'product')} · {w.request_code||w.item_code} / {w.item_code} · {name(w,'line')} · {t(w.status==='completed'?'prv3Completed':'prv3Active')}</option>)}
       </select></label>}
       {workPage?.next_cursor&&<button type="button" onClick={async()=>{setLoading(true);try{const response=await fetch('/api/production-shift-work?'+new URLSearchParams({factory,page_size:'100',cursor:workPage.next_cursor!}),{cache:'no-store'});const data=await response.json();if(!response.ok||data.factory_id!==factory||data.contract_version!==3)throw Error('shiftWorkChanged');setWorkPage({...data,rows:[...workPage.rows,...data.rows]});}catch{setWorkError('prv3WorkChanged');}finally{setLoading(false);}}}>{t('prv3MoreWork')}</button>}
       {row&&<>
        <section className="prv3-work"><h3>{name(row,'product')}</h3><p>{row.request_code&&row.request_code!==row.item_code&&<><bdi>{row.request_code}</bdi> / </>}<bdi>{row.item_code}</bdi> · {name(row,'line')} · {t(workKind)}</p><span className={`prv3-badge ${row.status==='completed'?'idle':'success'}`}>{t(row.status==='completed'?'prv3Completed':'prv3Active')}</span>{row.status==='completed'&&row.actual_finish&&<p>{t('prv3CompletedAt')} {formatTime(row.actual_finish,lang,String(s.factory?.timezone||occ?.timezone||'UTC'))}</p>}</section>
        {quantitySummary}

        {outputError&&message('recordingUnavailable','error')}
        {occ&&<details className="prv3-details"><summary>{t('prv3ShiftDetails')}</summary><p className="prv3-shift">{lang==='ar'?occ.name_ar||occ.name:occ.name} · <bdi>{occ.business_date}</bdi><br/>{formatTime(occ.starts_at,lang,String(s.factory?.timezone||occ.timezone))} — {formatTime(occ.ends_at,lang,String(s.factory?.timezone||occ.timezone))}</p></details>}
        {currentSummary?.makeup_committed&&message('prv3MakeupCommitted','warning')}
        {row.status==='completed'&&row.same_shift_recording_available===true&&canRecordWork(workPage,row)&&message('prv3CompletedSameShift','info')}


        {!technicians.some(x=>x.user_id===actor)&&<label>{t('recordingTechnician')}<select value={technician} onChange={e=>setTechnician(e.target.value)}><option value="">{t('recordingChooseTechnician')}</option>{technicians.map(x=><option key={String(x.id)} value={String(x.id)}>{String(x.display_name)}</option>)}</select></label>}
        <div className="prv3-fields"><label>{t('recordingGood')} · {unit(row.unit)}<input aria-invalid={error==='prv3InvalidGood'} aria-describedby={error?'prv3-form-feedback':undefined} inputMode="decimal" autoComplete="off" value={draft.good} onChange={e=>field('good',e.target.value)} placeholder="0" maxLength={2048}/></label>
        <label>{t('recordingScrap')} · {t('kg')}<input aria-invalid={error==='prv3InvalidScrap'} aria-describedby={error?'prv3-form-feedback':undefined} inputMode="decimal" autoComplete="off" value={draft.scrap} onChange={e=>field('scrap',e.target.value)} maxLength={2048}/><small>{t('prv3ZeroScrap')}</small></label></div>
        {similar&&message('prv3Similar','warning')}
        {Number(outputOptions?.replacement_allowance)>0&&<p role="status">{lang==='ar'?'السماح التعويضي المتبقي':'Replacement allowance remaining'}: {outputOptions?.replacement_allowance} {unit(row.unit)}. {lang==='ar'?'يُربط الإنتاج الإضافي تلقائياً بالسماح المعتمد دون زيادة الطلب الأصلي.':'Additional output is attributed to the authorized allowance; original demand stays unchanged.'}</p>}
        {recovery&&<fieldset className="prv3-fields"><legend>{lang==='ar'?'معالجة المواد المصروفة':'Process issued material'}</legend><p>{lang==='ar'?'المتبقي من المدخل المخصص':'Allocated input remaining'}: {recovery.remaining} {unit(row.unit)} · {recovery.material_status}</p><label>{lang==='ar'?'المدخل المستخدم فعلياً':'Input actually processed'} · {unit(row.unit)}<input required inputMode="decimal" value={draft.input} onChange={e=>field('input',e.target.value)}/></label><label>{lang==='ar'?'الكمية المستبعدة من المدخل':'Discarded input quantity'} · {unit(row.unit)}<input required inputMode="decimal" value={draft.discarded} onChange={e=>field('discarded',e.target.value)}/></label><p>{lang==='ar'?'المدخل = المكتمل + غير المكتمل + المستبعد. سجل وزن الخردة بالكيلوغرام بشكل منفصل.':'Input = Finished + Unfinished + Discarded. Record Scrap weight separately in KG.'}</p></fieldset>}
        <details className="prv3-details"><summary>{t('prv3Optional')}</summary><label className="prv3-check"><input type="checkbox" checked={hasWip} onChange={e=>setHasWip(e.target.checked)}/>{t('prv3IncludeWip')}</label>

         {hasWip&&(outputMode?<OutputGroupsEditor groups={unfinishedGroups} onChange={setUnfinishedGroups} operations={outputOptions!.operations} unit={unit(row.unit)} lang={lang}/>:<div className="prv3-fields"><label>{t('unfinishedQuantity')} · {unit(row.unit)}<input inputMode="decimal" value={draft.unfinished} onChange={e=>field('unfinished',e.target.value)}/></label><label>{t('unfinishedRemainingWork')}<input value={draft.remaining} minLength={3} maxLength={2000} onChange={e=>field('remaining',e.target.value)}/></label></div>)}
         <label>{t('notes')}<textarea value={draft.notes} maxLength={2000} onChange={e=>field('notes',e.target.value)}/></label></details>
        {overproduction&&<label className="prv3-check"><input type="checkbox" checked={draft.confirmed} onChange={e=>setDraft(d=>({...d,confirmed:e.target.checked}))}/>{t('recordingOverproductionConfirm')}</label>}
       </>}
      </fieldset>
     </form>
     <details className="prv3-details"><summary>{t('prv3Recent')}</summary>{recentError&&message(recentError,'warning')}{recent.length?recent.map(entry=><div className="prv3-recent" key={entry.id}><p><strong><bdi>{entry.good}</bdi> {unit(entry.unit)}</strong> · {t('recordingScrap')} <bdi>{entry.scrap_kg}</bdi> {t('kg')}</p><p><bdi>{entry.request_code}</bdi> · {lang==='ar'?entry.line_name_ar||entry.line_name:entry.line_name} · {formatTime(entry.recorded_at,lang,String(s.factory?.timezone||'UTC'))}</p></div>):<p>{t('prv3NoRecent')}</p>}{props.onProductionHistoryOpen&&<button type="button" onClick={()=>{close();props.onProductionHistoryOpen?.();}}>{t('productionHistory')}</button>}</details>
     {!outputMode&&!endItem&&<details className="prv3-details"><summary>{t('prv3OtherOptions')}</summary><p>{t('prv3OtherHelp')}</p><button type="button" onClick={()=>{setExistingMounted(true);setMode('existing');}}>{t('prv3OpenExisting')}</button></details>}
    </>}
    {existingMounted&&<div hidden={mode!=='existing'||!!intent}><p className="prv3-notice">{t('prv3ExistingHelp')}</p><button type="button" onClick={()=>setMode('current')} disabled={busy}>{t('prv3BackToCurrent')}</button>
      <ProductionRecording {...props} surface="record" exactRecording command={async(command,args)=>{
       if(command!=='record_lean_production')return props.command(command,args);
       return submitPayload(args.payload as Record<string,unknown>);
      }}/></div>}
   </div>
   {endState==='ended'&&!intent?footer(<button type="button" className="primary" onClick={close}>{t('done')}</button>)
   :result?.kind==='COMMITTED'?footer(intent?.completion&&endState!=='ended'?<><button type="button" onClick={close} disabled={busy}>{t('prv3Keep')}</button><button type="button" className="primary" disabled={busy||!allowed} onClick={()=>void completeExecution(intent.completion!)}>{t('prv3RetryEnd')}</button></>:<button type="button" className="primary" onClick={acknowledge} disabled={busy}>{t('done')}</button>)
   :intent?footer(<><button type="button" onClick={close} disabled={busy}>{t('prv3Keep')}</button>{result?.kind==='REJECTED'?<button type="button" className="primary" onClick={acknowledge} disabled={busy}>{t('prv3ReviewDraft')}</button>:<><button type="button" onClick={()=>void checkStatus()} disabled={busy}>{t('prv3Check')}</button><button type="button" className="primary" onClick={()=>void retryIntent()} disabled={busy||!allowed}>{t('prv3RetrySame')}</button></>}</>)
   :endOnly||period==='previous'?null:mode==='current'?footer(<><button type="button" onClick={close} disabled={busy}>{t('cancel')}</button>{ending&&<button type="button" onClick={()=>setEndOnly(true)} disabled={busy||!allowed||summaryLoading||summaryError}>{t('prv3EndWithout')}</button>}<button key="submit-recording" className="primary" form="prv3-record-form" type="submit" disabled={busy||!row||!occ||loading||!!workError||summaryLoading||summaryError||!currentSummary||currentSummary.makeup_committed||!canRecordWork(workPage,row)||!allowed||expired||outputError||outputOptions?.item!==selected}>{busy?t('recordingSaving'):t(ending?'prv3SaveAndEnd':'prv3Save')}</button></>):null}
  </Dialog>}
  {history&&<Dialog title={t('productionHistory')} t={t} onClose={close} className="prv3-dialog prv3-history" headerActions={headerActions}><div className="prv3-body"><ProductionRecording {...props} surface="history"/></div></Dialog>}
 </div>;
}
