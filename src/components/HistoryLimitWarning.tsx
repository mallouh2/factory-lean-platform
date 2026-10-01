import type { Snapshot, Translate } from "@/types";

/** A shared snapshot limit matters only to the history this surface consumes. */
export default function HistoryLimitWarning({ snapshot, tables, t }: {
  snapshot: Snapshot;
  tables: readonly string[];
  t: Translate;
}) {
  if (!tables.some((table) => snapshot.truncatedTables?.includes(table))) return null;
  return <div className="toast" role="alert">{t("truncatedData")}</div>;
}
