import { useEffect, useState } from 'react';
import type { Language, Translate } from '@/types';
import { formatTime } from './ui';
import { formatDuration } from '@/utils/production-flow.mjs';
type Guidance = { requested_delivery: string | null; target_ready: string; safety_buffer_days: number; state: string;
  suggestion: { start: string; finish: string; minutes: number } | null };
export default function SalesPlanningGuidance({ factory, item, fetchedAt, proposal, t, lang, zone }: {
  factory: string; item: string; fetchedAt: unknown; proposal: { finish: number; error?: string } | null; t: Translate; lang: Language; zone: string;
}) {
  const [result, setResult] = useState<{ key: string; data: Guidance } | null>(null), [error, setError] = useState('');
  const key = factory + ':' + item + ':' + String(fetchedAt);
  useEffect(() => {
    const abort = new AbortController(); setError('');
    fetch('/api/fulfillment?' + new URLSearchParams({ factory, item, mode: 'guidance' }), { cache: 'no-store', signal: abort.signal })
      .then(async response => { const data = await response.json(); if (!response.ok) throw Error(data.error || 'dataWarning'); return data; })
      .then(data => { if (!abort.signal.aborted) setResult({ key, data }); }).catch(cause => { if (!abort.signal.aborted) setError(cause.message); });
    return () => abort.abort();
  }, [factory, item, key]);
  const data = result?.key === key ? result.data : null;
  if (error) return <p className="planning-warning">{t(error)}</p>;
  if (!data) return <p role="status">{t('loading')}</p>;
  if (!data.requested_delivery) return <p className="muted">{t('noCustomerTarget')}</p>;
  const margin = proposal && !proposal.error ? (Date.parse(data.requested_delivery) - proposal.finish) / 60000 : null;
  return <section className="planning-proposal" aria-label={t('salesTargetGuidance')}>
    <strong>{t('salesTargetGuidance')} · {t(`target_${data.state}`)}</strong>
    <span>{t('customerRequested')}: {formatTime(data.requested_delivery, lang, zone)}</span>
    <span>{t('deliveryBuffer')}: {data.safety_buffer_days} {t('planningDays')} · {t('targetReady')}: {formatTime(data.target_ready, lang, zone)}</span>
    {data.suggestion && <><span>{t('planningTotalWorking')}: {formatDuration(data.suggestion.minutes, lang)}</span>
      <span>{t('suggestedStart')}: {formatTime(data.suggestion.start, lang, zone)}</span><span>{t('suggestedFinish')}: {formatTime(data.suggestion.finish, lang, zone)}</span></>}
    <span>{t('proposalMeetsTarget')}: {margin === null ? t('notSpecified') : t(margin >= 0 ? 'yes' : 'no')}</span>
    {margin !== null && <span>{t('targetMargin')}: {formatDuration(Math.round(margin), lang, true)}</span>}
    <small>{t('planningTargetAdvisory')}</small>
  </section>;
}
