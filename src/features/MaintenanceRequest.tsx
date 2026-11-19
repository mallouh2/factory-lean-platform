import { useEffect, useRef, useState } from 'react';
import { Dialog, Field, formatTime, localName } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import { maintenanceActions } from '@/utils/maintenance.mjs';
import { formatDuration } from '@/utils/production-flow.mjs';
import type { Row } from '@/types';
import type { FeatureProps } from './types';
import type { MaintenancePage, MaintenanceRequest } from './maintenance-types';
import { MaintenanceActualStops } from './MaintenanceActualStops';
import { formatLocalInput, localDateTimeToUtc } from '@/utils/manufacturing.mjs';
import { maintenanceKindCanBook } from '@/utils/maintenance-planning.mjs';

export function MaintenanceBadge({ status, t }: { status: string; t: FeatureProps['t'] }) {
  return <span className="mr-status" data-status={status}>{t(`maintenanceState_${status}`)}</span>;
}
export function MaintenanceCreate({ machine, downtime, onClose, onCreated, ...props }: FeatureProps & {
  machine?: Row; downtime?: Row; onClose: () => void; onCreated: (id: string) => void;
}) {
  const { snapshot: s, t, lang, can, command } = props;
  const [machineId, setMachineId] = useState(String(machine?.id || ''));
  const reason = s.tables.downtime_reasons?.find(row => row.id === downtime?.reason_id);
  const [title, setTitle] = useState(downtime ? (reason ? localName(reason, lang) : t('maintenanceProblem')) : '');
  const [description, setDescription] = useState(String(downtime?.initial_note || downtime?.notes || ''));
  const [priority, setPriority] = useState('NORMAL'), [assignee, setAssignee] = useState('');
  const [separate, setSeparate] = useState(false), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const retry = useRef<{ key: string; id: string } | null>(null);
  const factory = String(s.factory?.id || '');
  const options = useHistoryData<MaintenancePage>(`/api/maintenance?factory=${factory}`, s.fetchedAt);
  const existing = useHistoryData<{ rows: Row[]; total: number }>(machineId
    ? `/api/maintenance?factory=${factory}&context_machine=${machineId}` : null, s.fetchedAt);
  const duplicate = existing.data?.rows.find(row => row.downtime_id === downtime?.id);
  const blocked = Boolean(downtime && duplicate);
  async function submit(event: React.FormEvent) {
    event.preventDefault(); setBusy(true); setError('');
    const payload = { work_center_id: machineId, downtime_id: downtime?.id || null, title: title.trim(), description,
      priority, assigned_to: assignee || null, separate_problem: separate };
    const key = JSON.stringify(payload);
    if (retry.current?.key !== key) retry.current = { key, id: crypto.randomUUID() };
    try {
      const id = await command('create_maintenance_request', { factory, payload, request_id: retry.current.id });
      onCreated(String(id));
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'error'); }
    finally { setBusy(false); }
  }
  return <Dialog title={t('maintenanceCreate')} t={t} onClose={() => { if (!busy) onClose(); }}>
    <form className="mr-form" onSubmit={submit}>
      {(error || options.error || existing.error) && <p role="alert">{t(error || options.error || existing.error)}</p>}
      <fieldset disabled={busy}>
        <Field label={t('machine')}><select required value={machineId} disabled={Boolean(machine || downtime)}
          onChange={event => { setMachineId(event.target.value); setSeparate(false); }}>
          <option value="">{t('select')}</option>{(options.data?.options.machines || (s.tables.work_centers || []).filter(row => !row.archived))
            .map(row => <option key={String(row.id)} value={String(row.id)}>{String(row.code)} · {localName(row, lang)}</option>)}
        </select></Field>
        {downtime && <p className="mr-source">{t('maintenanceSource_DOWNTIME')} · {formatTime(downtime.started_at, lang, String(s.factory?.timezone))}</p>}
        {Boolean(existing.data?.total) && <aside className="mr-warning">
          <strong>{t('maintenanceExistingProblem')}</strong>
          {existing.data?.rows.map(row => <p key={String(row.id)}><bdi>{String(row.code)}</bdi> · {t(`maintenanceState_${row.status}`)}</p>)}
          {!downtime && <label className="check"><input type="checkbox" checked={separate}
            onChange={event => setSeparate(event.target.checked)} />{t('maintenanceSeparateProblem')}</label>}
        </aside>}
        <Field label={t('maintenanceProblem')}><input required maxLength={200} value={title} onChange={event => setTitle(event.target.value)} /></Field>
        <Field label={t('description')}><textarea maxLength={4000} value={description} onChange={event => setDescription(event.target.value)} /></Field>
        <Field label={t('mpUrgency')}><select value={priority} onChange={event => setPriority(event.target.value)}>
          {['NORMAL','URGENT'].map(value => <option key={value} value={value}>{t(`maintenancePriority_${value}`)}</option>)}
        </select></Field>
        {can('maintenance','edit') && <Field label={t('maintenanceAssignedTo')}><select value={assignee} onChange={event => setAssignee(event.target.value)}>
          <option value="">{t('maintenanceUnassigned')}</option>{options.data?.options.people.map(row =>
            <option key={String(row.id)} value={String(row.id)}>{localName(row, lang)}</option>)}
        </select></Field>}
      </fieldset>
      <footer className="mr-actions"><button className="primary" disabled={busy || !machineId || !title.trim() || !can('maintenance','create')
        || !existing.data || blocked || (Boolean(existing.data.total) && !downtime && !separate)}>{t('maintenanceCreate')}</button>
        <button type="button" disabled={busy} onClick={onClose}>{t('cancel')}</button>
        {existing.error && <button type="button" onClick={existing.reload}>{t('refresh')}</button>}</footer>
    </form>
  </Dialog>;
}

export function MaintenanceDetailBody({ request: r, ...props }: FeatureProps & { request: MaintenanceRequest }) {
  const { snapshot: s, t, lang } = props;
  const zone = String(s.factory?.timezone || 'UTC');
  const name = (en: string | null, ar: string | null) => lang === 'ar' ? ar || en || '—' : en || '—';
  return <div className="mr-detail">
    <div className="mr-detail-heading"><MaintenanceBadge status={r.status} t={t} /><span className="mr-priority" data-priority={r.priority}>{t(`maintenancePriority_${r.priority}`)}</span></div>
    <h3 dir="auto">{r.title}</h3><p dir="auto" className="mr-problem-description">{r.description || '—'}</p>
    <dl className="mr-facts">
      <div><dt>{t('machine')}</dt><dd><bdi>{r.machine_code}</bdi> · {name(r.machine_name,r.machine_name_ar)}</dd></div>
      <div><dt>{t('line')}</dt><dd>{name(r.line_name,r.line_name_ar)}</dd></div>
      <div><dt>{t('mpKind')}</dt><dd>{t(r.maintenance_kind ? 'mpKind_'+r.maintenance_kind : 'mpUnknown')}</dd></div>
      <div><dt>{t('mpDuration')}</dt><dd>{r.estimated_duration_minutes ? formatDuration(r.estimated_duration_minutes,lang) : '—'}</dd></div>
      <div><dt>{t('mpRequestedWindow')}</dt><dd>{formatTime(r.preferred_start,lang,zone)} — {formatTime(r.preferred_end,lang,zone)}</dd></div>
      <div><dt>{t('maintenanceSource')}</dt><dd>{t(`maintenanceSource_${r.source}`)}</dd></div>
      <div><dt>{t('maintenanceRequestedBy')}</dt><dd dir="auto">{r.requested_by_name}</dd></div>
      <div><dt>{t('maintenanceRequestedAt')}</dt><dd>{formatTime(r.requested_at,lang,zone)}</dd></div>
      <div><dt>{t('maintenanceAssignedTo')}</dt><dd dir="auto">{r.assignee_name || t('maintenanceUnassigned')}</dd></div>
    </dl>
    <ol className="mr-timeline">{[
      ['OPEN',r.requested_at,r.requested_by_name],['ASSIGNED',r.assigned_at,r.assignee_name],['IN_PROGRESS',r.started_at,null],
      ['COMPLETED',r.completed_at,r.completer_name],['VERIFIED',r.verified_at,r.verifier_name],['CANCELLED',r.cancelled_at,null],
    ].filter(([,stamp]) => stamp).map(([state,stamp,person]) => <li key={state}>
      <strong>{t(`maintenanceState_${state}`)}</strong><span>{formatTime(stamp,lang,zone)}{person ? ` · ${person}` : ''}</span>
    </li>)}</ol>
    {r.work_note && <section><h4>{t('maintenanceWorkDone')}</h4><p dir="auto" className="mr-note">{r.work_note}</p></section>}
    {r.status === 'COMPLETED' && <p className="mr-warning">{t('maintenanceAwaitingVerification')}</p>}
    {r.verification_result && <section><h4>{t('maintenanceVerification')}</h4>
      <p>{t(`maintenanceResult_${r.verification_result}`)} · {r.checker_name || '—'} · {formatTime(r.checked_at,lang,zone)}</p>
      <p dir="auto" className="mr-note">{r.verification_note}</p></section>}
    {r.cancellation_note && <p dir="auto" className="mr-note">{t('maintenanceCancelledReason')}: {r.cancellation_note}</p>}
    {r.downtime_id && <section className="mr-linked-stop"><h4>{t('maintenanceLinkedDowntime')}</h4>
      {r.downtime ? <><p>{formatTime(r.downtime.started_at,lang,zone)} — {formatTime(r.downtime.ended_at,lang,zone)}</p>
        <p dir="auto">{name(String(r.downtime.reason_name || ''),String(r.downtime.reason_name_ar || '')) || t('downtimeUnclassified')}</p>
        {r.downtime.approved_cause_name && <p>{t('downtimeApprovedCause')}: {name(String(r.downtime.approved_cause_name),String(r.downtime.approved_cause_name_ar || ''))}</p>}
        <p dir="auto" className="mr-note">{String(r.downtime.initial_note || r.downtime.notes || '')}</p></>
        : <p>{t('maintenanceDowntimePermission')}</p>}
      <button type="button" onClick={() => window.dispatchEvent(new CustomEvent('factory-downtime-open',{detail:r.downtime_id}))}
        disabled={!props.can('downtime')}>{t('maintenanceOpenDowntime')}</button>
      {r.saved_loss && <p>{t('maintenanceSavedLoss')}: {typeof r.saved_loss.effective_loss_minutes === 'number'
        ? formatDuration(r.saved_loss.effective_loss_minutes,lang) : t('lossMissing')} · {t('maintenanceReadOnly')}</p>}
    </section>}
  </div>;
}

function MaintenanceRequestFields({request, machines, busy, onSave, ...props}:FeatureProps & {
  request:MaintenanceRequest; machines:Row[]; busy:boolean;
  onSave:(payload:Record<string,unknown>)=>Promise<void>;
}) {
  const {snapshot,t,lang}=props;
  const zone=String(snapshot.factory?.timezone || 'UTC');
  const [equipment,setEquipment]=useState(request.work_center_id);
  const [title,setTitle]=useState(request.title);
  const [description,setDescription]=useState(request.description);
  const [kind,setKind]=useState(request.maintenance_kind || '');
  const [duration,setDuration]=useState(String(request.estimated_duration_minutes || ''));
  const originalFrom=request.preferred_start ? formatLocalInput(request.preferred_start,zone,true) : '';
  const originalUntil=request.preferred_end ? formatLocalInput(request.preferred_end,zone,true) : '';
  const [from,setFrom]=useState(originalFrom);
  const [until,setUntil]=useState(originalUntil);
  const [error,setError]=useState('');
  const downtimeLinked=request.source==='DOWNTIME'||Boolean(request.downtime_id);
  const changed=equipment!==request.work_center_id || title!==request.title || description!==request.description ||
    kind!==(request.maintenance_kind||'') || duration!==String(request.estimated_duration_minutes||'') ||
    from!==originalFrom || until!==originalUntil;
  async function submit(event:React.FormEvent) {
    event.preventDefault();
    if (busy || !changed || !kind) return;
    setError('');
    let preferredStart,preferredEnd;
    try {
      preferredStart=from===originalFrom ? request.preferred_start || null : from ? localDateTimeToUtc(from,zone) : null;
      preferredEnd=until===originalUntil ? request.preferred_end || null : until ? localDateTimeToUtc(until,zone) : null;
    } catch {setError('maintenanceUnknownWindow');return;}
    if(preferredStart && preferredEnd && Date.parse(preferredEnd)<=Date.parse(preferredStart)){
      setError('mpPreferredOrder');return;
    }
    await onSave({
      work_center_id:equipment,title,description,maintenance_kind:kind,
      estimated_duration_minutes:duration ? Number(duration) : null,
      preferred_start:preferredStart,preferred_end:preferredEnd,planning_notes:request.planning_notes || '',
    });
  }
  return <details className="mr-filters">
    <summary>{t('mpEditRequestDetails')}</summary>
    <form className="mr-form" onSubmit={submit}>
      {error && <p role="alert">{t(error)}</p>}
      <fieldset disabled={busy}>
        <Field label={t('machine')}><select required disabled={downtimeLinked} value={equipment} onChange={event=>setEquipment(event.target.value)}>
          {!machines.some(machine=>machine.id===request.work_center_id) && <option value={request.work_center_id}>{request.machine_name}</option>}
          {machines.map(machine=><option key={String(machine.id)} value={String(machine.id)}>{localName(machine,lang)}</option>)}
        </select></Field>
        <Field label={t('maintenanceProblem')}><input required maxLength={200} value={title} onChange={event=>setTitle(event.target.value)}/></Field>
        <Field label={t('description')}><textarea maxLength={4000} value={description} onChange={event=>setDescription(event.target.value)}/></Field>
        <Field label={t('mpKind')}><select required value={kind} onChange={event=>setKind(event.target.value as typeof kind)}>
          <option value="">{t('select')}</option><option value="CORRECTIVE">{t('mpKind_CORRECTIVE')}</option>
          {!downtimeLinked && <option value="PLANNED">{t('mpKind_PLANNED')}</option>}
        </select></Field>
        <Field label={t('mpDuration')+' · '+t('minutes')}><input type="number" min="1" step="1" required={kind==='PLANNED'}
          value={duration} onChange={event=>setDuration(event.target.value)}/></Field>
        <div className="mp-window-fields">
          <Field label={t('mpPreferredStart')}><input type="datetime-local" step="1" value={from} onChange={event=>setFrom(event.target.value)}/></Field>
          <Field label={t('mpPreferredEnd')}><input type="datetime-local" step="1" value={until} onChange={event=>setUntil(event.target.value)}/></Field>
        </div>
      </fieldset>
      <button disabled={busy || !kind || !changed}>{t('mpSaveDetails')}</button>
    </form>
  </details>;
}

type MaintenanceStartContext = {
  applies:boolean;
  blocker:string|null;
  planned_start:string|null;
  planned_end:string|null;
  estimated_end:string|null;
  overrun_seconds:number|null;
  actual_start:string|null;
  actual_end:string|null;
  affected:{kind:string;code:string|null;state:string;starts:string|null;ends:string|null}[];
};

const maintenanceStartMessages:Record<string,string> = {
  maintenance_planning_inactive:'maintenancePlanningInactive',
  maintenance_approval_required:'maintenanceApprovalRequired',
  maintenance_early_start:'maintenanceEarlyStart',
  maintenance_unknown_window:'maintenanceUnknownWindow',
  maintenance_machine_not_ready:'maintenanceMachineNotReady',
  maintenance_configuration_changed:'maintenanceConfigurationChanged',
  maintenance_transfer_unresolved:'maintenanceTransferUnresolved',
  maintenance_capacity_reserved:'maintenanceCapacityReserved',
  maintenance_production_conflict:'maintenanceProductionConflict',
};

export function MaintenanceDetails({ id, onClose, ...props }: FeatureProps & { id: string; onClose: () => void }) {
  const { snapshot: s, t, lang, can, command } = props;
  const [historyPage, setHistoryPage] = useState(1), [busy, setBusy] = useState(false), [error,setError] = useState('');
  const [assignee,setAssignee] = useState(''), [priority,setPriority] = useState(''), [note,setNote] = useState('');
  const [verification,setVerification] = useState(''), [result,setResult] = useState('RESOLVED'), [cancel,setCancel] = useState(false);
  const [cancelNote,setCancelNote] = useState('');
  const retry = useRef<{ key: string; id: string } | null>(null);
  const factory = String(s.factory?.id || '');
  const read = useHistoryData<MaintenancePage>(`/api/maintenance?factory=${factory}&selected=${id}&history_page=${historyPage}`,s.fetchedAt);
  const r = read.data?.detail;
  const actions: string[] = maintenanceActions(r,s.user.id,can('maintenance','edit'));
  const canStart=actions.includes('start');
  const checkStart=Boolean(r && maintenanceKindCanBook(r));
  const [checkTick,setCheckTick]=useState(0);
  const startRead=useHistoryData<MaintenanceStartContext>(
    checkStart ? '/api/maintenance?'+new URLSearchParams({factory,start_context:id}) : null,
    [s.fetchedAt,r?.revision,checkTick].join(':'));
  const startContext=startRead.data;
  const startBlocked=checkStart && (!startContext || !!startRead.error || !!startContext.blocker);
  const conflict=Boolean(startContext?.blocker && ['maintenance_capacity_reserved','maintenance_production_conflict'].includes(startContext.blocker));
  const zone=String(s.factory?.timezone || 'UTC');
  const time=(value:string|null)=>formatTime(value,lang,zone);
  const deviation=(actual:string,plan:string)=>formatDuration((Date.parse(actual)-Date.parse(plan))/60_000,lang,true);
  useEffect(()=>{
    if (!canStart || !startContext?.applies) return;
    const untilStart=Date.parse(startContext.planned_start || '')-Date.now();
    const delay=untilStart>0 ? Math.min(untilStart+100,30_000) : 30_000;
    const timer=setTimeout(()=>setCheckTick(tick=>tick+1),delay);
    return ()=>clearTimeout(timer);
  },[canStart,startContext,checkTick]);
  async function run(operation: string,payload: Record<string,unknown>) {
    if (!r) return;
    const args = { factory,maintenance_request:id,operation,payload,expected_revision:r.revision };
    const key = JSON.stringify(args);
    if (retry.current?.key !== key) retry.current = { key,id:crypto.randomUUID() };
    setBusy(true);setError('');
    try { await command(operation==='details' ? 'maintenance_planning_command' : 'change_maintenance_request',{...args,request_id:retry.current.id});
      retry.current=null;setCancel(false);read.reload(); }
    catch(cause) {
      setError(cause instanceof Error ? cause.message : 'error');
      read.reload();
      if(operation==='start') startRead.reload();
    }
    finally { setBusy(false); }
  }
  return <Dialog title={r?.code || t('maintenanceRequest')} t={t} onClose={() => { if (!busy) onClose(); }}>
    {(error || read.error) && <p role="alert">{t(error || read.error)} <button onClick={read.reload}>{t('refresh')}</button></p>}
    {read.loading && <p role="status">{t('loading')}</p>}
    {!read.loading && !read.error && !r && <p role="alert">{t('mpRepairNotFound')}</p>}
    {r && <><MaintenanceDetailBody {...props} request={r} />
      {can('maintenance','edit') && ['OPEN','ASSIGNED'].includes(r.status) &&
        <MaintenanceRequestFields key={r.id+':'+r.revision} {...props} request={r} busy={busy}
          machines={read.data?.options.machines || []} onSave={payload=>run('details',payload)}/>}
      {maintenanceKindCanBook(r) && <MaintenanceActualStops key={r.id} {...props} id={r.id} />}
      <div className="mr-workflow">
        {actions.includes('assign') && <form onSubmit={event => {event.preventDefault();void run('assign',{assigned_to:assignee});}}>
          <Field label={t('maintenanceAssignedTo')}><select required value={assignee} onChange={event => setAssignee(event.target.value)}>
            <option value="">{t('chooseEmployee')}</option>{read.data?.options.people.map(person => <option key={String(person.id)} value={String(person.id)}>{String(person.name)}</option>)}
          </select></Field><button disabled={busy || !assignee}>{t('maintenanceAssign')}</button>
        </form>}
        {actions.includes('priority') && <form onSubmit={event => {event.preventDefault();void run('priority',{priority:priority || r.priority});}}>
          <Field label={t('mpUrgency')}><select value={priority || r.priority} onChange={event => setPriority(event.target.value)}>
            {[...new Set([r.priority,'NORMAL','URGENT'])].map(value => <option key={value} value={value}>{t(`maintenancePriority_${value}`)}</option>)}
          </select></Field><button disabled={busy || !priority || priority === r.priority}>{t('save')}</button>
        </form>}
        {canStart && <>
          {checkStart && startRead.loading && !startContext && <p role="status">{t('mpCheckingStart')}</p>}
          {checkStart && startRead.error && <p role="alert">{t(startRead.error)} <button onClick={startRead.reload}>{t('refresh')}</button></p>}
          {startContext?.applies && <>
            {startContext.planned_start && startContext.planned_end && <p>
              {t('mpWindow')} · {time(startContext.planned_start)} — {time(startContext.planned_end)}
            </p>}
            {startContext.estimated_end && <p>{t('mpEstimatedFinish')} · {time(startContext.estimated_end)}</p>}
            {Number(startContext.overrun_seconds)>0 && <p role="status" className="mr-warning">
              {t('mpExpectedOverrun')} · {formatDuration(Math.ceil(Number(startContext.overrun_seconds)/60),lang)}
            </p>}
            {startContext.blocker && <div role="status" className="mr-warning">
              <p>{t(maintenanceStartMessages[startContext.blocker] || 'maintenanceUnknownWindow')}</p>
              {startContext.affected.length>0 && <ul aria-label={t('mpAffectedWork')}>
                {startContext.affected.map((work,index)=><li key={index}>
                  <bdi>{work.code || t(work.kind==='PRODUCTION'?'production':'maintenance')}</bdi>
                  {work.state==='active' ? ' · '+t('planningInProduction') : work.starts ? ' · '+time(work.starts) : ''}
                </li>)}
              </ul>}
              {conflict && <p>{t('mpResolveStartConflict')} {can('orders','view') && <a href="?view=planning">{t('planning')}</a>}</p>}
              {startContext.blocker==='maintenance_approval_required' && can('orders','view') &&
                <p><a href="?view=planning">{t('planning')}</a></p>}
            </div>}
          </>}
          <button className="primary" disabled={busy || startBlocked} onClick={() => void run('start',{})}>{t('maintenanceStart')}</button>
        </>}
        {startContext?.actual_start && startContext.planned_start && <p>
          {t('executionActualStart')} · {time(startContext.actual_start)} ({deviation(startContext.actual_start,startContext.planned_start)})
        </p>}
        {startContext?.actual_end && startContext.planned_end && <p>
          {t('executionActualFinish')} · {time(startContext.actual_end)} ({deviation(startContext.actual_end,startContext.planned_end)})
        </p>}
        {actions.includes('note') && <form onSubmit={event => {event.preventDefault();void run('note',{work_note:note || r.work_note});}}>
          <Field label={t('maintenanceWorkDone')}><textarea required maxLength={4000} value={note || r.work_note} onChange={event => setNote(event.target.value)} /></Field>
          <div className="mr-actions"><button disabled={busy || !(note || r.work_note).trim()}>{t('maintenanceSaveNote')}</button>
            <button type="button" className="primary" disabled={busy || !(note || r.work_note).trim()}
              onClick={() => void run('complete',{work_note:note || r.work_note})}>{t('maintenanceComplete')}</button></div>
        </form>}
        {actions.includes('verify') && <form onSubmit={event => {event.preventDefault();void run('verify',{result,verification_note:verification});}}>
          <Field label={t('maintenanceVerification')}><select value={result} onChange={event => setResult(event.target.value)}>
            <option value="RESOLVED">{t('maintenanceResult_RESOLVED')}</option><option value="REWORK_REQUIRED">{t('maintenanceResult_REWORK_REQUIRED')}</option>
          </select></Field><Field label={t('maintenanceVerificationNote')}><textarea required maxLength={4000} value={verification} onChange={event => setVerification(event.target.value)} /></Field>
          <button className="primary" disabled={busy || !verification.trim()}>{t(result === 'RESOLVED' ? 'maintenanceVerify' : 'maintenanceReturnWork')}</button>
        </form>}
        {r.status === 'COMPLETED' && !actions.includes('verify') && <p className="muted">{t('maintenanceIndependentVerifier')}</p>}
        {actions.includes('cancel') && !cancel && <button disabled={busy} onClick={() => setCancel(true)}>{t('maintenanceCancel')}</button>}
        {cancel && <form onSubmit={event => {event.preventDefault();void run('cancel',{cancellation_note:cancelNote});}} className="mr-warning">
          <p>{t('maintenanceCancelConfirm')}</p><Field label={t('reason')}><textarea required maxLength={4000} value={cancelNote} onChange={event => setCancelNote(event.target.value)} /></Field>
          <div className="mr-actions"><button disabled={busy || !cancelNote.trim()}>{t('maintenanceCancel')}</button><button type="button" disabled={busy} onClick={() => setCancel(false)}>{t('cancel')}</button></div>
        </form>}
      </div>
      <details className="mr-history"><summary>{t('audit')}</summary><ol>
        {read.data?.history.map(row => <li key={row.id}><strong>{row.actor_name || t('requestCreatorNotRecorded')}</strong> · {formatTime(row.created_at,props.lang,String(s.factory?.timezone))}
          <p>{row.old_data?.status !== row.new_data?.status
            ? `${row.old_data ? t(`maintenanceState_${row.old_data.status}`)+' → ' : ''}${t(`maintenanceState_${row.new_data?.status}`)}`
            : row.old_data?.assigned_to !== row.new_data?.assigned_to ? t('maintenanceAssign')
              : row.old_data?.priority !== row.new_data?.priority ? t('priority') : t('maintenanceSaveNote')}</p>
          {row.new_data?.work_note && row.old_data?.work_note !== row.new_data.work_note && <p className="mr-note" dir="auto">{row.new_data.work_note}</p>}
          {row.new_data?.verification_note && row.old_data?.verification_note !== row.new_data.verification_note && <p className="mr-note" dir="auto">{row.new_data.verification_note}</p>}
        </li>)}
      </ol><div className="mr-actions"><button disabled={read.loading || historyPage===1} onClick={() => setHistoryPage(value => value-1)}>{t('previous')}</button>
        <span>{historyPage}</span><button disabled={read.loading || historyPage*25>=(read.data?.history_total || 0)} onClick={() => setHistoryPage(value => value+1)}>{t('next')}</button></div></details>
    </>}
  </Dialog>;
}

export default function MaintenanceContext({ machine, downtime, lazy = false, ...props }: FeatureProps & { machine: Row; downtime?: Row; lazy?: boolean }) {
  const { snapshot:s,t,can } = props;
  const [creating,setCreating] = useState(false), [selected,setSelected] = useState('');
  const [expanded,setExpanded] = useState(false);
  const eligible = can('maintenance','view') || can('maintenance','edit') || can('maintenance','create') || s.membership?.status === 'approved';
  const read = useHistoryData<{ rows: Row[]; total: number }>(eligible && (!lazy || expanded)
    ? `/api/maintenance?factory=${s.factory?.id}&context_machine=${machine.id}` : null,s.fetchedAt);
  if (!eligible) return null;
  return <section className="mr-context">{lazy ? <button aria-expanded={expanded} onClick={() => setExpanded(value => !value)}>{t('maintenance')}</button> : <h4>{t('maintenance')}</h4>}
    {(!lazy || expanded) && <>
    {read.loading && <p role="status">{t('loading')}</p>}
    {read.error && <p role="alert">{t(read.error)} <button onClick={read.reload}>{t('refresh')}</button></p>}
    {read.data?.rows.map(row => <p key={String(row.id)}>{row.can_open
      ? <button type="button" onClick={() => setSelected(String(row.id))}><bdi>{String(row.code)}</bdi> · {t(`maintenanceState_${row.status}`)}</button>
      : <><bdi>{String(row.code)}</bdi> · {t(`maintenanceState_${row.status}`)}</>}</p>)}
    {read.data && read.data.total>10 && <p>{t('maintenanceMoreRequests')}</p>}
    {can('maintenance','create') && read.data && (!downtime || !read.data.rows.some(row => row.downtime_id === downtime.id))
      && <button type="button" onClick={() => setCreating(true)}>{t('maintenanceRequestAction')}</button>}
    {creating && <MaintenanceCreate {...props} machine={machine} downtime={downtime} onClose={() => setCreating(false)}
      onCreated={id => {setCreating(false);setSelected(id);read.reload();}} />}
    {selected && <MaintenanceDetails key={selected} {...props} id={selected} onClose={() => {setSelected('');read.reload();}} />}
    </>}
  </section>;
}
