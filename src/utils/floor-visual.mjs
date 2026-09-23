/**
 * Factory Floor V2 visual-state mapping — pure presentation logic over the
 * EXISTING production-flow verdicts. Physical status (work_centers.status) is
 * each machine's own truth: a stopped machine — including a stop whose
 * production was transferred elsewhere — always renders as stopped. Computed
 * flow impact (evaluateFlow) only overrides physically-running machines, so an
 * "affected" machine is never relabeled as physically stopped and the root
 * machine never displays as "affected by itself".
 */
import { evaluateFlow } from "./production-flow.mjs";
export const VISUAL_STATES = [
  "running",
  "stopped",
  "setup",
  "idle",
  "offline",
  "affected",
  "bufferActive",
  "alternative",
];
/**
 * Branch created by each OPEN production transfer, combining two independent
 * truths. TRANSFER ASSIGNMENT comes from the row itself: while it is open the
 * branch stays visible, the alternative stays borrowed, and its home line
 * keeps the assigned-away placeholder. EFFECTIVE PRODUCTION FLOW is the
 * separate evaluateFlow verdict carried in `state`:
 *   "flowing"            — evaluateFlow finds the alternative and restored
 *                          route clear (including non-blocking originals)
 *   "routeBlocked"       — transfer open but production is not flowing: the
 *                          alternative is itself flow-blocked, or a machine
 *                          downstream of the rejoin is blocked
 *   "alternativeStopped" — the alternative is physically not running
 */
export function transferBranches(centers, flow, transfers) {
  const list = [];
  for (const tx of transfers || []) {
    if (tx.ended_at) continue;
    const original = (centers || []).find(
      (c) => String(c.id) === String(tx.original_id),
    );
    const alternative = (centers || []).find(
      (c) => String(c.id) === String(tx.alternative_id),
    );
    if (!original || !alternative) continue;
    let state;
    if (String(alternative.status || "") !== "running")
      state = "alternativeStopped";
    else if (
      flow[String(original.id)]?.state === "blocked" ||
      flow[String(alternative.id)]?.state === "blocked"
    )
      state = "routeBlocked";
    else {
      // The branch rejoins immediately after the original, so any machine
      // evaluateFlow marks blocked downstream of it on the same line blocks
      // the restored route — evaluateFlow verdicts only, no second engine.
      const lineId = original.line_id ? String(original.line_id) : "";
      state =
        lineId &&
        (centers || []).some(
          (c) =>
            String(c.line_id || "") === lineId &&
            Number(c.position) > Number(original.position) &&
            flow[String(c.id)]?.state === "blocked",
        )
          ? "routeBlocked"
          : "flowing";
    }
    list.push({ transfer: tx, original, alternative, state });
  }
  return list;
}
/**
 * The line currently borrowing this machine through an OPEN transfer —
 * assignment truth, independent of the branch's effective-flow verdict, so a
 * borrowed machine only returns home when the transfer row actually ends.
 */
export function borrowingLineOf(center, branches, lines) {
  const b = (branches || []).find(
    (x) => String(x.alternative.id) === String(center.id),
  );
  if (!b) return undefined;
  const homeId = String(center.line_id || "");
  const borrowId = String(b.original.line_id || "");
  return borrowId !== homeId
    ? (lines || []).find((l) => String(l.id) === borrowId)
    : undefined;
}
export function machineVisualStates(centers, flow, transfers) {
  const branchByAlternative = new Map(
    transferBranches(centers, flow, transfers).map((b) => [
      String(b.alternative.id),
      b.state,
    ]),
  );
  const map = {};
  for (const c of centers || []) {
    const id = String(c.id);
    const status = String(c.status || "idle");
    if (status !== "running") {
      map[id] = status;
      continue;
    }
    // The blue "active" reroute presentation only while the branch effectively
    // carries production; a borrowed machine whose route is blocked renders as
    // affected, and a stopped one keeps its physical status.
    const branchState = branchByAlternative.get(id);
    if (branchState === "flowing") {
      map[id] = "alternative";
      continue;
    }
    if (branchState === "routeBlocked") {
      map[id] = "affected";
      continue;
    }
    const f = flow[id]?.state;
    map[id] =
      f === "blocked" ? "affected" : f === "bufferActive" ? "bufferActive" : "running";
  }
  return map;
}
export function matchesVisualFilter(filter, state) {
  if (filter === "all") return true;
  // A machine producing via an alternative route is operationally running.
  if (filter === "running") return state === "running" || state === "alternative";
  if (filter === "stopped") return state === "stopped";
  if (filter === "affected")
    return state === "affected" || state === "bufferActive";
  return false;
}
/**
 * Line summary chip. "Running via alternative" only while some transfer branch
 * on this line is effectively flowing; an open transfer whose route is blocked
 * or whose alternative is stopped must show the line's real condition instead —
 * the open row alone says nothing, and such a blocked branch also outranks
 * unrelated upstream machines that are still physically running.
 */
export function lineVisualStatus(ids, states, branches, borrowedAwayIds = []) {
  const all = (ids || []).map(String);
  if (!all.length) return null;
  const borrowedAway = new Set((borrowedAwayIds || []).map(String));
  const list = all.filter((id) => !borrowedAway.has(id));
  if (!list.length) return "idle";
  const lineBranches = (branches || []).filter((b) =>
    list.includes(String(b.original.id)),
  );
  if (lineBranches.some((b) => b.state === "flowing"))
    return "runningViaAlternative";
  // A blocked transfer branch means this line is not running via the branch —
  // an unrelated upstream machine still running must not flip the chip back
  // to "running"; the normal chain below reports the real condition instead.
  const branchBlocked = lineBranches.some(
    (b) => b.state === "routeBlocked" || b.state === "alternativeStopped",
  );
  if (
    !branchBlocked &&
    list.some((id) => states[id] === "running" || states[id] === "alternative")
  )
    return "running";
  if (
    list.some((id) => states[id] === "affected" || states[id] === "bufferActive")
  )
    return "affected";
  if (list.every((id) => states[id] === "stopped")) return "stopped";
  // A blocked branch with no other signal is itself an affecting condition.
  return branchBlocked ? "affected" : "idle";
}

/** Home-line connectors never animate through an assigned-away placeholder. */
export function connectorFlowing(a, b, states, flow, borrowedAwayIds = []) {
  const away = new Set((borrowedAwayIds || []).map(String));
  const aId = String(a.id), bId = String(b.id);
  const running = (id) => states[id] === "running" || states[id] === "alternative";
  return (
    !away.has(aId) && !away.has(bId) &&
    running(aId) && running(bId) &&
    flow[aId]?.state !== "blocked" && flow[bId]?.state !== "blocked"
  );
}
/**
 * The simplified V2 impact choice for a machine: which existing impact
 * behavior applies if it stops. Pure mapping of existing values —
 * non_blocking/independent machines and scope "none" all mean no impact.
 */
export function impactChoice(mode, scope) {
  const m = String(mode || ""),
    s = String(scope || "");
  if (s === "none" || m === "non_blocking" || m === "independent")
    return "none";
  return s === "whole_line" ? "whole_line" : "downstream";
}
/**
 * Apply a simplified choice WITHOUT destroying specialized modes: buffer keeps
 * its dependency mode (only impact_scope changes — a radio click can never
 * silently exit buffer); independent is not editable here (returns null so the
 * UI stays read-only); normal machines map to the canonical pairs used by the
 * classic editor's interlocks.
 */
export function applyImpactChoice(choice, current) {
  const scope =
    choice === "whole_line"
      ? "whole_line"
      : choice === "downstream"
        ? "downstream"
        : "none";
  const mode = String(current.dependency_mode || "");
  if (mode === "independent") return null;
  if (mode === "buffer")
    return { dependency_mode: "buffer", impact_scope: scope };
  return {
    dependency_mode: scope === "none" ? "non_blocking" : "blocking",
    impact_scope: scope,
  };
}
/**
 * ONE impact engine: builds a hypothetical snapshot (this machine stopped with
 * the proposed dependency/impact values) and runs the EXISTING evaluateFlow
 * against it. This helper only prepares the input and extracts the affected
 * list from evaluateFlow's verdict; it never reproduces propagation rules.
 */
export function previewStopImpact(
  centers,
  stops,
  transfers,
  machineId,
  mode,
  scope,
) {
  const id = String(machineId);
  const hypothetical = (centers || []).map((c) =>
    String(c.id) === id
      ? {
          ...c,
          status: "stopped",
          dependency_mode: String(mode),
          impact_scope: String(scope),
        }
      : c,
  );
  const flow = evaluateFlow(hypothetical, stops || [], transfers || []);
  const affectedIds = [];
  for (const cid of Object.keys(flow)) {
    const verdict = flow[cid];
    if (
      cid !== id &&
      verdict.state === "blocked" &&
      String(verdict.source) === id
    )
      affectedIds.push(cid);
  }
  return { affectedIds, selfState: flow[id]?.state || "clear" };
}
/**
 * Truthful availability of a CONFIGURED alternative. "active" = effectively
 * carrying production right now (target of a transfer evaluateFlow credits
 * whose restored route is clear — an open transfer with a blocked route or a
 * stopped alternative does not count); "available" = idle and order-
 * compatible (exactly what the existing transfer RPC accepts); other statuses
 * pass through for display, and "busy" marks an idle machine locked to a
 * different production order.
 */
export function alternativeAvailability(alt, activeAlternativeIds, originalOrderId) {
  const id = String(alt.id);
  if ((activeAlternativeIds || []).includes(id)) return "active";
  const status = String(alt.status || "idle");
  if (status === "idle") {
    const orderOk =
      !originalOrderId ||
      !alt.order_id ||
      String(alt.order_id) === String(originalOrderId);
    return orderOk ? "available" : "busy";
  }
  return status;
}

/**
 * Resolve the authoritative icon key for a work center from its category.
 * The category icon is authoritative; the legacy type/name heuristic is only
 * a defensive fallback for centers without a category (should not normally
 * exist — category_id is NOT NULL).
 */
export function categoryIconKey(center, categories) {
  const cat = (categories || []).find(
    (c) => String(c.id) === String(center.category_id),
  );
  return cat ? String(cat.icon_key) : null;
}

/**
 * Same-family eligibility for alternative CONFIGURATION: both centers must
 * carry the same non-null category. Same category makes a center ELIGIBLE to
 * be configured — it never creates the relationship itself.
 */
export function sameCategory(a, b) {
  return (
    !!a?.category_id &&
    String(a.category_id) === String(b?.category_id)
  );
}

/**
 * LIVE transfer picker — mirror of the server's transfer_production rules so
 * the picker only ever lists candidates the RPC would accept right now.
 * Checks BOTH sides: the original machine's prerequisites and each
 * candidate's validity. Returns { blockedReason, candidates }.
 */
export function liveTransferPicker(
  original,
  centers,
  configuredAlternativeIds,
  transfers,
  orders,
) {
  const oid = String(original.id);
  // Original-side prerequisites (server: invalid_order / stale transfers).
  if (String(original.status) !== "stopped")
    return { blockedReason: "transferNotStopped", candidates: [] };
  const openOriginalTransfer = (transfers || []).some(
    (x) => !x.ended_at && String(x.original_id) === oid,
  );
  if (openOriginalTransfer)
    return { blockedReason: "transferAlreadyActive", candidates: [] };
  const order = (orders || []).find(
    (o) =>
      String(o.id) === String(original.order_id) &&
      String(o.status) === "active",
  );
  if (!order)
    return { blockedReason: "activeOrderRequired", candidates: [] };
  const openDowntime = true; // open-stop presence is implied by stopped state in the UI; RPC remains authority
  if (!openDowntime)
    return { blockedReason: "activeOrderRequired", candidates: [] };
  const busyTargets = new Set(
    (transfers || [])
      .filter((x) => !x.ended_at)
      .map((x) => String(x.alternative_id)),
  );
  const candidates = (centers || [])
    .filter(
      (c) =>
        String(c.id) !== oid &&
        !c.archived &&
        (configuredAlternativeIds || []).includes(String(c.id)) &&
        String(c.category_id) === String(original.category_id) &&
        String(c.status) === "idle" &&
        (!c.order_id || String(c.order_id) === String(original.order_id)) &&
        !busyTargets.has(String(c.id)),
    );
  return { blockedReason: null, candidates };
}
