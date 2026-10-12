// Loopback-only offline reader fixture. No Supabase credentials, imports or connections.
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { build } from 'esbuild';
import { NextRequest } from 'next/server.js';
const root = resolve(tmpdir(), 'FactoryLean-TableExport-Batch1-20261011'); await mkdir(root, { recursive: true });
await build({ entryPoints: ['tests/table-export/batch1-browser-fixture.tsx'], bundle: true, platform: 'browser', jsx: 'automatic', outfile: join(root, 'preview.js'), logLevel: 'silent' });
await writeFile(join(root, 'styles.css'), await readFile('src/app/globals.css'));
const id = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const production = Array.from({ length: 123 }, (_, n) => ({ id: id(100 + n), product_id: id(n % 2 ? 3 : 4), production_request_id: id(5), request_code: 'PO-0044', item_code: 'PI-0044', product_name: 'Pressure pipe', product_name_ar: 'أنبوب ضغط', unit_key: 'line:' + id(6), unit_name: 'Extrusion line 1', unit_name_ar: 'خط البثق ١', shift_name: 'Night', shift_name_ar: 'الليل', created_at: '2026-10-10T01:00:00Z', technician_name: 'Production recorder', submitter_name: 'Supervisor', good_quantity: 10, effective_good: 7, effective_scrap: 3, effective_unfinished: 2, effective_scrap_kg: .75, produced_weight_kg: 4.5, unit: 'meter', corrected: true, corrections: [], running_good: 7, remaining_quantity: 3 }));
const stock = Array.from({ length: 123 }, (_, n) => ({ id: id(n === 0 ? 3 : 400 + n), row_key: 'finished:' + id(n === 0 ? 3 : 400 + n), entity: 'finished', name: 'Pressure pipe ' + n, name_ar: 'أنبوب ضغط ' + n, code: 'P-' + n, unit: 'meter', item_type: 'FINISHED_GOOD', on_hand: 20, reserved: n % 2 ? 5 : 0, available: n % 2 ? 15 : 20, semi_finished: 3, in_production: 8, minimum_stock: null, maximum_stock: 30, replenishment_status: 'OK', minimum_status: 'NOT_CONFIGURED', supply_source: 'MANUFACTURED' }));
stock.push({ ...stock[0], id: id(7), row_key: 'material:' + id(7), entity: 'material', name: 'Resin', name_ar: 'راتنج', code: 'R-1', unit: 'kg', item_type: 'RAW_MATERIAL' });
const movements = Array.from({ length: 63 }, (_, n) => ({ id: id(700 + n), kind: n % 2 ? 'dispatch' : 'reservation', quantity: n % 2 ? -3 : 0, reserved_delta: n % 2 ? -3 : 5, created_at: '2026-10-10T01:00:00Z', actor_name: 'Warehouse receiver', note: 'Synthetic movement ' + n, reference: 'WH-' + n, unit: 'meter' }));
const paged = (rows, page, size = 50) => ({ rows: rows.slice((page - 1) * size, page * size), total: rows.length, page, page_size: size });
const options = { products: [3, 4].map(n => ({ id: id(n), name: 'Pressure pipe ' + n, name_ar: 'أنبوب ضغط ' + n })), requests: [{ id: id(5), name: 'PO-0044' }], units: [{ id: 'line:' + id(6), name: 'Extrusion line 1' }], shifts: [], technicians: [] };
function read(name, args) {
  const f = args.filters || {};
  if (name === 'production_history') return { ...paged(production.filter(r => !f.product || f.product.split(',').includes(r.product_id)), args.page), totals: [], highest: [] };
  if (name === 'warehouse_inventory') return { ...paged(stock.filter(r => (!f.reserved || Number(r.reserved) > 0) && (!f.item_type?.length || f.item_type.includes(r.item_type))), args.page), units: ['meter', 'kg'] };
  if (name === 'warehouse_movements') return paged(movements.map(r => ({ ...r, unit: args.item_type === 'material' ? 'kg' : r.unit })), args.page, 25);
  if (name === 'production_history_options') return options;
  if (name === 'production_history_values') { const key = { product: 'products', request: 'requests', unit: 'units', shift: 'shifts', technician: 'technicians' }[args.field]; return { rows: options[key] || [], total: options[key]?.length || 0 }; }
  throw Error('Unknown offline reader');
}
const auth = { verifyOrigin() {}, async authenticatedClient() { return { user: { id: id(8) }, db: {
  from(table) { if (!['factories', 'production_entries', 'products'].includes(table)) throw Error('Unknown offline table'); return { select() { return { eq(_key, factory) { if (factory !== id(9)) throw Error('permission_denied'); return {
    single: async () => ({ data: { id: id(9), name: 'Demo Factory', timezone: 'Asia/Riyadh' } }),
    in: async (_key, ids) => ({ data: table === 'products' ? ids.map(id => ({ id, code: 'P-25' })) : production.filter(r => ids.includes(r.id)).map(r => ({ id: r.id, effective_scrap_kg: .75, produced_weight_kg: 4.5 })) }),
  }; } }; } }; },
  async rpc(name, args) { if (args.factory !== id(9)) throw Error('permission_denied'); return { data: read(name, args) }; },
} }; }, async authorize(factory) { if (factory !== id(9)) throw Error('permission_denied'); } };
const require = createRequire(import.meta.url), bundled = await build({ entryPoints: ['src/app/api/table-export/route.ts'], bundle: true, platform: 'node', format: 'cjs', packages: 'external', write: false, logLevel: 'silent', plugins: [{ name: 'offline-auth', setup(b) { b.onResolve({ filter: /services\/authorization$/ }, () => ({ path: 'fixture:auth', external: true })); } }] });
const mod = { exports: {} }; new Function('require', 'module', 'exports', bundled.outputFiles[0].text)(name => name === 'fixture:auth' ? auth : require(name), mod, mod.exports);
const html = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Offline Batch 1</title><link rel="stylesheet" href="/styles.css"></head><body><div id="root"></div><script src="/preview.js"></script></body></html>';
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1:4204');
    if (url.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }
    if (url.pathname === '/api/production-history') { const args = Object.fromEntries(url.searchParams); args.filters = Object.fromEntries(url.searchParams); args.page = Number(args.page || 1); res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(read(args.options ? 'production_history_options' : args.field ? 'production_history_values' : 'production_history', args))); return; }
    if (url.pathname === '/api/fulfillment') { const args = Object.fromEntries(url.searchParams); args.filters = JSON.parse(args.filters || '{}'); args.page = Number(args.page || 1); res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(read(args.mode === 'inventory' ? 'warehouse_inventory' : 'warehouse_movements', args))); return; }
    if (url.pathname === '/api/table-export' && req.method === 'POST') { const chunks = []; for await (const chunk of req) chunks.push(chunk); const response = await mod.exports.POST(new NextRequest(url, { method: 'POST', body: Buffer.concat(chunks), headers: { 'Content-Type': 'application/json' } })); res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(Buffer.from(await response.arrayBuffer())); return; }
    const file = { '/preview.js': 'preview.js', '/styles.css': 'styles.css' }[url.pathname];
    if (url.pathname !== '/' && !file) { res.writeHead(404); res.end(); return; }
    res.setHeader('Content-Type', file?.endsWith('.js') ? 'application/javascript' : file ? 'text/css' : 'text/html'); res.end(file ? await readFile(join(root, file)) : html);
  } catch (error) { res.writeHead(500); res.end('Offline fixture failed'); console.error(error); }
});
server.listen(4204, '127.0.0.1', () => console.log('Offline Batch 1: http://127.0.0.1:4204/'));
