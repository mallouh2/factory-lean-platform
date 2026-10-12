import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readFileSync(new URL('../src/app/globals.css', import.meta.url), 'utf8');
const shared = css.slice(css.indexOf('/* One scroll owner per operational table:'));

test('horizontal wrappers provide bounded vertical scrolling for sticky headers', () => {
  assert.match(shared, /\.table-wrap, \.quality-table-wrap\s*\{[^}]*max-block-size:\s*min\(70dvh, calc\(100dvh - 8rem\)\)[^}]*overflow:\s*auto/s);
  assert.match(shared, /> thead > tr > th\s*\{[^}]*position:\s*sticky[^}]*inset-block-start:\s*0[^}]*background:\s*var\(--surface\)/s);
  assert.match(shared, /border-collapse:\s*separate/);
});

test('shared alignment includes row headers, multiline values and action groups', () => {
  assert.match(shared, /:is\(thead, tbody, tfoot\) > tr > :is\(th, td\)\s*\{[^}]*text-align:\s*center[^}]*vertical-align:\s*middle/s);
  assert.match(shared, /> table \.row-actions\s*\{[^}]*justify-content:\s*center/s);
  assert.match(shared, /:is\(\.cell-note, \.lean-problem-link, pre\)[^{]*\{[^}]*text-align:\s*center/s);
});

test('sticky first-column intersections stay above header and body layers in RTL', () => {
  assert.match(shared, /\.inventory-table-scroll > \.inventory-table > thead > tr > th:first-child\s*\{[^}]*inset-inline-start:\s*0[^}]*z-index:\s*4/s);
  assert.match(css, /\.inventory-table td:first-child\s*\{[^}]*inset-inline-start:\s*0[^}]*z-index:\s*1/s);
});

test('modal and mobile-card layouts avoid additional vertical scroll owners', () => {
  assert.match(shared, /dialog :is\(\.table-wrap, \.quality-table-wrap, \.inventory-table-scroll\)\s*\{[^}]*overflow:\s*visible[^}]*max-block-size:\s*none/s);
  assert.match(shared, /@media \(max-width: 520px\)[\s\S]*\.quality-table-wrap\s*\{[^}]*max-block-size:\s*none[^}]*overflow:\s*visible/);
  assert.match(css, /\.quality-table td::before\{content:attr\(data-label\)/);
});

test('print resets sticky layers and limits without overriding semantic row colors', () => {
  const print = shared.slice(shared.indexOf('@media print'));
  assert.match(print, /overflow:\s*visible/);
  assert.match(print, /max-block-size:\s*none/);
  assert.match(print, /display:\s*table-header-group/);
  assert.match(print, /position:\s*static\s*!important/);
  assert.doesNotMatch(shared, /(?:\.high-scrap|data-row-state)[^{]*\{/);
  assert.match(css, /tr:is\(\.high-scrap,\[data-row-state="warning"\],\[data-row-state="error"\]\)/);
});
