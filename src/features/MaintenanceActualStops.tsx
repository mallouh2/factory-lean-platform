import { useRef, useState } from 'react';
import { Field, formatTime } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import type { FeatureProps } from './types';

export type StopSchedule = { id: string; revision: number; request_revision: number; code: string; title: string; planned_start: string; planned_end: string };
export function MaintenanceStopChoice({ machine, choice, onChange, ...props }: FeatureProps & {
  machine: string; choice: StopSchedule | null; onChange: (value: StopSchedule | null) => void;
}) {
  const { snapshot:s,t,lang } = props;
  const read = useHistoryData<{factory:string;machine:string;eligible:StopSchedule[]}>(
    `/api/maintenance?factory=${s.factory?.id}&actual_stop_machine=${machine}`,s.fetchedAt);
  const scoped = read.data?.factory === s.factory?.id && read.data?.machine === machine;
  const rows = scoped ? read.data!.eligible : [];
  return <Field label={t('maintenanceStopChoice')}>
    <select value={choice?.id || ''} onChange={event => onChange(rows.find(row => row.id === event.target.value) || null)}>
      <option value="">{t('maintenanceOrdinaryStop')}</option>
      {rows.map(row => <option key={row.id} value={row.id}>{row.code} · {row.title} · {formatTime(row.planned_start,lang,String(s.factory?.timezone))}</option>)}
      {choice && !rows.some(row => row.id === choice.id) && <option value={choice.id}>{choice.code} · {t('maintenanceStopStale')}</option>}
    </select>
    {read.loading && <span role="status">{t('loading')}</span>}
    {read.error && <span role="alert">{t(read.error)} <button type="button" onClick={read.reload}>{t('refresh')}</button></span>}
    {!read.loading && !read.error && rows.length===0 && <span>{t('maintenanceNoEligibleStop')}</span>}
    {choice && <span>{t('maintenanceStopRevalidate')}</span>}
  </Field>;
}

type ActualStop = { id:string;schedule_id:string;event_id:string;revision:number;relationship:string;approval_revision:number;started_at:string;ended_at:string|null };
type Association = ActualStop & {operation:string;reason:string;recorded_at:string;actor_name:string|null;reviewed_evidence:unknown[]};
export function MaintenanceActualStops({ id, ...props }: FeatureProps & {id:string}) {
  const {snapshot:s,t,lang,can,command} = props;
  const [page,setPage] = useState(1),[selected,setSelected] = useState<ActualStop|null>(null);
  const [reason,setReason] = useState(''),[busy,setBusy] = useState(false),[error,setError] = useState('');
  const retry = useRef<{key:string;id:string}|null>(null);
  const read = useHistoryData<{factory:string;request:string;current:ActualStop[];history:Association[];history_total:number}>(
    can('downtime') ? `/api/maintenance?factory=${s.factory?.id}&actual_stop_request=${id}&history_page=${page}` : null,s.fetchedAt);
  if (!can('downtime')) return <p>{t('maintenanceDowntimePermission')}</p>;
  const data=read.data?.factory===s.factory?.id && read.data?.request===id ? read.data : null;
  const zone=String(s.factory?.timezone);
  async function unlink(event:React.FormEvent) {
    event.preventDefault();if(!selected || !reason.trim()) return;
    const args={factory:s.factory?.id,event:selected.event_id,schedule:selected.schedule_id,
      approval_revision:selected.approval_revision,operation:'UNLINK',reason:reason.trim(),expected_revision:selected.revision};
    const key=JSON.stringify(args);if(retry.current?.key!==key) retry.current={key,id:crypto.randomUUID()};
    setBusy(true);setError('');
    try {await command('correct_maintenance_stop',{...args,request_id:retry.current.id});retry.current=null;setSelected(null);setReason('');read.reload();}
    catch(cause){setError(cause instanceof Error?cause.message:'error');read.reload();}finally{setBusy(false);}
  }
  return <section className="mr-linked-stop"><h4>{t('maintenanceActualStops')}</h4>
    {read.loading && <p role="status">{t('loading')}</p>}
    {read.data && !data && <p role="alert">{t('dataWarning')}</p>}
    {(read.error || error) && <p role="alert">{t(read.error || error)} <button type="button" onClick={read.reload}>{t('refresh')}</button></p>}
    {data?.current.length===0 && <p>{t('maintenanceNoActualStops')}</p>}
    {data?.current.map(row=><div key={row.id}><p>{formatTime(row.started_at,lang,zone)} — {row.ended_at?formatTime(row.ended_at,lang,zone):t('maintenanceStopOpen')}</p>
      <p>{t(`maintenanceRelationship_${row.relationship}`)} · {t('maintenanceApprovalRevision')} <bdi>{row.approval_revision}</bdi></p>
      <button type="button" onClick={()=>window.dispatchEvent(new CustomEvent('factory-downtime-open',{detail:row.event_id}))}>{t('maintenanceOpenDowntime')}</button>
      {can('maintenance','edit') && can('downtime','edit') && row.ended_at && <button type="button" disabled={busy} onClick={()=>{setSelected(row);setReason('');}}>{t('maintenanceUnlinkStop')}</button>}
    </div>)}
    {selected && can('maintenance','edit') && can('downtime','edit') && <form onSubmit={unlink}><Field label={t('maintenanceAssociationReason')}><textarea required maxLength={4000} value={reason} onChange={event=>setReason(event.target.value)} /></Field>
      <button disabled={busy || !reason.trim()}>{t('maintenanceUnlinkStop')}</button><button type="button" disabled={busy} onClick={()=>setSelected(null)}>{t('cancel')}</button></form>}
    <details><summary>{t('maintenanceAssociationHistory')}</summary><ol>{data?.history.map(row=><li key={row.id}>
      <strong>{t(`maintenanceAssociation_${row.operation}`)}</strong> · {row.actor_name || '—'} · {formatTime(row.recorded_at,lang,zone)}
      <p>{formatTime(row.started_at,lang,zone)} · {t(`maintenanceRelationship_${row.relationship}`)} · {t('maintenanceApprovalRevision')} <bdi>{row.approval_revision}</bdi></p>
      <p dir="auto">{row.reason}</p>{row.reviewed_evidence.length>0 && <p>{t('maintenanceReviewedEvidence')}</p>}
    </li>)}</ol><div className="mr-actions"><button disabled={read.loading || page===1} onClick={()=>setPage(value=>value-1)}>{t('previous')}</button>
      <span>{page}</span><button disabled={read.loading || page*25>=(data?.history_total || 0)} onClick={()=>setPage(value=>value+1)}>{t('next')}</button></div></details>
  </section>;
}
