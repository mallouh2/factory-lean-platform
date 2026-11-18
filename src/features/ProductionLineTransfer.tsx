import {useEffect,useRef,useState} from 'react';
import {localName} from '@/components/ui';
import {pendingExecution,retainExecution,clearExecution,submitExecution,executionOutcome,type ExecutionIntent,type ExecutionResult} from '@/services/production-execution-client';
import type {FeatureProps} from './types';
import type {Row} from '@/types';

type Materials={reason?:string;rows?:{name:string;name_ar?:string;missing:string;unit:string}[];legacy?:{name:string;name_ar?:string;held:string;unit:string}[]};
type Destination={machine:string;name:string;name_ar:string;line:string|null;line_name:string;line_name_ar:string;status:string;compatible:boolean;ready:boolean;blocker:string|null;materials:Materials|null;physical?:{machine?:{name:string;name_ar:string}}};
type Context={factory:string;item:string;source_machine:string;fingerprint:string;order:Row;remaining:string;requires_output_confirmation:boolean;rows:Destination[]};
export default function ProductionLineTransfer({props,source,orders,preferred,onTransferred}:{props:FeatureProps;source:Row;orders:Row[];preferred?:string;onTransferred:(machine:string)=>void}){
 const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||''),actor=String(s.user.id),[choice,setChoice]=useState(preferred||String(orders.find(o=>o.status==='active')?.id||orders[0]?.id||''));
 const id=String(orders.find(o=>o.id===choice)?.id||orders.find(o=>o.status==='active')?.id||orders[0]?.id||''),[context,setContext]=useState<Context|null>(null),[target,setTarget]=useState(''),[reason,setReason]=useState(''),[confirmed,setConfirmed]=useState(false);
 const [loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[materials,setMaterials]=useState<Materials|null>(null),[pending,setPending]=useState<ExecutionIntent|null>(null),[done,setDone]=useState(false),[reload,setReload]=useState(0),submitting=useRef(false);
 const editable=can('orders','edit')&&can('centers','edit'),selected=context?.rows.find(r=>r.machine===target),message=(key:string)=>{const translated=t(key==='incompatible_alternative'?'incompatibleAlternative':key);return translated===key?t('executionRejected'):translated;};
 useEffect(()=>{setContext(null);setTarget('');setConfirmed(false);setReason('');setError('');setNotice('');setMaterials(null);setDone(false);try{setPending(id?pendingExecution(localStorage,actor,factory,id):null);}catch{setError('executionPendingStorage');}},[actor,factory,id,source.id]);
 useEffect(()=>{if(!id||!can('orders','view'))return;const abort=new AbortController();setLoading(true);
  fetch('/api/production-execution?'+new URLSearchParams({factory,item:id,mode:'line-transfer',source_machine:String(source.id)}),{cache:'no-store',signal:abort.signal}).then(async response=>{const body=await response.json();if(!response.ok)throw Error(body.error||'dataWarning');const c=body.data as Context;if(c?.factory!==factory||c.item!==id||c.source_machine!==source.id||!Array.isArray(c.rows)||!/^[a-f0-9]{64}$/.test(c.fingerprint))throw Error('dataWarning');if(!abort.signal.aborted)setContext(c);}).catch(e=>{if(!abort.signal.aborted)setError(e instanceof Error?e.message:'dataWarning');}).finally(()=>{if(!abort.signal.aborted)setLoading(false);});return()=>abort.abort();
 },[factory,id,source.id,s.fetchedAt,reload,can]);
 async function outcome(result:ExecutionResult,intent:ExecutionIntent){
  if(result.outcome==='UNKNOWN'){setError(result.error);return;}
  try{clearExecution(localStorage,actor,intent);setPending(null);}catch{setError('executionPendingStorage');}
  if(result.outcome==='REJECTED'){setError(result.error);setMaterials(result.materials||null);setContext(null);setReload(n=>n+1);return;}
  setDone(true);setNotice(intent.operation==='TRANSFER_LINE'?'f20Transferred':intent.operation==='INTERRUPT'?'executionPaused':intent.operation==='RESUME'?'executionResumed':'executionStarted');setError('');
  try{if(await props.refreshSnapshot?.()===false){setNotice('executionRefreshAfterSuccess');return;}if(intent.operation==='TRANSFER_LINE'&&intent.alternative_machine)onTransferred(intent.alternative_machine);}catch{setNotice('executionRefreshAfterSuccess');}
 }
 async function recover(){if(submitting.current||!pending)return;submitting.current=true;setBusy(true);try{await outcome(await executionOutcome(pending),pending);}finally{submitting.current=false;setBusy(false);}}
 async function transfer(e:React.FormEvent){e.preventDefault();if(submitting.current||pending||done||!context||!selected?.ready||!editable)return;
  submitting.current=true;setBusy(true);setError('');setMaterials(null);
  try{const intent:ExecutionIntent={factory,item:id,operation:'TRANSFER_LINE',source_machine:String(source.id),alternative_machine:selected.machine,reason:reason.trim(),fingerprint:context.fingerprint,request_id:crypto.randomUUID(),output_confirmed:confirmed};retainExecution(localStorage,actor,intent);setPending(intent);await outcome(await submitExecution(intent),intent);}catch(e){setError(e instanceof Error?e.message:'executionOutcomeUnknown');}finally{submitting.current=false;setBusy(false);}
 }
 const evidence=materials||selected?.materials,missing=evidence?.rows?.filter(r=>/^\d+(\.\d+)?$/.test(String(r.missing))&&/[1-9]/.test(String(r.missing)))||[];
 return <section className="ff2-operational-section f20-transfer" aria-label={t('f20AvailableAlternatives')}>
  <h4>{t('f20AvailableAlternatives')}</h4><p className="muted">{t('f20TransferHelp')}</p>
  {!id?<p>{t('f20NoEligibleOrder')}</p>:<>
   <label>{t('orders')}<select value={id} disabled={busy||!!pending} onChange={e=>setChoice(e.target.value)}>{orders.map(o=><option key={String(o.id)} value={String(o.id)}>{String(o.code)} · {localName(s.tables.products?.find(p=>p.id===o.product_id),lang)}</option>)}</select></label>
   {loading&&<p role="status">{t('updating')}</p>}
   {context&&!context.rows.length&&<p>{t('f20NoConfiguredAlternative')}</p>}
   <div className="f20-destinations">{context?.rows.map(row=><button type="button" key={row.machine} aria-pressed={target===row.machine} disabled={busy||!!pending||done} onClick={()=>{setTarget(row.machine);setError('');setMaterials(null);}}>
    <strong dir="auto">{localName({name:row.name,name_ar:row.name_ar},lang)}</strong><span dir="auto">{lang==='ar'?row.line_name_ar||row.line_name:row.line_name} · {t(row.status)}</span><span>{t(row.compatible?'f20Compatible':'f20Incompatible')} · {row.ready?t('f20ReadyToValidate'):message(row.blocker||'dataWarning')}{row.physical?.machine&&<> · {localName(row.physical.machine,lang)}</>}</span>
   </button>)}</div>
   {selected&&<form onSubmit={transfer}><label>{t('f34Reason')}<textarea required minLength={3} maxLength={240} value={reason} disabled={busy||!!pending||done} onChange={e=>setReason(e.target.value)}/></label>
    {context?.requires_output_confirmation&&<label className="f34-confirm"><input type="checkbox" checked={confirmed} disabled={busy||!!pending||done} onChange={e=>setConfirmed(e.target.checked)}/>{t('f34OutputConfirmed')}</label>}
    {editable&&<button className="primary" aria-busy={busy} disabled={busy||loading||!!pending||done||!!error||!selected.ready||reason.trim().length<3||context?.requires_output_confirmation&&!confirmed}>{t(busy?'updating':'f20ContinueAlternativeLine')}</button>}
   </form>}
   {evidence?.reason&&<p>{message(evidence.reason)}</p>}
   {!!missing.length&&<ul>{missing.map((r,n)=><li key={n}>{lang==='ar'?r.name_ar||r.name:r.name}: <bdi>{r.missing} {t(r.unit)}</bdi></li>)}</ul>}
   {!!evidence?.legacy?.length&&<><p>{t('psLegacyOrderHelp')}</p><ul>{evidence.legacy.map((r,n)=><li key={n}>{lang==='ar'?r.name_ar||r.name:r.name}: <bdi>{r.held} {t(r.unit)}</bdi></li>)}</ul></>}
   {pending&&<p role="status">{t('f34RetryHelp')}</p>}{pending&&<button type="button" disabled={busy} onClick={()=>void recover()}>{t('executionCheckOutcome')}</button>}
   {!pending&&!done&&<button type="button" disabled={loading||busy} onClick={()=>{setError('');setReload(n=>n+1);}}>{t('refresh')}</button>}
  </>}
  {notice&&<p role="status">{t(notice)}</p>}{error&&<p role="alert">{message(error)}</p>}
 </section>;
}
