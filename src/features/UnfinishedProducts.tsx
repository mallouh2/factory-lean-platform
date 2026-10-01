import { useState } from 'react';
import { formatTime } from '@/components/ui';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
import { useUnfinished } from './useUnfinished';
import ProductionRecording from './ProductionRecording';

export default function UnfinishedProducts(props: FeatureProps) {
  const { snapshot: s, t, lang, can } = props;
  const [history, setHistory] = useState(false), [page, setPage] = useState(1), [selection, setSelected] = useState<Row | null>(null);
  const selected=selection?.factory_id===s.factory?.id?selection:null;
  const data = useUnfinished(s, history, page);
  const q = (value: unknown) => Number(value).toLocaleString(lang);
  const name = (row: Row, key: string) => String(row[lang === 'ar' ? `${key}_name_ar` : `${key}_name`] || row[`${key}_name`] || '');
  return <section className="panel unfinished-products" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    <header className="row-actions"><h2>{t('unfinishedProducts')}</h2><label><input type="checkbox" checked={history} onChange={e => { setHistory(e.target.checked); setPage(1); }} /> {t('unfinishedIncludeConsumed')}</label></header>
    {data.error && <p role="alert">{t(data.error)} <button onClick={data.refresh}>{t('refresh')}</button></p>}
    <p className="history-load-status muted" role="status">{data.busy ? t('loading') : `${t('historyRecords')}: ${q(data.total)}`}</p>
    {!data.busy && !data.rows.length && <p>{t('unfinishedEmpty')}</p>}
    <div className="unfinished-list">{data.rows.map(lot => <article key={String(lot.id)}>
      <h3 dir="auto">{name(lot, 'product')}</h3>
      <strong>{t('unfinishedAvailable')}: {q(lot.quantity_available)} {t(lot.unit === 'piece' ? 'pieceShort' : 'meterShort')}</strong>
      <small>{t(Number(lot.quantity_available) === 0 ? 'unfinishedConsumed' : Number(lot.quantity_available) < Number(lot.quantity_created) ? 'unfinishedPartial' : 'unfinishedAvailable')}</small>
      <p dir="auto">{t('unfinishedRemainingWork')}: {String(lot.remaining_work)}</p>
      <p><bdi>{String(lot.request_code || lot.item_code)}</bdi> · {name(lot, 'origin')}</p>
      <time>{formatTime(lot.created_at, lang, String(s.factory?.timezone || 'UTC'))}</time>
      <details><summary>{t('view')}</summary>
        <p title={String(lot.id)}>{t('unfinishedLotReference')}: <bdi>{String(lot.id).slice(0,8)}</bdi></p>
        <p>{t('unfinishedCreated')}: {q(lot.quantity_created)} {t(lot.unit === 'piece' ? 'pieceShort' : 'meterShort')}</p>
        <p>{t('recordingSubmittedBy')}: {String(s.tables.production_technicians?.find(x => x.user_id === lot.created_by)?.display_name || t('notAvailable'))}</p>
        <ol>{((lot.movements || []) as unknown as Row[]).map(m => <li key={String(m.id)}>{t(`unfinishedMovement_${m.kind}`)} · {q(m.quantity)} · {formatTime(m.created_at, lang, String(s.factory?.timezone || 'UTC'))}</li>)}</ol>
        {lot.parent_lot_id && <p title={String(lot.parent_lot_id)}>{t('unfinishedReprocessed')} · {t('unfinishedLotReference')}: <bdi>{String(lot.parent_lot_id).slice(0,8)}</bdi></p>}
      </details>
      {can('orders', 'edit') && Number(lot.quantity_available) > 0 && <button className="primary" disabled={!((lot.destinations || []) as unknown as Row[]).length} onClick={() => setSelected(lot)}>{t('unfinishedUse')}</button>}
      {Number(lot.quantity_available) > 0 && !((lot.destinations || []) as unknown as Row[]).length && <p className="muted">{t('unfinishedNoDestination')}</p>}
    </article>)}</div>
    <nav className="history-pagination"><button disabled={data.busy || page === 1} onClick={() => setPage(x => x - 1)}>{t('previous')}</button><span>{q(page)} / {q(Math.max(1, Math.ceil(data.total / 50)))}</span><button disabled={data.busy || page * 50 >= data.total} onClick={() => setPage(x => x + 1)}>{t('next')}</button></nav>
    {selected && <ProductionRecording {...props} selectedLot={selected} key={`${s.factory?.id}:${selected.id}`} />}
  </section>;
}
