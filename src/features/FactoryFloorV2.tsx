import { useEffect, useRef, useState } from "react";
import { downtimeReasonChoices } from "@/utils/downtime-reasons";
import { evaluateFlow, formatDuration } from "@/utils/production-flow.mjs";
import {
  downtimeMinutes,
  lineTodayOutput,
  reportPeriod,
} from "@/utils/manufacturing.mjs";
import MachineIcon from "@/components/MachineIcon";
import MachineVisual, { machineVisualType } from "@/components/FloorMachineMotion";
import FactoryRoute from "@/components/FactoryRoute";
import { formatTime, localName } from "@/components/ui";
import { executionTiming, lineExecutionQueue } from "@/utils/execution-queue.mjs";
import {
  machineVisualStates,
  noDemandIdle,
  matchesVisualFilter,
  lineVisualStatus,
  connectorFlowing,
  impactChoice,
  transferBranches,
  borrowingLineOf,
  categoryIconKey,
  liveTransferPicker,
  lineOperationalStatus,
  lineFlowActive,
} from "@/utils/floor-visual.mjs";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
import ProductionRecording from "./ProductionRecording";
import { productionProgress, entryQuantities } from "@/utils/production-recording.mjs";
import HistoryLimitWarning from "@/components/HistoryLimitWarning";
import ProductIdentity from '@/components/ProductIdentity';
import DeliveryContext from '@/components/DeliveryContext';
import { useFulfillment, type ProductionDemand } from './useFulfillment';
/**
 * Factory Floor V2. Renders the SAME snapshot through the
 * SAME logic as V1: physical status comes from work_centers.status, computed
 * production-flow impact from evaluateFlow, alternative routes from open
 * production transfers. This component visualizes; it never recomputes.
 */
type VisualState =
  | "running"
  | "stopped"
  | "setup"
  | "idle"
  | "offline"
  | "affected"
  | "bufferActive"
  | "alternative";
const stateLabelKey: Record<VisualState, string> = {
  running: "running",
  stopped: "stopped",
  setup: "setup",
  idle: "idle",
  offline: "offline",
  affected: "affected",
  bufferActive: "bufferActive",
  alternative: "alternativeActive",
};
const pauseReasons = ["borrow_machine", "cleaning", "changeover", "no_production", "other"];
// Presentation only: physical state owns the large color band; flow has its own indicator.
function FloorStateIcon({ state }: { state: string }) {
  const paths: Record<string, React.ReactNode> = {
    running: <path d="m9 5 10 7-10 7Z" fill="currentColor" stroke="none" />,
    stopped: <><path d="M12 3 2 21h20Z" /><path d="M12 9v5m0 3v.1" /></>,
    planned: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    setup: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    idle: <><path d="M9 6v12M15 6v12" /></>,
    offline: <><circle cx="12" cy="12" r="9" /><path d="m6 6 12 12" /></>,
    blocked: <><circle cx="12" cy="12" r="9" /><path d="M6 12h12" /></>,
    borrowed: <><path d="M5 20v-7a5 5 0 0 1 5-5h9m-4-4 4 4-4 4M5 4v4" /></>,
  };
  return <svg className="ff2-status-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[state] || paths.idle}</svg>;
}
export default function FactoryFloorV2(
  props: FeatureProps & {
    onManage: (machineId?: string) => void;
  },
) {
  const { snapshot: s, t, lang, can } = props;
  const [filter, setFilter] = useState("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedContextPaused, setSelectedContextPaused] = useState(false);
  const [selectedFromHomePlaceholder, setSelectedFromHomePlaceholder] = useState(false);
  const [pauseLineId, setPauseLineId] = useState<string | null>(null);
  const [pauseReason, setPauseReason] = useState("borrow_machine");
  const [pauseBusy, setPauseBusy] = useState(false);
  const [pauseNotice, setPauseNotice] = useState("");
  const [transferTarget, setTransferTarget] = useState<string | null>(null);
  const [transferReason, setTransferReason] = useState("");
  const [flowNotice, setFlowNotice] = useState("");
  const [flowBusy, setFlowBusy] = useState(false);
  const [executionBusyId, setExecutionBusyId] = useState<string | null>(null);
  const [quickAction, setQuickAction] = useState<"stop" | null>(null);
  const [stopNature, setStopNature] = useState<"unplanned" | "planned">("unplanned");
  const [plannedActivity, setPlannedActivity] = useState("");
  const [stopReason, setStopReason] = useState("");
  const [stopDetail, setStopDetail] = useState("");
  const [motionPaused, setMotionPaused] = useState(false);
  const fulfillment = useFulfillment<{ rows: ProductionDemand[] }>(s, 'production', 1, can('orders'));
  const drawerRef = useRef<HTMLElement>(null);
  const drawerCloseRef = useRef<HTMLButtonElement>(null);
  const openerRef = useRef<HTMLButtonElement>(null);
  const centers = (s.tables.work_centers || []).filter((c) => !c.archived);
  const lines = (s.tables.production_lines || []).filter((l) => !l.archived);
  const orders = s.tables.production_orders || [];
  const requests = s.tables.production_requests || [];
  const stops = s.tables.downtime_events || [];
  const stopCategories = downtimeReasonChoices.map(([name, key]) => ({
    row: s.tables.downtime_reasons?.find((reason) => reason.name === name && !reason.parent_id), key,
  })).filter(({ row }) => Boolean(row));
  const transfers = s.tables.production_transfers || [];
  const zone = String(s.factory?.timezone || "Asia/Qatar");
  const period = reportPeriod("today", zone);
  const flow = evaluateFlow(centers, stops, transfers);
  // OPEN transfer branches with their effective-flow verdict ("flowing",
  // "routeBlocked", "alternativeStopped"): the branch, the borrowing and the
  // home placeholder persist while the row is open — only the presentation
  // depends on the flow verdict.
  const allBranches = transferBranches(centers, flow, transfers);
  const entries = (s.tables.production_entries || []).filter(
    (e) =>
      String(e.created_at) >= period.from && String(e.created_at) < period.to,
  ).map((e): Row => ({ ...e, produced: entryQuantities(e).good }));
  async function executeItem(action: "start_product_item" | "finish_product_item", itemId: string) {
    setExecutionBusyId(itemId);
    try {
      await props.command(action, { factory: s.factory?.id, item: itemId });
    } catch { /* The shared command handler shows the database error. */ }
    finally { setExecutionBusyId(null); }
  }
  function executionJob(item: Row, label: string, ready: boolean) {
    const product = s.tables.products?.find((p) => String(p.id) === String(item.product_id));
    const request = requests.find((r) => String(r.id) === String(item.request_id));
    const timing = executionTiming(item);
    const unit = t(item.unit === "meter" ? "meterShort" : item.unit === "piece" ? "pieceShort" : "legacyUnit");
    const variance = (minutes: number) => minutes === 0 ? t("executionOnTime")
      : `${formatDuration(Math.abs(minutes), lang)} ${t(minutes > 0 ? "executionLate" : "executionEarly")}`;
    return <div className={`ff2-queue-job${ready ? " ff2-queue-ready" : ""}`} key={String(item.id)} data-product-item-id={String(item.id)} data-execution-state={String(item.status)}>
      <div className="ff2-queue-job-head">
        <strong>{label}</strong>
        <span>{item.status === "active" ? t("executionInProduction") : ready ? t("executionReady") : t("executionWaiting")}</span>
      </div>
      <div className="ff2-job-identity"><bdi className="ff2-job-order">{String(request?.code || item.code || "")}</bdi>
        <div className="ff2-queue-product" dir="auto"><ProductIdentity productId={item.product_id} productItemId={item.id}>{product ? localName(product, lang) : t("notAvailable")}</ProductIdentity></div></div>
      <DeliveryContext rows={fulfillment.data?.rows || []} item={item.id} t={t} lang={lang} zone={zone} />
      <dl className="recording-figures">
        {(["required", "good", "remaining"] as const).map(key => <div key={key}><dt>{t(key === "required" ? "recordingRequired" : key === "good" ? "recordingGoodSoFar" : "recordingRemaining")}</dt><dd>{productionProgress(item)[key].toLocaleString(lang)} {unit}</dd></div>)}
        {productionProgress(item).overproduction > 0 && <div><dt>{t("recordingOverproduction")}</dt><dd>{productionProgress(item).overproduction.toLocaleString(lang)} {unit}</dd></div>}
      </dl>
      <details className="ff2-queue-timing"><summary>{t("ffProductionTiming")}</summary><bdi>{String(item.code || "")}</bdi><dl className="ff2-queue-times">
        <div><dt>{t("executionPlannedStart")}</dt><dd>{formatTime(item.start_time, lang, zone)}</dd></div>
        <div><dt>{t("executionPlannedFinish")}</dt><dd>{formatTime(item.expected_finish, lang, zone)}</dd></div>
        {item.actual_start && <div><dt>{t("executionActualStart")}</dt><dd>{formatTime(item.actual_start, lang, zone)}</dd></div>}
        {item.actual_finish && <div><dt>{t("executionActualFinish")}</dt><dd>{formatTime(item.actual_finish, lang, zone)}</dd></div>}
      </dl><div className="ff2-queue-variance">
      {timing.startVarianceMinutes !== null && <small>{t("executionStartVariance")}: {variance(timing.startVarianceMinutes)}</small>}
      {timing.finishVarianceMinutes !== null && <small>{t("executionFinishVariance")}: {variance(timing.finishVarianceMinutes)}</small>}
      {ready && timing.startOverdueMinutes !== null && <small>{t("executionStartLateBy")}: {formatDuration(timing.startOverdueMinutes, lang)}</small>}
      {item.status === "active" && timing.overdueMinutes !== null && <small>{t("executionFinishLateBy")}: {formatDuration(timing.overdueMinutes, lang)}</small>}
      {item.status === "active" && !item.actual_start && <small>{t("executionLegacyStartMissing")}</small>}
      </div></details>
      {can("orders", "edit") && ready && <button className="primary"
        disabled={Boolean(executionBusyId) || Boolean(s.truncatedTables?.includes("production_orders"))}
        onClick={() => void executeItem("start_product_item", String(item.id))}>{t("startProduction")}</button>}
      {can("orders", "edit") && item.status === "active" && item.actual_start && <button className="primary"
        disabled={Boolean(executionBusyId)}
        onClick={() => void executeItem("finish_product_item", String(item.id))}>{t("finishProduction")}</button>}
    </div>;
  }
  // Pure mapping (see utils/floor-visual.mjs): physical status is the
  // machine's own truth; computed flow impact only overrides running machines;
  // "alternative" only for open transfers whose branch effectively carries
  // production.
  const visual: Record<string, string> = machineVisualStates(
    centers,
    flow,
    transfers,
  );
  const stateOf = (c: Row): VisualState =>
    (visual[String(c.id)] as VisualState) || "idle";
  const matchesFilter = (c: Row) =>
    matchesVisualFilter(filter, visual[String(c.id)] || "idle");
  const openStopOf = (c: Row) =>
    stops.find((x) => x.work_center_id === c.id && !x.ended_at);
  const sourceOf = (c: Row) =>
    centers.find((x) => x.id === flow[String(c.id)]?.source);
  const machineOutput = (c: Row) =>
    entries
      .filter((e) => String(e.work_center_id) === String(c.id))
      .reduce((n, e) => n + Number(e.produced || 0), 0);
  const lineDowntime = (machines: Row[]) =>
    machines.reduce(
      (sum, m) =>
        sum +
        stops
          .filter((x) => x.work_center_id === m.id)
          .reduce(
            (n, e) => n + downtimeMinutes(e, period.from, period.to),
            0,
          ),
      0,
    );
  const selected = centers.find((c) => String(c.id) === selectedId) || null;
  useEffect(() => {
    if (!selectedId) return;
    const drawer = drawerRef.current;
    if (!drawer) return;
    drawerCloseRef.current?.focus();
    const containFocus = (event: FocusEvent) => {
      if (!drawer.contains(event.target as Node)) drawerCloseRef.current?.focus();
    };
    document.addEventListener("focusin", containFocus);
    return () => document.removeEventListener("focusin", containFocus);
  }, [selectedId]);

  function closeDrawer() {
    setSelectedId(null);
    const opener = openerRef.current;
    requestAnimationFrame(() => {
      if (opener?.isConnected) opener.focus();
    });
  }

  function onDrawerKeyDown(event: React.KeyboardEvent<HTMLElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeDrawer();
      return;
    }
    if (event.key !== "Tab") return;
    const focusable = Array.from(
      drawerRef.current?.querySelectorAll<HTMLElement>(
        'button:not([disabled]):not([tabindex="-1"]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex="0"]',
      ) || [],
    ).filter((element) => element.getClientRects().length > 0);
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }
  const filters = [
    ["all", centers.length],
    [
      "running",
      centers.filter((c) =>
        matchesVisualFilter("running", visual[String(c.id)] || "idle"),
      ).length,
    ],
    [
      "stopped",
      centers.filter((c) =>
        matchesVisualFilter("stopped", visual[String(c.id)] || "idle"),
      ).length,
    ],
    [
      "affected",
      centers.filter((c) =>
        matchesVisualFilter("affected", visual[String(c.id)] || "idle"),
      ).length,
    ],
  ] as const;
  // Presentation labels consume existing verdicts; no propagation rules here.
  function flowLabelKey(c: Row, state: VisualState, paused: boolean,
    noDemand: boolean, override?: string) {
    const originalBranch = allBranches.find((b) => String(b.original.id) === String(c.id));
    if (noDemand) return "idleNoDemand";
    if (paused) return "paused";
    if (override) return override;
    if (originalBranch?.state === "flowing") return "alternativeActive";
    if (flow[String(c.id)]?.state === "bufferActive") return "bufferActive";
    if (state === "affected") return "flowBlocked";
    if (state === "running") return "ffFlowClear";
    if (["stopped", "offline", "idle"].includes(state))
      return flow[String(c.id)]?.state === "blocked" ? "flowBlocked" : "ffNotFlowing";
    return stateLabelKey[state];
  }
  function node(
    c: Row,
    dimmed: boolean,
    branch?: { labelKey?: string; note?: string },
    paused = false,
    sequence?: number,
  ) {
    const state = (paused ? String(c.status || "idle") : stateOf(c)) as VisualState;
    const stop = openStopOf(c);
    const noDemand = !paused && noDemandIdle(c, orders, stops, transfers);
    const source = state === "affected" ? sourceOf(c) : null;
    const assignment = allBranches.find((b) => String(b.alternative.id) === String(c.id));
    const job = orders.find((item) => item.id === c.order_id && item.status === "active");
    const product = job && s.tables.products?.find((item) => item.id === job.product_id);
    const flowKey = flowLabelKey(c, state, paused, noDemand, branch?.labelKey);
    const accent = noDemand ? "idle" : stop?.stop_nature === "planned" ? "planned"
      : String(c.status || "idle");
    const compactFlow = flowKey === "flowBlocked" ? "ffStateBlocked"
      : ["alternativeActive", "alternativeAssigned"].includes(flowKey) ? "ffStateBorrowed"
      : flowKey === "ffFlowClear" ? "ffStateNormal"
      : flowKey === "idleNoDemand" ? "ffStateNoDemand" : flowKey;
    const statusKey = accent === "planned" ? "ffStatePlanned" : accent === "setup" ? "ffStateSetup" : accent;
    return (
      <button
        className={`ff2-node ff2-${state} ff2-accent-${accent}${assignment ? " ff2-assigned" : ""}${dimmed ? " ff2-dim" : ""}`}
        dir={lang === "ar" ? "rtl" : "ltr"}
        data-machine-id={String(c.id)}
        data-physical-state={String(c.status || "idle")}
        data-flow-state={flowKey}
        onClick={(event) => {
          openerRef.current = event.currentTarget;
          setSelectedId(String(c.id));
          setSelectedContextPaused(paused);
          setSelectedFromHomePlaceholder(false);
          setTransferTarget(null);
          setTransferReason("");
          setFlowNotice("");
          setQuickAction(null);
        }}
        key={String(c.id)}
      >
        <span className="ff2-state-band">
          <span className="ff2-node-sequence" aria-label={sequence ? `${t("ffSequence")} ${sequence}` : t("alternativeAssigned")}>{sequence ? String(sequence).padStart(2, "0") : "↗"}</span></span>
        <MachineVisual type={machineVisualType(c, categoryIconKey(c, s.tables.work_center_categories))} borrowed={Boolean(assignment)}
          state={accent === "stopped" ? "fault" : paused || accent === "planned" || accent === "setup" ? "planned"
            : flowKey === "flowBlocked" ? "blocked" : accent === "running" ? "running" : "idle"} />
        <span className="ff2-node-name" dir="auto">{localName(c, lang)}</span>
        <span className="ff2-node-state"><FloorStateIcon state={accent} />{t(statusKey)}</span>
        <span className="sr-only">{t("ffPhysicalState")}: {t(String(c.status || "idle"))}</span>
        {(flowKey === "flowBlocked" && accent === "running") || flowKey === "bufferActive" ? <span className={`ff2-node-flow ff2-flow-state-${flowKey === "flowBlocked" ? "affected" : "buffer"}`} title={t(flowKey)}>
          <FloorStateIcon state={flowKey === "flowBlocked" ? "blocked" : accent} />
          <span className="sr-only">{t("flowSummary")}: </span>{t(compactFlow)}
          {compactFlow !== flowKey && <span className="sr-only"> · {t(flowKey)}</span>}
        </span> : <span className="sr-only">{t("flowSummary")}: {t(flowKey)}</span>}
        {!c.line_id && !assignment && job && <span className="ff2-node-production"><strong dir="auto"><ProductIdentity productId={job.product_id} productItemId={job.id}>{product ? localName(product, lang) : String(job.code || "")}</ProductIdentity></strong>
          <bdi>{String(requests.find(request => request.id === job.request_id)?.code || job.code || "")}</bdi>
          <span>{t("recordingRemaining")}: {productionProgress(job).remaining.toLocaleString(lang)} {t(job.unit === "meter" ? "meterShort" : job.unit === "piece" ? "pieceShort" : "legacyUnit")}</span></span>}
        {state === "stopped" && stop && <span className={`ff2-node-stop${stop.stop_nature === "planned" ? " ff2-stop-planned" : ""}`}>
          <strong dir="auto">{stop.stop_nature === "planned" ? t(`lossActivity_${stop.planned_activity}`)
            : stop.reason_id ? localName(s.tables.downtime_reasons?.find((reason) => reason.id === stop.reason_id), lang) : t("downtimeUnclassified")}</strong>
          <span className="ff2-node-duration">
            {formatDuration(
              (Date.now() - Date.parse(String(stop.started_at))) / 60000,
              lang,
            )}
          </span></span>}
        {assignment && <span className="ff2-node-assignment" dir="auto"><FloorStateIcon state="borrowed" />{t("ffStateBorrowed")}<span className="sr-only"> · {t("alternativeAssigned")}</span></span>}
        {branch?.note && !(assignment && branch.note === "alternativeAssigned") ? (
          <span className="sr-only" dir="auto">{t(branch.note)}</span>
        ) : source ? (
          <span className="sr-only" dir="auto">
            {t("affectedBy")} {localName(source, lang)}
          </span>
        ) : null}
        <span className="sr-only">{t("ffViewActions")}</span>
      </button>
    );
  }
  // Branches of OPEN transfers whose original sits on this line: [original,
  // alternative, effective-flow state]. The alternative node is inserted into
  // the ORIGINAL's route position (branch) and the original stays visible as
  // the stopped root with a broken stub — for as long as the transfer row is
  // open, regardless of whether production is actually flowing through it.
  const lineBranches = (lineId: string) =>
    allBranches.filter((b) => String(b.original.line_id || "") === lineId);
  // Machines currently borrowed BY this line (alternative rendering here,
  // muted placeholder at home) — assignment truth, not flow truth.
  const borrowedInto = (lineId: string) =>
    lineBranches(lineId).map((b) => b.alternative);
  const isBorrowedElsewhere = (c: Row) =>
    Boolean(borrowingLineOf(c, allBranches, lines));
  async function changeLinePause(line: Row, paused: boolean) {
    setPauseBusy(true);
    setPauseNotice("");
    try {
      await props.command("set_line_pause", {
        factory: s.factory?.id,
        line: line.id,
        paused,
        reason: paused ? pauseReason : null,
      });
      setPauseLineId(null);
      setPauseNotice("");
    } catch (error) {
      setPauseLineId(String(line.id));
      setPauseNotice(error instanceof Error ? error.message : "error");
    } finally {
      setPauseBusy(false);
    }
  }
  function lineCard(line: Row | null) {
    const lineId = line ? String(line.id) : "";
    const queue = line ? lineExecutionQueue(orders, lineId) : null;
    const borrowed = borrowedInto(lineId);
    const homeMachines = centers
      .filter((c) =>
        line ? c.line_id === line.id : !c.line_id,
      )
      .filter((c) => !borrowed.some((b) => String(b.id) === String(c.id)))
      .sort((a, b) => Number(a.position) - Number(b.position));
    if (!line && !homeMachines.length) return null;
    const machines = homeMachines;
    const borrowedAwayIds = machines
      .filter(isBorrowedElsewhere)
      .map((m) => String(m.id));
    const relevant = machines.filter(matchesFilter);
    // Filtering keeps the complete path: the line only disappears when nothing matches.
    if (filter !== "all" && !relevant.length && !borrowed.length) return null;
    const pausedAt = line?.paused_at || null;
    const summaryMachines = machines.filter((m) => !line || m.dependency_mode !== "independent");
    const status = lineOperationalStatus(lineVisualStatus(
      summaryMachines.map((m) => String(m.id)),
      visual,
      allBranches,
      borrowedAwayIds,
      flow,
    ), pausedAt);
    const noDemandLine = !pausedAt && summaryMachines.length > 0 &&
      summaryMachines.every((machine) => noDemandIdle(machine, orders, stops, transfers));
    const activeOrder = line
      ? orders.find(
          (o) => o.status === "active" && o.line_id === line.id,
        )
      : undefined;
    // The shared summary owns flow aggregation; this only selects existing chrome.
    const hasBlockedFlow = status === "affected";
    const plannedProblem = hasBlockedFlow && [...machines, ...borrowed].some(machine => openStopOf(machine)?.stop_nature === "planned") &&
      ![...machines, ...borrowed].some(machine => openStopOf(machine)?.stop_nature === "unplanned");
    const lineTone = noDemandLine ? "idle" : pausedAt || plannedProblem ? "planned"
      : status === "stopped" ? "stopped" : hasBlockedFlow ? "blocked" : status === "runningViaAlternative" ? "running" : status === "affected" ? "blocked" : status || "idle";
    const output = line
      ? lineTodayOutput(
          entries,
          orders,
          centers,
          String(line.id),
          period.from,
          period.to,
        )
      : machines.reduce((n, m) => n + machineOutput(m), 0);
    const progress =
      activeOrder &&
      Number(activeOrder.target_quantity) > 0 &&
      productionProgress(activeOrder).good > 0
        ? Math.round(
            (productionProgress(activeOrder).good /
              Number(activeOrder.target_quantity)) *
              100,
          )
        : null;
    return (
      <section className={`ff2-card ff2-line-tone-${lineTone}${pausedAt ? " ff2-paused" : ""}`} key={String(line ? line.id : "independent")} data-line-id={lineId || "independent"}>
        <header className="ff2-card-head">
          <div>
            <h3>{line ? localName(line, lang) : t("independent")}</h3>
          </div>
          <div className="ff2-card-controls">
            {status && !hasBlockedFlow && <span className={`ff2-chip ff2-chip-line ff2-chip-${noDemandLine ? "idle" : status}`}>
              {t(noDemandLine ? "idleNoDemand" : status)}</span>}
            {hasBlockedFlow && <span className={`ff2-line-flow ff2-line-flow-${plannedProblem ? "planned" : "blocked"}`}><FloorStateIcon state={plannedProblem ? "planned" : "blocked"} />{t(plannedProblem ? "ffStatePlanned" : "ffStateBlocked")}</span>}
            {line && can("centers", "edit") && (
              <button className="ff2-line-action" disabled={pauseBusy} onClick={() => {
                setPauseNotice("");
                if (pausedAt) void changeLinePause(line, false);
                else setPauseLineId(pauseLineId === lineId ? null : lineId);
              }}>{t(pausedAt ? "resumeLine" : "pauseLine")}</button>
            )}
          </div>
        </header>
        {pausedAt && <p className="ff2-pause-reason">{t("pauseReason")}: {t(String(line?.pause_reason || "other"))}</p>}
        {pauseLineId === lineId && !pausedAt && (
          <div className="ff2-pause-form">
            <p className="ff2-pause-help">{t("pauseLineConsequence")}</p>
            <label>{t("pauseReason")}
              <select value={pauseReason} onChange={(e) => setPauseReason(e.target.value)}>
                {pauseReasons.map((reason) => <option key={reason} value={reason}>{t(reason)}</option>)}
              </select>
            </label>
            <button className="primary" disabled={pauseBusy} onClick={() => void changeLinePause(line as Row, true)}>{t("pauseLine")}</button>
            <button onClick={() => setPauseLineId(null)}>{t("cancel")}</button>
          </div>
        )}
        {pauseNotice && pauseLineId === lineId && <p role="status" className="ff2-muted">{t(pauseNotice)}</p>}
        {line && <section className="ff2-queue" aria-label={t("productionQueue")}>
          {queue?.current
            ? executionJob(queue.current, t("executionCurrentReady"), String(queue.readyId) === String(queue.current.id))
            : <p className="muted">{t("executionNoQueuedJobs")}</p>}
        </section>}
        <div className="ff2-route-heading"><h4>{t("ffMachineSequence")}</h4></div>
        <FactoryRoute machines={machines} continuationLabel={t("routeContinues")}
          direction={lang === "ar" ? "rtl" : "ltr"} minimumCardWidth={176} maximumCardWidth={220} fillLastRow
          connectorActive={(a, b) => lineFlowActive(connectorFlowing(a, b, visual, flow, borrowedAwayIds), pausedAt)}
          connectorTone={(a, b) => borrowedAwayIds.includes(String(a.id)) || borrowedAwayIds.includes(String(b.id)) ? "borrowed"
            : lineBranches(lineId).some(branch => branch.original.id === a.id) ? "borrowed"
            : !pausedAt && (flow[String(a.id)]?.state === "blocked" || flow[String(b.id)]?.state === "blocked") ? "blocked" : undefined}
          renderMachine={(c, i) => {
            const branchHere = lineBranches(lineId).find((b) => String(b.original.id) === String(c.id));
            return <>
              {isBorrowedElsewhere(c) ? (
                  <button
                    className={`ff2-node ff2-borrowed ff2-assigned ff2-accent-${openStopOf(c)?.stop_nature === "planned" ? "planned" : String(c.status || "idle")}`}
                    dir={lang === "ar" ? "rtl" : "ltr"}
                    data-machine-id={String(c.id)}
                    data-physical-state={String(c.status || "idle")}
                    onClick={(event) => {
                      openerRef.current = event.currentTarget;
                      setSelectedId(String(c.id));
                      setSelectedContextPaused(Boolean(pausedAt));
                      setSelectedFromHomePlaceholder(true);
                      setQuickAction(null);
                      setTransferTarget(null);
                      setFlowNotice("");
                    }}
                  >
                    <span className="ff2-state-band"><span className="ff2-node-sequence" aria-label={`${t("ffSequence")} ${i + 1}`}>{String(i + 1).padStart(2, "0")}</span></span>
                    <MachineVisual type={machineVisualType(c, categoryIconKey(c, s.tables.work_center_categories))} state="home" borrowed />
                    <span className="ff2-node-name" dir="auto">{localName(c, lang)}</span>
                    <span className="ff2-node-state"><FloorStateIcon state="borrowed" />{t("ffStateBorrowed")}<span className="sr-only"> · {t("ffPhysicalState")}: {t(String(c.status || "idle"))}</span></span>
                    <span className="sr-only">{t("ffBorrowed")}</span>
                    <span className="ff2-node-source" dir="auto">
                      {t("temporarilyAssignedTo")}{" "}
                      {(() => {
                        const bl = borrowingLineOf(c, allBranches, lines);
                        return bl ? localName(bl, lang) : t("anotherLine");
                      })()}
                    </span>
                    <span className="sr-only">{t("ffViewActions")}</span>
                  </button>
              ) : node(c, filter !== "all" && !matchesFilter(c), undefined, Boolean(pausedAt), i + 1)}
              {branchHere && <div className={`ff2-branch${lineFlowActive(branchHere.state === "flowing", pausedAt) ? "" : " ff2-branch-muted"}`}>
                <span className={`ff2-branch-reroute${lineFlowActive(branchHere.state === "flowing", pausedAt) ? "" : " ff2-branch-off"}`}><FloorStateIcon state="borrowed" /> {t("ffStateBorrowed")}<span className="sr-only"> · {t("ffAlternativeRoute")}</span></span>
                {node(branchHere.alternative as Row, filter !== "all" && !matchesFilter(branchHere.alternative as Row),
                  lineFlowActive(branchHere.state === "flowing", pausedAt) ? undefined : {
                    labelKey: branchHere.state === "routeBlocked" ? "flowBlocked" : undefined,
                    note: "alternativeAssigned",
                  }, Boolean(pausedAt))}
                {machines[i + 1] && <span className={`ff2-branch-return${lineFlowActive(branchHere.state === "flowing", pausedAt) ? "" : " ff2-branch-off"}`} aria-hidden="true">⤴</span>}
              </div>}
            </>;
          }} />
        {!machines.length && <p className="ff2-empty">{t("noMachinesOnLine")}</p>}
        {queue?.next && <details className="ff2-next-job"><summary>{t("executionNext")} · <bdi>{String(requests.find(request => request.id === queue.next?.request_id)?.code || queue.next.code || "")}</bdi> · <span dir="auto">{localName(s.tables.products?.find(product => product.id === queue.next?.product_id), lang)}</span></summary>{executionJob(queue.next, t("executionNext"), false)}</details>}
        <details className="ff2-line-detail"><summary>{t("ffTimingDetails")}</summary><footer className="ff2-card-foot">
          <span>
            {t("todayProduction")}:{" "}
            <bdi dir="ltr">{output.toLocaleString(lang)}</bdi>
          </span>
          {progress !== null && (
            <span>
              {t("orderProgress")}: <bdi dir="ltr">{progress}%</bdi>
            </span>
          )}
          <span>
            {t("todayDowntime")}:{" "}
            <bdi dir="ltr">
              {formatDuration(lineDowntime(machines), lang)}
            </bdi>
          </span>
        </footer></details>
        <HistoryLimitWarning snapshot={s} tables={["production_entries", "downtime_events"]} t={t} />
      </section>
    );
  }
  const selectedState = selected ? stateOf(selected) : null;
  const selectedNoDemand = selected && !selectedContextPaused &&
    noDemandIdle(selected, orders, stops, transfers);
  const selectedOrder = selected
    ? orders.find((o) => o.id === selected.order_id)
    : undefined;
  const selectedProduct = s.tables.products?.find(
    (p) => p.id === selectedOrder?.product_id,
  );
  const selectedLine = selected
    ? lines.find((l) => l.id === selected.line_id)
    : undefined;
  const selectedStop = selected ? openStopOf(selected) : undefined;
  // ---- Production Flow derivations (all from existing snapshot + flow logic)
  // "active" availability means effectively carrying production — an open
  // transfer with a blocked route or a stopped alternative does not count.
  const selectedAlternatives = selected
    ? (s.tables.work_center_alternatives || [])
        .filter((x) => x.work_center_id === selected.id)
        .map(
          (x) =>
            centers.find((c) => c.id === x.alternative_id) as Row | undefined,
        )
        .filter((x): x is Row => !!x)
    : [];
  const selectedChoice = selected
    ? impactChoice(
        String(selected.dependency_mode || ""),
        String(selected.impact_scope || ""),
      )
    : null;
  const actualAffected = selected
    ? centers.filter(
        (c) =>
          String(c.id) !== String(selected.id) &&
          flow[String(c.id)]?.state === "blocked" &&
          String(flow[String(c.id)]?.source) === String(selected.id),
      )
    : [];
  const openOwnTransfer = selected
    ? transfers.find(
        (x) => !x.ended_at && String(x.original_id) === String(selected.id),
      )
    : undefined;
  const activeAltRow = openOwnTransfer
    ? centers.find((c) => c.id === openOwnTransfer.alternative_id)
    : undefined;
  // The transfer ROW is active — gates visibility and actions, not success.
  const transferActive = !!openOwnTransfer && !!activeAltRow;
  // Effective-flow verdict of this machine's own transfer branch.
  const ownBranchState = openOwnTransfer
    ? allBranches.find(
        (b) => String(b.original.id) === String(openOwnTransfer.original_id),
      )?.state
    : undefined;
  const actingFor = selected
    ? transfers.find(
        (x) =>
          !x.ended_at && String(x.alternative_id) === String(selected.id),
      )
    : undefined;
  const actingOriginal = actingFor
    ? centers.find((c) => c.id === actingFor.original_id)
    : undefined;
  // LIVE picker mirrors transfer_production's rules on BOTH sides.
  const livePicker = selected
    ? liveTransferPicker(
        selected,
        centers,
        selectedAlternatives.map((a) => String(a.id)),
        transfers,
        orders,
        lines,
        s.tables.work_center_capabilities || [],
      )
    : { blockedReason: null as string | null, candidates: [] as Row[] };
  const transferCandidates = livePicker.blockedReason
    ? []
    : livePicker.candidates;
  const canTransfer =
    !!selected && can("centers", "edit") && can("orders", "edit");
  const canReturn = can("centers", "edit") || can("machine_status", "edit");
  const canChangeStatus = canReturn;
  const selectedDisplayState = selectedContextPaused
    ? (String(selected?.status || "idle") as VisualState)
    : selectedState;
  const borrowedBy = selected ? borrowingLineOf(selected, allBranches, lines) : undefined;
  const issueSource = selected && selectedState === "affected" ? sourceOf(selected) : undefined;
  const stopReasonRow = selectedStop
    ? s.tables.downtime_reasons?.find((r) => r.id === selectedStop.reason_id)
    : undefined;
  const homeAffected = selected && flow[String(selected.id)]?.homeState === "blocked";
  const hasActiveProduction = selectedOrder?.status === "active";
  const canStopHere = !selectedFromHomePlaceholder && canChangeStatus &&
    (selectedDisplayState === "running" || selectedDisplayState === "alternative");
  const canReturnHere = selected?.status === "stopped" && transferActive && canReturn;
  const canRestartHere = selected?.status === "stopped" && !transferActive && canChangeStatus &&
    !selectedFromHomePlaceholder && !(actingFor ? borrowedBy?.paused_at : selectedLine?.paused_at);
  const canStartHere = selected?.status === "idle" &&
    !(actingFor ? borrowedBy?.paused_at : selectedLine?.paused_at) &&
    !selectedFromHomePlaceholder && canChangeStatus;
  const canTransferHere = selected?.status === "stopped" && !transferActive && canTransfer &&
    !selectedLine?.paused_at && !livePicker.blockedReason && transferCandidates.length > 0;
  const showQuickActions = canStopHere || canReturnHere || canRestartHere ||
    canStartHere || canTransferHere || Boolean(activeAltRow && transferActive) || Boolean(actingOriginal);
  async function runTransfer() {
    if (!selected || !transferTarget) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      await props.command("transfer_production", {
        factory: s.factory?.id,
        work_center: selected.id,
        alternative: transferTarget,
        reason: transferReason,
      });
      setTransferTarget(null);
      setTransferReason("");
      setFlowNotice("saved");
    } catch (error) {
      setFlowNotice(error instanceof Error ? error.message : "error");
    } finally {
      setFlowBusy(false);
    }
  }
  async function returnProduction() {
    if (!selected) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      await props.command("change_status", {
        factory: s.factory?.id,
        work_center: selected.id,
        status: "running",
        reason: null,
        sub_reason: null,
        notes: "",
        expected_restart: null,
        responsible: null,
        alternative: null,
        transferred: false,
      });
      setFlowNotice("saved");
    } catch (error) {
      setFlowNotice(error instanceof Error ? error.message : "error");
    } finally {
      setFlowBusy(false);
    }
  }
  async function startMachine() {
    if (!selected) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      await props.command("change_status", {
        factory: s.factory?.id, work_center: selected.id, status: "running",
        reason: null, sub_reason: null, notes: "", expected_restart: null,
        responsible: null, alternative: null, transferred: false,
      });
      setFlowNotice("saved");
    } catch (error) {
      setFlowNotice(error instanceof Error ? error.message : "error");
    } finally {
      setFlowBusy(false);
    }
  }
  async function stopMachine(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selected || (stopNature === "unplanned"
      ? !stopCategories.some(({ row }) => String(row?.id) === stopReason)
      : !plannedActivity)) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      await props.command("stop_machine", {
        factory: s.factory?.id, work_center: selected.id,
        nature: stopNature, reason: stopNature === "unplanned" ? stopReason : null,
        activity: stopNature === "planned" ? plannedActivity : null,
        notes: stopDetail.trim(),
      });
      setQuickAction(null);
      setStopReason("");
      setPlannedActivity("");
      setStopDetail("");
      setFlowNotice("saved");
    } catch (error) {
      setFlowNotice(error instanceof Error ? error.message : "error");
    } finally {
      setFlowBusy(false);
    }
  }
  return (
    <section className="ff2 ff2-engineer" dir={lang === "ar" ? "rtl" : "ltr"} data-motion-paused={motionPaused}>
      <header className="ff2-head">
        {(can("lines", "edit") || can("centers", "edit") || can("lines", "create") || can("centers", "create")) &&
          <button className="ff2-manage" onClick={() => props.onManage()}>{t("manageLinesMachines")}</button>}
      </header>
      <div className="ff2-overview">
        <p className="ff2-floor-count"><strong>{lines.length.toLocaleString(lang)}</strong> {t("ffLines")}<span aria-hidden="true">/</span><strong>{centers.length.toLocaleString(lang)}</strong> {t("ffMachines")}</p>
        <div className="ff2-head-actions">
          <button className="ff2-motion-toggle" aria-label={t(motionPaused ? "ffResumeMotion" : "ffPauseMotion")}
            title={t(motionPaused ? "ffResumeMotion" : "ffPauseMotion")} aria-pressed={motionPaused} onClick={() => setMotionPaused(value => !value)}>
            <FloorStateIcon state={motionPaused ? "running" : "idle"} />
          </button>
          <div className="ff2-filters" role="group" aria-label={t("status")}>
            {filters.map(([key, count]) => (
              <button
                key={key}
                className={filter === key ? "selected" : ""}
                aria-pressed={filter === key}
                data-filter-state={key}
                onClick={() => setFilter(key)}
              >
                {t(key === "affected" ? "affected" : key)}{" "}
                <span>{count}</span>
              </button>
            ))}
          </div>
        </div>
      </div>
      {!centers.length && !lines.length && <p className="ff2-empty">{t("noMachinesOnLine")}</p>}
      {lines.map(lineCard)}
      {lineCard(null)}
      {can("orders", "view") && <ProductionRecording {...props} />}
      {selected && (
        <>
          <div
            className="ff2-drawer-backdrop"
            onClick={closeDrawer}
            aria-hidden="true"
          />
          <aside
            ref={drawerRef}
            className="ff2-drawer"
            dir={lang === "ar" ? "rtl" : "ltr"}
            role="dialog"
            aria-modal="true"
            aria-label={localName(selected, lang)}
            onKeyDown={onDrawerKeyDown}
          >
            <header className="ff2-drawer-head">
              <MachineIcon
                center={selected}
                running={!selectedContextPaused && (selectedDisplayState === "running" || selectedDisplayState === "alternative")}
                categoryIconKey={
                  categoryIconKey(selected, s.tables.work_center_categories) ||
                  undefined
                }
              />
              <div>
                <h3>{localName(selected, lang)}</h3>
                <p className="ff2-card-sub">
                  {selectedDisplayState && (
                    <span className={`ff2-chip ff2-chip-${selectedNoDemand ? "idle" : selectedStop?.stop_nature === "planned" ? "planned" : selectedDisplayState}`}>
                      {t(selectedNoDemand ? "idleNoDemand" : stateLabelKey[selectedDisplayState])}
                    </span>
                  )}{" "}
                  {selectedLine
                    ? localName(selectedLine, lang)
                    : t("independent")}
                </p>
              </div>
              <button
                ref={drawerCloseRef}
                className="ff2-drawer-close"
                aria-label={t("close")}
                onClick={closeDrawer}
              >
                ×
              </button>
            </header>
            <div className="ff2-drawer-body">
              <div className="ff2-drawer-state"><span>{t("ffPhysicalState")}<strong>{t(String(selected.status || "idle"))}</strong></span>
                <span>{t("ffProductionFlow")}<strong>{t(flowLabelKey(selected, selectedDisplayState as VisualState,
                  selectedContextPaused, Boolean(selectedNoDemand)))}</strong></span></div>
              {borrowedBy && (
                <p className="ff2-drawer-context" dir="auto">
                  {t("borrowedByLine")} {localName(borrowedBy, lang)}
                </p>
              )}
              {selectedLine?.paused_at && (
                <p className="ff2-drawer-context" dir="auto">
                  {t("homeLinePaused")}
                </p>
              )}

              {hasActiveProduction && (
                <section className="ff2-operational-section" aria-labelledby="ff2-production-now">
                  <h4 id="ff2-production-now">{t("productionNow")}</h4>
                  <div className="ff2-production-now">
                    <strong dir="auto">{selectedProduct ? localName(selectedProduct, lang) : String(selectedOrder?.code || "")}</strong>
                    {selectedProduct && selectedOrder?.code && (
                      <span>{t("productionOrder")} <bdi dir="ltr">{String(selectedOrder.code)}</bdi></span>
                    )}
                    {Number.isFinite(Number(selectedOrder?.target_quantity)) && Number(selectedOrder?.target_quantity) > 0 &&
                      Number.isFinite(Number(selectedOrder?.produced_quantity)) && (
                        <span>{t("orderProgressNow")} <bdi dir="ltr">
                          {productionProgress(selectedOrder).good.toLocaleString(lang)} / {Number(selectedOrder?.target_quantity).toLocaleString(lang)}
                        </bdi></span>
                      )}
                  </div>
                </section>
              )}

              {!selectedNoDemand && (selectedDisplayState === "stopped" || selectedDisplayState === "affected") && (
                <section className="ff2-operational-section" aria-labelledby="ff2-current-issue">
                  <h4 id="ff2-current-issue">{t("currentIssue")}</h4>
                  <div className={`ff2-issue-card${selectedStop?.stop_nature === "planned" ? " ff2-issue-planned" : selectedDisplayState === "affected" ? " ff2-issue-blocked" : ""}`}>
                    {selectedDisplayState === "stopped" && (
                      <>
                        <strong dir="auto">{selectedStop?.stop_nature === "planned"
                          ? `${t("lossPlanned")} — ${t(`lossActivity_${selectedStop.planned_activity}`)}`
                          : stopReasonRow ? localName(stopReasonRow, lang)
                            : t("downtimeUnclassified")}</strong>
                        {selectedStop?.started_at && (
                          <span>{t("duration")}: {formatDuration(
                            (Date.now() - Date.parse(String(selectedStop.started_at))) / 60000, lang,
                          )}</span>
                        )}
                        {transferActive && activeAltRow ? (
                          <span dir="auto">
                            {t("transferredTo")} {localName(activeAltRow, lang)} · {t(
                              ownBranchState === "flowing" ? "alternativeActive" :
                              ownBranchState === "routeBlocked" ? "flowBlocked" : "alternativeAssigned",
                            )}
                          </span>
                        ) : actualAffected.length ? (
                          <span>{t("impact")}: {actualAffected.map((c) => localName(c, lang)).join(" · ")}</span>
                        ) : null}
                      </>
                    )}
                    {selectedDisplayState === "affected" && issueSource && (
                      <>
                        <strong dir="auto">{t("affectedBy")} {localName(issueSource, lang)}</strong>
                        {(() => {
                          const cause = openStopOf(issueSource);
                          const reason = cause && s.tables.downtime_reasons?.find((r) => r.id === cause.reason_id);
                          return reason ? <span dir="auto">{localName(reason, lang)}</span> : null;
                        })()}
                      </>
                    )}
                    {selectedDisplayState === "affected" && !issueSource && !homeAffected && (
                      <strong>{t("flowBlocked")}</strong>
                    )}
                    {selectedDisplayState === "affected" && borrowedBy && homeAffected && (
                      <strong>{t("homeLineAffected")}</strong>
                    )}
                  </div>
                </section>
              )}

              <section className="ff2-operational-section" aria-labelledby="ff2-flow-summary">
                <h4 id="ff2-flow-summary">{t("flowSummary")}</h4>
                <p className="ff2-flow-summary" dir="auto">
                  {borrowedBy ? (
                    <>{t("borrowedByLine")} {localName(borrowedBy, lang)}{homeAffected ? ` · ${t("homeLineAffected")}` : ""}</>
                  ) : transferActive && activeAltRow ? (
                    <>{t("transferredTo")} {localName(activeAltRow, lang)} · {t(
                      ownBranchState === "flowing" ? "alternativeActive" :
                      ownBranchState === "routeBlocked" ? "flowBlocked" : "alternativeAssigned",
                    )}</>
                  ) : (
                    <>{t("ifThisMachineStops")}: {t(
                      selectedChoice === "whole_line" ? "impactWholeLine" :
                      selectedChoice === "downstream" ? "impactDownstream" : "productionCanContinue",
                    )}</>
                  )}
                </p>
              </section>

              {showQuickActions && (
                <section className="ff2-operational-section" aria-labelledby="ff2-quick-actions">
                  <h4 id="ff2-quick-actions">{t("quickActions")}</h4>
                  <div className="ff2-quick-actions">
                    {canStopHere && (
                      <button onClick={() => { setQuickAction("stop"); setStopReason(""); setStopDetail(""); setFlowNotice(""); }} disabled={flowBusy}>
                        {t("stopMachine")}
                      </button>
                    )}
                    {canReturnHere && (
                      <button className="primary" disabled={flowBusy} onClick={() => void returnProduction()}>
                        {t("returnProduction")}
                      </button>
                    )}
                    {canRestartHere && (
                      <button className="primary" disabled={flowBusy} onClick={() => void startMachine()}>
                        {t("downtimeEnd")}
                      </button>
                    )}
                    {canStartHere && (
                      <button className="primary" disabled={flowBusy} onClick={() => void startMachine()}>
                        {t("startMachine")}
                      </button>
                    )}
                    {canTransferHere && (
                        <button disabled={flowBusy} onClick={() => {
                          setTransferTarget(String(transferCandidates[0].id));
                          setFlowNotice("");
                        }}>{t("transferProduction")}</button>
                    )}
                    {transferActive && activeAltRow && (
                      <button onClick={() => { setSelectedId(String(activeAltRow.id)); setQuickAction(null); setFlowNotice(""); }}>
                        {t("viewAlternative")}
                      </button>
                    )}
                    {actingOriginal && (
                      <button onClick={() => { setSelectedId(String(actingOriginal.id)); setQuickAction(null); setFlowNotice(""); }}>
                        {t("viewOriginal")}
                      </button>
                    )}
                  </div>

                  {quickAction === "stop" && canStopHere && (
                    <form className="ff2-quick-form" onSubmit={(event) => void stopMachine(event)}>
                      <label>{t("lossStopType")}
                        <select value={stopNature} onChange={(event) => {
                          setStopNature(event.target.value as "unplanned" | "planned");
                          setStopReason(""); setPlannedActivity("");
                        }}>
                          <option value="unplanned">{t("lossUnplanned")}</option>
                          <option value="planned">{t("lossPlanned")}</option>
                        </select>
                      </label>
                      {stopNature === "unplanned" ? <label>{t("downtimeInitialReason")}
                        <select required value={stopReason} onChange={(event) => setStopReason(event.target.value)}>
                          <option value="">{t("downtimeChooseReason")}</option>
                          {stopCategories.map(({ row, key }) => <option key={String(row?.id)} value={String(row?.id)}>{t(key)}</option>)}
                        </select>
                      </label> : <label>{t("lossPlannedActivity")}
                        <select required value={plannedActivity}
                          onChange={(event) => setPlannedActivity(event.target.value)}>
                          <option value="">{t("lossChooseActivity")}</option>
                          {(["cleaning", "changeover", "preventive_maintenance",
                            "inspection", "planned_process", "other"] as const).map((activity) =>
                            <option key={activity} value={activity}>{t(`lossActivity_${activity}`)}</option>)}
                        </select>
                      </label>}
                      <label>{t("downtimeOperatorNote")}
                        <textarea maxLength={2000} value={stopDetail}
                          onChange={(event) => setStopDetail(event.target.value)} />
                      </label>
                      <div className="ff2-row-actions">
                        <button className="primary" disabled={flowBusy ||
                          (stopNature === "unplanned" ? !stopReason : !plannedActivity)}>{t("confirmStop")}</button>
                        <button type="button" onClick={() => setQuickAction(null)}>{t("cancel")}</button>
                      </div>
                    </form>
                  )}

                  {transferTarget && selected.status === "stopped" && !transferActive && (
                    <div className="ff2-quick-form">
                      {transferCandidates.length > 1 && (
                        <label>{t("alternativeMachines")}
                          <select value={transferTarget} onChange={(event) => setTransferTarget(event.target.value)}>
                            {transferCandidates.map((alt: Row) => <option key={String(alt.id)} value={String(alt.id)}>{localName(alt, lang)}</option>)}
                          </select>
                        </label>
                      )}
                      <p>{t("transferTo")} {localName(transferCandidates.find((alt: Row) => String(alt.id) === transferTarget), lang)}</p>
                      <label>{t("reason")}
                        <textarea value={transferReason} onChange={(event) => setTransferReason(event.target.value)} minLength={3} maxLength={2000} />
                      </label>
                      <div className="ff2-row-actions">
                        <button className="primary" disabled={flowBusy || transferReason.trim().length < 3} onClick={() => void runTransfer()}>{t("transferProduction")}</button>
                        <button onClick={() => { setTransferTarget(null); setTransferReason(""); }}>{t("cancel")}</button>
                      </div>
                    </div>
                  )}
                </section>
              )}
              {flowNotice && flowNotice !== 'saved' && <p role="alert" className="notice">{t(flowNotice)}</p>}
            </div>
            {(can("centers", "view") || can("centers", "edit")) && (
              <footer className="ff2-drawer-foot">
                <button className="ff2-settings-link" onClick={() => props.onManage(String(selected.id))}>
                  {t("machineDetailsSettings")} <span aria-hidden="true" className="ff2-settings-arrow">→</span>
                </button>
              </footer>
            )}
          </aside>
        </>
      )}
    </section>
  );
}
