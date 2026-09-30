import { useEffect, useState } from "react";
import { formatTime, localName } from "@/components/ui";
import { localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import { formatDuration } from "@/utils/production-flow.mjs";
import { downtimeReasonChoices } from "@/utils/downtime-reasons";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
import styles from "./DowntimeCapture.module.css";
import LossImpactReview from "./LossImpactReview";

export default function DowntimeCapture({ snapshot: s, t, lang, command, can }: FeatureProps) {
  const [now, setNow] = useState(() => Date.now());
  const [initialEvent, setInitialEvent] = useState("");
  const [initialReason, setInitialReason] = useState("");
  const [initialNote, setInitialNote] = useState("");
  const [reviewId, setReviewId] = useState("");
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
  const events = s.tables.downtime_events || [];
  const machines = (s.tables.work_centers || []).filter((x) => !x.archived);
  const reasons = s.tables.downtime_reasons || [];
  const categories = downtimeReasonChoices.map(([name, key]) => ({
    row: reasons.find((r) => r.name === name && !r.parent_id), key,
  })).filter((option) => option.row);
  const open = events.filter((e) => !e.ended_at)
    .sort((a, b) => String(a.started_at).localeCompare(String(b.started_at)));
  const needsReview = events.filter((e) => e.ended_at && !e.approved_at)
    .sort((a, b) => String(b.ended_at).localeCompare(String(a.ended_at)));
  const endedUnclassified = events.filter((e) => e.ended_at && !e.reason_id &&
    e.stop_nature !== "planned")
    .sort((a, b) => String(b.ended_at).localeCompare(String(a.ended_at)));
  const focused = needsReview.find((e) => String(e.id) === reviewId) || needsReview[0];
  const focusedInitialIsCurrent = categories.some(({ row }) => row?.id === focused?.reason_id);
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
    .find((m) => String(m.user_id) === String(id))?.display_name || "—");
  const context = (event: Row) => {
    const item = (s.tables.production_orders || []).find((o) => o.id === event.order_id);
    const line = (s.tables.production_lines || []).find((l) => l.id === event.line_id);
    return <span>{line ? localName(line, lang) : "—"} · {item ? String(item.code || "—") : "—"}</span>;
  };
  const elapsed = (event: Row) => formatDuration(Math.max(0,
    Math.floor(((event.ended_at ? Date.parse(String(event.ended_at)) : now)
      - Date.parse(String(event.started_at))) / 60_000)), lang);

  async function run(name: string, args: Record<string, unknown>, done?: () => void) {
    setBusy(true);
    try { await command(name, { factory, ...args }); done?.(); }
    catch { /* The shared command handler displays the exact error. */ }
    finally { setBusy(false); }
  }
  return <section className={styles.page} aria-label={t("downtimeCaptureTitle")}>
    <header className={styles.heading}>
      <div><h2>{t("downtimeCaptureTitle")}</h2><p>{t("downtimeCaptureHelp")}</p></div>
      <div className={styles.metrics}>
        <span><strong>{open.length}</strong> {t("downtimeActive")}</span>
        <span><strong>{needsReview.length}</strong> {t("downtimeNeedsReview")}</span>
      </div>
    </header>

    <section className={styles.card} aria-labelledby="downtime-active-heading">
      <h3 id="downtime-active-heading">{t("downtimeActive")}</h3>
      {!open.length ? <p>{t("downtimeNoActive")}</p> : <div className={styles.grid}>
        {open.map((event) => <article className={styles.event} key={String(event.id)}>
          <div className={styles.eventHead}><strong>{localName(machine(event.work_center_id), lang)}</strong>
            <span>{elapsed(event)}</span></div>
          <p>{context(event)}</p>
          <p>{t("lossStopType")}: <strong>{stopName(event)}</strong></p>
          <small>{formatTime(event.started_at, lang, zone)}</small>
          {canOperate && <div className={styles.actions}>
            {!event.reason_id && event.stop_nature !== "planned" &&
              <button disabled={busy} onClick={() => {
              setInitialEvent(String(event.id)); setInitialReason(""); setInitialNote("");
            }}>{t("downtimeAddReason")}</button>}
          </div>}
          {canOperate && initialEvent === String(event.id) && !event.reason_id &&
            event.stop_nature !== "planned" &&
            <form className={styles.form} onSubmit={(e) => { e.preventDefault();
              void run("set_downtime_initial", { event: event.id, reason: initialReason,
                notes: initialNote }, () => { setInitialEvent(""); setInitialNote(""); });
            }}>
              <label>{t("downtimeInitialReason")}
                <select required value={initialReason} onChange={(e) => setInitialReason(e.target.value)}>
                  <option value="">{t("downtimeChooseReason")}</option>
                  {categories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{t(key)}</option>)}
                </select>
              </label>
              <label>{t("downtimeOperatorNote")}
                <textarea maxLength={2000} value={initialNote} onChange={(e) => setInitialNote(e.target.value)} />
              </label>
              <div className={styles.actions}><button className="primary" disabled={busy || !initialReason}>{t("save")}</button>
                <button type="button" onClick={() => setInitialEvent("")}>{t("cancel")}</button></div>
            </form>}
        </article>)}
      </div>}
    </section>

    {canOperate && endedUnclassified.length > 0 && <section className={styles.card}
      aria-labelledby="downtime-unclassified-heading">
      <h3 id="downtime-unclassified-heading">{t("downtimeUnclassified")}</h3>
      <div className={styles.grid}>{endedUnclassified.map((event) =>
        <article className={styles.event} key={String(event.id)}>
          <div className={styles.eventHead}><strong>{localName(machine(event.work_center_id), lang)}</strong>
            <span>{elapsed(event)}</span></div>
          <p>{context(event)}</p>
          <small>{formatTime(event.started_at, lang, zone)} — {formatTime(event.ended_at, lang, zone)}</small>
          <button disabled={busy} onClick={() => { setInitialEvent(String(event.id));
            setInitialReason(""); setInitialNote(""); }}>{t("downtimeAddReason")}</button>
          {initialEvent === String(event.id) && <form className={styles.form}
            onSubmit={(e) => { e.preventDefault(); void run("set_downtime_initial",
              { event: event.id, reason: initialReason, notes: initialNote },
              () => { setInitialEvent(""); setInitialNote(""); }); }}>
            <label>{t("downtimeInitialReason")}
              <select required value={initialReason} onChange={(e) => setInitialReason(e.target.value)}>
                <option value="">{t("downtimeChooseReason")}</option>
                {categories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{t(key)}</option>)}
              </select>
            </label>
            <label>{t("downtimeOperatorNote")}
              <textarea maxLength={2000} value={initialNote}
                onChange={(e) => setInitialNote(e.target.value)} />
            </label>
            <div className={styles.actions}><button className="primary" disabled={busy || !initialReason}>{t("save")}</button>
              <button type="button" onClick={() => setInitialEvent("")}>{t("cancel")}</button></div>
          </form>}
        </article>)}</div>
    </section>}

    {canReview && <section className={styles.card} aria-labelledby="downtime-review-heading">
      <h3 id="downtime-review-heading">{t("downtimeNeedsReview")} <span>{needsReview.length}</span></h3>
      {!needsReview.length ? <p>{t("downtimeReviewEmpty")}</p> : <div className={styles.review}>
        <div className={styles.reviewList}>
          {needsReview.map((e) => <button key={String(e.id)} type="button"
            aria-pressed={focused?.id === e.id} onClick={() => {
              setReviewId(String(e.id)); setCauseId(""); setEngineeringNote("");
            }}>
            <strong>{localName(machine(e.work_center_id), lang)}</strong>
            <span>{elapsed(e)} · {stopName(e)}</span>
          </button>)}
        </div>
        {focused && <div className={styles.reviewDetail} key={String(focused.id)}>
          <h4>{localName(machine(focused.work_center_id), lang)}</h4>
          <p>{context(focused)}</p>
          <dl>
            <div><dt>{t("downtimeStarted")}</dt><dd>{formatTime(focused.started_at, lang, zone)}</dd></div>
            <div><dt>{t("downtimeEnded")}</dt><dd>{formatTime(focused.ended_at, lang, zone)}</dd></div>
            <div><dt>{t("duration")}</dt><dd>{elapsed(focused)}</dd></div>
            <div><dt>{t("lossStopType")}</dt><dd>{stopName(focused)}</dd></div>
            <div><dt>{t("downtimeOperatorNote")}</dt><dd>{String(focused.initial_note || focused.notes || "—")}</dd></div>
            <div><dt>{t("downtimeEnteredBy")}</dt><dd>{personName(focused.initial_entered_by || focused.created_by)}</dd></div>
            {focused.retroactive && <div><dt>{t("downtimeRetroactive")}</dt><dd>{t("downtimeYes")}</dd></div>}
          </dl>
          {focused.stop_nature !== "planned" && <><label>{t("downtimeApprovedCause")}
            <select value={causeId || (focusedInitialIsCurrent ? String(focused.reason_id) : "")}
              onChange={(e) => setCauseId(e.target.value)}>
              <option value="">{t("downtimeChooseReason")}</option>
              {categories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{t(key)}</option>)}
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
        </div>}
      </div>}
    </section>}

    <LossImpactReview {...{ snapshot: s, t, lang, command, can }} />

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
          {machines.map((m) => <option key={String(m.id)} value={String(m.id)}>{localName(m, lang)}</option>)}
        </select></label>
        <label>{t("downtimeStarted")}<input required type="datetime-local" value={retroStart}
          onChange={(e) => setRetroStart(e.target.value)} /></label>
        <label>{t("downtimeEnded")}<input required type="datetime-local" value={retroEnd}
          onChange={(e) => setRetroEnd(e.target.value)} /></label>
        <label>{t("downtimeInitialReason")}<select value={retroReason} onChange={(e) => setRetroReason(e.target.value)}>
          <option value="">{t("downtimeUnclassified")}</option>
          {categories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{t(key)}</option>)}
        </select></label>
        <label>{t("downtimeOperatorNote")}<textarea maxLength={2000} value={retroNote}
          onChange={(e) => setRetroNote(e.target.value)} /></label>
        <button className="primary" disabled={busy}>{t("downtimeSaveRetroactive")}</button>
      </form>
    </details>}
    {can("downtime", "create") && <details className={styles.card}>
      <summary>{t("configuration")}</summary>
      <p>{t("downtimeCurrentReasonsHelp")}</p>
      <ul>{downtimeReasonChoices.map(([, key]) => <li key={key}>{t(key)}</li>)}</ul>
    </details>}
  </section>;
}
