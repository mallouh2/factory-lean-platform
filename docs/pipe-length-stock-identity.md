# Pipe length and shared order identity — Phase 4B.6.2

Status: implemented and verified in the isolated local candidate on 9 November 2026. Owner acceptance and hosted rollout remain pending. Evidence: D:/FactoryLean/Reports/Phase4B.6.2-20261109/REPORT.md.

## Physical business contract

A Sales line starts with the finished product's configured stock unit. A meter-based finished product with a positive configured kg/m weight also supports whole pipes/pieces. Piece mode requires a positive length per pipe, at most 1000 m and six decimal places; the displayed total is exact decimal multiplication. Internal manufactured formulations and Warehouse materials are excluded from Sales finished-product choices. Missing stock configuration remains an actionable validation error. Existing meter workflows remain supported.

A positive cut length resolves to one reusable Product identity keyed by factory, parent finished product and exact length. Its stock unit is piece. Ten 1 m pipes and five 2 m pipes have distinct product IDs even though both total 10 m. Production Requests/Orders, recording, Quality, receipts, reservations, source allocations and dispatch keep that identity through the existing protected contracts. There is no automatic cutting, splicing, repacking or cross-length substitution. Surplus retains its actual physical identity.

The derived Product snapshots the parent's descriptive configuration, recipe link and physical input routing at creation. Its kg/piece is kg/m × length; its capability rate is m/hour ÷ length, with the same setup time. Authorized parent capability updates regenerate inherited cut-length capabilities. The cut length and parent link are immutable, and integral finite count guards apply at the affected database boundaries. Parent and derived product configuration is not a general variant synchronization engine; later recipe, route or weight changes require deliberate review of affected physical specifications. Existing output provenance is not retroactively converted.

## Interface and authorization

MeasuredGanttCode compares real rendered text width with the actual bar interior using ResizeObserver. It never changes schedule geometry or minimum duration. A code is hidden if it cannot fit. Existing hover/focus details and the touch drawer remain available.

OrderIdentityProvider fetches one factory/user-scoped batch through order_identity_context and clears stale scope/permission data. Customer details require effective Sales view permission; actors without that permission receive no customer rows, and foreign-factory access is denied. OrderReference is shared across Planning/Floor context, Production lists/details/recording/history, Quality, Warehouse requests/receipts/movements/reservations/outputs and unfinished work. Missing or internal relationships do not invent a customer.

## Verification and limits

The real local Next application, synthetic local Auth/Data adapter and original protected PostgreSQL functions were exercised. Focused tests165/165, full Node1511/1511, TypeScript and isolated optimized webpack build passed. Twelve Gantt language/viewport/zoom combinations passed geometry and fit assertions; desktop hover/focus and mobile touch drawers were exercised in EN/AR. Sales units/count/length/total passed at1440px and390px in EN/AR. SQL smoke coverage includes explicit surplus feedstock, measured consumption, Quality without stock credit, physical receipt, correct reservations/dispatch, retry conservation and incompatible-length rejection, all inside a rollback transaction. Independent sessions verified real lock contention and one committed retry result.

No hosted Supabase, deployment, remote migration alignment or owner manual acceptance is certified. The preview's local material preparation runner invokes the existing private processor for the exact disposable factory only; it is not a hosted worker deployment.

## Product comparison

This is expected manufacturing/inventory parity. [Odoo documents separate inventory per variant](https://www.odoo.com/documentation/19.0/applications/sales/sales/products_prices/products/variants.html); [MRPeasy defines the item's stock/production unit explicitly](https://www.mrpeasy.com/resources/user-manual/stock/items/details/). Factory Lean uses a bounded cut-length identity within its existing Product model. No general attribute matrix, ERP expansion, measured savings or competitive advantage is claimed.
