import type { Language, Translate } from '@/types';
import { formatTime } from './ui';
import type { ProductionDemand } from '@/features/useFulfillment';
import { requestOriginLabel } from '@/utils/request-origin.mjs';
export default function DeliveryContext({ rows, item, t, lang, zone }: {
  rows: ProductionDemand[]; item: unknown; t: Translate; lang: Language; zone: string;
}) {
  const demand = rows.filter(row => row.item_id === String(item));
  if (!demand.length) return null;
  return <span className="delivery-context">{demand.map((row, index) => <span key={`${row.sales_order_id || row.item_id}-${index}`}
    className="delivery-signal" data-risk={row.risk || 'none'}>
    <strong>{t(requestOriginLabel(row.request_type))}</strong>
    {row.sales_order_code && <><bdi dir="ltr">{row.sales_order_code}</bdi>
      <span>{t('customerDue')}: {formatTime(row.promised_delivery || row.requested_delivery, lang, zone)}</span>
      <span>{t(`deliveryRisk_${row.risk || 'unknown'}`)}</span>
      <span>{t('targetReady')}: {formatTime(row.target_ready, lang, zone)}</span></>}
  </span>)}</span>;
}
