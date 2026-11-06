# Warehouse Inventory clarity and Requests pagination V2

1 November 2026. **COMPLETE / LOCAL VERIFIED; owner visual approval pending.** This is a focused follow-up to Warehouse V2, not a warehouse-ledger redesign or hosted release.

## Verified receipt and balances

Existing owner factory3ab24bb6-654e-40ab-a8bd-e0c8ca5c62c8; Product X pipe / أنبوب المنتج س (MP), Product8980e5b8-4f72-4458-afe8-931a15cd90b8, Meter. Execution **PO-0000022**, requestPO-0000021, item4afef1ed-2824-4c8a-ac4a-2a048142bbb8; entryae482a1e-6dd7-435d-9720-97b1ced52cf2; outputa85e37bc-616a-4c74-ad6d-19433816c585.

Recorded Good98m. Quality revision2 classified95m finished,1m recoverable unfinished requiring Printing,2m rejected with measured1kg. The unfinished receipt created its separate1m lot; it was not finished stock. Finished entitlement was95m before the receipt and0m afterward. Receipt revision4 produced exactly one movement7d695337-d514-4180-995f-feaefc8b327f at2026-11-01T11:16:14.568673Z (14:16 Qatar), destination Finished Goods Warehouse.

| Authoritative measure | Before this receipt | After/current |
|---|---:|---:|
| Physical On Hand |982m|1077m|
| Reserved |982m|982m|
| Available |not independently reconstructed|95m|
| Protected Projected |not independently reconstructed|1098m|

The ordered movement ledger establishes982→1077 with no subsequent movement for this Product;this is not current minus95 inference. Reserved-delta history establishes982→982. Current primary table reader returns1077/982/95/1098. SO-0000001 reserves1m;SO-0000002 reserves981m (approved). Reservation982 remains inside physical1077. Separate unfinished quantities are not merged into finished Good. Forecast1098 remains the existing protected forecast, not a new formula.

**Root cause: presentation/explanation, not duplicate/missing credit or a reproduced filter/aggregation defect.** No inventory calculation was replaced. Owner data were read-only throughout.

## Inventory interface and protected detail contract

One existing Product/unit grouping remains. Blue,strongest On Hand;amber Reserved for orders;green Available;secondary Projected. Labels include الموجود بالمخزون / المحجوز للطلبات / المتاح / المتوقع. Text and units carry meaning independently of color. Genuine shortage styling remains distinct. Search,typed filters,sort,column preferences,all-matching inventory export and print remain.

Selecting Details or the Reserved value shows the authoritative four quantities,actual active reservation rows (50/page),purpose,recorded reservation state,source details where present,and a permission-controlled readable order link. The linked Sales/Production order is inspected read-only inside the drawer,without a nested modal. SO references are primary identifiers;unattributed/material reservations do not become invented Sales Orders. Source allocations are supporting children and never added twice. The reserved heading includes all pages;the visible range is explicit. An excess over the recorded reserved balance raises a discrepancy;unknown units stay unknown. Nothing repairs or deletes reservations.

Recent five same-unit movements reuse warehouse_movements and show signed quantity,actual source order and timestamp where available. Full existing movement/source history stays on demand. No duplicate movement ledger.

New forward-only **20261101115302_warehouse_inventory_context_v2.sql** is necessary because the existing inventory aggregate/movement contracts did not expose the required protected reservation-to-order explanation. It adds only stable SECURITY DEFINER readers warehouse_inventory_context and warehouse_reservation_order,empty search_path,explicit factory+Warehouse view checks and additional Sales/Orders view for linked order details. PUBLIC/anon/service execution revoked;authenticated execution granted. No table,posting writer,reservation transition,permission definition or activation change. New authenticated GET /api/warehouse-inventory validates identity/unit/page and delegates authorization to those RPCs.

## Requests pagination root cause and correction

The previous client independently paged raw source datasets,then projected eligible requests and applied search/type filters. Source page capacities differed (Sales25 versus supply50);raw full-chunk heuristics/metadata could claim Next despite no later matching request. A display-only row-count check would lose legitimate later-source matches.

The new authenticated GET /api/warehouse-requests reuses existing protected readers,collects their actual counts or genuine has_more,combines eligible requests,preserves intended source/order sequence,filters globally and returns matching total/page/pages/has_more at50 rows. It fetches dispatch availability only for visible Sales orders. Client resets filters to page1,clears stale scope metadata,retains same-scope rows during polling,applies server clamps atomically and disables navigation on unknown/error/empty results. No shared pagination component or other modules were changed. Export/Print reuse this same current matching page (existing department_page request field retained).

A source scan is bounded to200 counted pages/10000 source rows (Sales25/page reaches the page limit sooner). Incomplete,duplicate or changed source totals fail closed rather than silently truncate or guess Next. Multiple RPCs are not an atomic database snapshot;same-count concurrent membership changes cannot all be detected. Protected issue/receipt/dispatch commands still revalidate authoritatively. Large-history query optimization is a future task,not an unbounded scalability claim.

## Verification and controlled fixtures

- **59/59 focused Node PASS**: warehouse view,global Requests boundaries0/1/3/49/50/51/101,full raw chunks,actual Sales25paging,search,type,clamp,source-count errors,existing export and retained refresh lifecycle.
- **8 standalone PostgreSQL rollback scenarios PASS**:Quality-approved0.5m partial receipt increases physical stock once;legitimate existing incoming commitment moves0.5m to Reserved while Available stays unchanged;original UUID retry once;actual Sales/Production/material attribution;released reservations excluded;61 reservation rows50+11 reconcile;wrong unit and same/foreign-factory denial;readers do not create events.
- **2 actual concurrent QA receipt races PASS**,each with observed lock wait:same UUID returns twice with one0.1m receipt;different UUID/stale revision permits one0.1m receipt and rejects the other with output_revision. Existing QA qcompact3 received3.8→4.0m;Available0 unchanged because incoming commitments legitimately converted to stock reservations. No duplicate credit,negative balance or owner write.
- Existing QA owner created one WQ-PAGE-V2 material and51 small requests through protected commands,no stock credit. Browser verified50+1,Next/Previous,filter/search reset,single result and zero results. One controlled normal cancellation200 removed the last-page request;polling clamped automatically to50/page1. Fixture remains for regression;do not recreate/repeat durable races/cancellation blindly.
- Final matching Requests Excel/Print HTTP200,**50 rows each**,actual XLSX/HTML bodies;no native print dialog or repeated downloads required. Existing inventory export regression PASS.
- Existing restricted actual-login account receivesHTTP403 from both new inventory and Requests APIs;no permission/user/membership changes. SQL tests exercise known existing foreign fixture identities and denied order reads.
- Real normal-owner login/read checks PASS. Inventory EN1440/768/390 and Details EN/AR1440/768/390;Requests EN/AR1440/768/390. No document overflow outside intentional table scrollers. Inline order drill-through works. Screenshots visually inspected,including Arabic390 and desktop quantities.
- Two real30s refresh cycles per workspace:selection,filter,focus,document/table/drawer identity,outer/inner scroll,reservation details and no transient loader collapse preserved. QA final-row cancellation visibly updated the real queue;owner latest-build read-only polling repeated PASS. Automatic refresh was not disabled/accelerated.
- TypeScript and isolated optimized production builds PASS for owner and QA latest review copies. Known existing Next start/standalone warning is operational guidance,not an authenticated API error. Initial pre-login unauthorized snapshot logs are separate from authenticated acceptance;browser pageerrors were empty.

This is PostgreSQL17/local Auth/Data API fixture evidence,not real hosted Supabase integration or deployment acceptance. No unrelated full suite was run. The UI uses existing tokens/components;React review and Product Differentiators check found no material new competitive claim requiring that document to change.

## Runtime, evidence and preservation

Owner preview **http://127.0.0.1:4222/?view=warehouse**. Existing **PlanningV3@local.invalid**;unchanged verified credentials file:

C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt

Owner database127.0.0.1:55496;Auth4304. Separate QA4238/database55500/Auth4322. Both use warehouse-inventory-v2-review-app isolated builds with unchanged local-only environment config. Other previews and3000 untouched. A runtime interruption required restarting these exact owned local processes with ordinary PostgreSQL WAL recovery;no reset,restore,history repair or unrelated process termination.

Evidence directories (outside Git):

- Owner: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/warehouse-inventory-v2
- QA: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Production-End-65b76ac01c494ac6b7b57f99886b9f6f/warehouse-inventory-v2

Owner owner-trace.json and owner-reservation-ledger.json contain the exact source/movement/ledger evidence. preservation.json verifies all**122** original owner table digests and all**137** historical migration SHA256 hashes unchanged. browser.json/refresh.json retain HTTP/sampled layout evidence;QA protected.json/concurrency.json/final-smoke.json retain SQL/race/export/denial results. build.txt/typecheck.txt and review-app .next/BUILD_ID identify optimized builds.

Screenshots: owner inventory-en-{1440,768,390}.png;details-{en,ar}-{1440,768,390}.png;QA requests-{en,ar}-{1440,768,390}.png;both refresh-*-start/end.png. Full source test commands/scripts are in the manifest below. Credentials are never embedded in reports/test logs.

The manufactured-output **shipped** gate remains constantFALSE;completed-shift activation rows remainFALSE. The inherited disposable-loopback-only manufactured test predicate evaluatesTRUE in these fixtures and was not introduced or changed here. This distinction is essential:local fixture execution is not feature activation. Pooled balances/issues/dispatch unchanged;receipt warehouse identity remains provenance only. No remote access,deployment,Git writes,activation,new account/grant,Design System change or Export Reader change. development HEADbb0d20e5dd433b896dd319f56e75f0d9eb5d2862;index empty.

## Exact task delta (29 files)

This list compares file hashes with the preserved dirty-worktree starting snapshot,not merely git diff against HEAD. Earlier unrelated changes remain untouched.

- HANDOFF.md
- docs/design/UX_SIMPLICITY_STANDARD.md
- docs/refresh-layout-stability.md
- docs/warehouse-inventory-clarity-v2.md
- docs/warehouse-management-v2.md
- src/app/api/warehouse-inventory/route.ts
- src/app/api/warehouse-requests/route.ts
- src/features/WarehouseInventory.tsx
- src/features/WarehouseItemDetails.tsx
- src/features/WarehouseRequests.tsx
- src/features/WarehouseReservations.tsx
- src/features/warehouse-v1.css
- src/locales/ar.json
- src/locales/en.json
- src/services/table-export-warehouse.ts
- src/services/warehouse-requests.ts
- src/utils/warehouse-view.mjs
- supabase/migrations/20261101115302_warehouse_inventory_context_v2.sql
- tests/warehouse-inventory-v2/browser.mjs
- tests/warehouse-inventory-v2/build.mjs
- tests/warehouse-inventory-v2/concurrency.mjs
- tests/warehouse-inventory-v2/final-smoke.mjs
- tests/warehouse-inventory-v2/local.mjs
- tests/warehouse-inventory-v2/pagination-fixture.mjs
- tests/warehouse-inventory-v2/preservation.mjs
- tests/warehouse-inventory-v2/protected.mjs
- tests/warehouse-inventory-v2/refresh.mjs
- tests/warehouse-requests-pagination.test.mjs
- tests/warehouse-view.test.mjs

## Remaining limits and stop

Owner visual review is pending. Warehouse-level balances,warehouse-specific stock-out allocation/transfers and large-history server query optimization remain out of scope. No preservation work for obsolete synthetic quantities was added. No Quality/Production/Planning,shift recording or unrelated workflow change. Stop after this report;no checkpoint or next task.
