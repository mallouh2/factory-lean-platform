import { useRef, useState } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field, formatTime, localName } from '@/components/ui';
import ProductIdentity from '@/components/ProductIdentity';
import { formatLocalInput, localDateTimeToUtc } from '@/utils/manufacturing.mjs';
import { useFulfillment, type SalesLine, type SalesOrder } from './useFulfillment';

type DraftLine = { product_id: string; quantity: string; unit: string; release_when_ready: boolean };
const emptyLine = (): DraftLine => ({ product_id: '', quantity: '', unit: '', release_when_ready: false });
export default function SalesOrders({ snapshot: s, t, lang, command, can }: FeatureProps) {
  const [page, setPage] = useState(1), [creating, setCreating] = useState(false), [editing, setEditing] = useState<SalesOrder | null>(null);
  const read = useFulfillment<{ rows: SalesOrder[]; total: number }>(s, 'sales', page, can('sales_orders'));
  const [customer, setCustomer] = useState(''), [requested, setRequested] = useState('');
  const [buffer, setBuffer] = useState(String(s.factory?.delivery_buffer_days ?? 2)), [notes, setNotes] = useState(''), [reason, setReason] = useState('');
  const [lines, setLines] = useState<DraftLine[]>([emptyLine()]), [editLines, setEditLines] = useState<SalesLine[]>([]);
  const [busy, setBusy] = useState(false), [notice, setNotice] = useState('');
  const [confirmCancel, setConfirmCancel] = useState(false);
  const [confirming,setConfirming]=useState<SalesOrder|null>(null);
  const preview=useFulfillment<{rows:{id:string;unit:string;ordered:string;available:string;to_reserve:string;incoming:string;additional:string}[]}>(s,'confirmation',1,!!confirming,{order:confirming?.id||''});
  const retry = useRef<{ key: string; id: string } | null>(null);
  const zone = String(s.factory?.timezone || 'UTC');
  const products = (s.tables.products || []).filter(product => product.stage === 'finished');
  async function run(name: string, args: Record<string, unknown>) {
    const key = JSON.stringify([name, args]);
    if (retry.current?.key !== key) retry.current = { key, id: crypto.randomUUID() };
    setBusy(true); setNotice('');
    try {
      await command(name, { factory: s.factory?.id, ...args, request_id: retry.current.id });
      retry.current = null; read.refresh(); setCreating(false); setEditing(null);setConfirming(null); setNotice('saved');
    } catch (cause) { setNotice(cause instanceof Error ? cause.message : 'error'); }
    finally { setBusy(false); }
  }
  function edit(order: SalesOrder) {
    setConfirmCancel(false);
    setEditing(order); setCreating(false); setCustomer(order.customer_reference); setRequested(order.requested_delivery ? formatLocalInput(order.requested_delivery, zone) : '');
    setBuffer(String(order.safety_buffer_days)); setNotes(order.notes); setReason(''); setEditLines(order.lines.map(line => ({ ...line }))); setNotice('');
  }
  const editable = can('sales_orders', 'edit') && (!editing || editing.status === 'draft' || can('sales_orders', 'approve'));
  const dates = () => ({ customer_reference: customer.trim(), requested_delivery: requested ? localDateTimeToUtc(requested, zone) : null,
    safety_buffer_days: Number(buffer), notes });
  return <section className="fulfillment-page" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    <div className="fulfillment-tools"><p className="muted">{t('salesHelp')}</p>
      {can('sales_orders', 'create') && <button className="primary" onClick={() => {
        setCreating(true); setEditing(null); setCustomer(''); setRequested(''); setBuffer(String(s.factory?.delivery_buffer_days ?? 2)); setNotes(''); setLines([emptyLine()]); setNotice('');
      }}>{t('salesCreate')}</button>}<button onClick={read.refresh}>{t('refresh')}</button></div>
    {(read.error || notice) && <p role="alert">{t(read.error || notice)}</p>}
    {read.loading && <p role="status">{t('loading')}</p>}
    {read.data && !read.data.rows.length && <p className="empty">{t('salesEmpty')}</p>}
    <div className="fulfillment-orders">{read.data?.rows.map(order => <article className="fulfillment-order" key={order.id} data-risk={order.risk}>
      <header><div><strong><bdi dir="ltr">{order.code}</bdi></strong><p dir="auto">{order.customer_reference || t('salesNoReference')}</p></div>
        <span className="fulfillment-status">{t(`salesState_${order.fulfillment_status}`)}</span></header>
      <dl className="fulfillment-dates"><div><dt>{t('customerRequested')}</dt><dd>{formatTime(order.requested_delivery, lang, zone)}</dd></div>
        {order.promised_delivery && <div><dt>{t('historicalPromise')}</dt><dd>{formatTime(order.promised_delivery, lang, zone)}</dd></div>}
        <div><dt>{t('estimatedReady')}</dt><dd>{order.estimated_ready ? formatTime(order.estimated_ready, lang, zone) : t('readinessPending')}</dd></div>
        {order.requested_delivery && <div><dt>{t('earliestFeasible')}</dt><dd>{formatTime(order.earliest_feasible, lang, zone)}</dd></div>}</dl>
      {order.status === 'approved' && order.requested_delivery && <p className="delivery-signal" data-risk={order.risk}>
        {t(`deliveryRisk_${order.risk}`)}{order.requested_feasible === false && <> · {t('requestedNotFeasible')}</>}
        {Boolean(order.delay_days) && <> · {order.delay_days} {t('planningDays')}</>}
        <span>{t('targetReady')}: {formatTime(order.target_ready, lang, zone)} · {t('deliveryBuffer')}: {order.safety_buffer_days} {t('planningDays')}</span>
      </p>}
      <div className="fulfillment-lines">{order.lines.map(line => <div key={line.id} className="fulfillment-line">
        <ProductIdentity productId={line.product_id}>{lang === 'ar' ? line.product_name_ar || line.product_name : line.product_name}</ProductIdentity>
        <span>{t('quantity')}: {line.quantity} {t(line.unit)}</span>
        <span>{t('stockReserved')}: {line.reserved_quantity}</span><span>{t('stockIncoming')}: {line.incoming_quantity}</span>
        <span>{t('productionRequired')}: {line.production_required}</span><span>{t('stockDispatched')}: {line.dispatched_quantity}</span>
        {Number(line.external_shortage) > 0 && <span>{t('externalReplenishment')}: {line.external_shortage} {t(line.unit)}</span>}
        {Number(line.source_decision_quantity) > 0 && <span>{t('sourcingDecision')}: {line.source_decision_quantity} {t(line.unit)}</span>}
        <span>{t(order.status==='completed'?'salesDeliveryConfirmed':'salesWarehouseDispatch')}</span>
      </div>)}</div>
      <footer>{order.status === 'draft' && can('sales_orders', 'approve') && <button className="primary" disabled={busy}
        onClick={() => {setNotice('');setConfirming(order);}}>{t('salesApprove')}</button>}
        {!['completed', 'cancelled'].includes(order.status) && can('sales_orders', 'edit') && (order.status === 'draft' || can('sales_orders', 'approve')) &&
          <button disabled={busy} onClick={() => edit(order)}>{t('edit')}</button>}
        <span className="muted">{t(order.status==='completed'?'salesDeliveryConfirmed':'salesWarehouseDispatch')}</span></footer>
    </article>)}</div>
    <nav className="fulfillment-pagination" aria-label={t('salesOrders')}><button disabled={page === 1 || read.busy} onClick={() => setPage(value => value - 1)}>{t('previous')}</button>
      <span>{page}</span><button disabled={read.busy || page * 25 >= (read.data?.total || 0)} onClick={() => setPage(value => value + 1)}>{t('next')}</button></nav>
    {confirming&&<Dialog title={t('salesApprove')} t={t} busy={busy} onClose={()=>{if(!busy)setConfirming(null);}}><p><bdi>{confirming.code}</bdi> · {confirming.customer_reference}</p>
     {preview.loading&&<p role="status">{t('loading')}</p>}{(preview.error||notice)&&<p role="alert">{t(preview.error||notice)}</p>}
     {preview.data?.rows.map(line=><section key={line.id}><strong>{(()=>{const p=confirming.lines.find(l=>l.id===line.id);return lang==='ar'?p?.product_name_ar||p?.product_name:p?.product_name;})()}</strong><dl className="quality-context">{[[t('quantity'),line.ordered],[t('available'),line.available],[lang==='ar'?'سيتم حجزه':'Will be reserved',line.to_reserve],[t('stockIncoming'),line.incoming],[t('productionRequired'),line.additional]].map(([name,value])=><div key={name}><dt>{name}</dt><dd><bdi>{value} {t(line.unit)}</bdi></dd></div>)}</dl></section>)}
     <p>{lang==='ar'?'يُعاد التحقق من الكميات عند تأكيد الطلب.':'Availability is checked again when you confirm the order.'}</p><button className="primary" disabled={busy||preview.busy||!!preview.error||!preview.data} onClick={()=>void run('approve_sales_order',{sales_order:confirming.id})}>{t('salesApprove')}</button>
    </Dialog>}
    {(creating || editing) && <Dialog title={t(creating ? 'salesCreate' : 'edit')} t={t} onClose={() => { if (!busy) { setCreating(false); setEditing(null); } }}>
      <form onSubmit={event => { event.preventDefault(); const payload = dates();
        if (requested && !payload.requested_delivery) { setNotice('planningInvalidStart'); return; }
        if (creating) run('create_sales_order', { payload: { ...payload, lines: lines.map(line => ({ ...line, quantity: Number(line.quantity) })) } });
        else if (editing) run('change_sales_order', { sales_order: editing.id, payload: { ...payload,
          lines: editLines.map(line => ({ id: line.id, quantity: Number(line.quantity), release_when_ready: line.release_when_ready })) }, reason });
      }}><fieldset disabled={busy || (editing !== null && !editable)} className="fulfillment-form">
        <Field label={t('customerReference')}><input maxLength={200} value={customer} onChange={event => setCustomer(event.target.value)} /></Field>
        <Field label={`${t('customerRequested')} (${t('optional')}) · ${zone}`}><input type="datetime-local" value={requested}
          onInput={event => setRequested(event.currentTarget.value)} onChange={event => setRequested(event.target.value)} /></Field>
        <Field label={t('deliveryBuffer')}><input required type="number" min="0" max="90" disabled={!can('sales_orders', 'approve')} value={buffer} onChange={event => setBuffer(event.target.value)} /></Field>
        <Field label={t('notes')}><textarea maxLength={2000} value={notes} onChange={event => setNotes(event.target.value)} /></Field>
        {creating ? lines.map((line, index) => <div className="fulfillment-line-editor" key={index}>
          <Field label={t('product')}><select required value={line.product_id} onChange={event => setLines(value => value.map((row, i) => i === index ? { ...row, product_id: event.target.value, unit: String(products.find(product => product.id === event.target.value)?.stock_unit || '') } : row))}>
            <option value="">{t('select')}</option>{products.map(product => <option key={String(product.id)} value={String(product.id)}>{localName(product, lang)}</option>)}</select></Field>
          <Field label={t('quantity')}><input required type="number" min="0.000001" step="any" value={line.quantity} onChange={event => setLines(value => value.map((row, i) => i === index ? { ...row, quantity: event.target.value } : row))} /></Field>
          <Field label={t('unit')}><select required value={line.unit} onChange={event => setLines(value => value.map((row, i) => i === index ? { ...row, unit: event.target.value } : row))}>
            <option value="">{t('select')}</option>{['meter','piece'].filter(unit => !products.find(product => product.id === line.product_id)?.stock_unit || products.find(product => product.id === line.product_id)?.stock_unit === unit).map(unit => <option key={unit} value={unit}>{t(unit)}</option>)}</select></Field>
          <label className="check"><input type="checkbox" checked={line.release_when_ready} onChange={event => setLines(value => value.map((row, i) => i === index ? { ...row, release_when_ready: event.target.checked } : row))} />{t('releaseWhenReady')}</label>
          {lines.length > 1 && <button type="button" onClick={() => setLines(value => value.filter((_, i) => i !== index))}>{t('remove')}</button>}
        </div>) : editLines.map((line, index) => <div className="fulfillment-line-editor" key={line.id}>
          <strong>{lang === 'ar' ? line.product_name_ar || line.product_name : line.product_name}</strong>
          <Field label={`${t('quantity')} · ${t(line.unit)}`}><input required type="number" min={Math.max(Number(line.dispatched_quantity), 0.000001)} step="any" value={line.quantity}
            onChange={event => setEditLines(value => value.map((row, i) => i === index ? { ...row, quantity: Number(event.target.value) } : row))} /></Field>
          <label className="check"><input type="checkbox" checked={line.release_when_ready} onChange={event => setEditLines(value => value.map((row, i) => i === index ? { ...row, release_when_ready: event.target.checked } : row))} />{t('releaseWhenReady')}</label>
        </div>)}
        {creating && <button type="button" disabled={lines.length >= 50} onClick={() => setLines(value => [...value, emptyLine()])}>{t('addProduct')}</button>}
        {editing && <Field label={t('reason')}><textarea required minLength={3} maxLength={2000} value={reason} onChange={event => setReason(event.target.value)} /></Field>}
        {notice && <p role="alert">{t(notice)}</p>}<button className="primary">{creating?(lang==='ar'?'حفظ مسودة':'Save Draft'):t('save')}</button>
        {editing && !confirmCancel && <button type="button" disabled={reason.trim().length < 3}
          onClick={() => setConfirmCancel(true)}>{t('salesCancel')}</button>}
        {editing && confirmCancel && <div className="fulfillment-cancel-confirm" role="group" aria-label={t('salesCancel')}>
          <p>{t('salesCancelConfirm')}</p><div className="row-actions">
            <button type="button" onClick={() => setConfirmCancel(false)}>{t('cancel')}</button>
            <button type="button" disabled={reason.trim().length < 3} onClick={() =>
              run('change_sales_order', { sales_order: editing.id, payload: { cancel: true }, reason })}>{t('salesCancel')}</button>
          </div>
        </div>}
      </fieldset></form>
    </Dialog>}
  </section>;
}
