import {useEffect,useRef,useState} from 'react';
import {formatTime,localName} from '@/components/ui';
import {formatDuration} from '@/utils/production-flow.mjs';
import {formatLocalInput,localDateTimeToUtc} from '@/utils/manufacturing.mjs';
import {productionDelayState,affectedPlannedWork,validDelayCommand,submitDelay,delayOutcome} from '@/utils/production-delay.mjs';
import type {FeatureProps} from './types';
import type {Row} from '@/types';
type DelayEvent={id:string;reason:string;estimated_finish:string|null;created_at:string;actor_name:string;planned_finish:string;plan_revision:number};
export type DelayRow={factory?:string;item:string;code:string;status:string;actual_finish:string|null;actual_line:string|null;planned_line:string|null;planned_finish:string|null;grace_minutes:number;last:DelayEvent|null;fingerprint:string;history?:DelayEvent[];history_total?:number};
type DelayBoard={factory:string;grace_minutes:number;rows:DelayRow[]};
type Intent={factory:string;operation:'REASON'|'POLICY';payload:Record<string,unknown>;request_id:string};
export function useProductionDelays(props:FeatureProps){
 const {snapshot:s,can}=props,factory=String(s.factory?.id||''),actor=String(s.user.id),allowed=can('orders','view'),identity=factory+':'+actor;
 const [state,setState]=useState<{identity:string;data:DelayBoard|null;error:string}>({identity:'',data:null,error:''}),[revision,setRevision]=useState(0);
 useEffect(()=>{if(!allowed)return;const refresh=()=>setRevision(v=>v+1),timer=setInterval(refresh,60000);window.addEventListener('focus',refresh);return()=>{clearInterval(timer);window.removeEventListener('focus',refresh);};},[allowed,identity]);
 useEffect(()=>{if(!allowed)return;const abort=new AbortController();fetch('/api/production-delay?'+new URLSearchParams({factory}),{signal:abort.signal,cache:'no-store'}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error||'f46ReadUnavailable');if(d.factory!==factory||!Number.isInteger(d.grace_minutes)||!Array.isArray(d.rows))throw Error('f46ReadUnavailable');if(!abort.signal.aborted)setState({identity,data:d,error:''});}).catch(e=>{if(!abort.signal.aborted)setState(v=>({identity,data:['permissionError','unauthorized'].includes(e.message)?null:v.identity===identity?v.data:null,error:e.message}));});return()=>abort.abort();},[factory,identity,allowed,s.fetchedAt,revision]);
 return {data:allowed&&state.identity===identity?state.data:null,error:allowed&&state.identity===identity?state.error:'',reload:()=>setRevision(v=>v+1)};
}
function useDelaySave(props:FeatureProps,scope:string,onCommitted:()=>void){
 const factory=String(props.snapshot.factory?.id||''),key=`factory-lean:delay:v1:${props.snapshot.user.id}:${factory}:${scope}`;
 const [pending,setPending]=useState<Intent|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[saved,setSaved]=useState(false),[storageBlocked,setStorageBlocked]=useState(false),lock=useRef(false),identity=useRef(key),committed=useRef(onCommitted);identity.current=key;committed.current=onCommitted;
 useEffect(()=>{setPending(null);setError('');setSaved(false);setStorageBlocked(false);try{const text=localStorage.getItem(key);if(text){const i=JSON.parse(text);if(!validDelayCommand(i)||i.factory!==factory||(scope==='POLICY'?i.operation!=='POLICY':i.payload.item!==scope))throw Error();setPending(i);}}catch{setStorageBlocked(true);setError('executionPendingStorage');}},[key,factory,scope]);
 async function accept(result:{outcome:string;error?:string},intent:Intent){if(result.outcome==='UNKNOWN'){if(identity.current===key)setError('f46OutcomeUnknown');return;}
  try{localStorage.removeItem(key);}catch{if(identity.current===key)setError('executionPendingStorage');return;}
  if(identity.current!==key)return;setPending(null);if(result.outcome==='REJECTED'){setError(result.error||'f46Invalid');return;}setSaved(true);setError('');committed.current();
 }
 async function run(operation:'REASON'|'POLICY',payload:Record<string,unknown>){if(lock.current||pending||storageBlocked)return;const intent={factory,operation,payload,request_id:crypto.randomUUID()};if(!validDelayCommand(intent)){setError('f46Invalid');return;}lock.current=true;setBusy(true);setError('');setSaved(false);
  try{try{localStorage.setItem(key,JSON.stringify(intent));}catch{setStorageBlocked(true);throw Error('executionPendingStorage');}setPending(intent);await accept(await submitDelay(intent),intent);}catch(e){setError(e instanceof Error&&e.message==='executionPendingStorage'?e.message:'f46OutcomeUnknown');}finally{lock.current=false;setBusy(false);}
 }
 async function recover(resend=false){if(lock.current||!pending)return;lock.current=true;setBusy(true);try{await accept(await(resend?submitDelay(pending):delayOutcome(pending)),pending);}finally{lock.current=false;setBusy(false);}}
 return {pending,busy,error,saved,storageBlocked,run,recover};
}
function Recovery({action,t}:{action:ReturnType<typeof useDelaySave>;t:FeatureProps['t']}){return <>{action.busy&&<p role="status">{t('recordingSaving')}</p>}{action.error&&<p role="alert">{t(action.error)}</p>}{action.pending&&!action.busy&&<><p>{t('f46OutcomeUnknown')}</p><button type="button" onClick={()=>void action.recover()}>{t('executionCheckOutcome')}</button><button type="button" onClick={()=>void action.recover(true)}>{t('f46RetryExact')}</button></>}</>;}
export function ProductionDelaySetting({props,grace,onSaved}:{props:FeatureProps;grace:number;onSaved:()=>void}){
 const factory=String(props.snapshot.factory?.id||''),[state,setState]=useState({factory,value:String(grace),saved:grace}),action=useDelaySave(props,'POLICY',onSaved);
 useEffect(()=>setState(v=>({factory,value:v.factory===factory&&v.value!==String(v.saved)?v.value:String(grace),saved:grace})),[factory,grace]);const value=Number(state.value),valid=/^\d+$/.test(state.value)&&Number.isInteger(value)&&value<=2147483647;
 return <section className="f46-setting"><label>{props.t('f46GraceMinutes')}<input type="number" min="0" max="2147483647" step="1" value={state.factory===factory?state.value:String(grace)} disabled={!props.can('factory','edit')||action.busy||!!action.pending} onChange={e=>setState(v=>({...v,value:e.target.value}))}/></label><p className="muted">{props.t('f46GraceHelp')}</p><button type="button" disabled={!props.can('factory','edit')||!valid||value===grace||action.busy||!!action.pending||action.storageBlocked} onClick={()=>void action.run('POLICY',{grace_minutes:value})}>{props.t('save')}</button>{action.saved&&<p role="status">{props.t('saved')}</p>}<Recovery action={action} t={props.t}/></section>;
}
export function ProductionDelayNotice({props,row,onSaved,showOrder=false,orders=[]}:{props:FeatureProps;row:DelayRow;onSaved:()=>void;showOrder?:boolean;orders?:Row[]}){
 const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||''),zone=String(s.factory?.timezone||'UTC');
 const [now,setNow]=useState(Date.now),[editing,setEditing]=useState(false),[context,setContext]=useState<DelayRow|null>(null),[revision,setRevision]=useState(0),[loading,setLoading]=useState(false),[error,setError]=useState(''),[reason,setReason]=useState(''),[estimate,setEstimate]=useState(''),initialized=useRef(false);
 const state=productionDelayState(row,now),action=useDelaySave(props,row.item,()=>{setEditing(false);initialized.current=false;setContext(null);onSaved();});
 useEffect(()=>{const timer=setTimeout(()=>setNow(Date.now()),state.nextTick);return()=>clearTimeout(timer);},[now,state.nextTick]);
 useEffect(()=>{if(!editing)return;const abort=new AbortController();setLoading(true);setError('');fetch('/api/production-delay?'+new URLSearchParams({factory,item:row.item}),{cache:'no-store',signal:abort.signal}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error||'f46ReadUnavailable');if(d.factory!==factory||d.item!==row.item||!/^[a-f0-9]{64}$/.test(d.fingerprint))throw Error('f46ReadUnavailable');if(abort.signal.aborted)return;setContext(d);if(!initialized.current){setReason(d.last?.reason||'');setEstimate(d.last?.estimated_finish?formatLocalInput(d.last.estimated_finish,zone):'');initialized.current=true;}}).catch(e=>{if(!abort.signal.aborted)setError(e.message);}).finally(()=>{if(!abort.signal.aborted)setLoading(false);});return()=>abort.abort();},[factory,row.item,editing,revision,zone]);
 const affected=affectedPlannedWork(row,orders,now),line=s.tables.production_lines?.find(l=>l.id===row.actual_line);
 if(!state.delayed&&!state.unknown&&!action.pending)return null;
 const elapsed=state.seconds<60?t('f46UnderMinute'):formatDuration(Math.floor(state.seconds/60),lang),editable=can('orders','edit');
 return <section className="f46-delay" aria-label={t('f46BehindSchedule')} data-delay-item={row.item}>
  <div className="f46-delay-heading">{showOrder&&<strong><bdi>{row.code}</bdi> · {localName(line,lang)}</strong>}<strong>{t(state.unknown?'f46PlanUnknown':'f46BehindSchedule')}{state.delayed?' · '+elapsed:''}</strong></div>
  {state.delayed&&<p>{t('executionPlannedFinish')}: {formatTime(row.planned_finish,lang,zone)}</p>}
  {state.pending&&<p className="f46-pending" role="status">{t('f46ReasonPending').replace('{minutes}',String(row.grace_minutes))}</p>}
  {row.last&&<p>{t('f46DelayReason')}: {row.last.reason}</p>}
  {row.last?.estimated_finish&&<p>{t('f46Estimate')}: {formatTime(row.last.estimated_finish,lang,zone)}{state.estimateExpired?' · '+t('f46EstimatePassed'):''}</p>}
  {!!affected.length&&<p>{t('f46PotentialImpact')}: <bdi>{String(affected[0].code)}</bdi> · {formatTime(affected[0].start_time,lang,zone)}{affected.length>1?' · +'+(affected.length-1):''}. {t('f46PlanUnchanged')}</p>}
  {state.delayed&&<button type="button" onClick={()=>{setEditing(v=>!v);if(editing)initialized.current=false;}} disabled={action.busy}>{t(editing?'close':editable?row.last?'f46UpdateDetails':'f46RecordReason':'f46ViewHistory')}</button>}
  {action.saved&&<p role="status">{t('f46Recorded')}</p>}
  {editing&&<>{loading&&<p role="status">{t('loading')}</p>}{error&&<p role="alert">{t(error)}</p>}{context&&<>
   {editable&&<form onSubmit={async e=>{e.preventDefault();if(action.busy||action.pending||loading)return;const form=new FormData(e.currentTarget),actualReason=String(form.get('reason')||'').trim(),actualEstimate=String(form.get('estimated_finish')||'');setError('');try{await action.run('REASON',{item:row.item,reason:actualReason,estimated_finish:actualEstimate?localDateTimeToUtc(actualEstimate,zone):null,fingerprint:context.fingerprint});}catch{setError('f46EstimateFuture');}}}><fieldset disabled={action.busy||!!action.pending}>
    <label>{t('f46DelayReason')}<textarea name="reason" required minLength={3} maxLength={500} value={reason} onChange={e=>setReason(e.target.value)}/></label>
    <label>{t('f46Estimate')} · {t('f46Optional')}<input name="estimated_finish" type="datetime-local" value={estimate} onChange={e=>setEstimate(e.target.value)}/></label>
    <p className="muted">{t('f46Nonblocking')}</p><button className="primary" disabled={loading||reason.trim().length<3||action.storageBlocked}>{t('save')}</button>
   </fieldset></form>}
   {!!context.history?.length&&<details><summary>{t('f46RecentHistory')} ({context.history.length}/{context.history_total})</summary><ul>{context.history.map(e=><li key={e.id}><bdi>{formatTime(e.created_at,lang,zone)}</bdi> · {e.actor_name} · {e.reason}{e.estimated_finish?' · '+t('f46Estimate')+': '+formatTime(e.estimated_finish,lang,zone):''}</li>)}</ul></details>}
  </>}</>}
  <Recovery action={action} t={t}/>{(action.error==='f46Changed'||error)&&editing&&<button type="button" disabled={loading||action.busy||!!action.pending} onClick={()=>setRevision(v=>v+1)}>{t('refresh')}</button>}
 </section>;
}
