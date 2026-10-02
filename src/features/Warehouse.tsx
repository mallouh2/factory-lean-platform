import { useRef, useState } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field, localName } from '@/components/ui';
import ProductIdentity from '@/components/ProductIdentity';
import UnfinishedProducts from './UnfinishedProducts';
import { useFulfillment, type SalesLine, type SalesOrder, type StockRow } from './useFulfillment';
export default function Warehouse({ snapshot: s, t, lang, command, can }: FeatureProps) {
  const [page, setPage] = useState(1), [tab, setTab] = useState('finished');
  const read = useFulfillment<{ rows: StockRow[]; total: number; orders: SalesOrder[]; orders_total: number }>(s, 'warehouse', page, can('warehouse'));
  const [dialog, setDialog] = useState(''), [product, setProduct] = useState(''), [unit, setUnit] = useState('');
  const [mode, setMode] = useState('MAKE_TO_ORDER'), [minimum, setMinimum] = useState(''), [maximum, setMaximum] = useState('');
  const [quantity, setQuantity] = useState(''), [reason, setReason] = useState(''), [busy, setBusy] = useState(false), [notice, setNotice] = useState('');
  const [dispatch, setDispatch] = useState<{ order: SalesOrder; line?: SalesLine } | null>(null);
  const retry = useRef<{ key: string; id: string } | null>(null);
  async function run(name: string, args: Record<string, unknown>) {
    const key = JSON.stringify([name, args]);
    if (retry.current?.key !== key) retry.current = { key, id: crypto.randomUUID() };
    setBusy(true); setNotice('');
    try {
      await command(name, { factory: s.factory?.id, ...args, ...(name === 'configure_product_stock' ? {} : { request_id: retry.current.id }) });
      retry.current = null; read.refresh(); setDialog(''); setDispatch(null); setNotice('saved');
    } catch (cause) { setNotice(cause instanceof Error ? cause.message : 'error'); } finally { setBusy(false); }
  }
  return <section className="fulfillment-page" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    <div className="fulfillment-tools"><button aria-pressed={tab === 'finished'} onClick={() => setTab('finished')}>{t('finishedProducts')}</button>
      {can('orders') && <button aria-pressed={tab === 'unfinished'} onClick={() => setTab('unfinished')}>{t('unfinishedProducts')}</button>}
      <button onClick={read.refresh}>{t('refresh')}</button>
      {can('warehouse', 'edit') && <><button onClick={() => { setDialog('configure'); setNotice(''); }}>{t('configureStock')}</button>
        <button onClick={() => { setDialog('adjust'); setQuantity(''); setReason(''); setNotice(''); }}>{t('adjustStock')}</button></>}
    </div>
    {(read.error || notice) && <p role="alert">{t(read.error || notice)}</p>}
    {tab === 'unfinished' ? <UnfinishedProducts snapshot={s} t={t} lang={lang} command={command} can={can} /> : <>
      <p className="muted">{t('warehouseHelp')}</p>{read.busy && <p role="status">{t('loading')}</p>}
      {read.data?.rows.length === 0 && <p className="empty">{t('warehouseEmpty')}</p>}
      <div className="finished-stock-list">{read.data?.rows.map(row => <article className="finished-stock-row" key={`${row.product_id}-${row.unit}`}>
        <ProductIdentity productId={row.product_id}>{lang === 'ar' ? row.name_ar || row.name : row.name}</ProductIdentity>
        <span>{t(row.unit)} · {t(row.supply_mode === 'MAKE_TO_STOCK' ? 'makeToStock' : 'makeToOrder')}</span>
        <dl>{(['on_hand', 'reserved', 'available', 'incoming', 'projected'] as const).map(key => <div key={key}><dt>{t(`stock_${key}`)}</dt><dd>{Number(row[key]).toLocaleString(lang)}</dd></div>)}</dl>
        {row.supply_mode === 'MAKE_TO_STOCK' && <p className="delivery-signal" data-risk={Number(row.projected) < Number(row.minimum_stock) ? 'at_risk' : 'on_time'}>
          {t('stockMin')}: {row.minimum_stock} · {t('stockMax')}: {row.maximum_stock} · {t('stockReplenishment')}</p>}
      </article>)}</div>
      <h2>{t('warehouseDispatchQueue')}</h2><p className="muted">{t('warehouseHoldHelp')}</p>
      <div className="fulfillment-orders">{read.data?.orders.map(order => <article key={order.id} className="fulfillment-order" data-risk={order.risk}>
        <header><strong><bdi dir="ltr">{order.code}</bdi> · {order.customer_reference}</strong><span>{t(`salesState_${order.fulfillment_status}`)}</span></header>
        {order.lines.map(line => <div className="fulfillment-line" key={line.id}>
          <ProductIdentity productId={line.product_id}>{lang === 'ar' ? line.product_name_ar || line.product_name : line.product_name}</ProductIdentity>
          <span>{line.quantity} {t(line.unit)} · {t('stockReserved')}: {line.reserved_quantity} · {t('stockDispatched')}: {line.dispatched_quantity}</span>
          {can('warehouse', 'issue') && line.dispatch_allowed && !order.dispatch_allowed && <button disabled={busy}
            onClick={() => setDispatch({ order, line })}>{t('dispatchProductLine')}</button>}
        </div>)}
        {can('warehouse', 'issue') && order.dispatch_allowed && <button className="primary" disabled={busy}
          onClick={() => setDispatch({ order })}>{t('dispatchOrder')}</button>}
      </article>)}</div>
      <nav className="fulfillment-pagination" aria-label={t('warehouse')}><button disabled={page === 1 || read.busy} onClick={() => setPage(value => value - 1)}>{t('previous')}</button><span>{page}</span>
        <button disabled={read.busy || (page * 50 >= (read.data?.total || 0) && page * 25 >= (read.data?.orders_total || 0))} onClick={() => setPage(value => value + 1)}>{t('next')}</button></nav>
    </>}
    {dispatch && <Dialog title={t('confirmDispatch')} t={t} onClose={() => { if (!busy) setDispatch(null); }}>
      <p>{t('dispatchConfirm')}</p><strong><bdi dir="ltr">{dispatch.order.code}</bdi> · {dispatch.order.customer_reference}</strong>
      {(dispatch.line ? [dispatch.line] : dispatch.order.lines.filter(line => line.dispatched_quantity < line.quantity)).map(line =>
        <p key={line.id}><ProductIdentity productId={line.product_id}>{lang === 'ar' ? line.product_name_ar || line.product_name : line.product_name}</ProductIdentity> · {line.quantity - line.dispatched_quantity} {t(line.unit)}</p>)}
      {notice && notice !== 'saved' && <p role="alert">{t(notice)}</p>}
      <div className="row-actions"><button disabled={busy} onClick={() => setDispatch(null)}>{t('cancel')}</button>
        <button className="primary" disabled={busy} onClick={() => run('dispatch_sales_order', { sales_order: dispatch.order.id, ...(dispatch.line ? { line: dispatch.line.id } : {}) })}>{t('confirmDispatch')}</button></div>
    </Dialog>}
    {dialog && <Dialog title={t(dialog === 'configure' ? 'configureStock' : 'adjustStock')} t={t} onClose={() => { if (!busy) setDialog(''); }}>
      <form onSubmit={event => { event.preventDefault();
        if (dialog === 'configure') run('configure_product_stock', { product, mode, unit, minimum: mode === 'MAKE_TO_STOCK' ? Number(minimum) : null, maximum: mode === 'MAKE_TO_STOCK' ? Number(maximum) : null });
        else run('adjust_finished_stock', { product, unit, quantity: Number(quantity), reason });
      }}><fieldset disabled={busy} className="fulfillment-form">
        <Field label={t('product')}><select required value={product} onChange={event => {
          setProduct(event.target.value); const selected = s.tables.products.find(row => row.id === event.target.value);
          setMode(String(selected?.supply_mode || 'MAKE_TO_ORDER')); setUnit(String(selected?.stock_unit || '')); setMinimum(String(selected?.minimum_stock ?? '')); setMaximum(String(selected?.maximum_stock ?? ''));
        }}><option value="">{t('select')}</option>{s.tables.products.filter(row => row.stage === 'finished').map(row => <option key={String(row.id)} value={String(row.id)}>{localName(row, lang)}</option>)}</select></Field>
        <Field label={t('unit')}><select required value={unit} onChange={event => setUnit(event.target.value)}><option value="">{t('select')}</option><option value="meter">{t('meter')}</option><option value="piece">{t('piece')}</option></select></Field>
        {dialog === 'configure' ? <><Field label={t('supplyMode')}><select value={mode} onChange={event => setMode(event.target.value)}><option value="MAKE_TO_ORDER">{t('makeToOrder')}</option><option value="MAKE_TO_STOCK">{t('makeToStock')}</option></select></Field>
          {mode === 'MAKE_TO_STOCK' && <><Field label={t('stockMin')}><input required type="number" min="0" step="any" value={minimum} onChange={event => setMinimum(event.target.value)} /></Field>
            <Field label={t('stockMax')}><input required type="number" min={Math.max(Number(minimum), 0.000001)} step="any" value={maximum} onChange={event => setMaximum(event.target.value)} /></Field></>}
        </> : <><p>{t('stockAdjustmentHelp')}</p><Field label={t('quantity')}><input required type="number" step="any" value={quantity} onChange={event => setQuantity(event.target.value)} /></Field>
          <Field label={t('reason')}><textarea required minLength={3} maxLength={2000} value={reason} onChange={event => setReason(event.target.value)} /></Field></>}
        {notice && <p role="alert">{t(notice)}</p>}<button className="primary">{t('save')}</button>
      </fieldset></form>
    </Dialog>}
  </section>;
}
