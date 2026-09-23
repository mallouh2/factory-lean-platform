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
  transferBranches,
  borrowingLineOf,
} from "../src/utils/floor-visual.mjs";
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
