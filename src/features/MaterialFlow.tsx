import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field, formatTime } from '@/components/ui';
import { useSupply, useSupplyCommand, type SupplyRow } from './useSupply';
export default function MaterialFlow(props: FeatureProps & { warehouse?: boolean }) {
  const { snapshot:s, t, lang, can, warehouse = false }=props;
  const [page,setPage]=useState(1),[create,setCreate]=useState(false),[kind,setKind]=useState('stock'),[choice,setChoice]=useState<SupplyRow|null>(null);
  const [search,setSearch]=useState(''),[choicePage,setChoicePage]=useState(1),[selection,setSelected]=useState<SupplyRow|null>(null),[reason,setReason]=useState('');
  const read=useSupply(s,'materials',{page:String(page)}),choices=useSupply(s,kind==='stock'?'catalogue':'lots',{page:String(choicePage),filters:JSON.stringify({search})},create);
  const selected=read.data?.rows.find(row=>row.id===selection?.id)||selection;
  const heading=useRef<HTMLHeadingElement>(null);
  useEffect(()=>{if(!warehouse)heading.current?.focus();},[warehouse,create,selection?.id]);
  const action=useSupplyCommand(props.command,s.factory?.id);
  const itemName=(row:SupplyRow)=>String(lang==='ar'?row.name_ar||row.name:row.name);
  const person=(id:unknown)=>String((s.membership?.user_id===id?s.membership:(s.tables.memberships||[]).find(row=>row.user_id===id))?.display_name||t('notAvailable'));
  async function change(next:string) {
    if(!selected)return;
    if(await action.run('material_change',{id:selected.id,revision:selected.revision,action:next,reason})){setSelected(null);read.refresh();}
  }
  const panel=(title:string,onClose:()=>void,children:ReactNode)=>warehouse?<Dialog title={title} t={t} onClose={onClose}>{children}</Dialog>:<section className="material-working-screen"><button className="orders-v2-back" disabled={action.busy} onClick={onClose}>← {t("materialRequests")}</button><h3 ref={heading} tabIndex={-1}>{title}</h3>{children}</section>;
  return <section className="supply-page" dir={lang==='ar'?'rtl':'ltr'}>
    {(warehouse||(!create&&!selected))&&<><header className="section-head"><h2 ref={warehouse?undefined:heading} tabIndex={-1}>{t(warehouse?'warehouseProductionMaterialRequests':'materialRequests')}</h2>{!warehouse&&can('orders','edit')&&<button className="primary" onClick={()=>{setCreate(true);setChoice(null);action.clearError();}}>{t('materialRequestCreate')}</button>}<button onClick={read.refresh}>{t('refresh')}</button></header>
    {read.error&&<p role="alert">{t(read.error)}</p>}{read.busy&&<p role="status">{t('loading')}</p>}
    {!read.busy&&!read.data?.rows.length&&<p className="empty">{t('materialRequestsEmpty')}</p>}
    <div className="supply-directory">{read.data?.rows.map(row=><article key={String(row.id)}>
      <strong>{String(row.item_name)}</strong><p>{String(row.quantity)} {t(String(row.unit))} · {t('materialState_'+String(row.status))}</p>
      <p>{String(row.requested_by_name)} · {formatTime(row.created_at,lang,String(s.factory?.timezone||'UTC'))}</p>
      {Boolean(row.note)&&<p className="supply-note">{String(row.note)}</p>}
      <button onClick={()=>{setSelected(row);setReason('');action.clearError();}}>{t('open')}</button>
    </article>)}</div>
    <nav className="fulfillment-pagination"><button disabled={page===1||read.busy} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav></>}
    {create&&panel(t('materialRequestCreate'),()=>{if(!action.busy)setCreate(false);},<>
      <Field label={t('inventoryType')}><select value={kind} onChange={e=>{setKind(e.target.value);setChoice(null);setChoicePage(1);}}><option value="stock">{t('inventoryCatalogue')}</option><option value="lot">{t('inventorySemiFinished')}</option></select></Field>
      {kind==='stock'&&<Field label={t('search')}><input maxLength={200} value={search} onChange={e=>{setSearch(e.target.value);setChoicePage(1);setChoice(null);}}/></Field>}
      <Field label={t('materialRequestItem')}><select required value={String(choice?.id||'')} onChange={e=>setChoice(choices.data?.rows.find(row=>row.id===e.target.value)||null)}><option value="">{t('select')}</option>
        {choices.data?.rows.filter(row=>kind==='stock'||Number(row.warehouse_quantity)>0).map(row=><option key={String(row.id)} value={String(row.id)}>{itemName(row)} · {String(row.unit||'—')}{kind==='lot'?' · '+String(row.remaining_work)+' · '+String(row.warehouse_quantity):''}</option>)}</select></Field>
      <div className="row-actions"><button disabled={choicePage===1||choices.busy} onClick={()=>{setChoicePage(x=>x-1);setChoice(null);}}>{t('previous')}</button><span>{choicePage}</span><button disabled={choices.busy||choicePage*50>=(choices.data?.total||0)} onClick={()=>{setChoicePage(x=>x+1);setChoice(null);}}>{t('next')}</button></div>
      {choices.error&&<p role="alert">{t(choices.error)}</p>}
      {choice&&<form onSubmit={async e=>{e.preventDefault();const form=new FormData(e.currentTarget);if(await action.run('material_request',{item:choice.id,item_type:kind==='lot'?'lot':choice.entity,unit:choice.unit,quantity:Number(form.get('quantity')),note:form.get('note'),...(form.get('production_item_id')?{production_item_id:form.get('production_item_id')}:{})})){setCreate(false);read.refresh();}}}><fieldset disabled={action.busy}>
        <p>{t('stock_available')}: {String(kind==='lot'?choice.warehouse_quantity:choice.available)} {t(String(choice.unit||'—'))}</p>
        <Field label={t('quantity')}><input required name="quantity" type="number" step="any" min="0.000001"/></Field><Field label={t('notes')}><textarea name="note" maxLength={2000}/></Field>
        <details><summary>{t('materialProductionContext')}</summary><Field label={t('productItem')}><select name="production_item_id"><option value="">{t('notRequired')}</option>{(s.tables.production_orders||[]).filter(row=>['planned','active'].includes(String(row.status))).map(row=><option value={String(row.id)} key={String(row.id)}>{String(row.code)} · {String(s.tables.products.find(p=>p.id===row.product_id)?.name||'')}</option>)}</select></Field></details>
        {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary" disabled={!choice.unit}>{t('materialRequestConfirm')}</button>
      </fieldset></form>}
    </>)}
    {selected&&panel(t('materialRequests'),()=>{if(!action.busy)setSelected(null);},<>
      <strong>{String(selected.item_name)}</strong><p>{String(selected.quantity)} {t(String(selected.unit))} · {t('materialState_'+String(selected.status))}</p>
      <p>{String(selected.requested_by_name)} · {formatTime(selected.created_at,lang,String(s.factory?.timezone||'UTC'))}</p>
      {Boolean(selected.note)&&<p className="supply-note">{String(selected.note)}</p>}
      {Boolean(selected.production_item_id)&&<p>{t('productItem')}: {String((s.tables.production_orders||[]).find(row=>row.id===selected.production_item_id)?.code||t('notAvailable'))}</p>}
      {Boolean(selected.movement_id)&&<p className="material-issued-quantity"><strong>{t("materialIssuedQuantity")}: {String(selected.quantity)} {t(String(selected.unit))}</strong></p>}
      <section className="material-request-history"><h4>{t("materialRequestHistory")}</h4><ol><li>{t("materialState_REQUESTED")} · {String(selected.requested_by_name)} · {formatTime(selected.created_at,lang,String(s.factory?.timezone||"UTC"))}</li>{Boolean(selected.issued_at)&&<li>{t("materialState_ISSUED")} · {person(selected.issued_by)} · {formatTime(selected.issued_at,lang,String(s.factory?.timezone||"UTC"))}</li>}{Boolean(selected.received_at)&&<li>{t("materialState_RECEIVED")} · {person(selected.received_by)} · {formatTime(selected.received_at,lang,String(s.factory?.timezone||"UTC"))}</li>}</ol></section>
      {Boolean(selected.movement_id)&&<details><summary>{t('materialIssueTrace')}</summary><p>{t('materialIssuedBy')}: <span title={String(selected.issued_by)}>{person(selected.issued_by)}</span> · {formatTime(selected.issued_at,lang,String(s.factory?.timezone||'UTC'))}</p><p><bdi>{String(selected.movement_id)}</bdi></p></details>}
      {Boolean(selected.received_at)&&<p>{t('materialReceivedBy')}: <span title={String(selected.received_by)}>{person(selected.received_by)}</span> · {formatTime(selected.received_at,lang,String(s.factory?.timezone||'UTC'))}</p>}
      {Boolean(selected.reason)&&<p className="supply-note">{String(selected.reason)}</p>}
      {warehouse&&selected.status==='REQUESTED'&&can('warehouse','issue')&&<>
        <p>{t('materialIssueHelp')}</p><Field label={t('supplyReason')}><textarea value={reason} onChange={e=>setReason(e.target.value)} maxLength={2000}/></Field>
        <div className="row-actions"><button className="primary" disabled={action.busy} onClick={()=>void change('issue')}>{t('materialIssueConfirm')}</button>
        <button disabled={action.busy||!reason.trim()} onClick={()=>void change('reject')}>{t('purchaseStatus_REJECTED')}</button><button disabled={action.busy||!reason.trim()} onClick={()=>void change('cancel')}>{t('cancel')}</button></div></>}
      {selected.status==='ISSUED'&&selected.requested_by===s.user.id&&<button className="primary" disabled={action.busy} onClick={()=>void change('receive')}>{t('materialReceiveConfirm')}</button>}
      {action.error&&<p role="alert">{t(action.error)}</p>}
    </>)}
  </section>;
}
