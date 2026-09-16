import { useState } from "react";
import { Field, localName } from "@/components/ui";
import {
  formatLocalInput,
  localDateTimeToUtc,
} from "@/utils/manufacturing.mjs";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
export default function DowntimePlan({
  event,
  ...props
}: FeatureProps & { event: Row }) {
  const { snapshot: s, t, lang, command } = props;
  const [busy, setBusy] = useState(false);
  const zone = String(s.factory?.timezone);
  return (
    <details className="restart-plan">
      <summary>{t("updateRestartPlan")}</summary>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          const f = new FormData(e.currentTarget);
          try {
            await command("update_downtime", {
              factory: s.factory?.id,
              id: event.id,
              expected_restart: f.get("eta")
                ? localDateTimeToUtc(String(f.get("eta")), zone)
                : null,
              notes: f.get("notes"),
              responsible: f.get("responsible") || null,
              alternative: f.get("alternative") || null,
              transferred: false,
            });
          } catch {
          } finally {
            setBusy(false);
          }
        }}
      >
        <Field label={`${t("expectedRestart")} (${zone})`}>
          <input
            name="eta"
            type="datetime-local"
            defaultValue={
              event.expected_restart
                ? formatLocalInput(String(event.expected_restart), zone)
                : ""
            }
          />
        </Field>
        <Field label={t("responsible")}>
          <select
            name="responsible"
            defaultValue={String(event.responsible_id || "")}
          >
            <option value="">{t("unassigned")}</option>
            {(s.tables.memberships || [])
              .filter((m) => m.status === "approved")
              .map((m) => (
                <option key={String(m.id)} value={String(m.id)}>
                  {String(m.display_name)}
                </option>
              ))}
          </select>
        </Field>
        <Field label={t("alternative")}>
          <select
            name="alternative"
            defaultValue={String(event.alternative_id || "")}
          >
            <option value="">{t("unassigned")}</option>
            {(s.tables.work_centers || [])
              .filter((c) => c.id !== event.work_center_id && !c.archived)
              .map((c) => (
                <option key={String(c.id)} value={String(c.id)}>
                  {localName(c, lang)}
                </option>
              ))}
          </select>
        </Field>

        <Field label={t("notes")}>
          <textarea
            name="notes"
            maxLength={2000}
            defaultValue={String(event.notes || "")}
          />
        </Field>
        <button className="primary" disabled={busy}>
          {t("save")}
        </button>
      </form>
    </details>
  );
}
