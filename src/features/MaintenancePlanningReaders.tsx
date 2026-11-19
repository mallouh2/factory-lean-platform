import {useEffect,useState} from 'react';
import {maintenancePreviewCurrent} from '@/utils/maintenance-planning.mjs';
import {Field,formatTime,localName} from '@/components/ui';
import {useHistoryData} from '@/hooks/useHistoryData';
import {formatLocalInput,localDateTimeToUtc} from '@/utils/manufacturing.mjs';
import type {FeatureProps} from './types';
import type {MaintenanceRequest} from './maintenance-types';
import type {MaintenanceSchedule,MaintenancePreview,MaintenanceGaps,MaintenanceHistory,MaintenanceRecordedScope} from './maintenance-planning-types';

export default function MaintenancePlanningReaders({request,schedule,start,end,onSelect,onPreview,...props}:FeatureProps & {
 request:MaintenanceRequest;schedule?:MaintenanceSchedule;start:string;end:string;onSelect:(start:string,end:string)=>void;onPreview:(preview:MaintenancePreview|null)=>void;
}) {
 const {snapshot:s,t,lang,can}=props,zone=String(s.factory?.timezone||'UTC');
 const [now,setNow]=useState(Date.now());
 useEffect(()=>{const timer=setInterval(()=>setNow(Date.now()),10000);return()=>clearInterval(timer);},[]);
 const [previewQuery,setPreviewQuery]=useState(''),[previewKey,setPreviewKey]=useState('');
 const [from,setFrom]=useState(formatLocalInput(new Date(Date.now()+60000).toISOString(),zone));
 const [until,setUntil]=useState(formatLocalInput(new Date(Date.now()+7*86400000).toISOString(),zone));
 const [gapQuery,setGapQuery]=useState(''),[gapKey,setGapKey]=useState(''),[before,setBefore]=useState<number|null>(null),[high,setHigh]=useState<number|null>(null),[inputError,setInputError]=useState('');
 const revision=schedule?.revision ?? request.planning_schedule_revision ?? 0;
 const base={factory:String(s.factory?.id),request:request.id,request_revision:String(request.revision),schedule_revision:String(revision)};
 const identity=JSON.stringify({factory:base.factory,request:request.id,zone,snapshot:s.fetchedAt,start,end,revision:request.revision,schedule:revision});
 const preview=useHistoryData<MaintenancePreview>(previewQuery&&previewKey===identity?previewQuery:null,s.fetchedAt);
 const gapIdentity=JSON.stringify({from,until,request:request.id,revision:request.revision,schedule:revision});
 const gaps=useHistoryData<MaintenanceGaps>(gapQuery&&gapKey===gapIdentity?gapQuery:null,s.fetchedAt);
 const historyParams=new URLSearchParams({factory:base.factory,request:request.id,mode:'history',limit:'10',...(before?{before_revision:String(before)}:{}),...(high!==null?{through_revision:String(high)}:{})});
 const history=useHistoryData<MaintenanceHistory>(can('maintenance','view')?`/api/maintenance-planning?${historyParams}`:null,s.fetchedAt);
 const allowed=can('maintenance','view')&&can('orders','view');
 function evaluate() {
  try {setInputError('');const params=new URLSearchParams({...base,mode:'preview',start:localDateTimeToUtc(start,zone),...(end?{end:localDateTimeToUtc(end,zone)}:{}),
    ...(previewKey===identity&&preview.data?.context_hash?{context_hash:preview.data.context_hash}:{})});
   setPreviewKey(identity);setPreviewQuery(`/api/maintenance-planning?${params}`);preview.reload();}
  catch {setInputError('maintenanceUnknownWindow');}
 }
 function find(more=false) {
  try {setInputError('');const params=new URLSearchParams({...base,mode:'gaps',start:localDateTimeToUtc(from,zone),end:localDateTimeToUtc(until,zone),limit:'5',
    ...(more&&gaps.data?.next_after_start?{after_start:gaps.data.next_after_start,context_hash:gaps.data.context_hash}:{})});
   setGapKey(gapIdentity);setGapQuery(`/api/maintenance-planning?${params}`);gaps.reload();}
  catch {setInputError('maintenanceUnknownWindow');}
 }
 const expired=preview.data&&now-Date.parse(preview.data.evaluated_at)>60000;
 const gapExpired=gaps.data&&now-Date.parse(gaps.data.evaluated_at)>60000;
 let windowStart='',windowEnd:string|null=null,windowValid=true;
 try {windowStart=start?localDateTimeToUtc(start,zone):'';windowEnd=end?localDateTimeToUtc(end,zone):null;}catch{windowValid=false;}
 const matches=windowValid&&preview.data?.factory_id===base.factory&&preview.data?.request_id===request.id&&
  preview.data?.request_revision===request.revision&&preview.data?.schedule_revision===revision&&
  Date.parse(preview.data?.start||'')===Date.parse(windowStart)&&(!windowEnd||Date.parse(preview.data?.end||'')===Date.parse(windowEnd));
 const display=previewKey===identity&&!preview.loading&&!preview.error&&!expired&&preview.data?.timezone===zone&&matches?preview.data:null;
 const current=display&&maintenancePreviewCurrent(display,{factory:base.factory,request:request.id,requestRevision:request.revision,
  scheduleRevision:revision,start:windowStart,end:windowEnd,timezone:zone,now})?display:null;
 useEffect(()=>{onPreview(current);},[current,onPreview]);
 useEffect(()=>{if(!preview.data)return;const timer=setTimeout(()=>setNow(Date.now()),Math.max(0,Date.parse(preview.data.evaluated_at)+60001-Date.now()));return()=>clearTimeout(timer);},[preview.data]);
 const scope=(resources:MaintenanceRecordedScope[]|null)=>resources===null?<p>{t('mpEvidenceMissing')}</p>:resources.map((resource,index)=><div key={index}>
  <p><strong>{t(resource.kind==='LINE'?'line':'machine')}</strong> · <bdi>{resource.line_id||resource.machine_id}</bdi></p>
  {resource.machine_evidence&&<p>{t('mpRecordedDependency')}: {t(resource.machine_evidence.dependency)} · {t('mpRecordedBuffer')}: {resource.machine_evidence.buffer} {t('minutes')}</p>}
 </div>);
 return <section className="mp-readers">
  <h4>{t('mpPreview')}</h4>
  {!allowed?<p>{t('mpPreviewPermission')}</p>:<>
   <button type="button" disabled={!start||preview.loading} onClick={evaluate}>{t('mpEvaluate')}</button>
   {previewKey&&(previewKey!==identity||expired||(preview.data&&(preview.data.timezone!==zone||!matches)))&&<p role="status" className="mr-warning">{t('mpPreviewStale')}</p>}
   {preview.loading&&<p role="status">{t('loading')}</p>}
   {display&&<div role="status"><strong>{t(`mpCapacity_${display.capacity}`)}</strong><p>{t('mpNonBinding')}</p>
    <p>{t('mpEvaluatedAt')}: {formatTime(display.evaluated_at,lang,zone)} · {t('mpImpact')}: {t(display.scope.kind==='WHOLE_LINE'?'mpLineImpact':'mpMachineImpact')}</p>
    {display.scope.line_id&&<p>{t('line')}: {localName(s.tables.production_lines?.find(line=>String(line.id)===display.scope.line_id),lang)} · <bdi>{display.scope.line_id}</bdi></p>}
    <p>{t('mpReadiness')}: {t(`mpReadiness_${display.physical_readiness}`)}</p>
    {display.conditions.configuration_or_routing_unknown&&<p className="mr-warning">{t('maintenanceUnknownWindow')}</p>}
    {!display.eligible&&<p className="mr-warning">{t('mpNotEligible')}</p>}
    {display.conditions.open_transfer&&<p className="mr-warning">{t('maintenanceTransferUnresolved')}</p>}
    {display.conflicts.map(issue=><p className="mr-warning" key={`${issue.kind}:${issue.reference_id}`}>{t(issue.code)} · <bdi>{issue.reference_id}</bdi></p>)}
    {!display.conflicts_complete&&<p>{t('mpMoreConflicts')}</p>}
   </div>}
   <details className="mr-filters"><summary>{t('mpFindGaps')}</summary><div className="mr-form">
    <div className="mp-window-fields"><Field label={`${t('mpSearchStart')} · ${zone}`}><input type="datetime-local" value={from} onChange={event=>{setFrom(event.target.value);setGapQuery('');}}/></Field>
     <Field label={`${t('mpSearchEnd')} · ${zone}`}><input type="datetime-local" value={until} onChange={event=>{setUntil(event.target.value);setGapQuery('');}}/></Field></div>
    <button type="button" disabled={gaps.loading||!from||!until} onClick={()=>find()}>{t('mpFindGaps')}</button>
    {gaps.loading&&<p role="status">{t('loading')}</p>}
    {gapExpired&&<p role="status" className="mr-warning">{t('mpPreviewStale')}</p>}
    {gaps.data&&!gaps.loading&&!gaps.error&&now-Date.parse(gaps.data.evaluated_at)<=60000&&<><p>{t(`mpCapacity_${gaps.data.capacity}`)} · {t('mpNonBinding')}</p>
     {!gaps.data.occupancy_complete&&<p className="mr-warning">{t('mpIncomplete')}</p>}
     {gaps.data.conditions.open_transfer&&<p className="mr-warning">{t('maintenanceTransferUnresolved')}</p>}
     {gaps.data.blockers.map(issue=><p key={`${issue.kind}:${issue.reference_id}`} className="mr-warning">{t(issue.code)} · <bdi>{issue.reference_id}</bdi></p>)}
     {!gaps.data.blockers_complete&&<p>{t('mpMoreConflicts')}</p>}
     {gaps.data.suggestions.map(gap=><button type="button" key={gap.start} onClick={()=>onSelect(formatLocalInput(gap.start,zone),formatLocalInput(gap.end,zone))}>
      {t('mpSelectGap')}: {formatTime(gap.start,lang,zone)} — {formatTime(gap.end,lang,zone)}</button>)}
     {gaps.data.has_more&&<button type="button" disabled={gaps.loading} onClick={()=>find(true)}>{t('next')}</button>}
    </>}
   </div></details>
  </>}
  {(inputError||preview.error||gaps.error)&&<p role="alert" className="mr-warning">{t(inputError||preview.error||gaps.error)} · {t('mpReaderUnavailable')}</p>}
  <details className="mr-history"><summary>{t('mpScheduleHistory')}</summary>
   {history.loading&&<p role="status">{t('loading')}</p>}{history.error&&<p role="alert">{t(history.error)}</p>}
   {history.data&&!history.data.rows.length&&<p>{t('noResults')}</p>}
   <ol>{history.data?.rows.map(row=><li key={row.revision}><strong>{row.revision} · {t(`mpEvent_${row.event}`)}</strong>
    <p>{row.actor_name||t('requestCreatorNotRecorded')} · {formatTime(row.changed_at,lang,zone)}</p>
    <p>{row.before_window.state?t(`mpState_${row.before_window.state}`):'—'} → {t(`mpState_${row.after_window.state}`)}</p>
    <p>{formatTime(row.before_window.start,lang,zone)} — {formatTime(row.before_window.end,lang,zone)}</p>
    <p>{formatTime(row.after_window.start,lang,zone)} — {formatTime(row.after_window.end,lang,zone)}</p>
    <p dir="auto">{row.reason}</p>{row.before_evidence==='NOT_RECORDED'&&<p>{t('mpEvidenceMissing')}</p>}
    {row.before_evidence==='NO_PREVIOUS_SCHEDULE'&&<p>{t('mpNoPreviousSchedule')}</p>}
    <details><summary>{t('mpRecordedScope')}</summary><h5>{t('mpBeforeScope')}</h5>{scope(row.before_resources)}<h5>{t('mpAfterScope')}</h5>{scope(row.after_resources)}</details>
   </li>)}</ol>
   {before!==null&&<button type="button" onClick={()=>{setBefore(null);setHigh(null);}}>{t('refresh')}</button>}
   {history.data?.has_more&&<button type="button" disabled={history.loading} onClick={()=>{setHigh(history.data!.through_revision);setBefore(history.data!.next_before_revision);}}>{t('next')}</button>}
  </details>
 </section>;
}
