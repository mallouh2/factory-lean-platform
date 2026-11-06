import { useEffect, useRef, useState } from 'react';
import type { Language, Translate } from '@/types';
import type { TableDataset } from '@/types/table-export';

type Props = { factory: string; dataset: TableDataset; filters: Record<string, unknown>; total: number;
  language: Language; t: Translate; disabled?: boolean; sort?: string; direction?: string; showScope?: boolean };
export default function TableExport({ factory, dataset, filters, total, language, t, disabled, sort, direction, showScope=true }: Props) {
  const menu = useRef<HTMLDetailsElement>(null), active = useRef<AbortController | null>(null);
  const popup = useRef<Window | null>(null);
  const [busy, setBusy] = useState(false), [error, setError] = useState(''), [message, setMessage] = useState('');
  const context = JSON.stringify({ factory, dataset, filters, language, sort, direction });
  useEffect(() => {
    setError(''); setMessage(''); setBusy(false);
    if (menu.current) menu.current.open = false;
    return () => { active.current?.abort(); active.current = null; popup.current?.close(); popup.current = null; };
  }, [context]);
  useEffect(() => {
    function outside(event: PointerEvent) { if (!menu.current?.contains(event.target as Node) && menu.current) menu.current.open = false; }
    document.addEventListener('pointerdown', outside);
    return () => document.removeEventListener('pointerdown', outside);
  }, []);
  async function run(format: 'excel' | 'print') {
    if (active.current || disabled) return;
    if (menu.current) menu.current.open = false;
    menu.current?.querySelector('summary')?.focus();
    setError(''); setMessage('');
    const abort = new AbortController(); active.current = abort;
    let preview: Window | null = null;
    try {
      if (format === 'print') {
        // Open during the user's click, before asynchronous fetching triggers popup blocking.
        preview = window.open('', '_blank');
        if (!preview) throw Error('tableExportPopup');
        preview.opener = null; preview.document.title = t('tableExportPreparing');
        preview.document.body.textContent = t('tableExportPreparing'); popup.current = preview;
      }
      setBusy(true);
      const response = await fetch('/api/table-export', { method: 'POST', signal: abort.signal,
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ factory, dataset, filters, language, format, sort, direction }) });
      if (!response.ok) { const data = await response.json(); throw Error(data.error || 'dataWarning'); }
      if (format === 'print') {
        const html = await response.text();
        if (abort.signal.aborted || !preview || preview.closed) return;
        preview.document.open(); preview.document.write(html); preview.document.close();
        await preview.document.fonts.ready;
        if (abort.signal.aborted || preview.closed) return;
        const button = preview.document.createElement('button'); button.className = 'print-controls';
        button.textContent = t('tableExportPrint'); button.onclick = () => preview?.print();
        preview.document.body.prepend(button); preview.focus(); preview.print(); popup.current = null;
      } else {
        const blob = await response.blob(); if (abort.signal.aborted) return;
        const url = URL.createObjectURL(blob), link = document.createElement('a');
        link.href = url;
        link.download = response.headers.get('Content-Disposition')?.match(/filename="([a-z0-9-]+\.xlsx)"/)?.[1] || `${dataset}.xlsx`;
        document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000);
      }
      setMessage('tableExportReady');
    } catch (cause) {
      preview?.close(); if (popup.current === preview) popup.current = null;
      if (!abort.signal.aborted) {
        const key = cause instanceof Error ? cause.message : '';
        setError(/^(tableExport(PrintLimit|ExcelLimit|Changed|Precision|Cancelled|Popup)|unauthorized|permissionError|dataWarning|error)$/.test(key) ? key : 'dataWarning');
      }
    } finally { if (active.current === abort) { active.current = null; setBusy(false); } }
  }
  return <div className="table-export" dir={language === 'ar' ? 'rtl' : 'ltr'}>
    <div className="table-export-tools">{showScope&&<small className="muted">{t('tableExportScope')} · {total.toLocaleString(language)} {t('tableExportRows')}</small>}
      <details ref={menu} onKeyDown={event => { if (event.key === 'Escape' && event.currentTarget.open) { event.preventDefault(); event.currentTarget.open = false; event.currentTarget.querySelector('summary')?.focus(); } }}>
        <summary aria-disabled={busy || disabled} onClick={event => { if (busy || disabled) event.preventDefault(); }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M12 3v12m-4-4 4 4 4-4M4 16v5h16v-5"/></svg>
          {t(busy ? 'tableExportPreparing' : 'tableExport')} <span aria-hidden="true">⌄</span>
        </summary>
        <div className="table-export-menu"><button type="button" disabled={busy || disabled} onClick={() => void run('excel')}><span aria-hidden="true">▦</span> {t('tableExportExcel')}</button>
          <button type="button" disabled={busy || disabled} onClick={() => void run('print')}><span aria-hidden="true">▤</span> {t('tableExportPrint')}</button></div>
      </details>
    </div>
    {busy && <p role="status">{t('tableExportPreparing')}</p>}{message && <p role="status">{t(message)}</p>}
    {error && <p role="alert">{t(error)} <button type="button" disabled={busy} onClick={() => { setError(''); if (menu.current) { menu.current.open = true; menu.current.querySelector('button')?.focus(); } }}>{t('retry')}</button></p>}
  </div>;
}
