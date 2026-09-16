import { useState } from "react";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
import { Field, localName, formatTime } from "@/components/ui";
export default function ProductionTransfers({
  center,
  ...props
}: FeatureProps & { center: Row }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [busy, setBusy] = useState(false);
  const history = (s.tables.production_transfers || []).filter(
    (x) => x.original_id === center.id || x.alternative_id === center.id,
  );
  const alternatives = (s.tables.work_center_alternatives || [])
    .filter((x) => x.work_center_id === center.id)
    .map((x) => s.tables.work_centers.find((c) => c.id === x.alternative_id))
    .filter((x): x is Row => !!x && !x.archived);
  return (
    <section>
      <h3>{t("productionTransfers")}</h3>
      {center.status === "stopped" &&
        can("centers", "edit") &&
        can("orders", "edit") &&
        !history.some((x) => x.original_id === center.id && !x.ended_at) && (
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              setBusy(true);
              try {
                await command("transfer_production", {
                  factory: s.factory?.id,
                  work_center: center.id,
                  alternative: f.get("alternative"),
                  reason: f.get("reason"),
                });
              } catch {
              } finally {
                setBusy(false);
              }
            }}
          >
            <p>{t("transferHelp")}</p>
            <Field label={t("alternative")}>
              <select name="alternative" required>
                <option value="">{t("chooseAlternative")}</option>
                {alternatives.map((a) => (
                  <option
                    key={String(a.id)}
                    value={String(a.id)}
                    disabled={
                      a.status !== "idle" ||
                      !!(a.order_id && a.order_id !== center.order_id)
                    }
                  >
                    {localName(a, lang)} · {t(String(a.status))}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={t("reason")}>
              <textarea name="reason" required minLength={3} maxLength={2000} />
            </Field>
            <button className="primary" disabled={busy || !center.order_id}>
              {t("transferProduction")}
            </button>
          </form>
        )}
      {!history.length && <p className="muted">{t("noTransfers")}</p>}
      <ol className="timeline">
        {history.map((x) => (
          <li key={String(x.id)}>
            <strong>
              {localName(
                s.tables.work_centers.find((c) => c.id === x.original_id),
                lang,
              )}{" "}
              →{" "}
              {localName(
                s.tables.work_centers.find((c) => c.id === x.alternative_id),
                lang,
              )}
            </strong>
            <p>
              {formatTime(x.created_at, lang, String(s.factory?.timezone))} ·{" "}
              {String(
                s.tables.production_orders?.find((o) => o.id === x.order_id)
                  ?.code || "—",
              )}
            </p>
            <p>{String(x.reason)}</p>
            <p>
              {t("responsible")}:{" "}
              {String(
                s.tables.memberships?.find((m) => m.user_id === x.created_by)
                  ?.display_name || x.created_by,
              )}
            </p>
            <p>
              {t("originalReturned")}:{" "}
              {formatTime(
                x.original_returned_at,
                lang,
                String(s.factory?.timezone),
              )}
            </p>
          </li>
        ))}
      </ol>
    </section>
  );
}
