import { useState } from "react";
import { Empty, Field, localName, formatTime } from "@/components/ui";
import type { FeatureProps } from "./types";
import {
  downtimeMinutes,
  pareto,
  reportPeriod,
  statusUtilization,
  calculateOee,
} from "@/utils/manufacturing.mjs";
import type { Row } from "@/types";
export default function Reports({
  view,
  ...props
}: FeatureProps & { view: string }) {
  const { snapshot: s, t, lang, can } = props;
  const [search,setSearch]=useState(""),[exporting,setExporting]=useState(false),[exportError,setExportError]=useState("");
  const [period, setPeriod] = useState("today"),
    [area, setArea] = useState("all"),
    [line, setLine] = useState("all"),
    [machine, setMachine] = useState("all"),
    [reason, setReason] = useState("all"),
    [from, setFrom] = useState(""),
    [to, setTo] = useState(""),
    [report, setReport] = useState("downtime");
  const zone = String(s.factory?.timezone);
  const invalidRange=period==="custom"&&(!from||!to||to<from);
  let range;
  try {
    range = reportPeriod(period, zone, new Date(), from, to);
  } catch {
    range = reportPeriod("today", zone);
  }
  const centers = (s.tables.work_centers || []).filter(
    (c) =>
      (area === "all" || c.area_id === area) &&
      (line === "all" || c.line_id === line) &&
      (machine === "all" || c.id === machine) && (localName(c,lang)+" "+c.code).toLowerCase().includes(search.toLowerCase()),
  );
  const events = (s.tables.downtime_events || []).filter(
    (e) =>
      centers.some((c) => c.id === e.work_center_id) &&
      !invalidRange && (reason === "all" || e.reason_id === reason || e.sub_reason_id === reason) &&
      downtimeMinutes(e, range.from, range.to) > 0,
  );
  const minutes = (e: Row) => downtimeMinutes(e, range.from, range.to);
  const grouped = pareto(events, minutes, (e: Row) => String(e.reason_id));
  const total = events.reduce((n, e) => n + minutes(e), 0);
  const frequent = pareto(
    events,
    () => 1,
    (e: Row) => String(e.reason_id),
  )[0];
  async function exportCsv() {
    setExporting(true);setExportError("");
    try{const r=await fetch("/api/export",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({factory:s.factory?.id,period,from,to,area,line,machine,reason,lang})});
    if(!r.ok){setExportError((await r.json()).error||"error");return;}
    const url=URL.createObjectURL(await r.blob()),link=document.createElement("a");link.href=url;link.download="downtime-report.csv";link.click();URL.revokeObjectURL(url);
    }catch{setExportError("error")}finally{setExporting(false)}
  }
  const breakdown = (
    key: string,
    group: (e: Row) => string,
    lookup: (id: string) => string,
  ) => (
    <section className="panel">
      <h3>{t(key)}</h3>
      {pareto(events, minutes, group).map(
        (r: { key: string; minutes: number; percent: number }) => (
          <div className="bar-row" key={r.key}>
            <span>{lookup(r.key)}</span>
            <div className="bar-track">
              <div style={{ width: `${r.percent}%` }} />
            </div>
            <strong>
              {Math.round(r.minutes)} {t("minutes")}
            </strong>
          </div>
        ),
      )}
    </section>
  );
  const observations = (s.tables.oee_observations || []).filter(o=>centers.some(c=>c.id===o.work_center_id)&&String(o.started_at)>=range.from&&String(o.ended_at)<=range.to);
  const output=(s.tables.production_entries||[]).filter(e=>!invalidRange&&centers.some(c=>c.id===e.work_center_id)&&String(e.created_at)>=range.from&&String(e.created_at)<range.to);
  const activity=(s.tables.status_events||[]).filter(e=>!invalidRange&&centers.some(c=>c.id===e.work_center_id)&&String(e.created_at)>=range.from&&String(e.created_at)<range.to);
  const orders=(s.tables.production_orders||[]).filter(o=>!invalidRange&&(line==="all"||o.line_id===line)&&((area==="all"&&machine==="all")||centers.some(c=>c.order_id===o.id)||output.some(e=>e.order_id===o.id))&&(!o.start_time||String(o.start_time)<range.to)&&(!o.expected_finish||String(o.expected_finish)>=range.from||output.some(e=>e.order_id===o.id)));

  return (
    <>
      <section className="panel report-controls">
        <div className="filters"><Field label={t("search")}><input value={search} onChange={e=>setSearch(e.target.value)} placeholder={t("centers")}/></Field>
          <Field label={t("period")}>
            <select value={period} onChange={(e) => setPeriod(e.target.value)}>
              {["today", "yesterday", "week", "month", "custom"].map((x) => (
                <option key={x} value={x}>
                  {t(x)}
                </option>
              ))}
            </select>
          </Field>
          {period === "custom" && (
            <>
              <Field label={t("from")}>
                <input
                  type="date"
                  value={from}
                  onChange={(e) => setFrom(e.target.value)}
                />
              </Field>
              <Field label={t("to")}>
                <input
                  type="date"
                  min={from}
                  value={to}
                  onChange={(e) => setTo(e.target.value)}
                />
              </Field>
            </>
          )}
          {[
            ["area", "areas", area, setArea],
            ["line", "production_lines", line, setLine],
            ["machine", "work_centers", machine, setMachine],
            ["reason", "downtime_reasons", reason, setReason],
          ].map(([label, table, value, setter]) => (
            <Field key={String(label)} label={t(String(label))}>
              <select
                value={String(value)}
                onChange={(e) =>
                  (setter as (v: string) => void)(e.target.value)
                }
              >
                <option value="all">{t("all")}</option>
                {s.tables[String(table)]?.map((x) => (
                  <option key={String(x.id)} value={String(x.id)}>
                    {localName(x, lang)}
                  </option>
                ))}
              </select>
            </Field>
          ))}
        </div>
        {can("reports", "export") && (
          <button disabled={exporting||invalidRange} onClick={()=>void exportCsv()}>{t(exporting?"loading":"exportDowntime")}</button>
        )}
      </section>
      {invalidRange && <p className="toast" role="alert">{t("invalidPeriod")}</p>}
      {exportError && <p className="toast" role="alert">{t(exportError)}</p>}
      {view === "reports" && (
        <div className="tabs report-tabs">
          {[
            "downtime",
            "utilization",
            "productionStatus",
            "operatorActivity",
            "lineReport",
            "dailySummary",
          ].map((x) => (
            <button
              key={x}
              aria-pressed={report === x}
              onClick={() => setReport(x)}
            >
              {t(x)}
            </button>
          ))}
        </div>
      )}
      <div className="report-kpis">
        <div className="panel">
          <span>{t("totalDowntime")}</span>
          <strong>
            {Math.round(total)} <small>{t("minutes")}</small>
          </strong>
        </div>
        <div className="panel">
          <span>{t("averageEvent")}</span>
          <strong>
            {events.length ? Math.round(total / events.length) : 0}{" "}
            <small>{t("minutes")}</small>
          </strong>
        </div>
        <div className="panel">
          <span>{t("mostFrequent")}</span>
          <strong className="small-value">
            {frequent
              ? localName(
                  s.tables.downtime_reasons?.find((x) => x.id === frequent.key),
                  lang,
                )
              : "—"}
          </strong>
        </div>
      </div>
      {(report === "downtime" ||
        view === "downtime" ||
        report === "dailySummary") && (
        <section className="panel">
          <header className="section-head">
            <h2>{t("pareto")}</h2>
            <span className="muted">
              {events.length} {t("events")}
            </span>
          </header>
          {grouped.length ? (
            grouped.map(
              (r: {
                key: string;
                minutes: number;
                percent: number;
                cumulative: number;
              }) => (
                <div className="pareto-row" key={r.key}>
                  <span>
                    {localName(
                      s.tables.downtime_reasons?.find((x) => x.id === r.key),
                      lang,
                    )}
                  </span>
                  <div className="bar-track">
                    <div style={{ width: `${r.percent}%` }} />
                  </div>
                  <strong>{r.percent.toFixed(1)}%</strong>
                  <small>
                    {t("cumulative")} {r.cumulative.toFixed(1)}%
                  </small>
                </div>
              ),
            )
          ) : (
            <Empty t={t} />
          )}
        </section>
      )}
      {(report === "lineReport" || report === "dailySummary") &&
        breakdown(
          "byLine",
          (e) =>
            String(
              centers.find((c) => c.id === e.work_center_id)?.line_id ||
                "independent",
            ),
          (id) =>
            id === "independent"
              ? t("independent")
              : localName(
                  s.tables.production_lines?.find((l) => l.id === id),
                  lang,
                ),
        )}
      {(report === "utilization" || report === "dailySummary") && (
        <>
          {breakdown(
            "byMachine",
            (e) => String(e.work_center_id),
            (id) =>
              localName(
                centers.find((c) => c.id === id),
                lang,
              ),
          )}
          <section className="panel">
            <h2>{t("utilization")}</h2><p className="muted">{t("utilizationHelp")}</p>{centers.map(c=>{const u=statusUtilization(s.tables.status_events||[],c.id,range.from,range.to);return <div className="attention-row" key={String(c.id)}><strong>{localName(c,lang)}</strong><span>{u?u.percent.toFixed(1)+"%":t("insufficient")}</span><span>{t("observed")}: {u?Math.round(u.observedMinutes):0} {t("minutes")}</span>{u&&u.coverage<0.99&&<small>{t("partialHistory")}</small>}</div>})}
            <h2>{t("oee")}</h2>
            {observations.length ? (
              observations.map((o) => {
                const result = calculateOee(o);
                return (
                  <p key={String(o.id)}>
                    {localName(
                      centers.find((c) => c.id === o.work_center_id),
                      lang,
                    )}
                    :{" "}
                    {result
                      ? `${(result.oee * 100).toFixed(1)}%`
                      : t("insufficient")}
                  </p>
                );
              })
            ) : (
              <>
                <h3>{t("insufficient")}</h3>
                <p className="muted">{t("oeeHelp")}</p>
              </>
            )}
          </section>
        </>
      )}
      {report === "dailySummary" && <section className="panel"><h2>{t("periodOutput")}</h2><div className="summary-strip"><span>{t("produced_quantity")}: <b>{output.reduce((n,e)=>n+Number(e.produced),0)}</b></span><span>{t("rejected_quantity")}: <b>{output.reduce((n,e)=>n+Number(e.rejected),0)}</b></span><span>{t("activeOrders")}: <b>{orders.filter(o=>o.status==="active").length}</b></span></div></section>}
      {report === "productionStatus" ? (
        <section className="panel">
          <h2>{t("productionStatus")}</h2>
          {!orders.length && <Empty t={t}/>}
          {orders.map((o) => (
            <div className="attention-row" key={String(o.id)}>
              <strong>{String(o.code)}</strong>
              <span>{t(String(o.status))}</span>
              <progress
                max={Number(o.target_quantity)}
                value={Number(o.produced_quantity)}
              />
              <span>
                {String(o.produced_quantity)} / {String(o.target_quantity)} · {t("periodOutput")}: {output.filter(e=>e.order_id===o.id).reduce((n,e)=>n+Number(e.produced),0)}
              </span>
            </div>
          ))}
        </section>
      ) : report === "operatorActivity" ? (
        <section className="panel">
          <h2>{t("operatorActivity")}</h2>
          {!activity.length && <Empty t={t}/>}
          {activity            .map((e) => (
              <div className="attention-row" key={String(e.id)}>
                <strong>
                  {String(
                    s.tables.memberships?.find(
                      (m) => m.user_id === e.created_by,
                    )?.display_name || "—",
                  )}
                </strong>
                <span>
                  {localName(
                    centers.find((c) => c.id === e.work_center_id),
                    lang,
                  )}
                </span>
                <span>{t(String(e.new_status))}</span>
                <time>{formatTime(e.created_at, lang, zone)}</time>
              </div>
            ))}
        </section>
      ) : (
        <section className="panel table-wrap">
          <table>
            <thead>
              <tr>
                {["centers", "reason", "started", "duration"].map((x) => (
                  <th key={x}>{t(x)}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {events.map((e) => (
                <tr key={String(e.id)}>
                  <td>
                    {localName(
                      centers.find((c) => c.id === e.work_center_id),
                      lang,
                    )}
                  </td>
                  <td>
                    {localName(
                      s.tables.downtime_reasons?.find(
                        (x) => x.id === e.reason_id,
                      ),
                      lang,
                    )}
                  </td>
                  <td>{formatTime(e.started_at, lang, zone)}</td>
                  <td>
                    {Math.round(minutes(e))} {t("minutes")}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
    </>
  );
}
