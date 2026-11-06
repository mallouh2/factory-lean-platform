import { useEffect, useRef, useState } from 'react';
import { Dialog, Field, formatTime } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import { formatDuration } from '@/utils/production-flow.mjs';
import { formatLocalInput, localDateTimeToUtc } from '@/utils/manufacturing.mjs';
import { maintenanceQueueView, maintenanceQueueViews } from '@/utils/maintenance-planning-view.mjs';
import type { FeatureProps } from './types';
import type { MaintenancePlanningBoard, MaintenanceSchedule, MaintenancePreview } from './maintenance-planning-types';
import type { MaintenanceRequest } from './maintenance-types';
import {maintenancePreviewCurrent} from '@/utils/maintenance-planning.mjs';
import MaintenancePlanningReaders from './MaintenancePlanningReaders';
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

export function MaintenancePlanningDrawer({request:r,schedule,board,onClose,onChanged,...props}: FeatureProps & {
  request:MaintenanceRequest; schedule?:MaintenanceSchedule; board:MaintenancePlanningBoard;
  onClose:()=>void; onChanged:()=>void;
}) {
  const {snapshot:s,t,lang,can,command} = props;
  const zone = String(s.factory?.timezone || 'UTC');
  const [start,setStart] = useState(schedule ? formatLocalInput(schedule.planned_start,zone) : r.preferred_start ? formatLocalInput(r.preferred_start,zone) : '');
  const [end,setEnd] = useState(schedule ? formatLocalInput(schedule.planned_end,zone) : '');
  const [reason,setReason] = useState(''),[busy,setBusy] = useState(false),[error,setError] = useState('');
  const [kind,setKind] = useState(r.maintenance_kind || ''),[duration,setDuration] = useState(String(r.estimated_duration_minutes || ''));
  const [preferredStart,setPreferredStart] = useState(r.preferred_start ? formatLocalInput(r.preferred_start,zone) : '');
  const [preferredEnd,setPreferredEnd] = useState(r.preferred_end ? formatLocalInput(r.preferred_end,zone) : '');
  const [notes,setNotes] = useState(r.planning_notes || '');
  const [safetyPreview,setSafetyPreview]=useState<MaintenancePreview|null>(null);
  const retry = useRef<{key:string;id:string}|null>(null);
  const authority = can('orders','edit') && can('maintenance','view');
  const mutable = ['OPEN','ASSIGNED'].includes(r.status) && !schedule?.actual_hold;
  const locked = ['CONFIRMED','INVALIDATED'].includes(schedule?.state || '');
  const stamp = (value:string) => value ? localDateTimeToUtc(value,zone) : null;
  function proofCurrent(requireActivation=false) {
    try {return maintenancePreviewCurrent(safetyPreview,{factory:String(s.factory?.id),request:r.id,requestRevision:r.revision,
      scheduleRevision:schedule?.revision||0,start:stamp(start),end:stamp(end),timezone:zone,requireActivation});}catch{return false;}
  }
  function confirmationReady() {
    if (!authority || !can('factory','view') || !can('orders','view') || !mutable || board.active!==true ||
      r.maintenance_kind!=='PLANNED' || !proofCurrent(true)) return false;
    if (locked) return Boolean(reason.trim());
    return schedule?.state==='PROPOSED' && Date.parse(safetyPreview!.start)===Date.parse(schedule.planned_start) &&
      Date.parse(safetyPreview!.end || '')===Date.parse(schedule.planned_end);
  }
  async function run(operation:string,payload:Record<string,unknown>) {
    if (busy) return;
    if (['confirm','reschedule'].includes(operation)) {
      if (!confirmationReady()) {setError(board.active===true ? 'mpPreviewRequired' : 'mpActivationBlocked');return;}
      payload={...payload,context_hash:safetyPreview!.context_hash,request_revision:safetyPreview!.request_revision};
    }
    const args = {factory:s.factory?.id,maintenance_request:r.id,operation,payload,
      expected_revision:operation==='details' ? r.revision : schedule?.revision || 0};
    const key = JSON.stringify(args);
    if (retry.current?.key !== key) retry.current = {key,id:crypto.randomUUID()};
    setBusy(true);setError('');
    try { await command('maintenance_planning_command',{...args,request_id:retry.current.id}); retry.current=null;onChanged();onClose(); }
    catch(cause) { setError(cause instanceof Error ? cause.message : 'error'); }
    finally {setBusy(false);}
  }
  function propose(event:React.FormEvent) {
    event.preventDefault();
    try {void run(locked ? 'reschedule' : 'propose',{start:stamp(start),...(end ? {end:stamp(end)} : {}),reason});}
    catch {setError('maintenanceUnknownWindow');}
  }
  const machine = s.tables.work_centers?.find(m => String(m.id)===r.work_center_id);
  const lineImpact = schedule?.resources.some(resource => resource.line_id) || Boolean(machine?.line_id);
  return <Dialog title={`${r.code} · ${t('mpScheduling')}`} t={t} busy={busy} onClose={onClose}>
    <div className="mp-drawer" dir={lang==='ar' ? 'rtl' : 'ltr'}>
      {board.active!==true && <p className="mr-warning" role="status">{t('mpActivationBlocked')}</p>}
      {error && <p role="alert">{t(error)} <button disabled={busy} onClick={() => {onChanged();onClose();}}>{t('refresh')}</button></p>}
      <h3 dir="auto">{r.title}</h3><p dir="auto">{r.description || '—'}</p>
      <dl className="mr-facts">
        <div><dt>{t('machine')}</dt><dd><bdi>{r.machine_code}</bdi> · {lang==='ar' ? r.machine_name_ar || r.machine_name : r.machine_name}</dd></div>
        <div><dt>{t('line')}</dt><dd>{lang==='ar' ? r.line_name_ar || r.line_name || '—' : r.line_name || '—'}</dd></div>
        <div><dt>{t('mpDuration')}</dt><dd>{r.estimated_duration_minutes ? formatDuration(r.estimated_duration_minutes,lang) : t('mpUnknown')}</dd></div>
        <div><dt>{t('mpState')}</dt><dd>{schedule ? t(`mpState_${schedule.state}`) : t('mpView_needs')} · {t(`maintenanceState_${r.status}`)}</dd></div>
        <div><dt>{t('mpPreferred')}</dt><dd>{formatTime(r.preferred_start,lang,zone)} — {formatTime(r.preferred_end,lang,zone)}</dd></div>
        <div><dt>{t('mpImpact')}</dt><dd>{t(lineImpact ? 'mpLineImpact' : machine?.dependency_mode==='independent' ? 'mpMachineImpact' : 'mpUnknown')}</dd></div>
      </dl>
      {schedule && <p>{t('mpWindow')}: {formatTime(schedule.planned_start,lang,zone)} — {formatTime(schedule.planned_end,lang,zone)}
        {schedule.actual_hold && <strong> · {t('mpHold')}</strong>}{schedule.overrun && <strong> · {t('mpOverrun')}</strong>}
        {schedule.missed_window && <strong> · {t('mpMissed')}</strong>}</p>}
      <MaintenancePlanningReaders {...props} request={r} schedule={schedule} start={start} end={end} onSelect={(a,b)=>{setStart(a);setEnd(b);}} onPreview={setSafetyPreview}/>
      {proofCurrent()&&<p role="status">{t('mpPreviewReady')}</p>}
      {!authority && <p role="status">{t('permissionError')}</p>}
      {can('maintenance','edit') && mutable && !locked && <details className="mr-filters"><summary>{t('mpDetails')}</summary>
        <form className="mr-form" onSubmit={event => {event.preventDefault();try {void run('details',{
          maintenance_kind:kind || null,estimated_duration_minutes:duration ? Number(duration) : null,
          preferred_start:stamp(preferredStart),preferred_end:stamp(preferredEnd),planning_notes:notes,
        });} catch {setError('maintenanceUnknownWindow');}}}>
          <fieldset disabled={busy}><Field label={t('mpKind')}><select value={kind} onChange={event => setKind(event.target.value)}>
            <option value="">{t('mpUnknown')}</option><option value="CORRECTIVE">{t('mpKind_CORRECTIVE')}</option>
            {r.source!=='DOWNTIME' && <option value="PLANNED">{t('mpKind_PLANNED')}</option>}
          </select></Field><Field label={t('mpDuration')}><input type="number" min="1" step="1" required={kind==='PLANNED'} value={duration} onChange={event => setDuration(event.target.value)}/></Field>
          <div className="mp-window-fields"><Field label={`${t('mpPreferredStart')} · ${zone}`}><input type="datetime-local" value={preferredStart} onChange={event => setPreferredStart(event.target.value)}/></Field>
            <Field label={`${t('mpPreferredEnd')} · ${zone}`}><input type="datetime-local" value={preferredEnd} onChange={event => setPreferredEnd(event.target.value)}/></Field></div>
          <Field label={t('notes')}><textarea maxLength={4000} value={notes} onChange={event => setNotes(event.target.value)}/></Field></fieldset>
          <button disabled={busy||!['PLANNED','CORRECTIVE'].includes(kind)}>{t('save')}</button>
        </form></details>}
      {authority && mutable && <form className="mr-form" onSubmit={propose}>
        <fieldset disabled={busy}><div className="mp-window-fields">
          <Field label={`${t('mpStart')} · ${zone}`}><input type="datetime-local" required value={start} onChange={event => setStart(event.target.value)}/></Field>
          <Field label={`${t('mpEnd')} · ${zone}`}><input type="datetime-local" value={end} onChange={event => setEnd(event.target.value)}/></Field>
        </div><p className="muted">{t('mpEndHelp')}</p>
        <Field label={t('reason')}><textarea required={Boolean(schedule?.revision)} maxLength={4000} value={reason} onChange={event => setReason(event.target.value)}/></Field></fieldset>
        <div className="mr-actions"><button className="primary" disabled={busy || !start || !r.estimated_duration_minutes || r.maintenance_kind!=='PLANNED' || locked || Boolean(schedule?.revision && !reason.trim())}>{t('mpPropose')}</button>
          <button type="button" disabled={busy || !confirmationReady()} title={t(board.active===true ? 'mpPreviewRequired' : 'mpActivationBlocked')}
            onClick={() => {try {void run(locked ? 'reschedule' : 'confirm',locked ? {start:stamp(start),...(end ? {end:stamp(end)} : {}),reason} : {reason});}catch {setError('maintenanceUnknownWindow');}}}>{t(locked ? 'mpReschedule' : 'mpConfirm')}</button>
          {schedule && ['PROPOSED','CONFIRMED','INVALIDATED'].includes(schedule.state) && <button type="button" disabled={busy || !reason.trim()}
            onClick={() => void run('unschedule',{reason})}>{t('mpUnschedule')}</button>}</div>
      </form>}
    </div>
  </Dialog>;
}

export default function MaintenancePlanning(props:FeatureProps) {
  const {t,lang,snapshot:s,can} = props;
  const [windowStart,setWindowStart]=useState(()=>Date.now());
  const [line,setLine]=useState('');
  const read = useOperationalPlanningBoard(props,windowStart,windowStart+7*86400000,line,'maintenance');
  const [view,setView] = useState('needs'),[page,setPage] = useState(1),[selected,setSelected] = useState('');
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
        <button onClick={() => window.dispatchEvent(new CustomEvent('factory-maintenance-open',{detail:r.id}))}>{t('mpRepairDetails')}</button></div>
    </article>;})}</div>
    {board && <nav className="mr-pagination" aria-label={t('mpScheduling')}><button disabled={page===1} onClick={() => setPage(p => p-1)}>{t('previous')}</button>
      <span>{page} · {rows.length}</span><button disabled={page*25>=rows.length} onClick={() => setPage(p => p+1)}>{t('next')}</button></nav>}
    {request && board && <MaintenancePlanningDrawer key={`${request.id}:${request.revision}:${scheduleFor(request.id)?.revision || 0}`}
      {...props} request={request} schedule={scheduleFor(request.id)} board={board} onClose={() => setSelected('')} onChanged={read.reload}/>}
  </section>;
}
