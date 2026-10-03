import { useEffect, useState } from 'react';
import { Field, formatTime } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import { maintenanceStates, maintenancePriorities } from '@/utils/maintenance.mjs';
import { MaintenanceBadge, MaintenanceCreate, MaintenanceDetails } from './MaintenanceRequest';
import type { MaintenancePage } from './maintenance-types';
import type { FeatureProps } from './types';

export default function Maintenance(props: FeatureProps) {
  const { snapshot:s,t,lang,can } = props;
  const [page,setPage] = useState(1), [filters,setFilters] = useState<Record<string,string>>({status:'ACTIVE'});
  const [creating,setCreating] = useState(false), [selected,setSelected] = useState('');
  useEffect(() => {
    const open = (event: Event) => setSelected(String((event as CustomEvent).detail));
    window.addEventListener('factory-maintenance-open',open);
    return () => window.removeEventListener('factory-maintenance-open',open);
  },[]);
  const query = new URLSearchParams({factory:String(s.factory?.id || ''),page:String(page),...filters});
  const read = useHistoryData<MaintenancePage>(`/api/maintenance?${query}`,s.fetchedAt);
  const options = read.data?.options;
  const zone = String(s.factory?.timezone || 'UTC');
  function filter(key:string,value:string) {setPage(1);setFilters(previous => {
    const next={...previous};if(value) next[key]=value;else delete next[key];return next;
  });}
  return <section className="mr-page" dir={lang==='ar' ? 'rtl' : 'ltr'}>
    <header className="mr-tools"><p>{t(read.data?.wide ? 'maintenanceHelp' : 'maintenanceMyWorkHelp')}</p><div className="mr-actions">
      {can('maintenance','create') && <button className="primary" onClick={() => setCreating(true)}>{t('maintenanceCreate')}</button>}
      <button onClick={read.reload}>{t('refresh')}</button></div></header>
    <div className="mr-counts">{maintenanceStates.filter((state:string) => state!=='CANCELLED').map((state:string) =>
      <button key={state} aria-pressed={filters.status===state} data-status={state} onClick={() => filter('status',state)}>
        <strong>{read.data ? read.data.counts[state] || 0 : '—'}</strong><span>{t(`maintenanceState_${state}`)}</span></button>)}</div>
    <details className="mr-filters"><summary>{t('historyFilters')}</summary><div className="mr-filter-grid">
      <Field label={t('status')}><select value={filters.status || 'ACTIVE'} onChange={event => filter('status',event.target.value)}>
        <option value="ACTIVE">{t('maintenanceActive')}</option><option value="ALL">{t('all')}</option>
        {maintenanceStates.map((state:string) => <option key={state} value={state}>{t(`maintenanceState_${state}`)}</option>)}
      </select></Field>
      <Field label={t('priority')}><select value={filters.priority || 'ALL'} onChange={event => filter('priority',event.target.value)}>
        <option value="ALL">{t('all')}</option>{maintenancePriorities.map((priority:string) => <option key={priority} value={priority}>{t(`maintenancePriority_${priority}`)}</option>)}
      </select></Field>
      {(['machine','line','assignee'] as const).map((key,index) => <Field key={key} label={t(['machine','line','maintenanceAssignedTo'][index])}>
        <select value={filters[key] || ''} onChange={event => filter(key,event.target.value)}><option value="">{t('all')}</option>
          {(key==='machine' ? options?.machines : key==='line' ? options?.lines : options?.people)?.map(row => <option key={String(row.id)} value={String(row.id)}>
            {String((lang==='ar' && row.name_ar) || row.name || row.code)}</option>)}
        </select></Field>)}
      <Field label={t('maintenanceSource')}><select value={filters.source || 'ALL'} onChange={event => filter('source',event.target.value)}>
        <option value="ALL">{t('all')}</option>{['MANUAL','DOWNTIME'].map(source => <option key={source} value={source}>{t(`maintenanceSource_${source}`)}</option>)}
      </select></Field>
      <Field label={t('maintenanceSince')}><input type="date" value={filters.since || ''} onChange={event => filter('since',event.target.value)} /></Field>
      <Field label={t('maintenanceUntil')}><input type="date" value={filters.until || ''} onChange={event => filter('until',event.target.value)} /></Field>
      <label className="check"><input type="checkbox" checked={filters.mine==='true'} onChange={event => filter('mine',event.target.checked ? 'true' : '')} />{t('maintenanceMyWork')}</label>
      <button onClick={() => {setFilters({status:'ACTIVE'});setPage(1);}}>{t('maintenanceClearFilters')}</button>
    </div></details>
    {read.error && <p role="alert">{t(read.error)} <button onClick={read.reload}>{t('refresh')}</button></p>}
    {read.loading && <p role="status">{t('loading')}</p>}
    {read.data && !read.data.rows.length && <div className="empty"><p>{t('maintenanceEmpty')}</p></div>}
    <div className="mr-list">{read.data?.rows.map(r => <article className="mr-row" key={r.id} data-status={r.status}>
      <header><button type="button" className="mr-open" onClick={() => setSelected(r.id)}><bdi>{r.code}</bdi><strong dir="auto">{r.title}</strong></button>
        <MaintenanceBadge status={r.status} t={t} /></header>
      <dl><div><dt>{t('machine')}</dt><dd><bdi>{r.machine_code}</bdi> · {lang==='ar' ? r.machine_name_ar || r.machine_name : r.machine_name}</dd></div>
        <div><dt>{t('line')}</dt><dd>{lang==='ar' ? r.line_name_ar || r.line_name || '—' : r.line_name || '—'}</dd></div>
        <div><dt>{t('priority')}</dt><dd><span className="mr-priority" data-priority={r.priority}>{t(`maintenancePriority_${r.priority}`)}</span></dd></div>
        <div><dt>{t('maintenanceSource')}</dt><dd>{t(`maintenanceSource_${r.source}`)}</dd></div>
        <div><dt>{t('maintenanceAssignedTo')}</dt><dd dir="auto">{r.assignee_name || t('maintenanceUnassigned')}</dd></div>
        <div><dt>{t('maintenanceRequestedAt')}</dt><dd>{formatTime(r.requested_at,lang,zone)}</dd></div>
      </dl>
      {r.downtime_id && <span className="mr-linked">{t('maintenanceLinkedDowntime')}</span>}
    </article>)}</div>
    <nav className="mr-pagination" aria-label={t('maintenance')}><button disabled={page===1 || read.loading} onClick={() => setPage(value => value-1)}>{t('previous')}</button>
      <span>{page} · {read.data?.total || 0} {t('maintenanceRequests')}</span><button disabled={read.loading || page*25>=(read.data?.total || 0)} onClick={() => setPage(value => value+1)}>{t('next')}</button></nav>
    {creating && <MaintenanceCreate {...props} onClose={() => setCreating(false)} onCreated={id => {setCreating(false);setSelected(id);read.reload();}} />}
    {selected && <MaintenanceDetails key={selected} {...props} id={selected} onClose={() => {setSelected('');read.reload();}} />}
  </section>;
}
