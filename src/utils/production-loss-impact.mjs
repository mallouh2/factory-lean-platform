import { evaluateFlow } from "./production-flow.mjs";

export const LOSS_MODEL_VERSION = 1;
const minute = 60_000;
const number = (value) => value === null || value === undefined || value === ""
  ? null : Number.isFinite(Number(value)) ? Number(value) : null;
const time = (value) => value ? Date.parse(value) : NaN;
const same = (left, right) => String(left) === String(right);
const rows = (context, key) => Array.isArray(context?.[key]) ? context[key] : [];
const round = (value) => Math.round(value * 1000) / 1000;

/** Immutable event-context samples are captured by database transition triggers.
 * @param {Record<string, any>} event
 * @param {Array<{id:number|string,event_id:string,captured_at:string,context:Record<string,any>}>} samples
 * @param {Record<string, any>|null} actual
 * @param {number} now
 * @param {Array<Record<string, any>>} comparable
 */
export function calculateProductionLoss(event, samples, actual = null, now = Date.now(),
  comparable = []) {
  const started = time(event.started_at);
  const ended = event.ended_at ? time(event.ended_at) : now;
  const base = {
    model_version: LOSS_MODEL_VERSION,
    calculated_at: new Date(now).toISOString(),
    stop_nature: event.stop_nature || "legacy_unknown",
    planned_activity: event.planned_activity || null,
    event_started_at: event.started_at,
    event_ended_at: event.ended_at || null,
    raw_stop_minutes: Number.isFinite(started) && Number.isFinite(ended)
      ? round(Math.max(0, ended - started) / minute) : 0,
    effective_loss_minutes: 0,
    non_production_minutes: 0,
    impact_level: 0,
    flow_scope: "none",
    estimated_lost_output_quantity: 0,
    unit: null,
    estimated_shutdown_scrap: null,
    estimated_restart_scrap: null,
    estimated_total_scrap: null,
    scrap_unit: null,
    actual_scrap_quantity: number(actual?.scrap_quantity),
    actual_recovery_minutes: number(actual?.recovery_minutes),
    deferred_quantity: 0,
    deferred_unit: null,
    estimated_recovery_minutes: null,
    mitigation: [],
    readiness: "NOT_APPLICABLE",
    missing: /** @type {string[]} */ ([]),
    assumptions: /** @type {Array<Record<string, any>>} */ ([]),
    confidence: "LOW",
    confidence_basis: { comparable_count: 0, mean_relative_scrap_error: null },
  };
  if (!Number.isFinite(started) || !Number.isFinite(ended) || ended <= started) return base;
  const history = samples
    .filter((x) => same(x.event_id, event.id) && Number.isFinite(time(x.captured_at)))
    .sort((a, b) => time(a.captured_at) - time(b.captured_at) ||
      Number(a.id) - Number(b.id));
  if (!history.length || time(history[0].captured_at) > started) {
    return { ...base, readiness: "INCOMPLETE",
      impact_level: null,
      effective_loss_minutes: null, estimated_lost_output_quantity: null,
      missing: ["Historical event context snapshot"] };
  }
  const boundaries = new Set([started, ended]);
  for (const sample of history) {
    const at = time(sample.captured_at);
    if (at > started && at < ended) boundaries.add(at);
    for (const order of rows(sample.context, "orders")) {
      for (const value of [order.start_time, order.expected_finish]) {
        const t = time(value);
        if (t > started && t < ended) boundaries.add(t);
      }
    }
    for (const stop of rows(sample.context, "stops")) {
      const center = rows(sample.context, "centers")
        .find((x) => same(x.id, stop.work_center_id));
      if (center?.dependency_mode !== "buffer") continue;
      const coverage = number(center.buffer_minutes);
      if (coverage === null || coverage < 0) continue;
      const expiry = time(stop.started_at) + coverage * minute;
      if (expiry > started && expiry < ended) boundaries.add(expiry);
    }
  }
  const points = [...boundaries].sort((a, b) => a - b);
  const missing = new Set();
  const mitigation = new Set();
  /** @type {Array<Record<string, any>>} */
  const assumptions = [];
  let output = 0;
  let deferred = 0;
  let recovery = 0;
  let recoveryUnknown = false;
  let lossTimeUnknown = false;
  let outputUnknown = false;
  let plannedMinutes = 0;
  let impact = 0;
  let productId = null;
  let scrapProductId = null;
  let scrapConflict = false;
  let scrapProfile = null;
  let scrapProfileSeen = false;
  let outputUnit = null;
  let deferredUnit = null;
  for (let index = 0; index < points.length - 1; index++) {
    const from = points[index];
    const to = points[index + 1];
    const duration = (to - from) / minute;
    const sample = [...history].reverse().find((x) => time(x.captured_at) <= from);
    if (!sample) {
      missing.add("Historical event context snapshot");
      lossTimeUnknown = true; outputUnknown = true;
      continue;
    }
    const context = sample.context;
    const centers = rows(context, "centers");
    const center = centers.find((x) => same(x.id, event.work_center_id));
    if (!center) {
      missing.add("Stopped machine context");
      lossTimeUnknown = true; outputUnknown = true;
      continue;
    }
    const lineId = event.line_id || center.line_id;
    const orders = rows(context, "orders").filter((x) =>
      x.line_id && same(x.line_id, lineId) && x.status !== "cancelled" &&
      time(x.start_time) <= from && time(x.expected_finish) >= to);
    if (!orders.length) {
      base.non_production_minutes += duration;
      continue;
    }
    plannedMinutes += duration;
    if (orders.length > 1) {
      missing.add("Overlapping planned Product Items");
      lossTimeUnknown = true; outputUnknown = true;
      continue;
    }
    const order = orders[0];
    productId = order.product_id;
    if (scrapProductId && !same(scrapProductId, productId)) scrapConflict = true;
    if (!scrapProductId) scrapProductId = productId;
    const product = rows(context, "products").find((x) => same(x.id, productId));
    const capability = rows(context, "capabilities").find((x) =>
      same(x.work_center_id, center.id) && same(x.product_id, productId));
    const rate = number(capability?.rate);
    const unit = capability?.rate_unit;
    const profile = rows(context, "profiles").find((x) =>
      same(x.work_center_id, center.id) && same(x.product_id, productId));
    if (!scrapProfileSeen) {
      scrapProfile = profile;
      scrapProfileSeen = true;
    }
    const flow = evaluateFlow(centers, rows(context, "stops"),
      rows(context, "transfers"), from + 1);
    const state = flow[String(center.id)]?.state;
    const source = flow[String(center.id)]?.source;
    // Only one causal root receives a line's lost throughput for this segment.
    // Downstream blocked centers remain visible in evaluateFlow but do not
    // create copies of the same production loss.
    const lineBlocker = centers.filter((candidate) =>
      same(candidate.line_id, lineId) && candidate.status === "stopped" &&
      flow[String(candidate.id)]?.state === "blocked" &&
      rows(context, "stops").some((stop) =>
        same(stop.work_center_id, candidate.id) && !stop.ended_at))
      .sort((a, b) => Number(a.position) - Number(b.position))[0];
    const scope = center.impact_scope || "none";
    const segmentAssumptions = {
      from: new Date(from).toISOString(), to: new Date(to).toISOString(),
      context_snapshot_id: sample.id, order_id: order.id, product_id: productId,
      intended_rate: rate, unit, flow_state: state, flow_source: source,
      dependency_mode: center.dependency_mode, buffer_minutes: center.buffer_minutes,
      can_defer: profile?.can_defer ?? null,
      scrap_expected: profile?.scrap_expected ?? null,
      shutdown_scrap_quantity: profile?.shutdown_scrap_quantity ?? null,
      restart_scrap_quantity: profile?.restart_scrap_quantity ?? null,
      scrap_unit: profile?.scrap_unit ?? null,
    };
    assumptions.push(segmentAssumptions);
    if (unit && outputUnit && !same(unit, outputUnit))
      missing.add("Multiple planned output units in one event");
    if (unit) outputUnit = unit;
    if (state === "bufferActive") {
      mitigation.add("buffer");
      impact = Math.max(impact, 1);
      continue;
    }
    if (state === "transferred") {
      if (lineBlocker && !same(lineBlocker.id, center.id)) {
        impact = Math.max(impact, 1);
        continue;
      }
      const transfer = rows(context, "transfers").find((x) =>
        same(x.original_id, center.id) && !x.ended_at);
      const alternative = centers.find((x) => same(x.id, transfer?.alternative_id));
      if (!alternative || alternative.status !== "running") {
        missing.add("Active alternative context"); continue;
      }
      mitigation.add("active_transfer");
      if (rate === null || rate <= 0 || !unit || !same(unit, product?.unit)) {
        missing.add(`Production rate for ${center.name || center.code} + ${product?.name || productId}`);
        lossTimeUnknown = true; outputUnknown = true;
        continue;
      }
      const alternativeCap = rows(context, "capabilities").find((x) =>
        same(x.work_center_id, alternative.id) && same(x.product_id, productId));
      const available = number(alternativeCap?.rate);
      segmentAssumptions.available_rate = available;
      segmentAssumptions.alternative_id = alternative.id;
      if (available === null || available <= 0 || !same(alternativeCap.rate_unit, unit)) {
        missing.add(`Alternative rate for ${alternative.name || alternative.code} + ${product?.name || productId}`);
        lossTimeUnknown = true; outputUnknown = true;
        continue;
      }
      if (available < rate) {
        base.effective_loss_minutes += duration * (rate - available) / rate;
        output += (rate - available) * duration / 60;
        impact = Math.max(impact, 3);
      } else impact = Math.max(impact, 1);
      base.flow_scope = scope;
      base.unit = unit;
      continue;
    }
    if (state !== "blocked") {
      if (center.status === "stopped" && center.dependency_mode === "independent" &&
        profile?.can_defer == null) {
        missing.add(`Deferred-work decision for ${center.name || center.code} + ${product?.name || productId}`);
      }
      if (profile?.can_defer === true && center.status === "stopped") {
        if (rate === null || rate <= 0 || !unit || !same(unit, product?.unit)) {
          missing.add(`Production rate for ${center.name || center.code} + ${product?.name || productId}`);
          outputUnknown = true;
          continue;
        }
        const recoveryRate = rows(context, "recovery_rates").find((x) =>
          same(x.work_center_id, center.id) && same(x.product_id, productId));
        segmentAssumptions.recovery_rate = number(recoveryRate?.rate);
        if (!recoveryRate || number(recoveryRate.rate) <= 0 || !same(recoveryRate.unit, unit)) {
          missing.add(`Recovery capacity for ${center.name || center.code} + ${product?.name || productId}`);
          recoveryUnknown = true;
        } else recovery += rate * duration / number(recoveryRate.rate);
        deferred += rate * duration / 60;
        if (deferredUnit && !same(deferredUnit, unit))
          missing.add("Multiple deferred output units in one event");
        deferredUnit = unit;
        base.deferred_unit = unit;
        impact = Math.max(impact, 2);
      } else if (center.status === "stopped") impact = Math.max(impact, 1);
      continue;
    }
    if (lineBlocker && !same(lineBlocker.id, center.id)) {
      impact = Math.max(impact, 1);
      continue;
    }
    if (center.dependency_mode === "buffer" && number(center.buffer_minutes) === null) {
      missing.add(`Reliable buffer coverage for ${center.name || center.code}`);
      lossTimeUnknown = true; outputUnknown = true;
      continue;
    }
    base.effective_loss_minutes += duration;
    impact = Math.max(impact, 4);
    if (rate === null || rate <= 0 || !unit || !same(unit, product?.unit)) {
      missing.add(`Production rate for ${center.name || center.code} + ${product?.name || productId}`);
      outputUnknown = true;
      continue;
    }
    output += rate * duration / 60;
    base.unit = unit;
    base.flow_scope = scope;
  }
  if (plannedMinutes && !scrapConflict) {
    if (!scrapProfile || scrapProfile.scrap_expected === null ||
      scrapProfile.scrap_expected === undefined) {
      missing.add("Shutdown/restart scrap expectation for stopped machine");
    } else if (scrapProfile.scrap_expected) {
      const shutdown = number(scrapProfile.shutdown_scrap_quantity);
      const restart = number(scrapProfile.restart_scrap_quantity);
      if (shutdown === null || restart === null || !scrapProfile.scrap_unit)
        missing.add("Shutdown/restart scrap quantities and unit");
      else {
        base.estimated_shutdown_scrap = shutdown;
        base.estimated_restart_scrap = restart;
        base.estimated_total_scrap = shutdown + restart;
        base.scrap_unit = scrapProfile.scrap_unit;
      }
    } else {
      base.estimated_shutdown_scrap = 0;
      base.estimated_restart_scrap = 0;
      base.estimated_total_scrap = 0;
    }
  } else if (scrapConflict) missing.add("Product changes during stop; scrap estimate needs review");
  base.effective_loss_minutes = lossTimeUnknown ? null : round(base.effective_loss_minutes);
  base.non_production_minutes = round(base.non_production_minutes);
  base.estimated_lost_output_quantity = outputUnknown ||
    missing.has("Multiple planned output units in one event")
    ? null : round(output);
  base.deferred_quantity = missing.has("Multiple deferred output units in one event")
    ? null : round(deferred);
  if (base.deferred_quantity === null) base.deferred_unit = null;
  base.estimated_recovery_minutes = deferred && !recoveryUnknown &&
    base.deferred_quantity !== null ? round(recovery) : null;
  base.impact_level = impact;
  base.mitigation = [...mitigation];
  base.assumptions = assumptions;
  base.missing = [...missing];
  base.readiness = missing.size ? "INCOMPLETE" : plannedMinutes ? "READY" : "NOT_APPLICABLE";
  const matching = comparable.filter((x) =>
    time(x.recorded_at) <= started &&
    same(x.stop_nature, event.stop_nature) &&
    (event.stop_nature !== "planned" ||
      same(x.planned_activity, event.planned_activity)) &&
    same(x.work_center_id, event.work_center_id) &&
    same(x.product_id, assumptions[0]?.product_id) &&
    x.readiness === "READY" &&
    number(x.actual_scrap_quantity) !== null &&
    number(x.estimated_total_scrap) !== null &&
    same(x.scrap_unit, scrapProfile?.scrap_unit));
  base.confidence_basis.comparable_count = matching.length;
  if (scrapProfile?.scrap_expected === true && matching.length >= 5)
    base.confidence = "MEDIUM";
  if (scrapProfile?.scrap_expected === true && matching.length >= 10) {
    const relativeErrors = matching.map((x) => Math.abs(
      Number(x.actual_scrap_quantity) - Number(x.estimated_total_scrap)) /
      Math.max(1, Number(x.actual_scrap_quantity)));
    const meanError = relativeErrors.reduce((sum, value) => sum + value, 0) /
      relativeErrors.length;
    base.confidence_basis.mean_relative_scrap_error = round(meanError);
    if (meanError <= 0.15) base.confidence = "HIGH";
  }
  return base;
}

/** Suggestions are advisory. Only an engineer's explicit configuration RPC changes a profile. */
export function suggestScrapCalibration(event, estimate, comparable, parameter) {
  if (!["shutdown", "restart"].includes(parameter)) return null;
  if (!["planned", "unplanned"].includes(event.stop_nature)) return null;
  const field = parameter === "shutdown"
    ? "actual_shutdown_scrap" : "actual_restart_scrap";
  const observations = comparable.filter((x) =>
    same(x.work_center_id, event.work_center_id) &&
    same(x.stop_nature, event.stop_nature) &&
    (event.stop_nature !== "planned" ||
      same(x.planned_activity, event.planned_activity)) &&
    same(x.product_id, estimate?.assumptions?.[0]?.product_id) &&
    same(x.scrap_unit, estimate?.scrap_unit) &&
    number(x[field]) !== null &&
    x.readiness === "READY");
  if (observations.length < 5) return null;
  const average = observations.reduce((sum, x) =>
    sum + Number(x[field]), 0) / observations.length;
  return { samples: observations.length, parameter,
    suggested_value: round(average), requires_approval: true };
}
