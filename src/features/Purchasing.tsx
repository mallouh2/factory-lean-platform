import { useRef, useState } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field, formatTime } from '@/components/ui';
import { useSupply, useSupplyCommand, type SupplyRow } from './useSupply';
import Suppliers from './Suppliers';
import PurchaseSupplier, { type SupplierChoice } from './PurchaseSupplier';
const statuses = ['REQUESTED', 'UNDER_REVIEW', 'NEEDS_CLARIFICATION', 'ORDERED', 'READY_FOR_RECEIPT', 'RECEIVED', 'REJECTED', 'CANCELLED'];
const columns = [['code','purchaseReference'],['item_name','purchaseItem'],['quantity','quantity'],['unit','unit'],['requested_by_name','requestedBy'],['source_context','purchaseContext'],['created_at','requestDate'],['status','status'],['supplier_name','supplier']];
export default function Purchasing(props: FeatureProps & { mine?: boolean; stock?: boolean }) {
  const { snapshot:s, t, lang, can, mine = false, stock = false } = props;
  const [page,setPage] = useState(1), [filters,setFilters] = useState<Record<string,string|string[]>>({});
  const [filterColumn,setFilterColumn] = useState(''), [draft,setDraft] = useState<string|string[]>('');
  const [selected,setSelected] = useState(''), [create,setCreate] = useState(false), [directory,setDirectory] = useState(false);
  const [reason,setReason] = useState(''), [supplier,setSupplier] = useState<SupplierChoice>({id:'',name:''});
  const [reasonAction,setReasonAction]=useState(''),[reasonInvalid,setReasonInvalid]=useState(false);
  const explanation=useRef<HTMLTextAreaElement>(null);
  const read = useSupply(s,stock?'stock_purchases':mine?'mine':'purchases',{page:String(page),filters:JSON.stringify(filters),...(selected?{selected}:{})});
  const action = useSupplyCommand(props.command,s.factory?.id);
  const detail = read.data?.selected;
  const manage = !mine && !stock && can('purchasing','edit');
  const own = detail?.requested_by === s.user.id;
  const stamp = (v:unknown) => formatTime(v,lang,String(s.factory?.timezone || 'UTC'));
  async function change(next:string,choice:SupplierChoice=supplier) {
    if (!detail) return;
    if (await action.run('purchase_change',{id:detail.id,revision:detail.revision,action:next,reason:next==='supplier'?'':reason,...(next==='supplier'?(choice.id?{supplier_id:choice.id}:{supplier_text:choice.name.trim()}):{})})) { if(next!=='supplier'){setReason('');setReasonAction('');setReasonInvalid(false);} read.refresh(); }
  }
  const reasonKeys:Record<string,string>={REJECTED:'purchaseRejection',NEEDS_CLARIFICATION:'purchaseClarification',CANCELLED:'purchaseCancellation',clarify:'purchaseReply'};
  function selectReason(next:string){if(next!==reasonAction)setReason('');setReasonAction(next);setReasonInvalid(next!==reasonAction||!reason.trim());queueMicrotask(()=>explanation.current?.focus());}
  const unitLabel=(v:unknown)=>['kg','meter','piece'].includes(String(v))?t(String(v)):String(v||'—');
  const contextLabel=(v:unknown)=>['Production','Maintenance','Administration','Warehouse'].includes(String(v))?t(String(v).toLowerCase()):String(v||'—');
  const value = (row:SupplyRow,key:string) =>key==='unit'?unitLabel(row[key]):key==='source_context'?contextLabel(row[key]):key==='status'?t('purchaseStatus_'+String(row.status)):key==='created_at'?stamp(row[key]):key==='supplier_name'?String(row[key] || '—'):String(row[key]??'—');
  if (directory) return <><button onClick={()=>setDirectory(false)}>{t('back')}</button><Suppliers {...props}/></>;
  return <section className="panel supply-page" dir={lang==='ar'?'rtl':'ltr'}>
    <header className="section-head"><h2>{t(stock?'warehousePurchaseRequests':mine?'myPurchaseRequests':'purchasing')}</h2><div className="row-actions">
      {!stock&&can('purchasing','create')&&<button className="primary" onClick={()=>{setCreate(true);action.clearError();}}>{t('purchaseCreate')}</button>}
      {!stock&&!mine&&(can('suppliers','edit')||can('purchasing'))&&<button onClick={()=>setDirectory(true)}>{t('supplierDirectory')}</button>}
      <button onClick={read.refresh}>{t('refresh')}</button></div></header>
    {Object.keys(filters).length>0&&<button className="supply-clear" onClick={()=>{setFilters({});setPage(1);}}>{t('inventoryClearAll')}</button>}
    {(read.error||action.error)&&<p role="alert">{t(read.error||action.error)}</p>}
    {read.busy&&<p role="status">{t('loading')}</p>}
    {!read.busy&&!read.data?.rows.length&&<p className="empty">{t('purchaseEmpty')}</p>}
    <div className="table-wrap supply-table"><table><thead><tr>{columns.map(([key,title])=><th scope="col" key={key}>{t(title)}
      {['item_name','requested_by_name','source_context','status','code'].includes(key)&&<button className="inventory-filter-button" data-active={!!filters[key]} aria-label={t('inventoryFilterColumn')+': '+t(title)} onClick={()=>{setFilterColumn(key);setDraft(filters[key]??(key==='status'?[]:''));}}>⌄</button>}</th>)}<th>{t('inventoryActions')}</th></tr></thead>
      <tbody>{read.data?.rows.map(row=><tr key={String(row.id)}>{columns.map(([key])=><td key={key}>{value(row,key)}</td>)}<td><button onClick={()=>{setSelected(String(row.id));setReason('');setSupplier({id:String(row.supplier_id||''),name:String(row.supplier_name||'')});setReasonAction('');setReasonInvalid(false);action.clearError();}}>{t('open')}</button></td></tr>)}</tbody></table></div>
    <div className="supply-mobile-filter"><select aria-label={t('inventoryColumn')} value={filterColumn} onChange={e=>{setFilterColumn(e.target.value);setDraft(filters[e.target.value]??(e.target.value==='status'?[]:''));}}><option value="">{t('inventoryFilterColumn')}</option>{columns.filter(([key])=>['item_name','requested_by_name','source_context','status','code'].includes(key)).map(([key,title])=><option key={key} value={key}>{t(title)}</option>)}</select></div>
    <div className="supply-cards">{read.data?.rows.map(row=><article key={String(row.id)}>
      <strong>{String(row.item_name)}</strong><p><bdi>{String(row.code)}</bdi> · {t('purchaseStatus_'+String(row.status))}</p>
      <p>{String(row.quantity)} {unitLabel(row.unit)} · {String(row.requested_by_name)}</p><p>{contextLabel(row.source_context)} · {stamp(row.created_at)}</p>
      <button onClick={()=>{setSelected(String(row.id));setReason('');setSupplier({id:String(row.supplier_id||''),name:String(row.supplier_name||'')});setReasonAction('');setReasonInvalid(false);action.clearError();}}>{t('open')}</button></article>)}</div>
    <nav className="fulfillment-pagination"><button disabled={page===1||read.busy} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav>
    {filterColumn&&<Dialog title={t('inventoryFilterColumn')+': '+t(columns.find(([key])=>key===filterColumn)?.[1]||'')} t={t} onClose={()=>setFilterColumn('')}>
      {filterColumn==='status'?<fieldset className="inventory-options"><legend>{t('status')}</legend>{statuses.map(status=><label key={status}><input type="checkbox" checked={Array.isArray(draft)&&draft.includes(status)} onChange={e=>setDraft(old=>e.target.checked?[...(Array.isArray(old)?old:[]),status]:(Array.isArray(old)?old:[]).filter(x=>x!==status))}/>{t('purchaseStatus_'+status)}</label>)}</fieldset>:<Field label={t('inventoryContains')}><input value={typeof draft==='string'?draft:''} onChange={e=>setDraft(e.target.value)} maxLength={200}/></Field>}
      <div className="row-actions"><button onClick={()=>{setFilters(old=>{const next={...old};delete next[filterColumn];return next;});setPage(1);setFilterColumn('');}}>{t('inventoryClearFilter')}</button>
      <button className="primary" onClick={()=>{setFilters(old=>({...old,[filterColumn]:draft}));setPage(1);setFilterColumn('');}}>{t('inventoryApply')}</button></div></Dialog>}
    {create&&<Dialog title={t('purchaseCreate')} t={t} onClose={()=>{if(!action.busy)setCreate(false);}}>
      <form onSubmit={async e=>{e.preventDefault();const data=new FormData(e.currentTarget);const payload=Object.fromEntries(data);if(await action.run('purchase_manual',{...payload,quantity:Number(data.get('quantity'))})){setCreate(false);read.refresh();}}}><fieldset disabled={action.busy} className="form-grid">
        <Field label={t('purchaseItem')}><input name="item_name" required maxLength={200}/></Field>
        <Field label={t('quantity')}><input name="quantity" type="number" step="any" min="0.000001" required/></Field>
        <Field label={t('unit')}><input name="unit" required maxLength={50}/></Field>
        <Field label={t('purchaseContext')}><input name="source_context" list="purchase-contexts" required maxLength={120}/><datalist id="purchase-contexts">{['Production','Maintenance','Administration','Warehouse'].map(x=><option key={x} value={x}>{t(x.toLowerCase())}</option>)}</datalist></Field>
        <Field label={t('purchaseDetails')}><textarea name="details" required maxLength={4000}/></Field><Field label={t('notes')}><textarea name="notes" maxLength={4000}/></Field>
        {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary">{t('purchaseConfirm')}</button>
      </fieldset></form></Dialog>}
    {selected&&<Dialog title={String(detail?.code||t('purchaseReference'))} t={t} onClose={()=>{if(!action.busy)setSelected('');}}>
      {detail?<><h3>{String(detail.item_name)}</h3><p>{String(detail.quantity)} {unitLabel(detail.unit)} · {t('purchaseStatus_'+String(detail.status))}</p>
        <p>{String(detail.requested_by_name)} · {contextLabel(detail.source_context)} · {stamp(detail.created_at)}</p>
        {Boolean(detail.supplier_name)&&<p>{t('supplier')}: {String(detail.supplier_name)}</p>}
        <p className="supply-note">{String(detail.details)}</p>{Boolean(detail.notes)&&<p className="supply-note">{String(detail.notes)}</p>}
        {Boolean(detail.purchasing_note)&&<p className="supply-note">{String(detail.purchasing_note)}</p>}
        {Boolean(detail.received_at)&&<p>{t('purchaseStatus_RECEIVED')} · {stamp(detail.received_at)}</p>}
        {!['RECEIVED','REJECTED','CANCELLED'].includes(String(detail.status))&&<>
          {!manage&&<Field label={t('supplyReason')}><textarea value={reason} onChange={e=>setReason(e.target.value)} maxLength={4000}/></Field>}
          {manage&&['REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION'].includes(String(detail.status))&&<PurchaseSupplier {...props} key={selected} value={supplier} onChange={setSupplier} onSave={choice=>void change('supplier',choice)} busy={action.busy}/>}
          <div className="row-actions">
            {manage&&detail.status==='REQUESTED'&&<button disabled={action.busy} onClick={()=>void change('UNDER_REVIEW')}>{t('purchaseStatus_UNDER_REVIEW')}</button>}
            {manage&&detail.status==='UNDER_REVIEW'&&<button disabled={action.busy||!(detail.supplier_id||detail.supplier_text)} onClick={()=>void change('ORDERED')}>{t('purchaseStatus_ORDERED')}</button>}
            {manage&&detail.status==='ORDERED'&&<button disabled={action.busy} onClick={()=>void change('READY_FOR_RECEIPT')}>{t('purchaseStatus_READY_FOR_RECEIPT')}</button>}
            {manage&&['REQUESTED','UNDER_REVIEW'].includes(String(detail.status))&&['NEEDS_CLARIFICATION','REJECTED'].map(next=><button key={next} disabled={action.busy} aria-pressed={reasonAction===next} onClick={()=>selectReason(next)}>{t(next==='REJECTED'?'purchaseReject':'purchaseNeedsClarification')}</button>)}
            {manage&&<button disabled={action.busy} aria-pressed={reasonAction==='CANCELLED'} onClick={()=>selectReason('CANCELLED')}>{t('purchaseCancel')}</button>}
            {own&&detail.status==='NEEDS_CLARIFICATION'&&<button disabled={action.busy||(!manage&&!reason.trim())} onClick={()=>manage?selectReason('clarify'):void change('clarify')}>{t('purchaseClarify')}</button>}
            {own&&detail.status==='READY_FOR_RECEIPT'&&!detail.material_id&&!detail.product_id&&<button className="primary" disabled={action.busy} onClick={()=>void change('receive_direct')}>{t('purchaseConfirmReceipt')}</button>}
            {own&&['REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION'].includes(String(detail.status))&&!manage&&<button disabled={action.busy||!reason.trim()} onClick={()=>void change('cancel_own')}>{t('purchaseCancelRequest')}</button>}
            {detail.status==='READY_FOR_RECEIPT'&&Boolean(detail.material_id||detail.product_id)&&can('warehouse','edit')&&<button className="primary" disabled={action.busy} onClick={async()=>{if(await action.run('receive_purchase',{id:detail.id,revision:detail.revision,reason})){read.refresh();}}}>{t('purchaseReceiveStock')}</button>}
          </div>
          {manage&&reasonAction&&<form className="purchase-explanation" onSubmit={async e=>{e.preventDefault();if(!reason.trim()){setReasonInvalid(true);explanation.current?.focus();return;}await change(reasonAction);}}>
            <Field label={t(reasonKeys[reasonAction]+'Label')}><textarea ref={explanation} required value={reason} placeholder={t(reasonKeys[reasonAction]+'Placeholder')} aria-invalid={reasonInvalid} aria-describedby={reasonInvalid?'purchase-explanation-error':undefined} onInvalid={()=>{setReasonInvalid(true);explanation.current?.focus();}} onChange={e=>{setReason(e.target.value);setReasonInvalid(false);}} maxLength={4000}/></Field>
            {reasonInvalid&&<p id="purchase-explanation-error" role="alert">{t(reasonKeys[reasonAction]+'Required')}</p>}
            <div className="row-actions"><button className="primary" disabled={action.busy}>{t(reasonKeys[reasonAction]+'Confirm')}</button><button type="button" disabled={action.busy} onClick={()=>{setReasonAction('');setReason('');setReasonInvalid(false);}}>{t('close')}</button></div>
          </form>}</>}
        {action.error&&<p role="alert">{t(action.error)}</p>}
        <details><summary>{t('supplyHistory')}</summary><ol>{((detail.history||[]) as SupplyRow[]).map(event=><li key={String(event.id)}>{t('purchaseStatus_'+String(event.status))} · {String(event.actor_name)} · {stamp(event.created_at)}{Boolean(event.note)&&<p className="supply-note">{String(event.note)}</p>}</li>)}</ol></details>
      </>:<p role="status">{t(read.busy?'loading':read.error||'noResults')}</p>}
    </Dialog>}
  </section>;
}
