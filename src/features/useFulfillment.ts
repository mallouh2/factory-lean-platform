import { useEffect, useState } from 'react';
import type { Snapshot } from '@/types';
export type SalesLine = { id: string; product_id: string; product_name: string; product_name_ar: string;
  quantity: number; unit: string; release_when_ready: boolean; reserved_quantity: number; incoming_quantity: number;
  production_required: number; dispatched_quantity: number; ready: boolean; dispatch_allowed: boolean };
export type SalesOrder = { id: string; code: string; customer_reference: string; requested_delivery: string;
  promised_delivery: string | null; safety_buffer_days: number; notes: string; status: string;
  fulfillment_status: string; risk: string; lines: SalesLine[]; estimated_ready: string | null;
  earliest_feasible: string | null; requested_feasible: boolean | null; target_ready: string;
  delay_days: number | null; dispatch_allowed: boolean };
export type StockRow = { product_id: string; name: string; name_ar: string; unit: string; on_hand: number;
  reserved: number; available: number; incoming: number; projected: number; supply_mode: string;
  minimum_stock: number | null; maximum_stock: number | null };
export type ProductionDemand = { item_id: string; request_type: string | null; sales_order_id: string | null;
  sales_order_code: string | null; requested_delivery: string | null; promised_delivery: string | null;
  estimated_ready: string | null; target_ready: string | null; risk: string | null; incoming_allocated: number | null };
export function useFulfillment<T>(snapshot: Snapshot, mode: string, page = 1, enabled = true) {
  const query = new URLSearchParams({ factory: String(snapshot.factory?.id || ''), mode, page: String(page) }).toString();
  const [result, setResult] = useState<{ query: string; data: T } | null>(null);
  const [error, setError] = useState(''), [busy, setBusy] = useState(false), [retry, setRetry] = useState(0);
  useEffect(() => {
    if (!enabled) return;
    const controller = new AbortController(); setBusy(true); setError('');
    fetch(`/api/fulfillment?${query}`, { cache: 'no-store', signal: controller.signal })
      .then(async response => { const data = await response.json(); if (!response.ok) throw Error(data.error || 'dataWarning'); return data; })
      .then(data => { if (!controller.signal.aborted) setResult({ query, data }); })
      .catch(cause => { if (!controller.signal.aborted) setError(cause.message); })
      .finally(() => { if (!controller.signal.aborted) setBusy(false); });
    return () => controller.abort();
  }, [query, enabled, snapshot.fetchedAt, retry]);
  return { data: enabled && result?.query === query ? result.data : null, busy, error, refresh: () => setRetry(value => value + 1) };
}
