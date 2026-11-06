# Warehouse Inventory workspace follow-up — 2 November 2026

The redesigned movement viewer now uses the existing retained useFulfillment lifecycle and normal snapshot.fetchedAt refresh. Its former bespoke history fetch cleared history and did not subscribe to background snapshot updates. Item Details no longer renders a second full-history accordion;recent5 and the dedicated viewer reuse existing protected readers. Initial loading stays distinct from background busy state. No global refresh-hook,timer,scroll-restoration or page-shell changes.

Current read-only real-cycle observation covers Inventory,Arabic390 Item Details and Stock Movements. Exact samples/screenshots/status are recorded in [workspace report](warehouse-inventory-workspace-ux.md) and the existing owner runtime/warehouse-workspace-ux/refresh.json. No operational write is needed to prove fresh reads render;do not claim a fabricated quantity change on unchanged owner stock.

# Inventory reservations / Requests pagination follow-up — 1 November 2026

Current WarehouseRequests retains loaded same-filter results while the authenticated combined page refreshes. Server-clamped page changes are applied with the corresponding retained response; scope changes cannot reuse old metadata. New inventory explanation/history panels use initial loading rather than background busy state. Shared30s polling and global layout are unchanged.

Actual acceptance:51 matching material requests,50+1 navigation;normal protected cancellation of the last-page request200;next poll returned to page1/50 rows without losing WQ-PAGE filter or focus. Two further real cycles passed. Owner Inventory selected Product X/Arabic390 reservation drawer and Requests selection/focus/table/scroll also survived two real cycles, repeated against the final review build. No timer acceleration or application scroll workaround. Screenshots/samples: [current report](warehouse-inventory-clarity-v2.md). Do not rerun the durable cancellation as new intent.

# Background refresh layout stability — 31 October 2026

## Warehouse V2 follow-up —1 November2026

The Requests workspace added after the earlier global fix had its own polling loader: `setLoaded(false)` inserted a paragraph above an otherwise retained table. Settled pre-fix Requests document height1108↔1142px through real polling; outer108px was held by browser anchoring in this trace. The paragraph also flickered behind an open receipt. Its dispatch pool separately cleared known values to an empty map during refetch. Inventory after initial settle was already stable (document1313px,outer180px,inner120px); no Inventory failure was invented.

`WarehouseRequests` now retains its loaded state and dispatch map for same-context background refresh. Factory/page changes still clear scoped results. Shared hooks,30s timers and cleanup are unchanged. No `scrollTo`, global scroll lock, stale-data freeze or new subscription was added. Receipt forms retain category, quantity, warehouse,note,focus and selected request; the post-commit revision read-back guard is separate from ordinary background polling.

Final real polling, two cycles/page: Inventory outer120px/document1369px/inner80px; Requests outer120px/document1164px; Arabic390 drawer document844px/inner80px,textarea focus/note/warehouse unchanged. Page/table nodes stayed alive; no transient loader/page error. A separate legitimate QA receipt changed available90.3→90.2m through polling while the0.2m draft remained. Owner normal-login checks were read-only. Source/build/screenshot/evidence details and final preservation: [Warehouse V2](warehouse-management-v2.md). Original31October evidence below remains historical and does not imply all later workspaces were covered then.

**LOCAL COMPLETE; owner manual acceptance pending.** Coordinated with the final Planning V3 simplification in `planning-v3.md`. No hosted evidence or release approval is implied.

## Observed cause, before changing refresh behavior

Actual authenticated Edge observation sampled document position, height, component identity, focus and nested scroll every40ms for68s/page. Timers were not accelerated. Each page received at least two normal30s `/api/data` updates. Existing owner records were read-only.

| Page, desktop1440 | Before | After root corrections, two real cycles |
| --- | --- | --- |
| Planning | scrollY450→554→450 twice; document2257→2300→2257px | scrollY450 throughout; document2225px throughout |
| Warehouse | document982→1056→1016→982px twice; scrollY82 held by browser anchoring | document982px and scrollY82 throughout |
| Factory Floor | document3363px and scrollY450 already stable | document3363px and scrollY450 remain stable |

Planning's protected operational reader retains data but correctly becomes incomplete while validating. Conditional readiness banners and disappearing line-load indicators changed geometry on each fetch. Warehouse's parent and inventory child each inserted a loading paragraph despite retaining their data. These two paragraphs caused the74px transient expansion. There was **no shared shell remount**, and FactoryApp was not replacing the page with its initial loader. Floor's desktop jump was not reproduced; do not describe it as a confirmed pre-fix failure.

The existing drawer focus effect also depended on the refreshed order object. It now depends on selected identity/presence. Before-fix focused-drawer movement was not separately measured; the final focused-drawer test passed.

## Implementation and safety

- `useFulfillment`/`useSupply` expose initial `loading` separately from background `refreshing`. Existing `busy` and all action-validation guards remain. Previously loaded same-query content survives a transient read failure; authorization failures clear it. Query changes cannot show a different query's retained data; abort cleanup remains intact.
- Warehouse, Stored Unfinished, Purchasing, Suppliers, Material Requests, Sales and source-identification views use initial-loading semantics for their visual loading messages. These are the same bounded loader corrections, not a navigation or business-workflow redesign. Source identification retains its form during same-query refresh. Existing request/quantity/permission guards still use busy/error as before.
- Planning keeps one reserved-height availability line and the last available load/gap visuals while validating. This is display only: fresh reader completeness still gates drag/slot actions. Metadata-unavailable saves are refused; protected SQL remains authoritative for manual placements outside the loaded range. Inputs remain editable during revalidation so focus/drafts are not lost. Save eligibility, capability checks, Planning locks/reasons and maintenance SQL protections remain.
- Production Start readiness keeps its previous status text during background loading; actual Start eligibility still uses the existing loading/security checks.
- The30s visible-document polling and cleanup in `FactoryApp.tsx` are unchanged. There is no application scroll lock, refresh `scrollTo`, timer acceleration, new subscription or artificial scroll-back fix. Routine availability updates do not repeatedly announce themselves; actual errors retain alert semantics.

## Final browser and test evidence

The final optimized build ran at4222 against the existing owner database55496/Auth4304. Two real cycles **per page** verified:

- Planning390px Arabic RTL: open drawer, unsubmitted datetime, source Details expanded, focus, document scroll and drawer scroll80px retained. No mutation submitted. Actual Printing no-fit blocker remained.
- Warehouse768px: search/filter `Product`, selected row, focus and current page retained. Earlier desktop observation covers a genuinely scrollable unfiltered inventory page.
- Floor390px: machine dialog, focus, panel and page positions retained. Initial async loading was allowed to settle3s before sampling; an earlier run caught one initial height increase before the first periodic refresh, not a periodic jump.
- No authenticated API failures, business POSTs, page errors or modal closures in the owner observation. Desktop/768/390 screenshots were inspected, including EN headings and AR RTL containment.

Separate QA55499/Auth4320/app4237 used the existing identities and capable resources. Two small requests created through authenticated application commands appeared through ordinary polling **without navigation/manual Refresh or scroll movement**. Printing manual Save200 and actual native pointer drag200 persisted2min schedules; existing Extrusion details/selection remained usable. Capability400, lock400, restricted actual-login400 and known foreign-factory-context400 denials preserved their target. The foreign check used an existing foreign factory with the local fixture item, not an invented foreign order. A new fixture's unlock/replan required a reason and returned200; protected history returned200 with two revisions. No production, Quality, receipt, stock or demand execution followed.

Focused Node: **280/280 PASS**. Includes205-row metadata collection, changing/invalid pages, protected API failures, refresh lifecycle/abort/authorization behavior, work visibility/priority, calendar/Printing safety, Gantt, maintenance integration, supply and Warehouse presentation. TypeScript and the exact isolated optimized webpack build passed. Seven standalone PostgreSQL assertion groups passed:105 protected replacement creations with100+tail metadata, changing context detection, grants, actual authenticated owner read, foreign/restricted/missing-identity denials. These fixtures rolled back.

The additional older `sales-fulfillment.test.mjs` harness still reports29 PASS/12 FAIL. All12 reproduce against the pre-task `planning-drawer-app` source copied to the isolated `refresh-baseline` directory. Its expectations concern prior Warehouse layout/actions/state indexing. They were not removed, rewritten or counted as passing. This bounded task is not a full green-platform release certificate. Previous SQL duration/maintenance-capacity and lock-race results remain applicable because their writers and migrations were not changed; they were not relabelled as new runs.

Evidence is outside Git: `%TEMP%\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\refresh-planning` contains before/final traces, screenshots, owner Gantt/context checks and table digests. QA traces/history/SQL results remain under `%TEMP%\FactoryLean-Compensation-Fix-44983c02-abe2-414a-8608-f3e1dd7b74d9`. No passwords are recorded in this report or test artifacts.

## Complete task-specific source manifest

These are incremental changes over the dirty starting checkout, not a staging list for all existing work:

```text
HANDOFF.md
docs/planning-v3.md
docs/refresh-layout-stability.md
src/app/api/manufactured-output/route.ts
src/app/globals.css
src/features/MaterialFlow.tsx
src/features/ProductionPlanning.tsx
src/features/ProductionStartReadiness.tsx
src/features/PurchaseSupplier.tsx
src/features/Purchasing.tsx
src/features/SalesOrders.tsx
src/features/SourceStock.tsx
src/features/StoredUnfinishedInventory.tsx
src/features/Suppliers.tsx
src/features/Warehouse.tsx
src/features/WarehouseInventory.tsx
src/features/WarehousePurchase.tsx
src/features/useFulfillment.ts
src/features/usePlanningWork.ts
src/features/useSupply.ts
src/locales/ar.json
src/locales/en.json
src/utils/planning-work-reader.mjs
supabase/migrations/20261031120000_planning_work_metadata_v1.sql
tests/planning.test.mjs
tests/planning-work-reader.test.mjs
tests/planning-work-reader.sql
tests/planning-refresh-owner.mjs
tests/planning-refresh-qa.mjs
tests/planning-refresh-replan.mjs
tests/refresh-layout-observe.mjs
tests/refresh-lifecycle.test.mjs
```

The one justified forward migration is a **read-only metadata reader**, explained in `planning-v3.md`. No historical migration or business writer was edited. Both shipped gates remain FALSE; the pre-existing disposable private manufactured-output predicate remains unchanged. No hosted access, Git writes, deployment,3000/3001 change, permission or credential change occurred. The temporary QA app/adapter/database were stopped after verification, with fixtures/results retained. The main preview remains running for owner manual review; do not start another task automatically.


## 2 November 2026 — scheduling guidance and Requests
Sales guidance's factory:item:fetchedAt key cleared it each poll. Stable factory:item data now remains during revalidation; action freshness is separate. A transient availability warning also altered height; a persistent status area and range-based timeline action address that independently. Requests stays mounted after first visit, with filters/page/selection/scroll retained, visible Updating status and all actions disabled until current validation completes. No polling or global scroll workarounds. Evidence: [consolidated report](e2e-acceptance-consolidated-fixes.md).
