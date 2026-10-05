# Lean Analysis UI acceptance fixes — 2026-10-05

Continued the exact uncommitted Lean V1 state on development, HEAD 60ee7d3911a32930afaf319f331761d711f65555. No commit/push, main change, DEV access, schema change, migration change or business-rule change. User manual freeze and real-device acceptance remain outstanding.

## Root cause and refresh behavior

FactoryApp refreshes the snapshot every 30 seconds. Lean previously moved its rolling period anchor whenever fetchedAt changed, producing a different request URL. useHistoryData treated every URL change as a different view and cleared the loaded rows. The resulting height collapse forced the browser's scroll position upward; detail evidence/disclosures disappeared for the same reason.

Lean list and detail now supply a stable working-view identity distinct from the advancing request window. Background refresh retains mounted content and equal response objects; genuine factory/filter/period/sort/page changes still mask old results immediately. Aborted requests cannot overwrite newer results. Legitimate freshness remains enabled. Query feedback has a reserved slot and mobile identities use durable problem keys. A failed background refresh reports its error while retaining the current view's last loaded evidence.

## Product and design decisions

Production engineers/managers need to identify which independent loss dimension warrants action and retain context while reviewing evidence. Production staff need an obvious internal Warehouse request workflow, including status and acknowledgment, within Production. Existing operational CSS, native controls, light surfaces, navy/teal typography and restrained Production semantic colors remain the foundation.

Applied UI/UX, frontend design, polish and color guidance. Reused the top-filter/date/machine workflow documented in [MachineMetrics Operations Production Runs](https://docs.machinemetrics.com/docs/product-guides/operations-production-runs-guide/). PRODUCT_DIFFERENTIATORS was reviewed; presentation/navigation changes do not change its classifications, so its pre-existing content is preserved. No new design system or dependency was introduced.

- One primary filter area includes period/custom dates, line, machine, Product, shift, Approved Cause, initiative status, sort/direction and clear/refresh. Its More filters disclosure retains minimum frequency, minimum Scrap, Monitor Only/Prioritized and recurrence. There are no column or duplicate mobile filters.
- Fourteen centered, wrapping columns, narrow frequency and wider subject/cause/Product/trend columns, compact evidence labels with retained explanations and subtle alternating white/slate rows. At 1440px the table's 1285px content fits its container. Narrow desktop uses a bounded scroll region; mobile uses cards.
- Independent cell attention: amber time, red Scrap, blue frequency. Time/frequency thresholds use the full currently filtered eligible population before pagination; highest fifth includes boundary ties. Unknown/zero, singleton and uniform populations do not invent relative outliers. Recurrence remains 2+ events and does not itself assign severity. Multiple metrics can receive attention; there is no score or row-level severity.
- Scrap attention reuses existing approved running/startup assessment. High-Scrap occurrences are already gated by SQL; linked Downtime declarations use frozen recording/standard snapshots and the same shared abnormalScrap helper, including earlier declarations consuming startup allowance. Existing measures/calculations and unknown data semantics remain intact.
- Overview, standalone Semi-Finished and top-level Material Requests are absent from operational navigation. Lines & Machines is the home. Old implementation modules/dispatch branches remain intact; internal navigation redirects hidden targets to visible destinations. Warehouse WIP/location/processing and all APIs remain available to their existing workflows.
- Production → Request Materials opens a full child screen. Create and detail are full working screens, with existing stock/lot selection, optional Product Item, status, issued quantity, actor/time history, movement trace and original-requester acknowledgment. Returning retains Production request filters. Selected detail follows refreshed Warehouse status. Warehouse's existing fulfillment dialog and Warehouse → Purchasing workflow remain separate.

## Backend boundary

Only GET /api/lean presentation changed: initiative-status filtering and independent attention metadata before final pagination. Additional linked-Scrap reads are batched, factory-scoped under the authenticated client's existing RLS, deterministically paginated and source-revision checked. No RPC, SQL, permission definition, migration, Edge Function, authoritative metric formula, inventory rule or persisted lifecycle changed. Commands/retry IDs/actors/times remain existing supply_command/lean_command behavior.

## Verification

- Full Node: 675/675 passed, zero failures/skips. New coverage tests full-population/pagination/ties, shared startup allowance, linked Scrap context, independent/coexisting cell attention, duplicate filters, retained asynchronous working views, stale-response/context isolation, hidden navigation, Production return context, full Material screens and refreshed issue status. Existing WIP, flow, Production, Warehouse, Purchasing and permission regressions pass.
- Focused affected Production/Supply/Lean UI run: 111/111. TypeScript noEmit/incremental false passed. Final isolated .next-check production build passed. Build-generated next-env/tsconfig restored to canonical Git content. git diff --check passed.
- TESTING WIP rollback SQL passed. Supply rollback SQL: original protected-owner fixture failed its attempt to remove Purchasing access because owner grants are retained. The same unmodified suite passed 99 assertions with existing non-owner Nasser substituted only in the in-memory transaction fixture. No test source or owner protection was changed; all fixture changes rolled back.
- Browser: desktop/mobile EN/AR/RTL, exactly one filter area, zero table-header controls, 14 centered headers, wrapping and alternating rows, independent Scrap/frequency and loss cells, visible mobile cards, no mobile page overflow. Shared visual-lint runtime was absent; native browser DOM checks and screenshot inspection checked fit, readable typography, labels and semantic contrast instead.
- Refresh: live 30-second snapshot updates preserved a selected problem, open manual comparison, scroll and sort; final non-default filter/sort/disclosure check recorded separately below.
- Live internal handoff: existing Nasser created QA request 18202b67-5817-4ed2-9b1c-b8a0e09705d4 for 1kg of existing isolated QA resin 3772ae40-58c2-49e1-9737-bb2811abd7aa. Warehouse issued it and original Production requester acknowledged it. Request is RECEIVED, movement be54edaa-b227-495a-a7ab-418f762cfcb3 occurs exactly once. Stock 54→53kg, Available49→48kg on issue; receipt acknowledgment leaves both unchanged. Genuine QA request/movement/Audit remain retained. No new account, package or package assignment was created.
- Local/TESTING migration count remains 79/79; all 79 starting migration SHA-256 hashes and all branch/remote refs match this task's baseline. Existing unrelated uncommitted files were preserved byte-for-byte.

Screenshot evidence is outside the repository at C:\Users\Temp\AppData\Local\Temp\factory-lean-ui-20261005. Final browser context: at 1280px, loaded rows5, minimum frequency1, frequency ascending and More filters open. Across 99 seconds and multiple live snapshot updates (13:02→13:03), scroll stayed244px, height1656px, all control values and the disclosure remained unchanged. Semantic text contrast: time6.07:1, Scrap6.80:1, frequency6.19:1. Temporary Lean:view grant was removed by its exact actor/time metadata; all92 original direct rows match the fresh task-baseline digest ff21dbb1961d3e649fce17fa1ed2911f, zero Lean grants and zero package assignments remain.

## Acceptance boundary

User manual acceptance/freeze and actual-device touch/browser coverage remain next. Viewport checks are not a physical-device test. No commit or push is authorized. Normal Lean access still requires legitimate direct grants/package assignment after QA access is removed.

## Files changed by this UI task

- HANDOFF.md
- docs/lean-analysis-v1-implementation.md
- docs/lean-analysis-ui-verification.md
- src/app/api/lean/route.ts
- src/app/globals.css
- src/components/FactoryApp.tsx
- src/features/LeanAnalysis.tsx
- src/features/LeanProblem.tsx
- src/features/MaterialFlow.tsx
- src/features/ProductionOrdersV2.tsx
- src/hooks/useHistoryData.ts
- src/locales/en.json
- src/locales/ar.json
- src/utils/lean-presentation.mjs
- tests/lean-presentation-api.test.mjs
- tests/lean-presentation.test.mjs
- tests/lean-ui.test.mjs
- tests/lazy-history.test.mjs
- tests/factory-navigation.test.mjs
- tests/supply-ui.test.mjs
- tests/production-orders-v2-render.test.mjs
