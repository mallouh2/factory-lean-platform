import { useEffect, useRef, useState, type ReactNode } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field, formatTime, localName } from '@/components/ui';
import type { InventoryRow } from './WarehouseInventory';
import TableExport from '@/components/TableExport';
export type MaterialStock = { id: string; name: string; name_ar: string; code: string; unit: string; inventory_kind: string; on_hand: number; reserved: number };
type Movement = { id: string; kind: string; quantity: number; reserved_delta?: number; unit: string | null; note: string; reference: string; created_by: string; actor_name: string | null; created_at: string };
export default function WarehouseReceiving({ snapshot: s, can, command, t, lang, materials = [], refresh, children, showMaterials=true, receiveRow, compactActions=false, settingsAction, purchaseAction }: FeatureProps & { materials: MaterialStock[]; refresh: () => void; children?: ReactNode; showMaterials?:boolean; receiveRow?:InventoryRow|null; compactActions?:boolean; settingsAction?:ReactNode; purchaseAction?:ReactNode }) {
  const [dialog, setDialog] = useState(''), [type, setType] = useState('finished'), [item, setItem] = useState('');
  const [source, setSource] = useState('external_receipt'), [quantity, setQuantity] = useState(''), [reference, setReference] = useState(''), [note, setNote] = useState('');
  const [name, setName] = useState(''), [nameAr, setNameAr] = useState(''), [code, setCode] = useState(''), [unit, setUnit] = useState('kg'), [kind, setKind] = useState('RAW_MATERIAL');
  const [busy, setBusy] = useState(false), [notice, setNotice] = useState(''), [page, setPage] = useState(1);
  const [history, setHistory] = useState<{ rows: Movement[]; total: number } | null>(null);
  const retry = useRef<{ key: string; id: string } | null>(null);
  const products = s.tables.products.filter(row => row.stage === 'finished' && row.stock_unit);
  if(receiveRow?.entity==='finished'&&!products.some(p=>p.id===receiveRow.id)) products.push({id:receiveRow.id,name:receiveRow.name,name_ar:receiveRow.name_ar,code:receiveRow.code,stock_unit:receiveRow.unit,stage:'finished'});
  const materialOptions = receiveRow?.entity==='material'&&!materials.some(m=>m.id===receiveRow.id)?[...materials,{id:receiveRow.id,name:receiveRow.name,name_ar:receiveRow.name_ar,code:receiveRow.code,inventory_kind:receiveRow.item_type,unit:receiveRow.unit||'',on_hand:receiveRow.on_hand??0,reserved:receiveRow.reserved??0}]:materials;
  const selected = (type === 'finished' ? products : materialOptions).find(row => String(row.id) === item);
  const selectedUnit = String(type === 'finished' ? (selected && 'stock_unit' in selected ? selected.stock_unit : '') || '' : selected?.unit || '');
  useEffect(()=>{if(!receiveRow||!can('warehouse','edit'))return;setDialog('receive');setType(receiveRow.entity);setItem(receiveRow.id);setSource('external_receipt');setQuantity('');setReference('');setNote('');setNotice('');},[receiveRow]);
  useEffect(() => {
    if (dialog !== 'history' || !item) return;
    const abort = new AbortController(); setHistory(null); setNotice('');
    fetch('/api/fulfillment?' + new URLSearchParams({ factory: String(s.factory?.id), mode: 'movements', item, item_type: type, page: String(page) }), { cache: 'no-store', signal: abort.signal })
      .then(async response => { const data = await response.json(); if (!response.ok) throw Error(data.error || 'dataWarning'); return data; })
      .then(data => { if (!abort.signal.aborted) setHistory(data); }).catch(error => { if (!abort.signal.aborted) setNotice(error.message); });
    return () => abort.abort();
  }, [dialog, item, type, page, s.factory?.id]);
  async function submit() {
    const args = dialog === 'material' ? { payload: { name: name.trim(), name_ar: nameAr.trim(), code: code.trim(), unit, inventory_kind: kind } }
      : { item, item_type: type, unit: selectedUnit, quantity: Number(quantity), source, reference: reference.trim(), note: note.trim() };
    const key = JSON.stringify(args); if (retry.current?.key !== key) retry.current = { key, id: crypto.randomUUID() };
    setBusy(true); setNotice('');
    try { await command(dialog === 'material' ? 'create_warehouse_material' : 'receive_warehouse_stock', { factory: s.factory?.id, ...args, request_id: retry.current.id });
      retry.current = null; setDialog(''); refresh(); setNotice('saved');
    } catch (error) { setNotice(error instanceof Error ? error.message : 'error'); } finally { setBusy(false); }
  }
  const show = (action: string) => { setDialog(action); setItem(''); setQuantity(''); setReference(''); setNote(''); setNotice(''); setSource('external_receipt'); setPage(1); };
  return <>
    <div className="fulfillment-tools warehouse-top-actions">{settingsAction}{can('warehouse', 'edit') && <><button className="primary" onClick={() => show('receive')}>{t('receiveStock')}</button>
      {!compactActions&&<button onClick={() => { show('receive'); setSource('opening_balance'); }}>{t('openingStock')}</button>}
      <button onClick={() => { show('material'); setName(''); setNameAr(''); setCode(''); }}>{t('addMaterial')}</button></>}
      <button onClick={() => show('history')}>{t(compactActions?'warehouseInventoryMovements':'stockMovements')}</button>{purchaseAction}</div>
    {notice && !dialog && <p role="status">{t(notice)}</p>}
    {children}
    {showMaterials&&<><h2>{t('materialInventory')}</h2>
    {!materials.length && <p className="empty">{t('materialsEmpty')}</p>}
    <div className="finished-stock-list">{materials.map(row => <article className="finished-stock-row" key={row.id}>
      <strong>{localName(row, lang)} · <bdi>{row.code}</bdi></strong><span> · {t(row.inventory_kind)} · {t('supply_EXTERNAL')} · {t(row.unit)}</span>
      <dl>{[ ['on_hand', row.on_hand], ['reserved', row.reserved], ['available', Number(row.on_hand) - Number(row.reserved)] ].map(([key, value]) =>
        <div key={key}><dt>{t(`stock_${key}`)}</dt><dd>{Number(value).toLocaleString(lang)}</dd></div>)}</dl>
    </article>)}</div></>}
    {dialog && <Dialog title={t(dialog === 'material' ? 'addMaterial' : dialog === 'history' ? 'stockMovements' : source === 'opening_balance' ? 'openingStock' : 'receiveStock')} t={t} onClose={() => { if (!busy) setDialog(''); }}>
      <form onSubmit={event => { event.preventDefault(); if (dialog !== 'history') void submit(); }}><fieldset className="fulfillment-form" disabled={busy}>
        {dialog === 'material' ? <>
          <Field label={t('name')}><input required maxLength={200} value={name} onChange={event => setName(event.target.value)} /></Field>
          <Field label={t('name_ar')}><input maxLength={200} value={nameAr} onChange={event => setNameAr(event.target.value)} /></Field>
          <Field label={t('code')}><input required maxLength={100} value={code} onChange={event => setCode(event.target.value)} /></Field>
          <Field label={t('inventoryType')}><select value={kind} onChange={event => setKind(event.target.value)}>{['RAW_MATERIAL','ACCESSORY','PACKAGING'].map(value => <option key={value} value={value}>{t(value)}</option>)}</select></Field>
          <Field label={t('unit')}><select value={unit} onChange={event => setUnit(event.target.value)}>{['kg','meter','piece'].map(value => <option key={value} value={value}>{t(value)}</option>)}</select></Field>
        </> : <>
          <Field label={t('inventoryType')}><select value={type} onChange={event => { setType(event.target.value); setItem(''); setPage(1); }}><option value="finished">{t('finishedProducts')}</option><option value="material">{t('materialInventory')}</option></select></Field>
          <Field label={t('item')}><select required value={item} onChange={event => { setItem(event.target.value); setPage(1); }}><option value="">{t('select')}</option>{(type === 'finished' ? products : materialOptions).map(row => <option key={String(row.id)} value={String(row.id)}>{localName(row, lang)}</option>)}</select></Field>
          {dialog === 'receive' && <>{compactActions&&<Field label={t('warehouseReceiptSource')}><select value={source} onChange={e=>setSource(e.target.value)}><option value="external_receipt">{t('receiveStock')}</option><option value="opening_balance">{t('openingStock')}</option></select></Field>}<p>{t(source === 'opening_balance' ? 'openingStockHelp' : 'externalReceiptHelp')}</p>
            <Field label={t('quantity')}><input required type="number" min="0.000001" step="any" value={quantity} onChange={event => setQuantity(event.target.value)} /></Field><p>{t('unit')}: {t(selectedUnit) || '—'}</p>
            <Field label={t('externalReference')}><input maxLength={200} value={reference} onChange={event => setReference(event.target.value)} /></Field>
            <Field label={t('notes')}><textarea maxLength={2000} value={note} onChange={event => setNote(event.target.value)} /></Field>
            <p className="muted">{t('receiptTimeActorHelp')}</p></>}
        </>}
        {notice && <p role="alert">{t(notice)}</p>}{dialog !== 'history' && <button className="primary" disabled={dialog === 'receive' && !selectedUnit}>{t('save')}</button>}
      </fieldset></form>
      {dialog === 'history' && item && <>{can('warehouse')&&<TableExport factory={String(s.factory?.id||'')} dataset="warehouse-movements" filters={{item,item_type:type}} total={history?.total??0} language={lang} t={t} disabled={!history||!!notice}/>}{!history && !notice && <p role="status">{t('loading')}</p>}<div className="fulfillment-orders">{history?.rows.map(row => <article className="fulfillment-order" key={row.id}>
        <strong>{t(`movement_${row.kind}`)}</strong><p>{t('stockMovementDelta')}: {Number(row.quantity).toLocaleString(lang)} {row.unit ? t(row.unit) : t('historicalUnitUnknown')}</p>
        {Number(row.reserved_delta) !== 0 && row.reserved_delta != null && <p>{t('reservedMovementDelta')}: {Number(row.reserved_delta).toLocaleString(lang)} {row.unit ? t(row.unit) : t('historicalUnitUnknown')}</p>}
        <p>{formatTime(row.created_at, lang, String(s.factory?.timezone || 'UTC'))}</p><p>{t('receivingActor')}: <bdi>{row.actor_name || row.created_by || t('notSpecified')}</bdi></p>
        {row.reference && <p dir="auto">{row.reference}</p>}{row.note && <p dir="auto">{row.note}</p>}
      </article>)}</div>{history && !history.rows.length && <p>{t('noData')}</p>}
        <nav className="fulfillment-pagination"><button disabled={page === 1} onClick={() => setPage(value => value - 1)}>{t('previous')}</button><span>{page}</span><button disabled={!history || page * 25 >= history.total} onClick={() => setPage(value => value + 1)}>{t('next')}</button></nav></>}
    </Dialog>}
  </>;
}
