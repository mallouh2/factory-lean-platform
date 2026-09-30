import test from "node:test";
import assert from "node:assert/strict";
import { hasDeferredWork, validateActualScrap } from
  "../src/utils/production-loss-actuals.mjs";

test("scrap accepts total-only, breakdown-only, and consistent mixed values", () => {
  assert.deepEqual(validateActualScrap("80", "", ""),
    { total: 80, shutdown: null, restart: null, error: null });
  assert.deepEqual(validateActualScrap("", "30", "50"),
    { total: 80, shutdown: 30, restart: 50, error: null });
  assert.deepEqual(validateActualScrap("80", "30", "50"),
    { total: 80, shutdown: 30, restart: 50, error: null });
  assert.equal(validateActualScrap("80", "30", "").error, null);
  assert.equal(validateActualScrap("0.3", "0.1", "0.2").error, null);
});

test("scrap conflicts show a specific error before submission", () => {
  assert.equal(validateActualScrap("34", "45", "").error,
    "lossScrapBreakdownExceedsTotal");
  assert.equal(validateActualScrap("80", "30", "40").error,
    "lossScrapBreakdownMismatch");
  assert.equal(validateActualScrap("", "30", "").error,
    "lossScrapNeedTotalOrBoth");
  assert.equal(validateActualScrap("-1", "", "").error,
    "lossActualNonnegative");
});

test("catch-up field only applies to deferred work or an existing actual", () => {
  assert.equal(hasDeferredWork({ deferred_quantity: 0,
    estimated_recovery_minutes: null }, null), false);
  assert.equal(hasDeferredWork({ deferred_quantity: 4,
    estimated_recovery_minutes: null }, null), true);
  assert.equal(hasDeferredWork({ deferred_quantity: 0,
    estimated_recovery_minutes: null }, { recovery_minutes: 12 }), true);
});
