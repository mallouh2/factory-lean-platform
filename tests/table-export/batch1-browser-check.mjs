// Run only against the loopback offline fixture. Installed Edge, no live application data.
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';
import ExcelJS from 'exceljs';
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const output = resolve(tmpdir(), 'FactoryLean-TableExport-Batch1-20261011', 'proof'); await mkdir(output, { recursive: true });
const browser = await chromium.launch({ headless: true, channel: process.env.PLAYWRIGHT_CHANNEL || 'msedge' });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
const errors = [], requests = [], results = [];
await context.route('**/*', route => route.request().url().startsWith('http://127.0.0.1:4204/') ? route.continue() : route.abort());
await context.addInitScript(() => { window.__printCalls = 0; window.print = () => window.__printCalls++; });
const page = await context.newPage(); page.on('pageerror', e => errors.push(e.message)); page.on('console', m => { if (['warning', 'error'].includes(m.type())) errors.push(m.text()); });
page.on('request', r => { if (r.url().endsWith('/api/table-export')) requests.push(JSON.parse(r.postData())); });
const tools = () => page.locator('.table-export');
const ready = () => tools().locator('summary[aria-disabled="false"]').waitFor();
async function excel(name, count) {
  await ready(); await tools().locator('summary').click(); const pending = page.waitForEvent('download');
  await tools().locator('.table-export-menu button').first().click(); const download = await pending; await download.saveAs(join(output, name + '.xlsx'));
  const b = new ExcelJS.Workbook(); await b.xlsx.readFile(join(output, name + '.xlsx')); const s = b.worksheets[0]; assert.equal(s.getCell('B6').value, count); results.push({ name, rows: count, format: 'excel' }); return s;
}
async function print(name, count) {
  await ready(); await tools().locator('summary').click(); const pending = context.waitForEvent('page');
  await tools().locator('.table-export-menu button').last().click(); const preview = await pending; await preview.waitForFunction(() => window.__printCalls === 1);
  assert.equal(await preview.locator('tbody tr').count(), count); await preview.emulateMedia({ media: 'print' }); assert.equal(await preview.locator('.print-controls').isVisible(), false);
  assert.equal(await preview.locator('thead').evaluate(e => getComputedStyle(e).display), 'table-header-group');
  await preview.pdf({ path: join(output, name + '.pdf'), preferCSSPageSize: true, printBackground: true });
  await preview.screenshot({ path: join(output, name + '.png'), fullPage: true }); await preview.close(); results.push({ name, rows: count, format: 'print' });
}
try {
  await page.goto('http://127.0.0.1:4204/'); await ready(); await excel('production-all', 123);
  await page.locator('.history-filter-arrow').nth(4).click(); const popover = page.locator('.history-column-popover');
  await popover.locator('select[multiple]').selectOption('10000000-0000-0000-0000-000000000004'); await popover.getByRole('button', { name: 'Apply filter', exact: true }).click();
  await tools().locator('small').filter({ hasText: '62 rows' }).waitFor(); await page.locator('.history-pagination').getByRole('button', { name: 'Next', exact: true }).click(); await ready();
  await tools().locator('summary').click(); await page.screenshot({ path: join(output, 'production-desktop.png') }); await tools().locator('summary').press('Escape');
  await excel('production-filtered', 62); assert.equal(requests.at(-1).filters.product, '10000000-0000-0000-0000-000000000004'); assert.equal(requests.at(-1).sort, 'date'); await print('production-filtered-print', 62);
  await page.getByRole('button', { name: 'stock', exact: true }).click(); await ready(); await excel('stock-all', 124);
  await page.locator('.inventory-filter-button').nth(7).click(); const filter = page.getByRole('dialog'); await filter.locator('select').last().selectOption('positive'); await filter.getByRole('button', { name: 'Apply Filter', exact: true }).click();
  await tools().locator('small').filter({ hasText: '61 rows' }).waitFor(); await page.locator('.fulfillment-pagination').getByRole('button', { name: 'Next', exact: true }).click(); await ready();
  await tools().locator('summary').click(); await page.screenshot({ path: join(output, 'stock-desktop.png') }); await tools().locator('summary').press('Escape');
  const s = await excel('stock-filtered', 61); assert.equal(s.getCell('H9').value, 5); assert.deepEqual(requests.at(-1).filters.reserved, { op: 'positive' }); await print('stock-filtered-print', 61);
  await page.getByRole('button', { name: 'movements', exact: true }).click(); await page.getByRole('button', { name: 'Stock Movements', exact: true }).click();
  const dialog = page.getByRole('dialog'); await dialog.locator('select').last().selectOption('10000000-0000-0000-0000-000000000003'); await ready();
  await dialog.locator('.fulfillment-pagination').getByRole('button', { name: 'Next', exact: true }).click(); await ready();
  await tools().locator('summary').click(); await page.screenshot({ path: join(output, 'movements-desktop.png') }); await tools().locator('summary').press('Escape'); assert.equal(await dialog.isVisible(), true);
  await excel('movements-all', 63); await print('movements-print', 63);
  await page.keyboard.press('Escape'); await page.getByRole('button', { name: 'English / العربية' }).click(); await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'stock', exact: true }).click(); await ready(); await tools().locator('summary').click(); await page.screenshot({ path: join(output, 'stock-arabic-mobile.png') }); await tools().locator('summary').press('Escape');
  const arabic = await excel('stock-arabic', 124); assert.equal(arabic.views[0].rightToLeft, true); await print('stock-arabic-print', 124);
  await page.getByRole('button', { name: 'production', exact: true }).click(); await ready(); await tools().locator('summary').click(); await page.screenshot({ path: join(output, 'production-arabic-mobile.png') }); await tools().locator('summary').press('Escape');
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  await page.getByRole('button', { name: 'View permission: on' }).click(); assert.equal(await page.locator('.table-export').count(), 0);
  assert.equal(errors.length, 0, JSON.stringify(errors)); await writeFile(join(output, 'browser-results.json'), JSON.stringify({ results, requests, errors }, null, 2)); console.log(JSON.stringify({ results, errors }));
} finally { await browser.close(); }
