import ProductionTransfers from "./ProductionTransfers";
import ProductionLineTransfer from './ProductionLineTransfer';
import ProductionReturn from './ProductionReturn';
import {executionLine} from '@/utils/execution-selection.mjs';
import { evaluateFlow, formatDuration } from "@/utils/production-flow.mjs";
import { impactChoice } from "@/utils/floor-visual.mjs";
import DowntimePlan from "./DowntimePlan";
import { downtimeMinutes } from "@/utils/manufacturing.mjs";
import { useRef, useState } from "react";
import { Badge, Dialog, Field, formatTime, localName } from "@/components/ui";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
import MaintenanceContext from './MaintenanceRequest';
export default function CenterDetails({
  center,
  onClose,
  ...props
}: FeatureProps & { center: Row; onClose: () => void }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [status, setStatus] = useState(String(center.status)),
    [busy, setBusy] = useState(false);
  const submitting = useRef(false);
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
  const returnReady = !(s.tables.production_transfers || []).some(x=>x.original_id===current.id&&!x.ended_at);
  const borrowed = s.tables.production_transfers?.find(x => x.alternative_id === current.id && !x.ended_at);
  const original = s.tables.work_centers.find(x => x.id === borrowed?.original_id);
  const flow = evaluateFlow(s.tables.work_centers, s.tables.downtime_events || [], s.tables.production_transfers || []);
  const availability = borrowed ? "machineBorrowed" : ["stopped", "offline", "setup"].includes(String(current.status)) ? "machineUnavailable" : current.order_id ? "machineAssigned" : current.status === "idle" ? "machineAvailable" : "machineUnavailable";
  const history = (s.tables.status_events || [])
    .filter((x) => x.work_center_id === current.id)
    .slice(0, 10);
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (submitting.current) return;
    if (status === "running" && !returnReady) return;
    submitting.current = true;
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
      submitting.current = false;
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
      <p className="machine-availability">{t(availability)}{borrowed && <> · {t("line")}: {localName(s.tables.production_lines?.find(l => l.id === original?.line_id), lang)}</>}</p>
      <p>{t("machineStopImpact")}: {t(impactChoice(current.dependency_mode, current.impact_scope))}</p>
      {flow[String(current.id)]?.state === "blocked" && <p role="status" className="notice">{t("machineFlowBlocked")}</p>}
      <dl className="detail-grid">
        {info.slice(0, 4).map(([label, value]) => (
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
          {!returnReady && <p role="status" className="notice">{t("f48UseReturn")}</p>}
          <fieldset disabled={busy}><div className="operator-actions">
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
            disabled={busy || status === current.status || status === "running" && !returnReady}
          >
            {t("changeStatus")}
          </button>
          </fieldset>
        </form>
      )}
      <ProductionReturn props={props} center={current} onReturned={onClose}/>
      <ProductionTransfers {...props} center={current} />
      {current.status==='stopped'&&current.line_id&&can('orders','view')&&<ProductionLineTransfer props={props} source={current} orders={(s.tables.production_orders||[]).filter(o=>executionLine(o)===current.line_id&&['planned','active'].includes(String(o.status))&&!o.actual_finish)} preferred={String(order?.id||'')} onTransferred={()=>onClose()}/>}
      <details className="machine-secondary"><summary>{t("machineProductionDetails")}</summary><dl className="detail-grid">{info.slice(4).map(([label,value])=><div key={String(label)}><dt>{t(String(label))}</dt><dd>{String(value ?? "—")}</dd></div>)}</dl></details>
      <details className="machine-secondary"><summary>{t("maintenance")}</summary>
      <MaintenanceContext {...props} key={String(current.id)} machine={current} />
      </details>
      <details className="machine-secondary"><summary>{t("history")}</summary>
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
      </details>
    </Dialog>
  );
}
