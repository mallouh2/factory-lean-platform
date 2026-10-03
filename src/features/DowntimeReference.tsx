import { Dialog,formatTime,localName } from '@/components/ui';
import { useHistoryData } from '@/hooks/useHistoryData';
import MaintenanceContext from './MaintenanceRequest';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
export default function DowntimeReference({id,onClose,...props}: FeatureProps & {id:string;onClose:()=>void}) {
  const {snapshot:s,t,lang} = props;
  const read = useHistoryData<{event:Row;machine:Row;line:Row;reason:Row;approved_cause:Row}>(
    `/api/maintenance?factory=${s.factory?.id}&downtime=${id}`,s.fetchedAt);
  const d=read.data,zone=String(s.factory?.timezone || 'UTC');
  return <Dialog title={t('maintenanceLinkedDowntime')} t={t} onClose={onClose}>
    {read.loading && <p role="status">{t('loading')}</p>}
    {read.error && <p role="alert">{t(read.error)} <button onClick={read.reload}>{t('refresh')}</button></p>}
    {d && <div className="mr-detail"><h3>{localName(d.machine,lang)}</h3><p>{localName(d.line,lang)}</p>
      <p>{formatTime(d.event.started_at,lang,zone)} — {formatTime(d.event.ended_at,lang,zone)}</p>
      <p>{t('downtimeInitialReason')}: {d.reason ? localName(d.reason,lang) : t('downtimeUnclassified')}</p>
      <p>{t('downtimeApprovedCause')}: {d.approved_cause ? localName(d.approved_cause,lang) : t('requestCreatorNotRecorded')}</p>
      <p className="mr-note" dir="auto">{String(d.event.initial_note || d.event.notes || '')}</p>
      <MaintenanceContext {...props} machine={d.machine} downtime={d.event} /></div>}
  </Dialog>;
}
