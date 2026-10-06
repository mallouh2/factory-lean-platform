import { useRef, useState } from 'react';
import type { FeatureProps } from './types';

export default function FactoryExport({ snapshot, can, t, lang }: FeatureProps) {
  const [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [error, setError] = useState('');
  const pending = useRef(false);
  if (!can('factory', 'export')) return null;
  async function download() {
    if (pending.current) return;
    pending.current = true; setBusy(true); setMessage(''); setError('');
    try {
      const response = await fetch('/api/factory-export', { method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ factory: snapshot.factory?.id, language: lang }) });
      if (!response.ok) {
        const result = await response.json(); throw new Error(result.error || 'error');
      }
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement('a'); link.href = url;
      link.download = `factory-data-${new Date().toISOString().slice(0,10)}.xlsx`;
      document.body.append(link); link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
      setMessage('factoryExportDownloaded');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'error'); }
    finally { pending.current = false; setBusy(false); }
  }
  return <section className="factory-export" aria-labelledby="factory-export-title">
    <h3 id="factory-export-title">{t('factoryExport')}</h3>
    <p className="muted">{t('factoryExportHelp')}</p>
    <button type="button" disabled={busy} aria-busy={busy} onClick={() => void download()}>
      {t(busy ? 'factoryExportPreparing' : 'factoryExport')}
    </button>
    {message && <p role="status">{t(message)}</p>}
    {error && <p role="alert">{t(error)} <button type="button" disabled={busy} onClick={() => void download()}>{t('retry')}</button></p>}
  </section>;
}
