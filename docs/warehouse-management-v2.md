# Warehouse Inventory workspace — 2 November 2026

**LOCAL COMPLETE; owner visual review pending.** Daily receiving stays prominent;rare history,stock/master settings and warehouse definitions are grouped under Management & Records. Item Details has one3-card summary,actual reserved orders,recent5 movements,and Additional Inventory Details. One wide/mobile Stock Movements viewer serves both independent menu lookup and preselected item history. All existing buttons/functions remain available;external/opening receipt,Quality-approved production receiving,pooled provenance-only stock and protected writers are unchanged.

Current implementation,forecast SQL mapping,full task manifest and local evidence:[Inventory workspace report](warehouse-inventory-workspace-ux.md). Earlier milestones below remain historical evidence.

# Inventory clarity / Requests pagination follow-up — 1 November 2026

**LOCAL COMPLETE; owner visual approval pending.** The +95m receipt is correctly included in1077m physical stock;982m remains reserved and95m available. Inventory now emphasizes physical stock and explains actual reservations/order links/recent movements through protected read-only readers. Requests globally pages matching rows, clamps after lifecycle changes and shares its exact visible-page scope with Export/Print. No receipt/stock/reservation formula changed. Pooled provenance-only semantics and prior Warehouse V2 remain intact.

Exact source trace, forward reader migration,29-file task manifest,local SQL/concurrency/browser evidence and bounded-scan limitations: [Inventory and Requests report](warehouse-inventory-clarity-v2.md). Historical verification below remains evidence for the previous milestone, not a claim that the later files were tested then.

# Warehouse V2 — local verification, 1 November 2026

**COMPLETE for the approved receipt-provenance scope; owner visual approval pending.** Local PostgreSQL plus the existing local Auth/Data API fixture, not hosted Supabase acceptance. No activation or release approval is implied.

## Scope and operational model

Warehouse retains two operational tabs: Inventory and Warehouse Requests. Manage Warehouses is a secondary, permission-controlled dialog. The operator identifies the request, enters the quantity physically received, selects a compatible destination and confirms. Optional history stays under Details. Existing tokens, components, units, EN/AR and RTL are reused.

The owner explicitly selected **receipt warehouse identity only**. Inventory continues to pool by Product/unit or unfinished lot. A receipt's destination is receiving provenance, not proof of current stock remaining in that warehouse. No per-warehouse balance/filter is offered. Warehouse-specific balances, stock-out allocation and inter-warehouse transfers require a separate future phase. No existing stock is assigned to a default warehouse.

[MRPeasy's storage-location guidance](https://www.mrpeasy.com/de/ressourcen/benutzerhandbuch/stock/settings/locations/) distinguishes physical locations from separate-site inventory. The useful pattern is a defined destination and an explicit unknown historical location. This task deliberately does not adopt its multi-stock/site system or claim equivalent warehouse-level accounting.

## Request identities and colors

Actual shared queue/export identifiers remain unchanged:

| Identifier | Meaning | Type identity |
|---|---|---|
| `issue` | Material issue to Production | Blue |
| `unfinished` | Issue stored unfinished material | Teal |
| `receipt` | Receive inspected production | Green |
| `acknowledge` | Historical physical acknowledgement, already credited | Amber |
| `dispatch` | Customer dispatch | Purple |

No purchasing/transfer/return request kind was invented. Compact badges use existing semantic/chart tokens and neutral rows. Status badges are separate from type identity; held receipts use error semantics. Drawers reuse the appropriate identity. Existing search, type filters, columns, export and print scopes remain.

## Receiving

- Eligible finished production is first/default. If only unfinished is eligible, it is selected. A deliberate category choice survives polling and successful partial receipts; hidden category forms preserve independent drafts.
- One prominent **Available to Receive / الكمية المتاحة للاستلام** uses the protected reader's exact released-minus-received amount for that output/group. It is not customer demand, a production target or factory stock. Release and prior receipts are secondary Details.
- Quantity Received Now defaults to that amount. Edited quantities, warehouse, notes and physical confirmation are retained. Successful submission resets quantity suggestion/confirmation; the next receipt waits for the committed revision to be read back. No stock is assumed received without submission.
- Active factory warehouses are filtered by category. Finished production requires FINISHED; stored unfinished requires SEMI_FINISHED. Raw materials/supplies use RAW in the existing external/opening form; legacy SEMI_FINISHED material identities retain their existing category. Purchased finished stock uses FINISHED. There is no warehouse creation inside receiving.
- Explicit physical confirmation remains required for manufactured output. Partial receipt, holds, stale revisions and original-UUID recovery still use the protected transaction. Unfinished operations remain concise and category-specific.
- External/opening receiving uses a thin protected adapter around the existing `receive_warehouse_stock` ledger. It adds a destination, not Quality inspection, a different stock ledger or new demand rules. Existing automatic Purchasing receipt callers and legacy APIs remain unchanged; they must not be displayed as warehouse-attributed unless an actual destination was recorded.

## Database, permissions and historical compatibility

One new forward migration: **20261101104030_factory_warehouses_v1.sql**. It introduces `public.factory_warehouses` and private immutable command/receipt-destination associations. The historical 136 migration files are byte-identical; local source count is now137. No hosted migration history was queried or changed.

`factory_warehouses_read` permits factory-scoped Warehouse view or Settings edit. Administration requires effective factory-scoped Settings edit, using existing direct/package permission evaluation. Receipt writers retain Warehouse edit. All exposed RPCs are authenticated-only; tables have RLS and no direct client mutation grants. No job-title authorization, permission grant or global bypass was added.

Admin commands use actor/UUID/intent-bound immutable results and optimistic revisions. Names can change; used categories cannot. Archive preserves identities, snapshots and prior receipt recovery. Defaults are an explicit, idempotent command, not a global migration seed. Only the authorized owner demo factory was configured with:

| Class | English | Arabic |
|---|---|---|
| RAW | Raw Materials Warehouse | مستودع المواد الخام |
| FINISHED | Finished Goods Warehouse | مستودع المنتجات الجاهزة |
| SEMI_FINISHED | Semi-Finished / Unfinished Goods Warehouse | مستودع المنتجات نصف الجاهزة |

Manufactured receipt validation extends the current protected function in place; no callable old implementation is exposed. Warehouse factory/class/active state is checked inside its existing factory → fulfillment → source lock order. The stock movement and immutable destination commit together. UUID recovery precedes current destination eligibility so archiving cannot prevent recovery of an already committed result. Receipt snapshots preserve the name at receipt time.

Historical pooled stock and receipts remain unassigned. Existing unfinished-lot labels/classification are retained; selecting a warehouse for a new partial receipt does not rewrite previous lot/receipt evidence. Destination snapshots cannot establish present-day location after pooled issues. Existing Quality, source, allocation, demand, Good/Scrap/WIP and Sales reservation rules remain authoritative.

## Verified results

- **50 focused Node tests PASS:** receipt/category/decimal/request-tone tests, Warehouse Details, refresh lifecycle and existing Excel/Print contracts.
- **21 rollback PostgreSQL scenarios PASS:**17 manufactured/admin/security/compatibility and4 non-production receipt checks. Finished/unfinished partial receipts, original/historical UUID recovery, stale/excess/invalid warehouse, archive/class preservation, direct-table denial, actual foreign warehouse and restricted actors covered. External and opening receipts use the old ledger once and require no Quality decision.
- **Two actual overlapping PostgreSQL races PASS**, each with an observed lock wait: same UUID succeeds twice/credits once; distinct UUIDs against one revision permit one and reject the stale one. QA finished received3.5→3.6→3.7m, each increment exactly0.1m.
- Actual normal-login browser: finished1.5m receipt200, simulated lost response503, same UUID recovery200/one movement. A too-early unfinished attempt409 changed nothing; fresh read then unfinished0.1m200. Brief post-commit UI readiness now prevents that local stale window. No server guard was relaxed.
- Browser warehouse create, selection, used-category lock, rename and archive200. Immutable receipt snapshot retained the original name. Normal restricted login: admin write403, manufactured receipt403 and foreign warehouse read403; no unauthorized command/receipt change.
- Raw-material browser: existing authorized owner created one isolated QA material;2.5kg external receipt200, two concurrent original-UUID replays200/200, one2.5kg ledger movement and one destination. No owner operational record was written.
- Actual filtered Warehouse Requests Excel and Arabic Print requests200 on QA and owner, without invoking a native print dialog. Existing scopes/security unchanged. No unnecessary file downloads.
- TypeScript and optimized isolated production builds PASS for matching owner/QA bundles. No build writes into the running checkout.
- Finished and unfinished screenshots inspected at1440/768/390, EN and AR RTL; raw receipt390 EN/AR and final owner Requests/receipt inspected. No document overflow or confirmation/footer overlap. Semantic foregrounds use existing contrast-oriented tokens; this is focused visual QA, not a full accessibility certification.

## Refresh evidence

Settled pre-fix Inventory was already stable: outer180px, inner120px, document1313px through two real30s cycles. Requests retained its table but toggled a loading paragraph above it on every poll: document1108↔1142px. Browser anchoring held outer108px in this trace; it is a confirmed34px layout shift, not evidence of a measured outer-scroll jump on every browser. The same paragraph flickered behind an open receiving dialog. Separately, dispatch availability was cleared to an empty map while its unchanged context was refetched.

The queue now retains loaded state and dispatch values during same-context refresh. Factory/page changes still clear scoped results. There is no shared refresh rewrite, global scroll lock, scroll-back workaround, new timer or polling suppression.

Final actual30s polling: Inventory, Requests and Arabic390 receiving drawer each received at least two `/api/data` cycles. Outer positions, heights, inner table/drawer80px, page/table identity, selection, focus, quantity, warehouse and note remained stable; no loading flicker or page errors. A separate legitimate QA0.1m receipt appeared automatically: available90.3→90.2m while the local0.2m draft and note remained unchanged. Owner observation made no operational POSTs. See `refresh-layout-stability.md`.

## Preview and preservation

**http://127.0.0.1:4222/?view=warehouse** is running the matching `warehouse-v2-complete-app`, using the existing loopback database55496/Auth4304. Owner: `PlanningV3@local.invalid`. Unchanged credential file:

`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`

Separate QA uses55500/Auth4322/app4238. Evidence and screenshots remain outside Git under each runtime's `warehouse-v2` directory. Successful write fixtures/UUIDs must be inspected before rerunning; continuation scripts preserved completed writes rather than replaying new transactions blindly. Early harness failures involved selectors, stale-read timing and an insufficient lock-observation interval; final results above distinguish the actual transaction outcomes.

All118 original owner table digests remain unchanged. Only new warehouse definitions/default-command audit records were added to that owner factory. Existing credentials, memberships, grants, Production/Quality/Planning/stock/Sales and unrelated dirty work are preserved. No hosted access, deployment, Git writes, branch change,3000 operation or unrelated-preview restart. Export Reader and Design System bytes unchanged. Both shipped gates remain FALSE; the inherited disposable manufactured-output test predicate is unchanged.

## Complete incremental file manifest

```text
HANDOFF.md
docs/PRODUCT_DIFFERENTIATORS.md
docs/warehouse-management-v2.md
docs/warehouse-receipt-ux.md
docs/refresh-layout-stability.md
src/app/api/warehouses/route.ts
src/features/Warehouse.tsx
src/features/WarehouseDefinitions.tsx
src/features/WarehouseReceiving.tsx
src/features/WarehouseRequests.tsx
src/features/ManufacturedReceiving.tsx
src/features/warehouse-v1.css
src/utils/manufactured-receiving.mjs
src/utils/warehouse-request-rows.mjs
supabase/migrations/20261101104030_factory_warehouses_v1.sql
tests/warehouse-v2.test.mjs
tests/warehouse-v2/browser.mjs
tests/warehouse-v2/build.mjs
tests/warehouse-v2/concurrency.mjs
tests/warehouse-v2/local.mjs
tests/warehouse-v2/nonproduction.mjs
tests/warehouse-v2/observe.mjs
tests/warehouse-v2/preservation.mjs
tests/warehouse-v2/protected.mjs
tests/warehouse-v2/raw-browser.mjs
tests/warehouse-v2/refresh.mjs
tests/warehouse-v2/smoke.mjs
```

This is a task delta over the existing dirty checkout, not a staging authorization. No full-platform or hosted acceptance is claimed. Stop for owner visual review; do not begin another module or checkpoint.


## 2 November 2026 — Requests performance and completion labels
Requests retains its mounted state across Inventory switches, revalidates in the background and blocks stale actions/export. Inventory-only full data is not loaded in Requests. Forward reader20261102113000 reuses existing Warehouse-authorized Sales detail/order paging without Inventory/material projections; matching-result counts/pagination unchanged. Same80-request local response remains42855bytes/50rows, median API8885→2638ms in three samples per version. Receiving uses Close after completion/zero remaining and Cancel for an unsaved action; completed Sales shows Delivery confirmed with actual dispatched quantity. No stock ledger/dispatch rule change. See [consolidated report](e2e-acceptance-consolidated-fixes.md).


## 4 November 2026 — isolated 4222 material preparation rollout

The local material preparation, custody/reservation and departmental-update extension is implemented in the isolated4222 source only. Planning warning7h remains separate from preparation6h. Factory time is Asia/Qatar; exact Day/Week occupancy is distinct from short-job captions. Existing stock/Sales/Quality/production permissions and workflows remain protected. Read [the consolidated report](automatic-material-preparation-rollout.md) and [the physical-input/operator guide](production-material-inputs.md) for configuration, migrations, proof and manual acceptance limits. No hosted release or source promotion to3000 is claimed.
