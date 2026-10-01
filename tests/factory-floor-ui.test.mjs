import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };
import { floorScenarios, floorSnapshot } from "./fixtures/factory-floor.mjs";
import {planningProductTones} from '../src/utils/planning.mjs';

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
test('Floor uses the full Planning catalog palette at line level without repeating Product context on normal machines',()=>{
  const tone=planningProductTones(floorSnapshot().tables.products).get('P1');
  for(const lang of ['en','ar']){
    const html=render('running',lang);
    assert.ok(html.includes(`--product-surface:${tone.surface}`));
    assert.ok(html.includes(`--product-edge:${tone.edge}`));
    assert.match(html,/data-execution-state="active"/);
    for(const id of ['M1','M2','M3','M4'])assert.doesNotMatch(machine(html,id),/product-identity|ITEM-041/);
  }
});
test("Factory Floor shows separate physical and flow states in both languages", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    const html = render("blocked", lang);
    const downstream = machine(html, "M3");
    assert.ok(downstream.includes(words.running));
    assert.ok(downstream.includes(words.flowBlocked));
    assert.ok(downstream.includes(words.ffPhysicalState));
    assert.ok(downstream.includes(words.affectedBy));
    assert.ok(html.indexOf('class="ff2-queue"') < html.indexOf('class="ff2-flow"'), "line production context precedes the machine route");
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
    assert.equal((machine(html, "A1").match(/class="ff2-node-assignment"/g) || []).length, 1,
      "borrowed assignment indicator stays visible once, including when the alternative stops");
    assert.ok(machine(html,"A1").includes(en.ffStateBorrowed));
    assert.match(html, /ff2-branch/);
  }
  assert.ok(machine(render("alternative-stopped"), "A1").includes(en.stopped));
});
test("existing execution and machine actions retain per-person permission gates", () => {
  assert.ok(!render("running", "en", "M1").includes(en.recordOutput), "machine drawer cannot record line output");
  assert.ok(render("running", "en", "M1").includes(en.stopMachine));
  assert.ok(render("running").includes(en.finishProduction));
  const readonly = render("running", "en", "M1", []);
  assert.ok(!readonly.includes(en.recordOutput));
  assert.ok(!readonly.includes(en.stopMachine));
  assert.ok(!readonly.includes(en.finishProduction));
  assert.ok(render("borrowed", "en", "M2").includes(en.returnProduction));
  assert.ok(render("alternative-stopped", "en", "A1").includes(en.downtimeEnd));
});
test("current line progress and today's output use corrected good output, excluding scrap", () => {
  const html=render("running", "en", null, null, s=>{
    Object.assign(s.tables.production_orders[0], {produced_quantity:120,rejected_quantity:20,good_quantity:100,remaining_quantity:4900});
    s.tables.production_entries=[{id:"ENTRY",order_id:"O1",line_id:"L1",work_center_id:null,
      produced:120,rejected:20,effective_good:100,effective_scrap:20,created_at:new Date().toISOString()}];
  });
  assert.ok(html.includes(en.recordingGoodSoFar));
  assert.match(html, /100 m<\/dd>/);
  assert.match(html, /4,900 m<\/dd>/);
  assert.match(html.replace(/<[^>]*>/g,""), /Today’s production:\s*100/);
});

test("physical state remains primary when a running machine has blocked flow", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    const card = machine(render("blocked", lang), "M3");
    assert.match(card, /ff2-accent-running/);
    assert.match(card, /data-physical-state="running"/);
    assert.match(card, /ff2-state-band/);
    assert.match(card, /ff2-node-state/);
    assert.ok(card.includes(words.running));
    assert.match(card, /ff2-node-flow ff2-flow-state-affected/);
    assert.ok(card.includes(words.ffStateBlocked));
    assert.ok(card.indexOf("ff2-state-band") < card.indexOf("ff2-node-flow"));
  }
});

test("stopped and borrowed states retain duration, assignment and accessible detail", () => {
  for (const [lang, words] of [["en", en], ["ar", ar]]) {
    const stopped = machine(render("unplanned-stop", lang), "M2");
    assert.match(stopped, /ff2-node-duration/);
    assert.ok(stopped.includes(words.downtimeUnclassified) || stopped.includes(lang === "ar" ? "ميكانيكي" : "Mechanical"));
    const borrowed = machine(render("alternative-stopped", lang), "A1");
    assert.match(borrowed, /ff2-accent-stopped/);
    assert.ok(borrowed.includes(words.ffStateBorrowed));
    assert.match(borrowed, /ff2-node-assignment/);
    assert.match(borrowed, /class="sr-only"/);
    assert.ok(borrowed.includes(words.ffViewActions.replaceAll("&", "&amp;")));
  }
});

test("independent machines and multiple lines keep their own routes and quantities", () => {
  for (const lang of ["en", "ar"]) {
    const html = render("running", lang, null, null, s => {
      s.tables.work_centers.push({id:"I1",name:"Independent inspection",name_ar:"فحص مستقل",line_id:null,status:"idle",order_id:null,dependency_mode:"independent"});
      s.tables.production_orders.push({...s.tables.production_orders[0],id:"O3",line_id:"L2",code:"ITEM-042"});
    });
    assert.ok(machine(html, "I1"));
    assert.ok(html.includes((lang === "ar" ? ar : en).independent));
    assert.ok(html.includes("ITEM-042"));
    assert.match(html, /ff2-queue-variance/);
    assert.match(html, /ff2-queue-timing/);
    assert.ok(!html.includes((lang === "ar" ? ar : en).ffFloorHelp));
  }
});

test("floor motion uses category identity before legacy names, including explicit generic", () => {
  const silhouettes = new Set();
  for (const kind of ["extruder", "cooling", "printer", "cutter", "packing", "mixer", "conveyor", "inspection", "manual", "cell", "cnc", "drill", "press", "injection", "generic", "heating", "pump", "assembly"]) {
    const html = render("running", "en", null, null, s => {
      s.tables.work_center_categories[0].icon_key = kind;
      s.tables.work_centers[0].name = "Misleading printer name";
    });
    assert.ok(machine(html, "M1").includes(`data-machine-kind="${kind}"`));
    silhouettes.add(machine(html, "M1").match(/data-machine-kind[\s\S]*?(<svg[\s\S]*?<\/svg>)/)?.[1]);
  }
  assert.equal(silhouettes.size, 18, "every supported type has a distinct shape even without motion or its name");
  const unknown = render("running", "en", null, null, s => { s.tables.work_center_categories[0].icon_key = "unknown"; });
  assert.ok(machine(unknown, "M1").includes('data-machine-kind="generic"'));
  const fallback = render("running", "en", null, null, s => { s.tables.work_center_categories = []; });
  assert.ok(machine(fallback, "M1").includes('data-machine-kind="mixer"'));
});

test("machine motion stops for faults, planned stops, idle, blocked flow and borrowed home placeholders", () => {
  const cases = [["running", "M1", "running"], ["unplanned-stop", "M2", "fault"],
    ["planned-stop", "M2", "planned"], ["idle", "M1", "idle"], ["blocked", "M3", "blocked"],
    ["borrowed", "A1", "running"], ["alternative-stopped", "A1", "fault"]];
  for (const lang of ["en", "ar"]) {
    for (const [scenario, id, state] of cases) {
      assert.ok(machine(render(scenario, lang), id).includes(`data-motion-state="${state}"`));
    }
    assert.ok(machine(render("borrowed", lang), "A1", 1).includes('data-motion-state="home"'));
    assert.ok(render("running", lang).includes((lang === "ar" ? ar : en).ffPauseMotion));
  }
});

test("line pause rests motion without changing physical status or queue", () => {
  const html = render("running", "en", null, null, s => { s.tables.production_lines[0].paused_at = new Date().toISOString(); });
  const card = machine(html, "M1");
  assert.match(card, /data-physical-state="running"/);
  assert.match(card, /data-motion-state="planned"/);
  assert.ok(html.includes(en.finishProduction));
});

test("borrowed machine types retain physical motion and cyan assignment through an open-transfer stop in EN/AR", () => {
  for (const kind of ["printer", "cutter", "extruder"]) {
    for (const lang of ["en", "ar"]) {
      for (const scenario of ["borrowed", "alternative-stopped"]) {
        const html = render(scenario, lang, null, null, s => {
          s.tables.work_center_categories[0].icon_key = kind;
        });
        const card = machine(html, "A1");
        const stopped = scenario === "alternative-stopped";
        assert.match(card, /ff2-assigned/);
        assert.ok(card.includes(`ff2-accent-${stopped ? "stopped" : "running"}`));
        assert.ok(card.includes(`data-machine-kind="${kind}"`));
        assert.ok(card.includes(`data-motion-state="${stopped ? "fault" : "running"}"`));
        assert.match(card, /ff2-node-assignment/);
        assert.doesNotMatch(machine(html, "M1"), /ff2-assigned/);
        assert.match(machine(html, "A1", 1), /data-motion-state="home"/);
        assert.ok(machine(html, "A1", 1).includes(`ff2-accent-${stopped ? "stopped" : "running"}`), "home placeholder retains actual physical color while assigned away");
        assert.match(html, /ff2-branch/);
      }
    }
  }
});

test("normal and borrowed line machines omit job metadata while the line owns current production", () => {
  for (const lang of ["en", "ar"]) for (const scenario of ["running", "borrowed", "alternative-stopped"]) {
    const html = render(scenario, lang);
    for (const id of ["M1", "M2", "M3", "M4", "A1"]) {
      const card = machine(html, id);
      assert.doesNotMatch(card, /ff2-node-production|ITEM-041|PO-2026-041|PVC Pipe 25 mm|أنبوب PVC مقاس/);
      assert.doesNotMatch(card, /recording-figures/);
      assert.ok(card.indexOf('ff2-machine-motion') < card.indexOf('ff2-node-name'));
      assert.ok(card.indexOf('ff2-node-name') < card.indexOf('ff2-node-state'));
    }
    const current = html.match(/data-product-item-id="O1"[\s\S]*?<\/details>/)?.[0] || "";
    assert.ok(current.includes("PO-2026-041"));
    assert.ok(current.includes((lang === "ar" ? ar : en).recordingRemaining));
    assert.match(current, /recording-figures/);
    assert.ok(html.indexOf('data-product-item-id="O1"') < html.indexOf('class="ff2-flow"'));
    const drawer = render(scenario, lang, "M1").split('<aside')[1];
    assert.ok(drawer.includes("ITEM-041-1"), "drawer retains the exact Product Item context");
  }
});

test("independent production keeps its own product, parent request and remaining quantity", () => {
  for (const lang of ["en", "ar"]) {
    const html = render("running", lang, null, null, s => {
      s.tables.work_centers.push({ id: "I1", name: "Independent unit", name_ar: "وحدة مستقلة", line_id: null,
        status: "running", order_id: "O3", category_id: "CAT", dependency_mode: "independent" });
      s.tables.production_orders.push({ ...s.tables.production_orders[0], id: "O3", line_id: null,
        code: "ITEM-INDEPENDENT", target_quantity: 300, produced_quantity: 100 });
    });
    const card = machine(html, "I1");
    assert.match(card, /ff2-node-production/);
    assert.ok(card.includes("PO-2026-041"));
    assert.ok(card.includes((lang === "ar" ? ar : en).recordingRemaining));
    assert.ok(card.includes((200).toLocaleString(lang)));
  }
});

test("blocked/planned line cues reuse existing flow and stop classification without hiding physical state", () => {
  assert.match(render("blocked"), /ff2-line-tone-blocked/);
  assert.match(render("planned-stop"), /ff2-line-tone-planned/);
  assert.match(render("idle"), /ff2-line-tone-idle/);
  assert.match(machine(render("blocked"), "M3"), /ff2-accent-running/);
  assert.match(machine(render("planned-stop"), "M2"), /ff2-accent-planned/);
  assert.match(render("borrowed"), /ff2-line-tone-running/);
  assert.match(render("alternative-stopped"), /ff2-line-tone-blocked/);
});

test("future function types resolve from explicit identifiers without overriding a generic category", () => {
  for (const type of ["heating", "pump", "assembly"]) {
    const explicit = render("running", "en", null, null, s => {
      s.tables.work_center_categories = [];
      s.tables.work_centers[0].type = type;
    });
    assert.ok(machine(explicit, "M1").includes(`data-machine-kind="${type}"`));
    const generic = render("running", "en", null, null, s => {
      s.tables.work_center_categories[0].icon_key = "generic";
      s.tables.work_centers[0].type = type;
    });
    assert.ok(machine(generic, "M1").includes('data-machine-kind="generic"'));
  }
});

test("an independent machine borrowed into a line does not repeat that line's job context", () => {
  const html = render("borrowed", "en", null, null, s => {
    s.tables.work_centers.find(c => c.id === "A1").line_id = null;
  });
  const borrowed = machine(html, "A1");
  assert.match(borrowed, /ff2-assigned/);
  assert.doesNotMatch(borrowed, /ff2-node-production|ITEM-041|PO-2026-041/);
});

test("different lines retain their own request, product and typed quantities", () => {
  for (const lang of ["en", "ar"]) {
    const html = render("running", lang, null, null, s => {
      s.tables.products.push({id:"P2",name:"Carton pack",name_ar:"عبوات كرتونية"});
      s.tables.production_requests.push({id:"R2",code:"PO-042"});
      s.tables.production_orders.push({...s.tables.production_orders[0],id:"O3",line_id:"L2",request_id:"R2",product_id:"P2",
        target_quantity:1200,produced_quantity:800,unit:"piece"});
    });
    const line2 = html.split('data-line-id="L2"')[1].split('class="ff2-flow"')[0];
    assert.ok(line2.includes("PO-042"));
    assert.ok(line2.includes(lang === "ar" ? "عبوات كرتونية" : "Carton pack"));
    assert.ok(line2.includes((400).toLocaleString(lang)));
    assert.ok(line2.includes((lang === "ar" ? ar : en).pieceShort));
    assert.ok(!line2.includes("PO-2026-041"));
  }
});

function lineHeader(html,id="L1") {
  return html.split(`data-line-id="${id}"`)[1].split('</header>')[0];
}
test("line header follows authoritative flow in EN/AR across the required operational states", () => {
  for(const [lang,words] of [["en",en],["ar",ar]]) {
    for(const [scenario,key] of [["running","running"],["blocked","ffStateBlocked"],
      ["unplanned-stop","ffStateBlocked"],["planned-stop","ffStatePlanned"],
      ["idle","idleNoDemand"],["borrowed","runningViaAlternative"],["alternative-stopped","ffStateBlocked"]]) {
      const header=lineHeader(render(scenario,lang));
      assert.ok(header.includes(words[key]),`${lang} ${scenario} header must show ${key}`);
      if(["blocked","unplanned-stop","alternative-stopped"].includes(scenario))
        assert.ok(!header.includes(words.runningViaAlternative));
    }
  }
});
test("last stopped machine cannot leave a line header claiming Running", () => {
  const html=render("running","en",null,null,s=>{s.tables.work_centers[3].status="stopped";});
  assert.ok(lineHeader(html).includes(en.ffStateBlocked));
  assert.ok(machine(html,"M1").includes(en.running));
  assert.ok(machine(html,"M4").includes(en.stopped));
});
test("independent physical running and stopping do not determine the normal route summary", () => {
  for(const [scenario,status,key] of [["idle","running","idleNoDemand"],["running","stopped","running"]]){
    const html=render(scenario,"en",null,null,s=>{
      s.tables.work_centers.push({id:"INDEPENDENT",line_id:"L1",position:9,name:"Independent printer",
        status,dependency_mode:"independent",impact_scope:"whole_line"});
    });
    assert.ok(lineHeader(html).includes(en[key]));
    assert.ok(!lineHeader(html).includes(en.ffStateBlocked));
  }
});
