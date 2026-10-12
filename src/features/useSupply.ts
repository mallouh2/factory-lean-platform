import { useEffect, useRef, useState } from 'react';
import type { Snapshot } from '@/types';
export type SupplyRow = Record<string, unknown>;
export type SupplyPage = { rows: SupplyRow[]; total: number; selected: SupplyRow | null };
export function useSupply<T = SupplyPage>(snapshot: Snapshot, mode: string, extra: Record<string, string> = {}, enabled = true, endpoint='/api/supply') {
  const query = endpoint+'?'+new URLSearchParams({ factory: String(snapshot.factory?.id || ''), mode, ...extra }).toString();
  const [result, setResult] = useState<{ query: string; data: T } | null>(null);
  const [busy, setBusy] = useState(false), [error, setError] = useState(''), [revision, setRevision] = useState(0);
  useEffect(() => {
    if (!enabled) return;
    const abort = new AbortController(); setBusy(true); setError('');
    fetch(query, { cache: 'no-store', signal: abort.signal }).then(async response => {
      const data = await response.json(); if (!response.ok) throw Error(data.error || 'dataWarning'); return data;
    }).then(data => { if (!abort.signal.aborted) setResult({ query, data }); })
      .catch(cause => { if (!abort.signal.aborted) setError(cause.message); })
      .finally(() => { if (!abort.signal.aborted) setBusy(false); });
    return () => abort.abort();
  }, [query, enabled, snapshot.fetchedAt, revision]);
  return { data: enabled && result?.query === query ? result.data : null, busy, error, refresh: () => setRevision(value => value + 1) };
}
export function useSupplyCommand(command: (name: string, args: Record<string, unknown>) => Promise<unknown>, factory: unknown, rpcName:'supply_command'|'quality_command'='supply_command') {
  const retry = useRef<{ key: string; id: string } | null>(null), submitting = useRef(false);
  const [busy, setBusy] = useState(false), [error, setError] = useState('');
  async function run(action: string, payload: Record<string, unknown>, onSuccess?: (result: unknown) => void) {
    if (submitting.current) return false;
    const key = JSON.stringify([factory, action, payload]); if (retry.current?.key !== key) retry.current = { key, id: crypto.randomUUID() };
    submitting.current = true; setBusy(true); setError('');
    try { const result = await command(rpcName, { factory, [rpcName==='quality_command'?'operation':'action']:action, payload, request_id: retry.current.id }); retry.current = null; onSuccess?.(result); return true; }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'error'); return false; }
    finally { submitting.current = false; setBusy(false); }
  }
  return { run, busy, error, clearError: () => setError('') };
}
