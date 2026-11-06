import {localName} from '@/components/ui';
import {useHistoryData} from '@/hooks/useHistoryData';
import type {Row} from '@/types';
import type {FeatureProps} from './types';

type Condition={ready:boolean;applicable?:boolean;reason:string|null;machine:Row|null};
type Readiness={factory:string;item:string;queue_ready:boolean;physical:Condition;maintenance_block:Condition|null};
export default function ProductionStartReadiness({item,busy,onStart,...props}:FeatureProps & {
  item:string;busy:boolean;onStart:()=>Promise<void>;
}) {
  const {snapshot:s,t,lang}=props;
  const read=useHistoryData<Readiness>(`/api/production-readiness?factory=${s.factory?.id}&item=${item}`,s.fetchedAt);
  const data=read.data?.factory===s.factory?.id && read.data?.item===item ? read.data : null;
  const blocker=data?.maintenance_block || (data && !data.physical.ready ? data.physical : null);
  const machine=blocker?.machine || data?.physical.machine;
  return <div className="ff2-start-readiness">
    <p role="status">{read.loading && !data ? t('loading') : !data ? t('productionReadinessUnavailable')
      : blocker ? t(`productionReadiness_${blocker.reason}`) : !data.queue_ready ? t('productionQueueChanged')
        : t(data.physical.applicable ? 'productionPhysicallyReady' : 'productionNoMaintenanceCheck')}</p>
    {machine && <p><bdi>{String(machine.code || '')}</bdi> · <span dir="auto">{localName(machine,lang)}</span> · {t(String(machine.status || 'notAvailable'))}</p>}
    {read.error && <p role="alert">{t(read.error)}</p>}
    <p className="muted">{t('productionReadinessRechecked')}</p>
    <div className="ff2-row-actions">
      {props.can('orders','edit') && <button className="primary" disabled={busy || read.loading || !data || !data.queue_ready || Boolean(blocker)
        || Boolean(s.truncatedTables?.includes('production_orders'))}
        onClick={()=>void (async()=>{try{await onStart();}finally{read.reload();}})()}>{t('startProduction')}</button>}
      <button type="button" disabled={busy || read.loading} onClick={read.reload}>{t('refresh')}</button>
    </div>
  </div>;
}
