import { useEffect, useRef, useState } from "react";
import { evaluateFlow, formatDuration } from "@/utils/production-flow.mjs";
import {
  downtimeMinutes,
  lineTodayOutput,
  reportPeriod,
} from "@/utils/manufacturing.mjs";
import MachineIcon from "@/components/MachineIcon";
import FactoryRoute from "@/components/FactoryRoute";
import { localName } from "@/components/ui";
import {
  machineVisualStates,
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
const pauseReasons = ["borrow_machine", "planned_stop", "cleaning", "changeover", "no_production", "other"];
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
  const [quickAction, setQuickAction] = useState<"stop" | "output" | null>(null);
  const [stopReason, setStopReason] = useState("");
  const [stopNotes, setStopNotes] = useState("");
  const [outputProduced, setOutputProduced] = useState("");
  const [outputRejected, setOutputRejected] = useState("0");
  const outputRequestId = useRef<string>("");
  const drawerRef = useRef<HTMLElement>(null);
  const drawerCloseRef = useRef<HTMLButtonElement>(null);
  const openerRef = useRef<HTMLButtonElement>(null);
  const centers = (s.tables.work_centers || []).filter((c) => !c.archived);
  const lines = (s.tables.production_lines || []).filter((l) => !l.archived);
  const orders = s.tables.production_orders || [];
  const stops = s.tables.downtime_events || [];
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
  );
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
  function node(
    c: Row,
    dimmed: boolean,
    branch?: { labelKey?: string; note?: string },
    paused = false,
  ) {
    const state = (paused ? String(c.status || "idle") : stateOf(c)) as VisualState;
    const stop = openStopOf(c);
    const source = state === "affected" ? sourceOf(c) : null;
    return (
      <button
        className={`ff2-node ff2-${state}${dimmed ? " ff2-dim" : ""}`}
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
        <MachineIcon
          center={c}
          running={!paused && (state === "running" || state === "alternative")}
          categoryIconKey={
            categoryIconKey(c, s.tables.work_center_categories) || undefined
          }
        />
        <span className="ff2-node-name" dir="auto">{localName(c, lang)}</span>
        <span className={`ff2-chip ff2-chip-${state}`} dir="auto">
          {t(paused ? stateLabelKey[state] : branch?.labelKey || stateLabelKey[state])}
        </span>
        {state === "stopped" && stop && (
          <span className="ff2-node-duration">
            {formatDuration(
              (Date.now() - Date.parse(String(stop.started_at))) / 60000,
              lang,
            )}
          </span>
        )}
        {branch?.note ? (
          <span className="ff2-node-source" dir="auto">{t(branch.note)}</span>
        ) : source ? (
          <span className="ff2-node-source" dir="auto">
            {t("affectedBy")} {localName(source, lang)}
          </span>
        ) : null}
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
    const status = lineOperationalStatus(lineVisualStatus(
      machines.map((m) => String(m.id)),
      visual,
      allBranches,
      borrowedAwayIds,
      flow,
    ), pausedAt);
    const activeOrder = line
      ? orders.find(
          (o) => o.status === "active" && o.line_id === line.id,
        )
      : undefined;
    const product = s.tables.products?.find(
      (p) => p.id === activeOrder?.product_id,
    );
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
      Number(activeOrder.produced_quantity) > 0
        ? Math.round(
            (Number(activeOrder.produced_quantity) /
              Number(activeOrder.target_quantity)) *
              100,
          )
        : null;
    return (
      <section className={`ff2-card${pausedAt ? " ff2-paused" : ""}`} key={String(line ? line.id : "independent")}>
        <header className="ff2-card-head">
          <div>
            <h3>{line ? localName(line, lang) : t("independent")}</h3>
            {(product || activeOrder) && (
              <p className="ff2-card-sub">
                {product ? localName(product, lang) : "—"}
                {activeOrder ? ` · ${String(activeOrder.code)}` : ""}
              </p>
            )}
          </div>
          <div className="ff2-card-controls">
            {status && <span className={`ff2-chip ff2-chip-line ff2-chip-${status}`}>{t(status)}</span>}
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
        <FactoryRoute machines={machines} continuationLabel={t("routeContinues")}
          connectorActive={(a, b) => lineFlowActive(connectorFlowing(a, b, visual, flow, borrowedAwayIds), pausedAt)}
          renderMachine={(c, i) => {
            const branchHere = lineBranches(lineId).find((b) => String(b.original.id) === String(c.id));
            return <>
              {isBorrowedElsewhere(c) ? (
                  <button
                    className="ff2-node ff2-borrowed"
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
                    <MachineIcon
                      center={c}
                      running={false}
                      categoryIconKey={
                        categoryIconKey(c, s.tables.work_center_categories) ||
                        undefined
                      }
                    />
                    <span className="ff2-node-name" dir="auto">{localName(c, lang)}</span>
                    <span className="ff2-node-source" dir="auto">
                      {t("temporarilyAssignedTo")}{" "}
                      {(() => {
                        const bl = borrowingLineOf(c, allBranches, lines);
                        return bl ? localName(bl, lang) : t("anotherLine");
                      })()}
                    </span>
                  </button>
              ) : node(c, filter !== "all" && !matchesFilter(c), undefined, Boolean(pausedAt))}
              {branchHere && <div className={`ff2-branch${lineFlowActive(branchHere.state === "flowing", pausedAt) ? "" : " ff2-branch-muted"}`}>
                <span className={`ff2-branch-reroute${lineFlowActive(branchHere.state === "flowing", pausedAt) ? "" : " ff2-branch-off"}`} aria-hidden="true">⤵</span>
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
        <footer className="ff2-card-foot">
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
        </footer>
      </section>
    );
  }
  const selectedState = selected ? stateOf(selected) : null;
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
  const canRecordOutput =
    !selectedFromHomePlaceholder && hasActiveProduction && can("orders", "edit") &&
    !(borrowedBy ? borrowedBy.paused_at : selectedLine?.paused_at) &&
    (selectedDisplayState === "running" || selectedDisplayState === "alternative");
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
  const showQuickActions = canStopHere || canRecordOutput || canReturnHere || canRestartHere ||
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
    if (!selected || !stopReason) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      await props.command("change_status", {
        factory: s.factory?.id, work_center: selected.id, status: "stopped",
        reason: stopReason, sub_reason: null, notes: stopNotes,
        expected_restart: null, responsible: null, alternative: null,
        transferred: false,
      });
      setQuickAction(null);
      setStopReason("");
      setStopNotes("");
      setFlowNotice("saved");
    } catch (error) {
      setFlowNotice(error instanceof Error ? error.message : "error");
    } finally {
      setFlowBusy(false);
    }
  }
  async function recordOutput(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selected || !selectedOrder || !outputRequestId.current) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      await props.command("record_output", {
        factory: s.factory?.id, work_center: selected.id,
        production_order: selectedOrder.id, request_id: outputRequestId.current,
        produced: Number(outputProduced), rejected: Number(outputRejected), notes: "",
      });
      setQuickAction(null);
      setOutputProduced("");
      setOutputRejected("0");
      outputRequestId.current = "";
      setFlowNotice("saved");
    } catch (error) {
      setFlowNotice(error instanceof Error ? error.message : "error");
    } finally {
      setFlowBusy(false);
    }
  }
  return (
    <section className="ff2">
      <header className="ff2-head">
        <h2>{t("floor")}</h2>
        <div className="ff2-head-actions">
          <div className="ff2-filters" role="group" aria-label={t("status")}>
            {filters.map(([key, count]) => (
              <button
                key={key}
                className={filter === key ? "selected" : ""}
                onClick={() => setFilter(key)}
              >
                {t(key === "affected" ? "affected" : key)}{" "}
                <span>{count}</span>
              </button>
            ))}
          </div>
          {(can("lines", "edit") || can("centers", "edit") || can("lines", "create") || can("centers", "create")) &&
            <button className="ff2-manage" onClick={() => props.onManage()}>{t("manageLinesMachines")}</button>}
        </div>
      </header>
      {lines.map(lineCard)}
      {lineCard(null)}
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
                    <span className={`ff2-chip ff2-chip-${selectedDisplayState}`}>
                      {t(stateLabelKey[selectedDisplayState])}
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
                          {Number(selectedOrder?.produced_quantity).toLocaleString(lang)} / {Number(selectedOrder?.target_quantity).toLocaleString(lang)}
                        </bdi></span>
                      )}
                  </div>
                </section>
              )}

              {(selectedDisplayState === "stopped" || selectedDisplayState === "affected") && (
                <section className="ff2-operational-section" aria-labelledby="ff2-current-issue">
                  <h4 id="ff2-current-issue">{t("currentIssue")}</h4>
                  <div className="ff2-issue-card">
                    {selectedDisplayState === "stopped" && (
                      <>
                        <strong dir="auto">{stopReasonRow ? localName(stopReasonRow, lang) : t("stopped")}</strong>
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
                      <button onClick={() => { setQuickAction("stop"); setFlowNotice(""); }} disabled={flowBusy}>
                        {t("stopMachine")}
                      </button>
                    )}
                    {canRecordOutput && (
                      <button onClick={() => { outputRequestId.current = crypto.randomUUID(); setQuickAction("output"); setFlowNotice(""); }} disabled={flowBusy}>
                        {t("recordOutput")}
                      </button>
                    )}
                    {canReturnHere && (
                      <button className="primary" disabled={flowBusy} onClick={() => void returnProduction()}>
                        {t("returnProduction")}
                      </button>
                    )}
                    {canRestartHere && (
                      <button className="primary" disabled={flowBusy} onClick={() => void startMachine()}>
                        {t("returnToRunning")}
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

                  {quickAction === "stop" && (
                    <form className="ff2-quick-form" onSubmit={(event) => void stopMachine(event)}>
                      <label>{t("reason")}
                        <select value={stopReason} required onChange={(event) => setStopReason(event.target.value)}>
                          <option value="">{t("reason")}</option>
                          {(s.tables.downtime_reasons || []).filter((r) => !r.parent_id).map((r) => (
                            <option key={String(r.id)} value={String(r.id)}>{localName(r, lang)}</option>
                          ))}
                        </select>
                      </label>
                      <label>{t("describeReason")}
                        <textarea value={stopNotes} onChange={(event) => setStopNotes(event.target.value)} maxLength={2000}
                          minLength={3} required={Boolean(s.tables.downtime_reasons?.find((r) => r.id === stopReason)?.requires_description)} />
                      </label>
                      <div className="ff2-row-actions">
                        <button className="primary" disabled={flowBusy || !stopReason}>{t("stopMachine")}</button>
                        <button type="button" onClick={() => setQuickAction(null)}>{t("cancel")}</button>
                      </div>
                    </form>
                  )}
                  {quickAction === "output" && (
                    <form className="ff2-quick-form" onSubmit={(event) => void recordOutput(event)}>
                      <label>{t("produced_quantity")}
                        <input type="number" min="1" step="1" required value={outputProduced}
                          onChange={(event) => setOutputProduced(event.target.value)} />
                      </label>
                      <label>{t("rejected_quantity")}
                        <input type="number" min="0" step="1" required value={outputRejected}
                          onChange={(event) => setOutputRejected(event.target.value)} />
                      </label>
                      <div className="ff2-row-actions">
                        <button className="primary" disabled={flowBusy || !outputProduced || Number(outputRejected) > Number(outputProduced)}>{t("recordOutput")}</button>
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
              {flowNotice && <p role="status" className="notice">{t(flowNotice)}</p>}
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
