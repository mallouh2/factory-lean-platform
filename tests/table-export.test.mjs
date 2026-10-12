import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { build } from 'esbuild';
import { NextRequest } from 'next/server.js';
import ExcelJS from 'exceljs';
import { renderToStaticMarkup } from 'react-dom/server';
import { collectTableRows, tableWorkbook, tablePrintHtml, reportValue } from '../src/utils/table-export.mjs';
import en from '../src/locales/en.json' with { type: 'json' };
import ar from '../src/locales/ar.json' with { type: 'json' };
const require = createRequire(import.meta.url), id = '12345678-1234-1234-1234-123456789abc';
const bundle = async entry => (await build({ entryPoints: [entry], bundle: true, platform: 'node', format: 'cjs', packages: 'external', write: false, logLevel: 'silent',
  plugins: [{ name: 'auth-fixture', setup(b) { b.onResolve({ filter: /services\/authorization$/ }, () => ({ path: 'fixture:auth', external: true })); } }] })).outputFiles[0].text;
const providerCode = await bundle('src/services/table-export.ts'), routeCode = await bundle('src/app/api/table-export/route.ts'), componentCode = await bundle('src/components/TableExport.tsx');
function load(code, mocks = {}) { const m = { exports: {} }; new Function('require', 'module', 'exports', code)(n => mocks[n] || require(n), m, m.exports); return m.exports; }
const { qualityReport, exportRequest } = load(providerCode), TableExport = load(componentCode).default;
const source = i => ({ id: 'row-' + i, request_code: 'PR-0044', item_code: 'PI-0044', line_name: 'Extrusion 1', line_name_ar: 'خط البثق ١', shift_name: 'Night', shift_name_ar: 'الليل', shift_date: '2026-10-09', product_name: 'Pipe 25', product_name_ar: 'أنبوب ٢٥', product_code: 'P-25', unit: 'meter', recorded_good: '100', current_good: '98', rejected: '8.125', accepted: '89.875', created_at: '2026-10-10T01:00:00Z', secret_token: 'never-export', factory_id: 'unrelated', source_id: 'private-source', physical_label: 'PRIVATE-LOT' });
function report(rows = [source(1)], dataset = 'quality-production', language = 'en') { return { ...qualityReport(dataset, language, rows), factory: 'Demo Factory', timezone: 'Asia/Riyadh', language, filters: 'Shift date: 2026-10-09', timestamp: '2026-10-10T08:00:00Z' }; }
async function workbook(r) { const b = new ExcelJS.Workbook(); await b.xlsx.load(await tableWorkbook(r)); return b.worksheets[0]; }
const body = overrides => ({ factory: id, dataset: 'quality-production', format: 'excel', filters: {}, language: 'en', ...overrides });
function fixture({ expired = false, denied = false, rows = [source(1)], rpcError = null, wrongMeta = false, revoke = false, badOrigin = false } = {}) {
  const calls = [], grants = [];
  const db = { from(name) { assert.equal(name, 'factories'); return { select(fields) { assert.equal(fields, 'id,name,timezone'); return { eq(key, value) { assert.equal(key, 'id'); calls.push({ meta: value }); return { single: async () => ({ data: { id: wrongMeta ? 'other' : value, name: 'Demo Factory', timezone: 'Asia/Riyadh' }, error: null }) }; } }; } }; },
    async rpc(name, args) { calls.push({ name, args }); if (rpcError) return { data: null, error: rpcError }; if (args.query.mode === 'filters') return { data: { lines: [{ id, name: 'Extrusion 1', name_ar: 'خط البثق ١' }], shifts: [{ id, name: 'Night' }], products: [] }, error: null };
      return { data: { rows: rows.slice((args.query.page - 1) * 50, args.query.page * 50), total: rows.length }, error: null }; } };
  const route = load(routeCode, { 'fixture:auth': { verifyOrigin() { if (badOrigin) throw Error('invalid_origin'); }, async authenticatedClient() { if (expired) throw Error('unauthorized'); return { db, user: { id } }; }, async authorize(factory, module, action) { grants.push({ factory, module, action }); if (denied || (revoke && grants.length > 1)) throw Error('permission_denied'); } } });
  return { ...route, calls, grants, post: b => route.POST(new NextRequest('http://localhost/api/table-export', { method: 'POST', body: JSON.stringify(b), headers: { 'Content-Type': 'application/json' } })) };
}
test('Excel opens with metadata, frozen headers, useful widths and true numeric quantities', async () => {
  const sheet = await workbook(report()); assert.equal(sheet.getCell('A1').value, 'Factory'); assert.equal(sheet.getCell('B1').value, 'Demo Factory');
  assert.equal(sheet.getCell('B6').value, 1); assert.equal(sheet.getCell('H8').value, 'Gross Good (original)');
  assert.equal(sheet.getCell('J9').value, 8.125); assert.equal(sheet.getCell('J9').type, ExcelJS.ValueType.Number);
  assert.equal(sheet.getCell('M9').value.includes('04:00'), true); assert.equal(sheet.views[0].ySplit, 8); assert.ok(sheet.getColumn(1).width >= 20);
});
test('Arabic workbook uses localized labels, real Arabic names and RTL', async () => {
  const s = await workbook(report(undefined, undefined, 'ar')); assert.equal(s.views[0].rightToLeft, true); assert.equal(s.getCell('C9').value, 'خط البثق ١'); assert.equal(s.getCell('H8').value, ar.tableExportGross);
});
test('Filtered result collection includes all 123 rows beyond the visible page and verifies both reads', async () => {
  const rows = Array.from({ length: 123 }, (_, i) => source(i)), calls = [];
  const output = await collectTableRows(async page => { calls.push(page); return { rows: rows.slice((page - 1) * 50, page * 50), total: rows.length }; }, 10000);
  assert.equal(output.length, 123); assert.deepEqual(calls, [1, 2, 3, 1, 2, 3]);
});
test('All supported filters retain exact table semantics; unsupported date ranges fail instead of silently broadening', () => {
  const filters = { date: '2026-10-09', shift: id, line: id, product: id, order: ' PR-%_ ' };
  assert.deepEqual(exportRequest(body({ filters })).filters, filters);
  for (const filters of [{ from: '2026-10-01', to: '2026-10-10' }, { date: '2026-02-30' }, { date: 'bad' }, { line: 'other' }, { order: 'a'.repeat(101) }, { page: '2' }]) assert.throws(() => exportRequest(body({ filters })));
});
test('Request allowlists reject client tables, columns, flags and unscoped history', () => {
  for (const b of [body({ dataset: 'factories' }), body({ columns: ['secret'] }), body({ table: 'users' }), body({ filters: { permission: 'all' } }), body({ dataset: 'quality-history' }), body({ factory: 'bad' }), body({ language: 'fr' }), body({ language: ['en'] }), body({ format: ['excel'] }), body({ format: 'csv' })]) assert.throws(() => exportRequest(b));
});
test('Large Excel and print results are rejected explicitly with no truncation', async () => {
  for (const [limit, count, key] of [[10000, 10001, 'tableExportExcelLimit'], [500, 501, 'tableExportPrintLimit']]) await assert.rejects(collectTableRows(async () => ({ rows: [], total: count }), limit), new RegExp(key));
});
test('Changed, duplicate or incomplete pages refuse mixed or partial output', async () => {
  let calls = 0;
  await assert.rejects(collectTableRows(async () => ({ rows: [{ ...source(1), accepted: String(++calls) }], total: 1 }), 10000), /tableExportChanged/);
  await assert.rejects(collectTableRows(async () => ({ rows: [source(1), source(1)], total: 2 }), 10000), /tableExportChanged/);
  await assert.rejects(collectTableRows(async () => ({ rows: [source(1)], total: 2 }), 10000), /tableExportChanged/);
  await assert.rejects(collectTableRows(async () => ({ rows: [], total: 0 }), 10000, { aborted: true }), /tableExportCancelled/);
});
test('Empty workbook and print preserve headers and zero count', async () => {
  const r = report([]); const s = await workbook(r); assert.equal(s.getCell('B6').value, 0); assert.equal(s.rowCount, 8);
  assert.match(tablePrintHtml(r), /No results/); assert.match(tablePrintHtml(r), /<dd>0<\/dd>/);
});
test('Sensitive and UI-only fields never enter the server-owned columns', async () => {
  const r = report(), s = await workbook(r); const values = JSON.stringify(s.getSheetValues()) + tablePrintHtml(r);
  for (const hidden of ['never-export', 'unrelated', 'private-source', 'PRIVATE-LOT', 'source_id', 'actions']) assert.equal(values.includes(hidden), false);
});
test('Untrusted formulas are literal Excel strings and print content is escaped', async () => {
  for (const value of ['=HYPERLINK("https://evil.example","run")', '+SUM(A1)', '-1+2', '@SUM(A1)', '\t=cmd', '<img src=x onerror=alert(1)>', 'Bearer private-token']) {
    const r = report([{ ...source(1), product_name: value }]), s = await workbook(r);
    assert.equal(s.getCell('G9').type, ExcelJS.ValueType.String); assert.equal(s.getCell('G9').formula, undefined);
    const html = tablePrintHtml(r); assert.equal(html.includes('<img'), false); assert.equal(html.includes('private-token'), false);
  }
});
test('Quality rejection exports preserve Scrap KG separately from Meter/Piece rework and reversal history', async () => {
  const rows = [{ ...source(1), quantity: '3.5', actual_scrap_kg: '.75', disposition: 'SCRAP', reason: 'Defect', notification: { status: 'OPEN' } },
    { ...source(2), unit: 'piece', quantity: '4', actual_scrap_kg: null, disposition: 'REWORK', reason: 'Rework', reversal: { reason: 'Mistake' } }];
  const r = report(rows, 'quality-history'), s = await workbook(r);
  assert.equal(s.getCell('I8').value, en.qualityActualKg); assert.equal(s.getCell('I9').value, .75); assert.equal(s.getCell('J9').value, null);
  assert.equal(s.getCell('I10').value, null); assert.equal(s.getCell('J10').value, 4); assert.equal(s.getCell('N10').value, en.qualityReversed);
});
test('Null quantities remain blank rather than becoming zero, and unsafe precision fails', async () => {
  const s = await workbook(report([{ ...source(1), accepted: null, shift_name: null }])); assert.equal(s.getCell('K9').value, null); assert.equal(s.getCell('D9').value, null);
  assert.throws(() => reportValue('1234567890123456.1', { type: 'number' }, report()), /tableExportPrecision/);
  assert.equal(reportValue('0.00000001', { type: 'number' }, report()), .00000001);
  assert.throws(() => reportValue('NaN', { type: 'number' }, report()), /tableExportPrecision/);
  assert.throws(() => reportValue('0.' + '0'.repeat(400) + '1', { type: 'number' }, report()), /tableExportPrecision/);
});
test('Print represents the same allowed rows, escapes metadata and supports RTL and repeated landscape headers', () => {
  const r = report([source(1), source(2)], undefined, 'ar'); r.factory = '<script>bad</script>';
  const html = tablePrintHtml(r); assert.match(html, /lang="ar" dir="rtl"/); assert.match(html, /A4 landscape/); assert.match(html, /table-header-group/);
  assert.equal((html.match(/<tr>/g) || []).length, 3); assert.match(html, /&lt;script&gt;/); assert.equal(html.includes('<script>'), false); assert.match(html, /أنبوب ٢٥/);
});
test('Unauthenticated and unauthorized departmental access fails before data retrieval', async () => {
  for (const [options, status] of [[{ expired: true }, 401], [{ denied: true }, 403], [{ badOrigin: true }, 403]]) { const r = fixture(options), res = await r.post(body()); assert.equal(res.status, status); assert.equal(r.calls.length, 0); }
});
test('Oversized cell and cumulative text budgets fail before generating a partial file', async () => {
  await assert.rejects(tableWorkbook(report([{ ...source(1), product_name: 'x'.repeat(32768) }])), /tableExportExcelLimit/);
  assert.throws(() => tablePrintHtml(report(Array.from({ length: 70 }, (_, i) => ({ ...source(i), product_name: 'x'.repeat(30000) })))), /tableExportPrintLimit/);
  await assert.rejects(tableWorkbook(report(Array.from({ length: 340 }, (_, i) => ({ ...source(i), product_name: 'x'.repeat(30000) })))), /tableExportExcelLimit/);
});
test('Cross-factory metadata and protected reader denial do not disclose tenant records', async () => {
  for (const options of [{ wrongMeta: true }, { rpcError: { code: '42501', message: 'secret SQL' } }]) { const r = fixture(options), res = await r.post(body()); assert.equal(res.status, 403); assert.deepEqual(await res.json(), { error: 'permissionError' }); }
});
test('Production route forwards all filters on every page and rechecks view permission without factory:export', async () => {
  const r = fixture({ rows: Array.from({ length: 51 }, (_, i) => source(i)) }); const filters = { date: '2026-10-09', shift: id, line: id, product: id, order: 'PR-%' };
  const res = await r.post(body({ filters })); assert.equal(res.status, 200); assert.equal(res.headers.get('X-Export-Row-Count'), '51'); assert.match(res.headers.get('Cache-Control'), /no-store/);
  assert.deepEqual(r.grants, [{ factory: id, module: 'quality', action: 'view' }, { factory: id, module: 'quality', action: 'view' }]);
  for (const call of r.calls.filter(c => c.args?.query.mode === 'board')) { assert.equal(call.args.factory, id); assert.deepEqual(call.args.query, { mode: 'board', ...filters, page: call.args.query.page }); }
  const s = new ExcelJS.Workbook(); await s.xlsx.load(Buffer.from(await res.arrayBuffer())); assert.match(s.worksheets[0].getCell('B5').value, /Extrusion 1/);
});
test('History route independently requires history view and print exposes only scoped entry results', async () => {
  const r = fixture(), res = await r.post(body({ dataset: 'quality-history', filters: { entry: id }, format: 'print' })); assert.equal(res.status, 200);
  assert.equal(r.grants.every(g => g.module === 'quality_history'), true);
  assert.equal(r.calls.filter(c => c.name).every(c => c.args.query.mode === 'history' && c.args.query.entry === id), true);
  assert.match(await res.text(), /PR-0044/);
});
test('Delivery is denied if authority is revoked while preparing the report', async () => {
  const r = fixture({ revoke: true }); const res = await r.post(body()); assert.equal(res.status, 403);
});
test('Toolbar uses accessible native disclosure, row scope and bilingual labels', () => {
  for (const language of ['en', 'ar']) { const d = language === 'ar' ? ar : en;
    const html = renderToStaticMarkup(require('react').createElement(TableExport, { factory: id, dataset: 'quality-production', filters: {}, total: 125, language, t: k => d[k] || k }));
    assert.match(html, /<details>/); assert.match(html, /<summary/); assert.ok(html.includes(d.tableExportScope)); assert.ok(html.includes(d.tableExportExcel)); assert.ok(html.includes(d.tableExportPrint));
  }
});
