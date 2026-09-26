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
