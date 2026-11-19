import { useEffect, useRef, useState } from 'react';
import { Dialog, Field, formatTime, localName } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import { formatDuration } from '@/utils/production-flow.mjs';
import { formatLocalInput, localDateTimeToUtc } from '@/utils/manufacturing.mjs';
import { maintenanceQueueView, maintenanceQueueViews } from '@/utils/maintenance-planning-view.mjs';
import type { FeatureProps } from './types';
import type { MaintenancePlanningBoard, MaintenanceSchedule, MaintenancePreview } from './maintenance-planning-types';
import type { MaintenanceRequest } from './maintenance-types';
import {maintenanceKindCanBook,maintenancePreviewCurrent} from '@/utils/maintenance-planning.mjs';
import {useOperationalPlanningBoard} from './useOperationalPlanningBoard';

export function useMaintenancePlanning(props: FeatureProps) {
  const { snapshot:s, can } = props;
  const [minute,setMinute] = useState(0);
  useEffect(() => { const timer = setInterval(() => setMinute(v => v+1),60_000); return () => clearInterval(timer); },[]);
  // Re-render elapsed states without periodically replacing an operator's unsaved form.
  void minute;
  return useHistoryData<MaintenancePlanningBoard>(can('maintenance','view')
    ? `/api/maintenance-planning?factory=${s.factory?.id}&view=board` : null,s.fetchedAt);
}

export function MaintenancePlanningDrawer({
  request, schedule, board, initialStart, onClose, onChanged, ...props
}: FeatureProps & {
  request: MaintenanceRequest;
  schedule?: MaintenanceSchedule;
  board: MaintenancePlanningBoard;
  initialStart?: string;
  onClose: () => void;
  onChanged: () => void;
}) {
  const {snapshot, t, lang, can, command, onMaintenanceRepairOpen} = props;
  const factory = String(snapshot.factory?.id || '');
  const zone = String(snapshot.factory?.timezone || 'UTC');
  const revision = schedule?.revision ?? request.planning_schedule_revision ?? 0;
  const locked = schedule?.state === 'CONFIRMED' || schedule?.state === 'INVALIDATED';
  const mutable = ['OPEN','ASSIGNED'].includes(request.status) && !schedule?.actual_hold;
  const authority = can('factory','view') && can('maintenance','view') && can('orders','view') && can('orders','edit');
  const bookable = maintenanceKindCanBook(request);
  const configured = bookable && Number(request.estimated_duration_minutes) > 0;
  const localInput = (value?:string|null) => value ? formatLocalInput(value,zone) : '';
  const [start,setStart] = useState(initialStart || localInput(
    schedule && schedule.state !== 'UNSCHEDULED' ? schedule.planned_start : null));
  const [reason,setReason] = useState('');
  const [busy,setBusy] = useState(false);
  const [error,setError] = useState('');
  const [removing,setRemoving] = useState(false);
  const retry = useRef<{key:string;id:string;payload:Record<string,unknown>}|null>(null);

  const stamp = (value: string) => value ? localDateTimeToUtc(value,zone) : null;
  let plannedStart: string | null = null;
  try {plannedStart = stamp(start);} catch { /* Invalid local time. */ }
  const end = plannedStart && configured
    ? new Date(Date.parse(plannedStart) + Number(request.estimated_duration_minutes) * 60_000).toISOString()
    : null;
  const outside = Boolean(plannedStart && end && (
    request.preferred_start && Date.parse(plannedStart) < Date.parse(request.preferred_start) ||
    request.preferred_end && Date.parse(end) > Date.parse(request.preferred_end)));
  const reasonRequired = outside || locked;
  const previewUrl = authority && mutable && plannedStart && end && Date.parse(plannedStart)>Date.now()
    ? '/api/maintenance-planning?' + new URLSearchParams({
      factory,request:request.id,mode:'preview',start:plannedStart,end,
      request_revision:String(request.revision),schedule_revision:String(revision),
    }) : null;
  const preview = useHistoryData<MaintenancePreview>(previewUrl,snapshot.fetchedAt);
  const proof = preview.data;
  const proofCurrent = Boolean(!preview.loading && !preview.error && plannedStart && end &&
    maintenancePreviewCurrent(proof,{
      factory,request:request.id,requestRevision:request.revision,scheduleRevision:revision,
      start:plannedStart,end,timezone:zone,requireActivation:true,
    }));
  const machine = snapshot.tables.work_centers?.find(row=>String(row.id)===request.work_center_id);
  const line = snapshot.tables.production_lines?.find(row=>String(row.id)===String(machine?.line_id ?? request.line_id));
  const equipment = localName(machine,lang) || (lang==='ar' && request.machine_name_ar) || request.machine_name;

  async function run(operation:string,payload:Record<string,unknown>,intent=payload) {
    if (busy) return;
    const args = {
      factory,maintenance_request:request.id,operation,
      expected_revision:revision,
    };
    const key = JSON.stringify({...args,intent});
    if (retry.current?.key!==key) retry.current={key,id:crypto.randomUUID(),payload};
    setBusy(true);
    setError('');
    try {
      await command('maintenance_planning_command',{...args,payload:retry.current.payload,request_id:retry.current.id});
      retry.current=null;
      onChanged();
      onClose();
    } catch(cause) {
      const message = cause instanceof Error ? cause.message : 'error';
      setError(message);
      if(message==='mpPreviewStale'){
        retry.current=null;
        preview.reload();
      }
    } finally {
      setBusy(false);
    }
  }

  function saveSchedule(event:React.FormEvent) {
    event.preventDefault();
    if(!board.active || !authority || !mutable || !configured || !plannedStart || reasonRequired && !reason.trim()) return;
    const intent = {start:plannedStart,reason:reason.trim(),request_revision:request.revision};
    if(!proofCurrent || !proof) {
      setError('mpPreviewStale');
      preview.reload();
      return;
    }
    void run('save',{...intent,context_hash:proof.context_hash},intent);
  }

  function openRepair() {
    if(!onMaintenanceRepairOpen?.(request.id)) setError('mpRepairUnavailable');
  }

  return <Dialog title={t('mpScheduling')+' · '+request.code} t={t} busy={busy} onClose={onClose}
    className="planning-drawer planning-maintenance-drawer">
    <div dir={lang==='ar' ? 'rtl' : 'ltr'}>
      <section className="planning-order-summary">
        <strong dir="auto">{request.title}</strong>
        {request.description && <p dir="auto">{request.description}</p>}
        <dl className="planning-editor-facts">
          <div><dt>{t('machine')}</dt><dd>{equipment || '—'}</dd></div>
          <div><dt>{t('line')}</dt><dd>{localName(line,lang) || request.line_name || '—'}</dd></div>
          <div><dt>{t('mpKind')}</dt><dd>{t(request.maintenance_kind ? 'mpKind_'+request.maintenance_kind : 'mpUnknown')}</dd></div>
          <div><dt>{t('mpDuration')}</dt><dd>{request.estimated_duration_minutes ? formatDuration(request.estimated_duration_minutes,lang) : '—'}</dd></div>
          <div><dt>{t('mpRequestedWindow')}</dt><dd>{formatTime(request.preferred_start,lang,zone)} — {formatTime(request.preferred_end,lang,zone)}</dd></div>
          <div><dt>{t('mpUrgency')}</dt><dd>{t('maintenancePriority_'+request.priority)}</dd></div>
          {schedule && <div><dt>{t('mpState')}</dt><dd>{t('mpState_'+schedule.state)}{schedule.actual_hold && ' · '+t('mpHold')}</dd></div>}
        </dl>
      </section>
      {error && <p role="alert" className="mr-warning">{t(error)}
        {error==='mpPreviewStale' && <button type="button" onClick={onChanged}>{t('refresh')}</button>}
      </p>}
      {can('maintenance','view') && <button type="button" disabled={busy} onClick={openRepair}>{t('mpRepairDetails')}</button>}
      {!configured && <p role="status">{t(!bookable && request.maintenance_kind==='CORRECTIVE' ? 'mpCorrectiveOnly' : 'mpDetailsNeeded')}</p>}
      {!mutable && <p role="status">{t('mpNotEligible')}</p>}
      {!authority && <p role="status">{t('permissionError')}</p>}
      {board.active!==true && <p className="mr-warning" role="status">{t('mpActivationBlocked')}</p>}
      {!removing && configured && mutable && authority && <form onSubmit={saveSchedule}>
        <label className="planning-field"><span>{t('executionPlannedStart')+' · '+zone}</span>
          <input type="datetime-local" required disabled={busy} value={start} onInput={event=>{setStart(event.currentTarget.value);setError('');}}/>
        </label>
        <p className="planning-time-basis">{t('executionPlannedFinish')} · {formatTime(end,lang,zone)}</p>
        {outside && <p role="status" className="mr-warning">{t('mpOutsidePreferred')}</p>}
        {reasonRequired && <Field label={t('reason')}><textarea required maxLength={4000} disabled={busy} value={reason} onChange={event=>setReason(event.target.value)}/></Field>}
        {start && (!plannedStart || Date.parse(plannedStart)<=Date.now()) && <p role="status">{t('maintenanceUnknownWindow')}</p>}
        {preview.loading && <p role="status">{t('loading')}</p>}
        {preview.error && <p role="alert">{t(preview.error)} <button type="button" onClick={preview.reload}>{t('refresh')}</button></p>}
        {!preview.loading && !preview.error && proof && proof.capacity!=='CLEAR' && <div role="status" className="mr-warning">
          <p>{t('mpCapacity_'+proof.capacity)}</p>
          {[...new Set(proof.conflicts.map(issue=>issue.code))].map(code=><p key={code}>{t(code)}</p>)}
          {proof.conditions.open_transfer && <p>{t('maintenanceTransferUnresolved')}</p>}
        </div>}
        <div className="planning-actions"><button className="primary" disabled={busy || !board.active || !proofCurrent || reasonRequired && !reason.trim()}>{t('mpSaveSchedule')}</button></div>
      </form>}
      {authority && mutable && schedule && ['PROPOSED','CONFIRMED','INVALIDATED'].includes(schedule.state) &&
        (removing ? <form onSubmit={event=>{event.preventDefault();if(reason.trim())void run('unschedule',{reason:reason.trim()});}}>
          <Field label={t('reason')}><textarea required maxLength={4000} disabled={busy} value={reason} onChange={event=>setReason(event.target.value)}/></Field>
          <div className="planning-actions"><button type="button" onClick={()=>setRemoving(false)}>{t('cancel')}</button>
            <button disabled={busy || !reason.trim()}>{t('mpUnschedule')}</button></div>
        </form> : <button type="button" disabled={busy} onClick={()=>setRemoving(true)}>{t('mpUnschedule')}</button>)}
    </div>
  </Dialog>;
}

export default function MaintenancePlanning(props:FeatureProps) {
  const {t,lang,snapshot:s,can} = props;
  const [windowStart,setWindowStart]=useState(()=>Date.now());
  const [line,setLine]=useState('');
  const read = useOperationalPlanningBoard(props,windowStart,windowStart+7*86400000,line,'maintenance');
  const [view,setView] = useState('needs'),[page,setPage] = useState(1),[selected,setSelected] = useState('');
  const [repairError,setRepairError] = useState(false);
  const board=read.data, zone=String(s.factory?.timezone || 'UTC');
  const scheduleFor = (id:string) => board?.schedules.find(schedule => schedule.maintenance_request_id===id);
  const rows = board?.requests.filter(r => maintenanceQueueView(r,scheduleFor(r.id))===view) || [];
  const request=board?.requests.find(r => r.id===selected);
  if (!can('maintenance','view')) return <p role="alert">{t('permissionError')}</p>;
  return <section className="mp-queue" dir={lang==='ar' ? 'rtl' : 'ltr'} aria-label={t('mpScheduling')}>
    <header className="mr-tools"><p>{t('mpQueueHelp')}</p><button onClick={read.reload}>{t('refresh')}</button></header>
    <label className="planning-window-start">{t('planningVisibleStart')} · {zone}
      <input type="datetime-local" dir="ltr" value={formatLocalInput(new Date(windowStart).toISOString(),zone)}
        onChange={event=>{try{if(event.target.value)setWindowStart(Date.parse(localDateTimeToUtc(event.target.value,zone)));}catch{/* Keep valid horizon. */}}}/>
    </label>
    <label>{t('line')}<select value={line} onChange={event=>setLine(event.target.value)}><option value="">{t('all')}</option>
      {(s.tables.production_lines||[]).filter(row=>!row.archived).map(row=><option key={String(row.id)} value={String(row.id)}>{lang==='ar'?String(row.name_ar||row.name):String(row.name)}</option>)}</select></label>
    <p role="status">{t(read.complete?'mpBoardComplete':read.error?'mpBoardError':'mpBoardIncomplete')} · {board?.loaded||0} / {board?.total??'—'} · {t('mpBoardHorizon')}</p>
    {board?.active!==true && <p className="mr-warning">{t('mpActivationBlocked')}</p>}
    <nav className="mp-views" aria-label={t('mpScheduling')}>{maintenanceQueueViews.map((key:string) => <button key={key} aria-pressed={view===key}
      onClick={() => {setView(key);setPage(1);}}>{t(`mpView_${key}`)} <bdi>{board ? board.requests.filter(r => maintenanceQueueView(r,scheduleFor(r.id))===key).length : '—'}</bdi></button>)}</nav>
    {read.loading && <p role="status">{t('loading')}</p>}{read.error && <p role="alert">{t(read.error)} · {t('mpReaderUnavailable')}</p>}
    {repairError && <p role="alert">{t('mpRepairUnavailable')}</p>}
    {board && !rows.length && <div className="empty"><p>{t('noResults')}</p></div>}
    <div className="mr-list">{rows.slice((page-1)*25,page*25).map(r => {const schedule=scheduleFor(r.id);return <article className="mr-row" data-status={r.status} key={r.id}>
      <header><button className="mr-open" disabled={read.loading} onClick={() => setSelected(r.id)}><bdi>{r.code}</bdi><strong dir="auto">{r.title}</strong></button>
        <span className="mr-status">{schedule ? t(`mpState_${schedule.state}`) : t('mpView_needs')}</span></header>
      <dl><div><dt>{t('machine')}</dt><dd><bdi>{r.machine_code}</bdi> · {lang==='ar' ? r.machine_name_ar || r.machine_name : r.machine_name}</dd></div>
        <div><dt>{t('mpKind')}</dt><dd>{t(r.maintenance_kind ? `mpKind_${r.maintenance_kind}` : 'mpUnknown')}</dd></div>
        <div><dt>{t('priority')}</dt><dd className="mr-priority" data-priority={r.priority}>{t(`maintenancePriority_${r.priority}`)}</dd></div>
        <div><dt>{t('mpDuration')}</dt><dd>{r.estimated_duration_minutes ? formatDuration(r.estimated_duration_minutes,lang) : t('mpUnknown')}</dd></div>
        <div><dt>{t('mpPreferred')}</dt><dd>{formatTime(r.preferred_start,lang,zone)} — {formatTime(r.preferred_end,lang,zone)}</dd></div>
        <div><dt>{t('mpImpact')}</dt><dd>{schedule ? t(schedule.resources.some(res => res.line_id) ? 'mpLineImpact' : 'mpMachineImpact') : t('mpImpactPending')}</dd></div></dl>
      {schedule && <p className="mp-current-window">{t('mpWindow')}: {formatTime(schedule.planned_start,lang,zone)} — {formatTime(schedule.planned_end,lang,zone)}
        {schedule.overrun && <strong> · {t('mpOverrun')}</strong>}{schedule.actual_hold && <strong> · {t('mpHold')}</strong>}{schedule.missed_window && <strong> · {t('mpMissed')}</strong>}</p>}
      <div className="mr-actions"><button disabled={read.loading} onClick={() => setSelected(r.id)}>{t(can('orders','edit') ? 'mpReview' : 'details')}</button>
        <button onClick={() => setRepairError(!props.onMaintenanceRepairOpen?.(r.id))}>{t('mpRepairDetails')}</button></div>
    </article>;})}</div>
    {board && <nav className="mr-pagination" aria-label={t('mpScheduling')}><button disabled={page===1} onClick={() => setPage(p => p-1)}>{t('previous')}</button>
      <span>{page} · {rows.length}</span><button disabled={page*25>=rows.length} onClick={() => setPage(p => p+1)}>{t('next')}</button></nav>}
    {request && board && <MaintenancePlanningDrawer key={`${request.id}:${request.revision}:${scheduleFor(request.id)?.revision || 0}`}
      {...props} request={request} schedule={scheduleFor(request.id)} board={board} onClose={() => setSelected('')} onChanged={read.reload}/>}
  </section>;
}
