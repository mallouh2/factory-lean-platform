import test from "node:test";
import assert from "node:assert/strict";
import { calculateProductionLoss, suggestScrapCalibration } from
  "../src/utils/production-loss-impact.mjs";

const at = (minute) => new Date(Date.UTC(2026, 8, 29, 10, minute)).toISOString();
const center = (overrides = {}) => ({
  id: "machine", line_id: "line", name: "Extruder 01", status: "stopped",
  dependency_mode: "blocking", impact_scope: "whole_line",
  buffer_minutes: 0, position: 1, archived: false, ...overrides,
});
const order = (start = at(0), end = at(60), overrides = {}) => ({
  id: "order", product_id: "product", line_id: "line", status: "planned",
  start_time: start, expected_finish: end, ...overrides,
});
const context = (overrides = {}) => ({
  centers: [center()],
  stops: [{ id: "event", work_center_id: "machine", started_at: at(0), ended_at: null }],
  transfers: [], orders: [order()],
  products: [{ id: "product", name: "Pipe", unit: "meter" }],
  capabilities: [{ work_center_id: "machine", product_id: "product",
    rate: 500, rate_unit: "meter" }],
  profiles: [{ work_center_id: "machine", product_id: "product",
    scrap_expected: false, can_defer: false }],
  recovery_rates: [], alternatives: [], lines: [{ id: "line" }],
  ...overrides,
});
const event = (end = at(30), overrides = {}) => ({
  id: "event", work_center_id: "machine", line_id: "line",
  started_at: at(0), ended_at: end, stop_nature: "unplanned", ...overrides,
});
const sample = (when, state, id = 1) => ({
  id, event_id: "event", captured_at: when, context: state,
});
const calculate = (e, samples) => calculateProductionLoss(e, samples);

test("planned cleaning between orders has physical stop but no production loss", () => {
  const e = event(at(25), { stop_nature: "planned" });
  const result = calculate(e, [sample(at(0), context({ orders: [order(at(30), at(60))] }))]);
  assert.equal(result.raw_stop_minutes, 25);
  assert.equal(result.effective_loss_minutes, 0);
  assert.equal(result.non_production_minutes, 25);
  assert.equal(result.readiness, "NOT_APPLICABLE");
  assert.equal(result.impact_level, 0);
});

test("planned cleaning overrun counts only Planning overlap", () => {
  const e = event(at(45), { stop_nature: "planned" });
  const result = calculate(e, [sample(at(0), context({ orders: [order(at(30), at(60))] }))]);
  assert.equal(result.raw_stop_minutes, 45);
  assert.equal(result.non_production_minutes, 30);
  assert.equal(result.effective_loss_minutes, 15);
  assert.equal(result.estimated_lost_output_quantity, 125);
  assert.equal(result.impact_level, 4);
});

test("planned maintenance with no production demand has no output loss", () => {
  const result = calculate(event(at(30), { stop_nature: "planned",
    planned_activity: "preventive_maintenance" }),
  [sample(at(0), context({ orders: [] }))]);
  assert.equal(result.impact_level, 0);
  assert.equal(result.effective_loss_minutes, 0);
  assert.equal(result.readiness, "NOT_APPLICABLE");
});

test("unplanned failure starting during idle counts only its production overlap", () => {
  const result = calculate(event(at(30)), [sample(at(0),
    context({ orders: [order(at(10), at(60))] }))]);
  assert.equal(result.non_production_minutes, 10);
  assert.equal(result.effective_loss_minutes, 20);
});

test("standby stop for 48 hours remains level zero without planned demand", () => {
  const start = new Date(Date.UTC(2026, 8, 27, 10)).toISOString();
  const e = event(at(0), { started_at: start });
  const result = calculate(e, [sample(start, context({ orders: [] }))]);
  assert.equal(result.raw_stop_minutes, 2880);
  assert.equal(result.impact_level, 0);
  assert.equal(result.estimated_lost_output_quantity, 0);
});

test("unplanned failure repaired during idle has zero production loss", () => {
  const result = calculate(event(at(25)), [sample(at(0),
    context({ orders: [order(at(30), at(60))] }))]);
  assert.equal(result.effective_loss_minutes, 0);
  assert.equal(result.stop_nature, "unplanned");
});

test("full stop uses product capability rate", () => {
  const result = calculate(event(at(12)), [sample(at(0), context())]);
  assert.equal(result.effective_loss_minutes, 12);
  assert.equal(result.estimated_lost_output_quantity, 100);
  assert.equal(result.unit, "meter");
  assert.equal(result.impact_level, 4);
  assert.equal(result.readiness, "READY");
});

test("cooling line blocker is full impact according to evaluateFlow", () => {
  const e = event(at(30), { work_center_id: "cooling" });
  const state = context({
    centers: [center({ id: "cooling", name: "Cooling", position: 2 })],
    stops: [{ id: "event", work_center_id: "cooling",
      started_at: at(0), ended_at: null }],
    capabilities: [{ work_center_id: "cooling", product_id: "product",
      rate: 500, rate_unit: "meter" }],
    profiles: [{ work_center_id: "cooling", product_id: "product",
      scrap_expected: false }],
  });
  assert.equal(calculate(e, [sample(at(0), state)]).impact_level, 4);
});

test("configured alternative without an open transfer gives no mitigation", () => {
  const result = calculate(event(at(30)), [sample(at(0), context({
    centers: [center(), center({ id: "alternative", line_id: null, status: "idle" })],
    alternatives: [{ work_center_id: "machine", alternative_id: "alternative" }],
  }))]);
  assert.equal(result.effective_loss_minutes, 30);
  assert.deepEqual(result.mitigation, []);
});

test("actual equal capacity transfer begins mitigation at its timestamp", () => {
  const initial = context();
  const mitigated = context({
    centers: [center(), center({ id: "alternative", line_id: null, status: "running" })],
    transfers: [{ original_id: "machine", alternative_id: "alternative",
      created_at: at(12), ended_at: null }],
    capabilities: [...initial.capabilities,
      { work_center_id: "alternative", product_id: "product", rate: 500, rate_unit: "meter" }],
  });
  const result = calculate(event(at(60)), [
    sample(at(0), initial), sample(at(12), mitigated, 2),
  ]);
  assert.equal(result.raw_stop_minutes, 60);
  assert.equal(result.effective_loss_minutes, 12);
  assert.equal(result.estimated_lost_output_quantity, 100);
  assert.deepEqual(result.mitigation, ["active_transfer"]);
});

test("slower alternative produces partial throughput loss", () => {
  const initial = context();
  const mitigated = context({
    centers: [center(), center({ id: "alternative", line_id: null, status: "running" })],
    transfers: [{ original_id: "machine", alternative_id: "alternative",
      created_at: at(12), ended_at: null }],
    capabilities: [...initial.capabilities,
      { work_center_id: "alternative", product_id: "product", rate: 300, rate_unit: "meter" }],
  });
  const result = calculate(event(at(42)), [
    sample(at(0), initial), sample(at(12), mitigated, 2),
  ]);
  assert.equal(result.effective_loss_minutes, 24);
  assert.equal(result.estimated_lost_output_quantity, 200);
  assert.equal(result.impact_level, 4);
});

test("borrowed alternative stopping does not end its transfer and restores full impact", () => {
  const initial = context();
  const transfer = { original_id: "machine", alternative_id: "alternative",
    created_at: at(12), ended_at: null };
  const active = context({
    centers: [center(), center({ id: "alternative", line_id: null, status: "running" })],
    transfers: [transfer],
    capabilities: [...initial.capabilities,
      { work_center_id: "alternative", product_id: "product", rate: 500, rate_unit: "meter" }],
  });
  const alternativeStopped = context({
    ...active, centers: [center(), center({ id: "alternative", line_id: null, status: "stopped" })],
    stops: [...initial.stops, { id: "other", work_center_id: "alternative",
      started_at: at(30), ended_at: null }],
  });
  const result = calculate(event(at(60)), [
    sample(at(0), initial), sample(at(12), active, 2),
    sample(at(30), alternativeStopped, 3),
  ]);
  assert.equal(result.effective_loss_minutes, 42);
  assert.equal(alternativeStopped.transfers[0].ended_at, null);
});

test("buffer expiry splits protected and lost intervals", () => {
  const result = calculate(event(at(30)), [sample(at(0), context({
    centers: [center({ dependency_mode: "buffer", buffer_minutes: 20 })],
  }))]);
  assert.equal(result.effective_loss_minutes, 10);
  assert.deepEqual(result.mitigation, ["buffer"]);
});

test("independent deferred process creates recovery workload, not scrap or permanent loss", () => {
  const result = calculate(event(at(30)), [sample(at(0), context({
    centers: [center({ dependency_mode: "independent" })],
    profiles: [{ work_center_id: "machine", product_id: "product",
      scrap_expected: false, can_defer: true }],
    recovery_rates: [{ work_center_id: "machine", product_id: "product",
      rate: 1000, unit: "meter" }],
  }))]);
  assert.equal(result.impact_level, 2);
  assert.equal(result.effective_loss_minutes, 0);
  assert.equal(result.deferred_quantity, 250);
  assert.equal(result.estimated_recovery_minutes, 15);
  assert.equal(result.estimated_total_scrap, 0);
});

test("deferred process without recovery capacity is incomplete with a named gap", () => {
  const result = calculate(event(at(30)), [sample(at(0), context({
    centers: [center({ dependency_mode: "independent" })],
    profiles: [{ work_center_id: "machine", product_id: "product",
      scrap_expected: false, can_defer: true }],
  }))]);
  assert.equal(result.readiness, "INCOMPLETE");
  assert.match(result.missing.join(" "), /Recovery capacity.*Extruder 01.*Pipe/);
  assert.equal(result.estimated_recovery_minutes, null);
});

test("unknown buffer coverage is a data gap rather than fabricated protection", () => {
  const result = calculate(event(at(30)), [sample(at(0), context({
    centers: [center({ dependency_mode: "buffer", buffer_minutes: null })],
  }))]);
  assert.equal(result.readiness, "INCOMPLETE");
  assert.equal(result.effective_loss_minutes, null);
});

test("missing product rate is a specific incomplete data gap", () => {
  const result = calculate(event(at(30)), [sample(at(0),
    context({ capabilities: [] }))]);
  assert.equal(result.readiness, "INCOMPLETE");
  assert.match(result.missing[0], /Production rate.*Extruder 01.*Pipe/);
  assert.equal(result.estimated_lost_output_quantity, null);
});

test("legacy event without captured context never claims impact level zero", () => {
  const result = calculate(event(at(30), { stop_nature: "legacy_unknown" }), []);
  assert.equal(result.readiness, "INCOMPLETE");
  assert.equal(result.impact_level, null);
  assert.equal(result.effective_loss_minutes, null);
});

test("downstream blocked machines do not duplicate an upstream causal loss", () => {
  const first = event(at(30));
  const downstream = event(at(30), { id: "downstream-event",
    work_center_id: "downstream" });
  const state = context({
    centers: [center(), center({ id: "downstream", name: "Cooling",
      position: 2, status: "stopped" })],
    stops: [
      { id: "event", work_center_id: "machine", started_at: at(0), ended_at: null },
      { id: "downstream-event", work_center_id: "downstream",
        started_at: at(0), ended_at: null },
    ],
    capabilities: [
      { work_center_id: "machine", product_id: "product", rate: 500, rate_unit: "meter" },
      { work_center_id: "downstream", product_id: "product", rate: 500,
        rate_unit: "meter" },
    ],
    profiles: [
      { work_center_id: "machine", product_id: "product", scrap_expected: false },
      { work_center_id: "downstream", product_id: "product", scrap_expected: false },
    ],
  });
  const upstream = calculate(first, [sample(at(0), state)]);
  const second = calculate(downstream, [{ ...sample(at(0), state),
    event_id: "downstream-event" }]);
  assert.equal(upstream.estimated_lost_output_quantity, 250);
  assert.equal(second.estimated_lost_output_quantity, 0);
});

test("historical snapshot is stable when live configuration changes", () => {
  const e = event(at(30));
  const saved = [sample(at(0), context())];
  const before = calculate(e, saved);
  const changed = context({ capabilities: [{ work_center_id: "machine",
    product_id: "product", rate: 900, rate_unit: "meter" }] });
  assert.equal(calculate(e, saved).estimated_lost_output_quantity,
    before.estimated_lost_output_quantity);
  assert.equal(calculate(e, [sample(at(0), changed)]).estimated_lost_output_quantity, 450);
});

test("scrap configured later in a stop does not fill an earlier missing assumption", () => {
  const initial = context({ profiles: [] });
  const configured = context({ profiles: [{ work_center_id: "machine",
    product_id: "product", scrap_expected: true,
    shutdown_scrap_quantity: 20, restart_scrap_quantity: 35, scrap_unit: "kg" }] });
  const result = calculate(event(at(30)), [
    sample(at(0), initial), sample(at(10), configured, 2),
  ]);
  assert.equal(result.readiness, "INCOMPLETE");
  assert.equal(result.estimated_total_scrap, null);
  assert.match(result.missing.join(" "), /scrap expectation/);
});

test("different planned output units in one stop never produce an aggregate quantity", () => {
  const state = context({
    orders: [order(at(0), at(15)), order(at(15), at(30), {
      id: "other", product_id: "other-product",
    })],
    products: [{ id: "product", name: "Pipe", unit: "meter" },
      { id: "other-product", name: "Fitting", unit: "piece" }],
    capabilities: [
      { work_center_id: "machine", product_id: "product", rate: 500,
        rate_unit: "meter" },
      { work_center_id: "machine", product_id: "other-product", rate: 20,
        rate_unit: "piece" },
    ],
    profiles: [{ work_center_id: "machine", product_id: "product",
      scrap_expected: false }, { work_center_id: "machine",
      product_id: "other-product", scrap_expected: false }],
  });
  const result = calculate(event(at(30)), [sample(at(0), state)]);
  assert.equal(result.readiness, "INCOMPLETE");
  assert.equal(result.estimated_lost_output_quantity, null);
  assert.match(result.missing.join(" "), /Multiple planned output units/);
});

test("planned stop with active equal capacity alternative is not a production problem", () => {
  const initial = context({
    centers: [center(), center({ id: "alternative", line_id: null, status: "running" })],
    transfers: [{ original_id: "machine", alternative_id: "alternative",
      created_at: at(0), ended_at: null }],
    capabilities: [
      { work_center_id: "machine", product_id: "product", rate: 500, rate_unit: "meter" },
      { work_center_id: "alternative", product_id: "product", rate: 500,
        rate_unit: "meter" },
    ],
  });
  const result = calculate(event(at(30), { stop_nature: "planned",
    planned_activity: "preventive_maintenance" }), [sample(at(0), initial)]);
  assert.equal(result.effective_loss_minutes, 0);
  assert.equal(result.impact_level, 1);
});

test("confidence needs five earlier comparable actuals and stable error for high", () => {
  const observations = Array.from({ length: 10 }, (_, i) => ({
    work_center_id: "machine", product_id: "product", readiness: "READY",
    stop_nature: "unplanned",
    recorded_at: new Date(Date.UTC(2026, 8, 28, i)).toISOString(),
    scrap_unit: "kg", actual_scrap_quantity: 50,
    estimated_total_scrap: 48,
  }));
  const state = context({ profiles: [{ work_center_id: "machine",
    product_id: "product", scrap_expected: true,
    shutdown_scrap_quantity: 20, restart_scrap_quantity: 28, scrap_unit: "kg" }] });
  const saved = [sample(at(0), state)];
  assert.equal(calculateProductionLoss(event(), saved, null, Date.now(),
    observations.slice(0, 4)).confidence, "LOW");
  assert.equal(calculateProductionLoss(event(), saved, null, Date.now(),
    observations.slice(0, 5)).confidence, "MEDIUM");
  assert.equal(calculateProductionLoss(event(), saved, null, Date.now(),
    observations).confidence, "HIGH");
  assert.equal(calculateProductionLoss(event(), saved, null, Date.now(),
    observations.map((x) => ({ ...x, actual_scrap_quantity: 100 }))).confidence,
  "MEDIUM");
});

test("actual quantities remain separate and calibration needs five comparable events", () => {
  const result = calculateProductionLoss(event(at(30)),
    [sample(at(0), context())], { scrap_quantity: 82, recovery_minutes: 45 });
  assert.equal(result.actual_scrap_quantity, 82);
  assert.equal(result.actual_recovery_minutes, 45);
  const records = Array.from({ length: 5 }, (_, i) => ({
    work_center_id: "machine", product_id: "product", scrap_unit: "kg",
    stop_nature: "unplanned",
    actual_restart_scrap: 40 + i, readiness: "READY",
  }));
  assert.equal(suggestScrapCalibration(event(), { assumptions: [{ product_id: "product" }],
    scrap_unit: "kg" }, records.slice(0, 4), "restart"), null);
  assert.equal(suggestScrapCalibration(event(), { assumptions: [{ product_id: "product" }],
    scrap_unit: "kg" }, records, "restart")?.suggested_value, 42);
});
