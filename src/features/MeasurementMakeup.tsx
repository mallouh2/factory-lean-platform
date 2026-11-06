import {useEffect,useRef,useState} from 'react';
import type {FeatureProps} from './types';
import {decimalCompare,quantityValid} from '@/utils/quality-quantities.mjs';
export type MeasurementShortage={source_shortage:string;available:string;allocated:string;ordinary_remaining:string;source_status:string;source_item_id:string;blocked_reason:string|null;work:{item_id:string;code:string;quantity:string;status:string}[]};
export default function MeasurementMakeup({props,output,unit,revision,state,onCommitted}:{props:FeatureProps;output:string;unit:string;revision:string;state:MeasurementShortage;onCommitted:()=>void}){
 const {lang,t,can}=props,factory=String(props.snapshot.factory?.id),say=(en:string,ar:string)=>lang==='ar'?ar:en;
 const key=['factory-lean:measurement-makeup',props.snapshot.user.id,factory,output].join(':'),authorized=can('orders','view')&&can('orders','edit')&&can('orders','create')&&can('orders','approve');
 const [quantity,setQuantity]=useState(state.available),[confirmed,setConfirmed]=useState(false),[pending,setPending]=useState(''),[ready,setReady]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[success,setSuccess]=useState('');const inFlight=useRef(false);
 useEffect(()=>{setReady(false);try{const raw=sessionStorage.getItem(key)||'';if(raw){const b=JSON.parse(raw);if(b.command!=='plan_measurement_makeup'||b.args.factory!==factory||b.args.target!==output)throw Error();}setPending(raw);setReady(true);}catch{setError('pcStorageError');}},[key,factory,output]);
 const available=decimalCompare(state.available,'0')===1&&!state.blocked_reason;
 async function submit(){if(inFlight.current||!authorized||!ready||!pending&&(!available||!confirmed||!quantityValid(quantity,unit,state.available)))return;inFlight.current=true;setBusy(true);setError('');try{
  const body=pending||JSON.stringify({command:'plan_measurement_makeup',args:{factory,target:output,payload:{quantity,recording_complete_confirmation:true},expected_revision:Number(revision),request_id:crypto.randomUUID()}});
  sessionStorage.setItem(key,body);if(sessionStorage.getItem(key)!==body)throw Error('pcStorageError');setPending(body);
  const response=await fetch('/api/manufactured-output',{method:'POST',headers:{'Content-Type':'application/json'},body,signal:AbortSignal.timeout(20000)}),data=await response.json();
  if(!response.ok){if(data.outcome==='REJECTED'){sessionStorage.removeItem(key);setPending('');onCommitted();}throw Error(response.status===403?'permissionError':'recordingContextChanged');}
  sessionStorage.removeItem(key);setPending('');setSuccess(data.data.code);onCommitted();void props.refreshSnapshot?.();
 }catch(e){setError(e instanceof Error?e.message:'dataWarning');}finally{inFlight.current=false;setBusy(false);}}
 if(decimalCompare(state.source_shortage,'0')!==1&&!pending&&!success)return null;
 return <section className="qu-section" aria-label={say('Unproduced quantity','الكمية غير المنتجة')}><h3>{say('Unproduced quantity','الكمية غير المنتجة')} · <bdi>{state.source_shortage} {t(unit)}</bdi></h3>
  <p className="qu-muted">{say('A recording measurement was corrected. This quantity was not produced; it is not rejected or unfinished stock.','تم تصحيح قياس مسجل. هذه الكمية لم تُنتج، وليست مخزوناً مرفوضاً أو غير مكتمل.')}</p>
  {state.blocked_reason==='CONTINUE_ORIGINAL'&&<p role="status">{say('Continue the original active job. Ordinary remaining production','تابع العمل الأصلي الجاري. الإنتاج العادي المتبقي')}: <bdi>{state.ordinary_remaining} {t(unit)}</bdi>.</p>}
  {state.work.map(w=><p key={w.item_id}>{say('Linked make-up work','عمل مرتبط لاستكمال النقص')}: <bdi>{w.code} · {w.quantity} {t(unit)}</bdi>{props.onOutputRelated&&<button className="qu-link" onClick={()=>props.onOutputRelated?.({factory,view:'planning',output,work:w.item_id})}>{say('Details','التفاصيل')}</button>}</p>)}
  {available&&authorized&&!pending&&!success&&<div className="qu-confirm"><p>{say('The original execution has ended. Create linked work for Planning only when its recording is complete. Nothing starts automatically.','انتهى التنفيذ الأصلي. أنشئ عملاً مرتبطاً للتخطيط فقط بعد اكتمال التسجيل. لن يبدأ أي عمل تلقائياً.')}</p>
   <label>{say('Make-up quantity','كمية استكمال النقص')} · {t(unit)}<input inputMode="decimal" value={quantity} disabled={busy} onChange={e=>setQuantity(e.target.value)}/></label><small>{say('Up to','حتى')} <bdi>{state.available} {t(unit)}</bdi></small>
   <label className="prv3-check"><input type="checkbox" checked={confirmed} disabled={busy} onChange={e=>setConfirmed(e.target.checked)}/>{say('All output from the ended job has been recorded.','تم تسجيل كل الإنتاج من العمل المنتهي.')}</label>
   <button className="primary" disabled={busy||!ready||!confirmed||!quantityValid(quantity,unit,state.available)} onClick={()=>void submit()}>{busy?t('saving'):say('Create linked make-up work','إنشاء عمل مرتبط لاستكمال النقص')}</button></div>}
  {pending&&<p role="alert">{say('Result unconfirmed. Retry the same request.','النتيجة غير مؤكدة. أعد الطلب نفسه.')} <button disabled={busy||!authorized||!ready} onClick={()=>void submit()}>{t('retry')}</button></p>}
  {success&&<p role="status">{say('Created for Planning','تم الإنشاء للتخطيط')}: <bdi>{success}</bdi></p>}{error&&<p role="alert">{t(error)}</p>}
 </section>;
}
