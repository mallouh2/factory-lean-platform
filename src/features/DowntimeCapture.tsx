import { useEffect, useRef, useState } from "react";
import { useHistoryData } from "@/hooks/useHistoryData";
import HistoryQueryState from "@/components/HistoryQueryState";
import { Dialog, formatTime, localName } from "@/components/ui";
import { localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import { formatDuration } from "@/utils/production-flow.mjs";
import { downtimeReasonChoices } from "@/utils/downtime-reasons";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
import styles from "./DowntimeCapture.module.css";
import LossImpactReview from "./LossImpactReview";
import { MaintenanceCreate } from "./MaintenanceRequest";
import DowntimeReference from './DowntimeReference';
import AuditHistory from "./AuditHistory";

export default function DowntimeCapture({ snapshot: s, t, lang, command, can, initialEventId, onReferenceClose, onMaintenanceRepairOpen }: FeatureProps & {
  initialEventId?: string | null; onReferenceClose?: () => void;
}) {
  const [now, setNow] = useState(() => Date.now());
  const [initialEvent, setInitialEvent] = useState("");
  const [initialReason, setInitialReason] = useState("");
  const [initialNote, setInitialNote] = useState("");
  const [selectedId, setSelectedId] = useState(initialEventId || "");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("all");
  const [equipment, setEquipment] = useState("");
  const [impact, setImpact] = useState("");
  const [page, setPage] = useState(1);
  const [openAction, setOpenAction] = useState("");
  const heading = useRef<HTMLHeadingElement>(null);
  const [causeId, setCauseId] = useState("");
  const [engineeringNote, setEngineeringNote] = useState("");
  const [retroMachine, setRetroMachine] = useState("");
  const [retroStart, setRetroStart] = useState("");
  const [retroEnd, setRetroEnd] = useState("");
  const [retroReason, setRetroReason] = useState("");
  const [retroNote, setRetroNote] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const factory = String(s.factory?.id || "");
  const zone = String(s.factory?.timezone || "Asia/Qatar");
  const registerUrl = factory ? "/api/loss-review?" + new URLSearchParams({ factory, view: "register" }) : null;
  const history = useHistoryData<{ rows: Row[]; correctedIds?: string[] }>(
    registerUrl, s.fetchedAt, registerUrl, true);
  const events = history.data?.rows || s.tables.downtime_events || [];
  const corrected = new Set(history.data?.correctedIds || []);
  const machines = s.tables.work_centers || [];
  const reasons = s.tables.downtime_reasons || [];
  const categories = reasons.map(row => ({
    row, key: downtimeReasonChoices.find(([name])=>name===row.name)?.[1],
  })).filter((option) => option.row);
  const open = events.filter((e) => !e.ended_at)
    .sort((a, b) => String(a.started_at).localeCompare(String(b.started_at)));
  const needsReview = events.filter((e) => e.ended_at && !e.approved_at)
    .sort((a, b) => String(b.ended_at).localeCompare(String(a.ended_at)));
  const canOperate = can("machine_status", "edit") || can("centers", "edit");
  const canReview = can("downtime", "edit");
  const machine = (id: unknown) => machines.find((m) => String(m.id) === String(id));
  const reasonName = (id: unknown) => id
    ? localName(reasons.find((r) => String(r.id) === String(id)), lang)
    : t("downtimeUnclassified");
  const stopName = (event: Row) => event.stop_nature === "planned"
    ? `${t("lossPlanned")} — ${t(`lossActivity_${event.planned_activity}`)}`
    : event.stop_nature === "legacy_unknown"
      ? `${t("lossLegacyUnknown")} — ${reasonName(event.reason_id)}`
      : reasonName(event.reason_id);
  const personName = (id: unknown) => String((s.tables.memberships || [])
    .find((m) => String(m.user_id) === String(id))?.display_name || t("requestCreatorNotRecorded"));
  const context = (event: Row) => {
    const item = (s.tables.production_orders || []).find((o) => o.id === event.order_id);
    const line = (s.tables.production_lines || []).find((l) => l.id === event.line_id);
    return [line && localName(line, lang), item?.code].filter(Boolean).join(" · ");
  };
  const statusOf = (event: Row) => !event.ended_at ? "open"
    : corrected.has(String(event.id)) ? "corrected" : event.approved_at ? "reviewed" : "pending";
  const statusLabel = (value: string) => t(value === "all" ? "downtimeAllEvents" : value === "open" ? "downtimeActive"
    : value === "pending" ? "downtimeNeedsReview" : value === "corrected" ? "downtimeStatusCorrected" : "downtimeStatusReviewed");
  const search = query.trim().toLocaleLowerCase(lang);
  const results = events.filter(event => {
    if (status === "pending" && (!event.ended_at || event.approved_at)) return false;
    if (status !== "all" && status !== "pending" && statusOf(event) !== status) return false;
    if (equipment && String(event.work_center_id) !== equipment) return false;
    if (impact === "blocking" && event.blocking_at_start !== true) return false;
    if (impact === "nonblocking" && event.blocking_at_start !== false) return false;
    if (impact === "planned" && event.stop_nature !== "planned") return false;
    return !search || [event.id, context(event), stopName(event), reasonName(event.approved_cause_id),
      localName(machine(event.work_center_id), lang), event.initial_note, event.notes, event.engineering_note]
      .filter(Boolean).some(value => String(value).toLocaleLowerCase(lang).includes(search));
  });
  const pages = Math.max(1, Math.ceil(results.length / 10));
  const visiblePage = Math.min(page, pages);
  const rows = results.slice((visiblePage - 1) * 10, visiblePage * 10);
  const focused = events.find(event => event.id === selectedId)
    || (!selectedId ? rows.find(event => event.ended_at) : null) || rows[0];
  const focusedId = focused?.id;
  useEffect(() => {
    if (focusedId && !selectedId) setSelectedId(String(focusedId));
  }, [focusedId, selectedId]);
  const openLinkUrl = focused && !focused.ended_at && can("maintenance", "view")
    ? "/api/loss-review?" + new URLSearchParams({ factory, related: String(focused.id) }) : null;
  const openLink = useHistoryData<{ relatedRequest: Row | null }>(openLinkUrl, s.fetchedAt, openLinkUrl, true);
  const focusedInitialIsCurrent = categories.some(({ row }) => row.id === focused?.reason_id);
  const pageTo = (next: number) => {
    setPage(next); setOpenAction(""); setSelectedId(""); setCauseId(""); setEngineeringNote(""); setInitialEvent("");
  };
  const elapsed = (event: Row) => {
    const end = event.ended_at ? Date.parse(String(event.ended_at)) : now;
    const minutes = (end - Date.parse(String(event.started_at))) / 60_000;
    if (!Number.isFinite(minutes) || minutes < 0) return t("downtimeSourceUnknown");
    return Number.isInteger(minutes) || !event.ended_at ? formatDuration(minutes, lang)
      : `${new Intl.NumberFormat(lang === "ar" ? "ar-u-nu-arab" : "en", { maximumFractionDigits: 3 })
        .format(minutes)} ${t("minutesShort")}`;
  };

  async function run(name: string, args: Record<string, unknown>, done?: () => void) {
    setBusy(true);
    try { await command(name, { factory, ...args }); done?.(); }
    catch { /* The shared command handler displays the exact error. */ }
    finally { setBusy(false); }
  }
  const eventHistory = focused ? <>
            <dl>
              <div><dt>{t("downtimeOperatorNote")}</dt><dd dir="auto">{String(focused.initial_note || focused.notes || t("downtimeSourceUnknown"))}</dd></div>
              <div><dt>{t("downtimeEnteredBy")}</dt><dd>{personName(focused.initial_entered_by || focused.created_by)}</dd></div>
              {focused.approved_at && <>
                <div><dt>{t("downtimeApprovedCause")}</dt><dd>{focused.stop_nature === "planned" ? stopName(focused) : reasonName(focused.approved_cause_id)}</dd></div>
                <div><dt>{t("downtimeStatusReviewed")}</dt><dd>{personName(focused.approved_by)} · {formatTime(focused.approved_at, lang, zone)}</dd></div>
                <div><dt>{t("downtimeEngineeringNote")}</dt><dd dir="auto">{String(focused.engineering_note || t("downtimeSourceUnknown"))}</dd></div>
              </>}
            </dl>
      {can("audit", "view") && <AuditHistory {...{ snapshot: s, t, lang, command, can }}
        eventSearch={String(focused.id)} />}
    </> : null;
  return <section className={styles.page} aria-label={t("downtimeCaptureTitle")}>
    {initialEventId && <DowntimeReference snapshot={s} t={t} lang={lang} command={command} can={can}
      id={initialEventId} onClose={onReferenceClose || (() => {})} />}
    <header className={styles.heading}>
      <div><h2>{t("downtimeCaptureTitle")}</h2><p>{t("downtimeCaptureHelp")}</p></div>
      <div className={styles.metrics}>
        <span><strong>{open.length}</strong> {t("downtimeActive")}</span>
        <span><strong>{needsReview.length}</strong> {t("downtimeNeedsReview")}</span>
      </div>
    </header>

    <div className={styles.register}>
      <section className={styles.card} aria-labelledby="downtime-register-heading">
        <h3 id="downtime-register-heading">{t("downtimeRegister")}</h3>
        <div className={styles.queue}>
          {["all", "pending", "open"].map(value => <button key={value} type="button"
            aria-pressed={status === value} onClick={() => { setStatus(value); pageTo(1); }}>
            {statusLabel(value)}
          </button>)}
        </div>
        <label className={styles.filter}>{t("downtimeSearch")}
          <input type="search" value={query} onChange={e => { setQuery(e.target.value); pageTo(1); }} />
        </label>
        <details className={styles.filters}>
          <summary>{t("downtimeMoreFilters")}</summary>
          <label className={styles.filter}>{t("status")}
            <select value={status} onChange={e => { setStatus(e.target.value); pageTo(1); }}>
              {["all", "pending", "open", "reviewed", "corrected"].map(value =>
                <option key={value} value={value}>{statusLabel(value)}</option>)}
            </select>
          </label>
          <label className={styles.filter}>{t("machine")}
            <select value={equipment} onChange={e => { setEquipment(e.target.value); pageTo(1); }}>
              <option value="">{t("downtimeAllEquipment")}</option>
              {machines.map(row => <option value={String(row.id)} key={String(row.id)}>{localName(row, lang)}</option>)}
            </select>
          </label>
          <label className={styles.filter}>{t("downtimeRecordedImpact")}
            <select value={impact} onChange={e => { setImpact(e.target.value); pageTo(1); }}>
              <option value="">{t("downtimeAllEvents")}</option>
              <option value="blocking">{t("downtimeBlocking")}</option>
              <option value="nonblocking">{t("downtimeNonblocking")}</option>
              <option value="planned">{t("lossPlanned")}</option>
            </select>
          </label>
        </details>
        <HistoryQueryState {...history} t={t} />
        {!history.data && (history.loading || history.error) && rows.length > 0 && <p>{t("downtimeRecentOnly")}</p>}
        <div className={styles.reviewList}>
          {rows.map(event => <button key={String(event.id)} type="button"
            aria-pressed={focused?.id === event.id} aria-controls="downtime-selected-event"
            onClick={() => {
              setSelectedId(String(event.id)); setOpenAction(""); setCauseId(""); setEngineeringNote(""); setInitialEvent("");
              if (window.matchMedia("(max-width: 850px)").matches) requestAnimationFrame(() => {
                heading.current?.focus({ preventScroll: true });
                heading.current?.scrollIntoView({ block: "start" });
              });
            }}>
            <span className={styles.eventLine}><strong>{localName(machine(event.work_center_id), lang)}</strong>
              <span className={styles.status} data-state={statusOf(event)}>{statusLabel(statusOf(event))}</span></span>
            <span>{stopName(event)}</span>
            <span>{formatTime(event.started_at, lang, zone)} · {elapsed(event)}</span>
          </button>)}
        </div>
        {!rows.length && !history.loading && !history.error && <p>{t("noResults")}</p>}
        {pages > 1 && <nav className="history-pagination" aria-label={t("lossReviewPages")}>
          <button type="button" disabled={visiblePage <= 1} onClick={() => pageTo(visiblePage - 1)}>{t("previous")}</button>
          <span>{visiblePage.toLocaleString(lang)} / {pages.toLocaleString(lang)}</span>
          <button type="button" disabled={visiblePage >= pages} onClick={() => pageTo(visiblePage + 1)}>{t("next")}</button>
        </nav>}
      </section>
      <section className={styles.card} id="downtime-selected-event" aria-labelledby="downtime-selected-heading">
        <h3 ref={heading} tabIndex={-1} id="downtime-selected-heading">{t("downtimeSelectedEvent")}</h3>
        {focused ? <div className={styles.reviewDetail} key={String(focused.id)}>
          <div className={styles.selectedHeader}>
            <h4>{localName(machine(focused.work_center_id), lang)}</h4>
            <p>{context(focused)}</p>
            <span className={styles.status} data-state={statusOf(focused)}>{statusLabel(statusOf(focused))}</span>
            {focused.approved_at && <small>{formatTime(focused.approved_at, lang, zone)}</small>}
          </div>
          <dl>
            <div><dt>{t("downtimeStarted")}</dt><dd>{formatTime(focused.started_at, lang, zone)}</dd></div>
            <div><dt>{t("downtimeEnded")}</dt><dd>{focused.ended_at ? formatTime(focused.ended_at, lang, zone) : t("downtimeActive")}</dd></div>
            <div><dt>{t("lossRawStop")}</dt><dd>{elapsed(focused)} · {t("downtimeSourceRecorded")}</dd></div>
            <div><dt>{t(focused.approved_cause_id ? "downtimeApprovedCause" : "downtimeInitialReason")}</dt><dd>{focused.approved_cause_id ? reasonName(focused.approved_cause_id) : stopName(focused)}</dd></div>
          </dl>
          {focused.ended_at ? <LossImpactReview {...{ snapshot: s, t, lang, command, can }}
            eventId={String(focused.id)} history={eventHistory} onMaintenanceRepairOpen={onMaintenanceRepairOpen}>
          {canReview && focused.ended_at && !focused.approved_at && <details className={styles.disclosure}>
            <summary>{t("downtimeReviewCause")}</summary>
            <div className={styles.form}>
          {focused.stop_nature !== "planned" && <><label>{t("downtimeApprovedCause")}
            <select value={causeId || (focusedInitialIsCurrent ? String(focused.reason_id) : "")}
              onChange={(e) => setCauseId(e.target.value)}>
              <option value="">{t("downtimeChooseReason")}</option>
              {categories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{key?t(key):localName(row,lang)}</option>)}
            </select>
          </label>
          <label>{t("downtimeEngineeringNote")}
            <textarea maxLength={2000} value={engineeringNote}
              onChange={(e) => setEngineeringNote(e.target.value)} />
          </label>
          <div className={styles.actions}>
            {focusedInitialIsCurrent && <button type="button" disabled={busy} onClick={() =>
              void run("approve_downtime_cause", { event: focused.id,
                cause: focused.reason_id, notes: engineeringNote }, () => {
                  setCauseId(""); setEngineeringNote("");
                })}>{t("downtimeApproveInitial")}</button>}
            <button className="primary" disabled={busy || !(causeId || focusedInitialIsCurrent)}
              onClick={() => void run("approve_downtime_cause", { event: focused.id,
                cause: causeId || focused.reason_id, notes: engineeringNote }, () => {
                  setCauseId(""); setEngineeringNote("");
                })}>{t("downtimeSaveCause")}</button>
          </div></>}
          {focused.stop_nature === "planned" && <>
            <label>{t("downtimeEngineeringNote")}
              <textarea maxLength={2000} value={engineeringNote}
                onChange={(e) => setEngineeringNote(e.target.value)} />
            </label>
            <button className="primary" disabled={busy}
              onClick={() => void run("approve_planned_downtime", {
                event: focused.id, notes: engineeringNote,
              }, () => setEngineeringNote(""))}>{t("lossApprovePlanned")}</button>
          </>}
            </div>
          </details>}
          </LossImpactReview> : <p>{t("downtimeOpenImpact")}</p>}
          {canOperate && <div className={styles.actions}>
            {!focused.reason_id && focused.stop_nature !== "planned" &&
              <button disabled={busy} onClick={() => {
              setInitialEvent(String(focused.id)); setInitialReason(""); setInitialNote("");
            }}>{t("downtimeAddReason")}</button>}
          </div>}
          {canOperate && initialEvent === String(focused.id) && !focused.reason_id &&
            focused.stop_nature !== "planned" &&
            <form className={styles.form} onSubmit={(e) => { e.preventDefault();
              void run("set_downtime_initial", { event: focused.id, reason: initialReason,
                notes: initialNote }, () => { setInitialEvent(""); setInitialNote(""); });
            }}>
              <label>{t("downtimeInitialReason")}
                <select required value={initialReason} onChange={(e) => setInitialReason(e.target.value)}>
                  <option value="">{t("downtimeChooseReason")}</option>
                  {categories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{key?t(key):localName(row,lang)}</option>)}
                </select>
              </label>
              <label>{t("downtimeOperatorNote")}
                <textarea maxLength={2000} value={initialNote} onChange={(e) => setInitialNote(e.target.value)} />
              </label>
              <div className={styles.actions}><button className="primary" disabled={busy || !initialReason}>{t("save")}</button>
                <button type="button" onClick={() => setInitialEvent("")}>{t("cancel")}</button></div>
            </form>}
          {!focused.ended_at && <>
            {openLink.data?.relatedRequest?.id && onMaintenanceRepairOpen && <button type="button"
              onClick={() => onMaintenanceRepairOpen(String(openLink.data?.relatedRequest?.id))}>
              {t("downtimeRelatedMaintenance")} <bdi>{String(openLink.data.relatedRequest.code || "")}</bdi>
            </button>}
            <details className={styles.moreActions}>
              <summary>{t("downtimeMoreActions")}</summary>
              <div className={styles.actions}>
                <button type="button" onClick={() => setOpenAction("history")}>{t("downtimeViewHistory")}</button>
                {can("maintenance", "create") && !openLink.data?.relatedRequest && machine(focused.work_center_id) &&
                  <button type="button" onClick={() => setOpenAction("maintenance")}>{t("maintenanceRequestAction")}</button>}
              </div>
            </details>
            {openAction === "history" && <Dialog title={t("downtimeViewHistory")} t={t} onClose={() => setOpenAction("")}>
              {eventHistory}
            </Dialog>}
            {openAction === "maintenance" && can("maintenance", "create") &&
              <MaintenanceCreate {...{ snapshot: s, t, lang, command, can }} machine={machine(focused.work_center_id)}
                downtime={focused} onClose={() => setOpenAction("")}
                onCreated={id => { setOpenAction(""); openLink.reload(); onMaintenanceRepairOpen?.(id); }} />}
          </>}
        </div> : <p>{t("noResults")}</p>}
      </section>
    </div>
    {canReview && <details className={styles.card}>
      <summary>{t("downtimeRetroactive")}</summary>
      <p>{t("downtimeRetroactiveHelp")}</p>
      <form className={styles.form} onSubmit={(e) => { e.preventDefault();
        if (!retroMachine || !retroStart || !retroEnd) return;
        void run("record_missed_downtime", { work_center: retroMachine,
          started_at: localDateTimeToUtc(retroStart, zone),
          ended_at: localDateTimeToUtc(retroEnd, zone),
          reason: retroReason || null, notes: retroNote }, () => {
            setRetroStart(""); setRetroEnd(""); setRetroReason(""); setRetroNote("");
          });
      }}>
        <label>{t("machine")}<select required value={retroMachine} onChange={(e) => setRetroMachine(e.target.value)}>
          <option value="">{t("downtimeChooseMachine")}</option>
          {machines.filter(m => !m.archived).map((m) => <option key={String(m.id)} value={String(m.id)}>{localName(m, lang)}</option>)}
        </select></label>
        <label>{t("downtimeStarted")}<input required type="datetime-local" value={retroStart}
          onChange={(e) => setRetroStart(e.target.value)} /></label>
        <label>{t("downtimeEnded")}<input required type="datetime-local" value={retroEnd}
          onChange={(e) => setRetroEnd(e.target.value)} /></label>
        <label>{t("downtimeInitialReason")}<select value={retroReason} onChange={(e) => setRetroReason(e.target.value)}>
          <option value="">{t("downtimeUnclassified")}</option>
          {categories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{key?t(key):localName(row,lang)}</option>)}
        </select></label>
        <label>{t("downtimeOperatorNote")}<textarea maxLength={2000} value={retroNote}
          onChange={(e) => setRetroNote(e.target.value)} /></label>
        <button className="primary" disabled={busy}>{t("downtimeSaveRetroactive")}</button>
      </form>
    </details>}
  </section>;
}
