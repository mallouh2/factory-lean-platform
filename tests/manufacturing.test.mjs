import test from "node:test";
import assert from "node:assert/strict";
import {
  downtimeMinutes,
  calculateOee,
  pareto,
  csvCell,
  reportPeriod,
  localDateTimeToUtc,
  formatLocalInput,
  statusUtilization,
  autoCode,
  lineTodayOutput,
} from "../src/utils/manufacturing.mjs";
import { machineIconCategory } from "../src/utils/machine-icons.mjs";
import fs from "node:fs";
test("overnight downtime clips to selected day", () =>
  assert.equal(
    downtimeMinutes(
      { started_at: "2026-09-14T23:00Z", ended_at: "2026-09-15T01:00Z" },
      "2026-09-15T00:00Z",
      "2026-09-16T00:00Z",
      Date.parse("2026-09-17"),
    ),
    60,
  ));
test("open event stops at now, future events do not contribute", () => {
  assert.equal(
    downtimeMinutes(
      { started_at: "2026-09-15T01:00Z" },
      "2026-09-15",
      "2026-09-16",
      Date.parse("2026-09-15T01:34Z"),
    ),
    34,
  );
  assert.equal(
    downtimeMinutes(
      { started_at: "2026-09-16" },
      "2026-09-15",
      "2026-09-16",
      Date.parse("2026-09-15"),
    ),
    0,
  );
});
test("OEE refuses absent or inconsistent inputs", () => {
  assert.equal(calculateOee({}), null);
  assert.equal(
    calculateOee({
      planned_seconds: 100,
      run_seconds: 90,
      ideal_cycle_seconds: 2,
      total_count: 100,
      good_count: 90,
    }),
    null,
  );
  assert.ok(
    Math.abs(
      calculateOee({
        planned_seconds: 100,
        run_seconds: 80,
        ideal_cycle_seconds: 1,
        total_count: 60,
        good_count: 50,
      }).oee - 0.5,
    ) < 1e-12,
  );
});
test("Pareto sorted with real cumulative percentages", () => {
  const r = pareto(
    [
      { r: "a", n: 3 },
      { r: "b", n: 7 },
    ],
    (e) => e.n,
    (e) => e.r,
  );
  assert.equal(r[0].key, "b");
  assert.equal(r[0].percent, 70);
  assert.equal(r[1].cumulative, 100);
});
test("CSV formula injection and quote escaping", () => {
  assert.equal(csvCell("=SUM(A1)"), '"\'=SUM(A1)"');
  assert.equal(csvCell('a"b'), '"a""b"');
});
test("factory timezone day and DST calendar boundary", () => {
  const q = reportPeriod("today", "Asia/Qatar", new Date("2026-09-15T01:00Z"));
  assert.equal(q.from, "2026-09-14T21:00:00.000Z");
  const n = reportPeriod(
    "today",
    "America/New_York",
    new Date("2026-03-08T12:00Z"),
  );
  assert.equal((Date.parse(n.to) - Date.parse(n.from)) / 3600000, 23);
});
test("both dictionaries have identical keys and nonempty translations", () => {
  const en = JSON.parse(fs.readFileSync("src/locales/en.json"));
  const ar = JSON.parse(fs.readFileSync("src/locales/ar.json"));
  assert.deepEqual(Object.keys(en).sort(), Object.keys(ar).sort());
  assert.ok(Object.values(ar).every((x) => x.trim().length));
});

test("factory local datetime ignores browser timezone", () => {
  assert.equal(
    localDateTimeToUtc("2026-09-15T11:30", "Asia/Qatar"),
    "2026-09-15T08:30:00.000Z",
  );
  assert.equal(
    formatLocalInput("2026-09-15T08:30:00Z", "Asia/Qatar"),
    "2026-09-15T11:30",
  );
});
test("nonexistent DST local time is rejected", () =>
  assert.throws(
    () => localDateTimeToUtc("2026-03-08T02:30", "America/New_York"),
    /invalidDate/,
  ));
test("auto codes stay unique, uppercase and within the database length limit", () => {
  const seen = new Set();
  for (let i = 0; i < 500; i++) {
    const code = autoCode(i % 2 ? "LINE" : "WC");
    assert.match(code, /^(LINE|WC)-[0-9A-Z]{8,20}$/);
    assert.ok(code.length <= 40);
    seen.add(code);
  }
  assert.equal(seen.size, 500);
});
test("line output respects the passed factory-zone window, not local dates", () => {
  const entries = [
    { created_at: "2026-09-15T20:30Z", produced: 10, order_id: "o1", work_center_id: "w1" },
    { created_at: "2026-09-15T21:30Z", produced: 7, order_id: "o1", work_center_id: "w1" },
    { created_at: "2026-09-14T10:00Z", produced: 99, order_id: "o1", work_center_id: "w1" },
    { created_at: "2026-09-15T22:00Z", produced: 40, order_id: "oX", work_center_id: "wX" },
  ];
  const orders = [{ id: "o1", line_id: "L1" }];
  const centers = [{ id: "w1", line_id: "L1" }];
  // Asia/Qatar day 2026-09-15 = 2026-09-14T21:00Z .. 2026-09-15T21:00Z
  const q = reportPeriod("today", "Asia/Qatar", new Date("2026-09-15T12:00Z"));
  assert.equal(lineTodayOutput(entries, orders, centers, "L1", q.from, q.to), 10);
  // non-string ids and empty inputs must not throw
  assert.equal(lineTodayOutput([], [], [], "L1", q.from, q.to), 0);
});

test("machine icon classification prefers type and never misreads ambiguous names", () => {
  assert.equal(machineIconCategory("packing_station", "Anything"), "packing");
  assert.equal(machineIconCategory("inspection_station", "Extruder 9"), "inspection");
  assert.equal(machineIconCategory("production_cell", "Mixer"), "cell");
  assert.equal(machineIconCategory("other", "Printer"), "generic");
  assert.equal(machineIconCategory("machine", "Material Mixer"), "mixer");
  assert.equal(machineIconCategory("machine", "Extruder 2"), "extruder");
  assert.equal(machineIconCategory("machine", "Printer Area Cooling"), "cooling");
  assert.equal(machineIconCategory("machine", "ماكينة البثق ١"), "extruder");
  assert.equal(machineIconCategory("machine", "Unknown Device"), "generic");
  assert.equal(machineIconCategory("", ""), "generic");
  assert.equal(machineIconCategory(null, "Cutter"), "cutter");
});

test("utilization excludes unknown time before first event", () => {
  const result = statusUtilization(
    [
      {
        work_center_id: "a",
        created_at: "2026-09-15T08:00Z",
        new_status: "running",
      },
      {
        work_center_id: "a",
        created_at: "2026-09-15T09:00Z",
        new_status: "stopped",
      },
    ],
    "a",
    "2026-09-15T07:00Z",
    "2026-09-15T10:00Z",
    Date.parse("2026-09-15T10:00Z"),
  );
  assert.equal(result.percent, 50);
  assert.equal(result.observedMinutes, 120);
  assert.ok(result.coverage < 1);
  assert.equal(
    statusUtilization([], "a", "2026-09-15T07:00Z", "2026-09-15T10:00Z"),
    null,
  );
});
