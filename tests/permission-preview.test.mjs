import test from "node:test";
import assert from "node:assert/strict";
import { hasEveryDefinedPermission, previewPermissions, previewPresets } from "../src/utils/permission-preview.mjs";

const catalog = [
  { module: "factory", action: "view" },
  { module: "orders", action: "view" },
  { module: "orders", action: "create" },
  { module: "roles", action: "edit" },
];
const real = catalog.map(({ module, action }) => `${module}:${action}`);

test("full-access eligibility requires every defined grant", () => {
  assert.equal(hasEveryDefinedPermission(real, catalog), true);
  assert.equal(hasEveryDefinedPermission(real.slice(0, -1), catalog), false);
  assert.equal(hasEveryDefinedPermission(real, []), false);
});

test("preview masks only presentation grants and never changes real grants", () => {
  const original = [...real];
  assert.equal(previewPermissions(real, "full"), real);
  assert.deepEqual(previewPermissions(real, "sales"), ["factory:view", "orders:view", "orders:create"]);
  assert.deepEqual(previewPermissions(real, "planning"), ["factory:view", "orders:view"]);
  assert.deepEqual(previewPermissions(real, "unknown"), []);
  assert.deepEqual(real, original);
});

test("all employee previews use only defined permission keys", () => {
  const defined = new Set([
    "factory:view", "dashboard:view", "orders:view", "orders:create", "orders:edit",
    "sales_orders:view", "sales_orders:create", "sales_orders:edit", "warehouse:view",
    "lines:view", "centers:view", "centers:edit", "machine_status:edit",
    "downtime:view", "downtime:create", "downtime:edit",
    "employees:view", "employees:create", "employees:edit", "employees:approve",
  ]);
  for (const [name, grants] of Object.entries(previewPresets)) {
    if (name === "full") continue;
    assert.ok(grants.length > 0);
    assert.ok(grants.every((grant) => defined.has(grant)), name);
  }
});
