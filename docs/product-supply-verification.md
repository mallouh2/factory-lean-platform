# Products, Warehouse and Purchasing V1 verification

Verified 2026-10-04, Asia/Riyadh. Uncommitted on `development` at `f5896f1e354554641768ea35f6a78d42f1bde17e`. This extends the existing 67-migration / 458-test checkpoint and preserves its dirty work.

## Architecture and scope

The existing application uses Next.js App Router, authenticated command routes, person-level factory grants, protected Postgres RPCs, the factory fulfillment lock/retry ledger, typed FG balances/movements, raw inventory transactions/reservations, and durable unfinished lots. Purchasing/suppliers/BOM tables existed as unused foundation tables; they were reused. Existing Planning, execution, flow/transfer, Sales fulfillment, Maintenance and CSS/dialog architecture remain authoritative.

Products now defines finished manufactured identities and reusable kg compounds. Formula versions explicitly describe kg ingredients per 1 kg output. Finished Products reference a compound and an explicit kg weight per stock unit. Requirements are theoretical and never issue inventory automatically. Warehouse creates RAW_MATERIAL, ACCESSORY and PACKAGING only. The existing zero-stock legacy SEMI_FINISHED material has no durable WIP linkage; its identity and classification were preserved, not converted.

Warehouse shows one primary row per Product, with historical units in an inspectable breakdown. FG On Hand, stored WIP, active remaining, Reserved FG, Available, future Incoming and Projected stay separate. Projected preserves existing Sales/production deductions and adds Ordered/Ready purchase supply. Requested purchases suppress duplicates but do not count as Incoming. Unknown primary-unit amounts remain NULL; typed zero stock remains visible. Stored WIP is excluded from FG availability and is a location on the existing lot, not another physical ledger.

The approved Good decision is implemented: recording Good immediately credits FG; physical Warehouse acknowledgment records receipt without another credit. Stock purchases use the existing External Receipt command once. Direct purchases create no inventory movement and require receipt by the original requester. Material issues are explicit complete quantities, protecting reservations and recording the ledger, person and server time. Optional Product Item context is supported; no mandatory line or machine.

Purchasing V1 provides stock-linked and specified free-text requests, own requests, supplier selection, Requested → Under Review → Ordered → Ready for Receipt → Received, reasoned clarification/reply, rejection and cancellation, and append-only events. Suppliers have contacts, notes, active state and category links with one Primary and Alternatives. There are no prices, purchase orders, accounting, auto-approval, MRP or automatic recipe consumption.

## Database and preservation

Only TESTING `silmfbpjyepalnggwulp` was changed. Forward migrations:

- `20261003205735_product_inventory_purchasing_v1.sql`: domain ownership, formulas, kg workflow compatibility, quantity reader, material flow, suppliers, Purchasing and scoped commands/readers.
- `20261003211521_supply_command_contracts.sql`: action/payload contracts and protection of compounds with recipes/dependent Products.
- `20261003212840_warehouse_unconfigured_quantities.sql`: distinguish unknown primary units from zero and retain typed historical details.

Local/TESTING were compared before each apply at 67, 68 and 69, then verified at **70/70**, every version/name. All 67 previous migration SHA256 hashes are unchanged. All three new files match their exact submitted queries. CLI-generated filenames were aligned to the assigned TESTING versions without changing SQL. No applied SQL was edited. DEV's historical count is not a current verification; DEV was not contacted.

The original lines, work centers, transfers, Product Items and shifts match pre-live JSON digests by their original IDs. Existing Sales orders, planning guidance, delivery context, fulfillment reader and old migration files remain byte-identical to the pre-task dirty-file copies where this task did not require edits. Existing raw stock changed only through the documented live purchase receipt and material issue below. Git HEAD/main/qa-baseline refs remain unchanged. No commit, push, branch change, deletion or history rewrite.

## Validation

- Focused Supply API/UI, Warehouse and Recording Node suites: **108/108**.
- Full Node suite: **523/523**; no skipped tests.
- TypeScript: passed.
- Isolated `.next-check` production build: passed; generated `next-env.d.ts` restored to its exact pre-build bytes.
- Supply SQL: **99 assertions** passed with full transaction rollback, including actor spoofing, formula/unit safety, duplicate/retry receipts, raw/accessory/packaging/compound/WIP issues, location conservation, permissions, supplier relationships and direct receipt.
- Fifteen other rollback suites passed: Warehouse master; Sales fulfillment; Sales stock sources; Internal Production; Recording; unfinished production; Execution; Planning write guard; snapshot authorization; snapshot contract; production history; shift windows; lazy history; Maintenance; Downtime Capture. Together with Supply, **16 distinct rollback suites** passed. The final Warehouse/Supply suites were rerun after their final additional assertions.
- Tracked whitespace checks pass. Existing applied migration EOF/trailing-space findings remain preserved; they are not permission to reformat applied SQL.

## Live TESTING evidence

Existing Nasser Al Kuwari / Nova account only; no new accounts. Four new permission grants were added to this existing person for disposable TESTING verification: purchasing:view/create/edit and suppliers:edit. Other person grants were preserved; no migration automatically grants these permissions.

| Scenario | Verified result |
| --- | --- |
| A — Product/compound | Created `QA-SUP-COMPOUND-20261004`, formula V1: 0.8 kg PVC resin + 0.2 kg calcium carbonate per kg. Created `QA-SUP-PIPE-20261004`, 1.5 kg/piece, referencing it. Ten pieces calculate 15 kg compound, 12 kg resin and 3 kg calcium carbonate. No actual stock consumption. |
| B — one Product row | QA pipe shows Finished 60, stored Semi 20, In Production 40, Reserved 10, Available 50, future Incoming 50 and Projected 140 pieces. Exactly one identity row. The durable lot remains 35 total: 20 stored, 15 floor, remaining work Printing. Clicking Semi opens its lot/history. Good acknowledgment preserves FG 60. |
| C — combined filters | Raw Material + At/Below Minimum + Reserved positive returns the reserved QA resin. Refresh retains the filters. Its initial quantities were On Hand 20, Reserved 5, Projected 15, Min 20, Max 50. Column selectors work at 390px. |
| D — stock purchase | Open/Cancel creates no PR; final confirmation creates one `PR-0000019` for 35 kg, exactly Max 50 − Projected 15. No Production is created. |
| E — Maintenance request | `PR-0000020`: two 6205-2RS bearings, free text, required specification, Maintenance context, original requester retained, optional Notes left empty. |
| F — supplier/status | Created QA Supply Supplier 20261004 with contact, phone/email and Primary category. Explicitly selected it for both PRs; each traversed Requested → Under Review → Ordered → Ready for Receipt. Primary replacement/Alternative behavior also passes rollback SQL. |
| G — direct receipt | Original Nasser confirms PR-0000020. Received has actor/time and six events, no material/Product link or receipt movement. |
| H — stocked receipt | PR-0000019 becomes Received through one External Receipt of 35 kg. On Hand rises 20 → 55, Reserved remains 5. Exactly one receipt movement references this PR. |
| I — EN/AR/RTL | Live Warehouse and Purchasing inspected in both languages; statuses, units, contexts, column selectors, cards and dialogs are translated, Arabic is RTL. |
| J — 390px | Actual signed-in viewport 390×844; Warehouse/Purchasing cards and dialogs inspected. DOM checks found no page/card horizontal overflow. Viewport restored afterward. This is browser viewport testing, not a real-device touch certification. |
| Additional material flow | A 2 kg request against the reserved QA resin includes optional Product Item PO-0000607. Warehouse issues once, Production confirms Received, actor/time and movement remain inspectable. Ledger delta −2; final resin On Hand 53, Reserved 5, Available 48. |

Live QA remains in disposable TESTING for manual acceptance. New Product/compound, one isolated QA line/machine/capability, active 100-piece item, future unscheduled 50-piece item, 10-piece Sales reservation, one 60 Good / 5 Scrap / 35 WIP entry, stored-location receipt, Good acknowledgment, supplier/category, two received PRs and one received material request remain. The isolated job's initial planned timestamps were fixture setup; normal Start/Recording/receipt commands were used afterward. No live Planning acceptance is claimed. Existing production/machine/transfer/shift state was not altered.

Proof files are outside the repository at `C:\Users\Temp\AppData\Local\Temp\factory-domain-v1-20261004`: recipe.png, wip-detail.png, wip-detail-desktop.png, warehouse-mobile-en.png, warehouse-mobile-ar.png, purchasing-mobile-en.png, purchasing-mobile-ar.png and material-issue.png. The final desktop Semi quantity click also opens the correct lot, with Created 35 and Received into Warehouse 20 in history.

## Research and interface review

The personas are the Production requester, Warehouse issuer/receiver and Purchasing coordinator. The main decisions are what existing item is required, whether stock covers it, whether to produce or purchase, which supplier to select and who confirms delivery. Column filters are the only Warehouse filtering model; quantity detail and secondary workflows open on demand. Desktop tables scroll within their region; identity remains pinned while actions scroll to avoid obscuring quantity buttons. Mobile uses cards and column selectors. No new CSS framework or generic ERP workflow was introduced.

Official [MRPeasy Item Details](https://www.mrpeasy.com/resources/user-manual/stock/items/details/), [Autodesk material requests](https://help.fusionoperations.autodesk.com/en/articles/4004268-material-requests-in-the-back-office) and [actual consumptions/lot traceability](https://help.fusionoperations.autodesk.com/en/articles/435903-real-consumptions-and-lot-traceability) informed reusable item/formula ownership and explicit issue/receipt handoffs. These are workflow parity references, not evidence of uniqueness, automatic consumption or equivalent enterprise genealogy.

## Acceptance and limits

No business decision remains unresolved; the Good receipt decision was supplied by the user. User manual acceptance/freeze is still separate from automated/live verification. Existing Production Loss calibration and real-device acceptance remain outstanding. Recipes select at most 500 kg raw definitions; the Product master retains the existing snapshot cap, and optional context/person names use loaded configuration. Operational supply readers/selectors otherwise paginate at 50. Unknown historical units are inspectable without conversion. Partial issue/receipt, stock conversion of a free-text PR, supplier unlinking, MRP, costs/accounting and publication hardening are outside V1.

## Requested coverage map

The following maps the user's 87 concerns to executed coverage. S = Supply SQL; W = Warehouse SQL; UI = Supply component/API tests; WH = Warehouse component/API tests; R = relevant existing regression suite; Live = scenarios above. A mapping establishes the named behavior at these tested boundaries, not blanket certification of every production deployment.

| # | Required behavior | Executed evidence |
| --- | --- | --- |
| 1 | Manufactured Product can only be defined through the intended Product path. | S + UI; Live A |
| 2 | Warehouse does not create duplicate Finished Product identities. | S + UI; Live A |
| 3 | Manufactured intermediate/compound can be defined. | S + UI; Live A |
| 4 | Formula can be reused by multiple Products. | S + UI; Live A |
| 5 | Formula quantities preserve unit safety. | S + UI; Live A |
| 6 | Product unit-weight calculation produces correct theoretical compound quantity. | S + UI; Live A |
| 7 | Finished Product appears once with coherent quantities. | S + W + WH; Live B |
| 8 | Raw Material appears correctly. | S + W + WH; Live B |
| 9 | Accessory appears correctly. | S + W + WH; Live B |
| 10 | Zero stock remains visible. | S + W + WH; Live B |
| 11 | Semi-Finished is not treated as an arbitrary new Product type. | S + W + WH; Live B |
| 12 | Semi-Finished quantity derives from durable WIP. | S + W + WH; Live B |
| 13 | Clicking Semi-Finished exposes remaining-work breakdown. | S + W + WH; Live B |
| 14 | In Production remains separate. | S + W + WH; Live B |
| 15 | Finished remains separate. | S + W + WH; Live B |
| 16 | Reserved remains correct. | S + W + WH; Live B |
| 17 | quantity conservation holds. | S + W + WH; Live B |
| 18 | old cluttered filter controls are removed. | W + WH (S for Semi); Live C/I/J |
| 19 | text column filter works. | W + WH (S for Semi); Live C/I/J |
| 20 | Type filter works. | W + WH (S for Semi); Live C/I/J |
| 21 | Supply Source filter works. | W + WH (S for Semi); Live C/I/J |
| 22 | Semi-Finished > 0 works. | W + WH (S for Semi); Live C/I/J |
| 23 | Reserved > 0 works. | W + WH (S for Semi); Live C/I/J |
| 24 | numeric filters work. | W + WH (S for Semi); Live C/I/J |
| 25 | At/Below Minimum works. | W + WH (S for Semi); Live C/I/J |
| 26 | multiple-column filters use AND. | W + WH (S for Semi); Live C/I/J |
| 27 | same categorical column uses OR. | W + WH (S for Semi); Live C/I/J |
| 28 | Clear Filter works. | W + WH (S for Semi); Live C/I/J |
| 29 | Clear All works. | W + WH (S for Semi); Live C/I/J |
| 30 | sorting works with filters. | W + WH (S for Semi); Live C/I/J |
| 31 | background refresh preserves filters. | W + WH (S for Semi); Live C/I/J |
| 32 | MANUFACTURED requires human confirmation before Production request. | W + WH + S; Live D |
| 33 | EXTERNAL can create Purchase Request only after human confirmation. | W + WH + S; Live D |
| 34 | BOTH requires sourcing decision. | W + WH + S; Live D |
| 35 | Purchase option does not create Production. | W + WH + S; Live D |
| 36 | Production option does not create Purchase Request. | W + WH + S; Live D |
| 37 | duplicate Production replenishment remains blocked. | W + WH + S; Live D |
| 38 | duplicate Purchase replenishment remains blocked. | W + WH + S; Live D |
| 39 | Production can request an existing Raw Material. | S + UI; Live material flow |
| 40 | Production can request Accessory. | S + UI; Live material flow |
| 41 | Production can request Compound. | S + UI; Live material flow |
| 42 | Production can request stored Semi-Finished quantity. | S + UI; Live material flow |
| 43 | Warehouse issue decreases authoritative inventory. | S + UI; Live material flow |
| 44 | issue is traceable. | S + UI; Live material flow |
| 45 | unavailable quantity is surfaced correctly. | S + UI; Live material flow |
| 46 | Warehouse can create stock-linked Purchase Request after confirmation. | S + UI; Live D/E |
| 47 | suggested quantity uses Max - Projected where valid. | S + UI; Live D/E |
| 48 | Warehouse may adjust requested quantity. | S + UI; Live D/E |
| 49 | manual Production Purchase Request supports free text. | S + UI; Live D/E |
| 50 | manual Maintenance Purchase Request supports free text. | S + UI; Live D/E |
| 51 | manual Administration Purchase Request supports free text. | S + UI; Live D/E |
| 52 | Details field works. | S + UI; Live D/E |
| 53 | Notes are optional. | S + UI; Live D/E |
| 54 | requester identity is preserved. | S + UI; Live D/E |
| 55 | source department/context is preserved. | S + UI; Live D/E |
| 56 | requester sees My Purchase Requests. | S + UI; Live D/E |
| 57 | Requested → Under Review works. | S + UI; Live F/G/H |
| 58 | Under Review → Ordered works. | S + UI; Live F/G/H |
| 59 | Ordered → Ready for Receipt works. | S + UI; Live F/G/H |
| 60 | Ready for Receipt → Received works. | S + UI; Live F/G/H |
| 61 | Needs Clarification requires reason. | S + UI; Live F/G/H |
| 62 | Rejected requires reason. | S + UI; Live F/G/H |
| 63 | Cancelled preserves history. | S + UI; Live F/G/H |
| 64 | Supplier can be created. | S + UI; Live F |
| 65 | phone/email are preserved. | S + UI; Live F |
| 66 | main supplier relationship works. | S + UI; Live F |
| 67 | alternative supplier relationship works. | S + UI; Live F |
| 68 | supplier category association works. | S + UI; Live F |
| 69 | Purchasing can select supplier for request. | S + UI; Live F |
| 70 | stock-linked purchase uses External Receipt. | S + UI; Live G/H |
| 71 | stock quantity increases exactly once. | S + UI; Live G/H |
| 72 | purchase becomes Received after valid stock receipt. | S + UI; Live G/H |
| 73 | Maintenance direct purchase does not enter stock. | S + UI; Live G/H |
| 74 | Production direct purchase does not enter stock unless deliberately treated as stocked inventory. | S + UI; Live G/H |
| 75 | requester can confirm direct receipt. | S + UI; Live G/H |
| 76 | requester cannot manage all Purchasing requests without permission. | S + UI/API + R snapshot authorization |
| 77 | Purchasing authorized user sees/manage requests. | S + UI/API + R snapshot authorization |
| 78 | Supplier management respects permissions. | S + UI/API + R snapshot authorization |
| 79 | permissions remain per-person. | S + UI/API + R snapshot authorization |
| 80 | Sales reservations remain correct. | R Sales fulfillment / stock sources |
| 81 | SALES_PRODUCTION remains correct. | R Sales fulfillment / stock sources |
| 82 | Warehouse Dispatch remains correct. | R Sales fulfillment + W |
| 83 | Opening Balance remains correct. | W + R stock sources |
| 84 | Production receipt remains correct. | S + R Recording / Sales fulfillment |
| 85 | WIP remains correct. | S + R unfinished production |
| 86 | Maintenance remains correct. | R Maintenance |
| 87 | EN/AR/RTL remain correct. | UI + WH + Live I/J |

## Exact task file delta

This task affects 44 files: 15 saved dirty files were extended, 14 previously clean tracked files were modified, and 15 new files were added. The other 13 saved dirty files remain byte-identical. The full dirty checkout also includes the previous milestone.

- `AGENTS.md`
- `HANDOFF.md`
- `docs/PRODUCT_DIFFERENTIATORS.md`
- `src/app/api/data/route.ts`
- `src/app/globals.css`
- `src/components/FactoryApp.tsx`
- `src/features/CenterCapabilities.tsx`
- `src/features/CenterLossProfile.tsx`
- `src/features/CreateProductionOrder.tsx`
- `src/features/FactoryFloorV2.tsx`
- `src/features/LossImpactReview.tsx`
- `src/features/ProductionHistory.tsx`
- `src/features/ProductionOrdersV2.tsx`
- `src/features/ProductionPlanning.tsx`
- `src/features/ProductionRecording.tsx`
- `src/features/UnfinishedProducts.tsx`
- `src/features/Warehouse.tsx`
- `src/locales/ar.json`
- `src/locales/en.json`
- `src/utils/permission-preview.mjs`
- `src/utils/planning.mjs`
- `src/utils/production-history.mjs`
- `tests/production-recording.test.mjs`
- `docs/product-supply-verification.md`
- `src/app/api/supply/route.ts`
- `src/features/MaterialFlow.tsx`
- `src/features/Products.tsx`
- `src/features/Purchasing.tsx`
- `src/features/Suppliers.tsx`
- `src/features/WarehouseInventory.tsx`
- `src/features/WarehouseOutputs.tsx`
- `src/features/WarehouseReceiving.tsx`
- `src/features/useSupply.ts`
- `src/utils/supply-contract.mjs`
- `src/utils/warehouse-inventory.mjs`
- `supabase/migrations/20261003205735_product_inventory_purchasing_v1.sql`
- `supabase/migrations/20261003211521_supply_command_contracts.sql`
- `supabase/migrations/20261003212840_warehouse_unconfigured_quantities.sql`
- `tests/sales-stock-sources.test.sql`
- `tests/supply-contract.test.mjs`
- `tests/supply-flow.test.sql`
- `tests/supply-ui.test.mjs`
- `tests/warehouse-master.test.mjs`
- `tests/warehouse-master.test.sql`
