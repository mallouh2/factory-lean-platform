import test from "node:test";
import assert from "node:assert/strict";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };
import { executionTiming, lineExecutionQueue } from "../src/utils/execution-queue.mjs";
import { requestStatus } from "../src/utils/order-overview.mjs";

const first = { id: "a", line_id: "line", status: "planned",
  start_time: "2026-09-28T08:00:00Z", expected_finish: "2026-09-28T10:00:00Z",
  actual_start: null, actual_finish: null };
const second = { ...first, id: "b", start_time: "2026-09-28T10:00:00Z",
  expected_finish: "2026-09-28T12:00:00Z" };

test("first persisted plan is ready even before its planned start", () => {
  const items = [second, first];
  assert.equal(lineExecutionQueue(items, "line").readyId, "a");
  assert.equal(lineExecutionQueue(items, "line").next.id, "b");
  assert.deepEqual(items, [second, first]);
});

test("only a strictly positive planned interval can be ready", () => {
  assert.equal(lineExecutionQueue([first], "line").readyId, "a");
  const zero = { ...first, expected_finish: first.start_time };
  const negative = { ...first, expected_finish: "2026-09-28T07:59:00Z" };
  assert.equal(lineExecutionQueue([zero, second], "line").readyId, "b");
  assert.equal(lineExecutionQueue([negative, second], "line").readyId, "b");
  assert.equal(lineExecutionQueue([zero, negative], "line").readyId, null);
});

test("active item remains current and the next plan waits; finish advances the queue", () => {
  const running = { ...first, status: "active", actual_start: "2026-09-28T07:30:00Z" };
  assert.equal(lineExecutionQueue([second, running], "line").current.id, "a");
  assert.equal(lineExecutionQueue([second, running], "line").next.id, "b");
  assert.equal(lineExecutionQueue([second, running], "line").readyId, null);
  const finished = { ...running, status: "completed", actual_finish: "2026-09-28T09:00:00Z" };
  assert.equal(lineExecutionQueue([second, finished], "line").readyId, "b");
  assert.equal(requestStatus([finished, second]), "active");
  assert.equal(requestStatus([finished, { ...second, status: "completed" }]), "completed");
});

test("legacy active item without a complete plan still blocks the ready queue", () => {
  const legacy = { ...first, status: "active", start_time: null, expected_finish: null };
  const queue = lineExecutionQueue([second, legacy], "line");
  assert.equal(queue.current.id, "a");
  assert.equal(queue.next.id, "b");
  assert.equal(queue.readyId, null);
});

test("plan versus actual and delay remain derived without changing plan", () => {
  const running = { ...first, status: "active", actual_start: "2026-09-28T07:30:00Z" };
  assert.equal(executionTiming(running, Date.parse("2026-09-28T10:42:00Z")).startVarianceMinutes, -30);
  assert.equal(executionTiming(running, Date.parse("2026-09-28T10:42:00Z")).overdueMinutes, 42);
  assert.equal(executionTiming({ ...running, actual_finish: "2026-09-28T09:00:00Z" }).finishVarianceMinutes, -60);
  assert.equal(running.start_time, first.start_time);
  assert.equal(running.expected_finish, first.expected_finish);
});

test("execution labels exist in English and Arabic", () => {
  for (const key of ["productionQueue", "executionReady", "executionInProduction", "executionWaiting",
    "startProduction", "finishProduction", "executionActualStart", "executionActualFinish",
    "executionStartVariance", "executionFinishVariance"]) {
    assert.ok(en[key], key);
    assert.ok(ar[key], key);
  }
});
