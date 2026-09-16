import { useState } from "react";
import type { FeatureProps } from "./types";
import { localName, formatTime, Empty, Field } from "@/components/ui";
import { reportPeriod, localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import { formatDuration, rankDowntime } from "@/utils/production-flow.mjs";
type ImpactEvent = import("@/types").Row & {
  score: number;
  minutes: number;
  lostUnits: number | null;
};
const colors = [
  "#0f766e",
  "#b45309",
  "#2563eb",
  "#9333ea",
  "#be123c",
  "#475569",
];
export default function DowntimeAnalysis({
  snapshot: s,
  t,
  lang,
}: FeatureProps) {
  const [period, setPeriod] = useState("today"),
    [line, setLine] = useState(""),
    [machine, setMachine] = useState(""),
    [area, setArea] = useState(""),
    [reason, setReason] = useState(""),
    [selected, setSelected] = useState(""),
    [from, setFrom] = useState(""),
    [to, setTo] = useState("");
  const zone = String(s.factory?.timezone),
    range = reportPeriod(period === "custom" ? "today" : period, zone);
  const start =
    period === "custom" && from
      ? localDateTimeToUtc(from + "T00:00", zone)
      : range.from;
  const end =
    period === "custom" && to
      ? localDateTimeToUtc(
          new Date(Date.parse(to + "T00:00:00Z") + 86400000)
            .toISOString()
            .slice(0, 10) + "T00:00",
          zone,
        )
      : range.to;
  const events = (s.tables.downtime_events || []).filter((e) => {
    const c = s.tables.work_centers?.find((c) => c.id === e.work_center_id);
    return (
      (!machine || e.work_center_id === machine) &&
      (!line || (e.line_id || c?.line_id) === line) &&
      (!area || c?.area_id === area) &&
      (!reason || e.reason_id === reason)
    );
  });
  const groups = rankDowntime(
      events,
      start,
      end,
      s.factory || {},
      Date.now(),
      s.tables.production_transfers || [],
    ),
    total = groups.reduce((n, g) => n + g.score, 0);
  let angle = 0;
  const segments = groups
    .map((g, i) => {
      const a = angle;
      angle += (g.score / total) * 100;
      return `${colors[i % colors.length]} ${a}% ${angle}%`;
    })
    .join(",");
  const focused = groups.find((g) => g.reason_id === selected);
  return (
    <section className="panel">
      <h2>{t("impactRankedDowntime")}</h2>
      <p>{t("impactHelp")}</p>
      <div className="filters">
        <Field label={t("period")}>
          <select value={period} onChange={(e) => setPeriod(e.target.value)}>
            {["today", "yesterday", "week", "month", "custom"].map((p) => (
              <option key={p} value={p}>
                {t(p)}
              </option>
            ))}
          </select>
        </Field>
        {period === "custom" && (
          <>
            <input
              aria-label={t("from")}
              type="date"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
            />
            <input
              aria-label={t("to")}
              type="date"
              value={to}
              onChange={(e) => setTo(e.target.value)}
            />
          </>
        )}
        {[
          ["area", s.tables.areas || [], area, setArea],
          ["line", s.tables.production_lines || [], line, setLine],
          ["machine", s.tables.work_centers || [], machine, setMachine],
          ["reason", s.tables.downtime_reasons || [], reason, setReason],
        ].map(([key, rows, value, setter]) => (
          <Field key={String(key)} label={t(String(key))}>
            <select
              value={String(value)}
              onChange={(e) => (setter as (x: string) => void)(e.target.value)}
            >
              <option value="">{t("all")}</option>
              {(rows as typeof events).map((r) => (
                <option value={String(r.id)} key={String(r.id)}>
                  {localName(r, lang)}
                </option>
              ))}
            </select>
          </Field>
        ))}
      </div>
      {!groups.length ? (
        <Empty t={t} />
      ) : (
        <div className="impact-layout">
          <div
            className="donut"
            role="img"
            aria-label={t("reasonDistribution")}
            style={{ background: `conic-gradient(${segments})` }}
          >
            <span>{t("operationalImpact")}</span>
          </div>
          <ol className="impact-ranking">
            {groups.map((g, i) => (
              <li key={g.reason_id}>
                <button
                  aria-pressed={selected === g.reason_id}
                  onClick={() => setSelected(String(g.reason_id))}
                >
                  <span
                    className="chart-dot"
                    style={{ background: colors[i % colors.length] }}
                  />
                  <strong>
                    {localName(
                      s.tables.downtime_reasons?.find(
                        (r) => r.id === g.reason_id,
                      ),
                      lang,
                    )}
                  </strong>
                  <span>
                    {Math.round((g.score / total) * 100)}% ·{" "}
                    {formatDuration(g.minutes, lang)} · {g.events.length}{" "}
                    {t("occurrences")}
                  </span>
                </button>
              </li>
            ))}
          </ol>
        </div>
      )}
      {focused && (
        <div className="table-wrap">
          <h3>
            {localName(
              s.tables.downtime_reasons.find((r) => r.id === focused.reason_id),
              lang,
            )}
          </h3>
          <table>
            <thead>
              <tr>
                {[
                  "machine",
                  "line",
                  "duration",
                  "time",
                  "orders",
                  "notes",
                  "estimatedLostUnits",
                ].map((k) => (
                  <th key={k}>{t(k)}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {focused.events
                .sort((a: ImpactEvent, b: ImpactEvent) => b.score - a.score)
                .map((e: ImpactEvent) => (
                  <tr key={String(e.id)}>
                    <td>
                      {localName(
                        s.tables.work_centers.find(
                          (c) => c.id === e.work_center_id,
                        ),
                        lang,
                      )}
                    </td>
                    <td>
                      {localName(
                        s.tables.production_lines.find(
                          (l) => l.id === e.line_id,
                        ),
                        lang,
                      )}
                    </td>
                    <td>{formatDuration(e.minutes, lang)}</td>
                    <td>
                      {formatTime(e.started_at, lang, zone)} —{" "}
                      {formatTime(e.ended_at, lang, zone)}
                    </td>
                    <td>
                      {String(
                        s.tables.production_orders.find(
                          (o) => o.id === e.order_id,
                        )?.code || "—",
                      )}
                    </td>
                    <td>{String(e.notes)}</td>
                    <td>
                      {e.lostUnits === null
                        ? t("insufficient")
                        : Math.round(e.lostUnits).toLocaleString(lang)}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      )}
      <details>
        <summary>{t("impactMethod")}</summary>
        <p>
          {t("impactMethodHelp")} {String(s.factory?.impact_blocking_weight)} /{" "}
          {String(s.factory?.impact_frequency_minutes)}
        </p>
      </details>
    </section>
  );
}
