import {useEffect,useRef,useState} from 'react';
import {Dialog,formatTime} from '@/components/ui';
import NavigationIcon from '@/components/NavigationIcon';
import type {OutputNotice} from './ManufacturedOutput';
import {sumQuantities} from '@/utils/quality-update-summary.mjs';
import type {FeatureProps} from './types';
import ProductionQualityCompletion from './ProductionQualityCompletion';
type Followup={state:string;status_revision:string;quality_revision:string;material_change:boolean;observation:string;requested_action:string;remaining_finished_demand:string;resolution_available:boolean;history:{state:string;at:string;note:string}[]};
type Notice=OutputNotice&{followup:Followup};
export default function ProductionQualityActions(props:FeatureProps){
 const {snapshot:s,lang,t,can}=props,factory=String(s.factory?.id||''),say=(a:string,b:string)=>lang==='ar'?b:a,key=`factory-lean:quality-actions:${s.user.id}:${factory}`;
 const[data,setData]=useState<{available:boolean;rows:Notice[];outstanding:number;has_more:boolean}|null>(null),[page,setPage]=useState(0),[filter,setFilter]=useState('outstanding'),[open,setOpen]=useState(false),[selected,setSelected]=useState<Notice|null>(null),[note,setNote]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false),[revision,setRevision]=useState(0),[pending,setPending]=useState(''),[ready,setReady]=useState(false),[audit,setAudit]=useState(false);const lock=useRef(false);
 const status=(v:string)=>({NEEDS_ACTION:say('Needs Action','بحاجة لإجراء'),IN_PROGRESS:say('In Progress','قيد المعالجة'),RESOLVED:say('Resolved','تمت المعالجة')}[v]||v);
 useEffect(()=>{setReady(false);try{const p=sessionStorage.getItem(key)||'';if(p&&JSON.parse(p).factory!==factory)throw Error();setPending(p);setReady(true);}catch{setError('pcStorageError');}},[factory,key]);
 useEffect(()=>{const a=new AbortController();fetch('/api/production-quality?'+new URLSearchParams({factory,page:String(page),state:filter}),{signal:a.signal,cache:'no-store'}).then(async r=>{if(!r.ok)throw Error('dataWarning');const d=await r.json();if(!Array.isArray(d.rows))throw Error('dataWarning');setData(d);setSelected(current=>d.rows.find((r:Notice)=>r.id===current?.id)||null);}).catch(e=>{if(e.name!=='AbortError')setError('dataWarning');});return()=>a.abort();},[factory,page,filter,revision,s.fetchedAt]);
 async function send(operation?:string){if(lock.current||!ready||!pending&&!selected)return;lock.current=true;setBusy(true);setError('');try{const body=pending||JSON.stringify({factory,target:selected!.id,operation,payload:{quality_revision:Number(selected!.followup.quality_revision),note},expected_revision:Number(selected!.followup.status_revision),request_id:crypto.randomUUID()});sessionStorage.setItem(key,body);if(sessionStorage.getItem(key)!==body)throw Error('pcStorageError');setPending(body);const r=await fetch('/api/production-quality',{method:'POST',headers:{'Content-Type':'application/json'},body,signal:AbortSignal.timeout(20000)}),result=await r.json();if(!r.ok){if(result.outcome==='REJECTED'){sessionStorage.removeItem(key);setPending('');setRevision(v=>v+1);}throw Error(r.status===403?'permissionError':result.error||'dataWarning');}sessionStorage.removeItem(key);setPending('');setNote('');setRevision(v=>v+1);}catch(e){setError(e instanceof Error?e.message:'dataWarning');}finally{lock.current=false;setBusy(false);}}
 const count=Number(data?.outstanding||0),title=say('Quality Updates','تحديثات الجودة');
 return <><button className={`quality-updates-button${count?' has-unread':''}`} onClick={()=>{setOpen(true);setSelected(null);}}><NavigationIcon name="notifications"/>{title}{count>0&&<span className="quality-unread-count" aria-label={say('Outstanding issues','المتابعات المتبقية')}>{count.toLocaleString(lang)}</span>}</button>
 {open&&<Dialog title={title} t={t} busy={busy} className="prv3-dialog quality-updates-dialog qu-drawer" onClose={()=>setOpen(false)} headerActions={<button onClick={props.onLanguageChange}>{lang==='ar'?'English':'العربية'}</button>}><div className="prv3-body" dir={lang==='ar'?'rtl':'ltr'}>
 {error&&<p role="alert">{error.startsWith('output_')?say('The record changed or physical work is incomplete. Refresh before continuing.','تغير السجل أو لم تكتمل المعالجة الفعلية. حدّثه قبل المتابعة.'):t(error)} <button onClick={()=>{setError('');setRevision(v=>v+1);}}>{t('refresh')}</button></p>}
 {pending&&<p role="alert">{say('Result unconfirmed. Retry the same action.','النتيجة غير مؤكدة. أعد الإجراء نفسه.')} <button disabled={busy} onClick={()=>void send()}>{t('retry')}</button></p>}
 {selected?<>
 <div className="qu-record-heading"><button className="qu-link" onClick={()=>{setSelected(null);setNote('');}} disabled={busy}>{t('back')}</button><span className="qu-status" data-state={selected.followup.state}>{status(selected.followup.state)}</span></div>
 <section className="qu-summary" aria-label={say('Production summary','ملخص الإنتاج')}>
 <span className="qu-eyebrow"><bdi>{selected.item_code||selected.request_code}</bdi></span><h3>{lang==='ar'?selected.product_name_ar||selected.product_name:selected.product_name}</h3>
 <div className="qu-metrics">{[
 {label:say('Original recording','التسجيل الأصلي'),value:sumQuantities(selected.original.map(g=>g.quantity)),tone:'neutral'},
 {label:say('Quality accepted','المكتمل المقبول'),value:sumQuantities((selected.quality?.groups||[]).filter(g=>!g.missing_operations.length).map(g=>g.quantity)),tone:'success'},
 {label:say('Recoverable unfinished','غير المكتمل القابل للاسترداد'),value:sumQuantities((selected.quality?.groups||[]).filter(g=>g.missing_operations.length).map(g=>g.quantity)),tone:'warning'},
 {label:say('Rejected production','الإنتاج المرفوض'),value:selected.quality?.rejected||'0',tone:'error'},
 ].map(metric=><div className="qu-metric" data-tone={metric.tone} key={metric.tone}><span>{metric.label}</span><strong><bdi>{metric.value}</bdi> <small>{t(selected.unit)}</small></strong></div>)}</div>
 {selected.quality?.actual_rejected_kg&&Number(selected.quality.actual_rejected_kg)>0&&<p className="qu-measured">{say('Measured rejected weight','الوزن المرفوض المقاس')}: <bdi>{selected.quality.actual_rejected_kg} {say('kg','كجم')}</bdi></p>}
 </section>
 <section className="qu-section qu-findings" aria-labelledby="qu-findings-heading"><div className="qu-section-heading"><NavigationIcon name="quality"/><h3 id="qu-findings-heading">{say('What Quality found','نتيجة فحص الجودة')}</h3></div>
 {selected.followup.material_change&&selected.quality?.reason&&<p dir="auto">{selected.quality.reason}</p>}
 {!selected.followup.material_change&&<p className="qu-observation-label">{say('Output accepted · process follow-up','الإنتاج مقبول · متابعة العملية')}</p>}
 {selected.followup.observation&&<p dir="auto">{selected.followup.observation}</p>}
 {selected.quality?.groups.filter(g=>g.missing_operations.length).map(g=><div className="qu-finding-row" key={g.id}><strong><bdi>{g.quantity} {t(selected.unit)}</bdi></strong><div><span>{g.missing_operations.map(id=>lang==='ar'?selected.operations[id]?.name_ar||selected.operations[id]?.name:selected.operations[id]?.name).join(' + ')}</span>{g.restriction&&<p dir="auto" className="qu-muted">{g.restriction}</p>}</div></div>)}
 {selected.followup.requested_action&&<p className="qu-requested" dir="auto"><strong>{say('Requested action','الإجراء المطلوب')}: </strong>{selected.followup.requested_action}</p>}
 </section>
 <ProductionQualityCompletion key={selected.id} props={props} output={selected.id} unit={selected.unit} code={selected.item_code||selected.request_code} qualityShortage={sumQuantities([selected.quality?.rejected||'0',...(selected.quality?.groups||[]).filter(g=>g.missing_operations.length).map(g=>g.quantity)])} onCommitted={()=>setRevision(v=>v+1)}/>
 {can('orders','edit')&&selected.followup.state!=='RESOLVED'&&<section className="qu-section qu-followup"><div className="qu-section-heading"><h3>{say('Production follow-up','متابعة الإنتاج')}</h3></div>
 {selected.followup.state==='NEEDS_ACTION'?<button disabled={busy||!!pending} onClick={()=>void send('START')}>{say('Start Handling','بدء المعالجة')}</button>:<><label>{say('Actual action taken','الإجراء الفعلي المتخذ')}<textarea maxLength={2000} value={note} disabled={busy||!!pending} onChange={e=>setNote(e.target.value)}/></label><button disabled={busy||!!pending||!selected.followup.resolution_available||note.trim().length<3} onClick={()=>void send('RESOLVE')}>{say('Mark Resolved','تأكيد المعالجة')}</button>{!selected.followup.resolution_available&&<p className="qu-muted">{say('Resolve the outstanding production shortage or Quality hold first.','عالج النقص الإنتاجي أو إيقاف الجودة أولاً.')}</p>}</>}
 </section>}
 <button className="qu-link qu-history-link" onClick={()=>setAudit(true)}>{say('View action record','عرض سجل المعالجة')}</button>

 </>:<><div className="qu-status-filters" role="group" aria-label={t('status')}>{['outstanding','NEEDS_ACTION','IN_PROGRESS','RESOLVED'].map(k=><button key={k} type="button" aria-pressed={filter===k} onClick={()=>{setFilter(k);setPage(0);setError('');}}>{k==='outstanding'?say('Open','المفتوحة'):status(k)}</button>)}</div>{!data&&<p role="status">{t('loading')}</p>}{data?.available===false&&<p role="status">{t('notAvailable')}</p>}{data?.available&&!data.rows.length&&<p>{t('noResults')}</p>}<div className="quality-notice-list">{data?.rows.map(row=><article key={row.id}><button disabled={busy||!!pending} onClick={()=>{setSelected(row);setNote('');}}><strong>{row.item_code||row.request_code} · {lang==='ar'?row.product_name_ar||row.product_name:row.product_name}</strong><span>{status(row.followup.state)}</span></button><p>{row.followup.observation||row.quality?.reason}</p><p>{row.followup.requested_action}</p></article>)}</div><nav><button disabled={!page||busy} onClick={()=>setPage(v=>v-1)}>{t('previous')}</button><button disabled={!data?.has_more||busy} onClick={()=>setPage(v=>v+1)}>{t('next')}</button></nav></>}
 </div></Dialog>}
 {audit&&selected&&<Dialog title={say('Production action record','سجل معالجة الإنتاج')} t={t} className="prv3-dialog qu-drawer" onClose={()=>setAudit(false)}><div className="prv3-body" dir={lang==='ar'?'rtl':'ltr'}>
 <strong><bdi>{selected.item_code||selected.request_code}</bdi> · {status(selected.followup.state)}</strong>
 {selected.followup.history.map((h,i)=><article className="qu-audit-row" key={i}><strong>{status(h.state)}</strong><span className="qu-muted">{formatTime(h.at,lang,String(s.factory?.timezone||'UTC'))}</span>{h.note&&<p dir="auto">{h.note}</p>}</article>)}
 {props.onOutputRelated&&can('orders','view')&&<button className="qu-link" onClick={()=>{setAudit(false);setOpen(false);props.onOutputRelated?.({factory,view:'production',entry:selected.entry_id});}}>{say('Open production record and Quality history','فتح سجل الإنتاج وتاريخ الجودة')}</button>}
 </div></Dialog>}
 </>;
}
