import test from "node:test";
import assert from "node:assert/strict";
import { orderAttention, orderMatchesFilter, sortOrdersForScan, nextScheduledOrder, requestStatus, requestAttention, requestMatchesFilter } from "../src/utils/order-overview.mjs";

const now = Date.parse("2026-09-24T12:00:00Z");
const orders = [
  { code: "A", status: "active", expected_finish: "2026-09-25T12:00:00Z" },
  { code: "B", status: "planned", start_time: "2026-09-24T11:00:00Z" },
  { code: "C", status: "completed", expected_finish: "2026-09-23T12:00:00Z" },
  { code: "D", status: "active", expected_finish: "2026-09-24T11:30:00Z" },
  { code: "E", status: "planned", start_time: "2026-09-24T14:00:00Z" },
  { code: "F", status: "planned", start_time: "2026-09-24T13:00:00Z" },
];

test("attention uses real timestamps without turning them into backend states", () => {
  assert.equal(orderAttention(orders[1], now), "startOverdue");
  assert.equal(orderAttention(orders[3], now), "finishOverdue");
  assert.equal(orderAttention(orders[2], now), null);
  assert.equal(orderAttention({ status: "planned" }, now), null);
  assert.equal(orderAttention({ status: "cancelled", expected_finish: "2026-09-23T12:00:00Z" }, now), null);
});

test("filters keep actual statuses and delayed view is derived", () => {
  assert.deepEqual(orders.filter((o) => orderMatchesFilter(o, "delayed", now)).map((o) => o.code), ["B", "D"]);
  assert.deepEqual(orders.filter((o) => orderMatchesFilter(o, "planned", now)).map((o) => o.code), ["B", "E", "F"]);
  assert.equal(orders.filter((o) => orderMatchesFilter(o, "all", now)).length, 6);
});

test("attention-first sort and next scheduled start use available planning data", () => {
  assert.deepEqual(sortOrdersForScan(orders, now).map((o) => o.code), ["D", "B", "A", "F", "E", "C"]);
  assert.equal(nextScheduledOrder(orders, now)?.code, "F");
  assert.equal(nextScheduledOrder([{ status: "planned" }], now), undefined);
});

test("request status and progress remain based on items with independent units", () => {
  const items = [
    { status: "completed", target_quantity: 500, produced_quantity: 500, unit: "meter" },
    { status: "planned", target_quantity: 200, produced_quantity: 0, unit: "piece" },
  ];
  assert.equal(requestStatus(items), "active");
  assert.equal(items.filter((item) => item.status === "completed").length, 1);
  assert.equal(requestMatchesFilter({}, items, "completed", now), false);
  assert.equal(requestMatchesFilter({}, items, "active", now), true);
  assert.equal(requestStatus(items.map((item) => ({ ...item, status: "completed" }))), "completed");
  assert.equal(requestAttention(items, now), null);
});
