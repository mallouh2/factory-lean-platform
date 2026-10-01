import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };
import { floorSnapshot } from "./fixtures/factory-floor.mjs";

const require = createRequire(import.meta.url);
const bundle = await build({ entryPoints: ["src/components/FactoryApp.tsx"],
  bundle: true, platform: "node", format: "cjs", packages: "external", write: false, logLevel: "silent",
  plugins: [{ name: "test-css", setup(build) {
    build.onLoad({ filter: /\.css$/ }, () => ({ contents: "export default {}", loader: "js" }));
  } }],
});
function render(view, limited, lang = "en", management = false) {
  const snapshot = floorSnapshot("running");
  snapshot.permissions.push("factory:view", "dashboard:view", "lines:view", "lines:edit", "reports:view", "audit:view", "downtime:view");
  snapshot.truncatedTables = limited;
  snapshot.tables.audit_logs = [{ id: "AUDIT", created_at: new Date().toISOString(), action: "READ", entity: "factory" }];
  const before = structuredClone(snapshot);
  const react = require("react");
  let hook = 0;
  const values = { 1: lang, 3: view, 4: snapshot, 5: false, 10: management };
  const module = { exports: {} };
  new Function("require", "module", "exports", bundle.outputFiles[0].text)(
    (name) => name === "react" ? { ...react,
      useState: (initial) => react.useState(Object.hasOwn(values, ++hook) ? values[hook] : initial),
    } : require(name), module, module.exports);
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = () => { throw new Error("Rendering a scoped warning must not fetch history"); };
    const html = renderToStaticMarkup(createElement(module.exports.default));
    assert.deepEqual(snapshot, before, "warning scope must preserve all current/history data and limit flags");
    return html;
  } finally { globalThis.fetch = originalFetch; }
}

test("audit history limit does not leak into Factory Floor or line management in EN/AR", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    for (const management of [false, true]) {
      const html = render("lines", ["audit_logs"], lang, management);
      assert.ok(!html.includes(words.truncatedData));
      assert.ok(html.includes("LINE 1") || html.includes("الخط ١"));
      assert.ok(html.includes("Pipe extruder") || html.includes("طارد الأنابيب"));
      if (!management) assert.ok(html.includes(words.finishProduction));
    }
  }
});

test("paginated audit uses its own loading state and no obsolete snapshot warning in EN/AR", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    const html = render("audit", ["audit_logs"], lang);
    assert.ok(!html.includes(words.truncatedData));
    assert.ok(html.includes(words.historyLoading));
    assert.ok(!render("audit", ["production_entries"], lang).includes(words.truncatedData));
  }
});

test("reporting still warns for its limited input without inheriting unrelated audit limits", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    assert.ok(render("reports", ["downtime_events"], lang).includes(words.truncatedData));
    assert.ok(!render("reports", ["audit_logs"], lang).includes(words.truncatedData));
    assert.ok(!render("reports", ["status_events"], lang).includes(words.truncatedData),
      "default downtime report does not use status history");
  }
});

test("Factory Floor preserves warnings beside affected today totals but management does not aggregate history", () => {
  for (const table of ["production_entries", "downtime_events"]) {
    const html = render("lines", [table]);
    assert.ok(html.includes(en.truncatedData));
    assert.ok(html.indexOf(en.todayProduction) < html.indexOf(en.truncatedData));
    assert.ok(!render("lines", [table], "en", true).includes(en.truncatedData));
  }
});

test("dashboard and downtime warning scopes retain relevant limits without global suppression", () => {
  assert.ok(render("dashboard", ["production_entries"]).includes(en.truncatedData));
  assert.ok(!render("dashboard", ["audit_logs"]).includes(en.truncatedData));
  for (const table of ["downtime_events", "production_transfers"]) {
    assert.ok(render("downtime", [table]).includes(en.truncatedData));
  }
  for (const table of ["downtime_classification_corrections", "production_loss_context_snapshots",
    "production_loss_estimates", "production_loss_actuals"]) {
    assert.ok(!render("downtime", [table]).includes(en.truncatedData));
  }
  assert.ok(!render("downtime", ["audit_logs"]).includes(en.truncatedData));
  assert.ok(!render("lines", []).includes(en.truncatedData));
});
