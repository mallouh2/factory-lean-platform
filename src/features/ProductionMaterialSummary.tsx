import {useHistoryData}from'@/hooks/useHistoryData';
import {localName}from'@/components/ui';
import {useEffect,useRef,useState}from'react';
import type{FeatureProps}from'./types';
type Materials={ready:boolean;reason:string|null;scope?:string;required_output?:string;rows:{id:string;name:string;name_ar?:string;required:string;production_held:string;missing:string;unit:string}[];legacy?:{name:string;name_ar?:string;held:string;unit:string}[]};
export default function ProductionMaterialSummary({props,item}:{props:FeatureProps;item:string}){
 const{snapshot:s,t,lang}=props,factory=String(s.factory?.id||''),container=useRef<HTMLElement>(null),[visible,setVisible]=useState(false);
 useEffect(()=>{const node=container.current;if(!node)return;const observer=new IntersectionObserver(entries=>setVisible(entries.some(e=>e.isIntersecting)),{rootMargin:'160px'});observer.observe(node);return()=>observer.disconnect();},[]);
 const read=useHistoryData<{factory:string;item:string;materials:Materials}>(visible?`/api/production-readiness?factory=${factory}&item=${item}`:null,s.fetchedAt),data=read.data?.factory===factory&&read.data?.item===item?read.data.materials:null;
 const noBooking=data?.scope==='PRODUCTION_STOCK_SHIFT'&&['production_stock_schedule_required','production_stock_no_shift_output'].includes(data.reason||'');
 return <section ref={container} className="production-material-summary" aria-label={t('materialPreparation')}>
  <p>{t('floorPlannedReservations')}: {t(!data?(read.loading?'loading':read.error?'productionReadinessUnavailable':'productionReadinessRechecked'):noBooking?'psNoCurrentBooking':data.ready?'psMaterialsReady':data.reason||'psStartBlocked')}</p>
  {!noBooking&&data?.rows.length? <ul>{data.rows.map(r=><li key={r.id}><span dir="auto">{localName(r,lang)}</span> · {t('psReservedForecast')} <bdi>{r.production_held} / {r.required} {t(r.unit)}</bdi></li>)}</ul>:null}
  {!!data?.legacy?.length&&<ul>{data.legacy.map((r,n)=><li key={n}>{localName(r,lang)}: {t('psLegacyHeld')} <bdi>{r.held} {t(r.unit)}</bdi></li>)}</ul>}
  {read.error&&<p role="alert">{t(read.error)}</p>}
 </section>;
}
