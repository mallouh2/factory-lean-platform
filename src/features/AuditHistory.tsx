import { useState } from "react";
import { Empty, formatTime } from "@/components/ui";
import HistoryQueryState from "@/components/HistoryQueryState";
import { useHistoryData } from "@/hooks/useHistoryData";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";

export default function AuditHistory({ snapshot: s, t, lang }: FeatureProps) {
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const query = new URLSearchParams({ factory: String(s.factory!.id), search, page: String(page) });
  const history = useHistoryData<{ rows: Row[]; total: number; page: number; pages: number }>(
    `/api/audit-history?${query}`, s.fetchedAt);
  return <section className="panel">
    <header className="section-head"><h2>{t("audit")}</h2>
      <input aria-label={t("search")} placeholder={t("search")} value={search}
        maxLength={2000} onChange={e => { setSearch(e.target.value); setPage(1); }} />
    </header>
    <HistoryQueryState {...history} t={t} />
    {history.data && <>
      <p>{t("historyRecords")}: {history.data.total.toLocaleString(lang)}</p>
      {!history.data.rows.length ? <Empty t={t} /> : <div className="table-wrap"><table>
        <thead><tr>{["time", "userId", "action", "entity", "oldValue", "newValue"].map(key =>
          <th key={key}>{t(key)}</th>)}</tr></thead>
        <tbody>{history.data.rows.map(row => <tr key={String(row.id)}>
          <td>{formatTime(row.created_at, lang, String(s.factory!.timezone))}</td>
          <td>{String(s.tables.memberships?.find(m => m.user_id === row.actor_id)?.display_name || row.actor_id || "—")}</td>
          <td>{String(row.action)}</td><td>{String(row.entity)}</td>
          <td><details><summary>{t("view")}</summary><pre>{JSON.stringify(row.old_data, null, 2)}</pre></details></td>
          <td><details><summary>{t("view")}</summary><pre>{JSON.stringify(row.new_data, null, 2)}</pre></details></td>
        </tr>)}</tbody>
      </table></div>}
      <nav className="history-pagination" aria-label={t("auditPages")}>
        <button disabled={history.loading || page <= 1} onClick={() => setPage(value => value - 1)}>{t("previous")}</button>
        <span>{page.toLocaleString(lang)} / {history.data.pages.toLocaleString(lang)}</span>
        <button disabled={history.loading || page >= history.data.pages} onClick={() => setPage(value => value + 1)}>{t("next")}</button>
      </nav>
    </>}
  </section>;
}
