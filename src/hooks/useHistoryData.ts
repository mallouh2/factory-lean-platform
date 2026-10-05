import { useEffect, useState } from "react";

/** A stable identity may retain the same working view as a live time window advances. */
export function useHistoryData<T>(url: string | null, revision: string, identity: string | null = url) {
  const [state, setState] = useState<{ url: string | null; identity: string | null; data: T | null;
    loading: boolean; error: string }>({ url: null, identity: null, data: null, loading: false, error: "" });
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    if (!url) return;
    const controller = new AbortController();
    setState(previous => ({ url, identity, data: previous.identity === identity ? previous.data : null,
      loading: true, error: "" }));
    void (async () => {
      try {
        const response = await fetch(url, { signal: controller.signal, cache: "no-store" });
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || "dataWarning");
        if (!controller.signal.aborted) setState(previous => ({ url, identity,
          data: previous.identity === identity && JSON.stringify(previous.data) === JSON.stringify(body) ? previous.data : body,
          loading: false, error: "" }));
      } catch (cause) {
        if (!controller.signal.aborted) setState(previous => ({ ...previous,
          data: identity !== url ? previous.data : null, loading: false,
          error: cause instanceof Error ? cause.message : "dataWarning" }));
      }
    })();
    return () => controller.abort();
  }, [url, identity, revision, retry]);
  const visible = url && state.identity === identity ? state : { url, data: null, loading: Boolean(url), error: "" };
  return { ...visible, reload: () => setRetry(value => value + 1) };
}
