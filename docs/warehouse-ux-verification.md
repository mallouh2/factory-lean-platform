# Warehouse UX verification — 2026-10-04

## Authority and result

Continued the exact dirty 70-migration / 523-test state on development HEAD `f5896f1e354554641768ea35f6a78d42f1bde17e`. AGENTS.md, HANDOFF.md, current code and relevant installed Next guides read. No commit, push, branch change, main edit, DEV connection, account creation or grant change. Warehouse operations refinement; existing Products/Purchasing architecture retained. Model scope used the project's Sol High rigor for the database boundary; no delegated agent.

Warehouse staff need existing item identity, quantities, status and contextual action. Reused CSS/table/dialog/card and lazy-reader conventions. Reviewed official [MRPeasy item definitions](https://www.mrpeasy.com/resources/user-manual/stock/items/details/) for identity, units and stock-operation separation. No competitor formula or ERP scope adopted. This is parity, with no classification change.

## Final behavior

- Exactly 13 centered columns: Item, Code, Type, Unit, On Hand, Semi-Finished, In Production, Reserved, Available, Minimum, Maximum, Status, Action. Only visible Supply Source, Incoming and Projected removed. Backend data, source rules, projections and confirmation previews retained.
- Top-aligned, content-driven rows;14px, `.35rem` vertical / `.25rem` horizontal padding; wrapped values and whole-word header controls. No fixed/minimum row height.
- Bounded native x/y scroll region, maximum `min(60vh,640px,calc(100dvh - 320px))`; horizontal bar stays at its viewport bottom while reading any internal vertical position. Keyboard-focusable. Opaque sticky headers z3; pinned first header z4, first body cell z1; logical offsets support RTL. No duplicated scrollbar or polling.
- Normal desktop fits all columns. 940px minimum is a narrow-desktop fallback.390px keeps mobile cards, identity, important quantities, status, actions and column filtering.
- Top actions: Stock Settings / Receive Stock / Add Material / Inventory Movements / Create Purchase Request, under existing person grants. Header filters and one active Clear All remain. Top finished/unfinished tabs, duplicate Refresh and Configure/Adjust shortcuts removed. Opening Balance remains inside Receive Stock, Adjust Stock inside Settings, Unfinished Products expandable below. Warehouse Supplier Directory removed; authorized Purchasing retains it.
- Purchase dialog chooses existing definitions only: required Item/positive Quantity, Unit, optional Details, no Notes. Stock identity persists. Configured units are authoritative; ordinary unconfigured FG defaults Piece and permits Meter, compounds kg, materials their authoritative unit. Existing compound-only kg Product constraint preserved. Unknown stock must be configured to the matching unit before receipt. No free-text-to-stock conversion or new identity.
- Explicit manual purchase is separate from low-stock sourcing and never changes supply source or starts Production. Min/Max still requires human confirmation; BOTH requires sourcing choice. Good acknowledgment never adds a second FG credit; WIP lot totals and existing External Receipt remain authoritative.

Separate headings, direction and helper are visible before opening either list:

| Flow | English | Arabic |
| --- | --- | --- |
| Production → Warehouse | **Production Material Requests**; “Production → Warehouse · Issue inventory”; “Requests from Production for Warehouse to issue materials or items to the factory floor.” | **طلبات مواد من الإنتاج للمستودع**; “من الإنتاج إلى المستودع · صرف مخزون”; “طلبات يرسلها الإنتاج إلى المستودع لصرف مواد أو أصناف إلى أرضية المصنع.” |
| Warehouse → Purchasing | **Warehouse Purchase Requests**; “Warehouse → Purchasing · Buy inventory”; “Purchase requests created by Warehouse and sent to Purchasing to buy inventory.” | **طلبات شراء من المستودع إلى المشتريات**; “من المستودع إلى المشتريات · شراء مخزون”; “طلبات ينشئها المستودع ويرسلها إلى قسم المشتريات لشراء أصناف للمخزون.” |

## Database and checks

Two forward migrations were necessary: the old purchase command was restricted to low-stock/source recommendations and could not create a manual stock-linked purchase of any existing item with optional Details.

1. `20261004062012_warehouse_manual_inventory_purchase.sql`: narrow `purchase_inventory` command, optional specifications only for stock links, factory/Warehouse edit checks before retries, server actor/time, finite positive quantity, configured units, duplicate prevention, shared serialization/retry ledger/events. Existing actions still delegate to unchanged implementation. No table, grant, supplier or identity created.
2. `20261004063242_warehouse_purchase_unit_safety.sql`: forward correction to the newly added helper rejects kg for ordinary finished Products, preserving compound-only kg ownership. Found in final receipt-path inspection; first applied migration retained.

Local/TESTING **72/72**, every version/name. All **70** prior migration SHA256 hashes and both submitted SQL files unchanged. DEV deliberately not queried under the user's boundary; current DEV alignment is not claimed. Tracked whitespace check passes; pre-existing applied SQL trailing space at `20261003145325_sales_dates_inventory_sources.sql:123` preserved.

Final focused **160/160**, full Node **536/536** (13 additional tests, none skipped), TypeScript and isolated `.next-check` production build passed after final CSS changes. Build-generated next-env restored exactly (SHA256 `B8B3A344484B959AF5E4E3FC1A1609DAC3CB9ECE0CDEB6C145BE29BC4C491000`).

Eight final-schema TESTING rollback suites passed: new `warehouse-manual-purchase` **34 assertions**, `supply-flow` **99 assertions**, `warehouse-master`, `sales-stock-sources`, `sales-fulfillment`, `production-recording`, `unfinished-production`, `snapshot-authorization`. Permission fixtures expire the live platform account's temporary support scope within rollback transactions to isolate normal person grants. Older suite files stay unchanged; isolation was added to executed queries only. Fixtures roll back; no live scope/permissions changed.

React review: existing abort/stale-reader and retry hooks reused, dialog catalogue loads on mount, named fields, stable identity keys, scoped server mutations, no client actor/time, no new dependency or derived-state effect. Adapted shared visual-runtime tiny/clipped-text checks ran through the authorized browser; desktop returned zero findings. Contrast/wrapping/screenshots inspected visually. No broad accessibility certification claimed. Existing non-blocking advisors remain: intentional RPC-only tables ([0008](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)), existing authenticated SECURITY DEFINER RPCs ([0029](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)), [leaked-password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) disabled. New private helper access denied; publication hardening unchanged.

## Live TESTING A–H

Existing signed-in Nasser/Nova; no new person or grants.

| Scenario | Result |
| --- | --- |
| A desktop |1440×900, centered13 columns,14px, content-driven wrapping; region/content1268px, no x overflow; region bottom813px. |
| B long table | Internal scroll >1100px; opaque header stays at region top. |
| C horizontal |1024×768, region876/content940px, bar bottom735px in view. RTL lower-row proof: scrollTop1308.8, scrollLeft−40, header160.8/region160, bottom608px. |
| D actions | Five operational top actions; no Warehouse suppliers; two lists opened independently, separate Received/Requested states/actions. |
| E purchase | Existing raw resin, quantity1kg, empty Details, no Notes; Confirm creates linked **PR-0000057**, REQUESTED. Final unconfigured FG options Piece/Meter; configured raw/compound kg. |
| F directions | Separate headings/helpers/directions readable while collapsed; no combined tabs. |
| G Arabic | Natural operational headings/helpers, actions, centered table, sticky/keyboard horizontal RTL. |
| H mobile | Actual390×844 EN/AR; card345px; no page/card overflow. Semi20 opens PO-0000606 / lot5b511738, stored20/floor15 Piece, Printing remaining work, timestamp/history. |

PR-0000057 UUID `e083212f-5699-4635-bd0f-4105565afbf5`, material `3772ae40-58c2-49e1-9737-bb2811abd7aa`, quantity1kg, Details/Notes empty, Nasser server actor, Warehouse context. Retained for user acceptance; no live ordering or receipt. Resin On Hand53/Reserved5/Available48 unchanged. Full-table digests for production_lines, work_centers, production_orders, production_transfers, products, materials and inventory_transactions match before/after. Stock-credit/material-issue replay evidence is rollback SQL, not a new live production cycle.

Proof: `C:\Users\Temp\AppData\Local\Temp\factory-warehouse-ux-20261004` contains desktop EN/AR, narrow RTL, request-section, purchase and mobile screenshots. Website stays running http://localhost:3000/; viewport restored and Warehouse left open.

## All41 requested checks

| # | Concern | Executed evidence |
| --- | --- | --- |
|1|Centered headers/cells|CSS test + live A|
|2|No fixed excess row height|CSS contract + screenshots|
|3|Wrapped content growth|CSS contract + live A|
|4|Sticky header|CSS contract + B/C/G|
|5|Source hidden|Exact visible-column test|
|6|Incoming hidden|Exact visible-column test|
|7|Projected hidden|Exact visible-column test|
|8|All other columns retained|Exact13-column test + A|
|9|Sources functional|Source UI confirmation + Warehouse/Sales SQL|
|10|Top clutter removed|Top-actions/region tests|
|11|Column filters|Text/set/numeric component + SQL + live Item|
|12|At/Below Min|Status/authoritative SQL + live checkbox/apply|
|13|Refresh retains filters|Revision/snapshot component test + live Item/global Refresh|
|14|Stock Settings|EN/AR top-action tests + D|
|15|Receive Stock|EN/AR top-action + receipt tests|
|16|Add Material|EN/AR top-action tests|
|17|Inventory Movements|EN/AR top-action + movement regressions|
|18|Create Purchase Request|EN/AR top-action/form + E|
|19|Supplier Directory absent|Stock-Purchasing guard + live expanded lists|
|20|Existing inventory item|EN/AR form + all-stock-kind SQL + E|
|21|Quantity required|Form/contract + zero/NaN SQL|
|22|Piece default|Unconfigured form/SQL|
|23|Legitimate alternatives|Meter editable for unconfigured FG; raw/compound kg; invalid ordinary kg denied|
|24|Details optional|EN/AR form + empty SQL/live E|
|25|Notes absent|Single textarea + payload denial + E|
|26|Stock link retained|Narrow contract/SQL + retained PR57|
|27|Production section separate|EN/AR two-section/heading tests + F|
|28|Purchase section separate|EN/AR two-section/heading tests + F|
|29|Production→Warehouse clear|EN/AR helper/direction tests + F/G|
|30|Warehouse→Purchasing clear|EN/AR helper/direction tests + F/G|
|31|Independent states/actions|Supply UI/99 SQL + separately expanded lists|
|32|No double Good credit|Supply/Recording rollback regressions|
|33|Acknowledgment idempotency|Supply99 retries|
|34|Material Issue|Supply99 issue/stock/caller + existing live Received request inspected|
|35|Purchasing lifecycle|Supply99 + manual34 Ordered/Ready/Receive|
|36|Human Min/Max|Confirmation UI + SQL preview/source/caller|
|37|Correct Semi|Supply/WIP SQL + stored20/floor15/Printing detail|
|38|English|EN tests + actual desktop/mobile|
|39|Arabic/RTL|AR tests + desktop/mobile/scroll|
|40|Desktop responsive|1440 fit +1024 fallback/sticky/bar|
|41|390px mobile|Actual cards, no overflow, filter/action/dialog|

## Exact task delta and next step

Extended17 existing dirty files: `src/app/globals.css`, `src/app/api/data/route.ts`, `src/features/MaterialFlow.tsx`, `src/features/Purchasing.tsx`, `src/features/Warehouse.tsx`, `src/features/WarehouseInventory.tsx`, `src/features/WarehouseReceiving.tsx`, `src/locales/en.json`, `src/locales/ar.json`, `src/utils/supply-contract.mjs`, `src/utils/warehouse-inventory.mjs`, `tests/sales-fulfillment.test.mjs`, `tests/supply-contract.test.mjs`, `tests/supply-ui.test.mjs`, `tests/warehouse-master.test.mjs`, `HANDOFF.md`, `docs/PRODUCT_DIFFERENTIATORS.md`.

Added five: `src/features/WarehousePurchase.tsx`, both migrations named above, `tests/warehouse-manual-purchase.test.sql`, this document.22 total. Original57 dirty files saved before edits at `C:\Users\Temp\AppData\Local\Temp\factory-warehouse-ux-baseline-20261004-090447`; unrelated bytes preserved. HEAD/main/qa-baseline refs unchanged.

IMPLEMENTED and agent-verified. User manual acceptance/freeze and real-device touch remain NEEDS VERIFICATION. No pending UX/business choice. Prior snapshot/recipe bounds, partial issues/receipts, automatic consumption, accounting/MRP, calibration and publication hardening remain unchanged/deferred. Commit/push or DEV requires separate authorization.
