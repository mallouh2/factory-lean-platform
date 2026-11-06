# Warehouse V1 simplified stock UX — 22 October 2026

**LOCAL COMPLETE — owner visual approval pending.** Purchasing rollout has not started. No hosted access, deployment, activation, migration or Git write.

## Delivered

- Exactly seven default columns: Item / Code, Type, On Hand, Reserved, Available, Projected, Attention. Quantities retain their own unit. Zero-stock rows and distinct Finished Good, Raw Material, legacy Semi-Finished, manufactured intermediate, accessory and packaging types remain intact.
- Single-row selection, keyboard/Enter and double-click read-only Details, one selected-item Actions menu and no row Actions column. Existing replenishment, sourcing, receiving, configuration and stored-WIP actions retained. Global Warehouse tasks and operational sections preserved.
- Column choices and Restore defaults scoped by actor/factory/Warehouse table. Search, all existing filter types, sort and pagination remain server-backed. Existing Warehouse Excel/Print datasets and filters are unchanged; export keeps its established report columns independently of optional screen-column preferences.
- Compact read-only Details uses existing authorized readers for movement history, typed legacy-unit breakdown and current physical source availability/commitments. Secondary information loads on demand with errors/retry. UNATTRIBUTED stock stays distinct. This is not a new all-history genealogy report; source results are limited to what the existing reader exposes.
- Receiving/settings use one searchable entity field. Configured unit and receipt type remain explicit; optional receiving references/notes collapse. Opening balances and external receipts remain separate. Good acknowledgment still states that inventory was already credited; physical identification remains separate.
- Replenishment keeps authoritative current/projected/minimum/maximum values, quantity and deliberate sourcing/manual confirmation. Warehouse-only source allocation uses a searchable picker without changing validation, quantity strings, commands or retries. Shared Production/Correction source controls retain their default behavior.
- Approved Phase4A tokens, fonts, 44px buttons, 48px fields, modal language controls, RTL, mobile table cards and retained sticky form actions. Purchasing.tsx, PurchaseSupplier.tsx and Suppliers.tsx are untouched. WarehousePurchase changes concern only its existing Warehouse dialog wrapper.

## Quantity/authorization boundary

The table displays warehouse_inventory fields directly: recorded On Hand, existing Reserved commitments, the reader's Available balance and Projected future-stock calculation. No frontend stock formula, automatic reservation, selling-eligibility inference, aggregate across items/units, new writer or migration was introduced. Stored WIP and active production remain separate optional quantities. Unknown primary quantities remain unavailable, with a configuration warning.

Details uses warehouse_movements and finished_source_stock behind the existing authenticated APIs. Source On Hand/Reserved/Available use the reader's available/committed/selectable fields respectively; no source reservation is subtracted a second time. Read-only source help does not imply that selecting a label creates physical traceability.

## Verification actually performed

- **76/76 focused Node checks passed:** Warehouse UI/filters/sort/retries/permission boundary, new Details/lazy readers, column scopes, shared Details interactions, Warehouse export contracts and source conservation.
- **Three standalone localhost PostgreSQL rollback suites passed:** existing Warehouse catalogue/confirmation/projection/permission suite; existing source-stock allocation/reservation/dispatch/issue/conservation suite (24 checks); new warehouse-ux.sql acknowledgment/receipt/source-access checks (four groups). Existing Warehouse SQL expects a demo factory; its external local copy selects the known disposable synthetic factory instead. Assertions and production SQL are unchanged. Initial missing demo/ambiguous fixture references were resolved only in that external test copy.
- The new SQL verifies an authenticated owner's acknowledgment retry leaves stock/source data identical, source identification remains accessible afterward, zero-stock material retains kg, and repeated external receipt credits exactly once. All transactions and audit effects rolled back.
- **TypeScript and final isolated optimized production build passed.** Final source hashes match the build copy.
- **One lightweight browser pass:** normal synthetic local-owner sign-in; seven real columns/units; scoped preference survived reload and defaults restored; selection/double-click Details; real movement and source reads; receiving item search and configured unit; in-modal EN/AR and RTL390px with no horizontal document overflow; sticky Save inside viewport. No stock or business command was submitted. No browser console errors observed. Native Print/PDF/download and real-device acceptance were not repeated; export API/format contracts passed focused Node checks.
- An additional diagnostic run included untouched legacy Quality UI tests: two board assertions expect old default columns now hidden by the approved Quality UX. The affected Quality source/test files were not changed in this task. These stale expectations are documented separately, not reported as passing. No inventory/security defect was found in the affected Warehouse paths.

Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Warehouse-V1-7CyxkD`. SQL55480, temporary app4212 and adapter4294 stopped; data/results retained. Browser automation used the local protocol adapter and original SQL, not hosted Supabase certification.

## Task file manifest

Existing: HANDOFF.md; UX_POLISH_BACKLOG.md; src/features/Warehouse.tsx, WarehouseInventory.tsx, WarehouseReceiving.tsx, WarehouseOutputs.tsx, WarehousePurchase.tsx, SourceStock.tsx, MaterialFlow.tsx; src/locales/en.json and ar.json; tests/warehouse-master.test.mjs; tests/production-recording-full-app/backend.mjs (read-only RPC allowlist extension for the local adapter).

New: src/features/WarehouseItemDetails.tsx, WarehouseUi.tsx, warehouse-v1.css; src/utils/warehouse-view.mjs; tests/warehouse-view.test.mjs; tests/warehouse-ux.sql; this report.

## Preview and preservation

http://127.0.0.1:4207/ → Menu → Warehouse. The retained localhost-only app/adapter/database remain running on4207/4291/55476. Adapter reload may require normal local sign-in; existing credentials were not reset. Before/after hashes for retained entries/orders, stock/source/movements, reservations, material/purchase requests, WIP, acknowledgments, permissions, memberships and recording gate were identical.

Development HEAD bb0d20e5dd433b896dd319f56e75f0d9eb5d2862, main/index, unrelated work, all101 migration files, pending Export Reader and Design System preserved. Completed-work recording remains FALSE/schema0. Product differentiators reviewed: this scoped presentation change introduces no new competitive claim; document unchanged. Stop for visual approval; do not begin Purchasing.

## Final layout improvements — 22 October 2026

LOCAL COMPLETE; await owner visual approval of this follow-up. The previously reviewed seven-column stock table is preserved. Only its small per-header filter dropdown buttons were removed; sortable headings and the toolbar Filters dialog still expose every filter, including optional columns, before server pagination. No filter or export contract changed.

Stock Adjustment uses the approved Arabic help and «فرق المخزون (+/−)», with equivalent English instructions and «Stock adjustment (+/−)». The value remains a signed difference; reason, source allocation, protected deduction/availability validation and audit commands are unchanged.

### Existing-operation mapping

| Previous location/function | Current destination |
| --- | --- |
| Production material-request accordion | Production Material Requests tab; same MaterialFlow issuing/status/cancellation permissions and receipt workflow |
| Good acknowledgment and physical identification in combined Outputs | Production Receipts tab; same acknowledge_good and SourceIdentityDialog; already-credited warning remains |
| Warehouse purchase-request accordion | Purchase Requests tab; existing Purchasing stock mode and supplier/sourcing/history/actions unchanged |
| Outputs WIP receipt, origin, remaining work and movements | Stored WIP tab; same receive_wip dialog/command |
| UnfinishedProducts list, consumed history and authorized processing | Stored WIP → Lot details and further processing; original Orders permission retained; lazy open |
| Sales order/line dispatch cards and source allocation | Dispatch tab; original readiness/reservations, confirmations and pagination retained |
| Ordinary external/opening stock receipt, material definition and stock movement history | Existing main Warehouse toolbar controls |
| Stock configuration and signed adjustment | Existing Stock Settings / selected-item Actions |
| Supplier administration | Existing authorized Suppliers/Purchasing access; no new Warehouse supplier workflow |

One keyed panel is mounted at a time, so unrelated workflow selection/drafts do not carry between tabs. Tab buttons are type=button, with tablist/tab/tabpanel semantics, roving keyboard focus, Home/End and direction-aware arrows. Native task dialogs retain their modal protection. Good and WIP readers run only in their corresponding view; original product-scoped WIP Details/default combined callers remain compatible. No polling, new framework or decorative count. Empty-state padding is compact only inside Warehouse Operations.

### Follow-up verification

- 85/85 focused Node checks: retained 76 Warehouse/filter/export/Details/conservation checks plus nine operation-mapping, keyboard EN/AR, permission, lazy WIP, reader separation and signed-adjustment command tests. These are component/contract checks, not new hosted or SQL execution claims.
- TypeScript PASS. Final isolated optimized production build PASS with Webpack. Initial default Turbopack attempt rejected the external node_modules junction in the isolated copy; documented supported --webpack build succeeded without repository/config/dependency changes.
- One lightweight existing localhost browser smoke: five tabs and contextual empty states; real Good acknowledgment/identification buttons; WIP receipt/movements and retained lot-processing disclosure; toolbar Reserved filter and clear; exact Arabic/English adjustment wording; RTL arrow navigation and Home;390px EN/AR with no horizontal document overflow; desktop seven sortable headers with zero stock-header filter buttons. No stock/acknowledgment/dispatch command was submitted; no console errors observed. Export downloads/Print and prior SQL posting tests were not repeated because their contracts and writers are unchanged.
- Prior V1 standalone SQL evidence above remains applicable to untouched acknowledgment, receipt and source-stock operations; no database migrations or posting logic changed in this follow-up. Browser uses original SQL through a localhost-only test adapter, not hosted Supabase certification.

Follow-up files: src/features/Warehouse.tsx, WarehouseInventory.tsx, WarehouseOutputs.tsx, warehouse-v1.css; src/locales/en.json, ar.json; tests/warehouse-master.test.mjs, warehouse-operations.test.mjs; this report, HANDOFF.md and UX_POLISH_BACKLOG.md. Evidence: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Warehouse-Tabs-014bbc455748453481e854402d73d4ed. Preview remains http://127.0.0.1:4207/ → Warehouse. No Purchasing redesign or new business capability; PRODUCT_DIFFERENTIATORS reviewed and unchanged. Stop for visual approval.

## Navigation consolidation — 22 October 2026

LOCAL COMPLETE; owner visual approval pending. Inventory now has one heading and a compact toolbar: Receive Stock, Inventory Movements and Manage inventory. Manage inventory contains Add Material and Warehouse Settings for existing Warehouse editors. The redundant inventory-catalogue heading and general page description were removed. Table search/filters/columns/export and selected-row Actions stay distinct.

Generic Create Purchase Request moved from the Inventory toolbar to the Purchase Requests tab's existing list header. Purchasing accepts an optional header-action slot; ordinary Purchasing/My Requests behavior, creation permissions and writers are unchanged. This is not a Purchasing redesign. Existing selected-item replenishment and receiving shortcuts remain in row Actions because they carry an item/Min-Max/sourcing context; they are not repeated prominent global buttons. Material creation still creates only the existing supported material types; manufactured Products remain owned by Products.

The five operation tabs, Production Good acknowledgment and physical identification, WIP receipt/processing and Sales dispatch remain unchanged. External/opening receiving still posts through receive_warehouse_stock; Production Receipts still acknowledges already-credited Good. No posting, quantity, reservation, permission, audit, retry or database logic was changed.

Verified:90/90 focused Node checks (five new contextual-entry/permission/management/slot checks), TypeScript and isolated optimized Webpack production build PASS. One lightweight existing-session browser smoke opened and closed Add Material, Settings, Receive Stock, general movements and purchase creation without submitting; all five tabs checked, real Good/WIP controls retained, EN/AR and390px navigation with no document overflow, zero console warnings/errors. Original standalone conservation/acknowledgment evidence reused; no SQL write tests or exports/downloads repeated. Before/after local operational/permission/membership/activation digests identical. The brief referenced two owner screenshots, but only its text was attached; current local UI and explicit written organization were used.

Files: src/features/Warehouse.tsx, WarehouseReceiving.tsx, WarehouseInventory.tsx, Purchasing.tsx (header slot only), warehouse-v1.css; src/locales/en.json and ar.json; tests/warehouse-operations.test.mjs; this report and HANDOFF.md. Evidence: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Warehouse-Navigation-c5692b2f8b6a4f5ca45f316e72ff419c. Preview http://127.0.0.1:4207/. All101 migrations, Design System, index/refs and unrelated work preserved. No hosted access, activation, deployment or Git writes. Stop for visual approval.
