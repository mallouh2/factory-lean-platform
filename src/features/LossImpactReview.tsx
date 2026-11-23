import { useState, type ReactNode } from "react";
import { formatDuration } from "@/utils/production-flow.mjs";
import { calculateProductionLoss, suggestScrapCalibration } from
  "@/utils/production-loss-impact.mjs";
import { hasDeferredWork, validateActualScrap } from "@/utils/production-loss-actuals.mjs";
import { Dialog, formatTime, localName } from "@/components/ui";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
import styles from "./DowntimeCapture.module.css";
import { useHistoryData } from "@/hooks/useHistoryData";
import HistoryQueryState from "@/components/HistoryQueryState";
import { MaintenanceCreate } from "./MaintenanceRequest";

function lossDuration(value: number, lang: FeatureProps["lang"],
  t: FeatureProps["t"]) {
  if (value > 0 && !Number.isInteger(value))
    return `${new Intl.NumberFormat(lang === "ar" ? "ar-u-nu-arab" : "en", {
      maximumFractionDigits: 3,
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
    "Frozen maintenance approval evidence": "lossGapMaintenanceApproval",
    "Historical production demand and routing evidence": "lossGapMaintenanceDemand",
    "Approved maintenance conflicts with intended production": "lossGapMaintenanceConflict",
    "Active alternative ownership evidence": "lossGapMaintenanceOwner",
    "Comparable alternative line rate": "lossGapAlternativeLineRate",
  };
  return simple[item] ? t(simple[item]) : item;
}

type ReviewData = { event: Row; actual: Row | null; saved: Row | null;
  correction: Row | null; corrections?: Row[]; relatedRequest?: Row | null;
  scrap?: { state: string; kg?: number; startup?: number | null; entries?: number };
  current_calculation?: ReturnType<typeof calculateProductionLoss> | null;
  calculation: ReturnType<typeof calculateProductionLoss>;
  maintenance?: { evidence: Row; review_state: string };
  suggestions: Array<NonNullable<ReturnType<typeof suggestScrapCalibration>>> };
function EventImpactDetail(props: FeatureProps & { data: ReviewData; children?: ReactNode; history?: ReactNode }) {
  const { snapshot: s, t, lang, command, can, data } = props;
  const { event, actual, correction, saved, calculation, suggestions, scrap: linked } = data;
  const effectiveEvent = { ...event,
    stop_nature: correction?.stop_nature || event.stop_nature,
    planned_activity: correction ? correction.planned_activity : event.planned_activity };
  const estimate = saved?.result && typeof saved.result === "object"
    ? saved.result as typeof calculation : calculation;
  const productId = estimate.assumptions[0]?.product_id;
  const profile = (s.tables.production_loss_profiles || []).find((x) =>
    x.work_center_id === event.work_center_id && x.product_id === productId);
  const canEngineer = can("downtime", "edit");
  const canCalibrate = canEngineer && can("centers", "edit");
  const [scrap, setScrap] = useState(String(actual?.scrap_unit==='kg' ? actual.scrap_quantity ?? '' : ''));
  const [scrapUnit] = useState('kg');
  const [shutdown, setShutdown] = useState(String(actual?.scrap_unit==='kg' ? actual.shutdown_scrap_quantity ?? '' : ''));
  const [restart, setRestart] = useState(String(actual?.scrap_unit==='kg' ? actual.restart_scrap_quantity ?? '' : ''));
  const [recovery, setRecovery] = useState(String(actual?.recovery_minutes ?? ""));
  const [lossMinutes, setLossMinutes] = useState(String(actual?.actual_loss_minutes ?? ""));
  const [lostQuantity, setLostQuantity] = useState(String(actual?.actual_lost_output_quantity ?? ""));
  const [lostUnit, setLostUnit] = useState(String(actual?.actual_lost_output_unit || estimate.unit || "meter"));
  const [action, setAction] = useState("");
  const [sourceConfirmed, setSourceConfirmed] = useState(false);
  const [observationSaved, setObservationSaved] = useState(false);
  const [actualFormError, setActualFormError] = useState("");
  const [nature, setNature] = useState(effectiveEvent.stop_nature === "planned" ? "planned" : "unplanned");
  const [reason, setReason] = useState(String(correction?.reason_id || event.reason_id || ""));
  const [activity, setActivity] = useState(String(correction?.planned_activity || event.planned_activity || ""));
  const [correctionNote, setCorrectionNote] = useState("");
  const [dismissed, setDismissed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const scrapValidation = validateActualScrap(scrap, shutdown, restart);
  const canObserveScrap = !linked || linked.state === "unlinked";
  const current = data.current_calculation || estimate;
  const zone = String(s.factory?.timezone || "UTC");
  const fmt = new Intl.NumberFormat(lang === "ar" ? "ar-u-nu-arab" : "en", { maximumFractionDigits: 3 });
  const time = (value: number | null) => value == null
    ? t("downtimeSourceUnknown") : lossDuration(value, lang, t);
  const quantity = (value: number | null, unit: string | null) => value == null
    ? t("downtimeSourceUnknown") : [fmt.format(value), unit === "meter" ? t("meterShort")
      : unit === "piece" ? t("pieceShort") : unit === "kg" ? t("kg") : unit].filter(Boolean).join(" ");
  const deferredRelevant = hasDeferredWork(estimate, actual);
  const reasonName = (id: unknown) => localName((s.tables.downtime_reasons || [])
    .find((x) => x.id === id), lang);
  const classification = (source: Row) => source.stop_nature === "planned"
    ? `${t("lossPlanned")} · ${t(`lossActivity_${source.planned_activity}`)}`
    : `${t(source.stop_nature === "unplanned" ? "lossUnplanned" : "lossLegacyUnknown")} · ${source.reason_id
      ? reasonName(source.reason_id) : t("downtimeUnclassified")}`;
  const canObserve = canEngineer && !actual && !observationSaved && event.ended_at;
  const machine = s.tables.work_centers?.find(row => row.id === event.work_center_id);
  const related = data.relatedRequest;
  const canCreateMaintenance = !related && machine && can("maintenance", "create");
  const closeAction = () => setAction("");
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
  const saveEstimate = !saved && canEngineer && event.ended_at && calculation.readiness === "READY"
    ? <button type="button" disabled={busy} onClick={() =>
      void run("save_production_loss_estimate", { event: event.id })}>{t("lossSaveEstimate")}</button>
    : null;
  const calibration = canCalibrate && profile?.scrap_unit==='kg' && !dismissed && suggestions.map((suggestion) =>
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
              scrap_unit: 'kg',
            });
          }}>{t("lossApproveSuggestion")}</button>
        </div>
      </section>);
  return <div className={styles.reviewDetail}>
    <section className={styles.outcome} aria-label={t("lossImpact")}>
      <h4>{t("lossImpact")}</h4>
      {data.current_calculation && <p>{t("downtimeCurrentRecalculation")}</p>}
      <dl>
        <div><dt>{t("lossEffective")}</dt><dd>{time(current.effective_loss_minutes)}</dd></div>
        {current.estimated_lost_output_quantity != null && <div>
          <dt>{t("lossLostOutput")}</dt><dd>{quantity(current.estimated_lost_output_quantity, current.unit)}</dd>
        </div>}
        {linked?.state === "recorded" && <div><dt>{t("downtimeLinkedScrap")}</dt>
          <dd>{quantity(linked.kg ?? null, "kg")}</dd></div>}
      </dl>
      <p>{t(current.effective_loss_minutes == null ? "downtimeLossEvidenceMissing"
        : current.effective_loss_minutes === 0
          ? event.blocking_at_start === false ? "downtimeNonblockingResult" : "downtimeZeroImpact"
          : "downtimeLossSource")}</p>
    </section>
    {props.children}
    {event.approved_at && saveEstimate}
    {related?.id && props.onMaintenanceRepairOpen && can("maintenance", "view") &&
      <button type="button" onClick={() => props.onMaintenanceRepairOpen?.(String(related.id))}>
        {t("downtimeRelatedMaintenance")} <bdi>{String(related.code || "")}</bdi>
      </button>}
    <details className={styles.moreActions}>
      <summary>{t("downtimeMoreActions")}</summary>
      <div className={styles.actions}>
        <button type="button" onClick={() => setAction("evidence")}>{t("downtimeCalculationDetails")}</button>
        {canEngineer && <button type="button" onClick={() => setAction("correct")}>{t("downtimeCorrectData")}</button>}
        {canObserve && <button type="button" onClick={() => setAction("observe")}>{t("downtimeExceptionalObservation")}</button>}
        {(props.history || data.corrections?.length || correction || actual) &&
          <button type="button" onClick={() => setAction("history")}>{t("downtimeViewHistory")}</button>}
        {canCreateMaintenance && <button type="button" onClick={() => setAction("maintenance")}>{t("maintenanceRequestAction")}</button>}
      </div>
    </details>
    {action === "evidence" && <Dialog title={t(saved ? "downtimeSavedCalculation" : "downtimeCalculationDetails")}
      t={t} onClose={closeAction} busy={busy}><div className={styles.reviewDetail}>
    {linked?.state === "recorded" && <p>{t("downtimeLinkedStartup")} {quantity(linked.startup ?? null, "kg")}</p>}
    {linked?.state !== "recorded" && <p>{t(linked?.state === "unverified" ? "downtimeScrapUnverified"
      : linked?.state === "unavailable" ? "downtimeScrapUnavailable" : "downtimeScrapUnlinked")}</p>}
    {saved && data.maintenance?.review_state !== "CURRENT" && <p role="status">
      <strong>{t(data.maintenance?.review_state === "EVIDENCE_CHANGED_AFTER_REVIEW"
        ? "lossMaintenanceEvidenceChanged" : "lossMaintenanceEvidenceUnknown")}</strong>
      {" "}{t("lossMaintenanceHistoryRetained")}
    </p>}
    <dl>
      {([
        ["lossRawStop", estimate.raw_stop_minutes],
        ["lossEffective", estimate.effective_loss_minutes],
        ["lossNonProduction", estimate.non_production_minutes],
        ["lossMaintenanceApproved", estimate.approved_maintenance_minutes],
        ["lossMaintenanceOutside", estimate.outside_window_minutes],
        ["lossRecovery", estimate.estimated_recovery_minutes],
      ] as const).map(([label, value]) => value != null && value > 0 && <div key={label}>
        <dt>{t(label)}</dt><dd>{time(value)}</dd>
      </div>)}
      {([
        ["lossLostOutput", estimate.estimated_lost_output_quantity, estimate.unit],
        ["lossEstimatedAlternativeRecovery", estimate.estimated_alternative_recovered_quantity, estimate.unit],
        ["lossDeferred", estimate.deferred_quantity, estimate.deferred_unit],
        ["lossEstimatedScrap", estimate.estimated_total_scrap, estimate.scrap_unit],
      ] as const).map(([label, value, unit]) => value != null && value > 0 && <div key={label}>
        <dt>{t(label)}</dt><dd>{quantity(value, unit)}</dd>
      </div>)}
    </dl>
    {estimate.assumptions.some(segment => segment.alternative_line_recovery === "DESTINATION_DEMAND") &&
      <p>{t("lossAlternativeDestinationDemand")}</p>}
    {estimate.readiness === "INCOMPLETE" ? <div role="status">
      <strong>{t("lossMissing")}</strong>
      <ul>{estimate.missing.map((item: string) =>
        <li key={item}>{lossGapText(item, t)}</li>)}</ul>
      <p>{t(estimate.missing.includes("Historical event context snapshot")
        ? "lossHistoricalGapHelp" : "lossConfigureHint")}</p>
    </div> : <p>{t(estimate.readiness === "READY" ? "lossReady" : "lossNotApplicable")}</p>}
    {saved ? <p>{t("lossEstimateSaved")} · {formatTime(estimate.calculated_at, lang, zone)}</p>
      : !event.approved_at && saveEstimate}
    {calibration}
    </div></Dialog>}
    {action === "observe" && canObserve && <Dialog title={t("downtimeExceptionalObservation")} t={t} onClose={closeAction} busy={busy}>
      <form className={styles.actualForm}
      noValidate onSubmit={(e) => { e.preventDefault();
        if (!sourceConfirmed) return;
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
          if (saved) { setObservationSaved(true); closeAction(); }
        }); }}>
      <p>{t("downtimeExceptionalHelp")}</p>
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
              <option value="meter">{t("meterShort")}</option><option value="piece">{t("pieceShort")}</option><option value="kg">{t("kg")}</option>
            </select></span>
          <small>{t("lossActualLostQuantityHelp")}</small></label>
      </section>
      {canObserveScrap && <section className={styles.actualGroup}>
        <h6>{t("lossActualScrapGroup")}</h6>
        <label>{t("lossActualScrap")} <small>{t("lossOptional")}</small>
          <span className={styles.valueWithUnit} dir="ltr"><input type="number" min="0" step="any"
            value={scrap} onChange={(e) => { setScrap(e.target.value); setActualFormError(""); }} />
            <span aria-label={t('lossScrapUnit')}>kg</span></span>
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
      </section>}
      {deferredRelevant && <section className={styles.actualGroup}>
        <h6>{t("lossActualDeferredGroup")}</h6>
        <label>{t("lossActualRecovery")} <small>{t("lossOptional")}</small>
          <span className={styles.valueWithUnit} dir="ltr"><input type="number" min="0" step="any"
            value={recovery} onChange={(e) => { setRecovery(e.target.value); setActualFormError(""); }} />
            <span>{t("minutesShort")}</span></span>
          <small>{t("lossActualRecoveryHelp")}</small></label>
      </section>}
      {(scrapValidation.error || actualFormError) && <p className={styles.actualError}
        role="alert">{t(scrapValidation.error || actualFormError)}</p>}
      <label className={styles.attestation}><input type="checkbox" checked={sourceConfirmed}
        onChange={e => setSourceConfirmed(e.target.checked)} /> {t("downtimeConfirmObservationSource")}</label>
      <button className="primary" disabled={busy || !sourceConfirmed}>{t("save")}</button>
    </form></Dialog>}
    {observationSaved && !actual && <p role="status">{t("downtimeObservationSaved")}</p>}
    {action === "correct" && canEngineer && <Dialog title={t("downtimeCorrectData")} t={t} onClose={closeAction} busy={busy}>
      <div className={styles.reviewDetail}>
      <p>{t("lossCorrectionHelp")}</p>
      <dl>
        <div><dt>{t("downtimeOriginalClassification")}</dt><dd>{classification(event)}</dd></div>
        {correction && <div><dt>{t("downtimeCurrentClassification")}</dt><dd>{classification(correction)}</dd></div>}
      </dl>
      <form className={styles.form} onSubmit={(e) => { e.preventDefault();
        void run("correct_downtime_classification", { event: event.id,
          nature, reason: nature === "unplanned" ? reason : null,
          activity: nature === "planned" ? activity : null, note: correctionNote }).then(ok => { if (ok) { setCorrectionNote(""); closeAction(); } });
      }}>
        <label>{t("lossStopType")}<select value={nature}
          onChange={(e) => setNature(e.target.value)}>
          <option value="unplanned">{t("lossUnplanned")}</option>
          <option value="planned">{t("lossPlanned")}</option>
        </select></label>
        {nature === "unplanned" ? <label>{t("downtimeInitialReason")}
          <select required value={reason} onChange={(e) => setReason(e.target.value)}>
            <option value="">{t("downtimeChooseReason")}</option>
            {(s.tables.downtime_reasons || []).map(row => <option value={String(row.id)} key={String(row.id)}>{localName(row,lang)}</option>)}
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
    </div></Dialog>}
    {action === "history" && <Dialog title={t("downtimeViewHistory")} t={t} onClose={closeAction}>
      <div className={styles.reviewDetail}>
      {props.history}
      {actual && <div className={styles.observation}>
        <h5>{t("downtimeStoredObservation")}</h5>
        <p>{t("downtimeObservationSource")} {String((s.tables.memberships || [])
          .find(person => person.user_id === actual.recorded_by)?.display_name || t("requestCreatorNotRecorded"))}
          {" · "}{formatTime(actual.recorded_at, lang, zone)}</p>
        <dl>
          {actual.actual_loss_minutes != null && <div><dt>{t("lossActualLossTime")}</dt><dd>{time(Number(actual.actual_loss_minutes))}</dd></div>}
          {actual.actual_lost_output_quantity != null && <div><dt>{t("lossActualLostQuantity")}</dt>
            <dd>{quantity(Number(actual.actual_lost_output_quantity), String(actual.actual_lost_output_unit || ""))}</dd></div>}
          {actual.scrap_quantity != null && <div><dt>{t("lossActualScrap")}</dt>
            <dd>{quantity(Number(actual.scrap_quantity), String(actual.scrap_unit || ""))}</dd></div>}
          {actual.shutdown_scrap_quantity != null && <div><dt>{t("lossActualShutdown")}</dt>
            <dd>{quantity(Number(actual.shutdown_scrap_quantity), String(actual.scrap_unit || ""))}</dd></div>}
          {actual.restart_scrap_quantity != null && <div><dt>{t("lossActualRestart")}</dt>
            <dd>{quantity(Number(actual.restart_scrap_quantity), String(actual.scrap_unit || ""))}</dd></div>}
        </dl>
      </div>}

      {actual && canEngineer && <p>{t("downtimeObservationCorrectionUnavailable")}</p>}
      {Boolean(data.corrections?.length || correction) && <><h4>{t("downtimeCorrectionHistory")}</h4>
      <ol className={styles.audit}>
        {(data.corrections || (correction ? [correction] : [])).map(entry => <li key={String(entry.id)}>
          <strong>{classification(entry)}</strong>
          <p dir="auto">{String(entry.note)}</p>
          <small>{formatTime(entry.corrected_at, lang, zone)} · {String((s.tables.memberships || [])
            .find(person => person.user_id === entry.corrected_by)?.display_name || t("requestCreatorNotRecorded"))}</small>
        </li>)}
      </ol>
    </>}
    </div></Dialog>}
    {action === "maintenance" && canCreateMaintenance && <MaintenanceCreate {...props} machine={machine}
      downtime={event} onClose={closeAction} onCreated={id => { closeAction(); props.onMaintenanceRepairOpen?.(id); }} />}
    {error && <p role="alert">{t(error)}</p>}
  </div>;
}

export default function LossImpactReview(props: FeatureProps & { eventId: string; children?: ReactNode; history?: ReactNode }) {
  const { snapshot: s, t, eventId } = props;
  const url = "/api/loss-review?" + new URLSearchParams({ factory: String(s.factory?.id), event: eventId });
  const detail = useHistoryData<ReviewData>(url, s.fetchedAt, url, true);
  return <>
    <HistoryQueryState {...detail} t={t} />
    {detail.data ? <EventImpactDetail key={eventId} {...props} data={detail.data} /> : props.children}
  </>;
}
