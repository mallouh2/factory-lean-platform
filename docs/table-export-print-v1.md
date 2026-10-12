# Current hosted TESTING integration — 2026-10-11

Pending Nasser export POST checks now executed: Quality production/history Excel/Print each return403 with27-byte permissionError JSON, no attachment or row-count header. Authorized Warehouse Excel returns200/11 rows/8154-byte XLSX response with ZIP signature; no repeat download. Same actual authenticated session, no grant changes. Latest report supersedes prior POST-unverified notices for this scope.

Latest actual session: Nasser's protected Quality board/history/reasons reads returned403. Warehouse catalogue and Excel/Print controls remain available under his existing grant; no export/download repeated. Actual Quality export POST denial, write-command and cross-factory denial remain unexercised. Prior sign-in-pending notices below are superseded.

Latest continuation supersedes the Print blocker below: user reports Print working in manual testing. Quality board and exact-entry history requests returned200; native history printing temporarily blocked browser controls until closure. Per-surface EN/AR rendered PDF layouts are not independently verified. No successful Excel exports repeated. Nasser's grants were inspected read-only; actual Quality denial awaits his normal sign-in.

All five actual departmental **Excel** downloads passed in EN/AR, with RTL workbooks: filtered Quality board2 rows, exact-entry history2, Production History34, Warehouse catalogue11 and selected P050 movements48. Movements export from actual UIpage2 includes all48 unique references. Narrow movement-kind translations fixed and rechecked in actual bilingual UI/XLSX; fallback muted contrast now4.507:1. Fresh focused60/60 and TypeScript passed. Native **Print remains BLOCKED**: successful API200, then unresponsive in-app tab; no rendering/PDF acceptance claimed. Restricted-account/factory-scope browser denial remains pending. See [the current integration report](quality-export-testing-integration.md). TESTING81, repository82; administrative Export Reader remains unapplied. Earlier local/offline results below keep their original scope.

# Departmental Table Export & Print V1 — Batch 1, 2026-10-11 (historical local milestone)

## Current local result

Continued the preserved dirty `development` checkout at `3e249c9d222a08ebe1e85c5fd401818821ed77d2`. Reused the existing TableExport system for exactly three more operational datasets. No commit/push, remote connection/migration/QA data change, Simulation/3001, DEV/PROD or main operation. Quality business logic and administrative export remain unchanged.

| Exact surface | Control placement / existing reader | Permission |
| --- | --- | --- |
| Production Recording → Production History | Existing filter/sort toolbar; `production_history` and shared scoped KG supplement | `orders:view` |
| Warehouse → Inventory catalogue | Existing inventory filter toolbar; `warehouse_inventory` | `warehouse:view` |
| Warehouse → Inventory Movements → selected item | Above actual paginated Stock Movements list inside its dialog; `warehouse_movements` | `warehouse:view` |

No buttons on decorative summaries, unit-breakdown prose, duplicate mobile rows, Good acknowledgment queues or WIP/source-allocation details. Those independent datasets were not silently included.

## Exact columns and unknown data

- **Production History (16):** Production Order, Product Item, Product code/name, recorded Production unit (line/work center), shift, recording timestamp, technician display name, original gross Good, current corrected gross Good, discarded/historical scrap quantity in production units, current WIP, unit, actual Scrap KG, correction status, submitter display name. One row per recording; audit corrections are not duplicated as new production. Product codes use a fixed scoped identity query under existing `orders:view` RLS. No contacts/emails/employee profiles or actor UUIDs.
- **Stock (12):** Item, Code, Type, Unit, On Hand, Semi-Finished/stored WIP, In Production, Reserved, Available, Minimum, Maximum, Status. Exactly the visible information columns, excluding actions. Primary-unit NULL stays blank; historic-unit breakdowns are never summed into the primary row. KG stays distinct from Meter/Piece; no stock calculation/allocation change.
- **Movements (11):** movement UUID/reference, external reference, timestamp, selected item name/code, movement classification, signed On Hand delta, separate signed Reserved delta, recorded unit, actor display name, notes. Material records without a reserved delta and historical records without a unit retain blanks. Reservations are not represented as receipts.

**Reader limits:** Production History returns gross recording/correction truth, not entry-level Quality acceptance/rejection/rework. Export does not infer those from item-level counters or expose Quality-private records through Orders grants. Existing Quality exports retain their separate columns/permissions. These Warehouse readers do not expose physical locations, identified source/UNATTRIBUTED balances, linked source receipts/lots/orders or last-stock-movement timestamps. Those fields are absent; no source is guessed from references, and historical pooled stock remains UNATTRIBUTED in the unchanged ledger. Because no Quality-only schema is needed, pending Quality tables/RPCs do not make Warehouse exports fail; no speculative schema probe is made. Future source-detail reporting needs its own protected reader/visible workflow. Stock's hidden Incoming/Projected/Supply Source remain internal, unchanged.

## Filter, pagination and security contracts

- History forwards existing applied from/to dates; request/Product/recording-unit/technician/shift multi-selection; correction status; measurement unit; Good/discarded/WIP operators and values; existing legacy Scrap quantity/percentage/row/shift semantics. Reuses `parseHistoryQuery` plus field/type/UUID/calendar validation and rejected ignored numeric operands. Exact sort/direction on every page. No new filter is invented.
- Stock forwards the existing typed text, categorical OR and numeric filters with cross-column AND and sort/direction. Reject unsupported keys/enum values/numeric-object extras instead of widening scope. Movements scope is precisely selected UUID + finished/material type, with existing timestamp/ID ordering. No date/search/movement-type filter exists on that screen.
- All matching pages, independent of the UI page: History/Stock50, Movements25. Stock uniqueness uses `row_key` (entity+ID), avoiding Product/material ID collisions. Two complete reads detect changed/duplicate/incomplete results; they are not a transaction snapshot. Preserve Excel10,000/Print500 limits and existing text budgets with no silent truncation. Server owns reader/page size/identity/column definitions.
- Confirmed session, exact factory metadata under RLS, existing per-person departmental view grants before reading and again before delivery; existing protected readers independently scope factory/permission. No administrative `factory:export` requirement added. Movement item name/code comes from the Warehouse-authorized catalogue and matches entity+UUID, never client labels; missing/cross-factory identities fail. Identity lookup is bounded to first200 catalogue pages (10,000 identities), with explicit failure rather than guessed identity. An exact protected lookup would improve very large catalogues in a future task.
- Shared changes: optional typed filters/sort, fixed providers, actual page size/identity and necessary numeric scientific-notation support. Numeric Excel values, precision/nonfinite/underflow rejection, literal formula-safe strings and print escaping preserved. No new dependency or export framework.

## Verification, preservation and deployment

**Current verification:** **181/181 focused tests passed**, zero skipped: new Batch1 **15**, existing shared exports20, Quality23, administrative exports11, and Production History/Warehouse/Sales regressions. Final TypeScript passed. Isolated production build passed, including history/export routes. Generated Next config/type files restored byte for byte. No standalone PostgreSQL or real Supabase tests run in this export-only task; no SQL changed.

Actual components checked in loopback-only headless Edge: Production123 full /62 filtered; Stock124 full /61 filtered; Movements63. Exports from UI page2 contain every matching record. Print uses the same filtered counts and real landscape PDFs. Arabic124-row stock XLSX/Print/PDF, actual Arabic labels/RTL,390px operational screens, menu/dialog Escape and hidden controls without view authority checked; no unexpected console errors. Native print handoff observed with harness stub; OS dialog/manual device acceptance not claimed. Screenshot/workbook/PDF/browser JSON/lint/build/test evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-TableExport-Batch1-20261011` outside Git.

Shared visual lint used installed Edge through a temporary copy of its script. Findings are pre-existing muted4.44:1 text, intentional table scrolling and absolute menus extending short toolbar containers; screenshots show visible usable menus within the viewport. No unrelated global color/style change. Scoped React/Ponytail review found no safe required-behavior reductions.

All **82 migration bytes unchanged**. TESTING's earlier79 is historical, not queried here. No new migration required; no dependency on administrative export-reader80 or pending Quality81/82. Quality hosted UI still requires separately authorized deployment. All39 pre-existing dirty files outside the Batch1 manifest remain unchanged, including both Quality drafts and canonical Design System.

**Current owner TESTING policy:** factories/orders/inventory/scenarios are synthetic disposable demonstration data. Lack of PITR/restorable backup is not an automatic TESTING blocker or prerequisite for local development; no backup investigation repeated. Synthetic data may need recreation later. Exact migration-set approval, fresh intended-project history, tenant isolation and migration discipline remain required before remote writes; no reset authority is implied. Simulation stays isolated.

**Batch1 file manifest (21):** added `src/services/{production-history,table-export-operational}.ts`, `tests/table-export-batch1.test.mjs`, `tests/table-export/{batch1-browser-fixture.tsx,batch1-preview.mjs,batch1-browser-check.mjs}`. Extended `src/types/table-export.ts`, `src/components/TableExport.tsx`, `src/services/table-export.ts`, `src/utils/table-export.mjs`, `src/app/api/{production-history,table-export}/route.ts`, `src/features/{ProductionHistory,WarehouseInventory,WarehouseReceiving}.tsx`, globals.css, EN/AR locales, this record, HANDOFF and PRODUCT_DIFFERENTIATORS. No generated artifacts in the diff.

**Next action:** user manual acceptance, then separately authorized intended TESTING history/migration-set/integration work. Existing readers should allow Batch1 independently of pending SQL, but real Supabase sessions/RLS/PostgREST/download/print remain unverified. **Next suitable batch:** Sales Orders/items and Maintenance using existing protected paginated readers, preserving commitments/partial dispatch and person-specific access. Requests/Planning need complete protected readers before capped snapshot-backed export can claim all matching rows. Do not begin another batch automatically. Ponytail result: Lean already. Ship. This is a local diff review, not deployment/user approval.

---

# Earlier initial departmental export — 2026-10-10

Implemented locally on `development`, unchanged HEAD `3e249c9d222a08ebe1e85c5fd401818821ed77d2`. Existing Quality V1 work is preserved. No commit, push, remote database access/migration, deployment, account change, Simulation/3001, DEV, PROD or main operation.

## Scope and workflow

Quality staff can use a compact **Export** disclosure beside the table scope/count, then choose **Export to Excel (.xlsx)** or **Print / Save as PDF**. Placement follows the end of the toolbar in LTR/RTL. Native keyboard navigation, Escape, outside-click dismissal, preparation feedback, localized retry errors and cancelled stale requests are supported. An open menu handles Escape; a closed menu allows the enclosing history dialog to handle Escape.

Integrated surfaces:

- Quality production-by-shift board: all matching production recordings, including later pages.
- Per-recording rejection history: all matching historical rejections, including reversals with their status. This retains its separate `quality_history:view` requirement.

No other operational page was modified. Administration → Export Factory Data remains unchanged, including its stronger export/view permissions, allowlist, reader migration and tests.

The workflow follows the established convention of exporting from the filtered operational list: [Katana purchase-order export](https://support.katanamrp.com/en/articles/5944986-how-to-export-purchase-orders-po), [filtered batch export](https://support.katanamrp.com/en/articles/5966868-how-to-export-batch-tracking-info), and [MRPeasy usage tips](https://www.mrpeasy.com/usage-tips/). This is expected data-portability parity, not a product differentiator or backup facility.

## Small shared architecture

| File | Responsibility |
| --- | --- |
| `src/components/TableExport.tsx` | Reusable disclosure, download, native print handoff, scope/count, EN/AR, cancellation and errors |
| `src/types/table-export.ts` | Dataset identifiers, typed columns and shared report shape |
| `src/services/table-export.ts` | Server-owned dataset/filter/permission definitions, localized field allowlists and Quality row mapping |
| `src/app/api/table-export/route.ts` | Origin/session/grant checks, scoped protected readers, metadata, permission recheck and private file response |
| `src/utils/table-export.mjs` | Complete paginated collection, ExcelJS workbook and escaped standalone print HTML |

Further tables should add a fixed dataset definition and authorized provider using their existing protected reader, configure its actual page size and identity, define columns/units/metadata, then add the shared toolbar. Do not accept SQL table names, column names or authorization flags from the browser, or rebuild an independent reporting framework.

Task file manifest: **created** the five files above, `tests/table-export.test.mjs`, `tests/table-export/browser-fixture.tsx`, `tests/table-export/preview.mjs`, `tests/table-export/browser-check.mjs` and this document. **Modified** only `src/features/Quality.tsx`, `src/app/globals.css`, `src/locales/en.json`, `src/locales/ar.json`, `docs/PRODUCT_DIFFERENTIATORS.md` and `HANDOFF.md`. Other pre-existing Quality files, canonical Design System, environments, dependencies and migrations were preserved. Screenshots, workbooks, PDFs, logs and build output are outside the repository.

## Data, filtering and authorization

- Authenticate with the existing confirmed-session helper. Use the user's Supabase client, never a service-role client. Check `quality:view` or `quality_history:view` through existing per-person `can_access`, before collection and again before delivery. Factory metadata uses RLS and an exact factory predicate; the returned ID must match. Every page uses the protected `quality_read` RPC, which independently checks factory scope and permission. No new export grant or global `factory:export` is needed for these same authorized departmental reads.
- Production filters are precisely the current table's **exact actual-shift date**, shift, line, product and order text. Empty filters are omitted; UUIDs/calendar dates/types/lengths are validated. Order matching retains the existing SQL semantics, including whitespace/wildcards. Page is owned by the server; the current UI page is never used as export scope.
- Quality currently has no date-range, selected-row or status filter. `from`/`to` and other unsupported keys fail validation instead of being ignored. Tests cover exact dates, invalid calendar dates and rejected ranges. Future date-range support must first exist in the authoritative table reader, then be reused by export.
- History requires one validated production-entry filter. No cross-entry history download is exposed by this integration.
- Collection checks totals, exact page lengths and duplicate IDs, then reads all pages a second time and compares results. Detected changes fail with a retry message. This is a bounded consistency check, **not a transactional database snapshot**; concurrent changes that occur outside both reads cannot be ruled out. Prefer stable data while exporting. A cooperative 90-second cancellation signal is checked between reads; it does not cancel an already-running database query.
- Row output uses explicit business-field allowlists. No source IDs, hidden tenant IDs, tokens, source availability, physical labels, nested private objects or action controls are exported. Existing credential-pattern redaction is reused without altering administrative export.

## Excel and print

Production columns: Order, Production Item, line, actual shift/date, Product code/name, original gross Good, corrected Good, Quality rejected, accepted Good, Meter/Piece unit and recorded timestamp. Historical gross remains distinct from corrected/accepted quantities.

History columns: Order/Item/line/shift/date/Product, rejected production quantity, **Actual Scrap (kg)**, **Rework production quantity**, reason/description, disposition, status/actor, Meter/Piece unit and timestamp. Scrap and Rework occupy separate columns; inapplicable values are blank, never inferred zero. Rework quantity means the rejection routed to rework, not a fabricated processed/remaining total. Reversed rejections remain historical rows clearly marked as reversed; they are not presented as net totals.

Both formats include factory, report title, factory-local timestamp/timezone, readable applied filters and actual exported row count. Empty results still produce metadata/headers and a clear no-results print row.

- Excel: actual `.xlsx` using installed ExcelJS, numeric quantity cells, decimal formats, wrapped cells, useful widths, frozen header, worksheet filter and Arabic RTL view. Date/time is a factory-local formatted string; business shift date stays the recorded calendar date. User formulas are stored as literal shared strings, never formula objects/hyperlinks. More than 15 significant digits or numeric underflow is refused rather than silently rounded to an unsafe exported quantity. Dataset/date filenames are server-owned.
- Print: synchronous blank-window opening avoids asynchronous popup blocking; escaped HTML contains no scripts, external resources or navigation. Browser-native `print()` is invoked after fonts are ready; a screen-only retry Print button remains available after cancelling the dialog. Printed CSS is white, uses existing typography/colors, repeated table headers and row-break avoidance, with A4 landscape for wide tables and portrait for narrow configurations. Pop-up blocking gets a localized actionable error.
- Explicit limits: **Excel 10,000 rows / 10 million text characters; Print 500 rows / 2 million text characters; individual cells 32,767 characters**. Exceeding limits fails before file delivery; no silent truncation or page-only fallback. Print's limit message offers Excel. There is no heavy PDF/spreadsheet dependency added.

## Verification and limitations

Current focused run: **54/54** passed (20 new export tests, 23 existing Quality tests, 11 existing administrative export tests). TypeScript passed. Production build passed after the final toolbar/precision fixes. No unrelated full suite or SQL/database suite was rerun for this read-only data capability.

Coverage includes workbook reopening, numeric cells/headers/metadata, 123-row paginated collection, exact date/shift/line/Product/order forwarding, unsupported ranges, EN/AR labels, RTL print, empty/null data, limits/text budgets, mocked session/grant/cross-factory denial, authority revocation, origin rejection, field exclusion, formula/XSS safety, and Scrap KG versus Meter/Piece Rework. These route mocks prove application routing/checks, **not live Supabase RLS or Auth behavior**.

Real headless Edge with the actual Quality/TableExport components and an isolated local API fixture verified:

- Keyboard Enter/Tab/Escape, English desktop1440px/tablet768px and Arabic mobile390px.
- Full125-row Excel download; a filtered62-row Excel download while the UI was on page two; actual Arabic worksheet RTL.
- The same62 filtered rows in Print; `window.print` handoff and genuine browser PDF rendering: five landscape pages. Arabic rejection-history PDF: one landscape page, separate kg/Rework cells.
- History-menu Escape versus dialog Escape, clear print-limit error/retry, closed failed preview, blocked pop-up feedback, localized network-failure feedback and no horizontal page overflow. No unexpected console/page/network errors; one intentional409 and one deliberately aborted request are recorded separately.

The browser harness replaces `window.print` to observe the handoff; it does not claim OS print-dialog/manual Save PDF acceptance. PDF layout is produced by Edge's real print engine. No hosted session, PostgREST, Supabase RLS or remote fixture was used. The existing localhost3000 app still points to its configured environment; it was not used to exercise the undeployed Quality schema.

Skill visual lint: no findings in the new toolbar after its scope label uses existing foreground color. Three existing muted-text contrasts are4.44:1 on the page background (including the fixture note). Arabic mobile lint also flags11 intentionally visually clipped accessible table-header elements; rendered row labels remain visible and the page has no horizontal overflow. These unrelated styles were preserved. Arabic/English print and desktop/mobile screenshots were visually inspected.

Evidence is outside Git: `%TEMP%\FactoryLean-TableExport-20261010\proof` contains six screenshots, three Excel samples, two PDFs, `browser-results.json` and visual-lint JSON. Isolated build/logs are retained in the parent directory; generated Next config/type edits were restored byte for byte. Test scripts are `tests/table-export.test.mjs` and `tests/table-export/{browser-fixture.tsx,preview.mjs,browser-check.mjs}`. The fixture binds only127.0.0.1:4203 and never proxies to Supabase. Owned server/browser processes are stopped after verification.

Skills actually used: installed UI/UX, Frontend Design Codex, project frontend-design (better-web-ui context), Ponytail Lite and scoped Ponytail Review; existing Supabase guidance and React best-practice review. No separate skill named `better-web-ui` was installed or invented. Scoped Ponytail review: **Lean already. Ship.** This is a simplicity result, not deployment authorization.

All82 migration contents match the inspection baseline; the two Quality drafts and pending administrative export reader are unchanged. Historical TESTING79 is not a current alignment claim and was not re-queried. Departmental export introduces no migration and does **not depend on** `20261006072000_factory_export_reader.sql`. The existing Quality reader still requires the separately authorized Quality deployment before hosted/manual testing.

## Remaining rollout inventory (planned, not implemented)

| Order | Surface / existing implementation | Provider / safeguards for later integration |
| --- | --- | --- |
| 1 | Production Recording History (`ProductionHistory.tsx`) | Reuse `/api/production-history`; full from/to, shift, Product, technician, unit/correction and quantity filters; retain gross versus corrected and Scrap KG |
| 2 | Warehouse Stock (`WarehouseInventory.tsx`) | Reuse `warehouse_inventory`; identical typed filters/sort, unit breakdowns, unknown values, accepted Incoming and source-safe totals |
| 3 | Warehouse Movements / Good acknowledgments / WIP (`Warehouse.tsx`, `WarehouseReceiving.tsx`, `WarehouseOutputs.tsx`) | Reuse `warehouse_movements` and protected Supply readers; include direction, event context and units without exposing unauthorized source data |
| 4 | Sales Orders/items (`SalesOrders.tsx`) | Reuse `sales_orders_page`; flatten Order/Item with commitments/partial dispatch preserved; no sum of Meter and Piece |
| 5 | Production Request/Item queue (`ProductionOrdersV2.tsx`) | This queue still filters snapshot data; add a protected complete reader before calling it universal export. Preserve request/item hierarchy and accepted/gross/replacement distinctions |
| 6 | Maintenance (`Maintenance.tsx`) | Reuse `/api/maintenance` query/status/assignee/line permissions; preserve person-specific access |
| 7 | Purchasing / Warehouse requests / Suppliers (`Purchasing.tsx`, `MaterialFlow.tsx`, `Suppliers.tsx`) | Reuse protected Supply readers and requester/Purchasing ownership; full active filters and appropriate supplier-contact field allowlist |
| 8 | Planning (`ProductionPlanning.tsx`) | Export a tabular schedule using a protected complete reader, exact horizon/line filters and planned/actual distinction; never mutate schedule |
| 9 | Downtime and Reports (`DowntimeAnalysis.tsx`, `Reports.tsx`) | Preserve existing `/api/export` CSV and `reports:export` plus `downtime:view` policy; agree whether new options retain this explicit grant. Reuse authoritative period/timezone/KPI semantics rather than capped snapshot rows |
| 10 | Lean Analysis / problems / actions (`LeanAnalysis.tsx`, `LeanProblem.tsx`) | Reuse `/api/lean` readers, date/filter scope and frozen comparison evidence; separate quantities by unit and avoid treating a paginated KPI as a full dataset |
| 11 | Products/recipes and authorized administrative histories | Separate dataset-specific permissions/fields; no broader factory backup privilege or contacts exported by accident |

Per-table acceptance: all-page filtered versus visible-row comparison, permissions/tenant tests, empty/large data, EN/AR/RTL, actual workbook/print review and user acceptance. None of these future integrations is claimed complete.
