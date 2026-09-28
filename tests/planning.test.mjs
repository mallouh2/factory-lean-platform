import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };
import {
  capableLines, crossesClosedTime, deadlineStatus, durationMs, finishAfterWorkingMs,
  firstAvailable, freeGaps, freeWorkingGaps, groupPlanningRequests, isScheduled,
  nextWorkingTime, panViewStart,
  workingCalendar, workingDurationMs, wheelViewStart, zoomViewStart, lineCapacity,
  lineRate, overlappingItems, planningBoardStatus, planningProductTones, planningStage, planningWarnings, previewPlacement,
  proposeSchedule, sortedLineSchedule, sortPlanningItems,
  suggestPlanningSlots,
} from "../src/utils/planning.mjs";

const requests = [
  { id: "R1", code: "PO-1", name: "Pipe project", priority: "urgent", required_by: "2026-09-25T10:00:00Z" },
  { id: "R2", code: "PO-2", name: "Stock", priority: "normal", required_by: "2026-10-10T10:00:00Z" },
];
const orders = [
  { id: "O1", request_id: "R1", code: "ITEM-1", product_id: "P", status: "planned", line_id: null, start_time: null, target_quantity: 300, unit: "meter" },
  { id: "O2", request_id: "R2", code: "ITEM-2", product_id: "P", status: "planned", line_id: "L", start_time: "2026-10-08T08:00:00Z", target_quantity: 50, unit: "piece" },
];
const lines = [{ id: "L", name: "Pipe line", name_ar: "خط الأنابيب" }, { id: "X", name: "Other line" }];
const centers = [{ id: "C", line_id: "L", status: "idle", archived: false, order_id: null, operator_id: null }];
const capabilities = [{ work_center_id: "C", product_id: "P", rate: 25, rate_unit: "piece" }];

test("unplanned items stay in the queue and capability narrows line choices", () => {
  assert.equal(isScheduled(orders[0]), false);
  assert.equal(isScheduled(orders[1]), true);
  assert.equal(planningStage(orders[0], centers, lines, capabilities), "needsPlanning");
  assert.deepEqual(capableLines(orders[0], lines, centers, capabilities).map((line) => line.id), ["L"]);
  assert.equal(sortPlanningItems([...orders].reverse(), requests, Date.parse("2026-09-26T00:00:00Z"))[0].id, "O1");
});

test("scheduling hands off to manager without requiring an operator", () => {
  assert.equal(planningStage(orders[1], centers, lines, capabilities), "waitingForManager");
  assert.equal(planningStage(orders[1], [{ ...centers[0], order_id: "O2", operator_id: "U" }], lines, capabilities), "readyForProduction");
  assert.deepEqual(planningWarnings(orders[1], requests[1], lines[0], centers, capabilities, orders, Date.parse("2026-09-26T00:00:00Z")), []);
});

test("due and incompatible resource warnings use recorded facts", () => {
  assert.deepEqual(planningWarnings(
    { ...orders[0], line_id: "X", start_time: "2026-09-27T08:00:00Z" },
    requests[0], lines[1], centers, capabilities, orders, Date.parse("2026-09-26T00:00:00Z")),
    ["planningDuePassed", "planningAfterDue", "planningIncompatibleLine"]);
});

test("paused lines and identical starts surface factual planning conflicts", () => {
  const other = { ...orders[0], id: "O3", line_id: "L", start_time: orders[1].start_time };
  const running = { ...other, id: "O4", status: "active", start_time: null };
  assert.deepEqual(planningWarnings(orders[1], requests[1],
    { ...lines[0], paused_at: "2026-10-01T00:00:00Z" }, centers, capabilities,
    [...orders, other, running], Date.parse("2026-09-26T00:00:00Z")),
    ["planningLinePaused", "planningLineActive", "planningSameStart"]);
});

const require = createRequire(import.meta.url);
const bundled = await build({ entryPoints: ["src/features/ProductionPlanning.tsx"], bundle: true,
  platform: "node", format: "cjs", packages: "external", write: false, logLevel: "silent" });
const planningModule = { exports: {} };
new Function("require", "module", "exports", bundled.outputFiles[0].text)(require, planningModule, planningModule.exports);
const ProductionPlanning = planningModule.exports.default;
const snapshot = { factory: { id: "F", timezone: "UTC" }, tables: {
  production_requests: requests, production_orders: orders,
  products: [{ id: "P", name: "PVC pipe", name_ar: "أنبوب" }],
  production_lines: lines, work_centers: centers, work_center_capabilities: capabilities,
} };

test("planner sees both request sections and focused fields in English and Arabic", () => {
  for (const [lang, dictionary, queueLabel] of [["en", en, "Waiting for planning"], ["ar", ar, "بانتظار التخطيط"]]) {
    const html = renderToStaticMarkup(createElement(ProductionPlanning, { snapshot,
      t: (key) => dictionary[key] || key, lang, can: () => true,
      command: async () => {}, initialItemId: "O1" }));
    assert.match(html, new RegExp(queueLabel));
    assert.match(html, /PO-1/);
    assert.match(html, /planning-timeline/);
    assert.match(html, /planning-lane-track/);
    assert.match(html, /role="dialog"/);
    assert.match(html, /type="datetime-local"/);
    assert.match(html, /value="L"/);
    assert.doesNotMatch(html, /name="operator_id"|name="technician"/);
  }
});

test("eligible scheduling sends the same line and planned start through the planning command", async () => {
  const fakeReact = {
    useState: (() => {
      const values = ["O2", "L", "2026-10-08T08:00", false, ""];
      let index = 0;
      return (initial) => [values[index++] ?? (typeof initial === "function" ? initial() : initial), () => {}];
    })(),
    useEffect: () => {},
    useRef: () => ({ current: null }),
  };
  const moduleWithHooks = { exports: {} };
  new Function("require", "module", "exports", bundled.outputFiles[0].text)(
    (name) => name === "react" ? fakeReact : require(name), moduleWithHooks, moduleWithHooks.exports);
  let saved;
  const existingPlan = { ...snapshot, tables: { ...snapshot.tables, production_orders: [
    orders[0], { ...orders[1], expected_finish: "2026-10-08T10:00:00Z" },
  ] } };
  const tree = moduleWithHooks.exports.default({ snapshot: existingPlan,
    t: (key) => en[key] || key, lang: "en", can: () => true,
    command: async (name, args) => { saved = { name, args }; }, initialItemId: "O2" });
  function find(node, type) {
    if (!node || typeof node !== "object") return null;
    if (Array.isArray(node)) return node.map((child) => find(child, type)).find(Boolean);
    if (node.type === type) return node;
    return find(node.props?.children, type);
  }
  const form = find(tree, "form");
  assert.ok(form);
  await form.props.onSubmit({ preventDefault() {} });
  assert.deepEqual(saved, { name: "plan_product_item", args: {
    factory: "F", item: "O2", target_line: "L",
    planned_start: "2026-10-08T08:00:00.000Z",
  } });
});

test("rate, duration and finish use the matching per-product capability", () => {
  const item = { ...orders[1], target_quantity: 50 };
  assert.deepEqual(lineRate(item, lines[0], centers, capabilities), { rate: 25, unit: "piece", setupMinutes: 0 });
  assert.equal(durationMs(item, lines[0], centers, capabilities).ms, 2 * 60 * 60_000);
  const proposed = proposeSchedule(item, lines[0], Date.parse("2026-10-09T08:00:00Z"),
    [orders[0]], centers, capabilities);
  assert.equal(proposed.finish, Date.parse("2026-10-09T10:00:00Z"));
  assert.equal(durationMs({ ...item, unit: "meter" }, lines[0], centers, capabilities).error, "planningMissingRate");
});

const workweek = workingCalendar({ working_days_mask: 31, workday_start: "08:00:00",
  workday_end: "17:00:00" });
const hour = 60 * 60_000;
const sunday = Date.parse("2026-09-27T08:00:00Z");

test("working calendar keeps one-day jobs inside hours and carries work to the next day", () => {
  assert.equal(finishAfterWorkingMs(sunday, 6 * hour, workweek), sunday + 6 * hour);
  assert.equal(finishAfterWorkingMs(sunday + 4 * hour, 10 * hour, workweek),
    Date.parse("2026-09-28T13:00:00Z"));
  assert.equal(workingDurationMs(sunday + 4 * hour,
    Date.parse("2026-09-28T13:00:00Z"), workweek), 10 * hour);
  assert.equal(crossesClosedTime(sunday + 4 * hour,
    Date.parse("2026-09-28T13:00:00Z"), workweek), true);
  assert.equal(finishAfterWorkingMs(sunday, 22 * hour, workweek),
    Date.parse("2026-09-29T12:00:00Z"));
});

test("closed Friday and Saturday are skipped in the factory timezone", () => {
  assert.equal(nextWorkingTime(Date.parse("2026-10-02T20:00:00Z"), workweek),
    Date.parse("2026-10-04T08:00:00Z"));
  assert.equal(finishAfterWorkingMs(Date.parse("2026-10-01T14:00:00Z"), 6 * hour, workweek),
    Date.parse("2026-10-04T11:00:00Z"));
  assert.equal(nextWorkingTime(Date.parse("2026-09-27T17:00:00Z"), workweek, "Asia/Qatar"),
    Date.parse("2026-09-28T05:00:00Z"));
  assert.deepEqual(freeWorkingGaps([], sunday, sunday + 24 * hour, workweek).gaps,
    [{ start: sunday, finish: sunday + 9 * hour }]);
});

test("setup stays separate from production and changes real reservation, line, and deadline", () => {
  const item = { ...orders[0], unit: "piece", target_quantity: 200 };
  const cap = [{ ...capabilities[0], setup_minutes: 60 }];
  const duration = durationMs(item, lines[0], centers, cap);
  assert.equal(duration.productionMs, 8 * hour);
  assert.equal(duration.setupMs, hour);
  assert.equal(duration.totalMs, 9 * hour);
  const proposal = proposeSchedule(item, lines[0], sunday + 6 * hour,
    [], centers, cap, 0, workweek);
  assert.equal(proposal.finish, Date.parse("2026-09-28T14:00:00Z"));
  assert.equal(deadlineStatus(proposal.finish, "2026-09-28T13:00:00Z", 0), "planningLate");
  const otherCenter = { ...centers[0], id: "C2", line_id: "X" };
  const otherCap = { ...cap[0], work_center_id: "C2", rate: 100, setup_minutes: 30 };
  const changed = proposeSchedule(item, lines[1], sunday + 6 * hour,
    [], [...centers, otherCenter], [...cap, otherCap], 0, workweek);
  assert.equal(changed.rate, 100);
  assert.equal(changed.setupMs, 30 * 60_000);
  assert.equal(changed.finish, Date.parse("2026-09-27T16:30:00Z"));
});

test("working-time gap fit includes setup, keeps booked jobs fixed, and manual equals drag", () => {
  const item = { ...orders[0], id: "NEW", unit: "piece", target_quantity: 175 };
  const cap = [{ ...capabilities[0], setup_minutes: 60 }]; // 7h production + 1h setup
  const booked = [{ ...orders[1], id: "B", start_time: "2026-09-28T10:00:00Z",
    expected_finish: "2026-09-28T12:00:00Z" }];
  const before = structuredClone(booked);
  const schedule = sortedLineSchedule(lines[0], booked, centers, cap);
  assert.equal(firstAvailable(schedule, sunday + 4 * hour, 8 * hour,
    Date.parse("2026-09-28T10:00:00Z"), workweek).error, "planningNoFit");
  assert.equal(firstAvailable(schedule, sunday + 4 * hour, 7 * hour,
    Date.parse("2026-09-28T10:00:00Z"), workweek).finish,
    Date.parse("2026-09-28T10:00:00Z"));
  const manual = proposeSchedule(item, lines[0], sunday + 4 * hour,
    booked, centers, cap, 0, workweek);
  const drag = previewPlacement(item, lines[0], sunday + 4 * hour,
    booked, centers, cap, { from: sunday, until: sunday + 48 * hour,
      increment: 15 * 60_000, now: 0, calendar: workweek });
  assert.equal(manual.error, "planningOverlap");
  assert.equal(drag.error, "planningNoFit");
  assert.deepEqual(booked, before);
  const noBookingManual = proposeSchedule(item, lines[0], sunday + 4 * hour,
    [], centers, cap, 0, workweek);
  const noBookingDrag = previewPlacement(item, lines[0], sunday + 4 * hour,
    [], centers, cap, { from: sunday, until: sunday + 48 * hour,
      increment: 15 * 60_000, now: 0, calendar: workweek });
  assert.equal(noBookingManual.finish, noBookingDrag.finish);
  assert.equal(noBookingDrag.finish - noBookingDrag.start, 23 * hour);
  const closedDrop = previewPlacement(item, lines[0], sunday + 12 * hour,
    [], centers, cap, { from: sunday, until: sunday + 48 * hour,
      increment: 15 * 60_000, now: 0, calendar: workweek });
  assert.equal(closedDrop.start, Date.parse("2026-09-28T08:00:00Z"));
  assert.notEqual(closedDrop.requestedStart, closedDrop.start);
});

test("Gantt renders closed periods and setup inside the real elapsed reservation in both languages", () => {
  const item = { ...orders[1], start_time: "2026-09-27T15:00:00Z",
    expected_finish: "2026-09-28T09:00:00Z" };
  const calendarSnapshot = { ...snapshot,
    factory: { ...snapshot.factory, working_days_mask: 31,
      workday_start: "08:00:00", workday_end: "17:00:00" },
    tables: { ...snapshot.tables, production_orders: [item],
      work_center_capabilities: [{ ...capabilities[0], setup_minutes: 60 }] } };
  for (const [lang, dictionary] of [["en", en], ["ar", ar]]) {
    const html = renderToStaticMarkup(createElement(ProductionPlanning, {
      snapshot: calendarSnapshot, lang, t: (key) => dictionary[key] || key,
      can: () => true, command: async () => {}, initialItemId: item.id }));
    assert.match(html, /planning-closed-time/);
    assert.match(html, /planning-setup-segment/);
    assert.match(html, /planning-timeline-scroll" dir="ltr"/);
    assert.ok(html.includes(dictionary.planningTotalWorking));
  }
});

test("sorted jobs expose a free middle gap and reject a job too large for it", () => {
  const start = Date.parse("2026-10-09T08:00:00Z");
  const booked = [
    { ...orders[1], id: "A", start_time: new Date(start).toISOString(),
      expected_finish: new Date(start + 2 * 60 * 60_000).toISOString() },
    { ...orders[1], id: "B", start_time: new Date(start + 5 * 60 * 60_000).toISOString(),
      expected_finish: new Date(start + 8 * 60 * 60_000).toISOString() },
  ];
  const schedule = sortedLineSchedule(lines[0], booked.reverse(), centers, capabilities);
  assert.deepEqual(schedule.map((slot) => slot.order.id), ["A", "B"]);
  assert.deepEqual(freeGaps(schedule, start + 2 * 60 * 60_000, start + 8 * 60 * 60_000).gaps,
    [{ start: start + 2 * 60 * 60_000, finish: start + 5 * 60 * 60_000 }]);
  assert.equal(firstAvailable(schedule, start + 2 * 60 * 60_000, 2 * 60 * 60_000).start,
    start + 2 * 60 * 60_000);
  assert.equal(proposeSchedule({ ...orders[1], id: "C", target_quantity: 100 }, lines[0],
    start + 2 * 60 * 60_000, booked, centers, capabilities).error, "planningOverlap");
  assert.equal(firstAvailable(schedule, start + 2 * 60 * 60_000, 4 * 60 * 60_000).start,
    start + 8 * 60 * 60_000);
});

test("line changes, start edits, deadlines and started work are evaluated from one proposal", () => {
  const item = { ...orders[0], unit: "piece", target_quantity: 25 };
  const at = Date.parse("2026-10-09T08:00:00Z");
  assert.equal(proposeSchedule(item, lines[1], at, [], centers, capabilities).error, "planningIncompatibleLine");
  assert.equal(proposeSchedule(item, lines[0], at + 60 * 60_000, [], centers, capabilities).finish,
    at + 2 * 60 * 60_000);
  assert.equal(deadlineStatus(at + 2 * 60 * 60_000, "2026-10-09T11:00:00Z", at), "planningAtRisk");
  assert.equal(deadlineStatus(at + 4 * 60 * 60_000, "2026-10-09T11:00:00Z", at), "planningLate");
  assert.equal(proposeSchedule({ ...item, status: "active" }, lines[0], at, [], centers, capabilities).error,
    "planningAlreadyStarted");
});

test("existing overlapping jobs remain visibly identifiable without moving them", () => {
  const at = Date.parse("2026-10-09T08:00:00Z");
  const booked = [
    { ...orders[1], id: "A", start_time: new Date(at).toISOString(),
      expected_finish: new Date(at + 3 * 60 * 60_000).toISOString() },
    { ...orders[1], id: "B", start_time: new Date(at + 60 * 60_000).toISOString(),
      expected_finish: new Date(at + 4 * 60 * 60_000).toISOString() },
  ];
  const schedule = sortedLineSchedule(lines[0], booked, centers, capabilities);
  assert.deepEqual([...overlappingItems(schedule)].sort(), ["A", "B"]);
  assert.equal(proposeSchedule({ ...orders[1], id: "C" }, lines[0], at + 2 * 60 * 60_000,
    booked, centers, capabilities).error, "planningOverlap");
});

test("one request card contains its separate product items in English and Arabic", () => {
  const secondItem = { ...orders[0], id: "O3", product_id: "Q", unit: "piece", target_quantity: 500 };
  const multi = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [orders[0], secondItem, orders[1]],
    products: [...snapshot.tables.products, { id: "Q", name: "Second product", name_ar: "منتج ثانٍ" }],
  } };
  const groups = groupPlanningRequests(multi.tables.production_orders, requests);
  assert.equal(groups.length, 2);
  assert.deepEqual(groups[0].items.map((item) => item.id), ["O1", "O3"]);
  for (const [lang, dictionary, name] of [["en", en, "Second product"], ["ar", ar, "منتج ثانٍ"]]) {
    const html = renderToStaticMarkup(createElement(ProductionPlanning, { snapshot: multi,
      t: (key) => dictionary[key] || key, lang, can: () => true, command: async () => {} }));
    assert.equal((html.match(/class="planning-request-card"/g) || []).length, 2);
    const firstCard = html.split('class="planning-request-card"')[1].split('</article>')[0];
    assert.match(firstCard, /PO-1/);
    assert.match(firstCard, new RegExp(name));
    assert.equal((firstCard.match(/class="planning-product-card"/g) || []).length, 2);
  }
});

function interactivePlanner(testSnapshot, initial = {}, command = async () => {}) {
  globalThis.document ??= { activeElement: null };
  globalThis.HTMLButtonElement ??= class HTMLButtonElement {};
  globalThis.Element ??= class Element {};
  const state = [initial.item ?? null, initial.line ?? "", initial.start ?? "", false, "",
    initial.zoom ?? 1, Date.parse(initial.anchor ?? "2026-10-09T00:00:00Z"),
    initial.lineFilter ?? "", initial.priorityFilter ?? "", initial.productFilter ?? "", initial.dragging ?? null,
    initial.hover ?? null, initial.optimistic ?? null, null, null, null, initial.panning ?? false,
    initial.pendingReason ?? null, initial.reasonCode ?? "", initial.reasonNote ?? "",
    initial.history ?? [], false, initial.slotSearch ?? null, initial.slotChoice ?? null];
  const updates = [];
  const fakeReact = { useState: (() => { let index = 0;
    return (fallback) => { const position = index++; return [state[position] ?? fallback,
      (value) => updates.push({ position, value })]; }; })(),
    useEffect: () => {}, useRef: () => ({ current: null }) };
  const moduleWithHooks = { exports: {} };
  new Function("require", "module", "exports", bundled.outputFiles[0].text)(
    (name) => name === "react" ? fakeReact : require(name), moduleWithHooks, moduleWithHooks.exports);
  return { tree: moduleWithHooks.exports.default({ snapshot: testSnapshot,
    t: (key) => (initial.lang === "ar" ? ar : en)[key] || key,
    lang: initial.lang ?? "en", can: () => true, command }), updates };
}
function allNodes(node, predicate) {
  if (!node || typeof node !== "object") return [];
  if (Array.isArray(node)) return node.flatMap((child) => allNodes(child, predicate));
  return [...(predicate(node) ? [node] : []), ...allNodes(node.props?.children, predicate)];
}

test("locked planned items show an unlock action and cannot drag, edit, or unschedule in EN/AR", () => {
  const locked = { ...orders[1], expected_finish: "2026-10-08T10:00:00Z",
    planning_locked_at: "2026-09-28T08:00:00Z", planning_locked_by_name: "Ahmad" };
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [orders[0], locked] } };
  for (const lang of ["en", "ar"]) {
    const { tree } = interactivePlanner(visual,
      { item: "O2", line: "L", start: "2026-10-08T08:00", lang });
    const card = allNodes(tree, (node) => node.props?.className?.startsWith("planning-product-card"))
      .find((node) => node.props?.title?.includes("Ahmad"));
    assert.equal(card.props.draggable, false);
    const drawer = allNodes(tree, (node) => node.props?.className === "planning-drawer")[0];
    assert.ok(drawer);
    assert.ok(allNodes(drawer, (node) => node.type === "button" &&
      node.props?.children === (lang === "ar" ? ar.planningUnlockPlan : en.planningUnlockPlan)).length);
    assert.ok(allNodes(drawer, (node) => node.type === "select" &&
      node.props.disabled).length);
    assert.ok(allNodes(drawer, (node) => node.type === "input" &&
      node.props.type === "datetime-local" && node.props.disabled).length);
    const unschedule = allNodes(drawer, (node) => node.type === "button" &&
      node.props.children === (lang === "ar" ? ar.planningUnschedule : en.planningUnschedule))[0];
    assert.equal(unschedule.props.disabled, true);
  }
});

test("unlocking a future planned item calls only the lock command", async () => {
  const locked = { ...orders[1], planning_locked_at: "2026-09-28T08:00:00Z",
    planning_locked_by_name: "Ahmad" };
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: [locked] } };
  const saved = [];
  const { tree } = interactivePlanner(visual,
    { item: "O2", line: "L", start: "2026-10-08T08:00" },
    async (name, args) => saved.push({ name, args }));
  const unlock = allNodes(tree, (node) => node.type === "button" &&
    node.props?.children === en.planningUnlockPlan)[0];
  await unlock.props.onClick();
  assert.deepEqual(saved, [{ name: "set_plan_lock",
    args: { factory: "F", item: "O2", locked: false } }]);
});

test("moving a planned Gantt block asks for a reason and cancellation restores its position", async () => {
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [{ ...orders[1], expected_finish: "2026-10-08T10:00:00Z" }] } };
  const saved = [];
  const { tree, updates } = interactivePlanner(visual,
    { dragging: "O2", anchor: "2026-10-08T00:00:00Z" },
    async (name, args) => saved.push({ name, args }));
  const lane = allNodes(tree, (node) => node.props?.className === "planning-lane-track")[0];
  lane.props.onDrop({ preventDefault() {}, dataTransfer: { getData: () => "O2" },
    clientX: 500, currentTarget: { getBoundingClientRect: () => ({ left: 0, width: 1000 }) } });
  assert.equal(saved.length, 0);
  const pending = updates.find((update) => update.position === 17)?.value;
  assert.deepEqual(pending, { source: "drop", item: "O2", target_line: "L",
    planned_start: "2026-10-08T12:00:00.000Z" });
  assert.ok(updates.some((update) => update.position === 12 && update.value?.id === "O2"));
  const modal = interactivePlanner(visual, { pendingReason: pending,
    optimistic: { id: "O2", line_id: "L", start_time: pending.planned_start,
      expected_finish: "2026-10-08T14:00:00.000Z" } });
  const cancel = allNodes(modal.tree, (node) => node.type === "button" &&
    node.props?.children === en.cancel)[0];
  cancel.props.onClick();
  assert.ok(modal.updates.some((update) => update.position === 12 && update.value === null));
  assert.equal(saved.length, 0);
});

test("manual start edits and unscheduling require a reason", () => {
  const planned = { ...orders[1], expected_finish: "2026-10-08T10:00:00Z" };
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: [planned] } };
  const { tree, updates } = interactivePlanner(visual,
    { item: "O2", line: "L", start: "2026-10-08T12:00" });
  const form = allNodes(tree, (node) => node.type === "form")[0];
  form.props.onSubmit({ preventDefault() {} });
  assert.equal(updates.find((update) => update.position === 17)?.value.source, "save");
  const unschedule = allNodes(tree, (node) => node.type === "button" &&
    node.props?.children === en.planningUnschedule)[0];
  unschedule.props.onClick();
  assert.deepEqual(updates.filter((update) => update.position === 17).at(-1)?.value,
    { source: "unschedule", item: "O2", target_line: null, planned_start: null });
});

test("a capable line change requests a reason before changing either line or finish", () => {
  const moved = { ...orders[1], expected_finish: "2026-10-08T10:00:00Z" };
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [moved],
    work_centers: [...centers, { ...centers[0], id: "C2", line_id: "X" }],
    work_center_capabilities: [...capabilities,
      { work_center_id: "C2", product_id: "P", rate: 50, rate_unit: "piece" }] } };
  const saved = [];
  const { tree, updates } = interactivePlanner(visual,
    { item: "O2", line: "X", start: "2026-10-09T12:00" },
    async (name, args) => saved.push({ name, args }));
  const form = allNodes(tree, (node) => node.type === "form")[0];
  form.props.onSubmit({ preventDefault() {} });
  assert.equal(saved.length, 0);
  assert.deepEqual(updates.find((update) => update.position === 17)?.value,
    { source: "save", item: "O2", target_line: "X",
      planned_start: "2026-10-09T12:00:00.000Z" });
});

test("history distinguishes initial from current plan and translates reasons in EN/AR", () => {
  const current = { ...orders[1], start_time: "2026-10-09T12:00:00Z",
    expected_finish: "2026-10-09T14:00:00Z" };
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: [current] } };
  const history = [
    { revision_no: 1, event: "initial", before_line_id: null, before_start: null,
      before_finish: null, after_line_id: "L", after_start: "2026-10-08T08:00:00Z",
      after_finish: "2026-10-08T10:00:00Z", reason_code: null, reason_note: null,
      changed_by_name: "Ahmad", changed_at: "2026-09-28T08:00:00Z" },
    { revision_no: 2, event: "replanned", before_line_id: "L",
      before_start: "2026-10-08T08:00:00Z", before_finish: "2026-10-08T10:00:00Z",
      after_line_id: "L", after_start: "2026-10-09T12:00:00Z",
      after_finish: "2026-10-09T14:00:00Z", reason_code: "priority_change",
      reason_note: null, changed_by_name: "Ahmad", changed_at: "2026-09-28T09:00:00Z" },
  ];
  for (const [lang, dict] of [["en", en], ["ar", ar]]) {
    const { tree } = interactivePlanner(visual,
      { item: "O2", line: "L", start: "2026-10-09T12:00", history, lang });
    const html = renderToStaticMarkup(tree);
    assert.ok(html.includes(dict.planningInitialPlan));
    assert.ok(html.includes(dict.planningCurrentPlan));
    assert.ok(html.includes(dict.planningReason_priority_change));
    assert.ok(html.includes("Ahmad"));
    if (lang === "ar") assert.ok(html.includes(lines[0].name_ar));
  }
});

test("reason save sends an atomic revision command with the selected category", async () => {
  const saved = [];
  const { tree } = interactivePlanner(snapshot, { pendingReason: {
    source: "drop", item: "O2", target_line: "L", planned_start: "2026-10-08T12:00:00Z",
  }, reasonCode: "priority_change" }, async (name, args) => saved.push({ name, args }));
  const dialog = allNodes(tree, (node) => node.props?.className === "planning-reason-dialog")[0];
  const form = allNodes(dialog, (node) => node.type === "form")[0];
  await form.props.onSubmit({ preventDefault() {} });
  assert.deepEqual(saved, [{ name: "revise_product_plan", args: {
    factory: "F", item: "O2", target_line: "L", planned_start: "2026-10-08T12:00:00Z",
    reason_code: "priority_change", reason_note: "",
  } }]);
});

test("re-scheduling after an unschedule is replanning for both manual and drag paths", () => {
  const waitingAgain = { ...orders[0], planning_ever_scheduled: true };
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [waitingAgain],
    work_center_capabilities: [{ ...capabilities[0], rate: 150, rate_unit: "meter" }] } };
  const saved = [];
  const manual = interactivePlanner(visual,
    { item: "O1", line: "L", start: "2026-10-09T08:00" },
    async (name, args) => saved.push({ name, args }));
  allNodes(manual.tree, (node) => node.type === "form")[0].props.onSubmit({ preventDefault() {} });
  assert.equal(manual.updates.find((update) => update.position === 17)?.value.source, "save");
  const drag = interactivePlanner(visual, { dragging: "O1" },
    async (name, args) => saved.push({ name, args }));
  const lane = allNodes(drag.tree, (node) => node.props?.className === "planning-lane-track")[0];
  lane.props.onDrop({ preventDefault() {}, dataTransfer: { getData: () => "O1" },
    clientX: 500, currentTarget: { getBoundingClientRect: () => ({ left: 0, width: 1000 }) } });
  assert.equal(drag.updates.find((update) => update.position === 17)?.value.source, "drop");
  assert.equal(saved.length, 0);
});

test("clicking or dragging an item targets only its own product and quantity", () => {
  const other = { ...orders[0], id: "O3", product_id: "Q", unit: "piece", target_quantity: 500 };
  const multi = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [orders[0], other],
    products: [...snapshot.tables.products, { id: "Q", name: "Second product" }],
  } };
  const { tree, updates } = interactivePlanner(multi);
  const cards = allNodes(tree, (node) => node.type === "button" &&
    node.props.className?.startsWith("planning-product-card"));
  assert.equal(cards.length, 2);
  assert.match(cards[1].props["aria-label"], /Second product · 500 pcs/);
  cards[1].props.onClick();
  assert.deepEqual(updates.find((update) => update.position === 0), { position: 0, value: "O3" });
  let dragged;
  cards[1].props.onDragStart({ dataTransfer: { setData: (type, id) => { dragged = { type, id }; } } });
  assert.deepEqual(dragged, { type: "text/plain", id: "O3" });
});

test("a scheduled sibling remains clickable and draggable for independent rescheduling", () => {
  const sibling = { ...orders[1], id: "O3", request_id: "R1" };
  const multi = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [orders[0], sibling] } };
  const { tree, updates } = interactivePlanner(multi);
  const cards = allNodes(tree, (node) => node.type === "button" &&
    node.props.className?.startsWith("planning-product-card"));
  assert.equal(cards.length, 2);
  assert.equal(cards[1].props.draggable, true);
  cards[1].props.onClick();
  assert.ok(updates.some((update) => update.position === 0 && update.value === "O3"));
  assert.ok(!updates.some((update) => update.position === 0 && update.value === "O1"));
});

test("drop rejects an incompatible line and directly saves only the dragged item on a capable line", async () => {
  const meterCapabilities = [{ ...capabilities[0], rate: 150, rate_unit: "meter" }];
  const testSnapshot = { ...snapshot, tables: { ...snapshot.tables,
    work_center_capabilities: meterCapabilities, production_orders: [orders[0]] } };
  const saved = [];
  const { tree, updates } = interactivePlanner(testSnapshot, { dragging: "O1" },
    async (name, args) => { saved.push({ name, args }); });
  const tracks = allNodes(tree, (node) => node.type === "div" && node.props.className === "planning-lane-track");
  assert.equal(tracks.length, 2);
  let prevented = 0;
  const event = { preventDefault: () => prevented++, dataTransfer: { getData: () => "O1" },
    clientX: 500, currentTarget: { getBoundingClientRect: () => ({ left: 0, width: 1000 }) } };
  tracks[1].props.onDrop(event);
  assert.ok(updates.some((update) => update.position === 4 && update.value === "planningIncompatibleLine"));
  assert.equal(saved.length, 0);
  tracks[0].props.onDrop(event);
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(saved, [{ name: "plan_product_item", args: {
    factory: "F", item: "O1", target_line: "L", planned_start: "2026-10-09T12:00:00.000Z",
  } }]);
  assert.ok(!updates.some((update) => update.position === 0 && update.value === "O1"));
  assert.ok(prevented >= 2);
});

test("meter and piece rates schedule independent items without shifting existing jobs", () => {
  const at = Date.parse("2026-10-09T08:00:00Z");
  const line = lines[0];
  const machine = centers[0];
  const meter = { ...orders[0], id: "M", target_quantity: 300 };
  const piece = { ...orders[0], id: "P2", unit: "piece", target_quantity: 500 };
  const rates = [
    { work_center_id: machine.id, product_id: meter.product_id, rate: 150, rate_unit: "meter" },
    { work_center_id: machine.id, product_id: "Q", rate: 250, rate_unit: "piece" },
  ];
  piece.product_id = "Q";
  const booked = [
    { ...orders[1], id: "A", start_time: new Date(at).toISOString(),
      expected_finish: new Date(at + 2 * 60 * 60_000).toISOString() },
    { ...orders[1], id: "B", start_time: new Date(at + 4 * 60 * 60_000).toISOString(),
      expected_finish: new Date(at + 6 * 60 * 60_000).toISOString() },
  ];
  const before = structuredClone(booked);
  assert.equal(durationMs(meter, line, centers, rates).ms, 2 * 60 * 60_000);
  assert.equal(durationMs(piece, line, centers, rates).ms, 2 * 60 * 60_000);
  const gap = proposeSchedule(meter, line, at + 2 * 60 * 60_000, booked, centers, rates);
  assert.equal(gap.finish, at + 4 * 60 * 60_000);
  assert.equal(proposeSchedule(piece, line, at + 3 * 60 * 60_000, booked, centers, rates).error,
    "planningOverlap");
  const after = proposeSchedule(piece, line, at + 6 * 60 * 60_000, [...booked,
    { ...meter, line_id: "L", start_time: new Date(gap.start).toISOString(),
      expected_finish: new Date(gap.finish).toISOString() }], centers, rates);
  assert.equal(after.finish, at + 8 * 60 * 60_000);
  assert.deepEqual(booked, before);
});

test("two items in one request may use different capable lines and starts", () => {
  const meter = { ...orders[0], id: "M", target_quantity: 300 };
  const piece = { ...orders[0], id: "P2", product_id: "Q", unit: "piece", target_quantity: 500 };
  const secondLine = { id: "L2", name: "Piece line" };
  const twoCenters = [...centers, { id: "C2", line_id: "L2", status: "idle", archived: false }];
  const rates = [
    { work_center_id: "C", product_id: "P", rate: 150, rate_unit: "meter" },
    { work_center_id: "C2", product_id: "Q", rate: 250, rate_unit: "piece" },
  ];
  assert.equal(groupPlanningRequests([meter, piece], requests)[0].items.length, 2);
  assert.deepEqual(capableLines(meter, [lines[0], secondLine], twoCenters, rates).map((line) => line.id), ["L"]);
  assert.deepEqual(capableLines(piece, [lines[0], secondLine], twoCenters, rates).map((line) => line.id), ["L2"]);
  const firstStart = Date.parse("2026-10-09T08:00:00Z");
  const secondStart = Date.parse("2026-10-09T12:00:00Z");
  assert.equal(proposeSchedule(meter, lines[0], firstStart, [], twoCenters, rates).finish,
    firstStart + 2 * 60 * 60_000);
  assert.equal(proposeSchedule(piece, secondLine, secondStart, [], twoCenters, rates).finish,
    secondStart + 2 * 60 * 60_000);
});

test("request header stays focused and child blocks show only product and quantity", () => {
  const html = renderToStaticMarkup(createElement(ProductionPlanning, { snapshot,
    t: (key) => en[key] || key, lang: "en", can: () => true, command: async () => {} }));
  const firstCard = html.split('class="planning-request-card"')[1].split('</article>')[0];
  assert.match(firstCard, /Pipe project/);
  assert.match(firstCard, /Required By/);
  assert.match(firstCard, /Urgent/);
  assert.match(firstCard, /1 waiting/);
  assert.match(firstCard, /PVC pipe/);
  assert.match(firstCard, /300 m/);
  assert.doesNotMatch(firstCard, /Requested By|Production rate|Line \/ planned start/);
});

test("catalog colors are stable, distinct, and shared by queue, Gantt, and details", () => {
  const catalog = [{ id: "P" }, { id: "Q" }, { id: "R" }];
  const first = planningProductTones(catalog);
  const reordered = planningProductTones([...catalog].reverse());
  assert.deepEqual(first.get("P"), reordered.get("P"));
  assert.equal(new Set(catalog.map((product) => first.get(product.id).surface)).size, 3);
  const html = renderToStaticMarkup(createElement(ProductionPlanning, { snapshot,
    t: (key) => en[key] || key, lang: "en", can: () => true,
    command: async () => {}, initialItemId: "O2" }));
  assert.ok(html.split(`--planning-product-bg:${planningProductTones(snapshot.tables.products).get("P").surface}`).length >= 4);
});

test("preview width doubles on a line with half the product rate", () => {
  const item = { ...orders[0], target_quantity: 1000 };
  const secondLine = { id: "L2", name: "Second line" };
  const twoCenters = [...centers, { id: "C2", line_id: "L2", archived: false, status: "idle" }];
  const rates = [
    { work_center_id: "C", product_id: "P", rate: 200, rate_unit: "meter" },
    { work_center_id: "C2", product_id: "P", rate: 100, rate_unit: "meter" },
  ];
  const at = Date.parse("2026-10-09T08:00:00Z");
  const options = { from: Date.parse("2026-10-09T00:00:00Z"),
    until: Date.parse("2026-10-10T00:00:00Z"), now: Date.parse("2026-10-08T00:00:00Z") };
  const fast = previewPlacement(item, lines[0], at, [], twoCenters, rates, options);
  const slow = previewPlacement(item, secondLine, at, [], twoCenters, rates, options);
  assert.equal(fast.durationMs, 5 * 60 * 60_000);
  assert.equal(slow.durationMs, 10 * 60 * 60_000);
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [item], production_lines: [lines[0], secondLine],
    work_centers: twoCenters, work_center_capabilities: rates } };
  const widths = [fast, slow].map((preview, index) => {
    const { tree } = interactivePlanner(visual, { dragging: "O1", hover: {
      itemId: "O1", lineId: index ? "L2" : "L", ...preview,
    } });
    const ghost = allNodes(tree, (node) => node.type === "span" &&
      node.props.className?.startsWith("planning-drag-ghost"))[0];
    assert.ok(ghost);
    return parseFloat(ghost.props.style.width);
  });
  assert.equal(widths[1], widths[0] * 2);
});

test("scheduled Gantt block width reflects its recorded production interval", () => {
  const at = Date.parse("2026-10-09T08:00:00Z");
  const timed = [
    { ...orders[1], id: "SHORT", start_time: new Date(at).toISOString(),
      expected_finish: new Date(at + 2 * 60 * 60_000).toISOString() },
    { ...orders[1], id: "LONG", start_time: new Date(at + 3 * 60 * 60_000).toISOString(),
      expected_finish: new Date(at + 11 * 60 * 60_000).toISOString() },
  ];
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: timed } };
  const { tree } = interactivePlanner(visual);
  const blocks = allNodes(tree, (node) => node.props?.className?.startsWith("planning-gantt-block"));
  assert.equal(blocks.length, 2);
  assert.equal(parseFloat(blocks[1].props.style.width), parseFloat(blocks[0].props.style.width) * 4);
});

test("preview fits a middle gap, rejects a too-large block, and accepts after the last job", () => {
  const at = Date.parse("2026-10-09T08:00:00Z");
  const booked = [
    { ...orders[1], id: "A", start_time: new Date(at).toISOString(),
      expected_finish: new Date(at + 2 * 60 * 60_000).toISOString() },
    { ...orders[1], id: "B", start_time: new Date(at + 7 * 60 * 60_000).toISOString(),
      expected_finish: new Date(at + 10 * 60 * 60_000).toISOString() },
  ];
  const rates = [{ work_center_id: "C", product_id: "P", rate: 100, rate_unit: "meter" }];
  const item = { ...orders[0], target_quantity: 300 };
  const options = { from: at, until: at + 20 * 60 * 60_000, now: at - 60 * 60_000 };
  const gap = previewPlacement(item, lines[0], at + 2 * 60 * 60_000, booked, centers, rates, options);
  assert.equal(gap.finish, at + 5 * 60 * 60_000);
  assert.equal(previewPlacement({ ...item, target_quantity: 600 }, lines[0],
    at + 2 * 60 * 60_000, booked, centers, rates, options).error, "planningNoFit");
  assert.equal(previewPlacement({ ...item, target_quantity: 400 }, lines[0],
    at + 2 * 60 * 60_000, booked, centers, rates,
    { ...options, now: at + 4 * 60 * 60_000 }).error, "planningNoFit");
  assert.equal(previewPlacement(item, lines[0], at + 10 * 60 * 60_000,
    booked, centers, rates, options).finish, at + 13 * 60 * 60_000);
  assert.equal(previewPlacement(item, lines[1], at + 10 * 60 * 60_000,
    booked, centers, rates, options).error, "planningIncompatibleLine");
});

test("server rejection clears the optimistic placement and leaves the original item", async () => {
  const rates = [{ work_center_id: "C", product_id: "P", rate: 150, rate_unit: "meter" }];
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    work_center_capabilities: rates, production_orders: [orders[0]] } };
  const { tree, updates } = interactivePlanner(visual, { dragging: "O1" }, async () => {
    throw new Error("planningOverlap");
  });
  const track = allNodes(tree, (node) => node.type === "div" &&
    node.props.className === "planning-lane-track")[0];
  track.props.onDrop({ preventDefault() {}, dataTransfer: { getData: () => "O1" }, clientX: 500,
    currentTarget: { getBoundingClientRect: () => ({ left: 0, width: 1000 }) } });
  await new Promise((resolve) => setImmediate(resolve));
  const placements = updates.filter((update) => update.position === 12).map((update) => update.value);
  assert.equal(placements[0].line_id, "L");
  assert.equal(placements.at(-1), null);
  assert.ok(updates.some((update) => update.position === 4 && update.value === "planningOverlap"));
  assert.equal(orders[0].line_id, null);
});

test("Arabic timeline keeps chronological left-to-right positions", () => {
  const timed = [
    { ...orders[1], id: "A", start_time: "2026-10-09T08:00:00Z", expected_finish: "2026-10-09T10:00:00Z" },
    { ...orders[1], id: "B", start_time: "2026-10-09T12:00:00Z", expected_finish: "2026-10-09T14:00:00Z" },
  ];
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: timed } };
  const { tree } = interactivePlanner(visual, { lang: "ar" });
  assert.equal(allNodes(tree, (node) => node.props?.className === "planning-timeline" &&
    node.props.dir === "ltr").length, 1);
  assert.equal(allNodes(tree, (node) => node.props?.className === "planning-timeline-scroll" &&
    node.props.dir === "ltr").length, 1);
  const blocks = allNodes(tree, (node) => node.props?.className?.startsWith("planning-gantt-block"));
  assert.equal(blocks.length, 2);
  assert.ok(parseFloat(blocks[0].props.style.left) < parseFloat(blocks[1].props.style.left));
});

test("one request splits its distinct items between horizontal waiting and progressed rows", () => {
  const sibling = { ...orders[1], id: "O3", request_id: "R1", product_id: "Q" };
  const multi = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [orders[0], sibling],
    products: [...snapshot.tables.products, { id: "Q", name: "Second product" }],
  } };
  const html = renderToStaticMarkup(createElement(ProductionPlanning, { snapshot: multi,
    t: (key) => en[key] || key, lang: "en", can: () => true, command: async () => {} }));
  const waiting = html.split('class="planning-section planning-requests-waiting"')[1].split('</section>')[0];
  const progressed = html.split('class="planning-section planning-requests-progressed"')[1].split('</section>')[0];
  assert.match(waiting, /Pipe project/);
  assert.match(progressed, /Pipe project/);
  assert.match(waiting, /PVC pipe/);
  assert.doesNotMatch(waiting, /Second product/);
  assert.match(progressed, /Second product/);
  assert.doesNotMatch(progressed, /PVC pipe/);
  assert.match(waiting, /1 waiting/);
  assert.match(progressed, /1 \/ 2 progressed/);
  assert.match(waiting, /planning-list/);
  assert.match(progressed, /planning-list/);
  const scheduled = { ...orders[0], line_id: "L", start_time: "2026-10-08T12:00:00Z" };
  const allPlaced = { ...multi, tables: { ...multi.tables, production_orders: [scheduled, sibling] } };
  const placedHtml = renderToStaticMarkup(createElement(ProductionPlanning, { snapshot: allPlaced,
    t: (key) => en[key] || key, lang: "en", can: () => true, command: async () => {} }));
  const emptyTop = placedHtml.split('class="planning-section planning-requests-waiting"')[1].split('</section>')[0];
  const fullBottom = placedHtml.split('class="planning-section planning-requests-progressed"')[1].split('</section>')[0];
  assert.doesNotMatch(emptyTop, /Pipe project/);
  assert.match(fullBottom, /2 \/ 2 progressed/);
  assert.equal((fullBottom.match(/class="planning-product-card"/g) || []).length, 2);
});

test("optimistic placement moves only the target item into its planned request card", () => {
  const sibling = { ...orders[0], id: "O3", product_id: "Q" };
  const multi = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [orders[0], sibling],
    products: [...snapshot.tables.products, { id: "Q", name: "Second product" }],
  } };
  const { tree } = interactivePlanner(multi, { optimistic: { id: "O1", line_id: "L",
    start_time: "2026-10-09T08:00:00Z", expected_finish: "2026-10-09T10:00:00Z" } });
  const waiting = allNodes(tree, (node) => node.props?.className === "planning-requests-waiting" ||
    node.props?.className === "planning-section planning-requests-waiting")[0];
  const progressed = allNodes(tree, (node) => node.props?.className === "planning-section planning-requests-progressed")[0];
  const waitingCards = allNodes(waiting, (node) => node.props?.className?.startsWith("planning-product-card"));
  const progressedCards = allNodes(progressed, (node) => node.props?.className?.startsWith("planning-product-card"));
  assert.equal(waitingCards.length, 1);
  assert.match(waitingCards[0].props["aria-label"], /Second product/);
  assert.equal(progressedCards.length, 1);
  assert.match(progressedCards[0].props["aria-label"], /PVC pipe.*Planned/);
});

test("board status uses stored item state and disables started or completed dragging", () => {
  assert.equal(planningBoardStatus(orders[0]), "planningWaiting");
  assert.equal(planningBoardStatus(orders[1]), "planningPlannedState");
  assert.equal(planningBoardStatus({ ...orders[1], status: "active" }), "planningInProduction");
  assert.equal(planningBoardStatus({ ...orders[1], status: "completed" }), "planningCompleted");
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: [
    orders[0], orders[1], { ...orders[1], id: "ACTIVE", status: "active" },
    { ...orders[1], id: "DONE", status: "completed" },
  ] } };
  const { tree } = interactivePlanner(visual);
  const cards = allNodes(tree, (node) => node.props?.className?.startsWith("planning-product-card"));
  assert.equal(cards.length, 4);
  assert.equal(cards.filter((card) => card.props.draggable).length, 2);
  assert.equal(cards.filter((card) => card.props.disabled).length, 0);
  const labels = cards.map((card) => card.props["aria-label"]);
  assert.ok(labels.some((label) => label.includes("In production")));
  assert.ok(labels.some((label) => label.includes("Completed")));
});

test("full-width board offers half-hour through four-week scales with a derived end", () => {
  const { tree, updates } = interactivePlanner(snapshot);
  const sections = allNodes(tree, (node) => node.type === "section" &&
    node.props.className?.startsWith("planning-section"));
  assert.deepEqual(sections.map((section) => section.props.className), [
    "planning-section planning-requests-waiting", "planning-section planning-gantt",
    "planning-section planning-requests-progressed",
  ]);
  const slider = allNodes(tree, (node) => node.props?.id === "planning-zoom-slider")[0];
  assert.deepEqual([slider.props.min, slider.props.max, slider.props.value], ["0", 5, 1]);
  slider.props.onChange({ target: { value: "5" } });
  assert.ok(updates.some((update) => update.position === 5 && update.value === 5));
  const movedStart = updates.find((update) => update.position === 6)?.value;
  assert.equal(typeof movedStart, "function");
  assert.ok(movedStart(Date.parse("2026-10-09T00:00:00Z")) < Date.parse("2026-10-09T00:00:00Z"));
  const zoomedStart = movedStart(Date.parse("2026-10-09T00:00:00Z"));
  const zoomed = interactivePlanner(snapshot, { zoom: 5,
    anchor: new Date(zoomedStart).toISOString() });
  const zoomedEnd = allNodes(zoomed.tree, (node) => node.type === "time")[0];
  assert.equal(zoomedEnd.props.dateTime,
    new Date(zoomedStart + 28 * 24 * 60 * 60_000).toISOString());
  assert.equal(zoomedStart + 14 * 24 * 60 * 60_000,
    Date.parse("2026-10-09T00:00:00Z") + 12 * 60 * 60_000);
  const close = interactivePlanner(snapshot, { zoom: 0 });
  const closeTicks = allNodes(close.tree, (node) => node.type === "span" &&
    node.props.style?.left && node.props.children === "00:30");
  assert.ok(closeTicks.length > 0);
  const wide = interactivePlanner(snapshot, { zoom: 5 });
  const wideTicks = allNodes(wide.tree, (node) => node.type === "span" && node.props.style?.left);
  assert.ok(wideTicks.length < 10);
  const timeline = allNodes(tree, (node) => node.props?.className === "planning-timeline")[0];
  assert.equal(timeline.props.style.minWidth, 1320);
});

test("future planned Gantt blocks can be dragged, while started blocks cannot", () => {
  const future = { ...orders[1], start_time: "2030-10-08T08:00:00Z",
    expected_finish: "2030-10-08T10:00:00Z" };
  const started = { ...orders[1], id: "ACTIVE", status: "active",
    start_time: "2030-10-08T12:00:00Z", expected_finish: "2030-10-08T14:00:00Z" };
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: [future, started] } };
  const { tree } = interactivePlanner(visual, { anchor: "2030-10-08T00:00:00Z" });
  const blocks = allNodes(tree, (node) => node.props?.className?.startsWith("planning-gantt-block"));
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].props.draggable, true);
  assert.equal(blocks[1].props.draggable, false);
});

test("releasing an invalid hover reports why the item returned", () => {
  const { tree, updates } = interactivePlanner(snapshot, { dragging: "O1" });
  const target = allNodes(tree, (node) => node.props?.className === "planning-lane-track")[1];
  const card = allNodes(tree, (node) => node.props?.className?.startsWith("planning-product-card"))[0];
  const event = { preventDefault() {}, clientX: 500, dataTransfer: {},
    currentTarget: { getBoundingClientRect: () => ({ left: 0, width: 1000 }) } };
  target.props.onDragOver(event);
  card.props.onDragEnd();
  assert.ok(updates.some((update) => update.position === 4 && update.value === "planningIncompatibleLine"));
  assert.ok(updates.some((update) => update.position === 15 && update.value === "O1"));
});

// ---------------------------------------------------------------------------
// Timeline navigation — pan, editable start, and scale share one visible window.
// ---------------------------------------------------------------------------
const navSpan = 24 * 60 * 60_000;
const navAnchor = Date.parse("2026-10-09T14:30:00Z"); // a deliberate non-midnight start

test("navigation helpers move the window backward and forward without snapping", () => {
  // Drag right pulls earlier time into view; drag left moves forward.
  assert.equal(panViewStart(navAnchor, navSpan, 1000, 100), navAnchor - navSpan / 10);
  assert.equal(panViewStart(navAnchor, navSpan, 1000, -100), navAnchor + navSpan / 10);
  // Wheel/trackpad right (or shift+wheel down) moves toward later time.
  assert.equal(wheelViewStart(navAnchor, navSpan, 1000, 200), navAnchor + navSpan / 5);
  assert.equal(wheelViewStart(navAnchor, navSpan, 1000, -50), navAnchor - navSpan / 20);
  // A moved start keeps its exact arbitrary time — no midnight/week normalization.
  assert.equal(panViewStart(navAnchor, navSpan, 1000, 0), navAnchor);
  // A 250px drag from 14:30 lands 6 hours earlier and keeps the :30 offset.
  assert.equal(panViewStart(navAnchor, navSpan, 1000, 250) % (30 * 60_000), navAnchor % (30 * 60_000));
});

test("zoom keeps the window centered and navigation never touches stored jobs", () => {
  const zoomed = zoomViewStart(navAnchor, navSpan, 3 * navSpan);
  assert.equal(zoomed + (3 * navSpan) / 2, navAnchor + navSpan / 2);
  // The helpers only move window positions; job data cannot pass through them.
  const booked = [{ id: "A", start_time: "2026-10-09T08:00:00Z", expected_finish: "2026-10-09T10:00:00Z" }];
  const before = structuredClone(booked);
  panViewStart(navAnchor, navSpan, 1000, 500);
  wheelViewStart(navAnchor, navSpan, 1000, 500);
  zoomViewStart(navAnchor, navSpan, 7 * 24 * 60 * 60_000);
  assert.deepEqual(booked, before);
});

test("editing the visible start moves the window exactly, including 14:30 local time", () => {
  const { tree, updates } = interactivePlanner(snapshot);
  const input = allNodes(tree, (node) => node.type === "input" &&
    node.props.type === "datetime-local" && node.props.dir === "ltr")[0];
  assert.ok(input);
  input.props.onChange({ target: { value: "2026-10-12T14:30" } });
  assert.equal(updates.find((update) => update.position === 6)?.value,
    Date.parse("2026-10-12T14:30:00Z"));
  assert.ok(!updates.some((update) => update.position === 5));
  const shifted = interactivePlanner(snapshot, { anchor: "2026-10-12T14:30:00Z" });
  const shiftedInput = allNodes(shifted.tree, (node) => node.type === "input" &&
    node.props.type === "datetime-local" && node.props.dir === "ltr")[0];
  const end = allNodes(shifted.tree, (node) => node.type === "time")[0];
  assert.equal(shiftedInput.props.value, "2026-10-12T14:30");
  assert.equal(end.props.dateTime, "2026-10-13T14:30:00.000Z");
  const qatar = interactivePlanner({ ...snapshot, factory: { ...snapshot.factory, timezone: "Asia/Qatar" } });
  const qatarInput = allNodes(qatar.tree, (node) => node.type === "input" &&
    node.props.type === "datetime-local" && node.props.dir === "ltr")[0];
  qatarInput.props.onChange({ target: { value: "2026-10-12T17:30" } });
  assert.equal(qatar.updates.find((update) => update.position === 6)?.value,
    Date.parse("2026-10-12T14:30:00Z"));
});

test("pointer panning moves the window backward/forward and leaves zoom and jobs alone", () => {
  const booked = [{ ...orders[1], id: "A", start_time: "2026-10-09T08:00:00Z",
    expected_finish: "2026-10-09T10:00:00Z" }];
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: booked } };
  const before = structuredClone(booked);
  const { tree, updates } = interactivePlanner(visual);
  const container = allNodes(tree, (node) => node.props?.className === "planning-timeline-scroll")[0];
  assert.ok(container);
  container.props.onPointerDown({ button: 0, pointerId: 7, clientX: 100, target: null,
    currentTarget: { clientWidth: 1000, setPointerCapture() {} } });
  assert.ok(updates.some((update) => update.position === 16 && update.value === true));
  container.props.onPointerMove({ pointerId: 7, clientX: 350 }); // drag right → earlier
  const panned = updates.find((update) => update.position === 6)?.value;
  assert.equal(panned, Date.parse("2026-10-09T00:00:00Z") - (250 / 1000) * navSpan);
  const moved = interactivePlanner(visual, { anchor: new Date(panned).toISOString() });
  const movedStart = allNodes(moved.tree, (node) => node.type === "input" &&
    node.props.type === "datetime-local" && node.props.dir === "ltr")[0];
  const movedEnd = allNodes(moved.tree, (node) => node.type === "time")[0];
  assert.equal(movedStart.props.value, "2026-10-08T18:00");
  assert.equal(movedEnd.props.dateTime, "2026-10-09T18:00:00.000Z");
  container.props.onPointerMove({ pointerId: 7, clientX: 1100 }); // drag far left → later
  assert.equal(updates.filter((update) => update.position === 6).length, 2);
  container.props.onPointerUp({ pointerId: 7 });
  assert.ok(updates.some((update) => update.position === 16 && update.value === false));
  assert.ok(!updates.some((update) => update.position === 5)); // zoom untouched
  assert.deepEqual(booked, before); // navigation never reschedules jobs
});

test("a Gantt window may start at an arbitrary non-midnight time and label it", () => {
  const { tree } = interactivePlanner(snapshot, { zoom: 0, anchor: "2026-10-09T14:30:00Z" });
  const labels = allNodes(tree, (node) => node.type === "span" && node.props.style?.left)
    .map((node) => node.props.children);
  assert.ok(labels.includes("14:30"));
  assert.ok(labels.includes("15:00"));
  const wide = interactivePlanner(snapshot, { zoom: 5, anchor: "2026-10-09T14:30:00Z" });
  const wideLabels = allNodes(wide.tree, (node) => node.type === "span" &&
    node.props.style?.left && typeof node.props.children === "string" && node.props.children)
    .map((node) => node.props.children);
  assert.ok(wideLabels.some((label) => label.includes("Oct 9")));
});

test("labels and closed-hours shading follow the moved window", () => {
  const calendarSnapshot = { ...snapshot,
    factory: { ...snapshot.factory, working_days_mask: 31,
      workday_start: "08:00:00", workday_end: "17:00:00" } };
  const early = interactivePlanner(calendarSnapshot, { zoom: 2, anchor: "2026-10-05T06:00:00Z" });
  const late = interactivePlanner(calendarSnapshot, { zoom: 2, anchor: "2026-10-05T10:00:00Z" });
  const closedAt = (tree) => allNodes(tree, (node) => node.props?.className === "planning-closed-time")
    .map((node) => node.props.style?.left);
  assert.notDeepEqual(closedAt(early.tree), closedAt(late.tree));
  assert.ok(closedAt(early.tree).includes("0%")); // window opens inside closed hours
  const ticksAt = (tree) => allNodes(tree, (node) => node.type === "span" &&
    node.props.style?.left && typeof node.props.children === "string" && node.props.children)
    .map((node) => node.props.children);
  assert.notDeepEqual(ticksAt(early.tree), ticksAt(late.tree)); // labels follow the window
});

test("now marker appears only when the visible window includes it and never navigates", () => {
  const aroundNow = interactivePlanner(snapshot, { anchor: new Date(Date.now() - 18 * 60 * 60_000).toISOString().slice(0, 19) + "Z" });
  const lanes = allNodes(aroundNow.tree, (node) => node.props?.className === "planning-lane-track").length;
  assert.equal(allNodes(aroundNow.tree, (node) => node.props?.className === "planning-now").length, lanes);
  const farFuture = interactivePlanner(snapshot, { anchor: "2030-10-08T00:00:00Z" });
  assert.equal(allNodes(farFuture.tree, (node) => node.props?.className === "planning-now").length, 0);
  assert.ok(!farFuture.updates.some((update) => update.position === 6));
});

test("dropping an item after panning resolves the actual visible future timestamp", async () => {
  const meterCapabilities = [{ ...capabilities[0], rate: 150, rate_unit: "meter" }];
  const testSnapshot = { ...snapshot, tables: { ...snapshot.tables,
    work_center_capabilities: meterCapabilities, production_orders: [orders[0]] } };
  const saved = [];
  const { tree } = interactivePlanner(testSnapshot,
    { dragging: "O1", anchor: "2030-10-08T06:00:00Z" },
    async (name, args) => { saved.push({ name, args }); });
  const track = allNodes(tree, (node) => node.type === "div" &&
    node.props.className === "planning-lane-track")[0];
  track.props.onDrop({ preventDefault() {}, dataTransfer: { getData: () => "O1" }, clientX: 250,
    currentTarget: { getBoundingClientRect: () => ({ left: 0, width: 1000 }) } });
  await new Promise((resolve) => setImmediate(resolve));
  // The window starts 2030-10-08 06:00; a drop one quarter in = 12:00 that day —
  // NOT relative to today's original anchor.
  assert.deepEqual(saved, [{ name: "plan_product_item", args: {
    factory: "F", item: "O1", target_line: "L", planned_start: "2030-10-08T12:00:00.000Z",
  } }]);
});

test("one compact toolbar shows editable start, derived end and scale in English and Arabic", () => {
  for (const [lang, dictionary] of [["en", en], ["ar", ar]]) {
    const html = renderToStaticMarkup(createElement(ProductionPlanning, {
      snapshot, t: (key) => dictionary[key] || key, lang, can: () => true, command: async () => {} }));
    assert.equal((html.match(/class="planning-board-toolbar"/g) || []).length, 1);
    assert.match(html, /type="datetime-local" dir="ltr"/);
    assert.match(html, /class="planning-window-end"/);
    assert.match(html, /id="planning-zoom-slider"/);
    assert.ok(html.includes(dictionary.planningVisibleStart));
    assert.ok(html.includes(dictionary.planningVisibleEnd));
    assert.ok(html.includes(dictionary.planningZoom));
    assert.ok(html.includes(dictionary.planningZoomDay));
    assert.doesNotMatch(html, /planning-time-slider|planning-time-navigation|planning-board-navigation/);
    assert.doesNotMatch(html, /type="date"|Previous period|Next period|>Today<|الفترة السابقة|الفترة التالية|>اليوم</);
    assert.match(html, /class="planning-timeline-scroll" dir="ltr"/);
  }
});

test("line capacity excludes closed hours and days in the factory timezone", () => {
  const from = Date.parse("2026-09-27T04:00:00Z"); // Sunday 07:00 in Qatar
  const until = Date.parse("2026-09-28T09:00:00Z"); // Monday 12:00 in Qatar
  const capacity = lineCapacity([], from, until, workweek, "Asia/Qatar");
  assert.deepEqual(capacity, { availableMinutes: 13 * 60, bookedMinutes: 0,
    percent: 0, incomplete: false });
  const friday = lineCapacity([], Date.parse("2026-10-02T00:00:00Z"),
    Date.parse("2026-10-03T00:00:00Z"), workweek);
  assert.equal(friday.availableMinutes, 0);
  assert.equal(friday.percent, null);
});

test("line load counts setup and production working minutes, including only visible overlap", () => {
  const rate = [{ ...capabilities[0], rate: 60, setup_minutes: 30 }];
  const item = { ...orders[1], target_quantity: 120, start_time: new Date(sunday).toISOString() };
  const duration = durationMs(item, lines[0], centers, rate);
  assert.equal(duration.setupMs, 30 * 60_000);
  assert.equal(duration.productionMs, 120 * 60_000);
  const finish = finishAfterWorkingMs(sunday, duration.totalMs, workweek);
  const full = lineCapacity([{ order: item, start: sunday, finish }], sunday, sunday + 9 * hour, workweek);
  assert.equal(full.availableMinutes, 540);
  assert.equal(full.bookedMinutes, 150);
  assert.ok(Math.abs(full.percent - 150 / 540 * 100) < 0.00001);
  const partial = lineCapacity([{ order: item, start: sunday, finish }], sunday + hour,
    sunday + 2 * hour, workweek);
  assert.deepEqual([partial.availableMinutes, partial.bookedMinutes, partial.percent], [60, 60, 100]);
  const overnight = lineCapacity([{ order: item, start: sunday + 8 * hour,
    finish: Date.parse("2026-09-28T09:00:00Z") }], sunday, sunday + 25 * hour, workweek);
  assert.equal(overnight.availableMinutes, 10 * 60);
  assert.equal(overnight.bookedMinutes, 2 * 60); // closed night is neither supply nor booking
  const spanning = { order: item, start: sunday, finish: Date.parse("2026-09-30T17:00:00Z") };
  const tuesday = Date.parse("2026-09-29T08:00:00Z");
  const oneDay = lineCapacity([spanning], tuesday, tuesday + 9 * hour, workweek);
  assert.deepEqual([oneDay.availableMinutes, oneDay.bookedMinutes, oneDay.percent], [540, 540, 100]);
  const overlap = lineCapacity([spanning, spanning], tuesday, tuesday + 9 * hour, workweek);
  assert.equal(overlap.percent, 200); // legacy overlaps remain visible as factual load
});

test("visible Planning summary counts product items and reuses deadline risk states", () => {
  const due = "2026-10-09T12:00:00Z";
  const cases = [
    { ...orders[0], id: "WAIT-1", request_id: "R1" },
    { ...orders[0], id: "WAIT-2", request_id: "R1" },
    { ...orders[1], id: "RISK", request_id: "R1", start_time: "2026-10-09T08:00:00Z",
      expected_finish: "2026-10-09T10:00:00Z" },
    { ...orders[1], id: "LATE", request_id: "R2", start_time: "2026-10-09T11:00:00Z",
      expected_finish: "2026-10-09T14:00:00Z" },
    { ...orders[1], id: "OUTSIDE", request_id: "R2", start_time: "2026-10-11T08:00:00Z",
      expected_finish: "2026-10-11T10:00:00Z" },
  ];
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    production_requests: requests.map((request) => ({ ...request, required_by: due })),
    production_orders: cases } };
  const before = structuredClone(cases);
  let writes = 0;
  const { tree } = interactivePlanner(visual, { anchor: "2026-10-09T00:00:00Z" }, async () => { writes++; });
  const metrics = allNodes(tree, (node) => node.type === "section" &&
    node.props.className === "planning-summary")[0];
  assert.deepEqual(allNodes(metrics, (node) => node.type === "dd").map((node) => node.props.children),
    ["2", "2", "1", "1"]);
  assert.equal(writes, 0);
  assert.deepEqual(cases, before);
  const blocks = allNodes(tree, (node) => node.props?.className?.startsWith("planning-gantt-block"));
  assert.equal(blocks.length, 2);
  assert.ok(blocks.some((block) => block.props.className.includes("planning-gantt-risk")));
  assert.ok(blocks.some((block) => block.props.className.includes("planning-gantt-late")));
  assert.deepEqual(blocks[0].props.style["--planning-product-bg"],
    blocks[1].props.style["--planning-product-bg"]); // product identity survives risk treatment
  const requestWarnings = allNodes(tree, (node) => node.props?.className?.startsWith("planning-request-risk"));
  assert.equal(requestWarnings.length, 2);
});

test("panning and zooming change load without moving stored jobs", () => {
  const booked = [{ ...orders[1], start_time: "2026-10-09T08:00:00Z",
    expected_finish: "2026-10-09T10:00:00Z" }];
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: booked } };
  const before = structuredClone(booked);
  let writes = 0;
  const renderLoad = (anchor, zoom = 1) => {
    const { tree } = interactivePlanner(visual, { anchor, zoom }, async () => { writes++; });
    return allNodes(tree, (node) => node.props?.className === "planning-line-load")[0].props.children;
  };
  assert.match(String(renderLoad("2026-10-09T00:00:00Z")), /8\.3%/);
  const panned = panViewStart(Date.parse("2026-10-09T00:00:00Z"), 24 * hour, 1000, -1000);
  assert.match(String(renderLoad(new Date(panned).toISOString())), /0%/);
  assert.match(String(renderLoad("2026-10-09T00:00:00Z", 2)), /2\.8%/);
  assert.deepEqual(booked, before);
  assert.equal(writes, 0);
});

test("capacity and summary respect line filters while keeping Arabic labels readable", () => {
  const secondLine = { id: "L2", name: "Second line", name_ar: "الخط الثاني" };
  const secondCenter = { ...centers[0], id: "C2", line_id: "L2" };
  const booked = [{ ...orders[1], start_time: "2026-10-09T08:00:00Z",
    expected_finish: "2026-10-09T10:00:00Z" }];
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: [orders[0], ...booked],
    production_lines: [lines[0], secondLine], work_centers: [centers[0], secondCenter],
    work_center_capabilities: [...capabilities, { ...capabilities[0], work_center_id: "C2" }] } };
  const { tree } = interactivePlanner(visual, { lang: "ar", lineFilter: "L2",
    anchor: "2026-10-09T00:00:00Z" });
  const labels = allNodes(tree, (node) => node.props?.className === "planning-line-name");
  assert.deepEqual(labels.map((label) => label.props.children), ["الخط الثاني"]);
  const metrics = allNodes(tree, (node) => node.type === "section" &&
    node.props.className === "planning-summary")[0];
  assert.deepEqual(allNodes(metrics, (node) => node.type === "dd").map((node) => node.props.children),
    [1, 0, 0, 0].map((value) => new Intl.NumberFormat("ar").format(value)));
  assert.ok(allNodes(metrics, (node) => node.type === "dt")
    .some((node) => node.props.children === ar.planningSummaryAtRisk));
  assert.equal(allNodes(tree, (node) => node.props?.className === "planning-timeline" &&
    node.props.dir === "ltr").length, 1);
});

const slotNow = Date.parse("2026-09-27T08:00:00Z");
const slotItem = { id: "NEW", request_id: "R", product_id: "P", status: "planned",
  unit: "piece", target_quantity: 100, line_id: null, start_time: null };
const slotRequest = { id: "R", required_by: "2026-09-27T16:00:00Z" };
const slotLines = [{ id: "A", name: "Fast" }, { id: "B", name: "Slow" }, { id: "X", name: "No rate" },
  { id: "D", name: "Not capable" }];
const slotCenters = [{ id: "CA", line_id: "A" }, { id: "CB", line_id: "B" },
  { id: "CX", line_id: "X" }];
const slotRates = [
  { work_center_id: "CA", product_id: "P", rate: 100, rate_unit: "piece", setup_minutes: 30 },
  { work_center_id: "CB", product_id: "P", rate: 50, rate_unit: "piece", setup_minutes: 60 },
  { work_center_id: "CX", product_id: "P", rate: 100, rate_unit: "meter" },
];
const findFixtureSlots = (booked = [], options = {}) => suggestPlanningSlots(slotItem, slotRequest,
  slotLines, booked, slotCenters, slotRates,
  { now: slotNow, calendar: workweek, horizonDays: 28, ...options });

test("smart slots use only capable lines with matching rates and keep line-specific setup and speed", () => {
  const result = findFixtureSlots();
  assert.deepEqual(result.suggestions.map((slot) => slot.lineId), ["A", "B"]);
  assert.deepEqual(result.suggestions.map((slot) => slot.setupMs), [30 * 60_000, 60 * 60_000]);
  assert.deepEqual(result.suggestions.map((slot) => slot.productionMs), [hour, 2 * hour]);
  assert.deepEqual(result.suggestions.map((slot) => slot.finish), [slotNow + 1.5 * hour, slotNow + 3 * hour]);
  assert.ok(result.suggestions.every((slot) => slot.finish === finishAfterWorkingMs(
    slot.start, slot.totalMs, workweek)));
  assert.equal(findFixtureSlots([], { limit: 1 }).suggestions.length, 1);
});

test("smart slots fit middle gaps around locked jobs, reject short gaps, and offer the tail opening", () => {
  const locked = { ...slotItem, id: "LOCK", line_id: "A", start_time: new Date(slotNow).toISOString(),
    expected_finish: new Date(slotNow + hour).toISOString(), planning_locked_at: new Date(slotNow).toISOString() };
  const later = { ...locked, id: "LATER", start_time: new Date(slotNow + 3 * hour).toISOString(),
    expected_finish: new Date(slotNow + 4 * hour).toISOString(), planning_locked_at: null };
  const before = structuredClone([locked, later]);
  const result = findFixtureSlots([locked, later]);
  const middle = result.suggestions.find((slot) => slot.lineId === "A");
  assert.equal(middle.start, slotNow + hour);
  assert.equal(middle.finish, slotNow + 2.5 * hour);
  assert.deepEqual([locked, later], before);
  const narrow = { ...later, start_time: new Date(slotNow + 2 * hour).toISOString(),
    expected_finish: new Date(slotNow + 3 * hour).toISOString() };
  const tail = findFixtureSlots([locked, narrow]).suggestions.find((slot) => slot.lineId === "A");
  assert.equal(tail.start, slotNow + 3 * hour);
  assert.equal(tail.finish, slotNow + 4.5 * hour);
});

test("smart slots carry work into the next open day and skip closed days", () => {
  const thursday = Date.parse("2026-10-01T16:00:00Z");
  const result = findFixtureSlots([], { now: thursday, horizonDays: 7 });
  assert.equal(result.suggestions[0].lineId, "A");
  assert.equal(result.suggestions[0].finish, Date.parse("2026-10-04T08:30:00Z"));
  assert.ok(result.suggestions.every((slot) => slot.start >= thursday));
});

test("a later opening on the faster line can finish before an earlier slower opening", () => {
  const booked = [{ ...slotItem, id: "BUSY", line_id: "A",
    start_time: new Date(slotNow).toISOString(),
    expected_finish: new Date(slotNow + hour).toISOString() }];
  const rates = slotRates.map((rate) => rate.work_center_id === "CA"
    ? { ...rate, setup_minutes: 0 } : rate);
  const result = suggestPlanningSlots(slotItem, slotRequest, slotLines, booked, slotCenters, rates,
    { now: slotNow, calendar: workweek });
  assert.equal(result.suggestions[0].lineId, "A");
  assert.equal(result.suggestions[0].start, slotNow + hour);
  assert.equal(result.suggestions[0].finish, slotNow + 2 * hour);
  assert.equal(result.suggestions[1].lineId, "B");
  assert.equal(result.suggestions[1].start, slotNow);
  assert.equal(result.suggestions[1].finish, slotNow + 3 * hour);
});

test("on-time options lead, but late options remain when every opening misses Required By", () => {
  const due = { ...slotRequest, required_by: new Date(slotNow + 2 * hour).toISOString() };
  const mixed = suggestPlanningSlots(slotItem, due, slotLines, [], slotCenters, slotRates,
    { now: slotNow, calendar: workweek });
  assert.equal(mixed.suggestions[0].lineId, "A");
  assert.equal(mixed.suggestions[0].deadline, "planningAtRisk");
  assert.equal(mixed.suggestions[1].deadline, "planningLate");
  const late = suggestPlanningSlots(slotItem, { ...due,
    required_by: new Date(slotNow + hour).toISOString() }, slotLines, [], slotCenters, slotRates,
    { now: slotNow, calendar: workweek });
  assert.ok(late.suggestions.length > 0);
  assert.ok(late.suggestions.every((slot) => slot.deadline === "planningLate"));
});

test("smart slot load is contextual, never a gate, and unavailable slots explain why", () => {
  const busy = { ...slotItem, id: "BUSY", line_id: "A",
    start_time: new Date(slotNow).toISOString(), expected_finish: new Date(slotNow + hour).toISOString() };
  const result = findFixtureSlots([busy]);
  assert.ok(result.suggestions.some((slot) => slot.lineId === "A" && slot.load.percent > 0));
  assert.equal(result.suggestions.find((slot) => slot.lineId === "A").load.bookedMinutes, 60);
  const noRate = suggestPlanningSlots(slotItem, slotRequest, [slotLines[2]], [], slotCenters, slotRates,
    { now: slotNow, calendar: workweek });
  assert.equal(noRate.reason, "planningMissingRate");
  const noLine = suggestPlanningSlots(slotItem, slotRequest, [slotLines[3]], [], slotCenters, slotRates,
    { now: slotNow, calendar: workweek });
  assert.equal(noLine.reason, "planningNoCapableLine");
  const allDay = { ...busy, expected_finish: "2026-09-27T17:00:00Z" };
  const noOpening = suggestPlanningSlots(slotItem, slotRequest, [slotLines[0]], [allDay],
    slotCenters, slotRates, { now: slotNow, calendar: workweek, horizonDays: 1 });
  assert.equal(noOpening.reason, "planningSlotNone");
});

test("Find slot is localized, previews on the left-to-right Gantt, and writes only after confirmation", async () => {
  const waiting = { ...orders[0], unit: "piece", target_quantity: 50 };
  const visual = { ...snapshot, tables: { ...snapshot.tables,
    production_orders: [waiting, orders[1]] } };
  for (const lang of ["en", "ar"]) {
    const writes = [];
    const command = async (name, args) => { writes.push({ name, args }); };
    const first = interactivePlanner(visual, { lang }, command);
    const find = allNodes(first.tree, (node) => node.props?.className === "planning-find-slot")[0];
    assert.equal(find.props.children, lang === "en" ? en.planningFindSlot : ar.planningFindSlot);
    find.props.onClick();
    const search = first.updates.find((update) => update.position === 22).value;
    assert.equal(writes.length, 0);
    assert.ok(search.suggestions.length >= 1 && search.suggestions.length <= 3);
    const preview = interactivePlanner(visual, { lang, slotSearch: search }, command);
    const panel = allNodes(preview.tree, (node) => node.props?.className === "planning-slot-panel")[0];
    assert.ok(panel);
    assert.ok(allNodes(panel, (node) => node.props?.className === "planning-slot-facts")
      .some((node) => JSON.stringify(node).includes(lang === "en" ? en.planningSlotLoad : ar.planningSlotLoad)));
    const choose = allNodes(panel, (node) => node.type === "button" &&
      node.props.children === (lang === "en" ? en.planningPreviewSlot : ar.planningPreviewSlot))[0];
    choose.props.onClick();
    assert.equal(preview.updates.find((update) => update.position === 23).value, 0);
    assert.equal(writes.length, 0);
    const selected = interactivePlanner(visual, { lang, slotSearch: search, slotChoice: 0,
      anchor: new Date(search.suggestions[0].start - 2 * hour).toISOString() }, command);
    assert.equal(allNodes(selected.tree, (node) => node.props?.className?.includes("planning-slot-ghost")).length, 1);
    assert.equal(allNodes(selected.tree, (node) => node.props?.className === "planning-timeline" &&
      node.props.dir === "ltr").length, 1);
    const confirm = allNodes(selected.tree, (node) => node.type === "button" &&
      node.props.children === (lang === "en" ? en.planningConfirmSlot : ar.planningConfirmSlot))[0];
    await confirm.props.onClick();
    assert.equal(writes.length, 1);
    assert.equal(writes[0].name, "plan_product_item");
    assert.equal(writes[0].args.item, "O1");
    assert.equal(writes[0].args.target_line, "L");
    assert.equal(writes[0].args.planned_start, new Date(search.suggestions[0].start).toISOString());
    assert.equal(selected.updates.some((update) => update.position === 17), false);
  }
});

test("Smart Slot for a previously scheduled waiting item requests a revision reason before writing", async () => {
  const waiting = { ...orders[0], unit: "piece", target_quantity: 50, planning_ever_scheduled: true };
  const visual = { ...snapshot, tables: { ...snapshot.tables, production_orders: [waiting] } };
  const search = suggestPlanningSlots(waiting, requests[0], lines, [waiting], centers, capabilities,
    { now: Math.ceil(Date.now() / 900_000) * 900_000 });
  let writes = 0;
  const { tree, updates } = interactivePlanner(visual, { slotSearch: { itemId: "O1", ...search },
    slotChoice: 0 }, async () => { writes++; });
  const confirm = allNodes(tree, (node) => node.type === "button" &&
    node.props.children === en.planningConfirmSlot)[0];
  await confirm.props.onClick();
  assert.equal(writes, 0);
  const reason = updates.find((update) => update.position === 17).value;
  assert.equal(reason.source, "save");
  assert.equal(reason.item, "O1");
});
