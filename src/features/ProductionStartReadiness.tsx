import ProductionStock from './ProductionStock';
import {localName} from '@/components/ui';
import {useHistoryData} from '@/hooks/useHistoryData';
import type {Row} from '@/types';
import type {FeatureProps} from './types';
import {ProductionMaterials} from './MaterialPreparation';
import {useEffect,useRef} from 'react';

type Condition={ready:boolean;applicable?:boolean;reason:string|null;machine:Row|null};
type MaterialReadiness={scope?:string;required_output?:string;unit?:string;occurrence?:{ends_at:string};legacy?:{name:string;name_ar?:string;unit:string;held:string;reserved:string;consumed:string}[];ready:boolean;reason:string|null;rows:{id:string;name:string;name_ar?:string;required:string;production_held:string;missing:string;unit:string}[]};
type Readiness={factory:string;item:string;queue_ready:boolean;physical:Condition;maintenance_block:Condition|null;materials:MaterialReadiness};
export default function ProductionStartReadiness({item,busy,onStart,...props}:FeatureProps & {
  item:string;busy:boolean;onStart:()=>Promise<void>;
}) {
  const {snapshot:s,t,lang}=props;
  const read=useHistoryData<Readiness>(`/api/production-readiness?factory=${s.factory?.id}&item=${item}`,s.fetchedAt);
  const data=read.data?.factory===s.factory?.id && read.data?.item===item ? read.data : null;
  const blocker=data?.maintenance_block || (data && !data.physical.ready ? data.physical : null);
  const machine=blocker?.machine || data?.physical.machine;
  const materials=data?.materials,materialBlocked=!materials?.ready;
  const reload=useRef({run:read.reload,busy:read.loading});reload.current={run:read.reload,busy:read.loading};
  const knownScope=useRef({key:'',stock:false,reason:null as string|null}),scopeKey=String(s.factory?.id)+':'+item;
  if(knownScope.current.key!==scopeKey)knownScope.current={key:scopeKey,stock:false,reason:null};
  if(data){knownScope.current.stock=data.materials.scope==='PRODUCTION_STOCK_SHIFT';knownScope.current.reason=data.materials.reason;}
  const shiftEnd=materials?.occurrence?.ends_at,stockScope=knownScope.current.stock;
  const awaitingStock=['production_stock_shortage','production_stock_legacy_review','recording_shift_unavailable'].includes(knownScope.current.reason||'');
  useEffect(()=>{
    if(!stockScope)return;
    const refresh=()=>{if(!document.hidden&&!reload.current.busy)reload.current.run();};
    const timer=awaitingStock?setInterval(refresh,10000):undefined,end=shiftEnd?Date.parse(shiftEnd):NaN;
    const boundary=Number.isFinite(end)?setTimeout(refresh,Math.max(0,end-Date.now()+25)):undefined;
    window.addEventListener('focus',refresh);document.addEventListener('visibilitychange',refresh);
    return()=>{if(timer!==undefined)clearInterval(timer);if(boundary!==undefined)clearTimeout(boundary);window.removeEventListener('focus',refresh);document.removeEventListener('visibilitychange',refresh);};
  },[s.factory?.id,item,stockScope,shiftEnd,awaitingStock]);
  return <div className="ff2-start-readiness">
    <p role="status">{read.loading && !data ? t('loading') : !data ? t('productionReadinessUnavailable')
      : blocker ? t(`productionReadiness_${blocker.reason}`) : !data.queue_ready ? t('productionQueueChanged') : materialBlocked ? t(materials?.scope==='PRODUCTION_STOCK_SHIFT'?'psStartBlocked':'productionMaterialNotReady')
        : t(data.physical.applicable ? 'productionPhysicallyReady' : 'productionNoMaintenanceCheck')}</p>
    {machine && <p><bdi>{String(machine.code || '')}</bdi> · <span dir="auto">{localName(machine,lang)}</span> · {t(String(machine.status || 'notAvailable'))}</p>}
    {materials?.scope==='PRODUCTION_STOCK_SHIFT'&&<p>{t('psShiftForecast')}: <bdi>{materials.required_output||'—'} {t(materials.unit||'')}</bdi></p>}{data&&materialBlocked&&<div className="material-preparation">
      {materials?.reason&&materials.reason!=='material_handover_required'&&<p>{t(materials.reason)}</p>}
      {!!materials?.legacy?.length&&<><p>{t('psLegacyOrderHelp')}</p><ul>{materials.legacy.map((row,n)=><li key={n}><span dir="auto">{localName(row,lang)}</span>: {t('psLegacyHeld')} <bdi>{row.held} {t(row.unit)}</bdi>{row.reserved!=='0'&&<> · {t('psLegacyWarehouseReserved')} <bdi>{row.reserved} {t(row.unit)}</bdi></>}{row.consumed!=='0'&&<> · {t('materialConsumed')} <bdi>{row.consumed} {t(row.unit)}</bdi></>}</li>)}</ul></>}
      <ul>{materials?.rows.filter(row=>row.missing!=='0').map(row=><li key={row.id}><span dir="auto">{lang==='ar'?row.name_ar||row.name:row.name}</span>: <bdi>{row.missing} {t(row.unit)}</bdi> {t(materials.scope==='PRODUCTION_STOCK_SHIFT'?'production_stock_shortage':'materialMissingHandover')}</li>)}</ul>
      {materials?.scope==='PRODUCTION_STOCK_SHIFT'?<ProductionStock props={props}/>:<details><summary>{t('materialViewRequests')}</summary><ProductionMaterials props={props} item={item} onChanged={read.reload}/></details>}
    </div>}
    {read.error && <p role="alert">{t(read.error)}</p>}
    <p className="muted">{t('productionReadinessRechecked')}</p>
    <div className="ff2-row-actions">
      {props.can('orders','edit') && <button className="primary" disabled={busy || !data || !data.queue_ready || Boolean(blocker) || materialBlocked
        || Boolean(s.truncatedTables?.includes('production_orders'))}
        onClick={()=>void (async()=>{try{await onStart();}finally{read.reload();}})()}>{t(busy?'updating':'startProduction')}</button>}
      <button type="button" disabled={busy || read.loading} onClick={read.reload}>{t('refresh')}</button>
    </div>
  </div>;
}
