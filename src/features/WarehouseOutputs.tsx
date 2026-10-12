import { useState } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field, formatTime } from '@/components/ui';
import { useSupply, useSupplyCommand, type SupplyRow } from './useSupply';
import { SourceIdentityDialog } from './SourceStock';
export default function WarehouseOutputs(props:FeatureProps & { product?:string; onClose?:()=>void; onChanged?:()=>void }) {
  const { snapshot:s,t,lang,can,product,onChanged }=props;
  const [page,setPage]=useState(1),[receiving,setReceiving]=useState<SupplyRow|null>(null),[quantity,setQuantity]=useState('');
  const [identifying,setIdentifying]=useState<SupplyRow|null>(null);
  const lots=useSupply(s,'lots',{page:String(page),...(product?{selected:product}:{})}),good=useSupply(s,'outputs',{page:String(page)},!product);
  const action=useSupplyCommand(props.command,s.factory?.id);
  const stamp=(value:unknown)=>formatTime(value,lang,String(s.factory?.timezone||'UTC'));
  async function run(name:string,payload:Record<string,unknown>){if(await action.run(name,payload)){setReceiving(null);lots.refresh();good.refresh();onChanged?.();}}
  const body=<section className="supply-page" dir={lang==='ar'?'rtl':'ltr'}>
    {!product&&<><h3>{t('warehouseGoodAcknowledgment')}</h3><p className="muted">{t('warehouseGoodAlreadyCredited')}</p>
      {good.data?.rows.map(row=><article key={String(row.id)}><strong>{String(lang==='ar'?row.name_ar||row.name:row.name)}</strong><p><bdi>{String(row.code)}</bdi> · {String(row.effective_good)} {t(String(row.unit))} · {stamp(row.created_at)}</p>
        {can('warehouse','edit')&&<div className="row-actions">{!row.acknowledged&&<button disabled={action.busy} onClick={()=>void run('acknowledge_good',{entry:row.id})}>{t('warehouseAcknowledgeGood')}</button>}<button onClick={()=>setIdentifying(row)}>{t('sourceIdentify')}</button></div>}</article>)}</>}
    <h3>{t('inventorySemiFinished')}</h3>{(lots.error||good.error||action.error)&&<p role="alert">{t(lots.error||good.error||action.error)}</p>}
    {lots.busy&&<p role="status">{t('loading')}</p>}{!lots.busy&&!lots.data?.rows.length&&<p className="empty">{t('unfinishedEmpty')}</p>}
    <div className="supply-directory">{lots.data?.rows.map(row=><article key={String(row.id)}>
      <strong>{String(lang==='ar'?row.name_ar||row.name:row.name)}</strong><p><bdi>{String(row.request_code||row.item_code)}</bdi> · {t('unfinishedLotReference')}: <bdi>{String(row.id).slice(0,8)}</bdi></p>
      <p>{t('inventorySemiFinished')}: {String(row.warehouse_quantity)} {t(String(row.unit))} · {t('warehouseFloorWip')}: {String(row.floor_quantity)} {t(String(row.unit))}</p>
      <p>{t('unfinishedRemainingWork')}: {String(row.remaining_work)}</p><time>{stamp(row.created_at)}</time>
      <details><summary>{t('supplyHistory')}</summary><ol>{((row.movements||[]) as SupplyRow[]).map(movement=><li key={String(movement.id)}>{t('unfinishedMovement_'+String(movement.kind))}: {String(Number(movement.location_delta)||movement.quantity)} · {stamp(movement.created_at)} · <span title={String(movement.created_by)}>{String(movement.actor_name||t('notAvailable'))}</span></li>)}</ol></details>
      {can('warehouse','edit')&&Number(row.floor_quantity)>0&&<button onClick={()=>{setReceiving(row);setQuantity(String(row.floor_quantity));action.clearError();}}>{t('warehouseReceiveWip')}</button>}
    </article>)}</div>
    <nav className="fulfillment-pagination"><button disabled={page===1||lots.busy} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{page}</span><button disabled={lots.busy||page*50>=Math.max(lots.data?.total||0,good.data?.total||0)} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav>
  </section>;
  return <>{product&&props.onClose?<Dialog title={t('inventorySemiFinished')} t={t} onClose={props.onClose}>{body}</Dialog>:body}
    {identifying&&<SourceIdentityDialog {...props} product={String(identifying.product_id)} unit={String(identifying.unit)} entry={String(identifying.id)} onClose={()=>setIdentifying(null)} onChanged={()=>{good.refresh();onChanged?.();}}/>}
    {receiving&&<Dialog title={t('warehouseReceiveWip')} t={t} onClose={()=>{if(!action.busy)setReceiving(null);}}>
      <strong>{String(receiving.name)}</strong><p>{String(receiving.remaining_work)}</p><form onSubmit={e=>{e.preventDefault();void run('receive_wip',{lot:receiving.id,quantity:Number(quantity)});}}><fieldset disabled={action.busy}>
        <Field label={t('quantity')+' ('+t(String(receiving.unit))+')'}><input required type="number" min="0.000001" step="any" max={Number(receiving.floor_quantity)} value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
        {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary">{t('warehouseConfirmPhysicalReceipt')}</button>
      </fieldset></form></Dialog>}
  </>;
}
