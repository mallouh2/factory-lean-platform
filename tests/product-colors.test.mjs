import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { build } from 'esbuild';
import { productColor } from '../src/utils/product-colors.mjs';
import { planningProductTones } from '../src/utils/planning.mjs';
import { floorSnapshot } from './fixtures/factory-floor.mjs';
import en from '../src/locales/en.json' with { type: 'json' };
import ar from '../src/locales/ar.json' with { type: 'json' };

const id = '7ffb504e-d87d-4bcc-a02c-014b4f885f48';
const product = { id, name: 'Pipe', name_ar: 'أنبوب' };
const catalog = [{ id: '00000000-0000-0000-0000-000000000001' }, product, { id: 'ffffffff-ffff-ffff-ffff-ffffffffffff' }];
const expected = productColor(id);

test('same Product ID is stable across fresh deserialization and UUID casing', () => {
  assert.deepEqual(expected, { surface: '#f4c2e7', ink: '#5f114a', edge: '#d025a1' }, 'fixed identity vector prevents accidental remapping');
  for (let i = 0; i < 20; i++) assert.deepEqual(productColor(JSON.parse(JSON.stringify(product)).id), expected);
  assert.deepEqual(productColor(id.toUpperCase()), expected);
});
test('inserting Products before and after an existing Product does not change its tone', () => {
  assert.deepEqual(planningProductTones([product]).get(id), planningProductTones(catalog).get(id));
});
test('removing other Products does not change its tone', () => {
  assert.deepEqual(planningProductTones(catalog.slice(1)).get(id), expected);
  assert.deepEqual(planningProductTones(catalog.slice(0, 2)).get(id), expected);
});
test('sorting and render order cannot change Product identity', () => {
  assert.deepEqual(planningProductTones([...catalog].reverse()).get(id), expected);
  assert.deepEqual(planningProductTones([catalog[2], catalog[0], product]).get(id), expected);
});
test('filtered and partial catalogs use the same Product tone', () => {
  assert.deepEqual(planningProductTones(catalog.filter(p => p.id === id)).get(id), expected);
});
test('rename, translated name, locale and object property order are irrelevant', () => {
  for (const p of [{ ...product, name: 'Renamed', name_ar: 'اسم جديد' }, { name_ar: 'غير ذلك', name: 'Other', id }]) {
    assert.deepEqual(planningProductTones([p]).get(id), expected);
  }
});
test('missing or malformed Product ID uses stable item identity without names or random state', () => {
  const itemId = '6dba6e4b-da06-5440-a2d9-bcfcdd68ca86';
  const tone = productColor(null, itemId);
  for (const invalid of [undefined, null, '', '  ', {}, [], false, 12, NaN]) {
    assert.deepEqual(productColor(invalid, itemId), tone);
    assert.deepEqual(productColor(invalid), productColor(null));
  }
  assert.deepEqual(productColor(null, itemId.toUpperCase()), tone);
  assert.deepEqual(productColor('legacy-product'), productColor('legacy-product'));
  assert.deepEqual(productColor(id, 'another-item'), expected, 'canonical Product ID takes priority');
});
test('direct colors are valid and varied, including long and Unicode legacy identifiers', () => {
  const seen = new Set();
  for (const key of ['', null, 'أنبوب', 'x'.repeat(10000), ...Array.from({ length: 1000 }, (_, i) => `legacy-${i}`)]) {
    const tone = productColor(key);
    for (const color of Object.values(tone)) assert.match(color, /^#[0-9a-f]{6}$/);
    assert.ok(Object.isFrozen(tone));
    seen.add(JSON.stringify(tone));
  }
  assert.ok(seen.size > 950, 'identity is not restricted to a twelve-color palette');
});
const testingProductIds = [
  'fc2aa5d5-96ec-56c9-8635-bc99cf5b737e', 'cc5a5f83-4e00-5f1f-ab28-ce5c17db90cb',
  'bf6a9de2-16d6-5fa6-b637-85b214706608', 'b5ad4f6d-7d8b-43ce-b0e6-710ff9d11e2a',
  '85caedc8-2da5-41b9-966a-5d045b28604f',
];
function luminance(hex) {
  const channels = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map(c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}
function hsl(hex) {
  const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min, l = (max + min) / 2;
  const hue = d === 0 ? 0 : ((max === r ? (g - b) / d : max === g ? (b - r) / d + 2 : (r - g) / d + 4) * 60 + 360) % 360;
  return { hue, saturation: d / (1 - Math.abs(2 * l - 1)) * 100, lightness: l * 100 };
}
test('controlled industrial HSL families retain readable text contrast', () => {
  for (const key of [...testingProductIds, ...Array.from({ length: 1000 }, (_, i) => `contrast-${i}`)]) {
    const tone = productColor(key), surface = hsl(tone.surface), edge = hsl(tone.edge), ink = hsl(tone.ink);
    assert.ok(surface.saturation >= 36 && surface.saturation <= 76 && surface.lightness >= 84 && surface.lightness <= 92);
    assert.ok(edge.saturation >= 36 && edge.saturation <= 76 && edge.lightness >= 21 && edge.lightness <= 58);
    assert.ok(ink.lightness >= 21 && ink.lightness <= 26);
    assert.ok((luminance(tone.surface) + 0.05) / (luminance(tone.ink) + 0.05) >= 4.5);
  }
});
test('current TESTING catalog has no exact duplicate surfaces, inks or accents', () => {
  const tones = testingProductIds.map(productColor);
  for (const part of ['surface', 'ink', 'edge']) assert.equal(new Set(tones.map(t => t[part])).size, tones.length);
});

const semanticTokens = {
  green: ['#2f9e63', '#16a34a'], red: ['#d64545', '#dc2626'], orange: ['#d98324', '#f59e0b'], primary: ['#2563eb'],
  blocked: ['#7c3aed'], blue: ['#3b7dd8', '#0891b2'], gray: ['#8a8a8f', '#94a3b8'],
};
// Independent CIELAB distance check against the real CSS tokens, without a runtime dependency.
function lab(hex) {
  const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map(c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const xyz = [(r * .4124564 + g * .3575761 + b * .1804375) / .95047,
    r * .2126729 + g * .7151522 + b * .0721750,
    (r * .0193339 + g * .1191920 + b * .9503041) / 1.08883];
  const [x, y, z] = xyz.map(v => v > .008856 ? Math.cbrt(v) : 7.787 * v + 16 / 116);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}
function distance(a, b) {
  const other = lab(b);
  return Math.hypot(...lab(a).map((v, i) => v - other[i]));
}
test('all five current catalog accents are perceptually distinct, beyond the former narrow magenta family', () => {
  const tones = testingProductIds.map(productColor);
  for (let i = 0; i < tones.length; i++) for (let j = i + 1; j < tones.length; j++) {
    assert.ok(distance(tones[i].edge, tones[j].edge) >= 18, `${i}/${j}: catalog accent separation`);
  }
  assert.equal(new Set(tones.slice(0, 3).map(t => hsl(t.edge).hue < 40 ? 'earth' : hsl(t.edge).hue < 310 ? 'plum' : 'rose')).size, 3);
});
test('red-like and green-like families are hard excluded, including legacy fallbacks', () => {
  for (const key of [...testingProductIds, null, '', ...Array.from({ length: 1000 }, (_, i) => `exclusion-${i}`)]) {
    for (const color of Object.values(productColor(key, 'legacy-item'))) {
      const { hue } = hsl(color);
      assert.ok((hue >= 22 && hue <= 36) || (hue >= 288 && hue <= 329), `${key}: ${color} leaves checked earth/berry bands`);
    }
    const edge = hsl(productColor(key, 'legacy-item').edge);
    if (edge.hue < 40) assert.ok(edge.lightness < 40, 'earth accent never becomes amber/orange attention');
  }
});
test('identity accents remain perceptually separated from every unchanged operational CSS token', () => {
  const css = readFileSync(new URL('../src/app/globals.css', import.meta.url), 'utf8');
  for (const [name, value] of Object.entries(semanticTokens)) {
    const declarations = [...css.matchAll(new RegExp(`--ff2-${name}:\\s*(#[0-9a-f]{6})`, 'gi'))];
    assert.ok(declarations.length > 0, name);
    assert.deepEqual([...new Set(declarations.map(d => d[1].toLowerCase()))], value, `${name}: status tokens unchanged`);
  }
  for (const key of [...testingProductIds, ...Array.from({ length: 1000 }, (_, i) => `semantic-${i}`)]) {
    const tone = productColor(key);
    for (const [name, values] of Object.entries(semanticTokens)) {
      for (const value of values) assert.ok(distance(tone.edge, value) >= 30, `${key}: ${name} accent separation`);
    }
  }
});

const require = createRequire(import.meta.url);
const pages = {};
for (const page of ['FactoryFloorV2', 'ProductionPlanning', 'ProductionOrdersV2', 'ProductionHistory']) {
  const output = await build({ entryPoints: [`src/features/${page}.tsx`], bundle: true,
    platform: 'node', format: 'cjs', packages: 'external', write: false, logLevel: 'silent' });
  const module = { exports: {} };
  new Function('require', 'module', 'exports', output.outputFiles[0].text)(require, module, module.exports);
  pages[page] = module.exports.default;
}
function renderPage(page, products, lang, productId = id) {
  const snapshot = floorSnapshot();
  snapshot.tables.products = products;
  snapshot.tables.production_orders.forEach(item => { item.product_id = productId; });
  snapshot.tables.work_center_capabilities.forEach(capability => { capability.product_id = productId; });
  const initial = { page: 1, page_size: 50, total: 1, totals: [], highest: [], rows: [{
    id: 'ENTRY', order_id: 'O1', product_id: productId, request_code: 'PO-2026-041',
    product_name: 'Pipe', product_name_ar: 'أنبوب', created_at: '2026-10-01T10:00:00Z',
    effective_good: 10, effective_scrap: 1, unit: 'meter', corrections: [],
  }] };
  const before = structuredClone({ snapshot, initial });
  const dictionary = lang === 'ar' ? ar : en;
  const html = renderToStaticMarkup(createElement(pages[page], { snapshot, initial, lang,
    t: key => dictionary[key] || key, can: () => true, onCorrect: () => {}, onManage: () => {},
    command: () => { throw Error('Identity rendering must not write'); } }));
  assert.deepEqual({ snapshot, initial }, before, 'color presentation never changes production/scheduling data');
  return html;
}
for (const lang of ['en', 'ar']) {
  test(`all four pages share the same Product tone across full, reordered, renamed and missing catalogs (${lang})`, () => {
    for (const [page] of Object.entries(pages)) {
      for (const products of [catalog, [...catalog].reverse(), [product], [{ ...product, name: 'Renamed', name_ar: 'جديد' }], []]) {
        const html = renderPage(page, products, lang);
        assert.ok(html.includes(`--product-surface:${expected.surface}`), `${page}: chip identity`);
        assert.ok(html.includes(`--product-edge:${expected.edge}`));
        assert.ok(html.includes(`--product-ink:${expected.ink}`));
        if (page === 'ProductionPlanning') assert.ok(html.includes(`--planning-product-bg:${expected.surface}`));
      }
    }
  });
}
test('legacy History declarations and operational pages share the Product Item fallback', () => {
  const tone = productColor(null, 'O1');
  for (const [page] of Object.entries(pages)) {
    const html = renderPage(page, [], 'en', null);
    assert.ok(html.includes(`--product-surface:${tone.surface}`), page);
    if (page === 'ProductionPlanning') assert.ok(html.includes(`--planning-product-bg:${tone.surface}`));
  }
});

test('changing Product identity never changes operational state presentation on any page', () => {
  for (const page of Object.keys(pages)) {
    const first = renderPage(page, catalog, 'en', testingProductIds[0]);
    const second = renderPage(page, catalog, 'en', testingProductIds[1]);
    const states = html => html.match(/(?:data-state|data-flow|data-status|class)="[^"]*(?:active|running|planned|completed|waiting|blocked|scheduled)[^"]*"/g) || [];
    assert.deepEqual(states(first), states(second), page);
    assert.ok(first.includes(`--product-edge:${productColor(testingProductIds[0]).edge}`));
    assert.ok(second.includes(`--product-edge:${productColor(testingProductIds[1]).edge}`));
  }
});
