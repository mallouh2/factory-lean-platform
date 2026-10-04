import { useEffect, useRef, useState } from 'react';
import type { Snapshot } from '@/types';
import type { Command } from './types';
export type PermissionPackage = { id: string; name: string; name_ar: string; description: string; revision: number; permissions: string[]; assigned_count: number };
export type PermissionPackagePage = { packages: PermissionPackage[]; package_ids: string[]; direct: string[]; inherited: string[]; effective: string[]; can_manage: boolean };
export function usePermissionPackages(s: Snapshot, person = '') {
  const query = new URLSearchParams({ factory: String(s.factory?.id || ''), ...(person ? { person } : {}) }).toString();
  const [result, setResult] = useState<{query: string; data: PermissionPackagePage} | null>(null);
  const [busy, setBusy] = useState(false), [error, setError] = useState(''), [revision, setRevision] = useState(0);
  useEffect(() => {
    const abort = new AbortController(); setBusy(true); setError('');
    fetch('/api/permission-packages?' + query, { cache: 'no-store', signal: abort.signal }).then(async response => {
      const data = await response.json(); if (!response.ok) throw Error(data.error || 'dataWarning'); return data;
    }).then(data => { if (!abort.signal.aborted) setResult({ query, data }); })
      .catch(cause => { if (!abort.signal.aborted) setError(cause.message); })
      .finally(() => { if (!abort.signal.aborted) setBusy(false); });
    return () => abort.abort();
  }, [query, s.fetchedAt, revision]);
  return { data: result?.query === query ? result.data : null, busy, error, refresh: () => setRevision(v => v + 1) };
}
export function usePackageCommand(command: Command) {
  const submitting = useRef(false), [busy, setBusy] = useState(false), [error, setError] = useState('');
  async function run(name: string, args: Record<string, unknown>, success?: () => void) {
    if (submitting.current) return false;
    submitting.current = true; setBusy(true); setError('');
    try { await command(name, args); success?.(); return true; }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'error'); return false; }
    finally { submitting.current = false; setBusy(false); }
  }
  return { run, busy, error };
}
