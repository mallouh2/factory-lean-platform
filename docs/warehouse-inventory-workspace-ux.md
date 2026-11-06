# Warehouse Inventory workspace redesign

2 November2026. **LOCAL COMPLETE; owner visual review pending.** Frontend-only operational reorganization;not a hosted release,activation or full-platform audit.

## Product decision and source inspection

User:Warehouse operator looking up physical stock,receiving external/opening stock,or inspecting why stock is reserved. First decision:find the item or act on the existing request. Success:read typed physical quantities,follow a real reservation/history reference,and complete the existing authorized workflow without confusing administration with daily work. Recovery keeps protected errors,retry identities and input rules. Modern Industrial tokens/Inter/IBM Plex Sans Arabic,existing components and CSS architecture reused;no dependencies,new role model or global shell redesign.

The starting Inventory mixed a separate warehouse-admin row,type filter,receiving/history/settings buttons,distant search and multiple repeated explanations. Existing Inventory Management actually provided **Add Material**,finished-product supply/min-max configuration,and protected stock adjustments;it was not a general Product creation/editor. Accurate new destination:**Item & Stock Settings / إدارة الأصناف والمخزون**. Products module itself is unchanged.

The Receive Stock button continues to use its original external_receipt/opening_balance contract and compatible receipt warehouse. It does not receive arbitrary unapproved production;inspected production remains under Warehouse Requests. No generic inbound Quality gate was added.

Comparable official references:[MRPeasy Stock](https://www.mrpeasy.com/resources/user-manual/stock/) separates inventory/item/lot tasks;[Odoo Moves History](https://www.odoo.com/documentation/17.0/applications/inventory_and_mrp/inventory/warehouses_storage/reporting/moves_history.html) treats history as a detailed movement report. Adaptation:compact daily overview and a distinct read-only history destination,without adopting their accounting/location models. The owner's direction was already approved;no additional style-selection gate was invented.

## Main workspace and preserved capabilities

- Existing Inventory / Warehouse Requests remain the only main tabs. Existing page title retained;no decorative header cards.
- Inventory heading groups **Receive Stock** as primary and **Management & Records / الإدارة والسجلات** as secondary. Menu entries have concise purpose descriptions.
- Stock Movements remains an independent entry. Item & Stock Settings retains Add Material,Stock Settings/configuration and the existing Adjust Stock transition. Manage Warehouses retains the three existing definitions and protected administration.
- Search and type filter share one row immediately above Actions,Columns,Filters,Clear and existing Export/Print. The table begins423–454px from the top at1440×1000;previous image began~615px. No excessive empty header gap or duplicate quantity-explanation paragraph.
- Single-row selection,double-click/Actions Details,stock replenishment,sourcing,purchase actions,non-production receiving,stored-WIP view and return,type badges,column preferences,search,typed filters,sort and global-matching export remain. Requests and its fixed matching-count pagination were not modified.

## One Stock Movements viewer

WarehouseMovements is reused by the Management & Records entry and **View All Movements** in item details. The second route preselects the exact item,including an item missing from the current catalogue snapshot,and returns to Details. No nested modal. The viewer uses a960px desktop drawer and full mobile sheet,with a bounded scrolling body. Product/type controls are first. The existing single searchable combobox opens its list in normal viewer flow so ancestor overflow cannot clip its first option. Keyboard selection/Escape and visible focus remain.

History still uses authenticated fulfillment/warehouse_movements with its real25-row pages;filter/item changes reset the page,known totals disable Next and polling can clamp a removed final page. Existing snapshot-driven retained-data hook now refreshes this viewer normally,unlike the removed bespoke fetch which cleared results and did not observe fetchedAt. It never edits inventory.

Rows show movement name,signed physical quantity/unit,direction,date/time in the factory timezone,actor where available,source reference and optional note. Green incoming,red outgoing,amber reservation-only. **Zero physical delta** explicitly says No physical stock change;reserved_delta is a distinct value,never an invented physical movement. Recent protected context enriches actual references for its most recent five events;older records retain only whatever reference the existing history reader supplies. No guessed order/actor identifiers. Existing Excel/Print uses all matching selected-item history and original protected export contract;no new ledger or export data broadening.

## Item details and forecast

Identity(code/category/unit),one three-card physical summary,actual reserved orders,up to5 recent ledger events,and View All Movements. The second large Reserved total and full-history accordion are removed. Recent events reuse the same MovementRow rendering. All five may include genuine reservation-only ledger events;these are accurately marked rather than omitted or presented as stock credit.

Projected Stock / الرصيد المتوقع,Expected Incoming / وارد متوقع,active production remaining,demand deduction,min/max,supply category,typed unit breakdown and lazy source traceability live under **Additional Inventory Details**. Source labels,quantities,unattributed stock and protected history remain. Production Details/Receiving,Quality Inspection,Completion/Replacement and Original Order shortcut buttons are removed only from this drawer;underlying department routes and source relationships are untouched. Authorized reserved Sales/Production order inspection remains.

Actual SQL reviewed locally:private.finished_inventory_projection uses output_stock_free + quality_production_remaining − Sales incoming allocations − uncovered approved Sales demand. private.warehouse_inventory_rows splits active production remaining from future incoming and adds purchase_incoming once. Therefore the displayed finished formula is **Available + Expected Incoming + active production remaining − committed/uncovered Sales demand**. Available already includes protected source/hold exclusions. Received output is already in stock;reserved stock is not subtracted twice. Materials use Available + eligible purchasing incoming.

warehouseForecast is a display-only exact-decimal breakdown of the existing typed row;it derives the combined demand deduction without querying/generating orders. Unknown unit/components or inconsistent negative deduction do not invent a breakdown. Separate production/purchasing or per-order future-demand components are not exposed by the current row and are not guessed. The protected projected result is never replaced by a client formula. Stock export adopts the same clearer Warehouse column labels without changing quantities,rows or authorization.

Reverified owner Product X / MP:On Hand1077m,Reserved982m(1m SO-0000001 +981m SO-0000002),Available95m,Projected1098m. The unchanged +95m physical receipt and source PO-0000022 remain visible;earlier +890m source PO-0000032 and real reservation events remain distinct. Full receipt trace:[preceding verification](warehouse-inventory-clarity-v2.md). The separate existing Unified acceptance product has an actual60m expected shortage;this remains forecast demand,not negative physical stock.

## Verification

- **69/69 focused Node PASS:**existing receiving/request eligibility,all pagination boundaries,retained refresh hooks,stock/export permissions/isolation,EN/AR item summary/lazy source/negative projection,shared history preselection,and new exact-decimal forecast/physical-versus-reservation movement tests. Initial test-double default-export and selector/case ambiguities were corrected;they were not application defects.
- **TypeScript and isolated optimized final build PASS.** No repeated broad Quality/Warehouse/concurrency suite:posting writers and SQL are untouched. Prior physical-receipt/idempotency/concurrency evidence remains applicable to unchanged contracts;not misreported as new operational execution.
- **Live local read-only PostgreSQL PASS:**exact1077/982/95/1098m,982m attributable reservations,7 history records,latest physical95m;three genuine restricted/foreign reads rejected. No accounts,permissions or memberships changed.
- **Normal authenticated owner browser PASS:**daily receiving form with opening balance option;Stock Movements independently and preselected;Add Material;stock configuration and protected Adjust Stock screen;three warehouse definitions;authorized SO inspection;stored-WIP return and Requests. Forms opened but not submitted;zero operational POSTs.
- **Excel/Print200,count7** for movement history. Existing inventory export regression and final labels validated;no native print dialog or repeated downloads. No inventory arithmetic or receipt delta changed.
- **EN/AR1440/768/390 screenshots PASS**,including main Inventory,three-card Details and wide/full-mobile Movements. First product option y203px,height44px;visible immediately. No document overflow outside intended scrolling. Actual recent receipt/reservation signs and authorized source/order references verified. Browser pageerrors empty.
- Real30s refresh observation and visual lint **PASS**:see final refresh.json. It covers Inventory,Arabic390 Details and Movements without disabling timers. Same query retains table/dialog/focus/filter/scroll and values;fresh authenticated responses are measured,not a fabricated stock change.

Temporary4240 test login was correctly rejected by existing APP_ORIGIN4222. It was stopped;checks ran at4222 without changing/bypassing origin protection. Early refresh-test failures were test timing/shared-language-context issues;independent normal-login browser contexts are used in final evidence. No observed application data/security failure was patched around.

### Final real-refresh evidence

|View|Actual snapshot cycles|Table/dialog/focus nodes|Outer scroll|Body scroll|Relevant contrast/tiny-text/image findings|
|---|---:|---|---|---|---:|
|inventory|2|stable|0||0|
|details-ar390|2|stable|0|120|0|
|movements|2|stable|0|120|0|

Each observed sample retained document/body height,filter/input value,selection and summary. No transient loading paragraph,no operational POST and no pageerror. Shared visual-runtime audit was executed against authenticated pages;intentional scrolling/container overflow findings are retained in raw evidence and do not imply clipped leaf text or a global accessibility certification.

## Preview, evidence and preservation

**http://127.0.0.1:4222/?view=warehouse**. Existing PlanningV3@local.invalid;unchanged credentials:

C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt

Current isolated build:warehouse-workspace-ux-final-app. Existing database127.0.0.1:55496(factory_lean_quality_local),Auth4304;independently validated marker/data directory/environment. QA and other previews were not restarted or written during this task. Browser checks block operational POSTs and all non-preview origins.

Evidence outside Git:

C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/warehouse-workspace-ux

browser.json,reader-checks.json,refresh.json,preservation.json,final-typecheck.txt,final-build.txt retain actual results. Screenshots:inventory-{en,ar}-{1440,768,390}.png;details-{en,ar}-{1440,768,390}.png;movements-{en,ar}-{1440,768,390}.png;movement-selector-en.png;forecast-product-x.png/forecast-shortage.png;refresh-*-start/end.png. These are local real-application screenshots,not hosted acceptance.

All122 existing owner table digests and all138 historical migration files are preserved;**no new migration or database function change**. Existing Design System,Export Reader,dirty files and source environment config preserved. Shipped manufactured-output gateFALSE and completed-shift gateFALSE;inherited disposable-loopback manufactured test predicate remains unchanged. No new activation,hosted TESTING/DEV/PROD/Simulation access,deployment,Git writes or localhost3000 changes. development HEADbb0d20e5dd433b896dd319f56e75f0d9eb5d2862,index empty.

## Exact task delta (23 files)

Compared by SHA256 with the dirty-worktree starting snapshot,not merely against HEAD:

- HANDOFF.md
- docs/design/UX_SIMPLICITY_STANDARD.md
- docs/refresh-layout-stability.md
- docs/warehouse-inventory-workspace-ux.md
- docs/warehouse-management-v2.md
- src/features/Warehouse.tsx
- src/features/WarehouseInventory.tsx
- src/features/WarehouseItemDetails.tsx
- src/features/WarehouseMovements.tsx
- src/features/WarehouseReceiving.tsx
- src/features/WarehouseReservations.tsx
- src/features/WarehouseUi.tsx
- src/features/warehouse-v1.css
- src/locales/ar.json
- src/locales/en.json
- src/services/table-export-operational.ts
- src/utils/warehouse-presentation.mjs
- src/utils/warehouse-view.mjs
- tests/warehouse-view.test.mjs
- tests/warehouse-workspace-browser.mjs
- tests/warehouse-workspace-preservation.mjs
- tests/warehouse-workspace-refresh.mjs
- tests/warehouse-workspace.test.mjs

## Limits and handoff

Owner visual approval remains pending. Pooled factory inventory is unchanged;receipt warehouse is provenance only. No per-warehouse balances,stock-out allocation,transfers or valuation. Viewer selection uses the existing authorized catalogue/snapshot;no new global-history backend or unbounded catalogue reader was added. Older history may lack a readable source reference. Forecast provides combined authoritative supply/demand components,not invented per-order/purchasing splits. No broader product/business capability changed,so PRODUCT_DIFFERENTIATORS was reviewed but not amended. Stop;no next feature/checkpoint/deployment.
