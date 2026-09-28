/** Planning is derived from existing order fields; no second order status is stored. */
import { formatLocalInput, localDateTimeToUtc } from "./manufacturing.mjs";

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;

/** Null fields preserve the legacy continuous calendar until a factory configures hours. */
export function workingCalendar(factory) {
  const mask = Number(factory?.working_days_mask);
  const start = String(factory?.workday_start || "").slice(0, 5);
  const end = String(factory?.workday_end || "").slice(0, 5);
  return Number.isInteger(mask) && mask > 0 && mask <= 127 &&
    /^\d\d:\d\d$/.test(start) && /^\d\d:\d\d$/.test(end) && start < end
    ? { mask, start, end } : null;
}

function localDay(time, zone) { return formatLocalInput(new Date(time).toISOString(), zone).slice(0, 10); }
function addDay(day, count) {
  return new Date(Date.parse(day + "T00:00:00Z") + count * DAY).toISOString().slice(0, 10);
}
function dayWindow(day, calendar, zone) {
  const weekday = new Date(day + "T00:00:00Z").getUTCDay();
  if (!(calendar.mask & (1 << weekday))) return null;
  return { start: Date.parse(localDateTimeToUtc(day + "T" + calendar.start, zone)),
    finish: Date.parse(localDateTimeToUtc(day + "T" + calendar.end, zone)) };
}

export function workingSegments(from, until, calendar, zone = "UTC") {
  if (!calendar) return until > from ? [{ start: from, finish: until }] : [];
  const segments = [];
  const firstDay = localDay(from, zone);
  for (let offset = 0; offset < 4000; offset++) {
    const day = addDay(firstDay, offset);
    const window = dayWindow(day, calendar, zone);
    if (window && window.start >= until) break;
    if (window) {
      const start = Math.max(from, window.start), finish = Math.min(until, window.finish);
      if (finish > start) segments.push({ start, finish });
    }
  }
  return segments;
}

export function nextWorkingTime(from, calendar, zone = "UTC") {
  if (!calendar) return from;
  const firstDay = localDay(from, zone);
  for (let offset = 0; offset < 8; offset++) {
    const window = dayWindow(addDay(firstDay, offset), calendar, zone);
    if (window && window.finish > from) return Math.max(from, window.start);
  }
  return NaN;
}

export function workingDurationMs(from, until, calendar, zone = "UTC") {
  return workingSegments(from, until, calendar, zone)
    .reduce((total, segment) => total + segment.finish - segment.start, 0);
}

export function finishAfterWorkingMs(start, duration, calendar, zone = "UTC") {
  if (!calendar) return start + duration;
  let remaining = duration;
  let cursor = nextWorkingTime(start, calendar, zone);
  for (let i = 0; i < 4000; i++) {
    const day = localDay(cursor, zone);
    const window = dayWindow(day, calendar, zone);
    if (window && cursor < window.finish) {
      const available = window.finish - cursor;
      if (remaining <= available) return cursor + remaining;
      remaining -= available;
      cursor = window.finish;
    }
    cursor = nextWorkingTime(cursor + MINUTE, calendar, zone);
  }
  return NaN;
}

export function crossesClosedTime(start, finish, calendar, zone = "UTC") {
  return Boolean(calendar) && workingDurationMs(start, finish, calendar, zone) < finish - start;
}

export function freeWorkingGaps(schedule, from, until, calendar, zone = "UTC") {
  const result = freeGaps(schedule, from, until);
  if (result.error || !calendar) return result;
  return { gaps: result.gaps.flatMap((gap) => workingSegments(gap.start, gap.finish, calendar, zone)) };
}

export function isScheduled(order) {
  return order.status === "planned" && Boolean(order.line_id) &&
    Number.isFinite(Date.parse(String(order.start_time || "")));
}

/** Board placement follows the stored production state; it never advances an item. */
export function planningBoardStatus(order) {
  if (order.status === "completed") return "planningCompleted";
  if (order.status === "active") return "planningInProduction";
  return isScheduled(order) ? "planningPlannedState" : "planningWaiting";
}

export function planningStage(order, centers = [], lines = [], capabilities = []) {
  if (order.status !== "planned") return "outsidePlanning";
  if (!isScheduled(order)) return "needsPlanning";
  const line = lines.find((candidate) => String(candidate.id) === String(order.line_id));
  if (!line || line.archived || line.paused_at) return "waitingForManager";
  return centers.some((center) => !center.archived &&
    String(center.line_id) === String(order.line_id) &&
    String(center.order_id) === String(order.id) && Boolean(center.operator_id) &&
    ["idle", "running"].includes(String(center.status)) &&
    capabilities.some((capability) =>
      String(capability.work_center_id) === String(center.id) &&
      String(capability.product_id) === String(order.product_id)))
    ? "readyForProduction" : "waitingForManager";
}

export function capableCenters(order, line, centers, capabilities) {
  return centers.filter((center) => !center.archived &&
    String(center.line_id) === String(line.id) &&
    capabilities.some((capability) =>
      String(capability.work_center_id) === String(center.id) &&
      String(capability.product_id) === String(order.product_id)));
}

export function capableLines(order, lines, centers, capabilities) {
  return lines.filter((line) => !line.archived &&
    capableCenters(order, line, centers, capabilities).length > 0);
}

/** A line has one usable throughput only when its capable centers agree. */
export function lineRate(order, line, centers, capabilities) {
  const matches = capableCenters(order, line, centers, capabilities)
    .map((center) => capabilities.find((capability) =>
      String(capability.work_center_id) === String(center.id) &&
      String(capability.product_id) === String(order.product_id)));
  if (!matches.length) return { error: "planningIncompatibleLine" };
  const unit = String(order.unit || "");
  if (!["meter", "piece"].includes(unit) || matches.some((match) =>
    !Number.isFinite(Number(match.rate)) || Number(match.rate) <= 0 ||
    String(match.rate_unit || "") !== unit)) return { error: "planningMissingRate" };
  const rate = Number(matches[0].rate);
  if (matches.some((match) => Number(match.rate) !== rate)) return { error: "planningAmbiguousRate" };
  const setupMinutes = Number(matches[0].setup_minutes || 0);
  if (matches.some((match) => Number(match.setup_minutes || 0) !== setupMinutes))
    return { error: "planningAmbiguousSetup" };
  return { rate, unit, setupMinutes };
}

export function durationMs(order, line, centers, capabilities) {
  const throughput = lineRate(order, line, centers, capabilities);
  if (throughput.error) return throughput;
  const quantity = Number(order.target_quantity);
  if (!Number.isFinite(quantity) || quantity <= 0) return { error: "planningInvalidQuantity" };
  const productionMs = Math.ceil(quantity / throughput.rate * 60) * MINUTE;
  const setupMs = throughput.setupMinutes * MINUTE;
  return { ...throughput, ms: productionMs, productionMs, setupMs, totalMs: productionMs + setupMs };
}

/** @param {{mask:number,start:string,end:string}|null} calendar */
export function plannedInterval(order, line, centers, capabilities, calendar = null, zone = "UTC") {
  const start = Date.parse(String(order.start_time || ""));
  if (!Number.isFinite(start)) return null;
  const recordedFinish = Date.parse(String(order.expected_finish || ""));
  if (Number.isFinite(recordedFinish) && recordedFinish > start)
    return { order, start, finish: recordedFinish };
  const duration = durationMs(order, line, centers, capabilities);
  return duration.error ? { order, start, finish: null, error: duration.error } :
    { order, start, finish: finishAfterWorkingMs(nextWorkingTime(start, calendar, zone),
      duration.totalMs, calendar, zone) };
}

/**
 * @param {string|null} [excludeId]
 * @param {{mask:number,start:string,end:string}|null} calendar
 */
export function sortedLineSchedule(line, orders, centers, capabilities, excludeId = null,
  calendar = null, zone = "UTC") {
  return orders.filter((order) => ["planned", "active"].includes(order.status) &&
    String(order.line_id) === String(line.id) && String(order.id) !== String(excludeId))
    .map((order) => plannedInterval(order, line, centers, capabilities, calendar, zone) ||
      { order, start: Date.now(), finish: null, error: "planningUnknownBlock" })
    .filter(Boolean).sort((a, b) => a.start - b.start);
}

/** Capacity is working time inside the visible window; overlapping reservations add up. */
/** @param {Array<{order: object, start: number, finish: number | null}>} schedule
 *  @param {{mask:number,start:string,end:string}|null} calendar */
export function lineCapacity(schedule, from, until, calendar = null, zone = "UTC") {
  const availableMs = workingDurationMs(from, until, calendar, zone);
  let bookedMs = 0;
  let incomplete = false;
  for (const slot of schedule) {
    if (!Number.isFinite(slot.finish)) {
      if (slot.start < until) incomplete = true;
      continue;
    }
    const start = Math.max(from, slot.start);
    const finish = Math.min(until, slot.finish);
    if (finish > start) bookedMs += workingDurationMs(start, finish, calendar, zone);
  }
  return { availableMinutes: availableMs / MINUTE, bookedMinutes: bookedMs / MINUTE,
    percent: availableMs > 0 ? bookedMs / availableMs * 100 : null, incomplete };
}

export function freeGaps(schedule, from, until) {
  const gaps = [];
  let cursor = from;
  for (const slot of schedule) {
    if (slot.finish === null) return { gaps, error: "planningUnknownBlock" };
    if (slot.finish <= from) continue;
    if (slot.start > cursor) gaps.push({ start: cursor, finish: Math.min(slot.start, until) });
    cursor = Math.max(cursor, slot.finish);
    if (cursor >= until) break;
  }
  if (cursor < until) gaps.push({ start: cursor, finish: until });
  return { gaps: gaps.filter((gap) => gap.finish > gap.start) };
}

export function overlappingItems(schedule) {
  const ids = new Set();
  for (let i = 0; i < schedule.length; i++) {
    for (let j = i + 1; j < schedule.length && schedule[j].start < (schedule[i].finish ?? Infinity); j++) {
      ids.add(String(schedule[i].order.id));
      ids.add(String(schedule[j].order.id));
    }
  }
  return ids;
}

/** @param {{mask:number,start:string,end:string}|null} calendar */
export function firstAvailable(schedule, from, duration, until = from + 365 * 24 * 60 * MINUTE,
  calendar = null, zone = "UTC") {
  const result = freeGaps(schedule, from, until);
  if (result.error) return result;
  for (const gap of result.gaps) {
    const start = nextWorkingTime(gap.start, calendar, zone);
    const finish = finishAfterWorkingMs(start, duration, calendar, zone);
    if (finish <= gap.finish) return { start, finish };
  }
  return { error: "planningNoFit" };
}

/** @param {{mask:number,start:string,end:string}|null} calendar */
export function proposeSchedule(order, line, start, orders, centers, capabilities, now = Date.now(),
  calendar = null, zone = "UTC") {
  if (order.status !== "planned" || Number(order.produced_quantity || 0) > 0)
    return { error: "planningAlreadyStarted" };
  const duration = durationMs(order, line, centers, capabilities);
  if (duration.error) return duration;
  if (!Number.isFinite(start)) return { error: "planningInvalidStart" };
  const placedStart = nextWorkingTime(start, calendar, zone);
  if (start < now - MINUTE) return { error: "planningInvalidStart" };
  const finish = finishAfterWorkingMs(placedStart, duration.totalMs, calendar, zone);
  const schedule = sortedLineSchedule(line, orders, centers, capabilities, order.id, calendar, zone);
  if (schedule.some((slot) => slot.finish === null)) return { error: "planningUnknownBlock" };
  if (schedule.some((slot) => placedStart < slot.finish && finish > slot.start))
    return { error: "planningOverlap" };
  return { start: placedStart, requestedStart: start, finish, durationMs: duration.totalMs,
    productionMs: duration.productionMs, setupMs: duration.setupMs, rate: duration.rate };
}

export function deadlineStatus(finish, requiredBy, now = Date.now()) {
  const due = Date.parse(String(requiredBy || ""));
  if (!Number.isFinite(due)) return "planningNoDeadline";
  if (!Number.isFinite(finish)) return due < now ? "planningLate" : "planningDeadlineUnknown";
  if (finish > due) return "planningLate";
  return due - finish <= 24 * 60 * MINUTE ? "planningAtRisk" : "planningOnTrack";
}

/** Derived openings only. Every candidate is checked by the normal placement rules. */
export function suggestPlanningSlots(order, request, lines, orders, centers, capabilities, options = {}) {
  const { now = Date.now(), horizonDays = 28, limit = 3, calendar = null, zone = "UTC" } = options;
  const until = now + horizonDays * DAY;
  const capable = capableLines(order, lines, centers, capabilities);
  if (!capable.length) return { suggestions: [], reason: "planningNoCapableLine", horizonDays };
  const candidates = [];
  let validRate = false;
  let unknownBlock = false;
  for (const line of capable) {
    const duration = durationMs(order, line, centers, capabilities);
    if (duration.error) continue;
    validRate = true;
    const schedule = sortedLineSchedule(line, orders, centers, capabilities, order.id, calendar, zone);
    const available = freeGaps(schedule, now, until);
    if (available.error) { unknownBlock = true; continue; }
    for (const gap of available.gaps) {
      const opening = firstAvailable([], gap.start, duration.totalMs, gap.finish, calendar, zone);
      if (opening.error || !Number.isFinite(opening.finish) || opening.finish > until) continue;
      const placement = proposeSchedule(order, line, opening.start, orders, centers, capabilities,
        now, calendar, zone);
      if (placement.error || placement.finish > gap.finish) continue;
      candidates.push({ lineId: String(line.id), start: placement.start, finish: placement.finish,
        setupMs: placement.setupMs, productionMs: placement.productionMs,
        totalMs: placement.durationMs, rate: Number(placement.rate),
        deadline: deadlineStatus(placement.finish, request?.required_by, now),
        load: lineCapacity(schedule, now, Math.min(until, now + 7 * DAY),
          calendar, zone) });
    }
  }
  const rank = (a, b) => Number(a.deadline === "planningLate") - Number(b.deadline === "planningLate") ||
    a.finish - b.finish || a.start - b.start ||
    (a.load.percent ?? Infinity) - (b.load.percent ?? Infinity) || a.lineId.localeCompare(b.lineId);
  candidates.sort(rank);
  const diverse = [], seen = new Set();
  for (const candidate of candidates) {
    if (!seen.has(candidate.lineId)) { diverse.push(candidate); seen.add(candidate.lineId); }
  }
  const chosen = diverse.slice(0, limit);
  for (const candidate of candidates) {
    if (chosen.length >= limit) break;
    if (!chosen.includes(candidate)) chosen.push(candidate);
  }
  chosen.sort(rank);
  return { suggestions: chosen, reason: chosen.length ? null :
    !validRate ? "planningMissingRate" : unknownBlock ? "planningUnknownBlock" : "planningSlotNone",
    horizonDays };
}

export function planningWarnings(order, request, line, centers, capabilities, orders, now = Date.now()) {
  const warnings = [];
  const due = Date.parse(String(request?.required_by || ""));
  const start = Date.parse(String(order.start_time || ""));
  if (Number.isFinite(due) && due < now) warnings.push("planningDuePassed");
  if (Number.isFinite(due) && Number.isFinite(start) && start > due)
    warnings.push("planningAfterDue");
  if (line) {
    const eligible = capableCenters(order, line, centers, capabilities);
    if (!eligible.length) warnings.push("planningIncompatibleLine");
    if (line.paused_at) warnings.push("planningLinePaused");
    if (eligible.length && eligible.every((center) => ["stopped", "offline"].includes(String(center.status))))
      warnings.push("planningCentersUnavailable");
    if (orders.some((other) => other.id !== order.id && other.status === "active" &&
      String(other.line_id) === String(line.id))) warnings.push("planningLineActive");
    if (Number.isFinite(start) && orders.some((other) =>
      other.id !== order.id && other.status === "planned" &&
      String(other.line_id) === String(line.id) &&
      Date.parse(String(other.start_time || "")) === start))
      warnings.push("planningSameStart");
  }
  return warnings;
}

export function sortPlanningItems(items, requests, now = Date.now()) {
  const byRequest = new Map(requests.map((request) => [String(request.id), request]));
  const priority = { urgent: 0, high: 1, normal: 2, low: 3, unspecified: 4 };
  return [...items].sort((a, b) => {
    const ar = byRequest.get(String(a.request_id));
    const br = byRequest.get(String(b.request_id));
    const due = (request) => {
      const value = Date.parse(String(request?.required_by || ""));
      return Number.isFinite(value) ? value : Infinity;
    };
    const aDue = due(ar); const bDue = due(br);
    const aUrgent = aDue < now ? 0 : 1; const bUrgent = bDue < now ? 0 : 1;
    return aUrgent - bUrgent ||
      (priority[ar?.priority] ?? 4) - (priority[br?.priority] ?? 4) ||
      aDue - bDue ||
      String(ar?.created_at || "").localeCompare(String(br?.created_at || ""));
  });
}

/** Keep each request's product items together while retaining queue priority order. */
export function groupPlanningRequests(items, requests) {
  const byRequest = new Map(requests.map((request) => [String(request.id), request]));
  const groups = new Map();
  for (const item of items) {
    const key = String(item.request_id || item.id);
    if (!groups.has(key)) groups.set(key, { request: byRequest.get(key) || null, items: [] });
    groups.get(key).items.push(item);
  }
  return [...groups.values()];
}

const PRODUCT_TONES = [
  { surface: "#deebf5", ink: "#224a69", edge: "#5b8db1" },
  { surface: "#e8e2f3", ink: "#594276", edge: "#9477b2" },
  { surface: "#dcefee", ink: "#235d5d", edge: "#5c9f9a" },
  { surface: "#eee4ed", ink: "#694865", edge: "#aa7d9f" },
  { surface: "#e3eaf6", ink: "#394e79", edge: "#7188b6" },
  { surface: "#e8edf0", ink: "#405a68", edge: "#7894a1" },
  { surface: "#ece6f5", ink: "#5d4b7a", edge: "#9a86b9" },
  { surface: "#dfecf3", ink: "#34566e", edge: "#739bb4" },
  { surface: "#e6ede9", ink: "#3f6057", edge: "#78a293" },
  { surface: "#f0e8ee", ink: "#694c61", edge: "#ac8ba1" },
  { surface: "#e2eaf0", ink: "#3d5b6c", edge: "#7897a9" },
  { surface: "#e8e8f2", ink: "#4f5274", edge: "#8d90b3" },
];

/** Stable, collision-free colors for the current catalog; no render-time randomness. */
export function planningProductTones(products) {
  const ids = [...new Set(products.map((product) => String(product.id)))].sort();
  return new Map(ids.map((id, index) => [id, PRODUCT_TONES[index % PRODUCT_TONES.length]]));
}

/** A drop and its ghost use the same capability, gap, and overlap rules. */
export function previewPlacement(order, line, rawStart, orders, centers, capabilities, options = {}) {
  const { from = rawStart, until = rawStart + 7 * 24 * 60 * MINUTE,
    increment = 15 * MINUTE, now = Date.now(), calendar = null, zone = "UTC" } = options;
  const start = Math.round(rawStart / increment) * increment;
  const duration = durationMs(order, line, centers, capabilities);
  if (duration.error) return { error: duration.error, start, finish: start };
  const placedStart = nextWorkingTime(Math.max(start, Math.ceil(now / increment) * increment), calendar, zone);
  const finish = finishAfterWorkingMs(placedStart, duration.totalMs, calendar, zone);
  const visual = { start: placedStart, requestedStart: start, finish,
    durationMs: duration.totalMs, productionMs: duration.productionMs,
    setupMs: duration.setupMs, rate: duration.rate };
  const schedule = sortedLineSchedule(line, orders, centers, capabilities, order.id, calendar, zone);
  const available = freeGaps(schedule, from, Math.max(until, finish));
  if (available.error) return { ...visual, error: available.error };
  if (!available.gaps.some((gap) => placedStart >= gap.start && finish <= gap.finish))
    return { ...visual, error: "planningNoFit" };
  return { ...visual, ...proposeSchedule(order, line, start, orders, centers, capabilities,
    now, calendar, zone) };
}

// ---------------------------------------------------------------------------
// Timeline navigation — pure VIEW state over the same continuous schedule.
// These helpers only move the visible window; they never receive, return, or
// modify planning data, so panning/zooming can never reschedule a job.
// ---------------------------------------------------------------------------
/** Dragging the timeline RIGHT pulls earlier time into view (grab metaphor). */
export function panViewStart(viewStart, span, widthPx, dxPx) {
  return Math.round(viewStart - (dxPx / Math.max(1, widthPx)) * span);
}

/** Wheel / trackpad right (or shift+wheel down) moves toward LATER time. */
export function wheelViewStart(viewStart, span, widthPx, deltaPx) {
  return Math.round(viewStart + (deltaPx / Math.max(1, widthPx)) * span);
}

/** Zoom changes keep the window centered on the same period. */
export function zoomViewStart(viewStart, currentSpan, nextSpan) {
  return viewStart + Math.round((currentSpan - nextSpan) / 2);
}
