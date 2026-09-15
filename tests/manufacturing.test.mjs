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
} from "../src/utils/manufacturing.mjs";
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
