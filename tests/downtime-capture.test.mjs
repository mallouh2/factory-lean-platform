import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };
import { calculateProductionLoss } from "../src/utils/production-loss-impact.mjs";

const require = createRequire(import.meta.url);
const bundled = await build({
  entryPoints: ["src/features/DowntimeCapture.tsx"], bundle: true,
  platform: "node", format: "cjs", packages: "external", write: false,
  logLevel: "silent", plugins: [{ name: "css-module-stub", setup(build) {
    build.onResolve({ filter: /hooks\/useHistoryData$/ }, () => ({ path: "test-history", external: true }));
    build.onLoad({ filter: /\.module\.css$/ }, () => ({
      contents: "export default new Proxy({}, {get: (_, key) => String(key)})",
      loader: "js",
    }));
  } }],
});
const featureModule = { exports: {} };
let historyState = "loaded";
new Function("require", "module", "exports", bundled.outputFiles[0].text)(
  name => name === "test-history" ? { useHistoryData: url => {
    if (["loading", "error"].includes(historyState)) return { data: null, loading: historyState === "loading",
      error: historyState === "error" ? "dataWarning" : "", reload: () => {} };
    const rows = historyState === "empty" ? [] : snapshot.tables.downtime_events;
    const event = rows.find(row => url?.endsWith("event=" + row.id));
    return { loading: false, error: "", reload: () => {}, data: url?.includes("event=") ? {
      event, actual: null, saved: null, correction: null,
      calculation: calculateProductionLoss(event, []), suggestions: [],
      scrap: historyState === "linked" ? { state: "recorded", kg: 7, startup: 3 } : undefined,
    } : { rows, total: rows.length, pages: 1 } };
  } } : require(name), featureModule, featureModule.exports);
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
        reason_id: "MECH", stop_nature: "legacy_unknown",
        initial_note: "Belt slipped", initial_entered_by: "U" },
      { id: "MISSED", work_center_id: "M", line_id: "L", order_id: "O",
        started_at: "2026-09-27T08:00:00Z", ended_at: "2026-09-27T09:00:00Z",
        reason_id: null, retroactive: true, entered_by: "U" },
    ],
  },
};
function render(lang, permissions, state = "loaded") {
  historyState = state;
  const dictionary = lang === "ar" ? ar : en;
  return renderToStaticMarkup(createElement(DowntimeCapture, {
    snapshot, lang, t: (key) => dictionary[key] || key,
    can: (module, action) => permissions.includes(`${module}:${action}`),
    command: async () => {},
  }));
}

test("downtime retains cause choices and missed-stop entry without the configuration accordion in EN/AR", () => {
  for (const lang of ["en", "ar"]) {
    const dictionary = lang === "ar" ? ar : en;
    const html = render(lang, ["machine_status:edit", "downtime:edit", "downtime:create"]);
    assert.doesNotMatch(html, /Start downtime|بدء التوقف|End downtime \/ resume/);
    assert.match(html, new RegExp(dictionary.downtimeUnclassified));
    assert.match(html, new RegExp(dictionary.downtimeActive));
    assert.match(html, new RegExp(dictionary.downtimeNeedsReview));
    assert.match(html, new RegExp(dictionary.downtimeApprovedCause));
    assert.match(html, new RegExp(dictionary.downtimeRetroactive));
    assert.match(html, new RegExp(dictionary.lossImpact));
    assert.match(html, new RegExp(dictionary.lossLegacyUnknown));
    assert.match(html, new RegExp(dictionary.downtimeLossEvidenceMissing));
    assert.match(html, /ITEM-101/);
    assert.doesNotMatch(html, /Belt slipped/);
    assert.match(html, /datetime-local/);
    assert.ok(!html.includes(`<summary>${dictionary.configuration}</summary>`));
    for (const key of ["downtimeMechanical", "downtimeElectrical", "downtimeMaterial",
      "downtimeQuality", "downtimeSetup", "downtimeUtilities", "downtimeOther"]) {
      assert.match(html, new RegExp(dictionary[key]));
    }
    assert.match(html, /Planned Maintenance|Old reason/);
  }
});

test("loss loading/error stay local and do not invent an empty result or hide current downtime in EN/AR", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    const loading = render(lang, [], "loading");
    assert.ok(loading.includes(words.historyLoading));
    assert.ok(loading.includes(words.downtimeActive));
    assert.ok(!loading.includes(words.lossGapHistorical));
    const error = render(lang, [], "error");
    assert.ok(error.includes(words.dataWarning));
    assert.ok(error.includes(words.refresh));
    assert.ok(error.includes("ITEM-101"));
    const empty = render(lang, [], "empty");
    assert.ok(empty.includes(words.noResults));
    assert.ok(!empty.includes(words.historyLoading));
    assert.ok(!empty.includes(words.lossGapHistorical));
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

test("exceptional observation and corrections are available on demand only", () => {
  for (const lang of ["en", "ar"]) {
    const dictionary = lang === "ar" ? ar : en;
    const html = render(lang, ["downtime:edit"]);
    assert.ok(html.includes('<details class="moreActions"><summary>' + dictionary.downtimeMoreActions));
    assert.ok(html.includes(dictionary.downtimeExceptionalObservation));
    assert.ok(html.includes(dictionary.downtimeCorrectData));
    assert.ok(!html.includes(dictionary.downtimeConfirmObservationSource));
    assert.ok(!html.includes(dictionary.lossActualScrapHelp));
    assert.ok(!html.includes(dictionary.downtimeSourceReview));
  }
});

test("reviewed production scrap is visible without extra inputs or startup details", () => {
  for (const lang of ["en", "ar"]) {
    const words = lang === "en" ? en : ar;
    const html = render(lang, ["downtime:edit"], "linked");
    assert.ok(html.includes(words.downtimeLinkedScrap));
    assert.ok(!html.includes(words.downtimeLinkedStartup));
    assert.ok(!html.includes(words.lossActualScrapHelp));
    assert.ok(!html.includes(words.lossActualLostQuantityHelp.replaceAll("'", "&#x27;")));
  }
});
