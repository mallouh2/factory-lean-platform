import type { Translate } from "@/types";

export default function HistoryQueryState({ loading, error, reload, t }:
  { loading: boolean; error: string; reload: () => void; t: Translate }) {
  return <>
    {loading && <p role="status">{t("historyLoading")}</p>}
    {error && <div role="alert" className="toast"><span>{t(error)}</span>
      <button type="button" onClick={reload}>{t("refresh")}</button></div>}
  </>;
}
