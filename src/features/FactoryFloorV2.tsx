import { useEffect, useState } from "react";
import { evaluateFlow, formatDuration } from "@/utils/production-flow.mjs";
import {
  downtimeMinutes,
  lineTodayOutput,
  reportPeriod,
} from "@/utils/manufacturing.mjs";
import MachineIcon from "@/components/MachineIcon";
import FlowConnector from "@/components/FlowConnector";
import LineConfigPanels, {
  type PanelKey,
  type PanelsState,
} from "./LineConfigPanels";
import CenterDetails from "./CenterDetails";
import { localName } from "@/components/ui";
import {
  machineVisualStates,
  matchesVisualFilter,
  lineVisualStatus,
  connectorFlowing,
  impactChoice,
  applyImpactChoice,
  previewStopImpact,
  alternativeAvailability,
  transferBranches,
  borrowingLineOf,
  categoryIconKey,
  sameCategory,
  liveTransferPicker,
} from "@/utils/floor-visual.mjs";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
/**
 * Factory Floor V2 — visual prototype. Renders the SAME snapshot through the
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
export default function FactoryFloorV2(
  props: FeatureProps & {
    onEditLayout: () => void;
    onRefresh?: () => void;
  },
) {
  const { snapshot: s, t, lang, can } = props;
  const [filter, setFilter] = useState("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [tab, setTab] = useState<
    "overview" | "flow" | "downtime" | "configuration"
  >("overview");
  const [panels, setPanels] = useState<PanelsState>({
    line: false,
    machine: false,
    areas: false,
  });
  const [requestOpen, setRequestOpen] = useState<PanelKey | null>(null);
  const [pendingChoice, setPendingChoice] = useState<string | null>(null);
  const [editingAlts, setEditingAlts] = useState(false);
  const [altDraft, setAltDraft] = useState<string[]>([]);
  const [transferTarget, setTransferTarget] = useState<string | null>(null);
  const [transferReason, setTransferReason] = useState("");
  const [flowNotice, setFlowNotice] = useState("");
  const [flowBusy, setFlowBusy] = useState(false);
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
    if (!selected) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        if (detailsOpen) setDetailsOpen(false);
        else setSelectedId(null);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [selected, detailsOpen]);
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
  ) {
    const state = stateOf(c);
    const stop = openStopOf(c);
    const source = state === "affected" ? sourceOf(c) : null;
    return (
      <button
        className={`ff2-node ff2-${state}${dimmed ? " ff2-dim" : ""}`}
        onClick={() => {
          setSelectedId(String(c.id));
          setDetailsOpen(false);
          setTab(state === "stopped" ? "flow" : "overview");
          setPendingChoice(null);
          setEditingAlts(false);
          setTransferTarget(null);
          setTransferReason("");
          setFlowNotice("");
        }}
        key={String(c.id)}
      >
        <MachineIcon
          center={c}
          running={state === "running" || state === "alternative"}
          categoryIconKey={
            categoryIconKey(c, s.tables.work_center_categories) || undefined
          }
        />
        <span className="ff2-node-name">{localName(c, lang)}</span>
        <span className={`ff2-chip ff2-chip-${state}`}>
          {t(branch?.labelKey || stateLabelKey[state])}
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
          <span className="ff2-node-source">{t(branch.note)}</span>
        ) : source ? (
          <span className="ff2-node-source">
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
  function lineCard(line: Row | null) {
    const lineId = line ? String(line.id) : "";
    const borrowed = borrowedInto(lineId);
    const homeMachines = centers
      .filter((c) =>
        line ? c.line_id === line.id : !c.line_id,
      )
      .filter((c) => !borrowed.some((b) => String(b.id) === String(c.id)))
      .sort((a, b) => Number(a.position) - Number(b.position));
    if (!homeMachines.length && !borrowed.length) return null;
    const machines = homeMachines;
    const borrowedAwayIds = machines
      .filter(isBorrowedElsewhere)
      .map((m) => String(m.id));
    const relevant = machines.filter(matchesFilter);
    // Filtering keeps the complete path: the line only disappears when nothing matches.
    if (filter !== "all" && !relevant.length && !borrowed.length) return null;
    const status = lineVisualStatus(
      machines.map((m) => String(m.id)),
      visual,
      allBranches,
      borrowedAwayIds,
    );
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
      <section className="ff2-card" key={String(line ? line.id : "independent")}>
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
          {status && (
            <span className={`ff2-chip ff2-chip-line ff2-chip-${status}`}>
              {t(status)}
            </span>
          )}
        </header>
        <div className="ff2-flow" dir="ltr">
          {machines.map((c, i) => {
            const branch = borrowed.find(
              (b) => String(b.id) === String(c.id),
            );
            return (
              <span className="ff2-flow-item" key={String(c.id)}>
                {i > 0 && (
                  <FlowConnector
                    active={connectorFlowing(
                      machines[i - 1], c, visual, flow, borrowedAwayIds,
                    )}
                  />
                )}
                {branch ? (
                  <>
                    {node(c, filter !== "all" && !matchesFilter(c))}
                  </>
                ) : isBorrowedElsewhere(c) ? (
                  <button
                    className="ff2-node ff2-borrowed"
                    onClick={() => {
                      setSelectedId(String(c.id));
                      setDetailsOpen(false);
                      setTab("overview");
                      setPendingChoice(null);
                      setEditingAlts(false);
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
                    <span className="ff2-node-name">{localName(c, lang)}</span>
                    <span className="ff2-node-source">
                      {t("temporarilyAssignedTo")}{" "}
                      {(() => {
                        const bl = borrowingLineOf(c, allBranches, lines);
                        return bl ? localName(bl, lang) : t("anotherLine");
                      })()}
                    </span>
                  </button>
                ) : (
                  node(c, filter !== "all" && !matchesFilter(c))
                )}
                {/* Transfer branch: the borrowed machine renders right after
                    its stopped original while the transfer row is open. Only an
                    effectively flowing branch (evaluateFlow credits the
                    transfer AND the restored route is clear) gets the active
                    blue reroute; blocked routes and stopped alternatives stay
                    visible with their truthful, non-success presentation. */}
                {(() => {
                  const branchHere = lineBranches(lineId).find(
                    (b) => String(b.original.id) === String(c.id),
                  );
                  if (!branchHere) return null;
                  const alt = branchHere.alternative as Row;
                  const nextMachine = machines[i + 1];
                  const dim = filter !== "all" && !matchesFilter(alt);
                  if (branchHere.state === "flowing")
                    return (
                      <>
                        <span className="ff2-branch-reroute" aria-hidden="true">
                          ⤵
                        </span>
                        {node(alt, dim)}
                        {nextMachine && (
                          <span className="ff2-branch-return" aria-hidden="true">
                            ⤴
                          </span>
                        )}
                      </>
                    );
                  return (
                    <>
                      <span
                        className="ff2-branch-reroute ff2-branch-off"
                        aria-hidden="true"
                      >
                        ⤵
                      </span>
                      {node(alt, dim, {
                        labelKey:
                          branchHere.state === "routeBlocked"
                            ? "flowBlocked"
                            : undefined,
                        note: "alternativeAssigned",
                      })}
                      {nextMachine && (
                        <span
                          className="ff2-branch-return ff2-branch-off"
                          aria-hidden="true"
                        >
                          ⤴
                        </span>
                      )}
                    </>
                  );
                })()}
              </span>
            );
          })}
        </div>
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
  const flowOf = (id: string) => flow[id]?.state;
  // "active" availability means effectively carrying production — an open
  // transfer with a blocked route or a stopped alternative does not count.
  const flowingAltIds = allBranches
    .filter((b) => b.state === "flowing")
    .map((b) => String(b.alternative.id));
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
  const effectiveChoice = pendingChoice ?? selectedChoice;
  const previewApply =
    selected && effectiveChoice
      ? applyImpactChoice(effectiveChoice, {
          dependency_mode: String(selected.dependency_mode || ""),
        })
      : null;
  const preview =
    selected && previewApply
      ? previewStopImpact(
          centers,
          stops,
          transfers,
          String(selected.id),
          previewApply.dependency_mode,
          previewApply.impact_scope,
        )
      : null;
  const previewNames = (preview?.affectedIds || [])
    .map((id) => centers.find((c) => String(c.id) === id))
    .filter((x): x is Row => !!x)
    .map((c) => localName(c, lang));
  const impactEditable =
    !!selected &&
    selected.line_id &&
    selected.dependency_mode !== "independent" &&
    can("lines", "edit") &&
    can("centers", "edit");
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
  const actingActive =
    !!actingFor && flowOf(String(actingFor.original_id)) === "transferred";
  const availabilityRows = selected
    ? selectedAlternatives.map((alt) => ({
        alt,
        availability: alternativeAvailability(alt, flowingAltIds, selected.order_id),
      }))
    : [];
  // Same-category machines ELIGIBLE to be configured (relationship stays explicit).
  const sameCategoryMachines = selected
    ? centers.filter(
        (c) => String(c.id) !== String(selected.id) && sameCategory(selected, c),
      )
    : [];
  // LIVE picker mirrors transfer_production's rules on BOTH sides.
  const livePicker = selected
    ? liveTransferPicker(
        selected,
        centers,
        selectedAlternatives.map((a) => String(a.id)),
        transfers,
        orders,
      )
    : { blockedReason: null as string | null, candidates: [] as Row[] };
  const transferCandidates = livePicker.blockedReason
    ? []
    : livePicker.candidates;
  const canEditAlts = !!selected && can("centers", "edit");
  const canTransfer =
    !!selected && can("centers", "edit") && can("orders", "edit");
  const canReturn = can("centers", "edit") || can("machine_status", "edit");
  async function saveImpact() {
    if (!selected || !pendingChoice || !previewApply) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      const layout = centers.map((c) => ({
        id: String(c.id),
        line_id: c.line_id ? String(c.line_id) : null,
        position: Number(c.position),
        dependency_mode:
          String(c.id) === String(selected.id)
            ? previewApply.dependency_mode
            : String(c.dependency_mode),
        buffer_minutes: Number(c.buffer_minutes),
        impact_scope:
          String(c.id) === String(selected.id)
            ? previewApply.impact_scope
            : String(c.impact_scope),
      }));
      await props.command("save_line_layout", {
        factory: s.factory?.id,
        version: Number(s.factory?.structure_version),
        layout,
      });
      setPendingChoice(null);
      setFlowNotice("saved");
    } catch (error) {
      const key = error instanceof Error ? error.message : "error";
      setFlowNotice(key);
      // Never overwrite or auto-retry a stale layout: surface the conflict and
      // refresh so the next attempt uses the latest structure version.
      if (key === "layoutConflict") props.onRefresh?.();
    } finally {
      setFlowBusy(false);
    }
  }
  async function saveAlternatives() {
    if (!selected) return;
    setFlowBusy(true);
    setFlowNotice("");
    try {
      await props.command("configure_center_alternatives", {
        factory: s.factory?.id,
        work_center: selected.id,
        alternatives: altDraft,
      });
      setEditingAlts(false);
      setFlowNotice("saved");
    } catch (error) {
      setFlowNotice(error instanceof Error ? error.message : "error");
    } finally {
      setFlowBusy(false);
    }
  }
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
  const config: [string, string][] = selected
    ? [
        ["type", t(String(selected.type || "machine"))],
        [
          "area_id",
          localName(
            s.tables.areas?.find((a) => a.id === selected.area_id),
            lang,
          ) || "—",
        ],
        [
          "line",
          selectedLine ? localName(selectedLine, lang) : t("independent"),
        ],
        ["code", String(selected.code || "—")],
        [
          "operator",
          String(
            s.tables.memberships?.find((m) => m.id === selected.operator_id)
              ?.display_name || "—",
          ),
        ],
        ["production_speed", String(selected.production_speed || "—")],
        [
          "default_cycle_time",
          String(selected.default_cycle_time || "—"),
        ],
        [
          "current_cycle_time",
          String(selected.current_cycle_time || "—"),
        ],
        ["planned_capacity", String(selected.planned_capacity || "—")],
      ]
    : [];
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
          {(can("lines", "create") || can("centers", "create")) && (
            <div className="ff2-add">
              <button
                className="ff2-add-btn"
                aria-expanded={addOpen}
                onClick={() => setAddOpen(!addOpen)}
              >
                + {t("add")}
              </button>
              {addOpen && (
                <div className="ff2-add-menu">
                  {can("lines", "create") && (
                    <button
                      onClick={() => {
                        setRequestOpen("line");
                        setAddOpen(false);
                      }}
                    >
                      {t("createLine")}
                    </button>
                  )}
                  {can("centers", "create") && (
                    <button
                      onClick={() => {
                        setRequestOpen("machine");
                        setAddOpen(false);
                      }}
                    >
                      {t("addMachine")}
                    </button>
                  )}
                </div>
              )}
            </div>
          )}
          <button onClick={props.onEditLayout}>{t("editLayout")}</button>
        </div>
      </header>
      {lines.map(lineCard)}
      {lineCard(null)}
      <LineConfigPanels
        {...props}
        draft={false}
        panels={panels}
        setPanels={setPanels}
        onDiscardDraft={() => undefined}
        requestOpen={requestOpen}
        onRequestHandled={() => setRequestOpen(null)}
      />
      {selected && (
        <>
          <div
            className="ff2-drawer-backdrop"
            onClick={() => setSelectedId(null)}
            aria-hidden="true"
          />
          <aside
            className="ff2-drawer"
            role="dialog"
            aria-label={localName(selected, lang)}
          >
            <header className="ff2-drawer-head">
              <MachineIcon
                center={selected}
                running={selectedState === "running" || selectedState === "alternative"}
                categoryIconKey={
                  categoryIconKey(selected, s.tables.work_center_categories) ||
                  undefined
                }
              />
              <div>
                <h3>{localName(selected, lang)}</h3>
                <p className="ff2-card-sub">
                  {selectedState && (
                    <span className={`ff2-chip ff2-chip-${selectedState}`}>
                      {t(stateLabelKey[selectedState])}
                    </span>
                  )}{" "}
                  {selectedLine
                    ? localName(selectedLine, lang)
                    : t("independent")}
                </p>
              </div>
              <button
                className="ff2-drawer-close"
                aria-label={t("close")}
                onClick={() => setSelectedId(null)}
              >
                ×
              </button>
            </header>
            <div className="ff2-tabs" role="tablist">
              {(
                ["overview", "flow", "downtime", "configuration"] as const
              ).map((x) => (
                <button
                  key={x}
                  role="tab"
                  aria-selected={tab === x}
                  className={tab === x ? "selected" : ""}
                  onClick={() => setTab(x)}
                >
                  {t(x === "flow" ? "productionFlow" : x)}
                </button>
              ))}
            </div>
            <div className="ff2-drawer-body">
              {tab === "overview" && (
                <>
                  <dl className="ff2-dl">
                    <div>
                      <dt>{t("product")}</dt>
                      <dd>
                        {selectedProduct
                          ? localName(selectedProduct, lang)
                          : "—"}
                      </dd>
                    </div>
                    <div>
                      <dt>{t("code")}</dt>
                      <dd>{selectedOrder ? String(selectedOrder.code) : "—"}</dd>
                    </div>
                    <div>
                      <dt>{t("todayProduction")}</dt>
                      <dd>
                        <bdi dir="ltr">
                          {machineOutput(selected).toLocaleString(lang)}
                        </bdi>
                      </dd>
                    </div>
                    <div>
                      <dt>{t("duration")}</dt>
                      <dd>
                        {selectedStop
                          ? formatDuration(
                              (Date.now() -
                                Date.parse(String(selectedStop.started_at))) /
                                60000,
                              lang,
                            )
                          : "—"}
                      </dd>
                    </div>
                    <div>
                      <dt>{t("category")}</dt>
                      <dd>
                        {(() => {
                          const cat = (
                            s.tables.work_center_categories || []
                          ).find(
                            (k) =>
                              String(k.id) === String(selected.category_id),
                          );
                          return cat ? localName(cat, lang) : "—";
                        })()}
                      </dd>
                    </div>
                    {selectedState === "affected" && sourceOf(selected) && (
                      <div>
                        <dt>{t("affected")}</dt>
                        <dd>
                          {t("affectedBy")}{" "}
                          {localName(sourceOf(selected) as Row, lang)}
                        </dd>
                      </div>
                    )}
                  </dl>
                  <div className="ff2-mini-sections">
                    <button
                      className="ff2-mini"
                      onClick={() => {
                        setTab("flow");
                        setPendingChoice(null);
                      }}
                    >
                      <span>{t("productionImpact")}</span>
                      <strong>
                        {selectedState === "stopped" &&
                        actualAffected.length
                          ? `${actualAffected.length} ${t("machinesAffected")}`
                          : effectiveChoice === "whole_line"
                            ? t("entireLine")
                            : effectiveChoice === "downstream"
                              ? t("impactDownstreamShort")
                              : t("impactNoneShort")}
                      </strong>
                    </button>
                    <button
                      className="ff2-mini"
                      onClick={() => {
                        setTab("flow");
                        setEditingAlts(false);
                      }}
                    >
                      <span>{t("alternativeMachines")}</span>
                      <strong>
                        {transferCandidates.length
                          ? `${t("alternativeAvailable")}: ${localName(
                              transferCandidates[0].alt,
                              lang,
                            )}`
                          : `${selectedAlternatives.length} ${t("configuredCount")}`}
                      </strong>
                    </button>
                  </div>
                </>
              )}
              {tab === "flow" && (
                <div className="ff2-flowtab">
                  {actingFor && (
                    <div className="ff2-note ff2-note-blue">
                      <strong>
                        {t("actingAsAlternative")}{" "}
                        {actingOriginal
                          ? localName(actingOriginal, lang)
                          : "—"}
                      </strong>
                      {actingOriginal && (
                        <button
                          onClick={() => {
                            setSelectedId(String(actingOriginal.id));
                            setPendingChoice(null);
                            setEditingAlts(false);
                            setFlowNotice("");
                          }}
                        >
                          {t("viewOriginal")}
                        </button>
                      )}
                    </div>
                  )}
                  {selected.status === "stopped" && (
                    <div className="ff2-note ff2-note-red">
                      <strong>{t("productionFlowInterrupted")}</strong>
                      {transferActive ? (
                        <p>
                          {t("transferredTo")}{" "}
                          {activeAltRow
                            ? localName(activeAltRow, lang)
                            : "—"}{" "}
                          ·{" "}
                          {ownBranchState === "flowing"
                            ? t("alternativeActive")
                            : ownBranchState === "routeBlocked"
                              ? t("flowBlocked")
                              : t("alternativeAssigned")}
                        </p>
                      ) : actualAffected.length ? (
                        <p>
                          {t("impact")}:{" "}
                          {actualAffected
                            .map((c) => localName(c, lang))
                            .join(" · ")}
                        </p>
                      ) : (
                        <p className="ff2-muted">{t("noOtherAffected")}</p>
                      )}
                    </div>
                  )}
                  {transferActive && activeAltRow && (
                    <div className="ff2-row-actions">
                      <button
                        onClick={() => {
                          setSelectedId(String(activeAltRow.id));
                          setPendingChoice(null);
                          setEditingAlts(false);
                          setFlowNotice("");
                        }}
                      >
                        {t("viewAlternative")}
                      </button>
                      {canReturn && (
                        <button
                          className="primary"
                          disabled={flowBusy}
                          onClick={() => void returnProduction()}
                        >
                          {t("returnProduction")}
                        </button>
                      )}
                    </div>
                  )}
                  <h4>{t("ifThisMachineStops")}</h4>
                  {selected.dependency_mode === "independent" ? (
                    <p className="ff2-muted">
                      {t("independentNote")}
                      {impactEditable && (
                        <>
                          {" "}
                          {t("useClassicEditor")}
                        </>
                      )}
                    </p>
                  ) : (
                    <>
                      <div className="ff2-options" role="radiogroup">
                        {(
                          [
                            ["none", "impactNone"],
                            ["downstream", "impactDownstream"],
                            ["whole_line", "impactWholeLine"],
                          ] as const
                        ).map(([value, label]) => (
                          <label
                            key={value}
                            className={`ff2-option${
                              effectiveChoice === value ? " selected" : ""
                            }${impactEditable ? "" : " readonly"}`}
                          >
                            <input
                              type="radio"
                              name="ff2-impact"
                              disabled={!impactEditable}
                              checked={effectiveChoice === value}
                              onChange={() => setPendingChoice(value)}
                            />
                            {t(label)}
                          </label>
                        ))}
                      </div>
                      {!selected.line_id && (
                        <p className="ff2-muted">{t("lineRequiredNote")}</p>
                      )}
                      {selected.dependency_mode === "buffer" && (
                        <p className="ff2-muted">
                          {t("bufferNote")}:{" "}
                          <bdi dir="ltr">
                            {String(selected.buffer_minutes)} {t("min")}
                          </bdi>
                          . {impactEditable ? t("useClassicEditor") : ""}
                        </p>
                      )}
                      {preview && (
                        <p className="ff2-current-effect">
                          {t("currentEffect")}:{" "}
                          {preview.selfState === "bufferActive"
                            ? t("bufferHolds")
                            : previewNames.length
                              ? previewNames.length === centers.filter(
                                    (c) => c.line_id === selected.line_id,
                                  ).length - 1
                                ? t("entireLine")
                                : previewNames.join(" · ")
                              : t("noOtherAffected")}
                        </p>
                      )}
                      {impactEditable && pendingChoice && (
                        <div className="ff2-row-actions">
                          <button
                            className="primary"
                            disabled={flowBusy}
                            onClick={() => void saveImpact()}
                          >
                            {t("save")}
                          </button>
                          <button
                            disabled={flowBusy}
                            onClick={() => setPendingChoice(null)}
                          >
                            {t("cancel")}
                          </button>
                        </div>
                      )}
                    </>
                  )}
                  <h4>{t("alternativeMachines")}</h4>
                  {!editingAlts && (
                    <>
                      {availabilityRows.length ? (
                        <ul className="ff2-alt-list">
                          {availabilityRows.map(({ alt, availability }) => (
                            <li
                              key={String(alt.id)}
                              className={`ff2-alt ${availability === "available" || availability === "active" ? "" : " ff2-dim"}`}
                            >
                              <span>{localName(alt, lang)}</span>
                              <span className="ff2-alt-state">
                                {availability === "available"
                                  ? `● ${t("available")}`
                                  : availability === "active"
                                    ? `↗ ${t("alternativeActive")}`
                                    : availability === "busy"
                                      ? `○ ${t("onAnotherOrder")}`
                                      : `${String(
                                          alt.status === "stopped"
                                            ? "■"
                                            : alt.status === "running"
                                              ? "●"
                                              : "○",
                                        )} ${t(String(alt.status))}`}
                              </span>
                            </li>
                          ))}
                        </ul>
                      ) : (
                        <p className="ff2-muted">
                          {t("noAlternativeConfigured")}
                        </p>
                      )}
                      {selected.status === "stopped" &&
                        !transferActive &&
                        canTransfer && (
                          <div className="ff2-transfer">
                            {livePicker.blockedReason ? (
                              <p className="ff2-muted">
                                {t(livePicker.blockedReason)}
                              </p>
                            ) : !transferCandidates.length ? (
                              <p className="ff2-muted">
                                {t("noAlternativeAvailable")}
                              </p>
                            ) : (
                              <>
                            {transferCandidates.length === 1 && (
                              <button
                                className="primary"
                                disabled={flowBusy}
                                onClick={() => {
                                  setTransferTarget(
                                    String(transferCandidates[0].id),
                                  );
                                }}
                              >
                                {t("transferTo")}{" "}
                                {localName(transferCandidates[0], lang)}
                              </button>
                            )}
                            {transferCandidates.length > 1 &&
                              !transferTarget && (
                                <button
                                  disabled={flowBusy}
                                  onClick={() =>
                                    setTransferTarget(
                                      String(transferCandidates[0].id),
                                    )
                                  }
                                >
                                  {t("transferProduction")}
                                </button>
                              )}
                            {transferCandidates.length >= 1 &&
                              transferTarget && (
                                <>
                                  {transferCandidates.length > 1 && (
                                    <div className="ff2-options">
                                      {transferCandidates.map((alt: Row) => (
                                        <label
                                          key={String(alt.id)}
                                          className={`ff2-option${
                                            transferTarget === String(alt.id)
                                              ? " selected"
                                              : ""
                                          }`}
                                        >
                                          <input
                                            type="radio"
                                            name="ff2-transfer-target"
                                            checked={
                                              transferTarget === String(alt.id)
                                            }
                                            onChange={() =>
                                              setTransferTarget(String(alt.id))
                                            }
                                          />
                                          {localName(alt, lang)} ·{" "}
                                          {t(String(alt.status))}
                                        </label>
                                      ))}
                                    </div>
                                  )}
                                  <textarea
                                    value={transferReason}
                                    onChange={(e) =>
                                      setTransferReason(e.target.value)
                                    }
                                    placeholder={t("reason")}
                                    minLength={3}
                                    maxLength={2000}
                                  />
                                  <div className="ff2-row-actions">
                                    <button
                                      className="primary"
                                      disabled={
                                        flowBusy ||
                                        !selected.order_id ||
                                        transferReason.trim().length < 3
                                      }
                                      onClick={() => void runTransfer()}
                                    >
                                      {t("transferProduction")}
                                    </button>
                                    <button
                                      disabled={flowBusy}
                                      onClick={() => {
                                        setTransferTarget(null);
                                        setTransferReason("");
                                      }}
                                    >
                                      {t("cancel")}
                                    </button>
                                  </div>
                                </>
                              )}
                              </>
                            )}
                          </div>
                        )}
                      {canEditAlts && (
                        <div className="ff2-row-actions">
                          <button
                            onClick={() => {
                              setAltDraft(
                                selectedAlternatives.map((a) => String(a.id)),
                              );
                              setEditingAlts(true);
                            }}
                          >
                            {selectedAlternatives.length
                              ? t("editAlternatives")
                              : t("configureAlternative")}
                          </button>
                        </div>
                      )}
                    </>
                  )}
                  {editingAlts && (
                    <div className="ff2-alt-edit">
                      <p className="ff2-muted">{t("selectAlternatives")}</p>
                      <ul className="ff2-alt-list">
                        {sameCategoryMachines.map((c) => (
                          <li key={String(c.id)}>
                            <label className="ff2-check">
                              <input
                                type="checkbox"
                                checked={altDraft.includes(String(c.id))}
                                onChange={(e) =>
                                  setAltDraft(
                                    e.target.checked
                                      ? [...altDraft, String(c.id)]
                                      : altDraft.filter(
                                          (x) => x !== String(c.id),
                                        ),
                                  )
                                }
                              />
                              {localName(c, lang)}{" "}
                              <span className="ff2-muted">
                                · {t(String(c.status))}
                              </span>
                            </label>
                          </li>
                        ))}
                      </ul>
                      {!sameCategoryMachines.length && (
                        <p className="ff2-muted">
                          {t("noSameCategoryMachines")}
                        </p>
                      )}
                      <div className="ff2-row-actions">
                        <button
                          className="primary"
                          disabled={flowBusy}
                          onClick={() => void saveAlternatives()}
                        >
                          {t("save")}
                        </button>
                        <button
                          disabled={flowBusy}
                          onClick={() => setEditingAlts(false)}
                        >
                          {t("cancel")}
                        </button>
                      </div>
                    </div>
                  )}
                  {flowNotice && (
                    <p role="status" className="notice">
                      {t(flowNotice)}
                    </p>
                  )}
                </div>
              )}
              {tab === "downtime" && selectedStop && (
                <div className="ff2-downtime">
                  <strong>
                    {localName(
                      s.tables.downtime_reasons?.find(
                        (r) => r.id === selectedStop.reason_id,
                      ),
                      lang,
                    )}
                  </strong>
                  <p>
                    {t("duration")}:{" "}
                    {formatDuration(
                      (Date.now() - Date.parse(String(selectedStop.started_at))) /
                        60000,
                      lang,
                    )}
                  </p>
                  {selectedStop.expected_restart && (
                    <p>{t("expectedRestart")}: {String(selectedStop.expected_restart)}</p>
                  )}
                  {String(selectedStop.notes || "") && (
                    <p>{String(selectedStop.notes)}</p>
                  )}
                </div>
              )}
              {tab === "downtime" && !selectedStop && (
                <p className="ff2-muted">{t("allClear")}</p>
              )}
              {tab === "configuration" && (
                <>
                  <dl className="ff2-dl">
                    {config.map(([key, value]) => (
                      <div key={key}>
                        <dt>{t(key)}</dt>
                        <dd>{value}</dd>
                      </div>
                    ))}
                  </dl>
                  <p className="ff2-muted">{t("configurationHelp")}</p>
                </>
              )}
            </div>
            {(can("centers", "edit") ||
              can("machine_status", "edit") ||
              can("downtime", "edit") ||
              can("orders", "edit")) && (
              <footer className="ff2-drawer-foot">
                <button
                  className="primary"
                  onClick={() => setDetailsOpen(true)}
                >
                  {t("operatorView")}
                </button>
              </footer>
            )}
          </aside>
          {detailsOpen && (
            <CenterDetails
              {...props}
              center={selected}
              onClose={() => setDetailsOpen(false)}
            />
          )}
        </>
      )}
    </section>
  );
}
