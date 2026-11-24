import { useEffect, useRef, useState, type CSSProperties } from "react";
import { formatTime, localName } from "@/components/ui";
import HistoryQueryState from "@/components/HistoryQueryState";
import MeasuredGanttCode from "@/components/MeasuredGanttCode";
import { useHistoryData } from "@/hooks/useHistoryData";
import type { Row } from "@/types";
import { formatLocalInput, localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import { formatDuration } from "@/utils/production-flow.mjs";
import { planActualEvidence, planActualLayout, planActualTracks, timestampInWindow } from "@/utils/plan-actual.mjs";
import type { FeatureProps } from "./types";
import styles from "./PlanActual.module.css";

type Segment = ReturnType<typeof planActualEvidence>["segments"][number];
type Mode = "original" | "latest";
type Entry = { order: Row; plan: Row[]; history: Row[]; demo?: boolean };
type Bar = Segment & { item: string; code: string; product: string; demo?: boolean };
type Marker = { id: string; item: string; start: string; code: string; label: string };
type Stop = Row & { correction?: Row | null;
  maintenance?: { valid: boolean; approved_start: string; approved_end: string } | null };
type Comparison = Entry & {
  line_transfers: Row[]; return_transfers: Row[]; loans: Row[];
  delay: Row[]; delayTotal: number; stops: Stop[]; stopTotal: number; downtimeView: boolean;
  request: Row | null; asOf: string;
};
const day = 86_400_000;
const hour = 3_600_000;
const nextDate = (date: string) => new Date(Date.parse(date + "T00:00:00Z") + day).toISOString().slice(0, 10);
const zoomLevels = [1, 2, 4, 8];

export default function PlanActual({ snapshot: s, lang, t, onBack }: FeatureProps & { onBack: () => void }) {
  const factory = String(s.factory?.id || "");
  const zone = String(s.factory?.timezone || "UTC");
  const [fromDate, setFrom] = useState(() => formatLocalInput(new Date(Date.now() - 8 * day).toISOString(), zone).slice(0, 10));
  const [toDate, setTo] = useState(() => formatLocalInput(new Date(Date.now() + day).toISOString(), zone).slice(0, 10));
  const [item, setItem] = useState("");
  const [line, setLine] = useState("");
  const [mode, setMode] = useState<Mode>("original");
  const [selected, setSelected] = useState("");
  const [zoom, setZoom] = useState(0);
  const [now, setNow] = useState(Date.now);
  const scroller = useRef<HTMLDivElement>(null);
  const detailsHeading = useRef<HTMLHeadingElement>(null);
  const focusDetails = useRef(false);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 15_000);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => {
    if (selected && focusDetails.current) detailsHeading.current?.focus();
    focusDetails.current = false;
  }, [selected]);

  let from = "", to = "";
  try {
    if (fromDate && toDate && toDate >= fromDate) {
      from = localDateTimeToUtc(fromDate + "T00:00", zone);
      to = localDateTimeToUtc(nextDate(toDate) + "T00:00", zone);
    }
  } catch { /* Invalid date input is handled below. */ }
  const start = Date.parse(from), span = Date.parse(to) - start;
  const valid = span > 0 && span <= 32 * day;
  const catalogUrl = valid ? "/api/plan-actual?" + new URLSearchParams({ factory, from, to }) : null;
  const catalog = useHistoryData<{ entries: Entry[]; asOf: string }>(catalogUrl, s.fetchedAt, catalogUrl, true);
  const entries = catalog.data?.entries || [];
  const allLines = s.tables.production_lines || [];
  const name = (table: string, id: unknown) => localName(s.tables[table]?.find(row => row.id === id), lang) || t("notAvailable");
  const at = (date: string) => formatTime(date, lang, zone);
  const position = (date: string) => (Date.parse(date) - start) / span * 100;
  const open = (id: string) => {
    focusDetails.current = id !== selected;
    setSelected(id);
    if (id === selected) detailsHeading.current?.focus();
  };
  const bars = new Map<string, { plan: Bar[]; actual: Bar[]; interruptions: Marker[] }>();
  const markers: Marker[] = [];
  const missing: Entry[] = [];
  const asOf = catalog.data?.asOf || new Date(now).toISOString();
  for (const entry of entries) {
    const id = String(entry.order.id);
    const code = String(entry.order.code || "");
    if (item && item !== id) continue;
    const evidence = planActualTracks(entry, mode, asOf);
    let onSelectedLine = !line;
    for (const segment of evidence.segments) {
      if (segment.line !== line && line) continue;
      if (Date.parse(segment.start) >= start + span || Date.parse(segment.finish) <= start) continue;
      onSelectedLine = true;
      const group = bars.get(segment.line) || { plan: [], actual: [], interruptions: [] };
      const itemBar = { ...segment, id: id + "-" + segment.id, item: id, code, demo: entry.demo,
        product: name("products", entry.order.product_id) };
      if (segment.kind === "actual") {
        group.actual.push(itemBar);
        if (segment.run?.state === "INTERRUPTED" && timestampInWindow(segment.finish, from, to)) {
          group.interruptions.push({ id: itemBar.id, item: id, start: segment.finish, code,
            label: [t("f37Run_INTERRUPTED"), segment.run.reason].filter(Boolean).join(" · ") });
        }
      } else group.plan.push(itemBar);
      bars.set(segment.line, group);
    }
    if (!line) for (const point of evidence.unmatchedBounds) {
      if (timestampInWindow(point.start, from, to)) markers.push({ start: String(point.start), id: id + "-" + point.id, item: id,
        code, label: [entry.demo ? t("f37Demo") : "", t(point.kind === "start" ? "f37ActualStart" : "f37ActualFinish")]
          .filter(Boolean).join(" · ") });
    }
    if (onSelectedLine && !evidence.chartPlan && evidence.revision?.event !== "unscheduled" &&
      (mode === "original" || entry.plan.length === 0 || evidence.revision?.event === "baseline")) missing.push(entry);
  }
  const lines = [...new Set([...allLines.map(row => String(row.id)), ...bars.keys()])]
    .filter(id => !line || id === line);
  const detailEntry = entries.find(entry => entry.order.id === (selected || item) && (!item || item === entry.order.id));
  const itemUrl = detailEntry
    ? "/api/plan-actual?" + new URLSearchParams({ factory, item: String(detailEntry.order.id) }) : null;
  const data = useHistoryData<Comparison>(itemUrl, s.fetchedAt, itemUrl, true);

  const nowDate = new Date(now).toISOString();
  const showNow = valid && timestampInWindow(nowDate, from, to);
  const basePixels = Math.max(600, span / day * 110);
  const pixels = basePixels * zoomLevels[zoom];
  const step = [1, 2, 3, 4, 6, 12, 24, 48, 72, 168].map(hours => hours * hour)
    .find(duration => duration >= span * 125 / pixels) || day;
  const timeLabel = new Intl.DateTimeFormat(lang, { timeZone: zone, month: "short", day: "numeric",
    ...(step < day ? { hour: "2-digit", minute: "2-digit" } : {}) });
  const caption = (kind: string) => t(kind === "original" ? "f37Original" : kind === "actual" ? "f37Actual" : "f37Latest");
  const wrapped = (bar: Bar) => [bar.code, bar.demo ? t("f37Demo") : "", bar.product, caption(bar.kind),
    at(bar.start) + " — " + at(bar.finish), bar.open ? t("f37OpenRun") : "", bar.run?.reason]
    .filter(Boolean).join(" · ");
  const nowLine = showNow && <i className={styles.nowLine} style={{ insetInlineStart: position(nowDate) + "%" }} />;
  const markerButton = (marker: Marker, interruption: boolean) => {
    const label = [marker.code, marker.label, at(marker.start)].join(" · ");
    return <button type="button" key={marker.id} className={styles.marker}
      data-interruption={interruption} aria-label={label} title={label}
      aria-pressed={detailEntry?.order.id === marker.item}
      style={{ insetInlineStart: position(marker.start) + "%" }} onClick={() => open(marker.item)} />;
  };
  const track = (segments: Bar[], breaks: Marker[] = []) => {
    const layout = planActualLayout(segments, from, to, pixels);
    return <div className={styles.track} style={{ minHeight: Math.max(1, layout.tracks) * 32 }}>
      {nowLine}
      {layout.jobs.map(job => {
        const bar = job.segment as Bar;
        return <button type="button" key={bar.id} className={styles.bar} data-kind={bar.kind} data-open={Boolean(bar.open)}
          aria-label={wrapped(bar)} title={wrapped(bar)} aria-pressed={detailEntry?.order.id === bar.item}
          style={{ insetInlineStart: job.left + "%", inlineSize: job.width + "%", top: job.track * 32 + 4 }}
          onClick={() => open(bar.item)}>
          <MeasuredGanttCode code={bar.code} />
        </button>;
      })}
      {breaks.map(marker => markerButton(marker, true))}
    </div>;
  };

  return <section className={"lean-page " + styles.page} dir={lang === "ar" ? "rtl" : "ltr"}>
    <header className="lean-header">
      <div><button type="button" onClick={onBack}>{t("back")} · {t("lean")}</button>
        <h2>{t("f37Title")}</h2><p>{t("f37Intro")}</p></div>
    </header>
    <div className={styles.filters}>
      <label>{t("from")}<input type="date" value={fromDate} onChange={e => setFrom(e.target.value)} /></label>
      <label>{t("to")}<input type="date" value={toDate} onChange={e => setTo(e.target.value)} /></label>
      <label>{t("f37TimelineLine")}<select aria-label={t("f37TimelineLine")} value={line} onChange={e => setLine(e.target.value)}>
        <option value="">{t("f37AllLines")}</option>
        {allLines.map(row => <option key={String(row.id)} value={String(row.id)}>{localName(row, lang)}</option>)}
      </select></label>
      <label>{t("f37Order")}<select aria-label={t("f37Order")} value={item} onChange={e => {
        setItem(e.target.value);
        setSelected(e.target.value);
      }}>
        <option value="">{t("f37AllOrders")}</option>
        {item && !entries.some(entry => entry.order.id === item) && <option value={item}>{t("f37OrderOutsideRange")}</option>}
        {entries.map(({ order, demo }) => <option key={String(order.id)} value={String(order.id)}>
          {String(order.code || "")}{demo ? " · " + t("f37Demo") : ""}
        </option>)}
      </select></label>
      <label>{t("f37Compare")}<select aria-label={t("f37Compare")} value={mode} onChange={e => setMode(e.target.value as Mode)}>
        <option value="original">{t("f37OriginalComparison")}</option>
        <option value="latest">{t("f37LatestComparison")}</option>
      </select></label>
    </div>
    {!valid && <p role="status">{t("f37RangeInvalid")}</p>}
    <HistoryQueryState {...catalog} t={t} />
    {catalog.data && <>
      <div className={styles.toolbar}>
        <ul className={styles.legend} aria-label={t("f37Legend")}>
          <li><i data-kind={mode === "original" ? "original" : "approved"} />{caption(mode === "original" ? "original" : "approved")}</li>
          <li><i data-kind="actual" />{t("f37Actual")}</li>
          <li><i data-kind="interrupt" />{t("f37Run_INTERRUPTED")}</li>
          <li><i data-kind="point" />{t("f37RecordedBounds")}</li>
          {showNow && <li><i data-kind="now" />{t("f37Now")}</li>}
        </ul>
        <div className={"planning-zoom-control " + styles.zoom}>
          <label htmlFor="f37-zoom">{t("planningZoom")}</label>
          <input id="f37-zoom" type="range" min={0} max={zoomLevels.length - 1} step={1}
            value={zoom} aria-valuetext={zoomLevels[zoom] + "×"} onChange={e => setZoom(Number(e.target.value))} />
          {showNow && <button type="button" onClick={() => scroller.current?.querySelector("[data-now]")?.scrollIntoView({
            block: "nearest", inline: "center",
          })}>{t("f37Now")}</button>}
        </div>
      </div>
      {bars.size === 0 && markers.length === 0 && <p>{t(entries.length ? "f37NoIntervals" : "f37NoOrders")}</p>}
      <div ref={scroller} className={styles.desktop} tabIndex={0} role="region" aria-label={t("f37SharedScale")}>
        <div className={styles.canvas} style={{ "--timeline-width": pixels + "px", "--tick-step": step / span * 100 + "%" } as CSSProperties}>
          <div className={styles.axis}><span>{zone}</span><div className={styles.ticks}>
            {Array.from({ length: Math.ceil(span / step) }, (_, index) => index * step).filter(offset => offset === 0 ||
              (span - offset) / span * pixels >= 60).map(offset => <span key={offset} data-first={offset === 0}
              style={{ insetInlineStart: offset / span * 100 + "%" }}>
              {timeLabel.format(start + offset)}
            </span>)}
            {showNow && <i data-now className={styles.nowLine} style={{ insetInlineStart: position(nowDate) + "%" }} />}
          </div></div>
          {lines.map(id => {
            const group = bars.get(id);
            return <section className={styles.lane} key={id} aria-label={name("production_lines", id)}>
              <h4>{name("production_lines", id)}</h4>
              <div className={styles.trackRow}><span>{t("f37PlanTrack")}</span>{track(group?.plan || [])}</div>
              <div className={styles.trackRow}><span>{t("f37Actual")}</span>{track(group?.actual || [], group?.interruptions)}</div>
            </section>;
          })}
          {markers.length > 0 && <div className={styles.trackRow}><span>{t("f37RecordedBounds")}</span>
            <div className={styles.track}>{nowLine}{markers.map(marker => markerButton(marker, false))}</div>
          </div>}
        </div>
      </div>
      <div className={styles.mobile}>
        {lines.map(id => {
          const group = bars.get(id);
          const ordered = [...(group?.plan || []), ...(group?.actual || [])]
            .sort((a, b) => Date.parse(a.start) - Date.parse(b.start) || a.id.localeCompare(b.id));
          if (!ordered.length) return null;
          return <section key={id}><h4>{name("production_lines", id)}</h4>
            {ordered.map(bar => <button type="button" key={bar.id} data-kind={bar.kind}
              aria-pressed={detailEntry?.order.id === bar.item} onClick={() => open(bar.item)}>
              <strong><bdi>{bar.code}</bdi> · {bar.product}{bar.demo ? " · " + t("f37Demo") : ""}</strong>
              <span>{caption(bar.kind)} · {at(bar.start)} — {at(bar.finish)}</span>
              {bar.open && <small>{t("f37OpenRun")}</small>}
              {bar.run?.state === "INTERRUPTED" && <small>{t("f37Run_INTERRUPTED")}</small>}
            </button>)}
          </section>;
        })}
        {markers.length > 0 && <section><h4>{t("f37RecordedBounds")}</h4>{markers.map(marker =>
          <button type="button" key={marker.id} onClick={() => open(marker.item)}>
            <bdi>{marker.code}</bdi> {marker.label} · {at(marker.start)}
          </button>)}</section>}
      </div>
      {missing.length > 0 && <details className={styles.detail}>
        <summary>{t(mode === "original" ? "f37OriginalMissing" : "f37LatestMissing")} ({missing.length.toLocaleString(lang)})</summary>
        <ul>{missing.map(({ order }) => <li key={String(order.id)}><button type="button" onClick={() => open(String(order.id))}>
          <bdi>{String(order.code)}</bdi> · {name("products", order.product_id)}
        </button></li>)}</ul>
      </details>}
    </>}
    {detailEntry && <div className={styles.orderDetails}>
      <div className={styles.orderHeading}><h3 ref={detailsHeading} tabIndex={-1}>
        <bdi>{String(detailEntry.order.code)}</bdi> · <bdi>{name("products", detailEntry.order.product_id)}</bdi>{detailEntry.demo ? " · " + t("f37Demo") : ""}
      </h3>
        {!item && <button type="button" onClick={() => setSelected("")}>{t("close")}</button>}
      </div>
      <HistoryQueryState {...data} t={t} />
      {data.data && <OrderDetails key={String(data.data.order.id)} {...{ snapshot: s, t, lang, zone, mode }} comparison={data.data} />}
    </div>}
  </section>;
}

function OrderDetails({ snapshot: s, lang, t, zone, mode, comparison: c }: Pick<FeatureProps, "snapshot" | "lang" | "t"> & {
  zone: string; mode: Mode; comparison: Comparison;
}) {
  const evidence = planActualTracks(c, mode, c.asOf);
  const latest = planActualTracks(c, "latest", c.asOf);
  const name = (table: string, id: unknown) => localName(s.tables[table]?.find(row => row.id === id), lang) || t("notAvailable");
  const at = (value: unknown) => typeof value === "string" && Number.isFinite(Date.parse(value))
    ? formatTime(value, lang, zone) : t("notAvailable");
  const actor = (id: unknown) => (s.tables.memberships || []).find(row => row.user_id === id)?.display_name || "";
  const direction = lang === "ar" ? " ← " : " → ";
  const due = Date.parse(String(c.request?.required_by || ""));
  const finished = Date.parse(String(c.order.actual_finish || ""));
  const delta = (value: number | null) => {
    if (!evidence.chartPlan || value == null) return t("notAvailable");
    if (value !== 0 && Math.abs(value) < 60_000) return new Intl.NumberFormat(lang,
      { maximumFractionDigits: 1, signDisplay: "exceptZero" }).format(value / 1000) + " " + t("f37Seconds");
    return formatDuration(value / 60_000, lang, true);
  };
  const interval = (plan: Segment | null) => plan
    ? [name("production_lines", plan.line), at(plan.start) + " — " + at(plan.finish)].join(" · ") : t("notAvailable");
  return <>
    <section className={styles.detail} aria-label={t("f37Timing")}>
      {!evidence.original && <p>{t(evidence.ordered[0]?.event === "baseline" ? "f37EarlierPlanUnknown" : "f37OriginalMissing")}</p>}
      {!evidence.runs.length && <p>{t(evidence.bounds.length ? "f37BoundsOnly" : "f37ActualMissing")}</p>}
      {evidence.runs.length > 0 && evidence.unmatchedBounds.length > 0 && <p>{t("f37PartialRuns")}</p>}
      <dl>
        <div><dt>{t("f37Original")}</dt><dd>{interval(evidence.original)}</dd></div>
        <div><dt>{t("f37Latest")}</dt><dd>{latest.revision?.event === "unscheduled" ? t("f37Unscheduled") : interval(latest.chartPlan)}</dd></div>
        <div><dt>{t("f37ActualStart")}</dt><dd>{at(c.order.actual_start)}</dd></div>
        <div><dt>{t("f37ActualFinish")}</dt><dd>{at(c.order.actual_finish)}</dd></div>
        <div><dt>{t("f37StartDifference")}</dt><dd>{delta(evidence.startDelta)}</dd></div>
        <div><dt>{t("f37FinishDifference")}</dt><dd>{delta(evidence.finishDelta)}</dd></div>
        <div><dt>{t("f37ElapsedDifference")}</dt><dd>{delta(evidence.elapsedDelta)}</dd></div>
      </dl>
      {Number.isFinite(due) && <p>{t("f37RequiredBy")} {at(c.request?.required_by)}
        {Number.isFinite(finished) && " · " + t(finished > due ? "f37AfterDeadline" : "f37ByDeadline")}</p>}
    </section>
    <details className={styles.detail}><summary>{t("f37ExecutionHistory")}</summary>
      {!evidence.runs.length && !c.line_transfers.length && !c.return_transfers.length && !c.loans.length && !c.delay.length &&
        <p>{t("f37ActualMissing")}</p>}
      <ul>
        {evidence.runs.map((run, index) => <li key={run.id}><strong>{name("production_lines", run.line)} · {t("f37Run_" + run.run?.state)}</strong>
          <p>{at(run.start)} — {run.open ? t("f37OpenRun") : at(run.finish)}</p>
          {index > 0 && evidence.runs[index - 1].run?.state === "INTERRUPTED" &&
            Date.parse(evidence.runs[index - 1].finish) <= Date.parse(run.start) && <p>{t("f37Resumed")}</p>}
          <small>{[run.run?.start_reason, run.run?.reason, actor(run.run?.start_actor), actor(run.run?.end_actor)]
            .filter(Boolean).filter((value, index, values) => values.indexOf(value) === index).join(" · ")}</small></li>)}
        {c.line_transfers.map(row => <li key={String(row.request_id)}><strong>{t("f37Transfer")}</strong>
          <p><bdi>{name("production_lines", row.source_line)}</bdi>{direction}<bdi>{name("production_lines", row.destination_line)}</bdi> · {at(row.started_at)}</p>
          <small>{[row.reason, actor(row.actor)].filter(Boolean).join(" · ")}</small></li>)}
        {c.return_transfers.map(row => <li key={String(row.request_id)}><strong>{t(row.mode === "LINE" ? "f37ReturnLine" : "f37EquipmentReturn")}</strong>
          <p>{at(row.returned_at)} · {name("work_centers", row.source_machine)}</p>
          <small>{[row.reason, actor(row.actor)].filter(Boolean).join(" · ")}</small></li>)}
        {c.loans.map(row => <li key={String(row.id)}><strong>{t("f37Loan")}</strong>
          <p><bdi>{name("work_centers", row.original_id)}</bdi>{direction}<bdi>{name("work_centers", row.alternative_id)}</bdi> · {at(row.created_at)}</p>
          <small>{[row.reason, actor(row.created_by)].filter(Boolean).join(" · ")}</small></li>)}
        {c.delay.map(row => <li key={String(row.id)}><strong>{t("f46DelayReason")} · {formatDuration(Number(row.delay_seconds) / 60, lang)}</strong>
          <p>{at(row.created_at)} · {t("f37Revision")} {Number(row.plan_revision).toLocaleString(lang)} · {t("f37ApprovedFinish")} {at(row.planned_finish)}</p>
          <small>{[row.reason, row.actor_name, row.estimated_finish && `${t("f37RevisedEta")} ${at(row.estimated_finish)}`].filter(Boolean).join(" · ")}</small></li>)}
      </ul>
      {c.delayTotal > c.delay.length && <p>{t("f37RecentDelay")}</p>}
    </details>
    {c.downtimeView && <details className={styles.detail}><summary>{t("f37RelatedStops")}</summary>
      <p>{t("f37StopsHelp")}</p>
      {!c.stops.length && <p>{t("noResults")}</p>}
      <ul>{c.stops.map(stop => <li key={String(stop.id)}>
        <strong>{name("work_centers", stop.work_center_id)} · {name("production_lines", stop.line_id)}</strong>
        <p>{at(stop.started_at)} — {at(stop.ended_at)} · {(stop.correction?.stop_nature || stop.stop_nature) === "planned"
          ? t("lossPlanned") : name("downtime_reasons", stop.correction?.reason_id || stop.approved_cause_id || stop.reason_id)}</p>
        {(stop.correction?.note || stop.engineering_note || stop.initial_note) &&
          <p dir="auto">{String(stop.correction?.note || stop.engineering_note || stop.initial_note)}</p>}
        {stop.maintenance && <small>{stop.maintenance.valid
          ? `${t("f37MaintenanceWindow")} ${at(stop.maintenance.approved_start)} — ${at(stop.maintenance.approved_end)}`
          : t("f37MaintenanceUnknown")}</small>}
      </li>)}</ul>
      {c.stopTotal > c.stops.length && <p>{t("f37RecentStops")}</p>}
    </details>}
  </>;
}
