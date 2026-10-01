import { useEffect, useState } from 'react';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
export function useUnfinished(s: FeatureProps['snapshot'], history = false, page = 1, lot = '') {
  const factory = String(s.factory?.id || '');
  const query = new URLSearchParams({ factory, history: history ? '1' : '0', page: String(page),lot }).toString();
  const [result, setResult] = useState<{ query: string; rows: Row[]; total: number } | null>(null);
  const [error, setError] = useState(''), [busy, setBusy] = useState(true), [retry, setRetry] = useState(0);
  useEffect(() => {
    const controller = new AbortController(); setBusy(true); setError('');
    fetch(`/api/unfinished?${query}`, { signal: controller.signal, cache: 'no-store' })
      .then(async r => { if (!r.ok) throw Error('dataWarning'); return r.json(); })
      .then(data => { if (!controller.signal.aborted) setResult({ query, ...data }); })
      .catch(e => { if (!controller.signal.aborted) setError(e.message); })
      .finally(() => { if (!controller.signal.aborted) setBusy(false); });
    return () => controller.abort();
  }, [query, s.fetchedAt, retry]);
  return { loaded:result?.query===query, rows: result?.query === query ? result.rows : [], total: result?.query === query ? result.total : 0, busy, error, refresh: () => setRetry(x => x + 1) };
}
