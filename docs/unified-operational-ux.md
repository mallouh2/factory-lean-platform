# Unified operational UX — 28 October 2026

**Navigation superseded:** the owner rejected this report's grouped sidebar. The later [Sidebar navigation correction](sidebar-navigation.md) replaces its navigation structure/visuals and records current local verification. All business-workflow acceptance limits below remain unchanged.

**Status: PARTIAL — local implementation verified; complete fresh operational acceptance remains blocked. Stop for owner review.**

This continues the existing dirty `development` checkout at `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`. It does not certify hosted acceptance or authorize activation/checkpointing. Original review fixtures were not rewritten to manufacture success.

## Phase results

| Area | Result | Implemented / verified / remaining |
| --- | --- | --- |
| Rejected production and measured Scrap KG | Local PASS | EN/AR Rejected Production; exact finished = total − rejected − unfinished; required actual measured KG, separately labelled theoretical estimate. Existing immutable finding is the evidence source; latest finding contributes once to Quality totals, independently of Production Scrap. SQL: 909 total / 9 rejected / 10 unfinished = 890 finished, 4.8 actual KG; 0.2 Production Scrap remains separate. |
| Inspection table / group notes | Local PASS | Pending-only table, search, date, product, quantity and status; select a row to inspect. Notes beside the relevant operations, separate rejection/correction explanation. General history remains in Production History. Final browser draft was cancelled; original owner's pending record remains unchanged. |
| Production notifications | Local PASS | Material changes appear automatically on Factory Floor; original/latest quantities and groups, reason and correct Details reference. Existing matching result produces no new material-change notice. No permission or acknowledgement rule changed. |
| Warehouse two-view structure | Local PASS | Inventory and Warehouse Requests are the two primary views. Inventory distinguishes supplies, finished products and stored unfinished stock. Protected stored-WIP reader reports physical, reserved, available and held quantities separately. |
| Warehouse actions / partial dispatch | PARTIAL acceptance | Unified request rows link normal material issue, source-identified unfinished issue, released production receiving and the existing exact-quantity Sales dispatch. Existing Purchasing/nonproduction receipt/settings remain under contextual actions. Existing pooled partial dispatch remains protected; new fixture dispatched 40/100 successfully. Remaining 60 could not reach recording/receipt; no complete new shipment claim. |
| Planning line selector / priority | PARTIAL diagnosis | Missing optional capable-line metadata can no longer throw an undefined `.includes` error. The owner's precise reported selector failure was not reproduced against a known failing item, so its root cause is unconfirmed. Protected new demand-linked COMPLETE/REPLACE work defaults HIGH only when a real received-finished shortage exists; STOCK remains normal. Work type uses the authoritative decision. |
| Scheduling / overdue replanning | Local PASS, prior evidence reused | Existing normal scheduling and protected reasoned never-started/unlocked overdue replanning preserved. New native mouse drag reached a trusted drop, HTTP 200 and persisted a legitimate schedule without changing actual execution. No queue bypass, timestamp rewriting or cascading reschedule. Prior overdue command/concurrency evidence remains applicable; not re-executed. |
| Sidebar / motion | Local PASS | Task groups, scoped child links, icons, keyboard focus, selected state, reduced-motion behavior; RTL mobile drawer specificity fixed. Suppliers under Purchasing; Downtime under Lean; Reports removed from prominent navigation. No permissions hidden as a substitute for authorization. |
| History / Sales regressions | Local PASS, bounded | Contextual History Back verified. Existing Save Draft / Confirm Order and partial fulfillment contracts retained and covered by affected tests. New Sales confirmation and 40-unit dispatch returned HTTP 200. No redistribution or full recovery/fulfillment claim. |
| Complete integrated testing | BLOCKED | Fresh order → production → Quality → receiving → remaining shipment and completion/replacement chains were not completed. Managed shift admission rejected recording eligibility; see exact fixture below. No fake output, stock or successful acceptance. |

## Accounting and authorization

- Measured rejection weight is stored in the existing immutable Quality event, not a second Scrap ledger. Original Production Good/Scrap evidence is not overwritten. A revised finding replaces the current evidence calculation; revisions are not summed. Approved Lean/Loss snapshots are not rewritten.
- UUID receipts, source locks, revision checks, factory scope, effective direct/package permissions and protected reconciliation remain in the existing command. Actual KG is mandatory for positive rejected production and cannot be silently inferred from meters/pieces. Zero rejection cannot carry positive rejected KG.
- Quality determination does not create a receipt or finished stock credit. Released production still requires its existing protected physical receiving workflow. Purchased supplies/opening receipts are unchanged.
- Stored unfinished stock is not finished stock. Current demand allocations reserve it; a Quality hold makes eligible availability zero without hiding or erasing physical quantity. No aggregate of incompatible units or remaining-work groups.
- Request availability uses protected Sales pool context; it is not copied from reservation quantity. Unknown material availability is explicitly `—` and checked by the command. No automatic source selection claims physical traceability.
- New priority affects only newly created qualifying work. It does not reschedule jobs, rewrite existing priorities or reduce original finished demand because recovery ran.

## Forward migrations

122 local files, all 118 pre-task migration hashes unchanged. Applied only to verified disposable loopback databases 55498 and 55496; no hosted history/alignment claim.

1. `supabase/migrations/20261028073043_manufactured_quality_measured_mass_v1.sql`: measured rejection evidence and latest-mass helper in existing protected finding command. Its optional reader-metadata string replacement did not match the existing alias; no reader metadata change is claimed. UI uses the already-authoritative source recording timestamp.
2. `supabase/migrations/20261028073555_completion_shortage_default_priority_v1.sql`: shortage-bound new-work priority trigger.
3. `supabase/migrations/20261028074043_manufactured_quality_mass_projection_v1.sql`: existing Quality projection adds latest manufactured rejection KG separately from Production Scrap.
4. `supabase/migrations/20261028075249_warehouse_stored_unfinished_reader_v1.sql`: protected factory-scoped stored-WIP read, authenticated Warehouse view only; no writes or exposed private tables.

## Verification

Current evidence, not a full-platform green-suite claim:

- Focused Node: **166/166 PASS**; separate navigation/drill-through/history assertions **30/30 PASS**.
- SQL harness: prior relevant base 38 positive / 19 expected rejection assertions; final **49 positive / 24 expected rejection assertions**, including **11 new positives and 5 new expected rejections**. New cases cover measured KG, coexistence with Production Scrap, unchanged gross/stock, replay, missing/negative evidence, scope/authorization, demand priority, WIP reservation and holds.
- Two new actual Quality concurrency groups PASS with observed lock waits: same UUID gives one event and replay; different UUID with stale revision rejects. Existing seven pooled-dispatch/overdue lock groups are reused previous evidence, not new runs.
- Restricted existing viewer normal login: Quality GET **403**, Quality POST **403**, stored-WIP GET **403**, no data disclosed, target event count unchanged. Accounts, packages and grants were not changed; owner retains 102 effective permissions.
- Final TypeScript and isolated optimized Webpack production build PASS. Final served source matches the repository source.
- Final owner browser PASS: normal login; pending table/date; 909/9/10→890 draft with 4.8 KG and group note cancelled; two Warehouse views; real stored-WIP reader; automatic material notice/correct Details; matching-result absence; Planning and History Back; Arabic 390px / RTL drawer / keyboard Escape / reduced motion. No page exceptions; final screenshots visually inspected.
- Warehouse stock Excel **200**, valid XLSX response; Print **200**, HTML response. Responses inspected in memory without repeating native Print dialogs or unnecessary downloads.
- Real native pointer drag PASS: request `63a8a158-21a4-4554-a942-0411771c0fa2`, item `a95fc0bb-cc3a-415d-828b-3ff7d115588b`, line `7f66a3fb-2c0b-442a-99c9-52926a10df5b` (Same-shift reporting QA), planned **2026-10-28 19:00–19:01 UTC**, actual start null. Trusted drag/drop events, HTTP 200 and persisted schedule inspected. Successful schedule was not resubmitted.
- Broader affected historical harness: **213/232 PASS, 19 FAIL**. Eight failures reproduce the pre-task stale Warehouse baseline (EXTERNAL/BOTH replenishment placement, EN/AR movement-history location, receipt selectors, old top actions). Eleven additionally assert the superseded five-tab/child-dispatch structure. New five semantic Warehouse workspace tests plus actual browser checks cover the approved replacement, but the old tests remain unchanged and the suite is not represented as green.

Standalone PostgreSQL/local Auth evidence does not prove Supabase-specific hosted behavior. No unrelated Quality/Warehouse/platform audit was run.

## Fresh acceptance fixture — preserved, do not blindly retry

Only a separate new local product/cell/order was used; original PO31/32/34 review records, existing shifts, queues and commitments were not altered. Protected authenticated APIs created ordinary fixture configuration and transactions. One new routing-step configuration used a documented local-only fixture insertion because no public routing editor exists; no production quantity, audit, stock balance, permission or receipt was inserted through SQL.

| Record | Value |
| --- | --- |
| Product | Unified acceptance pipe / UX-UNIFIED, meter, 0.5 KG per meter; `b192886f-ec9e-49e4-a184-f5067f6bef39` |
| Line | Unified acceptance cell / UX-CELL; `205870cd-8049-4a09-8642-9e72cc747fda` |
| Machine | Acceptance processing unit / UX-UNIT; `97bb6226-231b-43df-aa68-5ac963261881`; configured capability 6000 meter/hour, only this new machine set RUNNING |
| Sales | SO-0000004, approved; `a3895098-5518-40d9-8ec8-99b186bff019`; line `99ddcb83-29ee-4104-b82e-48e552957f38` |
| Production | PO-0000048; `1391f46a-fcad-44a2-b321-28f90fb2737c`; completed normally **08:06:13.854156–08:06:14.234372 UTC** |
| Shift fixture | `07ea081f-6e46-4c8f-99c4-9844291650ec`; legacy times do not override managed occurrence admission |
| Dispatch | 40 meter, HTTP 200; `714f870a-d18e-4f80-918f-e2a41eab8670` |

Before opening/confirmation: product stock 0, no fixture Sales commitments. Opening 40 → confirmation reserves 40 and links incoming 60 → dispatch 40 leaves stock 0, reserved stock 0, dispatched 40, outstanding 60/incoming commitment 60. Production job has **zero recording entries**, Good 0, Scrap 0, WIP 0, no manufactured receipt or Quality decision. No inventory conservation failure was observed.

At **08:09:40 UTC**, protected M1 returned `available:false`, `reason:OCCURRENCE_NOT_READY`, occurrence null, first verified managed start **08:56:52.779517 UTC**, late recording unavailable. The test harness should have checked authoritative shift readiness before starting/finishing the new job. It did not; this is a test-preparation error, not evidence of a broken stock writer. The affected workflow stopped before recording. Nothing was reopened, backdated, force-recorded or credited.

A later current shift cannot make that pre-admission completed execution eligible. Any supported disposition of this preserved fixture requires a separately reviewed action; do not blindly rerun the journal or alter timestamps. Full fresh A/B/C/D/E recovery/receipt/shipment acceptance remains outstanding, not PASS.

## Remaining limitations and owner review

- Exact reported Planning selector failure needs its affected item and original error. Defensive null handling and successful normal/native scheduling do not prove that particular incident is fixed.
- Requests are paged within each source department, clearly labelled, rather than pretending to be a globally sorted/paginated queue. Source-specific protected actions still revalidate current state.
- Product-material issue needing physical source identity opens the existing specialist workflow; no auto-selection. Unfinished completion-input cancellation/rejection remains a protected Planning decision, not a Warehouse shortcut.
- Existing stock/history exports and Print remain available. No new combined Requests or stored-WIP bulk export dataset was added.
- Local fixture operation names can repeat (two existing Extrusion identities); display does not merge their distinct UUIDs. Owner should review fixture naming, not assume the choices are identical operations.
- Existing same-open-shift recording implementation and affected tests are preserved. No newly completed valid managed-occurrence recording was executed in this task; do not claim that blocked fixture proved it.
- Final visual approval and complete fresh operational acceptance remain pending. No measured training reduction or customer readiness is asserted.

Preview: **http://127.0.0.1:4222/**, current `unified-ux-app` optimized build. Existing owner: `PlanningV3@local.invalid`. Verified local-only credential file (unchanged):

`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`

Owner review: sign in normally; Quality → select pending row → Modify inspection; check separate rejected quantity, measured KG, group notes and automatic finished result (Close cancels). Warehouse → Inventory type / Warehouse Requests → inspect a row before any physical action. Production → Factory Floor → Quality updates → Details. Planning → inspect work type/priority and normal available-line selection; History → Back. Repeat in Arabic at narrow width. Do not submit fabricated measurements or repeat already completed fixture transactions.

## Exact task change manifest

Existing source files changed:

```text
src/app/api/fulfillment/route.ts
src/app/globals.css
src/components/FactoryApp.tsx
src/features/ManufacturedOutput.tsx
src/features/ManufacturedReceiving.tsx
src/features/ProductionPlanning.tsx
src/features/Warehouse.tsx
src/features/WarehouseInventory.tsx
```

New source:

```text
src/features/StoredUnfinishedInventory.tsx
src/features/WarehouseRequests.tsx
```

Four migrations are listed above. New test scripts:

```text
tests/unified-ux/browser.mjs
tests/unified-ux/denials.mjs
tests/unified-ux/inspection.test.mjs
tests/unified-ux/mass-coexist.sql
tests/unified-ux/native-drag.mjs
tests/unified-ux/operational.mjs
tests/unified-ux/priority.sql
tests/unified-ux/quality-concurrency.mjs
tests/unified-ux/quality-mass.sql
tests/unified-ux/warehouse-workspace.test.mjs
tests/unified-ux/wip-hold.sql
tests/unified-ux/wip-reader.sql
```

Documentation: this report and a dated `HANDOFF.md` entry only. Product differentiators reviewed; this task adds no substantiated commercial differentiation beyond the existing dated parity discussion. Workflow references: [MRPeasy shipments](https://www.mrpeasy.com/resources/user-manual/stock/shipment/) and [Tulip corrections/review](https://support.tulip.co/docs/process-data-corrections-and-review). These informed task/state clarity and immutable-evidence presentation, not new business rules.

Evidence outside Git: preview root `unified-ux` contains final Node/build/TypeScript logs, browser/denials/native-drag/operational JSON, screenshots and before/final preservation manifests. Regression root is `C:\Users\Temp\AppData\Local\Temp\FactoryLean-OperationalUX-SQL-d7232dad5d0d4b6689e384197aadc0ab`; scripts/results/data retained, server stopped after verification. Preview database 127.0.0.1:55496, adapter 4304 and application 4222 stay running. Credentials and generated evidence were not added to the repository.

## Safety and checkpoint boundary

Shipped manufactured-output capability remains **FALSE**; shipped SQL predicate unchanged false. The pre-existing disposable local helper simulation remains unchanged. Completed-shift late recording remains **FALSE / schema contract 0**. No hosted access, deployment, activation, Git writes, account/grant/password changes or localhost:3000 operations. Export Reader, Design System, historical migrations, shared owner adapter and unrelated work preserved; index remains empty and HEAD unchanged.

Future checkpoint is pending separate owner authorization after manual review and addressing acceptance limits. Inspect the entire pre-existing dirty worktree then stage selectively; do not assume this 28-file incremental manifest describes all earlier uncommitted work. Exclude credentials, runtime data, screenshots and other generated test artifacts. Do not start hosted acceptance or main-environment consolidation from this report.
