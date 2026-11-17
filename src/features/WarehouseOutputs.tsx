import OrderReference from '@/components/OrderReference';
import {WarehouseDialog as Dialog} from './WarehouseUi';
import { useState } from 'react';
import type { FeatureProps } from './types';
import { Field, formatTime } from '@/components/ui';
import { useSupply, useSupplyCommand, type SupplyRow } from './useSupply';
import { SourceIdentityDialog } from './SourceStock';
import ManufacturedReceiving from './ManufacturedReceiving';
export default function WarehouseOutputs(props:FeatureProps & { product?:string; mode?:'good'|'wip'; onClose?:()=>void; onChanged?:()=>void }) {
  const { snapshot:s,t,lang,can,product,onChanged }=props;
  const showGood=!product&&props.mode!=='wip',showWip=props.mode!=='good';
  const [page,setPage]=useState(1),[receiving,setReceiving]=useState<SupplyRow|null>(null),[quantity,setQuantity]=useState('');
  const [newFlow,setNewFlow]=useState(false);
  const [identifying,setIdentifying]=useState<SupplyRow|null>(null);
  const lots=useSupply(s,'lots',{page:String(page),...(product?{selected:product}:{})},showWip),good=useSupply(s,'outputs',{page:String(page)},showGood);
  const action=useSupplyCommand(props.command,s.factory?.id);
  const stamp=(value:unknown)=>formatTime(value,lang,String(s.factory?.timezone||'UTC'));
  async function run(name:string,payload:Record<string,unknown>){if(await action.run(name,payload)){setReceiving(null);lots.refresh();good.refresh();onChanged?.();}}
  const legacyGood=showGood&&(!newFlow||!!good.data?.rows.length);
  const body=<section className="supply-page warehouse-output-v1" dir={lang==='ar'?'rtl':'ltr'}>
    {showGood&&<ManufacturedReceiving {...props} onChanged={onChanged} onAvailability={setNewFlow}/>}
    {legacyGood&&<><h3>{t('warehouseGoodAcknowledgment')}</h3><p className="muted">{t('warehouseGoodAlreadyCredited')}</p>
      {good.busy&&<p role="status">{t('loading')}</p>}{!good.busy&&!good.error&&good.data&&!good.data.rows.length&&<p className="empty">{t('warehouseReceiptsEmpty')}</p>}
      {good.data?.rows.map(row=><article key={String(row.id)}><strong>{String(lang==='ar'?row.name_ar||row.name:row.name)}</strong><p><bdi>{String(row.code)}</bdi> · {String(row.effective_good)} {t(String(row.unit))} · {stamp(row.created_at)}</p>
        {can('warehouse','edit')&&<div className="row-actions">{!row.acknowledged&&<button disabled={action.busy} onClick={()=>void run('acknowledge_good',{entry:row.id})}>{t('warehouseAcknowledgeGood')}</button>}<button onClick={()=>setIdentifying(row)}>{t('sourceIdentify')}</button></div>}</article>)}</>}
    {(lots.error||good.error||action.error)&&<p role="alert">{t(lots.error||good.error||action.error)}</p>}
    {showWip&&<><h3>{t('inventorySemiFinished')}</h3>
    {lots.busy&&<p role="status">{t('loading')}</p>}{!lots.busy&&!lots.data?.rows.length&&<p className="empty">{t('unfinishedEmpty')}</p>}
    <div className="supply-directory">{lots.data?.rows.map(row=><article key={String(row.id)}>
      <strong>{String(lang==='ar'?row.name_ar||row.name:row.name)}</strong><p><OrderReference reference={row.item_code||row.request_code} item={row.item_id}/> · {t('unfinishedLotReference')}: <bdi>{String(row.id).slice(0,8)}</bdi></p>
      <p>{t('inventorySemiFinished')}: {String(row.warehouse_quantity)} {t(String(row.unit))} · {t('warehouseFloorWip')}: {String(row.floor_quantity)} {t(String(row.unit))}</p>
      <p>{t('unfinishedRemainingWork')}: {String(row.remaining_work)}</p><time>{stamp(row.created_at)}</time>
      <details><summary>{t('supplyHistory')}</summary><ol>{((row.movements||[]) as SupplyRow[]).map(movement=><li key={String(movement.id)}>{t('unfinishedMovement_'+String(movement.kind))}: {String(Number(movement.location_delta)||movement.quantity)} · {stamp(movement.created_at)} · <span title={String(movement.created_by)}>{String(movement.actor_name||t('notAvailable'))}</span></li>)}</ol></details>
      {can('warehouse','edit')&&Number(row.floor_quantity)>0&&<button onClick={()=>{setReceiving(row);setQuantity(String(row.floor_quantity));action.clearError();}}>{t('warehouseReceiveWip')}</button>}
    </article>)}</div></>}
    {(showWip||legacyGood)&&<nav className="fulfillment-pagination"><button disabled={page===1||lots.busy||good.busy} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{page}</span><button disabled={lots.busy||good.busy||page*50>=Math.max(lots.data?.total||0,good.data?.total||0)} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav>}
  </section>;
  return <>{product&&props.onClose?<Dialog {...props} title={t('inventorySemiFinished')} t={t} onClose={props.onClose}>{body}</Dialog>:body}
    {identifying&&<SourceIdentityDialog {...props} warehouse product={String(identifying.product_id)} unit={String(identifying.unit)} entry={String(identifying.id)} onClose={()=>setIdentifying(null)} onChanged={()=>{good.refresh();onChanged?.();}}/>}
    {receiving&&<Dialog {...props} title={t('warehouseReceiveWip')} t={t} onClose={()=>{if(!action.busy)setReceiving(null);}}>
      <strong>{String(receiving.name)}</strong><p>{String(receiving.remaining_work)}</p><form onSubmit={e=>{e.preventDefault();void run('receive_wip',{lot:receiving.id,quantity:Number(quantity)});}}><fieldset disabled={action.busy}>
        <Field label={t('quantity')+' ('+t(String(receiving.unit))+')'}><input required type="number" min="0.000001" step="any" max={Number(receiving.floor_quantity)} value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
        {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary">{t('warehouseConfirmPhysicalReceipt')}</button>
      </fieldset></form></Dialog>}
  </>;
}
