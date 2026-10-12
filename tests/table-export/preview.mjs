// Local-only fixture on unused loopback port 4203; no Supabase imports or credentials.
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { build } from 'esbuild';
import { NextRequest } from 'next/server.js';
const root = resolve(tmpdir(), 'FactoryLean-TableExport-20261010'); await mkdir(root, { recursive: true });
await build({ entryPoints: ['tests/table-export/browser-fixture.tsx'], bundle: true, platform: 'browser', jsx: 'automatic', outfile: join(root, 'preview.js'), logLevel: 'silent' });
await writeFile(join(root, 'styles.css'), await readFile('src/app/globals.css'));
const id = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const item = { request_code: 'PR-0044', item_code: 'PI-0044-01', product_code: 'PVC-25', product_name: 'PVC pressure pipe 25 mm', product_name_ar: 'أنبوب ضغط PVC قطر ٢٥ مم', product: id(3), unit: 'meter', recorded_good: '100', current_good: '98', accepted: '89.875', rejected: '8.125', eligible: '89.875', physical_label: 'PIPE-A-001', shift: id(5), shift_name: 'Night shift', shift_name_ar: 'الوردية الليلية', shift_date: '2026-10-09', factory_timezone: 'Asia/Riyadh', created_at: '2026-10-10T00:00:00Z' };
const rows = Array.from({ length: 125 }, (_, n) => ({ ...item, id: id(100 + n), line: id(n % 2 ? 4 : 6), line_name: n % 2 ? 'Extrusion line 1' : 'Extrusion line 2', line_name_ar: n % 2 ? 'خط البثق ١' : 'خط البثق ٢' }));
const history = [{ ...rows[0], id: id(300), quantity: '3.5', actual_scrap_kg: '.75', disposition: 'SCRAP', reason: 'Dimensional defect', reason_ar: 'عيب في الأبعاد', actor_name: 'Quality inspector', notification: { status: 'OPEN' } },
  { ...rows[0], id: id(301), quantity: '4.625', disposition: 'REWORK', reason: 'Surface defect', reason_ar: 'عيب في السطح', actor_name: 'Quality inspector', notification: { status: 'ACKNOWLEDGED' } }];
const options = { products: [{ id: id(3), name: item.product_name, name_ar: item.product_name_ar }], lines: [4, 6].map((n, i) => ({ id: id(n), name: 'Extrusion line ' + (i + 1), name_ar: 'خط البثق ' + (i + 1) })), shifts: [{ id: id(5), name: item.shift_name, name_ar: item.shift_name_ar }] };
function read(query) {
  if (query.mode === 'filters') return options;
  if (query.mode === 'history') return { rows: history, total: 2 };
  if (query.mode === 'detail') return history.find(r => r.id === query.rejection);
  const matches = rows.filter(r => (!query.date || r.shift_date === query.date) && ['line', 'shift', 'product'].every(k => !query[k] || query[k] === r[k]) && (!query.order || r.request_code.includes(query.order) || r.item_code.includes(query.order)));
  const page = Number(query.page || 1); return { rows: matches.slice((page - 1) * 50, page * 50), total: matches.length, quality_scrap_kg: '.75' };
}
const db = { from() { return { select() { return { eq(_key, factory) { return { single: async () => ({ data: { id: factory, name: 'Demo Factory', timezone: 'Asia/Riyadh' } }) }; } }; } }; }, rpc: async (_name, args) => ({ data: read(args.query), error: null }) };
const code = (await build({ entryPoints: ['src/app/api/table-export/route.ts'], bundle: true, platform: 'node', format: 'cjs', packages: 'external', write: false, logLevel: 'silent', plugins: [{ name: 'offline-auth', setup(b) { b.onResolve({ filter: /services\/authorization$/ }, () => ({ path: 'fixture:auth', external: true })); } }] })).outputFiles[0].text;
const require = createRequire(import.meta.url), mod = { exports: {} };
new Function('require', 'module', 'exports', code)(n => n === 'fixture:auth' ? { verifyOrigin() {}, authenticatedClient: async () => ({ db, user: { id: id(8) } }), authorize: async factory => { if (factory !== id(9)) throw Error('permission_denied'); } } : require(n), mod, mod.exports);
const html = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Offline Table Export</title><link rel="stylesheet" href="/styles.css"><div id="root"></div><script src="/preview.js"></script></html>';
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1:4203');
    if (url.pathname === '/favicon.ico') { res.writeHead(204); res.end(); return; }
    if (url.pathname === '/api/quality' && req.method === 'GET') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(read(Object.fromEntries(url.searchParams)))); return; }
    if (url.pathname === '/api/table-export' && req.method === 'POST') {
      const chunks = []; for await (const chunk of req) chunks.push(chunk);
      const response = await mod.exports.POST(new NextRequest(url, { method: 'POST', body: Buffer.concat(chunks), headers: { 'Content-Type': 'application/json' } }));
      res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(Buffer.from(await response.arrayBuffer())); return;
    }
    const file = { '/preview.js': 'preview.js', '/styles.css': 'styles.css' }[url.pathname];
    if (url.pathname !== '/' && !file) { res.writeHead(404); res.end(); return; }
    res.setHeader('Content-Type', file?.endsWith('.js') ? 'application/javascript' : file ? 'text/css' : 'text/html'); res.end(file ? await readFile(join(root, file)) : html);
  } catch (error) { res.writeHead(500); res.end('Offline fixture failed'); console.error(error); }
});
server.listen(4203, '127.0.0.1', () => console.log('Offline fixture: http://127.0.0.1:4203/'));
