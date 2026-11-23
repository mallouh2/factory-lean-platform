import { useEffect, useRef, useState } from "react";

/** A stable identity may retain the same working view as a live time window advances. */
export function useHistoryData<T>(url: string | null, revision: string, identity: string | null = url,
  quiet = false) {
  const [state, setState] = useState<{ url: string | null; identity: string | null; data: T | null;
    loading: boolean; error: string }>({ url: null, identity: null, data: null, loading: false, error: "" });
  const [retry, setRetry] = useState(0);
  const pending = useRef(Promise.resolve());
  useEffect(() => {
    if (!url) return;
    const controller = new AbortController();
    let obsolete = false;
    async function read() {
      if (obsolete || !url) return;
      setState(previous => ({ url, identity, data: previous.identity === identity ? previous.data : null,
        loading: !quiet || previous.identity !== identity || !previous.data, error: "" }));
      let status: number | undefined;
      try {
        const response = await fetch(url, {
          signal: quiet ? AbortSignal.timeout(20_000) : controller.signal, cache: "no-store",
        });
        status = response.status;
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || "dataWarning");
        if (!obsolete) setState(previous => ({ url, identity,
          data: previous.identity === identity && JSON.stringify(previous.data) === JSON.stringify(body) ? previous.data : body,
          loading: false, error: "" }));
      } catch (cause) {
        if (!obsolete) setState(previous => ({ ...previous,
          data: quiet ? ([401, 403, 404].includes(status || 0) ? null : previous.data)
            : identity !== url ? previous.data : null, loading: false,
          error: cause instanceof Error ? cause.message : "dataWarning" }));
      }
    }
    if (quiet) pending.current = pending.current.then(read);
    else void read();
    return () => { obsolete = true; if (!quiet) controller.abort(); };
  }, [url, identity, revision, retry, quiet]);
  const visible = url && state.identity === identity ? state : { url, data: null, loading: Boolean(url), error: "" };
  return { ...visible, reload: () => setRetry(value => value + 1) };
}
