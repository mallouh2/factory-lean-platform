import { useState } from "react";
import { formatDuration } from "@/utils/production-flow.mjs";
import { calculateProductionLoss, suggestScrapCalibration } from
  "@/utils/production-loss-impact.mjs";
import { downtimeReasonChoices } from "@/utils/downtime-reasons";
import { hasDeferredWork, validateActualScrap } from "@/utils/production-loss-actuals.mjs";
import { formatTime, localName } from "@/components/ui";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
import styles from "./DowntimeCapture.module.css";
import { useHistoryData } from "@/hooks/useHistoryData";
import HistoryQueryState from "@/components/HistoryQueryState";

function lossDuration(value: number, lang: FeatureProps["lang"],
  t: FeatureProps["t"]) {
  if (value > 0 && value < 10 && !Number.isInteger(value))
    return `${new Intl.NumberFormat(lang === "ar" ? "ar-u-nu-arab" : "en", {
      maximumFractionDigits: 2,
    }).format(value)} ${t("minutesShort")}`;
  return formatDuration(value, lang);
}
function lossGapText(item: string, t: FeatureProps["t"]) {
  const named = [
    ["Production rate for ", "lossGapRate"],
    ["Alternative rate for ", "lossGapAlternativeRate"],
    ["Recovery capacity for ", "lossGapRecovery"],
    ["Deferred-work decision for ", "lossGapDeferred"],
    ["Reliable buffer coverage for ", "lossGapBuffer"],
  ] as const;
  for (const [prefix, key] of named) if (item.startsWith(prefix))
    return `${t(key)}: ${item.slice(prefix.length)}`;
  const simple: Record<string, string> = {
    "Historical event context snapshot": "lossGapHistorical",
    "Stopped machine context": "lossGapMachine",
    "Overlapping planned Product Items": "lossGapOverlap",
    "Active alternative context": "lossGapAlternative",
    "Multiple planned output units in one event": "lossGapUnits",
    "Multiple deferred output units in one event": "lossGapDeferredUnits",
    "Product changes during stop; scrap estimate needs review": "lossGapScrapProduct",
    "Shutdown/restart scrap expectation for stopped machine": "lossGapScrapExpected",
    "Shutdown/restart scrap quantities and unit": "lossGapScrapValues",
  };
  return simple[item] ? t(simple[item]) : item;
}

type ReviewData = { event: Row; actual: Row | null; saved: Row | null;
  correction: Row | null; calculation: ReturnType<typeof calculateProductionLoss>;
  suggestions: Array<NonNullable<ReturnType<typeof suggestScrapCalibration>>> };
function EventImpactDetail(props: FeatureProps & { data: ReviewData }) {
  const { snapshot: s, t, lang, command, can, data } = props;
  const { event, actual, correction, saved, calculation, suggestions } = data;
  const effectiveEvent = { ...event,
    stop_nature: correction?.stop_nature || event.stop_nature,
    planned_activity: correction?.planned_activity || event.planned_activity };
  const estimate = saved?.result && typeof saved.result === "object"
    ? saved.result as typeof calculation : calculation;
  const productId = estimate.assumptions[0]?.product_id;
  const profile = (s.tables.production_loss_profiles || []).find((x) =>
    x.work_center_id === event.work_center_id && x.product_id === productId);
  const canEngineer = can("downtime", "edit");
  const canCalibrate = canEngineer && can("centers", "edit");
  const [scrap, setScrap] = useState(String(actual?.scrap_quantity ?? ""));
  const [scrapUnit, setScrapUnit] = useState(String(actual?.scrap_unit || "kg"));
  const [shutdown, setShutdown] = useState(String(actual?.shutdown_scrap_quantity ?? ""));
  const [restart, setRestart] = useState(String(actual?.restart_scrap_quantity ?? ""));
  const [recovery, setRecovery] = useState(String(actual?.recovery_minutes ?? ""));
  const [lossMinutes, setLossMinutes] = useState(String(actual?.actual_loss_minutes ?? ""));
  const [lostQuantity, setLostQuantity] = useState(String(actual?.actual_lost_output_quantity ?? ""));
  const [lostUnit, setLostUnit] = useState(String(actual?.actual_lost_output_unit || estimate.unit || "meter"));
  const [actualFormError, setActualFormError] = useState("");
  const [nature, setNature] = useState(String(correction?.stop_nature || event.stop_nature || "unplanned"));
  const [reason, setReason] = useState(String(correction?.reason_id || event.reason_id || ""));
  const [activity, setActivity] = useState(String(correction?.planned_activity || event.planned_activity || ""));
  const [correctionNote, setCorrectionNote] = useState("");
  const [dismissed, setDismissed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const scrapValidation = validateActualScrap(scrap, shutdown, restart);
  const deferredRelevant = hasDeferredWork(estimate, actual);
  const reasonName = (id: unknown) => localName((s.tables.downtime_reasons || [])
    .find((x) => x.id === id), lang);
  const activityKey = String(correction?.planned_activity || event.planned_activity || "");
  const stopDescription = effectiveEvent.stop_nature === "planned"
    ? `${t("lossPlanned")} — ${t(`lossActivity_${activityKey}`)}`
    : effectiveEvent.stop_nature === "legacy_unknown"
      ? `${t("lossLegacyUnknown")} — ${reasonName(event.reason_id)}`
      : `${t("lossUnplanned")} — ${reasonName(correction?.reason_id || event.reason_id)}`;
  const variance = estimate.estimated_total_scrap !== null &&
    actual?.scrap_quantity !== null && actual?.scrap_quantity !== undefined &&
    String(actual.scrap_unit) === String(estimate.scrap_unit)
      ? Number(actual.scrap_quantity) - Number(estimate.estimated_total_scrap) : null;

  async function run(name: string, args: Record<string, unknown>) {
    setBusy(true); setError("");
    try { await command(name, { factory: s.factory?.id, ...args }); return true; }
    catch (cause) {
      const message = cause instanceof Error ? cause.message : "error";
      if (name === "record_production_loss_actuals") setActualFormError(message);
      else setError(message);
      return false;
    }
    finally { setBusy(false); }
  }
  return <div className={styles.reviewDetail}>
    <h4>{stopDescription}</h4>
    {correction && <p>{t("lossCorrectionRecorded")}: {String(correction.note)}</p>}
    <dl>
      <div><dt>{t("lossRawStop")}</dt><dd>{lossDuration(estimate.raw_stop_minutes, lang, t)}</dd></div>
      <div><dt>{t("lossNonProduction")}</dt><dd>{lossDuration(estimate.non_production_minutes, lang, t)}</dd></div>
      <div><dt>{t("lossEffective")}</dt><dd>{estimate.effective_loss_minutes === null
        ? "—" : lossDuration(estimate.effective_loss_minutes, lang, t)}</dd></div>
      <div><dt>{t("lossImpact")}</dt><dd>{estimate.impact_level === null
        ? "—" : t(`lossLevel_${estimate.impact_level}`)}</dd></div>
      <div><dt>{t("lossLostOutput")}</dt><dd>{estimate.estimated_lost_output_quantity === null
        ? "—" : `${estimate.estimated_lost_output_quantity} ${estimate.unit || ""}`}</dd></div>
      <div><dt>{t("lossDeferred")}</dt><dd>{estimate.deferred_quantity ?? "—"}
        {" "}{estimate.deferred_unit || ""}</dd></div>
      <div><dt>{t("lossRecovery")}</dt><dd>{estimate.estimated_recovery_minutes === null
        ? "—" : formatDuration(estimate.estimated_recovery_minutes, lang)}</dd></div>
      <div><dt>{t("lossEstimatedScrap")}</dt><dd>{estimate.estimated_total_scrap === null
        ? "—" : `${estimate.estimated_total_scrap} ${estimate.scrap_unit || ""}`}</dd></div>
      <div><dt>{t("lossShutdownScrap")}</dt><dd>{estimate.estimated_shutdown_scrap ?? "—"}
        {" "}{estimate.scrap_unit || ""}</dd></div>
      <div><dt>{t("lossRestartScrap")}</dt><dd>{estimate.estimated_restart_scrap ?? "—"}
        {" "}{estimate.scrap_unit || ""}</dd></div>
      <div><dt>{t("lossMitigation")}</dt><dd>{estimate.mitigation.length
        ? estimate.mitigation.map((item: string) => t(`lossMitigation_${item}`)).join(", ")
        : t("lossMitigation_none")}</dd></div>
      <div><dt>{t("lossActualScrap")}</dt><dd>{actual?.scrap_quantity ?? "—"} {actual?.scrap_unit || ""}</dd></div>
      <div><dt>{t("lossActualLossTime")}</dt><dd>{actual?.actual_loss_minutes == null
        ? "—" : lossDuration(Number(actual.actual_loss_minutes), lang, t)}</dd></div>
      <div><dt>{t("lossActualLostQuantity")}</dt><dd>{actual?.actual_lost_output_quantity ?? "—"}
        {" "}{actual?.actual_lost_output_unit || ""}</dd></div>
      {deferredRelevant && <div><dt>{t("lossActualRecovery")}</dt><dd>{actual?.recovery_minutes === null ||
        actual?.recovery_minutes === undefined ? "—"
        : formatDuration(Number(actual.recovery_minutes), lang)}</dd></div>}
      <div><dt>{t("lossConfidence")}</dt><dd>{t(`lossConfidence_${estimate.confidence}`)}</dd></div>
      <div><dt>{t("lossModel")}</dt><dd>V{estimate.model_version}</dd></div>
      <div><dt>{t("lossCalculatedAt")}</dt><dd>{formatTime(estimate.calculated_at,
        lang, String(s.factory?.timezone || "UTC"))}</dd></div>
    </dl>
    {variance !== null && <p>{t("lossScrapVariance")}: {variance > 0 ? "+" : ""}{variance}
      {" "}{estimate.scrap_unit} {estimate.estimated_total_scrap
        ? `(${variance > 0 ? "+" : ""}${(variance /
          Number(estimate.estimated_total_scrap) * 100).toFixed(1)}%)` : ""}</p>}
    {actual?.recovery_minutes !== null && actual?.recovery_minutes !== undefined &&
      estimate.estimated_recovery_minutes !== null &&
      <p>{t("lossRecoveryVariance")}: {formatDuration(
        Number(actual.recovery_minutes) - Number(estimate.estimated_recovery_minutes),
        lang, true)}</p>}
    {estimate.readiness === "INCOMPLETE" ? <div role="status">
      <strong>{t("lossMissing")}</strong>
      <ul>{estimate.missing.map((item: string) =>
        <li key={item}>{lossGapText(item, t)}</li>)}</ul>
      <p>{t(estimate.missing.includes("Historical event context snapshot")
        ? "lossHistoricalGapHelp" : "lossConfigureHint")}</p>
    </div> : <p>{t(estimate.readiness === "READY" ? "lossReady" : "lossNotApplicable")}</p>}
    {saved ? <p>{t("lossEstimateSaved")}</p> : canEngineer && event.ended_at &&
      calculation.readiness === "READY" &&
      <button type="button" disabled={busy} onClick={() =>
        void run("save_production_loss_estimate", {
          event: event.id,
        })}>{t("lossSaveEstimate")}</button>}
    {canEngineer && event.ended_at && <form className={styles.actualForm}
      noValidate onSubmit={(e) => { e.preventDefault();
        if (scrapValidation.error) { setActualFormError(scrapValidation.error); return; }
        if ([lossMinutes, lostQuantity, recovery].some((value) =>
          value !== "" && (!Number.isFinite(Number(value)) || Number(value) < 0))) {
          setActualFormError("lossActualNonnegative"); return;
        }
        if (scrapValidation.total === null && lossMinutes === "" && lostQuantity === "" &&
          (!deferredRelevant || recovery === "")) {
          setActualFormError("lossActualAtLeastOne"); return;
        }
        setActualFormError("");
        void run("record_production_loss_actuals", {
          event: event.id, scrap_quantity: scrapValidation.total,
          scrap_unit: scrapValidation.total === null ? null : scrapUnit,
          shutdown_scrap: scrapValidation.shutdown,
          restart_scrap: scrapValidation.restart,
          actual_loss_minutes: lossMinutes === "" ? null : Number(lossMinutes),
          actual_lost_output_quantity: lostQuantity === "" ? null : Number(lostQuantity),
          actual_lost_output_unit: lostQuantity === "" ? null : lostUnit,
          recovery_minutes: !deferredRelevant || recovery === "" ? null : Number(recovery),
        }).then((saved) => {
          if (saved && scrap === "" && scrapValidation.total !== null)
            setScrap(String(scrapValidation.total));
        }); }}>
      <h5>{t("lossRecordActual")}</h5>
      <section className={styles.actualGroup}>
        <h6>{t("lossActualImpactGroup")}</h6>
        <label>{t("lossActualLossTime")} <small>{t("lossOptional")}</small>
          <span className={styles.valueWithUnit} dir="ltr"><input type="number" min="0" step="any"
            value={lossMinutes} onChange={(e) => { setLossMinutes(e.target.value); setActualFormError(""); }} />
            <span>{t("minutesShort")}</span></span>
          <small>{t("lossActualLossTimeHelp")}</small></label>
        <label>{t("lossActualLostQuantity")} <small>{t("lossOptional")}</small>
          <span className={styles.valueWithUnit} dir="ltr"><input type="number" min="0" step="any"
            value={lostQuantity} onChange={(e) => { setLostQuantity(e.target.value); setActualFormError(""); }} />
            <select aria-label={t("lossActualLostUnit")} value={lostUnit}
              onChange={(e) => setLostUnit(e.target.value)}>
              <option value="meter">{t("meterShort")}</option><option value="piece">{t("pieceShort")}</option>
            </select></span>
          <small>{t("lossActualLostQuantityHelp")}</small></label>
      </section>
      <section className={styles.actualGroup}>
        <h6>{t("lossActualScrapGroup")}</h6>
        <label>{t("lossActualScrap")} <small>{t("lossOptional")}</small>
          <span className={styles.valueWithUnit} dir="ltr"><input type="number" min="0" step="any"
            value={scrap} onChange={(e) => { setScrap(e.target.value); setActualFormError(""); }} />
            <select aria-label={t("lossScrapUnit")} value={scrapUnit}
              onChange={(e) => setScrapUnit(e.target.value)}>
              {!(["kg", "piece"].includes(scrapUnit)) && <option value={scrapUnit}>{scrapUnit}</option>}
              <option value="kg">{t("lossKg")}</option><option value="piece">{t("lossPiece")}</option>
            </select></span>
          <small>{t("lossActualScrapHelp")}</small></label>
        <div className={styles.actualParts}>
          <label>{t("lossActualShutdown")} <small>{t("lossOptional")}</small>
            <input type="number" min="0" step="any" value={shutdown}
              onChange={(e) => { setShutdown(e.target.value); setActualFormError(""); }} />
            <small>{t("lossActualShutdownHelp")}</small></label>
          <label>{t("lossActualRestart")} <small>{t("lossOptional")}</small>
            <input type="number" min="0" step="any" value={restart}
              onChange={(e) => { setRestart(e.target.value); setActualFormError(""); }} />
            <small>{t("lossActualRestartHelp")}</small></label>
        </div>
        <small>{t("lossScrapSharedUnitHelp")} {t(scrapUnit === "piece" ? "lossPiece" : "lossKg")}</small>
        {(scrapValidation.error || actualFormError) && <p className={styles.actualError}
          role="alert">{t(scrapValidation.error || actualFormError)}</p>}
      </section>
      {deferredRelevant && <section className={styles.actualGroup}>
        <h6>{t("lossActualDeferredGroup")}</h6>
        <label>{t("lossActualRecovery")} <small>{t("lossOptional")}</small>
          <span className={styles.valueWithUnit} dir="ltr"><input type="number" min="0" step="any"
            value={recovery} onChange={(e) => { setRecovery(e.target.value); setActualFormError(""); }} />
            <span>{t("minutesShort")}</span></span>
          <small>{t("lossActualRecoveryHelp")}</small></label>
      </section>}
      <button className="primary" disabled={busy}>{t("save")}</button>
    </form>}
    {canEngineer && <details>
      <summary>{t("lossCorrectClassification")}</summary>
      <p>{t("lossCorrectionHelp")}</p>
      <form className={styles.form} onSubmit={(e) => { e.preventDefault();
        void run("correct_downtime_classification", { event: event.id,
          nature, reason: nature === "unplanned" ? reason : null,
          activity: nature === "planned" ? activity : null, note: correctionNote });
      }}>
        <label>{t("lossStopType")}<select value={nature}
          onChange={(e) => setNature(e.target.value)}>
          <option value="unplanned">{t("lossUnplanned")}</option>
          <option value="planned">{t("lossPlanned")}</option>
        </select></label>
        {nature === "unplanned" ? <label>{t("downtimeInitialReason")}
          <select required value={reason} onChange={(e) => setReason(e.target.value)}>
            <option value="">{t("downtimeChooseReason")}</option>
            {downtimeReasonChoices.map(([name, key]) => {
              const row = (s.tables.downtime_reasons || [])
                .find((x) => x.name === name && !x.parent_id);
              return row ? <option value={String(row.id)} key={String(row.id)}>{t(key)}</option> : null;
            })}
          </select></label> : <label>{t("lossPlannedActivity")}
          <select required value={activity} onChange={(e) => setActivity(e.target.value)}>
            <option value="">{t("lossChooseActivity")}</option>
            {(["cleaning", "changeover", "preventive_maintenance",
              "inspection", "planned_process", "other"] as const).map((name) =>
              <option value={name} key={name}>{t(`lossActivity_${name}`)}</option>)}
          </select></label>}
        <label>{t("lossCorrectionReason")}
          <textarea required minLength={3} maxLength={2000} value={correctionNote}
            onChange={(e) => setCorrectionNote(e.target.value)} /></label>
        <button disabled={busy || correctionNote.trim().length < 3}>{t("save")}</button>
      </form>
    </details>}
    {canCalibrate && profile && !dismissed && suggestions.map((suggestion) =>
      suggestion && <section key={suggestion.parameter}>
        <h5>{t("lossCalibration")}</h5>
        <p>{suggestion.samples} {t("lossComparableEvents")} · {suggestion.parameter === "shutdown"
          ? t("lossShutdownScrap") : t("lossRestartScrap")}: {suggestion.suggested_value}
          {" "}{String(profile.scrap_unit || "")}</p>
        <div className={styles.actions}>
          <button type="button" disabled={busy} onClick={() => setDismissed(true)}>{t("lossKeepCurrent")}</button>
          <button type="button" disabled={busy} onClick={() => {
            void run("configure_production_loss_profile", {
              work_center: event.work_center_id, product: productId,
              can_defer: profile.can_defer, scrap_expected: true,
              shutdown_scrap: suggestion.parameter === "shutdown"
                ? suggestion.suggested_value : profile.shutdown_scrap_quantity,
              restart_scrap: suggestion.parameter === "restart"
                ? suggestion.suggested_value : profile.restart_scrap_quantity,
              scrap_unit: profile.scrap_unit,
            });
          }}>{t("lossApproveSuggestion")}</button>
        </div>
      </section>)}
    {error && <p role="alert">{t(error)}</p>}
  </div>;
}

export default function LossImpactReview(props: FeatureProps) {
  const { snapshot: s, t, lang } = props;
  const [page, setPage] = useState(1);
  const [selectedId, setSelectedId] = useState("");
  const factory = String(s.factory!.id);
  const list = useHistoryData<{ rows: Row[]; total: number; pages: number }>(
    `/api/loss-review?${new URLSearchParams({ factory, page: String(page) })}`, s.fetchedAt);
  const selected = list.data?.rows.find(row => String(row.id) === selectedId) || list.data?.rows[0];
  const detail = useHistoryData<ReviewData>(selected
    ? `/api/loss-review?${new URLSearchParams({ factory, event: String(selected.id) })}` : null, s.fetchedAt);
  const machines = s.tables.work_centers || [];
  return <section className={styles.card}>
    <h3>{t("lossImpact")}</h3>
    <HistoryQueryState {...list} t={t} />
    {list.data && (!list.data.rows.length ? <p>{t("downtimeReviewEmpty")}</p> : <>
      <div className={styles.review}>
        <div className={styles.reviewList}>
          {list.data.rows.map(item => <button key={String(item.id)} type="button"
            aria-pressed={item.id === selected?.id}
            onClick={() => setSelectedId(String(item.id))}>
            <strong>{localName(machines.find(row => row.id === item.work_center_id), lang)}</strong>
            <span>{String(item.started_at).slice(0, 16)}</span>
          </button>)}
        </div>
        <div><HistoryQueryState {...detail} t={t} />
          {detail.data && <EventImpactDetail key={String(detail.data.event.id)}
            {...props} data={detail.data} />}
        </div>
      </div>
      <nav className="history-pagination" aria-label={t("lossReviewPages")}>
        <button disabled={list.loading || page <= 1}
          onClick={() => { setPage(value => value - 1); setSelectedId(""); }}>{t("previous")}</button>
        <span>{page.toLocaleString(lang)} / {list.data.pages.toLocaleString(lang)}</span>
        <button disabled={list.loading || page >= list.data.pages}
          onClick={() => { setPage(value => value + 1); setSelectedId(""); }}>{t("next")}</button>
      </nav>
    </>)}
  </section>;
}
