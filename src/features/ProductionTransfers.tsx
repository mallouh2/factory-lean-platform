import { useRef, useState } from "react";
import { liveTransferPicker } from "@/utils/floor-visual.mjs";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
import { Field, localName, formatTime } from "@/components/ui";
export default function ProductionTransfers({
  center,
  ...props
}: FeatureProps & { center: Row }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [busy, setBusy] = useState(false);
  const submitting = useRef(false);
  const history = (s.tables.production_transfers || []).filter(
    (x) => x.original_id === center.id || x.alternative_id === center.id,
  );
  const configured = (s.tables.work_center_alternatives || [])
    .filter((x) => x.work_center_id === center.id)
    .map((x) => String(x.alternative_id));
  const picker = liveTransferPicker(center, s.tables.work_centers, configured,
    s.tables.production_transfers || [], s.tables.production_orders || [],
    s.tables.production_lines || [], s.tables.work_center_capabilities || [], s.tables.downtime_events || []);
  const alternatives: Row[] = picker.candidates;
  const homeLine = (c: Row | undefined) => localName(s.tables.production_lines?.find(l => l.id === c?.line_id), lang);
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
              if (submitting.current) return;
              const f = new FormData(e.currentTarget);
              if (picker.blockedReason || !alternatives.some(a => a.id === f.get("alternative"))) return;
              submitting.current = true;
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
                submitting.current = false;
                setBusy(false);
              }
            }}
          >
            <p>{t("transferHelp")}</p>
            {picker.blockedReason && <p role="status" className="notice">{t(picker.blockedReason)}</p>}
            {!picker.blockedReason && !alternatives.length && <p role="status" className="notice">{t("transferNoCompatibleAvailable")}</p>}
            <fieldset disabled={busy || !!picker.blockedReason || !alternatives.length}>
            <Field label={t("alternative")}>
              <select name="alternative" required>
                <option value="">{t("chooseAlternative")}</option>
                {alternatives.map((a) => (
                  <option
                    key={String(a.id)}
                    value={String(a.id)}
                  >
                    {localName(a, lang)} · {homeLine(a)} · {t(String(a.status))}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={t("reason")}>
              <textarea name="reason" required minLength={3} maxLength={2000} />
            </Field>
            <button className="primary" disabled={busy || !center.order_id}>
              {t(busy ? "updating" : "transferProduction")}
            </button>
            </fieldset>
          </form>
        )}
      {!history.length && <p className="muted">{t("noTransfers")}</p>}
      {!!history.length && <details className="machine-secondary" open={history.some(x => !x.ended_at)}><summary>{t("transferHistory")}</summary>
      <ol className="timeline">
        {history.map((x) => (
          <li key={String(x.id)}>
            <strong>
              {localName(
                s.tables.work_centers.find((c) => c.id === x.original_id),
                lang,
              )}{" "}
              <span aria-hidden="true">{lang === "ar" ? "←" : "→"}</span>{" "}
              {localName(
                s.tables.work_centers.find((c) => c.id === x.alternative_id),
                lang,
              )}
            </strong>
            <p>{t(x.ended_at ? "transferEnded" : "transferOpen")}</p>
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
            {x.ended_at && <p>{t("transferEnded")}: {formatTime(x.ended_at, lang, String(s.factory?.timezone))}</p>}
          </li>
        ))}
      </ol>
      </details>}
    </section>
  );
}
