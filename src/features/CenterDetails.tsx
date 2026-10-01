import ProductionTransfers from "./ProductionTransfers";
import { formatDuration } from "@/utils/production-flow.mjs";
import DowntimePlan from "./DowntimePlan";
import { downtimeMinutes } from "@/utils/manufacturing.mjs";
import { useState } from "react";
import { Badge, Dialog, Field, formatTime, localName } from "@/components/ui";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
export default function CenterDetails({
  center,
  onClose,
  ...props
}: FeatureProps & { center: Row; onClose: () => void }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [status, setStatus] = useState(String(center.status)),
    [busy, setBusy] = useState(false);
  const zone = String(s.factory?.timezone);
  const current =
    s.tables.work_centers.find((x) => x.id === center.id) || center;
  const order = s.tables.production_orders?.find(
    (x) => x.id === current.order_id,
  );
  const downtime = s.tables.downtime_events?.find(
    (x) => x.work_center_id === current.id && !x.ended_at,
  );
  const reasons = s.tables.downtime_reasons || [];
  const history = (s.tables.status_events || [])
    .filter((x) => x.work_center_id === current.id)
    .slice(0, 10);
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    const f = new FormData(e.currentTarget);
    try {
      await command("change_status", {
        factory: s.factory?.id,
        work_center: current.id,
        status,
        reason: null,
        sub_reason: null,
        notes: f.get("notes") || "",
        expected_restart: null,
        responsible: null,
        alternative: null,
        transferred: false,
      });
      onClose();
    } catch {
      // The shared command handler keeps a readable error visible.
    } finally {
      setBusy(false);
    }
  }
  const info = [
    ["code", current.code],
    [
      "line",
      localName(
        s.tables.production_lines?.find((x) => x.id === current.line_id),
        lang,
      ),
    ],
    [
      "product",
      localName(
        s.tables.products?.find((x) => x.id === order?.product_id),
        lang,
      ),
    ],
    ["orders", order?.code],
    [
      "operator",
      s.tables.memberships?.find((x) => x.id === current.operator_id)
        ?.display_name,
    ],
    ["target_quantity", order?.target_quantity],
    ["produced_quantity", order?.produced_quantity],
    ["rejected_quantity", order?.rejected_quantity],
    ["production_speed", current.production_speed],
    ["start_time", formatTime(current.start_time, lang, zone)],
    [
      "expected_finish",
      formatTime(current.expected_finish || order?.expected_finish, lang, zone),
    ],
    ["restart", formatTime(current.last_restart_time, lang, zone)],
  ];
  return (
    <Dialog title={localName(current, lang)} onClose={onClose} t={t}>
      <Badge status={String(current.status)} t={t} />
      <dl className="detail-grid">
        {info.map(([label, value]) => (
          <div key={String(label)}>
            <dt>{t(String(label))}</dt>
            <dd>{String(value ?? "—")}</dd>
          </div>
        ))}
      </dl>
      {downtime && (
        <div className="downtime-detail">
          <h3>
            {localName(
              reasons.find((x) => x.id === downtime.reason_id),
              lang,
            )}
          </h3>
          <p>
            {t("duration")}:{" "}
            {formatDuration(
              downtimeMinutes(
                downtime,
                downtime.started_at,
                new Date().toISOString(),
              ),
              lang,
            )}
          </p>
          <p>
            {t("started")}: {formatTime(downtime.started_at, lang, zone)}
          </p>
          <p>
            {t("expectedRestart")}:{" "}
            {formatTime(downtime.expected_restart, lang, zone)}
          </p>
          <p>{String(downtime.notes)}</p>
          <p>
            {t("subReason")}:{" "}
            {localName(
              reasons.find((x) => x.id === downtime.sub_reason_id),
              lang,
            )}
          </p>
          <p>
            {t("responsible")}:{" "}
            {String(
              s.tables.memberships?.find(
                (x) => x.id === downtime.responsible_id,
              )?.display_name || "—",
            )}
          </p>
          <p>
            {t("alternative")}:{" "}
            {localName(
              s.tables.work_centers?.find(
                (x) => x.id === downtime.alternative_id,
              ),
              lang,
            )}
          </p>
          <p>
            {t("transferred")}: {downtime.transferred ? "✓" : "—"}
          </p>
        </div>
      )}
      {downtime &&
        (can("downtime", "edit") || can("machine_status", "edit")) && (
          <DowntimePlan {...props} event={downtime} />
        )}
      {(can("centers", "edit") || can("machine_status", "edit")) && (
        <form onSubmit={submit}>
          <h3>{t("operatorView")}</h3>
          <div className="operator-actions">
            {["running", "idle", "offline"].map((x) => (
              <button
                type="button"
                className={status === x ? "selected" : ""}
                key={x}
                onClick={() => setStatus(x)}
              >
                <Badge status={x} t={t} />
              </button>
            ))}
          </div>
          <Field label={t("describeReason")}>
            <textarea
              name="notes"
              maxLength={2000}
            />
          </Field>
          <button
            className="primary"
            disabled={busy || status === current.status}
          >
            {t("changeStatus")}
          </button>
        </form>
      )}
      <ProductionTransfers {...props} center={current} />
      <h3>{t("history")}</h3>
      <ol className="timeline">
        {history.map((e) => (
          <li key={String(e.id)}>
            <time>{formatTime(e.created_at, lang, zone)}</time>
            <Badge status={String(e.new_status)} t={t} />
            <span>
              {e.reason_id
                ? localName(
                    reasons.find((r) => r.id === e.reason_id),
                    lang,
                  )
                : ""}
            </span>
            <p>{String(e.notes || "")}</p>
          </li>
        ))}
      </ol>
    </Dialog>
  );
}
