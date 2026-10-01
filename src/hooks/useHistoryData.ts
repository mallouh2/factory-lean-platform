import { useEffect, useState } from "react";

/** Mounted-page reads only. URL changes mask old data; aborted replies never win. */
export function useHistoryData<T>(url: string | null, revision: string) {
  const [state, setState] = useState<{ url: string | null; data: T | null;
    loading: boolean; error: string }>({ url: null, data: null, loading: false, error: "" });
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    if (!url) return;
    const controller = new AbortController();
    setState(previous => ({ url, data: previous.url === url ? previous.data : null,
      loading: true, error: "" }));
    void (async () => {
      try {
        const response = await fetch(url, { signal: controller.signal, cache: "no-store" });
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || "dataWarning");
        if (!controller.signal.aborted) setState({ url, data: body, loading: false, error: "" });
      } catch (cause) {
        if (!controller.signal.aborted) setState(previous => ({ ...previous,
          data: null, loading: false, error: cause instanceof Error ? cause.message : "dataWarning" }));
      }
    })();
    return () => controller.abort();
  }, [url, revision, retry]);
  const visible = state.url === url ? state : { url, data: null, loading: Boolean(url), error: "" };
  return { ...visible, reload: () => setRetry(value => value + 1) };
}
