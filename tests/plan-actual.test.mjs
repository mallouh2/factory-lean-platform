import test from "node:test";
import assert from "node:assert/strict";
import { fitPlanActualScale, planActualEvidence, planActualLayout, planActualTracks, timestampInWindow } from "../src/utils/plan-actual.mjs";

const at = minute => new Date(Date.UTC(2026, 10, 20, 8, minute)).toISOString();
const approved = { revision_no: 1, event: "initial", after_line_id: "A", after_start: at(0), after_finish: at(60) };
const order = { line_id: "A", start_time: at(0), expected_finish: at(60), actual_start: at(0), actual_finish: at(60) };
const run = (id, line_id, from, to, state = "FINISHED", reason = null) =>
  ({ id, line_id, started_at: at(from), ended_at: to == null ? null : at(to), state, reason });

test("on-time approved work maps to the same coordinates on both tracks without changing the plan", () => {
  const saved = structuredClone(order);
  const result = planActualEvidence(order, [approved], [run("run", "A", 0, 60)], 0, at(60));
  assert.deepEqual([result.startDelta, result.finishDelta, result.elapsedDelta], [0, 0, 0]);
  const layout = planActualLayout(result.segments, at(-30), at(90), 760);
  assert.deepEqual(layout.jobs.map(row => [row.left, row.width]), [[25, 50], [25, 50]]);
  assert.deepEqual(order, saved);
});

test("late actual start and finish are measured against the selected approved schedule", () => {
  const result = planActualEvidence({ ...order, actual_start: at(7), actual_finish: at(72) },
    [approved], [run("a", "A", 7, 72)], 0, at(90));
  assert.deepEqual([result.startDelta, result.finishDelta, result.elapsedDelta], [420000, 720000, 300000]);
});

test("explicit interruption and resumption leave an execution gap and retain the reason", () => {
  const runs = [run("a", "A", 0, 12, "INTERRUPTED", "Material check"), run("b", "A", 28, 60)];
  const result = planActualEvidence(order, [approved], runs.reverse(), 0, at(75));
  assert.deepEqual(result.runs.map(item => [item.start, item.finish]), [[at(0), at(12)], [at(28), at(60)]]);
  assert.equal(result.runs[0].run.reason, "Material check");
});

test("revision selection retains the original plan and records unscheduling separately", () => {
  const revised = { ...approved, revision_no: 2, event: "replanned", after_line_id: "B", after_start: at(20), after_finish: at(80) };
  const removed = { revision_no: 3, event: "unscheduled", before_line_id: "B", before_start: at(20), before_finish: at(80) };
  const revisions = [removed, revised, approved];
  const result = planActualEvidence(order, revisions, [], 2, at(90));
  assert.equal(result.original.line, "A");
  assert.equal(result.selected.line, "B");
  assert.equal(result.startDelta, -1200000);
  assert.equal(planActualEvidence(order, revisions, [], 0, at(90)).selected, null);
});

test("transfer uses actual physical line and open runs end at the report time only", () => {
  const history = [run("old", "A", 0, 10, "INTERRUPTED"), run("open", "B", 10, null, "ACTIVE"),
    run("armed", "C", 12, null, "ARMED")];
  const result = planActualEvidence({ ...order, actual_finish: null }, [approved], history, 0, at(40));
  assert.deepEqual(result.runs.map(item => [item.line, item.finish, Boolean(item.open)]),
    [["A", at(10), false], ["B", at(40), true]]);
  assert.equal(result.original.line, "A");
  assert.equal(result.finishDelta, null);
  const visible = planActualLayout(result.runs, at(5), at(25), 760);
  assert.deepEqual(visible.jobs.map(row => [row.left, row.width]), [[0, 25], [25, 75]]);
});

test("legacy order bounds remain point evidence, including without an actual line", () => {
  const result = planActualEvidence(order, [approved], [], 0, at(60));
  assert.equal(result.runs.length, 0);
  assert.deepEqual(result.unmatchedBounds.map(point => point.start), [at(0), at(60)]);
  assert.equal(timestampInWindow(at(60), at(0), at(60)), false);
});

test("a current schedule or legacy baseline never stands in for an original approval", () => {
  const actual = [run("a", "A", 0, 60)];
  const missing = planActualEvidence(order, [], actual, 0, at(60));
  assert.deepEqual(missing.segments.map(segment => segment.kind), ["actual"]);
  const baseline = planActualEvidence(order, [{ ...approved, event: "baseline" }], actual, 0, at(60));
  assert.equal(baseline.original, null);
  assert.equal(baseline.startDelta, null);
  assert.deepEqual(baseline.segments.map(segment => segment.kind), ["baseline", "actual"]);
  const laterInitial = planActualEvidence(order, [{ ...approved, revision_no: 3 }], actual, 0, at(60));
  assert.equal(laterInitial.original, null);
});

test("shared scale fits short recorded intervals without stretching or leaving the requested range", () => {
  const evidence = planActualEvidence(order, [approved], [run("x", "A", 40, 41)], 0, at(90));
  const scope = fitPlanActualScale(evidence.segments, [], at(-1440), at(1440));
  assert.deepEqual(scope, { from: at(-15), to: at(75) });
  const result = planActualLayout(evidence.runs, scope.from, scope.to, 760);
  assert.equal(result.jobs[0].width, 100/90);
  assert.deepEqual(fitPlanActualScale(evidence.runs, [], at(40), at(41)), { from: at(40), to: at(41) });
});

test("multi-order comparison changes one plan per order and keeps the actual timeline fixed", () => {
  const revised = { ...approved, revision_no: 2, event: "replanned", after_start: at(20), after_finish: at(80) };
  const later = { ...approved, after_start: at(80), after_finish: at(100) };
  const entry = { order, plan: [approved, revised], history: [run("source", "A", 20, 30, "INTERRUPTED"),
    run("destination", "B", 40, 80)] };
  const nextOrder = { order: {}, plan: [later], history: [] };
  const shared = mode => [entry, nextOrder].map(item => planActualTracks(item, mode, at(100)));
  const [original, nextOriginal] = shared("original");
  const [latest, nextLatest] = shared("latest");
  assert.equal(original.chartPlan.start, at(0));
  assert.equal(latest.chartPlan.start, at(20));
  assert.deepEqual(nextOriginal.chartPlan.start, nextLatest.chartPlan.start);
  assert.deepEqual(original.runs, latest.runs);
  assert.deepEqual(planActualLayout([latest.chartPlan, nextLatest.chartPlan], at(0), at(100), 1000)
    .jobs.map(job => [job.left, job.width, job.track]), [[20, 60, 0], [80, 20, 0]]);
  assert.deepEqual(planActualLayout(latest.runs, at(0), at(100), 1000)
    .jobs.map(job => [job.left, job.width]), [[20, 10], [40, 40]]);
});

test("comparison modes withhold legacy baselines and preserve future or unscheduled states", () => {
  const baseline = { ...approved, event: "baseline" };
  const removal = { revision_no: 2, event: "unscheduled" };
  for (const mode of ["original", "latest"]) {
    assert.equal(planActualTracks({ order, plan: [baseline], history: [] }, mode, at(90)).chartPlan, null);
    assert.equal(planActualTracks({ order: {}, plan: [approved], history: [] }, mode, at(-1)).runs.length, 0);
  }
  assert.equal(planActualTracks({ order, plan: [approved, removal], history: [] }, "latest", at(90)).chartPlan, null);
});
