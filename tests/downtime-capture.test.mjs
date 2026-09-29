import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };

const require = createRequire(import.meta.url);
const bundled = await build({
  entryPoints: ["src/features/DowntimeCapture.tsx"], bundle: true,
  platform: "node", format: "cjs", packages: "external", write: false,
  logLevel: "silent", plugins: [{ name: "css-module-stub", setup(build) {
    build.onLoad({ filter: /\.module\.css$/ }, () => ({
      contents: "export default new Proxy({}, {get: (_, key) => String(key)})",
      loader: "js",
    }));
  } }],
});
const featureModule = { exports: {} };
new Function("require", "module", "exports", bundled.outputFiles[0].text)(
  require, featureModule, featureModule.exports);
const DowntimeCapture = featureModule.exports.default;

const snapshot = {
  factory: { id: "F", timezone: "UTC" },
  tables: {
    work_centers: [{ id: "M", name: "Extruder", name_ar: "الطارد", status: "stopped" },
      { id: "R", name: "Running machine", status: "running" }],
    production_lines: [{ id: "L", name: "Pipe line", name_ar: "خط الأنابيب" }],
    production_orders: [{ id: "O", code: "ITEM-101" }],
    memberships: [{ user_id: "U", display_name: "Operator" }],
    downtime_reasons: [
      ...[["MECH", "Mechanical Failure"], ["ELEC", "Electrical Failure"],
        ["MAT", "Material Shortage"], ["QUAL", "Quality Problem"],
        ["SET", "Setup / Changeover"], ["UTIL", "Utilities"],
        ["OTHER", "Other"]].map(([id, name]) => ({ id, name, name_ar: name })),
      { id: "OLD", name: "Planned Maintenance", name_ar: "Old reason" },
    ],
    downtime_events: [
      { id: "ACTIVE", work_center_id: "M", line_id: "L", order_id: "O",
        started_at: "2026-09-29T08:00:00Z", reason_id: null, entered_by: "U" },
      { id: "REVIEW", work_center_id: "M", line_id: "L", order_id: "O",
        started_at: "2026-09-28T08:00:00Z", ended_at: "2026-09-28T09:00:00Z",
        reason_id: "MECH", initial_note: "Belt slipped", initial_entered_by: "U" },
      { id: "MISSED", work_center_id: "M", line_id: "L", order_id: "O",
        started_at: "2026-09-27T08:00:00Z", ended_at: "2026-09-27T09:00:00Z",
        reason_id: null, retroactive: true, entered_by: "U" },
    ],
  },
};
function render(lang, permissions) {
  const dictionary = lang === "ar" ? ar : en;
  return renderToStaticMarkup(createElement(DowntimeCapture, {
    snapshot, lang, t: (key) => dictionary[key] || key,
    can: (module, action) => permissions.includes(`${module}:${action}`),
    command: async () => {},
  }));
}

test("downtime page retains review, retroactive entry and fixed configuration in EN/AR", () => {
  for (const lang of ["en", "ar"]) {
    const dictionary = lang === "ar" ? ar : en;
    const html = render(lang, ["machine_status:edit", "downtime:edit", "downtime:create"]);
    assert.doesNotMatch(html, /Start downtime|بدء التوقف|End downtime \/ resume/);
    assert.match(html, new RegExp(dictionary.downtimeUnclassified));
    assert.match(html, new RegExp(dictionary.downtimeAddReason));
    assert.match(html, new RegExp(dictionary.downtimeNeedsReview));
    assert.match(html, new RegExp(dictionary.downtimeApprovedCause));
    assert.match(html, new RegExp(dictionary.downtimeRetroactive));
    assert.match(html, /ITEM-101/);
    assert.match(html, /Belt slipped/);
    assert.match(html, /Operator/);
    assert.match(html, /datetime-local/);
    for (const key of ["downtimeMechanical", "downtimeElectrical", "downtimeMaterial",
      "downtimeQuality", "downtimeSetup", "downtimeUtilities", "downtimeOther"]) {
      assert.match(html, new RegExp(dictionary[key]));
    }
    assert.doesNotMatch(html, /Planned Maintenance|Old reason/);
  }
});

test("per-person view hides stop and approval controls without edit grants", () => {
  const viewOnly = render("en", []);
  assert.match(viewOnly, /Unclassified/);
  assert.doesNotMatch(viewOnly, /Start downtime|Approve initial reason|Record missed downtime/);
  const reviewer = render("en", ["downtime:edit"]);
  assert.match(reviewer, /Approve initial reason/);
  assert.doesNotMatch(reviewer, /Start downtime/);
});
