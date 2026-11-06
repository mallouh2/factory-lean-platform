import {useState} from 'react';
import {historyNumber} from '@/utils/production-history-view.mjs';
import {useSupply,type SupplyRow} from './useSupply';
import {WarehouseDialog} from './WarehouseUi';
import type {InventoryRow} from './WarehouseInventory';
import type {FeatureProps} from './types';
import {projectedQuantity,warehouseForecast} from '@/utils/warehouse-presentation.mjs';
import {warehouseColumnTitle} from '@/utils/warehouse-view.mjs';
import WarehouseReservations,{type InventoryExplanation} from './WarehouseReservations';
import WarehouseMovements,{MovementRow,type WarehouseMovement}from './WarehouseMovements';
export default function WarehouseItemDetails(props:FeatureProps&{row:InventoryRow;onClose:()=>void}){
 const {snapshot:s,t,lang,row}=props,[movements,setMovements]=useState(false),[sources,setSources]=useState(false),[sourcePage,setSourcePage]=useState(1),[reservationPage,setReservationPage]=useState(1);
 const explanation=useSupply<InventoryExplanation>(s,'context',{item:row.id,item_type:row.entity,unit:row.unit||'',page:String(reservationPage)},props.can('warehouse'),'/api/warehouse-inventory');
 const stock=explanation.data?.summary||row;
 const source=useSupply<{rows:SupplyRow[];unattributed:string;total:number}>(s,'sources',{product:row.id,unit:row.unit||'',page:String(sourcePage)},sources&&row.entity==='finished'&&!!row.unit&&props.can('warehouse'),'/api/quality');
 const q=(v:unknown,u=row.unit)=>v==null?t('notAvailable'):(historyNumber(v,lang)??t('notAvailable'))+(u?' '+t(u):'');
 const forecast=warehouseForecast(row),shortage=projectedQuantity(stock.projected),name=lang==='ar'?row.name_ar||row.name:row.name;
 if(movements)return <WarehouseMovements {...props} initialItem={row} backToDetails onClose={()=>setMovements(false)}/>;
 return <WarehouseDialog {...props} className="warehouse-item-dialog" title={t('historyViewDetails')} drawer onClose={props.onClose}>
  <header className="warehouse-item-identity"><h3>{name}</h3><p><bdi>{row.code}</bdi><span>{t(row.item_type)}</span>{row.unit&&<span>{t(row.unit)}</span>}</p></header>{!row.unit&&<p className="wv-warning" role="status">{t('wvUnknownUnit')}</p>}
  <dl className="wv-values warehouse-stock-summary">{(['on_hand','reserved','available'] as const).map(k=><div key={k} className={'warehouse-quantity-'+k}><dt>{t(warehouseColumnTitle(k))}</dt><dd><bdi>{q(stock[k])}</bdi></dd></div>)}</dl>
  {row.replenishment_status!=='OK'&&<p className="warehouse-item-status">{t('status')}: {t(row.replenishment_status==='INCOMING'?'whExpectedIncoming':'inventory_'+row.replenishment_status)}</p>}
  {explanation.loading&&<p role="status">{t('loading')}</p>}{explanation.error&&<p role="alert">{t(explanation.error)} <button onClick={explanation.refresh}>{t('refresh')}</button></p>}
  {explanation.data&&<><WarehouseReservations props={props} data={explanation.data} unit={row.unit} busy={explanation.busy} onPage={setReservationPage}/><section className="warehouse-recent-movements"><div className="warehouse-section-heading"><h4>{t('whRecentMovements')}</h4><button type="button" onClick={()=>setMovements(true)}>{t('whViewAllMovements')}</button></div>{explanation.data.recent.map(m=><MovementRow key={String(m.id)} props={props} compact movement={m as WarehouseMovement}/>)}{!explanation.data.recent.length&&<p>{t('noData')}</p>}</section></>}
  <details className="warehouse-additional-details"><summary>{t('whAdditionalDetails')}</summary>
   <dl className="wv-values warehouse-forecast-values"><div className={shortage.shortage?'warehouse-forecast-shortage':''}><dt>{t(shortage.shortage?'whExpectedShortage':'whProjected')}</dt><dd><bdi>{q(shortage.quantity)}</bdi></dd></div><div><dt>{t('whExpectedIncoming')}</dt><dd>{q(row.incoming)}</dd></div>{row.entity==='finished'&&<div><dt>{t('inventoryInProduction')}</dt><dd>{q(row.in_production)}</dd></div>}{forecast&&row.entity==='finished'&&<div><dt>{t('whForecastDemand')}</dt><dd>{q(forecast.demand)}</dd></div>}</dl>
   <p className="warehouse-forecast-help">{t(row.entity==='material'?'whMaterialForecastHelp':'whForecastHelp')}</p>{shortage.shortage&&<p className="warehouse-forecast-shortage">{t('whShortageHelp')}</p>}
   <dl className="wv-values">{[['semi_finished','inventorySemiFinished'],['minimum_stock','stockMin'],['maximum_stock','stockMax']].map(([k,label])=><div key={k}><dt>{t(label)}</dt><dd>{q(row[k as keyof InventoryRow])}</dd></div>)}</dl><p>{t('supplySource')}: {t('supply_'+row.supply_source)}</p>
   {Number(row.unit_breakdown?.length)>1&&<details><summary>{t('inventoryUnitBreakdown')}</summary><p>{t('inventoryUnitBreakdownHelp')}</p>{row.unit_breakdown?.map(x=><p key={String(x.unit)}>{t(String(x.unit))}: {t('stock_on_hand')} {q(x.on_hand,String(x.unit))} · {t('stock_reserved')} {q(x.reserved,String(x.unit))} · {t(projectedQuantity(x.projected).shortage?'whExpectedShortage':'whProjected')} {q(projectedQuantity(x.projected).quantity,String(x.unit))} · {t('whExpectedIncoming')} {q(x.incoming,String(x.unit))} · {t('inventorySemiFinished')} {q(x.semi_finished,String(x.unit))}</p>)}</details>}
   {row.entity==='finished'&&row.unit&&<details onToggle={e=>setSources(e.currentTarget.open)}><summary>{t('wvSources')}</summary>{source.error&&<p role="alert">{t(source.error)} <button onClick={source.refresh}>{t('refresh')}</button></p>}{source.loading&&<p role="status">{t('loading')}</p>}{source.data&&<><p>{t('sourceUnattributed')}: <strong>{q(source.data.unattributed)}</strong></p>{source.data.rows.map(x=><article className="wv-history" key={String(x.id)}><strong>{String(x.physical_label||t('sourceNotIdentified'))}</strong><p>{t('stock_on_hand')}: {q(x.available)} · {t('stock_reserved')}: {q(x.committed)} · {t('stock_available')}: {q(x.selectable)}</p></article>)}{!source.data.rows.length&&<p>{t('noData')}</p>}<nav className="fulfillment-pagination"><button disabled={sourcePage===1||source.busy} onClick={()=>setSourcePage(p=>p-1)}>{t('previous')}</button><span>{sourcePage}</span><button disabled={source.busy||sourcePage*50>=source.data.total} onClick={()=>setSourcePage(p=>p+1)}>{t('next')}</button></nav></>}</details>}
  </details>
 </WarehouseDialog>;
}
