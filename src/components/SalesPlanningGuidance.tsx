import { useEffect, useState } from 'react';
import type { Language, Translate } from '@/types';
import { formatTime } from './ui';
import { formatDuration } from '@/utils/production-flow.mjs';
type Guidance = { requested_delivery: string | null; target_ready: string; safety_buffer_days: number; state: string;
  suggestion: { line:string; start: string; finish: string; minutes: number } | null };
export default function SalesPlanningGuidance({ factory, item, fetchedAt, proposal, t, lang, zone,validateSuggestion,onChoose,onInspect,checking=false,needsTimelineCheck }: {
  checking?:boolean;needsTimelineCheck?:(candidate:NonNullable<Guidance['suggestion']>)=>boolean;onInspect?:(candidate:NonNullable<Guidance['suggestion']>)=>void;validateSuggestion?:(candidate:NonNullable<Guidance['suggestion']>)=>string|null;onChoose?:(candidate:NonNullable<Guidance['suggestion']>)=>void;
  factory: string; item: string; fetchedAt: unknown; proposal: { finish: number; error?: string } | null; t: Translate; lang: Language; zone: string;
}) {
  const [result, setResult] = useState<{ key: string; data: Guidance } | null>(null), [error, setError] = useState(''),[revalidating,setRevalidating]=useState(false);
  const key = factory + ':' + item;
  useEffect(() => {
    const abort = new AbortController(); setError('');setRevalidating(true);
    fetch('/api/fulfillment?' + new URLSearchParams({ factory, item, mode: 'guidance' }), { cache: 'no-store', signal: abort.signal })
      .then(async response => { const data = await response.json(); if (!response.ok) throw Error(data.error || 'dataWarning'); return data; })
      .then(data => { if (!abort.signal.aborted) setResult({ key, data }); }).catch(cause => { if (!abort.signal.aborted) setError(cause.message); }).finally(()=>{if(!abort.signal.aborted)setRevalidating(false);});
    return () => abort.abort();
  }, [factory, item, fetchedAt, key]);
  const data = result?.key === key ? result.data : null;
  if (!data&&error)return <p className="planning-warning">{t(error)}</p>;
  if (!data) return <p role="status">{t('loading')}</p>;
  if (!data.requested_delivery) return <p className="muted">{t('noCustomerTarget')}</p>;
  const unavailable=data.suggestion&&validateSuggestion?validateSuggestion(data.suggestion):'salesTargetNoSlot';
  const margin = proposal && !proposal.error ? (Date.parse(data.requested_delivery) - proposal.finish) / 60000 : null;
  return <section className="planning-proposal planning-deadline-choice" aria-label={t('salesTargetGuidance')}>
    {error&&<p className="planning-warning" role="alert">{t(error)}</p>}
    <strong>{t('planningMeetDeadline')} · {t(`target_${data.state}`)}</strong>
    <span>{t('customerRequested')}: {formatTime(data.requested_delivery, lang, zone)}</span>
    <span>{t('deliveryBuffer')}: {data.safety_buffer_days} {t('planningDays')} · {t('targetReady')}: {formatTime(data.target_ready, lang, zone)}</span>
    {data.suggestion && <><span>{t('planningTotalWorking')}: {formatDuration(data.suggestion.minutes, lang)}</span>
      <span>{t('suggestedStart')}: {formatTime(data.suggestion.start, lang, zone)}</span><span>{t('suggestedFinish')}: {formatTime(data.suggestion.finish, lang, zone)}</span></>}
    <span>{t('proposalMeetsTarget')}: {margin === null ? t('notSpecified') : t(margin >= 0 ? 'yes' : 'no')}</span>
    {margin !== null && <span>{t('targetMargin')}: {formatDuration(Math.round(margin), lang, true)}</span>}
    {data.suggestion&&onChoose&&<button type="button" disabled={revalidating||!!error||!!unavailable} onClick={()=>onChoose(data.suggestion!)}>{t('planningUseDeadline')}</button>}{data.suggestion&&(needsTimelineCheck?needsTimelineCheck(data.suggestion):unavailable==='mpBoardOutside')&&onInspect&&<button type="button" onClick={()=>onInspect(data.suggestion!)}>{t('planningCheckDeadline')}</button>}<span className={unavailable&&!checking&&!revalidating?'planning-warning planning-guidance-status':'planning-guidance-status'} role="status">{checking||revalidating?t('loading'):unavailable?t(unavailable):'\u00a0'}</span>
    <small>{t('planningTargetAdvisory')}</small>
  </section>;
}
