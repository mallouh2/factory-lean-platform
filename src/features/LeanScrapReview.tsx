import { useRef, useState } from 'react';
import { Field, localName, formatTime } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import HistoryQueryState from '@/components/HistoryQueryState';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
function Observation({entry,causes,...props}:FeatureProps & {entry:Row;causes:Row[]}){
 const {snapshot:s,t,lang,command}=props;
 const [cause,setCause]=useState(''),[note,setNote]=useState(''),[response,setResponse]=useState(''),[downtime,setDowntime]=useState('');
 const [at,setAt]=useState(new Date(Date.parse(String(entry.created_at))-new Date().getTimezoneOffset()*60000).toISOString().slice(0,23));
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[saved,setSaved]=useState(false);
 const request=useRef(crypto.randomUUID()),id=useRef(crypto.randomUUID());
 if(saved)return <p role="status">{t('leanObservationSaved')}</p>;
 return <form className="recording-form" onSubmit={async e=>{e.preventDefault();setBusy(true);setError('');try{
  await command('lean_command',{factory:s.factory?.id,request_id:request.current,operation:'scrap_observation',payload:{id:id.current,entry_id:entry.id,occurred_at:new Date(at).toISOString(),preliminary_cause_id:cause||null,observation:note,response,downtime_id:downtime||null}});setSaved(true);
 }catch(e){setError(e instanceof Error?e.message:'error');}finally{setBusy(false);}}}>
  <p>{t('leanAbnormalPrompt')} · <bdi>{formatTime(entry.created_at,lang,String(s.factory?.timezone||'UTC'))}</bdi> · {Number(entry.effective_scrap_kg).toLocaleString(lang)} kg</p>
  <fieldset disabled={busy}><div className="form-grid">
   <Field label={t('leanPreliminaryCause')}><select required value={cause} onChange={e=>setCause(e.target.value)}><option value="">{t('choose')}</option>{causes.map(c=><option key={String(c.id)} value={String(c.id)}>{localName(c,lang)}</option>)}</select></Field>
   <Field label={t('leanOccurredAt')}><input required type="datetime-local" step="0.001" value={at} onInput={e=>setAt(e.currentTarget.value)} onChange={e=>setAt(e.target.value)}/></Field>
   <Field label={t('leanWhatHappened')}><textarea required minLength={3} maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></Field>
   <Field label={t('leanResponse')}><textarea required minLength={3} maxLength={2000} value={response} onChange={e=>setResponse(e.target.value)}/></Field>
   <Field label={t('leanLinkedStop')}><select value={downtime} onChange={e=>setDowntime(e.target.value)}><option value="">{t('leanNoReliableLink')}</option>{(s.tables.downtime_events||[]).filter(d=>d.line_id===entry.line_id&&d.order_id===entry.order_id).map(d=><option key={String(d.id)} value={String(d.id)}>{formatTime(d.started_at,lang,String(s.factory?.timezone||'UTC'))} · {String(d.initial_note||'')}</option>)}</select></Field>
  </div><p className="muted">{t('leanLinkHelp')}</p><button className="primary">{t('save')}</button></fieldset>{error&&<p role="alert">{t(error)}</p>}
 </form>;
}
export default function LeanScrapReview(props:FeatureProps & {revision?:number}){
 const {snapshot:s,t,lang,can}=props;const [page,setPage]=useState(1);
 const factory=String(s.factory?.id||'');
 const data=useHistoryData<{rows:Row[];total:number}>(can('orders','view')?'/api/lean?'+new URLSearchParams({factory,mode:'recording_review',page:String(page)}):null,String(s.fetchedAt)+':'+props.revision);
 const library=useHistoryData<{causes:Row[]}>('/api/lean?'+new URLSearchParams({factory,mode:'recording_context'}),String(s.fetchedAt));
 if(!data.data?.rows.length&&!data.error)return null;
 return <section aria-label={t('leanScrapReview')}><h3>{t('leanScrapReview')}</h3><HistoryQueryState {...data} t={t}/>
  {can('orders','edit')&&data.data?.rows.map(entry=><Observation key={String(entry.id)} {...props} entry={entry} causes={library.data?.causes||[]}/>)}
  <nav className="history-pagination"><button disabled={page<=1} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{page}</span><button disabled={page*100>=(data.data?.total||0)} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></nav>
 </section>;
}
