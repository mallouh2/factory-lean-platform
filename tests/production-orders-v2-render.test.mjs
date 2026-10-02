import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with { type: "json" };
import ar from "../src/locales/ar.json" with { type: "json" };
import {planningProductTones} from '../src/utils/planning.mjs';

const require = createRequire(import.meta.url);
const bundled = await build({
  entryPoints: ["src/features/ProductionOrdersV2.tsx"],
  bundle: true,
  platform: "node",
  format: "cjs",
  packages: "external",
  write: false,
  logLevel: "silent",
});
const orderModule = { exports: {} };
new Function("require", "module", "exports", bundled.outputFiles[0].text)(require, orderModule, orderModule.exports);
const ProductionOrdersV2 = orderModule.exports.default;
const editorBundle = await build({
  entryPoints: ["src/features/Configuration.tsx"], bundle: true,
  platform: "node", format: "cjs", packages: "external", write: false, logLevel: "silent",
});
const editorModule = { exports: {} };
new Function("require", "module", "exports", editorBundle.outputFiles[0].text)(require, editorModule, editorModule.exports);
const Configuration = editorModule.exports.default;
const createBundle = await build({
  entryPoints: ["src/features/CreateProductionOrder.tsx"], bundle: true,
  platform: "node", format: "cjs", packages: "external", write: false, logLevel: "silent",
});
const createModule = { exports: {} };
new Function("require", "module", "exports", createBundle.outputFiles[0].text)(require, createModule, createModule.exports);
const CreateProductionOrder = createModule.exports.default;

const snapshot = {
  user: { id: "U", email: "user@example.test" },
  membership: { user_id: "U", display_name: "Ahmad Khalil", role_id: "R", job_title: "Sales Engineer", job_title_ar: "مهندس مبيعات" },
  factory: { id: "F", timezone: "UTC" },
  tables: {
    production_requests: [
      { id: "REQ", code: "PO-101", name: "Al Rayyan Project", requested_by: "U", requested_by_name: "Ahmad Khalil", priority: "high", notes: "", created_at: "2026-09-24T12:00:00Z" },
      { id: "REQ2", code: "PO-102", name: "Warehouse replenishment", requested_by: "U", requested_by_name: "Ahmad Khalil", priority: "normal", created_at: "2026-09-23T12:00:00Z" },
    ],
    production_orders: [
      { id: "A", request_id: "REQ", code: "ITEM-101", product_id: "P", line_id: "L", status: "active", target_quantity: 500, produced_quantity: 300, unit: "meter", expected_finish: "2026-09-01T00:00:00Z" },
      { id: "B", request_id: "REQ", code: "ITEM-102", product_id: "P2", line_id: "L2", status: "completed", target_quantity: 200, produced_quantity: 200, unit: "piece" },
      { id: "C", request_id: "REQ2", code: "ITEM-103", product_id: "P", line_id: null, status: "planned", target_quantity: 60, produced_quantity: 0, unit: "meter" },
    ],
    products: [{ id: "P", name: "PVC Pipe", name_ar: "أنبوب بلاستيك" }, { id: "P2", name: "PVC Elbow", name_ar: "كوع بلاستيك" }],
    production_lines: [{ id: "L", name: "Line one", name_ar: "الخط الأول" }, { id: "L2", name: "Line three", name_ar: "الخط الثالث" }],
    roles: [{ id: "R", name: "Sales Engineer", name_ar: "مهندس مبيعات" }],
  },
};

test('Requests share Planning Product identity while lifecycle tint and creator/mobile controls remain separate in EN/AR',()=>{
  const tone=planningProductTones(snapshot.tables.products).get('P');
  for(const [lang,dictionary] of [['en',en],['ar',ar]]){
    const html=renderToStaticMarkup(createElement(ProductionOrdersV2,{
      snapshot,t:key=>dictionary[key]||key,lang,can:()=>false,command:async()=>{},
    }));
    assert.ok(html.includes(`--product-surface:${tone.surface}`));
    assert.ok(html.includes(`--product-edge:${tone.edge}`));
    assert.match(html,/data-state="delayed"/);
    assert.match(html,/data-state="waiting"/);
    assert.match(html,/data-product-id="P"/);
    assert.ok(html.includes(dictionary.requestedBy));
    assert.match(html,/value="U"/);
    assert.match(html,/popover="auto" role="dialog"/);
    assert.match(html,/popoverTarget="requests-filter-sheet"|popovertarget="requests-filter-sheet"/);
    assert.doesNotMatch(html,/Sales Owner|demo-banner/);
  }
});

test('request filters share desktop/mobile state and survive a retained-snapshot refresh without commands',()=>{
  const data=structuredClone(snapshot);data.tables.production_requests[1].requested_by='U2';
  data.tables.production_requests[1].requested_by_name='Another requester';
  const states=[];let hook=0;
  const react=require('react'),mod={exports:{}};
  new Function('require','module','exports',bundled.outputFiles[0].text)(name=>name==='react'?{...react,
    useState:initial=>{const i=hook++;if(!(i in states))states[i]=typeof initial==='function'?initial():initial;
      return[states[i],next=>{states[i]=typeof next==='function'?next(states[i]):next;}];},
    useRef:()=>({current:null}),useEffect:()=>{},
  }:require(name),mod,mod.exports);
  function all(node){if(!node||typeof node!=='object')return[];if(Array.isArray(node))return node.flatMap(all);
    return[node,...all(node.props?.children)];}
  function render(){hook=0;return all(mod.exports.default({snapshot:data,lang:'en',t:key=>en[key]||key,
    can:()=>false,command:()=>{throw Error('filters must not write');}}));}
  const rows=nodes=>nodes.filter(node=>node.type==='button'&&node.props['data-state']);
  let nodes=render();assert.equal(rows(nodes).length,2);
  nodes.find(node=>node.type==='button'&&node.props.children?.[0]===en.plannedWaiting).props.onClick();
  nodes=render();assert.equal(rows(nodes).length,1);
  const creator=nodes.find(node=>node.type==='label'&&node.props.children?.[0]?.props.children===en.requestedBy).props.children[1];
  creator.props.onChange({target:{value:'U2'}});
  data.fetchedAt='new retained snapshot';nodes=render();assert.equal(rows(nodes).length,1);
  const copies=nodes.filter(node=>node.type==='label'&&node.props.children?.[0]?.props.children===en.requestedBy);
  assert.equal(copies.length,2);for(const label of copies)assert.equal(label.props.children[1].props.value,'U2');
  nodes.find(node=>node.type==='button'&&node.props.children===en.historyClear).props.onClick();
  assert.equal(rows(render()).length,2);
});

test('active request rows retain labelled planned timestamps without reclassifying the execution item',()=>{
  const data=structuredClone(snapshot);data.tables.production_orders[0].start_time='2026-09-01T00:00:00Z';
  const before=JSON.stringify(data);
  for(const [lang,words] of [['en',en],['ar',ar]]){
    const html=renderToStaticMarkup(createElement(ProductionOrdersV2,{snapshot:data,lang,t:key=>words[key]||key,can:()=>false,command:async()=>{}}));
    assert.ok(html.includes(words.executionPlannedStart));assert.ok(html.includes(words.executionPlannedFinish));
    assert.ok(html.includes(words.executionInProduction));
  }
  assert.equal(JSON.stringify(data),before);
});

test('request work queue distinguishes a recorded schedule from waiting without rewriting lifecycle facts in EN/AR', () => {
  for (const [lang, dictionary] of [['en', en], ['ar', ar]]) {
    const data = structuredClone(snapshot);
    data.tables.production_orders[0] = { ...data.tables.production_orders[0], status: 'planned',
      start_time: '2026-10-08T08:00:00Z', expected_finish: '2026-10-08T09:00:00Z' };
    data.tables.production_orders[1] = { ...data.tables.production_orders[1], status: 'planned',
      start_time: '2026-10-08T09:00:00Z', expected_finish: '2026-10-08T10:00:00Z' };
    const before = JSON.stringify(data);
    const html = renderToStaticMarkup(createElement(ProductionOrdersV2, {
      snapshot: data, t: key => dictionary[key] || key, lang, can: () => false, command: async () => {},
    }));
    assert.ok(html.includes(dictionary.requestScheduled));
    assert.ok(html.includes(dictionary.requestAwaitingPlanning));
    assert.ok(html.includes(dictionary.executionPlannedStart));
    assert.ok(html.includes(dictionary.executionPlannedFinish));
    assert.ok(html.includes(dictionary.requestQueueSearch));
    assert.ok(html.includes(lang === 'ar' ? 'الخط الأول' : 'Line one'));
    assert.equal(JSON.stringify(data), before);
    assert.doesNotMatch(html, /historyClearAll|notRecorded/);
  }
});

test("English request scan shows one header for multiple products and item count", () => {
  const html = renderToStaticMarkup(createElement(ProductionOrdersV2, {
    snapshot, t: (key) => en[key] || key, lang: "en", can: () => true, command: async () => {},
  }));
  assert.match(html, /PO-101/);
  assert.equal((html.match(/PO-101/g) || []).length, 1);
  assert.match(html, /Al Rayyan Project/);
  assert.match(html, /2 products/);
  assert.match(html, /500 m/);
  assert.match(html, /200 pcs/);
  assert.match(html, /Ahmad Khalil/);
  assert.match(html, /1 of 2 items completed/);
  assert.match(html, /High/);
  assert.match(html, /Expected completion has passed/);
  assert.match(html, /Planned \/ Waiting/);
  assert.match(html, /Completed/);
  assert.doesNotMatch(html, /<table/);
});

test("Arabic request scan keeps localized labels and LTR request code", () => {
  const html = renderToStaticMarkup(createElement(ProductionOrdersV2, {
    snapshot, t: (key) => ar[key] || key, lang: "ar", can: () => false, command: async () => {},
  }));
  assert.match(html, /المنتجات/);
  assert.match(html, /عدد المنتجات: 2/);
  assert.match(html, /<bdi dir="ltr">PO-101<\/bdi>/);
  assert.match(html, /متأخر/);
  assert.doesNotMatch(html, /إنشاء أمر إنتاج/);
});

test("request creation exposes header, repeatable item controls, requester and optional fields in both languages", () => {
  for (const [lang, dictionary, requestName, quantity, selectProduct] of [
    ["en", en, "Production Request Name", "Required quantity", "Select a product"],
    ["ar", ar, "اسم طلب الإنتاج", "الكمية المطلوبة", "اختر منتجًا"],
  ]) {
    const html = renderToStaticMarkup(createElement(CreateProductionOrder, {
      snapshot, t: (key) => dictionary[key] || key, lang, can: () => true,
      command: async () => {}, onCreated: () => {}, onCancel: () => {},
    }));
    assert.match(html, new RegExp(requestName));
    assert.match(html, new RegExp(quantity));
    // one searchable product combobox per item row; its listbox only renders while open, so
    // at rest no products are listed and filtering/selecting happens entirely on the client
    assert.match(html, /<input id="request-product-0" role="combobox" type="text"/);
    assert.match(html, /aria-autocomplete="list"/);
    assert.match(html, /aria-controls="request-product-options-0"/);
    assert.match(html, new RegExp(`placeholder="${selectProduct}"`));
    assert.match(html, /aria-expanded="false"/);
    assert.doesNotMatch(html, /role="listbox"/);
    assert.doesNotMatch(html, /<select[^>]*id="request-product/);
    assert.doesNotMatch(html, /type="search"/);
    assert.doesNotMatch(html, /PVC Pipe|أنبوب بلاستيك/);
    assert.match(html, /Add product|إضافة منتج/);
    assert.match(html, /Remove|إزالة/);
    assert.match(html, /Ahmad Khalil/);
    assert.match(html, /Sales Engineer|مهندس مبيعات/);
    assert.match(html, /readOnly/);
    assert.match(html, /Meter|متر/);
    assert.match(html, /Piece|قطعة/);
    assert.match(html, /<option value="normal" selected="">/);
    for (const value of ["low", "high", "urgent"]) assert.match(html, new RegExp(`value="${value}"`));
    assert.doesNotMatch(html, /value="unspecified"/);
    assert.doesNotMatch(html, /Find product|ابحث عن منتج/);
    assert.match(html, /type="datetime-local"/);
    assert.match(html, /<textarea/);
    for (const field of ["code", "line_id", "start_time", "operator_id", "status"])
      assert.doesNotMatch(html, new RegExp(`name="${field}"`));
  }
});
test("later planning editor still allows line and start time without changing the generated code", () => {
  const html = renderToStaticMarkup(createElement(Configuration, {
    snapshot, t: (key) => en[key] || key, lang: "en", can: () => true,
    command: async () => {}, view: "orders",
    standalone: { record: snapshot.tables.production_orders[1], onSaved: () => {}, onCancel: () => {} },
  }));
  assert.match(html, /name="product_id"/);
  assert.match(html, /name="target_quantity"/);
  assert.match(html, /name="line_id"/);
  assert.match(html, /name="start_time"/);
  assert.doesNotMatch(html, /name="code"/);
  assert.doesNotMatch(html, /name="operator_id"/);
});

test("generic order editor no longer exposes a create button", () => {
  const html = renderToStaticMarkup(createElement(Configuration, {
    snapshot, t: (key) => en[key] || key, lang: "en", can: () => true,
    command: async () => {}, view: "orders",
  }));
  assert.doesNotMatch(html, /<button class="primary">\+ Add<\/button>/);
});

// ---------------------------------------------------------------------------
// Required By (business deadline) creation path. A partially entered
// datetime-local displays segments while reporting value "" with
// validity.badInput = true; submission must be blocked with a clear error
// instead of silently saving a missing deadline. A complete value converts to
// UTC and reaches create_production_request unchanged; empty stays null.
// ---------------------------------------------------------------------------
function createSubmitHarness({ requiredBy = "", badInput = false, reason = "QA internal reason", allowed = true, command } = {}) {
  const created = [];
  const bag = {};
  const commandImpl = command ?? (async (name, args) => {
    bag.saved = { name, args };
    return "REQ-NEW";
  });
  const state = [
    "Required By path verification",
    [{ key: 0, productId: "P", quantity: "100", unit: "meter", query: "", open: false, active: -1 }],
    "normal",
    requiredBy,
    reason,
    {},
    false,
  ];
  const updates = [];
  const fakeReact = { useState: (() => { let index = 0;
    return (fallback) => { const position = index++;
      return [state[position] ?? (typeof fallback === "function" ? fallback() : fallback),
        (value) => updates.push({ position, value })]; }; })(),
    useEffect: () => {}, useRef: () => ({ current: null }) };
  const moduleWithHooks = { exports: {} };
  new Function("require", "module", "exports", createBundle.outputFiles[0].text)(
    (name) => name === "react" ? fakeReact : require(name), moduleWithHooks, moduleWithHooks.exports);
  const tree = moduleWithHooks.exports.default({ snapshot,
    t: (key) => en[key] || key, lang: "en", can: () => allowed, command: commandImpl,
    onCreated: (id) => created.push(id), onCancel: () => {} });
  const form = (function find(node) {
    if (!node || typeof node !== "object") return null;
    if (Array.isArray(node)) { for (const child of node) { const hit = find(child); if (hit) return hit; } return null; }
    if (node.type === "form") return node;
    return find(node.props?.children);
  })(tree);
  return {
    updates, created, bag,
    submit: async () => {
      const previous = globalThis.document;
      globalThis.document = { activeElement: null,
        getElementById: (id) => id === "request-required-by"
          ? { validity: { badInput: Boolean(badInput) }, focus() {} } : null };
      try { await form.props.onSubmit({ preventDefault() {} }); }
      finally { globalThis.document = previous; }
    },
  };
}

test('internal creation rejects missing, whitespace and oversized reasons before calling the server', async () => {
  for (const reason of ['', ' \t\n ', 'x'.repeat(2001)]) {
    const harness = createSubmitHarness({reason});
    await harness.submit();
    assert.equal(harness.bag.saved, undefined);
    assert.equal(harness.updates.find(update => update.position === 5).value.reason, 'internalReasonRequired');
  }
});

test('internal creation checks person permission even when the form is called directly', async () => {
  const harness = createSubmitHarness({allowed:false});
  await harness.submit();
  assert.equal(harness.bag.saved, undefined);
  assert.deepEqual(harness.updates[0].value, {submit:'permissionError'});
});

test('internal creation trims its reason and submits no browser actor or demand type', async () => {
  const harness = createSubmitHarness({reason:'  Engineering trial  '});
  await harness.submit();
  assert.equal(harness.bag.saved.args.request_notes,'Engineering trial');
  assert.equal('request_type' in harness.bag.saved.args,false);
  assert.equal('requested_by' in harness.bag.saved.args,false);
});

test('EN/AR internal request form has required reason and renamed manual action', () => {
  for (const [lang, dictionary] of [['en',en],['ar',ar]]) {
    const html=renderToStaticMarkup(createElement(CreateProductionOrder,{snapshot,t:key=>dictionary[key]||key,lang,can:()=>true,command:async()=>{},onCreated:()=>{},onCancel:()=>{}}));
    assert.ok(html.includes(dictionary.createProductionRequest));
    assert.ok(html.includes(dictionary.internalProductionReason));
    assert.match(html,/<textarea[^>]*id="request-notes"[^>]*required/);
    assert.ok(html.includes(dictionary.internalCreatedBy));
  }
});

test("a filled Required By reaches the create command converted to UTC", async () => {
  const harness = createSubmitHarness({ requiredBy: "2026-10-05T15:00" });
  await harness.submit();
  assert.deepEqual(harness.bag.saved, { name: "create_production_request", args: {
    factory: "F",
    request_name: "Required By path verification",
    request_priority: "normal",
    request_required_by: "2026-10-05T15:00:00.000Z",
    request_notes: "QA internal reason",
    request_items: [{ product_id: "P", quantity: 100, unit: "meter" }],
  } });
  assert.deepEqual(harness.created, ["REQ-NEW"]);
});

test("an incomplete Required By entry blocks submission instead of silently saving null", async () => {
  const harness = createSubmitHarness({ requiredBy: "2026-10-05T15:00", badInput: true });
  await harness.submit();
  assert.equal(harness.bag.saved, undefined);
  const lastError = harness.updates.filter((update) => update.position === 5).at(-1).value;
  assert.equal(typeof lastError, "function");
  assert.deepEqual(lastError({}), { requiredBy: "orderRequiredByInvalid" });
  assert.deepEqual(harness.created, []);
});

test("an empty Required By still creates the request without a deadline", async () => {
  const harness = createSubmitHarness({ requiredBy: "" });
  await harness.submit();
  assert.equal(harness.bag.saved.args.request_required_by, null);
  assert.deepEqual(harness.created, ["REQ-NEW"]);
});

test("the deadline field presents the business-deadline meaning in English and Arabic", () => {
  for (const [lang, dictionary] of [["en", en], ["ar", ar]]) {
    const html = renderToStaticMarkup(createElement(CreateProductionOrder, {
      snapshot, t: (key) => dictionary[key] || key, lang, can: () => true,
      command: async () => {}, onCreated: () => {}, onCancel: () => {} }));
    assert.match(html, /type="datetime-local"/);
    assert.ok(html.includes(dictionary.requiredBy));
    assert.ok(html.includes(dictionary.requiredByHint));
  }
});
