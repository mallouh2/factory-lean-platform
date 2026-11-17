import MaterialDeviationPolicy from './MaterialDeviationPolicy';
import PlanningChangeUpdates from './PlanningChangeUpdates';
import StoredUnfinishedInventory from './StoredUnfinishedInventory';
import WarehouseRequests from './WarehouseRequests';
import { useEffect, useId, useRef, useState } from 'react';
import type { FeatureProps } from './types';
import { Field, localName } from '@/components/ui';
import {WarehouseDialog as Dialog,WarehousePicker} from './WarehouseUi';
import './warehouse-v1.css';
import WarehouseDefinitions from './WarehouseDefinitions';
import ProductIdentity from '@/components/ProductIdentity';
import WarehouseReceiving, { type MaterialStock } from './WarehouseReceiving';
import WarehouseInventory, { type InventoryRow } from './WarehouseInventory';
import { useFulfillment, type SalesLine, type SalesOrder, type StockRow } from './useFulfillment';
import { SourceAllocationFields,type SourcePick } from './SourceStock';
import { decimalCompare,decimalSubtract,quantityValid } from '@/utils/quality-quantities.mjs';
export default function Warehouse(props: FeatureProps & {initialWorkspace?:'inventory'|'requests'}) {
  const {snapshot:s,t,lang,command,can}=props;
  const [workspace,setWorkspace]=useState<'inventory'|'requests'>(props.initialWorkspace||'inventory');
  const [page, setPage] = useState(1);
  const read = useFulfillment<{ rows: StockRow[]; total: number; orders: SalesOrder[]; orders_total: number; materials: MaterialStock[]; materials_total: number }>(s, 'warehouse', page, can('warehouse')&&workspace==='inventory');
  const [dialog, setDialog] = useState(''), [product, setProduct] = useState(''), [unit, setUnit] = useState('');
  const [mode, setMode] = useState('MAKE_TO_ORDER'), [minimum, setMinimum] = useState(''), [maximum, setMaximum] = useState('');
  const [source, setSource] = useState('MANUFACTURED');
  const [quantity, setQuantity] = useState(''), [reason, setReason] = useState(''), [busy, setBusy] = useState(false), [notice, setNotice] = useState('');
  const [dispatch, setDispatch] = useState<{ order: SalesOrder; line?: SalesLine } | null>(null);
  const [dispatchQuantity,setDispatchQuantity]=useState<string|null>(null);
  const pool=useFulfillment<{rows:{id:string;ordered:string;reserved:string;dispatched:string;outstanding:string;dispatchable:string;source_assigned:string}[]}>(s,'pool',1,!!dispatch,{order:dispatch?.order.id||''});
  const poolLine=pool.data?.rows.find(line=>line.id===dispatch?.line?.id),dispatchAmount=dispatchQuantity??poolLine?.dispatchable??'';
  const [adjustPicks,setAdjustPicks]=useState<SourcePick[]>([]),[adjustValid,setAdjustValid]=useState(false);
  const retry = useRef<{ key: string; id: string } | null>(null);
  const [revision, setRevision] = useState(0), [receiveRow,setReceiveRow] = useState<InventoryRow|null>(null);
  const [configuredRow,setConfiguredRow] = useState<InventoryRow|null>(null);
  const [inventoryType,setInventoryType]=useState('');
  const [requestsVisited,setRequestsVisited]=useState(props.initialWorkspace==='requests');
  useEffect(()=>{if(workspace==='requests')setRequestsVisited(true);},[workspace]);
  const operationsId = useId();
  useEffect(()=>{if(props.initialWorkspace)setWorkspace(props.initialWorkspace);},[props.initialWorkspace]);
  function workspaceKey(event:React.KeyboardEvent<HTMLButtonElement>){if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key))return;event.preventDefault();const next=event.key==='Home'?'inventory':event.key==='End'?'requests':workspace==='inventory'?'requests':'inventory';setWorkspace(next);event.currentTarget.parentElement?.querySelectorAll<HTMLButtonElement>('[role=tab]')[next==='inventory'?0:1]?.focus();}
  const refresh = () => { read.refresh(); setRevision(v=>v+1); };
  const configure = (row:InventoryRow) => {
    const catalogue = s.tables.products.find(product=>product.id===row.id);
    setConfiguredRow(row); setProduct(row.id); setUnit(String(catalogue?.stock_unit || row.unit || '')); setSource(String(catalogue?.supply_source || row.supply_source));
    setMode(String(catalogue?.supply_mode || (row.minimum_stock==null?'MAKE_TO_ORDER':'MAKE_TO_STOCK')));
    setMinimum(String(catalogue?.minimum_stock??row.minimum_stock??'')); setMaximum(String(catalogue?.maximum_stock??row.maximum_stock??''));setNotice('');setDialog('configure');
  };
  async function run(name: string, args: Record<string, unknown>) {
    if(busy)return;
    const key = JSON.stringify([name, args]);
    if (retry.current?.key !== key) retry.current = { key, id: crypto.randomUUID() };
    setBusy(true); setNotice('');
    try {
      await command(name, { factory: s.factory?.id, ...args, ...(name === 'configure_warehouse_product' ? {} : { request_id: retry.current.id }) });
      retry.current = null; refresh(); setDialog(''); setDispatch(null); setNotice('saved');
    } catch (cause) { setNotice(cause instanceof Error ? cause.message : 'error'); } finally { setBusy(false); }
  }
  return <section className="fulfillment-page warehouse-v1" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    {can('warehouse','view')&&<PlanningChangeUpdates props={props} audience="WAREHOUSE"/>}{((workspace==='inventory'&&read.error)||notice)&&<p role="alert">{t((workspace==='inventory'&&read.error)||notice)}</p>}
    <><div className="warehouse-operation-tabs" role="tablist" aria-label={t('warehouse')}><button role="tab" id={operationsId+'-inventory-tab'} aria-controls={operationsId+'-inventory'} tabIndex={workspace==='inventory'?0:-1} onKeyDown={workspaceKey} aria-selected={workspace==='inventory'} onClick={()=>setWorkspace('inventory')}>{lang==='ar'?'المخزون':'Inventory'}</button><button role="tab" id={operationsId+'-requests-tab'} aria-controls={operationsId+'-requests'} tabIndex={workspace==='requests'?0:-1} onKeyDown={workspaceKey} aria-selected={workspace==='requests'} onClick={()=>setWorkspace('requests')}>{lang==='ar'?'طلبات المستودع':'Warehouse Requests'}</button></div>
      {workspace==='inventory'&&<div role="tabpanel" id={operationsId+'-inventory'} aria-labelledby={operationsId+'-inventory-tab'}>
      {read.loading && <p role="status">{t('loading')}</p>}

      <WarehouseReceiving onLanguageChange={props.onLanguageChange} snapshot={s} t={t} lang={lang} command={command} can={can} materials={read.data?.materials || []} refresh={refresh} showMaterials={false} receiveRow={receiveRow} compactActions
       administrationAction={can('settings','edit')&&<button type="button" onClick={()=>setDialog('warehouses')}><strong>{lang==='ar'?'إدارة المستودعات':'Manage Warehouses'}</strong><small>{lang==='ar'?'تعريف المستودعات وأنواع التخزين':'Warehouse definitions and storage categories'}</small></button>}
       settingsAction={can('warehouse','edit')&&<button onClick={()=>{setDialog('configure');setNotice('');}}>{t('warehouseStockSettings')}</button>}>
      {inventoryType==='wip'?<><label className="warehouse-type-filter">{lang==='ar'?'نوع المخزون':'Inventory type'}<select value={inventoryType} onChange={e=>setInventoryType(e.target.value)}><option value="">{t('all')}</option><option value="RAW_MATERIAL,ACCESSORY,PACKAGING">{lang==='ar'?'مواد خام وملحقات':'Raw Materials & Supplies'}</option><option value="FINISHED_GOOD,MANUFACTURED_INTERMEDIATE">{lang==='ar'?'منتجات مكتملة':'Finished Goods'}</option><option value="wip">{lang==='ar'?'إنتاج غير مكتمل مخزن':'Stored Unfinished / WIP'}</option></select></label><StoredUnfinishedInventory {...props}/></>:<WarehouseInventory inventoryFilter={<label className="warehouse-type-filter">{lang==='ar'?'نوع المخزون':'Inventory type'}<select value={inventoryType} onChange={e=>setInventoryType(e.target.value)}><option value="">{t('all')}</option><option value="RAW_MATERIAL,ACCESSORY,PACKAGING">{lang==='ar'?'مواد خام وملحقات':'Raw Materials & Supplies'}</option><option value="FINISHED_GOOD,MANUFACTURED_INTERMEDIATE">{lang==='ar'?'منتجات مكتملة':'Finished Goods'}</option><option value="wip">{lang==='ar'?'إنتاج غير مكتمل مخزن':'Stored Unfinished / WIP'}</option></select></label>} onStoredUnfinished={()=>setInventoryType('wip')} inventoryType={inventoryType} onLanguageChange={props.onLanguageChange} onOutputRelated={props.onOutputRelated} snapshot={s} t={t} lang={lang} command={command} can={can} revision={revision} onChanged={refresh} onConfigure={configure} onReceive={row=>setReceiveRow({...row})}/>}
      </WarehouseReceiving>
      </div>}
      {(requestsVisited||workspace==='requests')&&<div hidden={workspace!=='requests'} role="tabpanel" id={operationsId+'-requests'} aria-labelledby={operationsId+'-requests-tab'}><WarehouseRequests {...props} active={workspace==='requests'} orders={read.data?.orders||[]} onDispatch={(order,line)=>{setDispatchQuantity(null);setDispatch({order,line});}} onChanged={refresh}/></div>}
    </>
    {dispatch && <Dialog {...props} busy={busy} title={t('confirmDispatch')} t={t} onClose={() => { if (!busy) setDispatch(null); }}>
      <p>{t('dispatchConfirm')}</p><strong><bdi dir="ltr">{dispatch.order.code}</bdi> · {dispatch.order.customer_reference}</strong>
      {dispatch.line&&<div><p><ProductIdentity productId={dispatch.line.product_id}>{lang==='ar'?dispatch.line.product_name_ar||dispatch.line.product_name:dispatch.line.product_name}</ProductIdentity> · {t(dispatch.line.unit)}</p>
       {pool.busy&&<p role="status">{t('loading')}</p>}{pool.error&&<p role="alert">{t(pool.error)}</p>}
       {poolLine&&<><dl className="quality-context"><div><dt>{t('quantity')}</dt><dd>{poolLine.ordered}</dd></div><div><dt>{t('stockReserved')}</dt><dd>{poolLine.reserved}</dd></div><div><dt>{t('stockDispatched')}</dt><dd>{poolLine.dispatched}</dd></div><div><dt>{lang==='ar'?'المتاح للإرسال الآن':'Dispatchable now'}</dt><dd>{poolLine.dispatchable}</dd></div><div><dt>{lang==='ar'?'المتبقي للعميل':'Outstanding for customer'}</dt><dd>{poolLine.outstanding}</dd></div></dl>
       <Field label={(lang==='ar'?'كمية الإرسال':'Dispatch quantity')+' · '+t(dispatch.line.unit)}><input inputMode="decimal" value={dispatchAmount} onChange={e=>setDispatchQuantity(e.target.value)}/></Field>
       <p>{lang==='ar'?'المتبقي بعد الإرسال':'Remaining after dispatch'}: {quantityValid(dispatchAmount,dispatch.line.unit,poolLine.dispatchable)?decimalSubtract(poolLine.outstanding,dispatchAmount):'—'} {t(dispatch.line.unit)}</p>
       {decimalCompare(poolLine.dispatchable,'0')!==1&&<p role="status">{lang==='ar'?'بعض المخزون محفوظ بشكل منفصل أو موقوف من الجودة. راجع تفاصيل المخزون قبل الإرسال.':'Some stock is kept separately or held by Quality. Review stock details before dispatch.'}</p>}</>}
      </div>}
      {notice && notice !== 'saved' && <p role="alert">{t(notice)}</p>}
      <div className="row-actions"><button disabled={busy} onClick={() => setDispatch(null)}>{t('cancel')}</button>
        <button className="primary" disabled={busy||pool.busy||!!pool.error||!poolLine||!dispatch.line||!quantityValid(dispatchAmount,dispatch.line.unit,poolLine.dispatchable)} onClick={()=>dispatch.line&&void run('dispatch_sales_quantity',{sales_order:dispatch.order.id,line:dispatch.line.id,quantity:dispatchAmount})}>{t('confirmDispatch')}</button></div>
    </Dialog>}
    {dialog==='warehouses'&&<Dialog {...props} title={lang==='ar'?'إدارة المستودعات':'Manage Warehouses'} busy={busy} onClose={()=>{if(!busy)setDialog('');}}><WarehouseDefinitions {...props} onBusyChange={setBusy}/></Dialog>}
    {dialog && dialog!=='warehouses' && <Dialog {...props} title={t(dialog === 'configure' ? 'configureStock' : 'adjustStock')} t={t} onClose={() => { if (!busy) setDialog(''); }}>
      {dialog==='configure'&&<MaterialDeviationPolicy props={props}/>}
      {dialog==='configure'&&<button onClick={()=>{setDialog('adjust');setQuantity('');setReason('');setNotice('');}}>{t('adjustStock')}</button>}
      <form onSubmit={event => { event.preventDefault();
        if (dialog === 'configure') run('configure_warehouse_product', { product, source, mode, unit, minimum: mode === 'MAKE_TO_STOCK' ? Number(minimum) : null, maximum: mode === 'MAKE_TO_STOCK' && maximum !== '' ? Number(maximum) : null });
        else if(decimalCompare(quantity,'0')===-1){if(adjustValid)run('source_stock_command',{operation:'adjust',payload:{product,unit,quantity,reason},allocations:adjustPicks});}
        else run('adjust_finished_stock', { product, unit, quantity: Number(quantity), reason });
      }}><fieldset disabled={busy} className="fulfillment-form">
        <WarehousePicker label={t('product')} required value={product} placeholder={t('select')} options={[...(configuredRow&&!s.tables.products.some(p=>p.id===configuredRow.id)?[{id:configuredRow.id,name:lang==='ar'?configuredRow.name_ar||configuredRow.name:configuredRow.name}]:[]),...s.tables.products.filter(row=>row.stage==='finished').map(row=>({id:String(row.id),name:localName(row,lang)}))]} onChange={id=>{setProduct(id);const selected=s.tables.products.find(row=>row.id===id);setMode(String(selected?.supply_mode||'MAKE_TO_ORDER'));setUnit(String(selected?.stock_unit||''));setMinimum(String(selected?.minimum_stock??''));setMaximum(String(selected?.maximum_stock??''));setSource(String(selected?.supply_source||'MANUFACTURED'));}}/>
        <Field label={t('unit')}><select required value={unit} onChange={event => setUnit(event.target.value)}><option value="">{t('select')}</option><option value="meter">{t('meter')}</option><option value="piece">{t('piece')}</option>{(s.tables.products.find(row=>row.id===product)?.product_kind==='MANUFACTURED_INTERMEDIATE'||unit==='kg')&&<option value="kg">{t('kg')}</option>}</select></Field>
        {dialog === 'configure' ? <><Field label={t('supplySource')}><select value={source} onChange={event => setSource(event.target.value)}>{['MANUFACTURED','EXTERNAL','BOTH'].map(value => <option key={value} value={value}>{t(`supply_${value}`)}</option>)}</select></Field>
          {source === 'BOTH' && <p>{t('hybridSourceHelp')}</p>}
          <Field label={t('supplyMode')}><select value={mode} onChange={event => setMode(event.target.value)}><option value="MAKE_TO_ORDER">{t('makeToOrder')}</option><option value="MAKE_TO_STOCK">{t('makeToStock')}</option></select></Field>
          {mode === 'MAKE_TO_STOCK' && <><Field label={t('stockMin')}><input required type="number" min="0" step="any" value={minimum} onChange={event => setMinimum(event.target.value)} /></Field>
            <Field label={t('stockMax')}><input type="number" min={Math.max(Number(minimum), 0.000001)} step="any" value={maximum} onChange={event => setMaximum(event.target.value)} /></Field></>}
        </> : <><p>{t('stockAdjustmentHelp')}</p><Field label={t('stockAdjustmentDifference')}><input required type="number" step="any" value={quantity} onChange={event => setQuantity(event.target.value)} /></Field>
          <Field label={t('reason')}><textarea required minLength={3} maxLength={2000} value={reason} onChange={event => setReason(event.target.value)} /></Field></>}
        {dialog!=='configure'&&decimalCompare(quantity,'0')===-1&&<SourceAllocationFields warehouse disabled={busy} snapshot={s} t={t} lang={lang} product={product} unit={unit} quantity={quantity.slice(1)} onChange={(picks,valid)=>{setAdjustPicks(picks);setAdjustValid(valid);}}/>}
        {notice && <p role="alert">{t(notice)}</p>}<button className="primary" disabled={dialog!=='configure'&&decimalCompare(quantity,'0')===-1&&!adjustValid}>{t('save')}</button>
      </fieldset></form>
    </Dialog>}
  </section>;
}
