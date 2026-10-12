import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { build } from 'esbuild';
import { NextRequest } from 'next/server.js';
import ExcelJS from 'exceljs';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { collectTableRows, tableWorkbook, tablePrintHtml, reportValue } from '../src/utils/table-export.mjs';
import en from '../src/locales/en.json' with { type: 'json' };
import ar from '../src/locales/ar.json' with { type: 'json' };
const require = createRequire(import.meta.url), id = '12345678-1234-1234-1234-123456789abc';
const bundle = async entry => (await build({ entryPoints: [entry], bundle: true, platform: 'node', format: 'cjs', packages: 'external', write: false, logLevel: 'silent',
  plugins: [{ name: 'auth-fixture', setup(b) { b.onResolve({ filter: /services\/authorization$/ }, () => ({ path: 'fixture:auth', external: true })); } }] })).outputFiles[0].text;
function load(code, mocks = {}) { const m = { exports: {} }; new Function('require', 'module', 'exports', code)(n => mocks[n] || require(n), m, m.exports); return m.exports; }
const routeCode = await bundle('src/app/api/table-export/route.ts');
const { exportRequest } = load(await bundle('src/services/table-export.ts'));
const { operationalReport, operationalFilterText } = load(await bundle('src/services/table-export-operational.ts'));
const production = n => ({ id: 'entry-' + n, factory_id: id, product_id: id, request_code: 'PO-44', item_code: 'PI-44', product_name: 'Pipe', product_name_ar: 'أنبوب', unit_name: 'Line 1', unit_name_ar: 'الخط ١', shift_name: 'Night', shift_name_ar: 'الليل', created_at: '2026-10-10T01:00:00Z', technician_name: 'Recorder', submitter_name: 'Supervisor', good_quantity: 10, effective_good: 7, effective_scrap: 3, effective_unfinished: 2, unit: 'piece', corrected: true, corrections: [{ corrected_good: 7 }], secret_token: 'PRIVATE' });
const stock = n => ({ id: 'stock-' + n, row_key: 'finished:stock-' + n, entity: 'finished', name: 'Pipe', name_ar: 'أنبوب', code: 'P-25', item_type: 'FINISHED_GOOD', unit: 'meter', on_hand: 20, reserved: 5, available: 15, semi_finished: 3, in_production: 8, minimum_stock: null, maximum_stock: 30, replenishment_status: 'OK', source_id: 'invented-source', traceability: 'UNATTRIBUTED', quality_reserved_wip: 10 });
const movement = n => ({ id: 'move-' + n, kind: n % 2 ? 'dispatch' : 'reservation', quantity: n % 2 ? -3 : 0, reserved_delta: n % 2 ? -3 : 5, unit: n % 2 ? 'piece' : 'meter', created_at: '2026-10-10T01:00:00Z', reference: '=HYPERLINK("bad")', note: '<img src=x>', actor_name: 'Warehouse receiver', created_by: 'PRIVATE-USER-ID', source_id: 'PRIVATE-SOURCE' });
const body = (dataset, overrides = {}) => ({ factory: id, dataset, filters: dataset === 'warehouse-movements' ? { item: id, item_type: 'finished' } : {}, language: 'en', format: 'excel', ...overrides });
const report = (dataset, rows, language = 'en') => ({ ...operationalReport(dataset, language, rows, { name: 'Pipe', name_ar: 'أنبوب', code: 'P-25' }), factory: 'Factory', timezone: 'Asia/Riyadh', language, timestamp: '2026-10-10T01:00:00Z', filters: 'All' });
test('Hosted Quality movement kinds export readable bilingual labels instead of internal keys', async () => {
  const kinds = ['quality_rejection', 'quality_reversal', 'material_issue'];
  for (const language of ['en', 'ar']) {
    const data = report('warehouse-movements', kinds.map((kind, n) => ({ ...movement(n), kind })), language);
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(await tableWorkbook(data));
    const values = JSON.stringify(workbook.worksheets[0].getSheetValues());
    for (const kind of kinds) {
      assert.ok(!values.includes('movement_' + kind));
      assert.ok(values.includes((language === 'ar' ? ar : en)['movement_' + kind]));
    }
  }
});
async function sheet(response) { assert.equal(response.status, 200, await response.clone().text()); const book = new ExcelJS.Workbook(); await book.xlsx.load(await response.arrayBuffer()); return book.worksheets[0]; }
function fixture({ rows = [], denied = false, expired = false, missingItem = false, badFactory = false, revoke = false, error = null } = {}) {
  const calls = [], grants = [];
  let requestedDataset;
  const db = {
    from(table) {
      assert.ok(['factories', 'products', 'production_entries'].includes(table));
      return { select(fields) { return { eq(key, factory) {
        assert.equal(factory, id); calls.push({ table, fields, key, factory });
        return { single: async () => ({ data: { id: badFactory ? 'other' : id, name: 'Factory', timezone: 'Asia/Riyadh' } }),
          in: async (key, ids) => ({ data: table === 'products' ? [{ id, code: 'P-25' }] : ids.map(id => ({ id, effective_scrap_kg: .75, effective_startup_kg: null, produced_weight_kg: 2.25 })) }) };
      } }; } };
    },
    async rpc(name, args) {
      calls.push({ name, args }); assert.equal(args.factory, id);
      if (error) return { error };
      if (name === 'warehouse_inventory' && requestedDataset === 'warehouse-movements') return { data: { rows: missingItem ? [] : [{ ...stock(1), id, row_key: 'finished:' + id }, { ...stock(2), id, entity: 'material', row_key: 'material:' + id }], total: missingItem ? 0 : 2 } };
      const size = name === 'warehouse_movements' ? 25 : 50;
      return { data: { rows: rows.slice((args.page - 1) * size, args.page * size), total: rows.length } };
    },
  };
  const route = load(routeCode, { 'fixture:auth': {
    verifyOrigin() {}, async authenticatedClient() { if (expired) throw Error('unauthorized'); return { db, user: { id } }; },
    async authorize(factory, module, action) { grants.push({ factory, module, action }); if (denied || (revoke && grants.length > 1)) throw Error('permission_denied'); },
  } });
  return { calls, grants, post: b => { requestedDataset = b.dataset; return route.POST(new NextRequest('http://localhost/api/table-export', { method: 'POST', body: JSON.stringify(b) })); } };
}
test('Production export forwards date, shift, unit, correction and numeric filters across every sorted page', async () => {
  const rows = Array.from({ length: 123 }, (_, n) => production(n)), r = fixture({ rows });
  const filters = { from: '2026-10-01', to: '2026-10-11', product: id, request: id, shift: id + ',unknown', technician: id, unit: 'line:' + id, corrected: 'yes', measurement_unit: 'piece', good_op: 'gte', good_min: '5' };
  const s = await sheet(await r.post(body('production-history', { filters, sort: 'good', direction: 'asc' })));
  assert.equal(s.getCell('B6').value, 123); assert.equal(s.getCell('C9').value, 'P-25'); assert.equal(s.getCell('J9').value, 7); assert.equal(s.getCell('N9').value, .75);
  const calls = r.calls.filter(c => c.name === 'production_history'); assert.deepEqual(calls.map(c => c.args.page), [1, 2, 3, 1, 2, 3]);
  for (const c of calls) { assert.deepEqual(c.args.filters, filters); assert.equal(c.args.sort_key, 'good'); assert.equal(c.args.sort_direction, 'asc'); }
  assert.deepEqual(r.grants, Array.from({ length: 2 }, () => ({ factory: id, module: 'orders', action: 'view' })));
});
test('Production corrections stay one row with original/current gross, discarded units, WIP and Scrap KG separate', async () => {
  const b = new ExcelJS.Workbook(); await b.xlsx.load(await tableWorkbook(report('production-history', [production(1)]))); const s = b.worksheets[0];
  assert.equal(s.getCell('B6').value, 1); assert.equal(s.getCell('I9').value, 10); assert.equal(s.getCell('J9').value, 7); assert.equal(s.getCell('K9').value, 3); assert.equal(s.getCell('L9').value, 2);
  assert.equal(s.getCell('N9').value, null); assert.equal(s.getCell('J8').value, en.tableExportCorrectedGross);
  assert.equal(s.getSheetValues().flat().includes('Accepted Good'), false);
});
test('Stock reuses typed AND/OR filters and sort for all matching rows, preserving reservations and WIP', async () => {
  const r = fixture({ rows: Array.from({ length: 121 }, (_, n) => stock(n)) });
  const filters = { item_type: ['FINISHED_GOOD', 'RAW_MATERIAL'], code: 'P-%_', reserved: { op: 'positive' }, available: { op: 'range', value: 1, to: 20 }, minimum_stock: { op: 'not_configured' } };
  const s = await sheet(await r.post(body('warehouse-stock', { filters, sort: 'available', direction: 'desc' })));
  assert.equal(s.getCell('B6').value, 121); for (const [column, value] of [['E', 20], ['F', 3], ['G', 8], ['H', 5], ['I', 15], ['J', null]]) assert.equal(s.getCell(column + '9').value, value);
  const calls = r.calls.filter(c => c.name); assert.equal(calls.length, 6); for (const c of calls) { assert.equal(c.name, 'warehouse_inventory'); assert.deepEqual(c.args.filters, filters); assert.equal(c.args.sort, 'available'); assert.equal(c.args.direction, 'desc'); }
  assert.equal(r.grants[0].module, 'warehouse');
});
test('Catalogue identity includes entity so a material and Product cannot collide; unknown units stay unknown', async () => {
  const rows = [{ ...stock(1), id, row_key: 'finished:' + id, unit: null, on_hand: null }, { ...stock(2), id, row_key: 'material:' + id, item_type: 'RAW_MATERIAL', unit: 'kg' }];
  const s = await sheet(await fixture({ rows }).post(body('warehouse-stock'))); assert.equal(s.getCell('B6').value, 2); assert.equal(s.getCell('D9').value, null); assert.equal(s.getCell('E9').value, null); assert.equal(s.getCell('D10').value, en.kg);
});
test('Historical pooled stock is never assigned guessed provenance or exposed as additional free stock', () => {
  const r = report('warehouse-stock', [stock(1)]), text = tablePrintHtml(r);
  assert.equal(r.rows[0].available, 15); for (const v of ['invented-source', 'UNATTRIBUTED', 'quality_reserved_wip', 'source_id']) assert.equal(text.includes(v), false);
  assert.equal(Object.keys(r.rows[0]).includes('quality_reserved_wip'), false);
});
test('Movement history uses actual 25-row pages, selected item, signed stock and distinct reservation deltas', async () => {
  const r = fixture({ rows: Array.from({ length: 63 }, (_, n) => movement(n)) }); const s = await sheet(await r.post(body('warehouse-movements')));
  assert.equal(s.getCell('B6').value, 63); assert.equal(s.getCell('G9').value, 0); assert.equal(s.getCell('H9').value, 5); assert.equal(s.getCell('G10').value, -3); assert.equal(s.getCell('D9').value, 'Pipe');
  const calls = r.calls.filter(c => c.name === 'warehouse_movements'); assert.deepEqual(calls.map(c => c.args.page), [1, 2, 3, 1, 2, 3]);
  for (const c of calls) assert.deepEqual(c.args, { factory: id, item: id, item_type: 'finished', page: c.args.page });
  assert.equal(s.getCell('B9').type, ExcelJS.ValueType.String); assert.equal(s.getCell('B9').formula, undefined); assert.equal(s.getCell('J9').value, 'Warehouse receiver');
});
test('Each operational dataset denies unauthorized/expired users before any table reads', async () => {
  for (const d of ['production-history', 'warehouse-stock', 'warehouse-movements']) for (const [options, status] of [[{ denied: true }, 403], [{ expired: true }, 401]]) {
    const r = fixture(options); assert.equal((await r.post(body(d))).status, status); assert.equal(r.calls.length, 0);
  }
});
test('Cross-factory context, revoked delivery and missing scoped movement identities are denied', async () => {
  assert.equal((await fixture({ badFactory: true }).post(body('warehouse-stock'))).status, 403);
  assert.equal((await fixture({ rows: [stock(1)], revoke: true }).post(body('warehouse-stock'))).status, 403);
  const r = fixture({ rows: [movement(1)], missingItem: true }); assert.equal((await r.post(body('warehouse-movements'))).status, 404); assert.equal(r.calls.some(c => c.name === 'warehouse_movements'), false);
});
test('Unsupported filters, invalid IDs/dates/sets/operators and non-string sort fail without scope widening', () => {
  const cases = [body('production-history', { filters: { line: id } }), body('production-history', { filters: { good_min: '1' } }), body('production-history', { filters: { from: '2026-02-30' } }), body('production-history', { filters: { unit: id } }), body('production-history', { filters: { corrected: 'maybe' } }), body('production-history', { sort: ['date'] }), body('warehouse-stock', { direction: ['asc'] }), body('warehouse-stock', { filters: { reserved: { op: 'positive', sql: 'ignore' } } }), body('warehouse-stock', { filters: { item_type: ['secret'] } }), body('warehouse-stock', { filters: { warehouse: id } }), body('warehouse-movements', { filters: { item: 'bad', item_type: 'finished' } }), body('warehouse-movements', { filters: { item: id, item_type: 'finished', kind: 'dispatch' } }), body('warehouse-movements', { sort: 'date' })];
  for (const b of cases) assert.throws(() => exportRequest(b));
});
test('Every dataset preserves EN/AR labels, RTL, factory time, safe Print layout and field exclusions', async () => {
  for (const [dataset, row] of [['production-history', production(1)], ['warehouse-stock', stock(1)], ['warehouse-movements', movement(1)]]) {
    const r = report(dataset, [row], 'ar'), html = tablePrintHtml(r);
    assert.match(html, /dir="rtl"/); assert.match(html, /A4 landscape/); assert.match(html, /table-header-group/); assert.match(html, /أنبوب/); assert.equal(html.includes('<img'), false);
    for (const privateValue of ['PRIVATE', 'PRIVATE-USER-ID', 'PRIVATE-SOURCE']) assert.equal(html.includes(privateValue), false);
    const b = new ExcelJS.Workbook(); await b.xlsx.load(await tableWorkbook(r)); assert.equal(b.worksheets[0].views[0].rightToLeft, true);
  }
  assert.equal(operationalReport('production-history', 'ar', []).columns[9].label, ar.tableExportCorrectedGross);
  const t = key => ar[key] || key;
  const metadata = operationalFilterText('production-history', { good_op: 'gte', good_min: '5', measurement_unit: 'piece', corrected: 'yes', scrap_scope: 'shift', scrap_metric: 'percentage' }, 'good', 'desc', t);
  assert.ok(metadata.includes(ar.historyOperator_gte)); assert.ok(metadata.includes(ar.piece)); assert.ok(metadata.includes(ar.historyPerShift)); assert.ok(metadata.includes(ar.historyCorrected));
  assert.ok(operationalFilterText('warehouse-stock', { code: 'tableExportGross', replenishment_status: ['OK'] }, 'code', 'asc', t).includes('tableExportGross'));
});
test('Tiny scientific quantities stay numeric; unsafe precision, overflow and underflow remain rejected', () => {
  const r = report('warehouse-stock', []); assert.equal(reportValue(1e-7, { type: 'number' }, r), .0000001); assert.equal(reportValue('-3.25e-7', { type: 'number' }, r), -.000000325);
  for (const v of ['1e400', '1e-400', '1.1234567890123456e-7', 'NaN']) assert.throws(() => reportValue(v, { type: 'number' }, r), /tableExportPrecision/);
});
test('Empty operational reports retain headers and zero count, and row limits apply before file creation', async () => {
  for (const dataset of ['production-history', 'warehouse-stock', 'warehouse-movements']) {
    const s = await sheet(await fixture().post(body(dataset))); assert.equal(s.getCell('B6').value, 0); assert.equal(s.rowCount, 8);
    const r = fixture({ rows: Array.from({ length: 501 }, (_, n) => dataset === 'production-history' ? production(n) : dataset === 'warehouse-stock' ? stock(n) : movement(n)) });
    const res = await r.post(body(dataset, { format: 'print' })); assert.equal(res.status, 409); assert.equal((await res.json()).error, 'tableExportPrintLimit');
  }
  await assert.rejects(collectTableRows(async () => ({ total: 10001, rows: [] }), 10000, undefined, 25), /tableExportExcelLimit/);
});
test('Material movements retain KG, blank legacy units and the original signed ledger quantities', async () => {
  const rows = [{ ...movement(1), unit: 'kg', quantity: -1.25 }, { ...movement(2), unit: null, quantity: 4 }];
  const s = await sheet(await fixture({ rows }).post(body('warehouse-movements', { filters: { item: id, item_type: 'material' } })));
  assert.equal(s.getCell('G9').value, -1.25); assert.equal(s.getCell('I9').value, en.kg); assert.equal(s.getCell('I10').value, null);
});
test('Shared production reader preserves the existing scoped RPC, mass fields, audit and empty-data behavior', async () => {
  const { readProductionHistory } = load(await bundle('src/services/production-history.ts'));
  const calls = [], original = production(1);
  const db = { async rpc(name, args) { calls.push({ name, args }); return { data: { rows: [original], total: 1 } }; },
    from(table) { assert.equal(table, 'production_entries'); return { select(fields) { assert.equal(fields, 'id,effective_scrap_kg,effective_startup_kg,lean_startup_id,produced_weight_kg,weight_kg_per_unit'); return { eq(key, factory) { assert.equal(key, 'factory_id'); assert.equal(factory, id); return { in: async (key, ids) => { assert.equal(key, 'id'); assert.deepEqual(ids, ['entry-1']); return { data: [{ id: 'entry-1', effective_scrap_kg: .75 }] }; } }; } }; } }; } };
  const args = { filters: { corrected: 'yes' }, sort_key: 'good', sort_direction: 'desc', page: 2 };
  const result = await readProductionHistory(db, id, args); assert.deepEqual(calls, [{ name: 'production_history', args: { factory: id, ...args } }]);
  assert.equal(result.rows[0].effective_scrap_kg, .75); assert.deepEqual(result.rows[0].corrections, original.corrections); assert.equal(original.effective_scrap_kg, undefined);
  const empty = await readProductionHistory({ rpc: async () => ({ data: { rows: [], total: 0 } }), from() { throw Error('No extra reads for empty data'); } }, id, args); assert.equal(empty.total, 0);
  await assert.rejects(readProductionHistory({ rpc: async () => ({ error: { code: '42501' } }) }, id, args), error => error.code === '42501');
});
test('All three actual surfaces reuse TableExport, with no buttons on summaries and no unauthorized control', async () => {
  const snapshot = { factory: { id, timezone: 'UTC' }, tables: { products: [], production_shifts: [] }, fetchedAt: 'offline' };
  for (const [file, extra] of [['ProductionHistory', { onCorrect() {}, initial: { rows: [], total: 0, page: 1, page_size: 50, totals: [], highest: [] } }], ['WarehouseInventory', { onChanged() {}, onConfigure() {}, onReceive() {} }]]) {
    const Component = load(await bundle('src/features/' + file + '.tsx')).default;
    for (const language of ['en', 'ar']) for (const allowed of [true, false]) {
      const d = language === 'ar' ? ar : en, html = renderToStaticMarkup(createElement(Component, { snapshot, t: k => d[k] || k, lang: language, can: () => allowed, command() { throw Error('no writes'); }, ...extra }));
      assert.equal((html.match(/class="table-export"/g) || []).length, allowed ? 1 : 0);
    }
  }
});
