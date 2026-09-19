import { formatDuration, evaluateFlow } from "@/utils/production-flow.mjs";
import { useState } from "react";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
import { Badge, Empty, localName } from "@/components/ui";
import { reportPeriod } from "@/utils/manufacturing.mjs";
export default function Dashboard(
  props: FeatureProps & {
    onCenter: (row: Row) => void;
    onNavigate: (view: string) => void;
  },
) {
  const { snapshot: s, t, lang, onCenter, onNavigate } = props;
  const [filter, setFilter] = useState("all");
  const [line, setLine] = useState("all");
  const [search, setSearch] = useState("");
  const centers = (s.tables.work_centers || []).filter((x) => !x.archived),
    orders = s.tables.production_orders || [],
    stops = s.tables.downtime_events || [];
  const period = reportPeriod(
    "today",
    String(s.factory?.timezone || "Asia/Qatar"),
  );
  const flow = evaluateFlow(
    centers,
    stops,
    s.tables.production_transfers || [],
  );
  const active = orders.filter((o) => o.status === "active");
  // "Today" always means the factory's own calendar day, DST included.
  const entries = (s.tables.production_entries || []).filter(
    (e) =>
      String(e.created_at) >= period.from &&
      String(e.created_at) < period.to,
  );
  const total = entries.reduce((n, e) => n + Number(e.produced), 0),
    delayed = active.filter(
      (x) =>
        x.expected_finish &&
        Date.parse(String(x.expected_finish)) < Date.now(),
    ).length;
  const lines = (s.tables.production_lines || []).filter((x) => !x.archived);
  const lineSummary = (lineId: string) => {
    const orderIds = new Set(
      orders
        .filter((o) => String(o.line_id) === String(lineId))
        .map((o) => String(o.id)),
    );
    const centerIds = new Set(
      centers
        .filter((c) => String(c.line_id) === String(lineId))
        .map((c) => String(c.id)),
    );
    const output = entries
      .filter(
        (e) =>
          orderIds.has(String(e.order_id)) ||
          centerIds.has(String(e.work_center_id)),
      )
      .reduce((n, e) => n + Number(e.produced), 0);
    const order = active.find((o) => String(o.line_id) === String(lineId));
    const product = s.tables.products?.find(
      (p) => p.id === order?.product_id,
    );
    return { order, product, output };
  };
  const kpis = [
    {
      label: "productionLines",
      value: lines.length,
      action: () => onNavigate("lines"),
      color: "blue",
    },
    {
      label: "activeOrders",
      value: active.length,
      action: () => onNavigate("orders"),
      color: "green",
    },
    {
      label: "delayedOrders",
      value: delayed,
      action: () => onNavigate("orders"),
      color: "red",
    },
    {
      label: "todayProduction",
      value: total.toLocaleString(lang),
      action: () => onNavigate("orders"),
      color: "orange",
    },
  ];
  const groups = [...lines, { id: "independent", name: t("independent") }];
  const visible = centers.filter(
    (x) =>
      (filter === "all" || x.status === filter) &&
      (line === "all" || x.line_id === line) &&
      (localName(x, lang) + " " + x.code)
        .toLowerCase()
        .includes(search.toLowerCase()),
  );
  return (
    <>
      <div className="kpis">
        {kpis.map((k) => (
          <button
            className={`kpi accent-${k.color}`}
            key={k.label}
            onClick={k.action}
          >
            <span>{t(k.label)}</span>
            <strong>
              <bdi dir="ltr">{k.value}</bdi>
            </strong>
            <small aria-hidden="true">↗</small>
          </button>
        ))}
      </div>
      <section className="panel floor-panel">
        <header className="section-head">
          <div>
            <p className="eyebrow">{t("live")}</p>
            <h2>{t("floor")}</h2>
          </div>
          <div className="filters">
            <input
              aria-label={t("search")}
              placeholder={t("search")}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <select
              aria-label={t("line")}
              value={line}
              onChange={(e) => setLine(e.target.value)}
            >
              <option value="all">{t("all")}</option>
              {lines.map((x) => (
                <option value={String(x.id)} key={String(x.id)}>
                  {localName(x, lang)}
                </option>
              ))}
            </select>
          </div>
        </header>
        <div className="status-tabs">
          {["all", "running", "stopped", "setup", "idle", "offline"].map(
            (x) => (
              <button
                className={filter === x ? "selected" : ""}
                onClick={() => setFilter(x)}
                key={x}
              >
                {t(x)}
                <span>
                  {x === "all"
                    ? centers.length
                    : centers.filter((c) => c.status === x).length}
                </span>
              </button>
            ),
          )}
        </div>
        {!visible.length && <Empty t={t} />}
        <div className="lines-floor">
          {groups.map((group) => {
            const machines = visible
              .filter((x) =>
                group.id === "independent"
                  ? !x.line_id
                  : x.line_id === group.id,
              )
              .sort((a, b) => Number(a.position) - Number(b.position));
            if (!machines.length) return null;
            const summary =
              group.id === "independent" ? null : lineSummary(String(group.id));
            return (
              <section className="line-floor" key={String(group.id)}>
                <div className="line-heading">
                  <h3>{localName(group, lang)}</h3>
                  <span>
                    {machines.length} {t("centers")}
                  </span>
                </div>
                {summary && (
                  <p className="line-detail">
                    <bdi dir="ltr">
                      {summary.product || summary.order
                        ? `${
                            summary.product
                              ? localName(summary.product, lang)
                              : t("unassigned")
                          } · ${
                            summary.order ? String(summary.order.code) : "—"
                          }`
                        : t("unassigned")}
                    </bdi>
                    {" · "}
                    {t("todayProduction")}:{" "}
                    <bdi dir="ltr">
                      {summary.output.toLocaleString(lang)}
                    </bdi>
                  </p>
                )}
                <div className="machine-flow">
                  {machines.map((center) => {
                    const order = orders.find((o) => o.id === center.order_id),
                      product = s.tables.products?.find(
                        (p) => p.id === order?.product_id,
                      );
                    const stop = stops.find(
                      (x) => x.work_center_id === center.id && !x.ended_at,
                    );
                    const reason = s.tables.downtime_reasons?.find(
                      (r) => r.id === stop?.reason_id,
                    );
                    return (
                      <button
                        className={`machine-card machine-${center.status}`}
                        key={String(center.id)}
                        onClick={() => onCenter(center)}
                      >
                        <div className="machine-top">
                          <span className="machine-icon" aria-hidden="true">
                            {center.type === "machine"
                              ? "⚙"
                              : center.type === "packing_station"
                                ? "▣"
                                : "▤"}
                          </span>
                          <span className="code">{String(center.code)}</span>
                        </div>
                        <h4>{localName(center, lang)}</h4>
                        <Badge status={String(center.status)} t={t} />
                        {flow[String(center.id)]?.state !== "clear" && (
                          <div
                            className={`flow-state flow-${flow[String(center.id)].state}`}
                          >
                            <strong>{t(flow[String(center.id)].state)}</strong>
                            <small>
                              {localName(
                                centers.find(
                                  (c) =>
                                    c.id === flow[String(center.id)].source,
                                ),
                                lang,
                              )}
                            </small>
                          </div>
                        )}
                        <p className="machine-product">
                          {product ? localName(product, lang) : t("unassigned")}
                        </p>
                        {stop ? (
                          <div className="stop-note">
                            <strong>{localName(reason, lang)}</strong>
                            <span>
                              {formatDuration(
                                (Date.now() -
                                  Date.parse(String(stop.started_at))) /
                                  60000,
                                lang,
                              )}
                            </span>
                          </div>
                        ) : (
                          <div className="machine-footer">
                            {order ? String(order.code) : t("notAvailable")}
                          </div>
                        )}
                      </button>
                    );
                  })}
                </div>
              </section>
            );
          })}
        </div>
      </section>
      <section className="panel attention-panel">
        <h2>{t("attention")}</h2>
        {stops.filter((e) => !e.ended_at).length ? (
          stops
            .filter((e) => !e.ended_at)
            .map((e) => (
              <button
                className="attention-row"
                key={String(e.id)}
                onClick={() => {
                  const c = centers.find((x) => x.id === e.work_center_id);
                  if (c) onCenter(c);
                }}
              >
                <span className="alert-icon">!</span>
                <strong>
                  {localName(
                    centers.find((c) => c.id === e.work_center_id),
                    lang,
                  )}
                </strong>
                <span>
                  {localName(
                    s.tables.downtime_reasons?.find(
                      (r) => r.id === e.reason_id,
                    ),
                    lang,
                  )}
                </span>
                <span className="muted">
                  {formatDuration(
                    (Date.now() - Date.parse(String(e.started_at))) / 60000,
                    lang,
                  )}
                </span>
                <span aria-hidden="true">↗</span>
              </button>
            ))
        ) : (
          <p className="muted">{t("allClear")}</p>
        )}
      </section>
    </>
  );
}
