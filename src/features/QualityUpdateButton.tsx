import {useEffect,useRef,useState} from 'react';
import {Dialog,formatTime} from '@/components/ui';
import NavigationIcon from '@/components/NavigationIcon';
import {OutputDetails,type OutputNotice} from './ManufacturedOutput';
import {outputTotal} from '@/utils/manufactured-output.mjs';
import {decimalSubtract} from '@/utils/quality-quantities.mjs';
import type {FeatureProps} from './types';

type Notices={available:boolean;rows:OutputNotice[];unread_count:number;total:number;has_more:boolean};
export default function QualityUpdateButton(props:FeatureProps){
 const {snapshot:s,t,lang}=props,factory=String(s.factory?.id||''),say=(en:string,ar:string)=>lang==='ar'?ar:en;
 const key=`factory-lean:quality-notices:${s.user.id}:${factory}`;
 const [data,setData]=useState<Notices|null>(null),[page,setPage]=useState(0),[open,setOpen]=useState(false),[selected,setSelected]=useState<OutputNotice|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[pending,setPending]=useState(''),[revision,setRevision]=useState(0),[ready,setReady]=useState(false);
 const lock=useRef(false);
 useEffect(()=>{setData(null);setSelected(null);setReady(false);try{const saved=sessionStorage.getItem(key)||'';if(saved){const b=JSON.parse(saved);if(b.command!=='manufactured_output_command'||b.args.factory!==factory||b.args.operation!=='ACKNOWLEDGE'||typeof b.args.request_id!=='string')throw Error();}setPending(saved);setReady(true);}catch{setError('pcStorageError');}},[factory,key]);
 useEffect(()=>{const abort=new AbortController();fetch('/api/manufactured-output?'+new URLSearchParams({factory,mode:'notifications',page:String(page)}),{cache:'no-store',signal:abort.signal}).then(async r=>{if(!r.ok)throw Error('dataWarning');const d=await r.json();const count=typeof d.unread_count==='string'&&/^(0|[1-9]\d*)$/.test(d.unread_count)?Number(d.unread_count):d.unread_count;if(!Array.isArray(d.rows)||d.available&&(!Number.isSafeInteger(count)||count<0))throw Error('dataWarning');setData({...d,unread_count:count});}).catch(e=>{if(e.name!=='AbortError')setError('dataWarning');});return()=>abort.abort();},[factory,page,revision,s.fetchedAt]);
 async function acknowledge(row?:OutputNotice){
  if(lock.current||!ready||!pending&&(!row?.unread||!row.notification_revision))return;
  lock.current=true;setBusy(true);setError('');
  const body=pending||JSON.stringify({command:'manufactured_output_command',args:{factory,operation:'ACKNOWLEDGE',target:row!.id,payload:{quality_revision:Number(row!.notification_revision)},expected_revision:Number(row!.revision),request_id:crypto.randomUUID()}});
  try{sessionStorage.setItem(key,body);if(sessionStorage.getItem(key)!==body)throw Error('pcStorageError');setPending(body);
   const r=await fetch('/api/manufactured-output',{method:'POST',headers:{'Content-Type':'application/json'},body,signal:AbortSignal.timeout(20000)}),result=await r.json();
   if(!r.ok){if(result.outcome==='REJECTED'){sessionStorage.removeItem(key);setPending('');setRevision(n=>n+1);}throw Error(r.status===403?'permissionError':result.error==='recordingContextChanged'?'recordingContextChanged':'dataWarning');}
   if(result.data?.output_id!==JSON.parse(body).args.target)throw Error('dataWarning');
   sessionStorage.removeItem(key);setPending('');setRevision(n=>n+1);setSelected(current=>current&&current.id===result.data.output_id?{...current,unread:false}:current);
  }catch(e){setError(e instanceof Error?e.message:'dataWarning');}finally{lock.current=false;setBusy(false);}
 }
 const count=data?.unread_count||0,title=say('Quality Updates','تحديثات الجودة');
 return <><button type="button" className={`quality-updates-button${count?' has-unread':''}`} aria-label={`${title}${count?' · '+count.toLocaleString(lang):''}`} onClick={()=>{setOpen(true);setSelected(null);}}><NavigationIcon name="notifications"/>{title}{count>0&&<span className="quality-unread-count" aria-label={say('Unread','غير مقروء')}>{count.toLocaleString(lang)}</span>}</button>
 {open&&<Dialog title={title} t={t} busy={busy} onClose={()=>setOpen(false)} className="prv3-dialog quality-updates-dialog" headerActions={<button onClick={props.onLanguageChange} disabled={!props.onLanguageChange}>{lang==='ar'?'English':'العربية'}</button>}><div className="prv3-body" dir={lang==='ar'?'rtl':'ltr'}>
  {error&&<p role="alert">{t(error)} <button onClick={()=>{setError('');setRevision(n=>n+1);}}>{t('refresh')}</button></p>}
  {pending&&<p role="alert">{say('Reading is not yet confirmed. Retry the same acknowledgement.','لم تتأكد القراءة بعد. أعد محاولة التأكيد نفسه.')} <button disabled={busy||!ready} onClick={()=>void acknowledge()}>{t('retry')}</button></p>}
  {selected?<><button onClick={()=>setSelected(null)} disabled={busy}>{t('back')}</button><OutputDetails row={selected} lang={lang} props={props} view="production"/></>:<>
   {!data&&!error&&<p role="status">{t('loading')}</p>}
   {data?.available===false&&<p role="status">{t('notAvailable')}</p>}
   {data?.available&&!data.rows.length&&<p role="status">{say('No material Quality updates.','لا توجد تحديثات جوهرية من الجودة.')}</p>}
   <div className="quality-notice-list">{data?.rows.map(row=><article key={row.id} data-unread={row.unread}><button disabled={busy||!!pending} onClick={()=>{setSelected(row);if(row.unread)void acknowledge(row);}}><strong><bdi>{row.item_code||row.request_code}</bdi> · {lang==='ar'?row.product_name_ar||row.product_name:row.product_name}</strong><span>{row.unread?say('Unread','غير مقروء'):say('Read','مقروء')}</span></button><p>{say('Finished quantity change','تغير الكمية المكتملة')}: <bdi>{decimalSubtract(outputTotal((row.quality?.groups||[]).filter(g=>!g.missing_operations.length)),outputTotal(row.recorded.filter(g=>!g.missing_operations.length)))} {t(row.unit)}</bdi> · {say('Unfinished','غير مكتمل')}: {outputTotal((row.quality?.groups||[]).filter(g=>g.missing_operations.length))} {t(row.unit)} · {say('Rejected','مرفوض')}: {row.quality?.rejected||'0'} {t(row.unit)}</p><p dir="auto">{row.quality?.reason}</p><time>{formatTime(row.history.find(event=>event.revision===row.notification_revision)?.at,lang,String(s.factory?.timezone||'UTC'))}</time></article>)}</div>
   <nav><button disabled={!page||busy||!!pending} onClick={()=>setPage(n=>n-1)}>{t('previous')}</button><button disabled={!data?.has_more||busy||!!pending} onClick={()=>setPage(n=>n+1)}>{t('next')}</button></nav>
  </>}
 </div></Dialog>}</>;
}
