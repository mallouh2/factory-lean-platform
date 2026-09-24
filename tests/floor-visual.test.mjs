import test from "node:test";
import assert from "node:assert/strict";
import {
  machineVisualStates,
  matchesVisualFilter,
  lineVisualStatus,
  connectorFlowing,
  impactChoice,
  applyImpactChoice,
  previewStopImpact,
  alternativeAvailability,
  liveTransferPicker,
  transferBranches,
  borrowingLineOf,
  lineOperationalStatus,
  lineFlowActive,
  routeRows,
} from "../src/utils/floor-visual.mjs";

test("long route wraps in production order without reversing for RTL", () => {
  assert.deepEqual(routeRows([1, 2, 3, 4, 5, 6, 7], 3), [[1, 2, 3], [4, 5, 6], [7]]);
  assert.deepEqual(routeRows([1, 2], 0), [[1], [2]]);
});

test("paused home line releases an idle configured alternative with another order", () => {
  const original = { id: "O", status: "stopped", order_id: "ORDER-B", category_id: "CAT" };
  const alt = { id: "A", status: "idle", order_id: "ORDER-A", line_id: "HOME", category_id: "CAT" };
  const orders = [{ id: "ORDER-B", status: "active" }];
  const pausedLines = [{ id: "HOME", paused_at: "2026-09-23T10:00:00Z" }];
  assert.equal(alternativeAvailability(alt, [], original.order_id, pausedLines), "available");
  assert.deepEqual(
    liveTransferPicker(original, [original, alt], ["A"], [], orders, pausedLines).candidates.map((c) => c.id),
    ["A"],
  );
  assert.equal(alt.line_id, "HOME");
  assert.equal(alternativeAvailability(alt, [], original.order_id, [{ id: "HOME", paused_at: null }]), "busy");
  assert.equal(
    liveTransferPicker(original, [original, alt], ["A"], [], orders, [{ id: "HOME", paused_at: null }]).candidates.length,
    0,
  );
});

test("paused-line exception keeps physical, assignment, category and configuration guards", () => {
  const original = { id: "O", status: "stopped", order_id: "ORDER-B", category_id: "CAT" };
  const alt = { id: "A", status: "idle", order_id: "ORDER-A", line_id: "HOME", category_id: "CAT" };
  const orders = [{ id: "ORDER-B", status: "active" }];
  const pausedLines = [{ id: "HOME", paused_at: "2026-09-23T10:00:00Z" }];
  for (const status of ["stopped", "setup", "offline"]) {
    const unavailable = { ...alt, status };
    assert.equal(alternativeAvailability(unavailable, [], original.order_id, pausedLines), status);
    assert.equal(liveTransferPicker(original, [original, unavailable], ["A"], [], orders, pausedLines).candidates.length, 0);
  }
  const open = [{ original_id: "OTHER", alternative_id: "A", ended_at: null }];
  assert.equal(alternativeAvailability(alt, [], original.order_id, pausedLines, ["A"]), "borrowed");
  assert.equal(liveTransferPicker(original, [original, alt], ["A"], open, orders, pausedLines).candidates.length, 0);
  assert.equal(liveTransferPicker(original, [original, { ...alt, category_id: "OTHER" }], ["A"], [], orders, pausedLines).candidates.length, 0);
  assert.equal(liveTransferPicker(original, [original, alt], [], [], orders, pausedLines).candidates.length, 0);
});

test("line pause masks line success but preserves borrowed flow and physical state", () => {
  const pausedAt = "2026-09-23T09:00:00Z";
  assert.equal(lineOperationalStatus("runningViaAlternative", pausedAt), "paused");
  assert.equal(lineFlowActive(true, pausedAt), false);
  assert.equal(lineFlowActive(true, null), true);
  const centers = [
    { id: "O", status: "stopped", line_id: "L", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
    { id: "A", status: "running", line_id: "H", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  ];
  const transfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];
  const flow = evaluateFlow(centers, [{ work_center_id: "O", started_at: pausedAt, ended_at: null }], transfers);
  const branches = transferBranches(centers, flow, transfers);
  assert.equal(branches[0].state, "flowing");
  assert.equal(centers[1].status, "running");
  assert.equal(centers[1].line_id, "H");
  assert.equal(lineOperationalStatus(lineVisualStatus(["A"], machineVisualStates(centers, flow, transfers), branches, ["A"]), pausedAt), "paused");
  assert.equal(lineOperationalStatus(lineVisualStatus(["O"], machineVisualStates(centers, flow, transfers), branches), null), "runningViaAlternative");
});
import { evaluateFlow } from "../src/utils/production-flow.mjs";

// A five-machine line: O=root stopped machine, U1/U2 upstream, D1/D2 downstream,
// A=a configured alternative. Physical statuses and evaluateFlow verdicts are
// fixtures mirroring what the real utility produces for each impact scope.
const line = [
  { id: "U1", status: "running" },
  { id: "U2", status: "running" },
  { id: "O", status: "stopped" },
  { id: "D1", status: "running" },
  { id: "D2", status: "running" },
];
const ids = line.map((c) => c.id);

test("downstream impact: root stays stopped, only downstream affected", () => {
  const flow = {
    U1: { state: "clear" },
    U2: { state: "clear" },
    O: { state: "blocked", source: "O" },
    D1: { state: "blocked", source: "O" },
    D2: { state: "blocked", source: "O" },
  };
  const s = machineVisualStates(line, flow, []);
  assert.equal(s.O, "stopped");
  assert.equal(s.D1, "affected");
  assert.equal(s.D2, "affected");
  assert.equal(s.U1, "running");
  assert.equal(s.U2, "running");
  // Upstream still producing, so the line itself remains truthfully "running";
  // the blocked detail is visible on the machine chips.
  assert.equal(lineVisualStatus(ids, s, []), "running");
});

test("whole_line impact: every peer affected, root still stopped", () => {
  const flow = {
    U1: { state: "blocked", source: "O" },
    U2: { state: "blocked", source: "O" },
    O: { state: "blocked", source: "O" },
    D1: { state: "blocked", source: "O" },
    D2: { state: "blocked", source: "O" },
  };
  const s = machineVisualStates(line, flow, []);
  assert.equal(s.O, "stopped");
  assert.equal(s.U1, "affected");
  assert.equal(s.U2, "affected");
  assert.equal(s.D1, "affected");
  assert.equal(s.D2, "affected");
});

test("impact_scope none: only the stopped machine shows the problem", () => {
  const flow = {
    U1: { state: "clear" },
    U2: { state: "clear" },
    O: { state: "blocked", source: "O" },
    D1: { state: "clear" },
    D2: { state: "clear" },
  };
  const s = machineVisualStates(line, flow, []);
  assert.equal(s.O, "stopped");
  assert.equal(s.D1, "running");
  assert.equal(s.U1, "running");
});

test("transferred original stays physically stopped", () => {
  const flow = { O: { state: "transferred", source: "O" } };
  const s = machineVisualStates([{ id: "O", status: "stopped" }], flow, [
    { original_id: "O", alternative_id: "A", ended_at: null },
  ]);
  assert.equal(s.O, "stopped");
});

test("running alternative becomes Alternative active", () => {
  const flow = {
    O: { state: "transferred", source: "O" },
    A: { state: "clear" },
  };
  const centers = [
    { id: "O", status: "stopped" },
    { id: "A", status: "running" },
  ];
  const s = machineVisualStates(centers, flow, [
    { original_id: "O", alternative_id: "A", ended_at: null },
  ]);
  assert.equal(s.A, "alternative");
  assert.equal(s.O, "stopped");
});

test("alternative stops -> Alternative active disappears and impact returns", () => {
  // evaluateFlow flips the original back to blocked when the alternative is
  // not running; the alternative leaves the active set automatically.
  const flow = {
    O: { state: "blocked", source: "O" },
    A: { state: "clear" },
    D1: { state: "blocked", source: "O" },
  };
  const centers = [
    { id: "O", status: "stopped" },
    { id: "A", status: "stopped" },
    { id: "D1", status: "running" },
  ];
  const s = machineVisualStates(centers, flow, [
    { original_id: "O", alternative_id: "A", ended_at: null },
  ]);
  assert.equal(s.A, "stopped");
  assert.equal(s.D1, "affected");
  // A still-running alternative that evaluateFlow does not credit (e.g. its own
  // flow is blocked) must not render as Alternative active either.
  const flow2 = {
    O: { state: "blocked", source: "O" },
    A: { state: "blocked", source: "X" },
  };
  const s2 = machineVisualStates(
    [
      { id: "O", status: "stopped" },
      { id: "A", status: "running" },
    ],
    flow2,
    [{ original_id: "O", alternative_id: "A", ended_at: null }],
  );
  assert.equal(s2.A, "affected");
});

test("line shows Running via alternative only for an effectively flowing branch", () => {
  const flow = {
    O: { state: "transferred", source: "O" },
    D1: { state: "clear" },
    A: { state: "clear" },
  };
  const centers = [
    { id: "O", status: "stopped" },
    { id: "D1", status: "running" },
    { id: "A", status: "running" },
  ];
  const transfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];
  const branches = transferBranches(centers, flow, transfers);
  assert.equal(branches.length, 1);
  assert.equal(branches[0].state, "flowing");
  const s = machineVisualStates(centers, flow, transfers);
  assert.equal(s.A, "alternative");
  assert.equal(lineVisualStatus(["O", "D1"], s, branches), "runningViaAlternative");
});

test("open transfer row alone must NOT produce Running via alternative", () => {
  const flow = {
    O: { state: "blocked", source: "O" },
    D1: { state: "blocked", source: "O" },
    A: { state: "blocked", source: "X" },
  };
  const centers = [
    { id: "O", status: "stopped" },
    { id: "D1", status: "running" },
    { id: "A", status: "running" },
  ];
  const transfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];
  const branches = transferBranches(centers, flow, transfers);
  // The branch stays visible (the row is open), but it is not flowing.
  assert.equal(branches.length, 1);
  assert.equal(branches[0].state, "routeBlocked");
  const s = machineVisualStates(centers, flow, transfers);
  assert.equal(s.A, "affected");
  assert.notEqual(
    lineVisualStatus(["O", "D1"], s, branches),
    "runningViaAlternative",
  );
  assert.equal(lineVisualStatus(["O", "D1"], s, branches), "affected");
});

test("Alternative active matches the Running filter", () => {
  assert.equal(matchesVisualFilter("running", "alternative"), true);
  assert.equal(matchesVisualFilter("running", "running"), true);
  assert.equal(matchesVisualFilter("running", "stopped"), false);
  assert.equal(matchesVisualFilter("stopped", "stopped"), true);
  assert.equal(matchesVisualFilter("affected", "bufferActive"), true);
  assert.equal(matchesVisualFilter("all", "offline"), true);
});

test("setup and offline keep their own truthful statuses", () => {
  const s = machineVisualStates(
    [
      { id: "S", status: "setup" },
      { id: "F", status: "offline" },
      { id: "I", status: "idle" },
    ],
    { S: { state: "clear" }, F: { state: "clear" }, I: { state: "clear" } },
    [],
  );
  assert.equal(s.S, "setup");
  assert.equal(s.F, "offline");
  assert.equal(s.I, "idle");
  assert.equal(matchesVisualFilter("stopped", "setup"), false);
  assert.equal(matchesVisualFilter("stopped", "offline"), false);
});

test("flow impact never overrides a physically stopped machine", () => {
  // The root machine's own evaluateFlow verdict is "blocked"; it must still
  // render as the physically stopped machine, never "affected by itself".
  const s = machineVisualStates(
    [{ id: "O", status: "stopped" }],
    { O: { state: "blocked", source: "O" } },
    [],
  );
  assert.equal(s.O, "stopped");
});

// ---------------------------------------------------------------------
// Simplified impact choice mapping
// ---------------------------------------------------------------------
test("impact choice maps existing values both ways", () => {
  assert.equal(impactChoice("blocking", "downstream"), "downstream");
  assert.equal(impactChoice("blocking", "whole_line"), "whole_line");
  assert.equal(impactChoice("non_blocking", "downstream"), "none");
  assert.equal(impactChoice("blocking", "none"), "none");
  assert.equal(impactChoice("independent", "downstream"), "none");
});

test("applying a choice never destroys buffer or independent modes", () => {
  // buffer: only impact_scope changes — the mode is preserved for every choice
  for (const choice of ["none", "downstream", "whole_line"]) {
    const applied = applyImpactChoice(choice, {
      dependency_mode: "buffer",
      impact_scope: "downstream",
    });
    assert.equal(applied.dependency_mode, "buffer");
  }
  assert.deepEqual(
    applyImpactChoice("whole_line", { dependency_mode: "buffer" }),
    { dependency_mode: "buffer", impact_scope: "whole_line" },
  );
  // independent is never editable through the simplified UI
  assert.equal(
    applyImpactChoice("downstream", { dependency_mode: "independent" }),
    null,
  );
  // normal machines use the canonical pairs
  assert.deepEqual(
    applyImpactChoice("none", { dependency_mode: "blocking", impact_scope: "downstream" }),
    { dependency_mode: "non_blocking", impact_scope: "none" },
  );
  assert.deepEqual(
    applyImpactChoice("downstream", { dependency_mode: "non_blocking", impact_scope: "none" }),
    { dependency_mode: "blocking", impact_scope: "downstream" },
  );
});

// ---------------------------------------------------------------------
// evaluateFlow-driven stop-impact preview (ONE engine, no duplication)
// ---------------------------------------------------------------------
const previewLine = [
  { id: "U1", status: "running", line_id: "L", position: 0, dependency_mode: "non_blocking" },
  { id: "O", status: "running", line_id: "L", position: 1, dependency_mode: "non_blocking" },
  { id: "D1", status: "running", line_id: "L", position: 2, dependency_mode: "non_blocking" },
  { id: "D2", status: "running", line_id: "L", position: 3, dependency_mode: "non_blocking" },
];

test("previewStopImpact: downstream choice matches evaluateFlow verdicts", () => {
  const { affectedIds } = previewStopImpact(
    previewLine,
    [],
    [],
    "O",
    "blocking",
    "downstream",
  );
  assert.deepEqual([...affectedIds].sort(), ["D1", "D2"]);
});

test("previewStopImpact: whole_line choice affects every peer", () => {
  const { affectedIds } = previewStopImpact(
    previewLine,
    [],
    [],
    "O",
    "blocking",
    "whole_line",
  );
  assert.deepEqual([...affectedIds].sort(), ["D1", "D2", "U1"]);
});

test("previewStopImpact: none choice affects nothing", () => {
  const { affectedIds } = previewStopImpact(
    previewLine,
    [],
    [],
    "O",
    "blocking",
    "none",
  );
  assert.deepEqual(affectedIds, []);
});

test("previewStopImpact keeps using evaluateFlow with an active transfer relief", () => {
  // With a running alternative credited by evaluateFlow, the original is
  // transferred and no downstream machine is affected.
  const stops = [{ work_center_id: "O", started_at: new Date().toISOString(), ended_at: null }];
  const transfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];
  const centers = [
    ...previewLine.map((c) => ({ ...c, dependency_mode: c.id === "O" ? "blocking" : c.dependency_mode, impact_scope: "downstream" })),
    { id: "A", status: "running", line_id: null, position: 0 },
  ];
  const { affectedIds, selfState } = previewStopImpact(
    centers,
    stops,
    transfers,
    "O",
    "blocking",
    "downstream",
  );
  assert.equal(selfState, "transferred");
  assert.deepEqual(affectedIds, []);
});

// ---------------------------------------------------------------------
// Alternative availability
// ---------------------------------------------------------------------
test("alternative availability distinguishes configured/available/unavailable/active", () => {
  const active = ["A1"];
  assert.equal(alternativeAvailability({ id: "A1", status: "running" }, active), "active");
  assert.equal(alternativeAvailability({ id: "A2", status: "idle" }, active), "available");
  assert.equal(
    alternativeAvailability({ id: "A3", status: "idle", order_id: "OTHER" }, active, "O1"),
    "busy",
  );
  assert.equal(alternativeAvailability({ id: "A4", status: "idle", order_id: "O1" }, active, "O1"), "available");
  assert.equal(alternativeAvailability({ id: "A5", status: "stopped" }, active), "stopped");
  assert.equal(alternativeAvailability({ id: "A6", status: "setup" }, active), "setup");
  assert.equal(alternativeAvailability({ id: "A7", status: "running" }, active), "running");
});

// ---------------------------------------------------------------------
// Transfer assignment vs effective production flow (Phase 1 fixes)
// ---------------------------------------------------------------------
// LINE L: O (stopped, open transfer -> A) -> B (stopped too: an UNRELATED
// blocker) -> C. LINE L2: A alone, running. evaluateFlow still credits the
// transfer (A runs and its own route is clear), but the restored route
// rejoins BEFORE B, so production is NOT actually flowing through A.
const blockedRouteLine = [
  { id: "O", status: "stopped", line_id: "L", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "B", status: "stopped", line_id: "L", position: 1, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "C", status: "running", line_id: "L", position: 2, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "A", status: "running", line_id: "L2", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
];
const blockedRouteStops = [
  { work_center_id: "O", started_at: "2026-09-22T06:00:00Z", ended_at: null },
  { work_center_id: "B", started_at: "2026-09-22T06:30:00Z", ended_at: null },
];
const blockedRouteTransfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];
const borrowingLines = [
  { id: "L", name: "Line L" },
  { id: "L2", name: "Line 2" },
];

test("open transfer + unrelated blocked machine: branch visible, line not claiming production", () => {
  const flow = evaluateFlow(blockedRouteLine, blockedRouteStops, blockedRouteTransfers);
  assert.equal(flow.O.state, "transferred"); // the alternative itself is fine...
  assert.equal(flow.C.state, "blocked"); // ...but the route downstream is not
  const branches = transferBranches(blockedRouteLine, flow, blockedRouteTransfers);
  // Assignment state: the branch remains visible and the alternative stays
  // borrowed (its home line keeps the assigned-away placeholder).
  assert.equal(branches.length, 1);
  assert.equal(String(branches[0].original.id), "O");
  assert.equal(String(branches[0].alternative.id), "A");
  assert.equal(
    String(borrowingLineOf({ id: "A", line_id: "L2" }, branches, borrowingLines)?.id),
    "L",
  );
  // Effective flow: NOT restored — no "Running via alternative", no
  // successful alternative styling, the line shows its real condition.
  assert.equal(branches[0].state, "routeBlocked");
  const s = machineVisualStates(blockedRouteLine, flow, blockedRouteTransfers);
  assert.equal(s.A, "affected");
  assert.equal(s.O, "stopped");
  assert.equal(lineVisualStatus(["O", "B", "C"], s, branches), "affected");
  assert.notEqual(
    lineVisualStatus(["O", "B", "C"], s, branches),
    "runningViaAlternative",
  );
});

// Same line, but now the ALTERNATIVE itself has been stopped while the
// transfer row is still open.
const stoppedAltLine = [
  { id: "O", status: "stopped", line_id: "L", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "B", status: "running", line_id: "L", position: 1, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "A", status: "stopped", line_id: "L2", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
];
const stoppedAltStops = [
  { work_center_id: "O", started_at: "2026-09-22T06:00:00Z", ended_at: null },
];
const stoppedAltTransfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];

test("open transfer whose alternative stops: assignment persists, no success styling", () => {
  const flow = evaluateFlow(stoppedAltLine, stoppedAltStops, stoppedAltTransfers);
  assert.equal(flow.O.state, "blocked"); // no longer credited
  assert.equal(flow.B.state, "blocked"); // the stop blocks the line again
  const branches = transferBranches(stoppedAltLine, flow, stoppedAltTransfers);
  // Branch + borrowing persist until the transfer row actually ends — the
  // machine must not visually return home while the row is open.
  assert.equal(branches.length, 1);
  assert.equal(branches[0].state, "alternativeStopped");
  assert.equal(
    String(borrowingLineOf({ id: "A", line_id: "L2" }, branches, borrowingLines)?.id),
    "L",
  );
  const s = machineVisualStates(stoppedAltLine, flow, stoppedAltTransfers);
  assert.equal(s.A, "stopped"); // physical stopped styling, never success
  assert.equal(s.O, "stopped");
  assert.equal(s.B, "affected");
  assert.equal(lineVisualStatus(["O", "B"], s, branches), "affected");
  assert.notEqual(
    lineVisualStatus(["O", "B"], s, branches),
    "runningViaAlternative",
  );
});

// The line-status bug: an unrelated UPSTREAM machine still running must not
// make the line claim "running" while its own transfer branch is blocked.
// U -> O -> B -> C, with O stopped under an OPEN transfer to A (running), and
// B stopped downstream of the rejoin — so the restored route is blocked.
const upstreamRunningLine = [
  { id: "U", status: "running", line_id: "L", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "O", status: "stopped", line_id: "L", position: 1, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "B", status: "stopped", line_id: "L", position: 2, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "C", status: "running", line_id: "L", position: 3, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  { id: "A", status: "running", line_id: "L2", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
];
const upstreamRunningStops = [
  { work_center_id: "O", started_at: "2026-09-23T06:00:00Z", ended_at: null },
  { work_center_id: "B", started_at: "2026-09-23T06:30:00Z", ended_at: null },
];
const upstreamRunningTransfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];

test("blocked transfer branch outranks an unrelated upstream running machine", () => {
  const flow = evaluateFlow(upstreamRunningLine, upstreamRunningStops, upstreamRunningTransfers);
  assert.equal(flow.O.state, "transferred"); // the alternative itself is fine...
  assert.equal(flow.B.state, "blocked"); // ...but the restored route is blocked
  assert.equal(flow.C.state, "blocked");
  const branches = transferBranches(upstreamRunningLine, flow, upstreamRunningTransfers);
  // Assignment state: branch stays visible, alternative stays borrowed away.
  assert.equal(branches.length, 1);
  assert.equal(branches[0].state, "routeBlocked");
  assert.equal(
    String(borrowingLineOf({ id: "A", line_id: "L2" }, branches, borrowingLines)?.id),
    "L",
  );
  const s = machineVisualStates(upstreamRunningLine, flow, upstreamRunningTransfers);
  assert.equal(s.A, "affected"); // no successful alternative styling
  // Line status: the blocked branch outranks the running upstream machine.
  const status = lineVisualStatus(["U", "O", "B", "C"], s, branches);
  assert.notEqual(status, "running");
  assert.notEqual(status, "runningViaAlternative");
  assert.equal(status, "affected");
});

test("non-blocking original with an open transfer and clear route flows", () => {
  const centers = [
    { id: "O", status: "stopped", line_id: "L", position: 0, dependency_mode: "non_blocking", impact_scope: "none", buffer_minutes: 0 },
    { id: "A", status: "running", line_id: "L2", position: 0, dependency_mode: "non_blocking", impact_scope: "none", buffer_minutes: 0 },
  ];
  const transfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];
  const flow = evaluateFlow(centers, [], transfers);
  assert.equal(flow.O.state, "clear");
  const branches = transferBranches(centers, flow, transfers);
  assert.equal(branches.length, 1);
  assert.equal(branches[0].state, "flowing");
  const states = machineVisualStates(centers, flow, transfers);
  assert.equal(states.A, "alternative");
  assert.equal(lineVisualStatus(["O"], states, branches), "runningViaAlternative");
});

test("successful cross-line transfer leaves only a non-flowing home placeholder", () => {
  const centers = [
    { id: "O", status: "stopped", line_id: "L", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
    { id: "A", status: "running", line_id: "L2", position: 0, dependency_mode: "blocking", impact_scope: "downstream", buffer_minutes: 0 },
  ];
  const transfers = [{ original_id: "O", alternative_id: "A", ended_at: null }];
  const flow = evaluateFlow(centers, [{ work_center_id: "O", started_at: "2026-09-23T06:00:00Z", ended_at: null }], transfers);
  const branches = transferBranches(centers, flow, transfers);
  const states = machineVisualStates(centers, flow, transfers);
  const home = centers[1];
  const borrowedAwayIds = borrowingLineOf(home, branches, borrowingLines) ? ["A"] : [];
  assert.deepEqual(borrowedAwayIds, ["A"]); // home placeholder remains assigned away
  assert.equal(lineVisualStatus(["A"], states, branches, borrowedAwayIds), "idle");
  assert.equal(
    connectorFlowing({ id: "H" }, home, { ...states, H: "running" }, { ...flow, H: { state: "clear" } }, borrowedAwayIds),
    false,
  );
  assert.equal(branches[0].state, "flowing");
  assert.equal(states.A, "alternative");
  assert.equal(lineVisualStatus(["O"], states, branches), "runningViaAlternative");
});

function borrowedHomeFixture(dependency_mode = "blocking", impact_scope = "whole_line") {
  const centers = [
    { id: "H0", line_id: "HOME", position: 0, status: "running", dependency_mode: "blocking", impact_scope: "downstream" },
    { id: "A1", line_id: "HOME", position: 1, status: "running", dependency_mode, impact_scope },
    { id: "H2", line_id: "HOME", position: 2, status: "running", dependency_mode: "blocking", impact_scope: "downstream" },
    { id: "B1", line_id: "BORROWER", position: 0, status: "stopped", dependency_mode: "blocking", impact_scope: "whole_line" },
    { id: "B2", line_id: "BORROWER", position: 1, status: "running", dependency_mode: "blocking", impact_scope: "downstream" },
  ];
  const stops = [{ work_center_id: "B1", started_at: "2026-09-24T08:00:00Z", ended_at: null }];
  const transfers = [{ original_id: "B1", alternative_id: "A1", created_at: "2026-09-24T08:10:00Z", ended_at: null }];
  return { centers, stops, transfers };
}

test("resumed home line is blocked by a whole-line machine borrowed elsewhere", () => {
  const { centers, stops, transfers } = borrowedHomeFixture();
  const flow = evaluateFlow(centers, stops, transfers);
  const branches = transferBranches(centers, flow, transfers);
  const states = machineVisualStates(centers, flow, transfers);
  assert.equal(centers[1].status, "running");
  assert.equal(centers[1].line_id, "HOME");
  assert.equal(flow.A1.homeState, "blocked");
  assert.equal(flow.A1.state, "clear");
  assert.equal(flow.H0.state, "blocked");
  assert.equal(flow.H2.state, "blocked");
  assert.equal(states.H0, "affected");
  assert.equal(states.H2, "affected");
  assert.equal(lineOperationalStatus(lineVisualStatus(["H0", "A1", "H2"], states, branches, ["A1"], flow), null), "affected");
  assert.equal(connectorFlowing(centers[0], centers[1], states, flow, ["A1"]), false);
  assert.equal(connectorFlowing(centers[1], centers[2], states, flow, ["A1"]), false);
  assert.equal(branches[0].state, "flowing");
  assert.equal(states.A1, "alternative");
  assert.equal(flow.B1.state, "transferred");
  assert.equal(flow.B2.state, "clear");
  assert.equal(lineVisualStatus(["B1", "B2"], states, branches), "runningViaAlternative");
  assert.equal(borrowingLineOf(centers[1], branches, [{ id: "HOME" }, { id: "BORROWER" }])?.id, "BORROWER");
});

test("borrowed-away downstream impact leaves upstream flow clear", () => {
  const { centers, stops, transfers } = borrowedHomeFixture("blocking", "downstream");
  const flow = evaluateFlow(centers, stops, transfers);
  const states = machineVisualStates(centers, flow, transfers);
  assert.equal(flow.H0.state, "clear");
  assert.equal(flow.H2.state, "blocked");
  assert.equal(flow.A1.homeState, "blocked");
  assert.equal(lineVisualStatus(["H0", "A1", "H2"], states, transferBranches(centers, flow, transfers), ["A1"], flow), "affected");
});

test("borrowed-away non-blocking machine does not block unrelated home production", () => {
  for (const [mode, scope] of [["non_blocking", "none"], ["blocking", "none"], ["independent", "whole_line"]]) {
    const { centers, stops, transfers } = borrowedHomeFixture(mode, scope);
    const flow = evaluateFlow(centers, stops, transfers);
    const branches = transferBranches(centers, flow, transfers);
    const states = machineVisualStates(centers, flow, transfers);
    assert.equal(flow.H0.state, "clear");
    assert.equal(flow.H2.state, "clear");
    assert.equal(flow.A1.homeState, undefined);
    assert.equal(lineVisualStatus(["H0", "A1", "H2"], states, branches, ["A1"], flow), "running");
    assert.equal(connectorFlowing(centers[0], centers[1], states, flow, ["A1"]), false);
    assert.equal(branches[0].state, "flowing");
  }
});

test("borrowed-away buffer delays its configured home-line impact", () => {
  const { centers, stops, transfers } = borrowedHomeFixture("buffer", "whole_line");
  centers[1].buffer_minutes = 30;
  const before = evaluateFlow(centers, stops, transfers, Date.parse("2026-09-24T08:20:00Z"));
  assert.equal(before.A1.homeState, "bufferActive");
  assert.equal(before.H0.state, "clear");
  const after = evaluateFlow(centers, stops, transfers, Date.parse("2026-09-24T08:40:00Z"));
  assert.equal(after.A1.homeState, "blocked");
  assert.equal(after.H0.state, "blocked");
  assert.equal(after.A1.state, "clear");
});

test("ending the transfer restores the machine to its unchanged home route", () => {
  const { centers, stops, transfers } = borrowedHomeFixture();
  transfers[0].ended_at = "2026-09-24T09:00:00Z";
  const flow = evaluateFlow(centers, stops, transfers);
  const branches = transferBranches(centers, flow, transfers);
  const states = machineVisualStates(centers, flow, transfers);
  assert.equal(flow.A1.homeState, undefined);
  assert.equal(flow.H0.state, "clear");
  assert.equal(flow.H2.state, "clear");
  assert.equal(centers[1].line_id, "HOME");
  assert.equal(states.A1, "running");
  assert.equal(lineVisualStatus(["H0", "A1", "H2"], states, branches, [], flow), "running");
  assert.equal(connectorFlowing(centers[0], centers[1], states, flow), true);
  assert.equal(branches.length, 0);
});

test("returned machine does not mask another home-line blocker", () => {
  const { centers, stops, transfers } = borrowedHomeFixture();
  centers[2].status = "stopped";
  centers[2].impact_scope = "whole_line";
  stops.push({ work_center_id: "H2", started_at: "2026-09-24T08:30:00Z", ended_at: null });
  transfers[0].ended_at = "2026-09-24T09:00:00Z";
  stops[0].ended_at = "2026-09-24T09:00:00Z";
  centers[3].status = "running";
  const flow = evaluateFlow(centers, stops, transfers);
  const branches = transferBranches(centers, flow, transfers);
  const states = machineVisualStates(centers, flow, transfers);
  assert.equal(centers[1].status, "running");
  assert.equal(centers[1].line_id, "HOME");
  assert.equal(flow.A1.homeState, undefined);
  assert.equal(flow.A1.state, "blocked");
  assert.equal(states.A1, "affected");
  assert.equal(lineVisualStatus(["H0", "A1", "H2"], states, branches, [], flow), "affected");
  assert.equal(branches.length, 0);
});
