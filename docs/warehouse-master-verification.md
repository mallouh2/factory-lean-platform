# Warehouse master inventory verification — 2026-10-03

Implemented on development, HEAD f5896f1e354554641768ea35f6a78d42f1bde17e. Existing dirty Sales/source implementation preserved. No commit/push/main/DEV action.

## Architecture and quantity truth

The old Finished Goods reader started from finished_goods_balances, omitting Products without balance rows. The new reader starts from finished Product catalogue keys, then joins authoritative balances and batched projected supply. Existing materials are the raw/semi catalogue; their signed ledger and unreleased reservations remain separate from Finished Goods. Historical product/production units stay separate rows; no quantities are converted or aggregated across units. Temporary WIP remains on its existing page.

Finished Goods:
- Available = On Hand − Reserved.
- Incoming = remaining_quantity of planned/active matching product/unit Production.
- Projected = Available + Incoming − Sales incoming allocations − uncovered approved Sales demand.
- Uncovered demand per approved line = max(quantity − dispatched − FG reservation − incoming allocation, 0).
- At / Below Minimum = configured Min AND Projected <= Min.
- Suggested production = Max − Projected when Max exists. Without Max, the person must enter a finite positive quantity.

Materials:
- On Hand = SUM signed inventory_transactions.quantity.
- Reserved = SUM inventory_reservations.quantity where released_at IS NULL.
- Available/Projected = On Hand − Reserved.
- Incoming = NULL: this source model has no incoming-material supply records.

The old private.projected_finished delegates to the same batched projection used by inventory. A rollback comparison matched all existing products in meter/piece before application.

## Commands and boundaries

GET /api/fulfillment?mode=inventory authorizes warehouse:view, validates typed JSON filters and sorting, and calls warehouse_inventory. Filtering and sorting precede 50-row pagination. No inventory history was added to factory_snapshot. A fixed list of fourteen column keys controls filtering/sorting; units are a bounded catalogue facet.

confirm_warehouse_replenishment requires warehouse:edit independently of orders:create. It locks the existing factory structure/fulfillment boundary, checks exact stock unit/source/current projection, retries by the protected command ledger, reuses any planned/active same product/unit stock request and creates an unscheduled STOCK_REPLENISHMENT header/item only after confirmation. Source BOTH accepts deliberate produce or external. External records a choice and no Production. A new header-insert trigger requires protected confirmation proof; the old private Sales production helper rejects stock origins.

All old Min/Max hooks are retained as no-op compatibility calls. They no longer create, resize or cancel demand from configuration, Sales approval/change, stock adjustments, receipts, Dispatch or Production changes. Sales automatic shortage creation and allocation remain separate and passed existing regressions. Existing confirmed/planned requests are not cancelled or rebuilt.

## Verification results

| Check | Result |
| --- | --- |
| Focused Node: Warehouse, Sales, Planning, Internal Production, permission preview | 146/146 |
| New Warehouse Node component/API tests | 29/29 |
| Full Node | 458/458 |
| TypeScript | Passed |
| Isolated production build (.next-check) | Passed |
| Distinct TESTING rollback SQL suites | 15 passed |
| Local / TESTING migration version/name history | 67 / 67 aligned |
| All 66 prior migration hashes | Unchanged |
| New local migration SQL vs applied query | Exact match |
| Branch/HEAD/main/qa baseline | Unchanged |
| Build-generated next-env.d.ts | Restored |

SQL suites: warehouse-master, sales-fulfillment, sales-stock-sources, internal-production, production-recording, unfinished-production, production-execution, planning-order-write-guard, snapshot-authorization, snapshot-contract, production-history, shift-time-windows, lazy-history, maintenance and downtime-capture.

Security advisors have no ERROR findings. The intentionally authenticated permission-checked DEFINER APIs are flagged, including three new APIs; deny-policy ledger tables remain inaccessible. Existing leaked-password protection configuration remains a publication-stage concern. See the official [DEFINER advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) and [password protection documentation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). No broad authorization weakening or new user/grant was introduced.

## Requested 52-case coverage

| Requested cases | Evidence |
| --- | --- |
| 1–5: finished/raw/semi zero, explicit 0, no history prerequisite | warehouse-master SQL catalogue assertions, Node zero/NULL/type rendering, live initial QA catalogue |
| 6–8: three authoritative inventory types | warehouse-master SQL and EN/AR render tests; live raw/semi/finished rows |
| 9–13: above/equal/below/no Min/shared calculation | warehouse-master SQL equality, above, adjustment, NULL and shared projection assertions; pre-apply old-formula comparison |
| 14–18: action, no pre-confirm mutation, one confirmed request, Cancel, duplicate protection | Node dialog/cancel/double-submit/retry tests; SQL guarded creation/retry/reuse; live zero before/after Cancel then one after Confirm and reload |
| 19–21: external action/status/no Production | SQL source guard, Node source action, live external QA count 0 |
| 22–24: hybrid choice/internal final confirmation/external no Production | Node both choices; SQL both choices; live external first count 0 then Arabic internal final confirmation count 1 |
| 25–28: reservations/Available/Incoming/existing demand | SQL Sales reservation and projected-stock assertions; live QA 20/5/15 kg and confirmed incoming 50 m |
| 29–31: name/type/source filters | SQL text bilingual and categorical predicates; API typed query; live raw filter |
| 32–35: On Hand/Reserved/Available/Incoming filters | SQL equality, positive, greater, range predicates; Node numeric range query |
| 36–38: low/zero/combined AND | SQL minimum status/AND; Node quick filters; live three-way combination |
| 39–41: clear one/all/refresh preservation | Node handlers and changed fetchedAt; live three filters survive Warehouse refresh |
| 42–44: viewer denied/editor allowed/person grants | SQL removal of actual Warehouse edit and orders:create; API denied/allowed; Node viewer actions absent |
| 45: Sales production unchanged | Updated Sales A–J only adds explicit Warehouse confirmation to its stock fixture; existing source/shortage/allocation tests passed |
| 46–47: Opening/External receipts | sales-stock-sources SQL; existing receiving command/render tests; live QA reserved resin Opening receipt |
| 48–49: Good completion/Dispatch | sales-fulfillment, production-recording and unfinished SQL suites passed; no new live completion/dispatch claimed |
| 50: unit safety | source suite and new confirmation wrong-unit rejection; historical-unit configuration regression |
| 51–52: EN/AR/RTL | Node labels/dir checks; live Arabic table/filter/confirmation; 390px actual-component card/filter/confirmation screenshots |

## Live TESTING evidence and limits

Existing Nasser Al Kuwari / Nova account. QA catalogue was prepared through existing permission-checked RPCs using Supabase SQL; UI decisions and filters used the signed-in browser. No new accounts.

- Initial QA MANUFACTURED/EXTERNAL/BOTH products plus raw/semi materials all appeared at zero with no movements/requests.
- Manufactured preview left zero requests; Cancel left zero. Browser confirmation created PO-0000546, header 5483262e-beec-4450-b1e4-9391427462f7, item 2849c1aa-8b29-4ea9-bd75-e52d1410aba9, 50 meters, low priority, unscheduled.
- Reload showed Incoming 50, Projected 50, Above Minimum and already requested; Create was absent. One request remained.
- EXTERNAL stayed at zero Production requests.
- BOTH external choice recorded one decision and zero Production. Later Arabic Produce Internally opened a second confirmation and still had zero requests; final Confirm created one 50-meter stock request.
- QA reserved resin has a 20 kg opening receipt and a SQL-assisted 5 kg material reservation against the QA stock job. The browser Raw Material + At/Below Min + Has Reservations filter returned only this row, showing 20 On Hand / 5 Reserved / 15 Available/Projected / Min 20. Refresh retained all three filters.
- EN/AR desktop table and Arabic filter/confirmation checked. Read-only actual-component previews at 390px showed cards, warnings, quantities, actions, filters and confirmation in EN/RTL. The full app has X-Frame-Options DENY; it was not embedded or weakened. Physical-device/live mobile touch interaction remains unverified.
- Screenshots outside Git: C:\Users\Temp\AppData\Local\Temp\factory-warehouse-master-20261003. Temporary public preview removed.

Retained QA: Products QA-WHM-MANUFACTURED/EXTERNAL/BOTH-20261003; materials QA-WHM-RAW/SEMI/RESERVED-20261003; two explicit stock requests; one hybrid external decision; one raw Opening receipt/reservation. Previous QA and existing PVC 25 stock request remain. No scheduling/physical machine/transfer change.

## Files changed for this task

1. AGENTS.md — durable confirmed-replenishment rule.
2. HANDOFF.md — current checkpoint and evidence.
3. docs/PRODUCT_DIFFERENTIATORS.md — manual inventory review remains parity; sources S25/S26.
4. docs/warehouse-master-verification.md — this evidence record.
5. src/app/api/data/route.ts — Warehouse commands/errors.
6. src/app/api/fulfillment/route.ts — validated inventory reader.
7. src/app/globals.css — scoped table/mobile/status/filter styles.
8. src/features/Warehouse.tsx — master view, receiving/configuration integration.
9. src/features/WarehouseReceiving.tsx — optional raw section and row-directed receipt.
10. src/features/WarehouseInventory.tsx — master table/cards, filters, sorting, confirmation.
11. src/features/useFulfillment.ts — extra bounded reader parameters.
12. src/utils/warehouse-inventory.mjs — shared column/filter contract.
13. src/locales/en.json — English labels.
14. src/locales/ar.json — Arabic labels.
15. tests/sales-fulfillment.test.mjs — derived Warehouse states and historical configuration regression.
16. tests/sales-fulfillment.test.sql — stock fixture now explicitly confirmed.
17. tests/warehouse-master.test.mjs — 29 focused component/API tests.
18. tests/warehouse-master.test.sql — catalogue/stock/confirmation/filter/permission regressions.
19. supabase/migrations/20261003181748_warehouse_master_confirmation.sql — forward schema/reader/command/guard changes.

Unrelated existing SalesOrders, ProductionPlanning, DeliveryContext, SalesPlanningGuidance and source SQL tests are byte-identical to the start-of-task backup. All prior applied SQL is unchanged. Existing applied whitespace exception (20261003145325 line 123) is preserved.

## Remaining decisions and deferred scope

No business decision blocks this implementation. Current material entities have no internal-manufacturing source/link; future internally manufactured raw/semi stock needs an explicit model/workflow decision. Incoming material supply, standalone large-catalogue receipt/history selectors, material correction/issue flows, Purchasing/BOM/accounting and broad publication hardening remain deferred.

A configured Max equal to Min at exact equality yields a suggested quantity of zero, so no invalid zero-quantity request is created. Stock units and legacy rows never convert automatically. User manual acceptance/freeze and physical-device verification remain outstanding; commit/push need separate authorization.
