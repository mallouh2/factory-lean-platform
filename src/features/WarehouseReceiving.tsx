import { useEffect, useId, useRef, useState, type ReactNode } from 'react';
import type { FeatureProps } from './types';
import { Field, localName } from '@/components/ui';
import type { InventoryRow } from './WarehouseInventory';
import {WarehouseDialog as Dialog,WarehousePicker} from './WarehouseUi';
import WarehouseMovements from './WarehouseMovements';
import {useWarehouses,WarehouseSelector} from './WarehouseDefinitions';
export type MaterialStock = { id: string; name: string; name_ar: string; code: string; unit: string; inventory_kind: string; on_hand: number; reserved: number };
export default function WarehouseReceiving(props: FeatureProps & { materials: MaterialStock[]; refresh: () => void; children?: ReactNode; showMaterials?:boolean; receiveRow?:InventoryRow|null; compactActions?:boolean; settingsAction?:ReactNode;administrationAction?:ReactNode }) {
  const { snapshot: s, can, command, t, lang, materials = [], refresh, children, showMaterials=true, receiveRow, compactActions=false, settingsAction,administrationAction }=props;
  const warehouses=useWarehouses(props),[warehouseDraft,setWarehouse]=useState<string|null>(null);
  const managementId=useId();
  const [dialog, setDialog] = useState(''), [type, setType] = useState('finished'), [item, setItem] = useState('');
  const [source, setSource] = useState('external_receipt'), [quantity, setQuantity] = useState(''), [reference, setReference] = useState(''), [note, setNote] = useState('');
  const [name, setName] = useState(''), [nameAr, setNameAr] = useState(''), [code, setCode] = useState(''), [unit, setUnit] = useState('kg'), [kind, setKind] = useState('RAW_MATERIAL');
  const [busy, setBusy] = useState(false), [notice, setNotice] = useState('');
  const retry = useRef<{ key: string; id: string } | null>(null);
  const products = s.tables.products.filter(row => row.stage === 'finished' && row.stock_unit);
  if(receiveRow?.entity==='finished'&&!products.some(p=>p.id===receiveRow.id)) products.push({id:receiveRow.id,name:receiveRow.name,name_ar:receiveRow.name_ar,code:receiveRow.code,stock_unit:receiveRow.unit,stage:'finished'});
  const materialOptions = receiveRow?.entity==='material'&&!materials.some(m=>m.id===receiveRow.id)?[...materials,{id:receiveRow.id,name:receiveRow.name,name_ar:receiveRow.name_ar,code:receiveRow.code,inventory_kind:receiveRow.item_type,unit:receiveRow.unit||'',on_hand:receiveRow.on_hand??0,reserved:receiveRow.reserved??0}]:materials;
  const selected = (type === 'finished' ? products : materialOptions).find(row => String(row.id) === item);
  const selectedUnit = String(type === 'finished' ? (selected && 'stock_unit' in selected ? selected.stock_unit : '') || '' : selected?.unit || '');
  const warehouseClass=type==='finished'?'FINISHED':selected&&'inventory_kind' in selected&&selected.inventory_kind==='SEMI_FINISHED'?'SEMI_FINISHED':'RAW';
  const eligibleWarehouses=warehouses.rows.filter(w=>w.active&&w.storage_class===warehouseClass),warehouse=warehouseDraft??eligibleWarehouses[0]?.id??'',initialWarehouse=eligibleWarehouses[0]?.id;
  useEffect(()=>{setWarehouse(null);},[warehouseClass,receiveRow]);
  useEffect(()=>{if(warehouseDraft===null&&initialWarehouse)setWarehouse(initialWarehouse);},[initialWarehouse,warehouseDraft]);
  useEffect(()=>{if(!receiveRow||!can('warehouse','edit'))return;setDialog('receive');setType(receiveRow.entity);setItem(receiveRow.id);setSource('external_receipt');setQuantity('');setReference('');setNote('');setNotice('');},[receiveRow]);
  async function submit() {
    const args = dialog === 'material' ? { payload: { name: name.trim(), name_ar: nameAr.trim(), code: code.trim(), unit, inventory_kind: kind } }
      : { item, item_type: type, unit: selectedUnit, quantity: Number(quantity), source, reference: reference.trim(), note: note.trim(),warehouse_id:warehouse };
    const key = JSON.stringify(args); if (retry.current?.key !== key) retry.current = { key, id: crypto.randomUUID() };
    setBusy(true); setNotice('');
    try { if(dialog==='material')await command('create_warehouse_material', { factory: s.factory?.id, ...args, request_id: retry.current.id });
      else {const r=await fetch('/api/warehouses',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({factory:s.factory?.id,operation:'RECEIVE_STOCK',payload:args,request_id:retry.current.id})}),d=await r.json();if(!r.ok)throw Error(d.error?.startsWith('warehouse_')?'dataWarning':d.error||'error');}
      retry.current = null; setDialog(''); refresh(); setNotice('saved');
    } catch (error) { setNotice(error instanceof Error ? error.message : 'error'); } finally { setBusy(false); }
  }
  const show = (action: string) => { setDialog(action); setItem(''); setQuantity(''); setReference(''); setNote(''); setNotice(''); setSource('external_receipt'); };
  return <>
    {compactActions?<header className="warehouse-inventory-heading warehouse-top-actions">
      <h2>{t('warehouseInventoryTitle')}</h2>
      <div className="warehouse-inventory-tools" role="group" aria-label={t('warehouseInventoryTitle')}>
        {can('warehouse','edit')&&<button type="button" className="primary" onClick={()=>show('receive')}>{t('receiveStock')}</button>}
        <button type="button" popoverTarget={managementId}>{t('whManagementRecords')} ▾</button>
        <div id={managementId} popover="auto" className="warehouse-popover warehouse-management-menu" onClick={event=>{if((event.target as HTMLElement).closest('button'))event.currentTarget.hidePopover();}}>
          <button type="button" onClick={()=>show('history')}><strong>{t('stockMovements')}</strong><small>{t('whMovementDescription')}</small></button>
          {can('warehouse','edit')&&<button type="button" onClick={()=>show('manage')}><strong>{t('whItemStockSettings')}</strong><small>{t('whSettingsDescription')}</small></button>}
          {administrationAction}
        </div>
      </div>
    </header>:<div className="fulfillment-tools warehouse-top-actions">{settingsAction}{can('warehouse','edit')&&<>
      <button className="primary" onClick={()=>show('receive')}>{t('receiveStock')}</button>
      <button onClick={()=>{show('receive');setSource('opening_balance');}}>{t('openingStock')}</button>
      <button onClick={()=>{show('material');setName('');setNameAr('');setCode('');}}>{t('addMaterial')}</button></>}
      <button onClick={()=>show('history')}>{t('stockMovements')}</button></div>}
    {notice && !dialog && <p role="status">{t(notice)}</p>}
    {children}
    {showMaterials&&<><h2>{t('materialInventory')}</h2>
    {!materials.length && <p className="empty">{t('materialsEmpty')}</p>}
    <div className="finished-stock-list">{materials.map(row => <article className="finished-stock-row" key={row.id}>
      <strong>{localName(row, lang)} · <bdi>{row.code}</bdi></strong><span> · {t(row.inventory_kind)} · {t('supply_EXTERNAL')} · {t(row.unit)}</span>
      <dl>{[ ['on_hand', row.on_hand], ['reserved', row.reserved], ['available', Number(row.on_hand) - Number(row.reserved)] ].map(([key, value]) =>
        <div key={key}><dt>{t(`stock_${key}`)}</dt><dd>{Number(value).toLocaleString(lang)}</dd></div>)}</dl>
    </article>)}</div></>}
    {dialog==='history'&&<WarehouseMovements {...props} materials={materialOptions} onClose={()=>setDialog('')}/>}
    {dialog==='manage'&&<Dialog {...props} title={t('whItemStockSettings')} onClose={()=>setDialog('')}><div className="warehouse-management-choices"><button onClick={()=>{show('material');setName('');setNameAr('');setCode('');}}>{t('addMaterial')}</button><div onClick={e=>{if((e.target as HTMLElement).closest('button'))setDialog('');}}>{settingsAction}</div><p className="muted">{t('whSettingsDescription')}</p></div></Dialog>}
    {dialog && !['history','manage'].includes(dialog) && <Dialog {...props} title={t(dialog === 'material' ? 'addMaterial' : dialog === 'history' ? 'stockMovements' : source === 'opening_balance' ? 'openingStock' : 'receiveStock')} t={t} onClose={() => { if (!busy) setDialog(''); }}>
      <form onSubmit={event => { event.preventDefault(); if (dialog !== 'history') void submit(); }}><fieldset className="fulfillment-form" disabled={busy}>
        {dialog === 'material' ? <>
          <Field label={t('name')}><input required maxLength={200} value={name} onChange={event => setName(event.target.value)} /></Field>
          <Field label={t('name_ar')}><input maxLength={200} value={nameAr} onChange={event => setNameAr(event.target.value)} /></Field>
          <Field label={t('code')}><input required maxLength={100} value={code} onChange={event => setCode(event.target.value)} /></Field>
          <Field label={t('inventoryType')}><select value={kind} onChange={event => setKind(event.target.value)}>{['RAW_MATERIAL','ACCESSORY','PACKAGING'].map(value => <option key={value} value={value}>{t(value)}</option>)}</select></Field>
          <Field label={t('unit')}><select value={unit} onChange={event => setUnit(event.target.value)}>{['kg','meter','piece'].map(value => <option key={value} value={value}>{t(value)}</option>)}</select></Field>
        </> : <>
          <Field label={t('inventoryType')}><select value={type} onChange={event => { setType(event.target.value); setItem(''); }}><option value="finished">{t('finishedProducts')}</option><option value="material">{t('materialInventory')}</option></select></Field>
          <WarehousePicker label={t('item')} required value={item} placeholder={t('select')} options={(type==='finished'?products:materialOptions).map(row=>({id:String(row.id),name:localName(row,lang)}))} onChange={id=>{setItem(id);}}/>
          {dialog === 'receive' && <>{compactActions&&<Field label={t('warehouseReceiptSource')}><select value={source} onChange={e=>setSource(e.target.value)}><option value="external_receipt">{t('receiveStock')}</option><option value="opening_balance">{t('openingStock')}</option></select></Field>}<p>{t(source === 'opening_balance' ? 'openingStockHelp' : 'externalReceiptHelp')}</p>
            <Field label={t('quantity')}><input required type="number" min="0.000001" step="any" value={quantity} onChange={event => setQuantity(event.target.value)} /></Field><p>{t('unit')}: {t(selectedUnit) || '—'}</p>
            <WarehouseSelector rows={warehouses.rows} value={warehouse} onChange={setWarehouse} storageClass={warehouseClass} lang={lang}/>
            <details><summary>{t('wvOptional')}</summary><Field label={t('externalReference')}><input maxLength={200} value={reference} onChange={event => setReference(event.target.value)} /></Field>
            <Field label={t('notes')}><textarea maxLength={2000} value={note} onChange={event => setNote(event.target.value)} /></Field>
            </details><p className="muted">{t('receiptTimeActorHelp')}</p></>}
        </>}
        {notice && <p role="alert">{t(notice)}</p>}{dialog !== 'history' && <button className="primary" disabled={dialog === 'receive' && (!selectedUnit||!warehouses.ready||!eligibleWarehouses.some(w=>w.id===warehouse))}>{t('save')}</button>}
      </fieldset></form>

    </Dialog>}
  </>;
}
