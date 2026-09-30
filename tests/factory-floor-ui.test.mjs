import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };
import { floorScenarios, floorSnapshot } from "./fixtures/factory-floor.mjs";

const require = createRequire(import.meta.url);
const bundle = await build({ entryPoints: ["src/features/FactoryFloorV2.tsx"],
  bundle: true, platform: "node", format: "cjs", packages: "external", write: false, logLevel: "silent" });
function render(scenario, lang = "en", selected = null, permissions = null, configure = () => {}) {
  const snapshot = floorSnapshot(scenario);
  if (permissions) snapshot.permissions = permissions;
  configure(snapshot);
  const before = structuredClone(snapshot);
  const dictionary = lang === "ar" ? ar : en;
  let hook = 0;
  const react = require("react");
  const module = { exports: {} };
  const load = (name) => name === "react" ? { ...react,
    useState: (initial) => react.useState(++hook === 2 && selected ? selected : initial),
  } : require(name);
  new Function("require", "module", "exports", bundle.outputFiles[0].text)(load, module, module.exports);
  const html = renderToStaticMarkup(createElement(module.exports.default, {
    snapshot, lang, t: (key) => dictionary[key] || key,
    can: (module, action = "view") => snapshot.permissions.includes(`${module}:${action}`),
    command: async () => { throw new Error("Rendering must never issue a command"); }, onManage: () => {},
  }));
  assert.deepEqual(snapshot, before, "presentation must leave snapshot and scheduling unchanged");
  return html;
}
function machine(html, id, index = 0) {
  return [...html.matchAll(new RegExp(`<button[^>]*data-machine-id="${id}"[\\s\\S]*?</button>`, "g"))][index]?.[0] || "";
}
test("Factory Floor shows separate physical and flow states in both languages", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    const html = render("blocked", lang);
    const downstream = machine(html, "M3");
    assert.ok(downstream.includes(words.running));
    assert.ok(downstream.includes(words.flowBlocked));
    assert.ok(downstream.includes(words.ffPhysicalState));
    assert.ok(downstream.includes(words.affectedBy));
    assert.ok(html.indexOf('class="ff2-flow"') < html.indexOf('class="ff2-queue"'));
    assert.match(html, new RegExp(`class="ff2-flow" dir="${lang === "ar" ? "rtl" : "ltr"}"`));
    assert.ok(html.includes(words.ffProductionTiming));
    assert.match(html, /aria-pressed="true"/);
  }
});

test("redesigned transfer drawer requires an active assignment, valid category/capability and permissions", () => {
  const offered = (html) => html.includes(`>${en.transferProduction}</button>`);
  assert.ok(offered(render("stopped", "en", "M2")));
  assert.ok(!offered(render("stopped", "en", "M2", [])));
  for (const missing of ["orders:edit", "centers:edit"]) {
    assert.ok(!offered(render("stopped", "en", "M2", null,
      (s) => { s.permissions = s.permissions.filter((p) => p !== missing); })));
  }
  for (const configure of [
    (s) => { s.tables.work_center_alternatives = []; },
    (s) => { s.tables.work_centers[4].category_id = "OTHER"; },
    (s) => { s.tables.work_center_capabilities = []; },
    (s) => { s.tables.work_center_capabilities[0].rate_unit = "piece"; },
    (s) => { s.tables.production_orders[0].status = "completed"; },
    (s) => { s.tables.work_centers[1].order_id = "PREVIOUS"; },
  ]) assert.ok(!offered(render("stopped", "en", "M2", null, configure)));
  assert.ok(!offered(render("borrowed", "en", "M2")));
  assert.ok(!offered(render("alternative-stopped", "en", "M2")));
  const arHtml = render("stopped", "ar", "M2");
  assert.ok(arHtml.includes(`>${ar.transferProduction}</button>`));
});
test("all requested floor scenarios render without changing their inputs", () => {
  for (const scenario of floorScenarios) for (const lang of ["en", "ar"]) {
    assert.ok(render(scenario, lang).includes('data-machine-id="M1"'));
  }
});
test("planned and unplanned downtime remain visually distinct from no demand", () => {
  assert.match(machine(render("planned-stop"), "M2"), /ff2-accent-planned/);
  assert.match(machine(render("unplanned-stop"), "M2"), /ff2-accent-stopped/);
  const idle = machine(render("idle"), "M2");
  assert.ok(idle.includes(en.idleNoDemand));
  assert.doesNotMatch(idle, /ff2-node-stop/);
  assert.ok(!render("idle", "en", "M2").includes(en.currentIssue));
});
test("open borrowing survives a stopped alternative and retains its home placeholder", () => {
  for (const scenario of ["borrowed", "alternative-stopped"]) {
    const html = render(scenario);
    assert.equal((html.match(/data-machine-id="A1"/g) || []).length, 2);
    assert.ok(machine(html, "A1", 1).includes(en.temporarilyAssignedTo));
    assert.ok(machine(html, "A1").includes(en.alternativeAssigned));
    assert.equal(machine(html, "A1").split(`>${en.alternativeAssigned}<`).length - 1, 1,
      "assignment stays visible once, including when the alternative stops");
    assert.match(html, /ff2-branch/);
  }
  assert.ok(machine(render("alternative-stopped"), "A1").includes(en.stopped));
});
test("existing execution and machine actions retain per-person permission gates", () => {
  assert.ok(render("running", "en", "M1").includes(en.recordOutput));
  assert.ok(render("running", "en", "M1").includes(en.stopMachine));
  assert.ok(render("running").includes(en.finishProduction));
  const readonly = render("running", "en", "M1", []);
  assert.ok(!readonly.includes(en.recordOutput));
  assert.ok(!readonly.includes(en.stopMachine));
  assert.ok(!readonly.includes(en.finishProduction));
  assert.ok(render("borrowed", "en", "M2").includes(en.returnProduction));
  assert.ok(render("alternative-stopped", "en", "A1").includes(en.downtimeEnd));
});
