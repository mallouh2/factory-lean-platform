# Operational UX simplification and workflow corrections

28 October 2026. **LOCAL IMPLEMENTATION VERIFIED; OWNER MANUAL/VISUAL ACCEPTANCE PENDING.** Three bounded batches implemented in sequence. Batch3 acceptance is PARTIAL because native pointer dragging remains a manual check; the real browser drop handler and protected transaction were exercised. This is not hosted acceptance or activation approval.

## Verified environment and preservation

- `development`, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, empty index. No Git writes, deployment, hosted access or activation.
- Preview: **http://127.0.0.1:4222/**, matching isolated optimized `operational-final-app` build. Existing owner **PlanningV3@local.invalid** signs in normally; password unchanged in the owner-restricted `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`. No credentials in source/docs/results.
- Independent PostgreSQL address/port/database/data-directory checks: preview **127.0.0.1:55496**, Auth/Data adapter **4304**; separate SQL regression **127.0.0.1:55498**. Both `factory_lean_quality_local`, different owned temporary data directories. No hosted Supabase connection. No dependency installation.
- Shipped manufactured capability remains `available:false`; shipped predicate remains FALSE. Existing disposable preview helper simulation is unchanged. Completed-shift late activation rows remain `enabled:false`, schema contract0. Same-shift eligibility was not extended or spoofed.
- **118 local migrations**, all **113 pre-task migration hashes unchanged**, including Export Reader. New five forward migrations below were applied only to disposable localhost databases. No claim of current remote alignment.
- Original PO31/PO32 and its old closed shift were preserved. Do not attempt ordinary recording in that expired occurrence. Existing owner adapter/permissions and unrelated previews/source remain intact; owner still has102 effective permissions, no new preview account/grants.

## Batch 1 — Quality: COMPLETE locally

**Root cause:** the old form kept a909m finished group while adding2m rejection, so its conservation check correctly rejected911 against909. The release field was an entitlement, not a replacement for the group's physical quantity. The same form obscured the distinction between one group and the recording total. A corrected measured total was also not an accepted command input.

Normal inspection now offers **Approve Inspection** or **Modify inspection**. Modification accepts measured total, nonrecoverable rejection, unfinished groups/remaining operations and a meaningful reason; finished output is derived with exact decimals: total−rejected−unfinished. Thus909/2→907 and909/2/4→903. There is no editable finished/release number. Multiple separately tracked finished group identities remain intact; changing their combined quantity requires existing reconciliation instead of guessing a split.

The protected command validates corrected total against its result and saves it in immutable Quality evidence. Original declaration/Production Good/source are never overwritten. Existing revision, UUID retry, per-person authorization, holds, received/allocated reconciliation and Warehouse-only stock posting remain authoritative. No second Scrap ledger: a rejected production quantity is not silently converted into KG or posted as a Scrap movement. Invalid sums, units, reasons, operations and protected stock produce actionable errors; success is shown only after a verified response.

Production notifications compare canonical quantities/classifications, aggregating equivalent unordered operation combinations. Matching approval, notes-only edits and release-only changes do not create a new unread discrepancy. Prior acknowledgements survive notes-only revisions; immutable events remain available. Actual material differences remain informational, not a request for Production approval.

Default Quality is an inspection queue. General historical filters/table and existing Quality exports now live in **Production History → Quality history & export**. Exact record drill-through/previous decisions/amendments remain accessible; no history was deleted. Existing production date/Product/line/order/shift lookup and permissions are reused. History-only rendering avoids unrelated shift/unfinished/startup readers.

Operation display names use existing work-center categories, with original IDs/snapshots retained. This fixture has two Extrusion work-center steps; both correctly display Extrusion. No Printing/Cutting IDs or routing configuration were invented. Distinct real operation configuration remains the factory's responsibility.

## Batch 2 — Warehouse/Sales: COMPLETE for supported pooled stock

Ordinary dispatch uses one confirmed Sales line and an actual quantity. It shows ordered/reserved/dispatched/dispatchable/outstanding and exact remaining after dispatch; no Stock Tag/Add Source control. Existing protected reservation, balance, movement, source and audit contracts handle the deduction once.

**Pool boundary:** only genuinely pooled **UNATTRIBUTED** finished quantities and that line's unassigned reservations qualify. Separately identified source assignments and source-scoped Quality holds remain protected. No FIFO/batch origin is invented. Identified-only stock cannot silently become mixed stock; it requires the existing physically justified allocation workflow and is explained as a blocker. Source picking remains available for existing specialist stock operations, outside ordinary dispatch.

The new quantity command holds the established factory lock, rechecks issue permission and state, uses immutable fulfillment UUID receipts, consumes only that order's reservation and records a NULL-source pooled allocation through existing triggers. Partial lines/orders remain open. Linked incoming is retained; only actual received eligible stock becomes reservation. An order completes only after all line quantities were dispatched. Existing reasoned Sales revision/cancellation rules preserve prior shipments and release only remaining commitments.

Sales wording is **Save Draft / Confirm Order**; internal `sales_orders:approve` authority is unchanged. Confirmation shows an advisory item summary for quantity available toward this order, reservation, eligible incoming and additional requirement. Candidate eligibility is shared with the existing allocator; the final confirmation still recalculates under its locks. A preview promises neither inventory nor a scheduling slot. No duplicate incoming or replacement forecast is introduced.

## Batch 3 — Planning/navigation: PARTIAL acceptance, local implementation complete

Scheduling keeps origin/priority/required-by, quantity, eligible line and factory-local start/finish visible. Original-order links, rates/setup, revisions and advanced slot analysis are in Details. The redundant prominent Find Slot action is removed; automatic availability, real blockers and protected scheduling remain. Existing factory time-zone conversion is reused; UTC is the explicit fallback when none is configured, never browser guessing. No stored timestamp reinterpretation.

Elapsed planned start alone no longer forbids a reasoned replan. The protected trigger checks genuinely planned/unstarted/unlocked work, actual timestamps, zero output/entries, issued/received material and operational holds. Existing factory/structure/item lock order, capability/calendar/capacity/maintenance checks and immutable plan history remain. Started, locked, materially committed or held jobs reject. Existing lock/unlock policy is deliberately unchanged; this is not permission to unlock protected schedules.

History has an EN/AR contextual Back action using allowlisted internal state. The originating screen stays mounted, preserving filters/pagination/selection/preferences where supported, with scroll restored. Direct History uses Factory Floor as fallback; there is no external return URL. Planning→History→Back and Floor→History→Back passed actual browser checks.

## Forward migrations / exact application and test scope

1. `supabase/migrations/20261027122009_operational_quality_inspection_v1.sql`
2. `supabase/migrations/20261027122758_quality_material_notification_v1.sql`
3. `supabase/migrations/20261027123356_pooled_partial_dispatch_v1.sql`
4. `supabase/migrations/20261027123847_sales_confirmation_preview_v1.sql`
5. `supabase/migrations/20261027124724_overdue_unstarted_replanning_v1.sql`

Changed existing application files: `src/app/api/data/route.ts`, `src/app/api/fulfillment/route.ts`, `src/components/FactoryApp.tsx`; `src/features/ManufacturedOutput.tsx`, `ProductionPlanning.tsx`, `ProductionRecording.tsx`, `Quality.tsx`, `SalesOrders.tsx`, `Warehouse.tsx`, `types.ts`, `useUnfinished.ts`; `src/locales/en.json`, `ar.json`. New helper: `src/utils/quality-inspection.mjs`. No CSS/dependency/configuration/owner-adapter change.

Affected existing harnesses: `tests/factory-navigation.test.mjs` (pre-existing missing hook slot), `quality-ui.test.mjs` (history now separate), `sales-fulfillment.test.mjs` (new partial/pool contract, existing harness imports), `warehouse-operations.test.mjs` (new reader's empty rows fixture). New `tests/operational-ux.test.mjs` and `tests/operational-ux/`: `prepare-local.ps1`, `quality.sql`, `quality-notifications.sql`, `quality-concurrency.mjs`, `dispatch.sql`, `dispatch-safety.sql`, `dispatch-revision-permissions.sql`, `dispatch-concurrency.mjs`, `dispatch-two-orders.mjs`, `sales-preview.sql`, `planning.sql`, `planning-concurrency.mjs`, `quality-browser.mjs`, `fulfillment-browser.mjs`, `planning-browser.mjs`, `final-preview.mjs`.

Documentation: this report, HANDOFF, dated links in Planning V3/manufactured Phase4 reports, and a bounded parity note in PRODUCT_DIFFERENTIATORS. These lists describe this task's delta, not permission to stage all prior dirty files. Future checkpoint requires the owner's separate authorization and review of the preserved combined work.

## Verification and actual evidence

- **193/193 affected Node tests PASS**, including Quality, navigation, Planning, same-shift recording, manufactured UI/reconciliation/drill-through, History, Warehouse inventory/operations and exact-decimal inspection cases. TypeScript and isolated optimized Webpack production build PASS. No full unrelated platform suite.
- **38 positive SQL assertions +19 expected negative cases PASS** in standalone PostgreSQL. Matching inspection, corrected total/original separation,907/903, notes-only acknowledgement, no Quality stock credit; pool holds/identified restriction;40 initial reservation,20+20 dispatch, actual protected production60→Quality→physical receipt→reservation60→dispatch60; incoming forecast sharing; Sales partial revision/cancellation; overdue replan/reason/history/locks/material issues/permissions.
- **Seven concurrency groups PASS with observed database waits**: Quality same UUID replay/different UUID stale revision; dispatch same UUID replay/competing same-line quantities; two separate Sales orders sharing40 stock; Start-first/replan-first races. Source/stock events were checked after transactions. Package-only Warehouse authority succeeded; removing that package denied further dispatch without replacing direct grants. Restricted and foreign-factory commands rejected.
- Real normal owner browser writes: changed909 inspection (903 finished/4 unfinished/2 rejected) and matching2m inspection HTTP200; no movements from Quality; two20m partial dispatches HTTP200 on separate synthetic Sales fixture. Full final60 production/receipt/shipment proven through protected SQL, not claimed as a repeated browser workflow.
- Browser Planning reasoned overdue replan HTTP200; actual drop handler→protected command→one plan revision persisted on the capable free QA line. Native pointer drag remained inconclusive. A harness waited for `dragend` on the removed queue row after the successful drop; SQL state was inspected and the transaction was **not repeated**. Other harness timing/origin/sidebar issues were corrected without weakening app validation.
- Final optimized4222 normal login/read checks PASS: correct owner/factory; pending-only Quality; History filters/export workspace/Back; persisted material/matching decisions and notification distinction; Sales dispatched40/outstanding60; Planning Back; EN/AR390px no page overflow, zero browser exceptions or authenticated API errors. Pre-login snapshot401 is expected, not an authenticated defect.
- Screenshots inspected for desktop Quality/modification, Arabic mobile Quality/Warehouse/Planning. Existing horizontal Gantt/table scrolling retained. Shared `visual_lint.mjs` was not present in the installed skill files; browser overflow/console checks and screenshot inspection were used. No claim of a full accessibility audit or physical-device acceptance.
- Separate older `sales-fulfillment.test.mjs`: **33/41 pass,8 pre-existing stale Warehouse UI cases fail**. Before-task source baseline had29/41 pass,12 fail; all eight remaining failures are in that baseline: EXTERNAL/BOTH replenishment layout, EN/AR movement-history action location, external/opening receipt selectors, EN/AR top actions. Four obsolete complete-line/source-picker expectations were updated for the approved new contract. These unrelated older cases were not used to justify production changes or falsely reported green.

Evidence: preview root `operational-ux/` contains browser response journals/screenshots, build/TypeScript/Node results, baseline comparison and971-file preservation manifest. SQL root `C:\Users\Temp\AppData\Local\Temp\FactoryLean-OperationalUX-SQL-d7232dad5d0d4b6689e384197aadc0ab` retains scripts/results and disposable data; server stopped after tests. This uses local Auth/Data fixtures and standalone PostgreSQL, not hosted Supabase/PostgREST acceptance.

## Owner manual review / remaining limits

1. Open4222, sign in with existing local credentials, open **Quality**. Original PO34 still awaits a user Quality decision. Select it; approve unchanged, or modify with a reason and check the calculated finished result. Do not reuse old PO32's expired shift.
2. **Production History & Quality decisions** opens historical lookup/export; Back returns to Quality. Inspect prior **PO35/PO36** correction (909 original,903 finished/4 unfinished/2 rejected) and **PO37/PO38** matching decision. Relevant previous decisions remain in Details.
3. **Warehouse → Dispatch**, **SO-0000003 / UX pooled dispatch pipe**:40 already dispatched,60 still outstanding/incoming. Do not expect dispatchable60 before legitimate production/inspection/receiving. Existing commitments were not replaced to fake availability.
4. **Planning**, **PO42**: revised unstarted job on Same-shift reporting QA; inspect reason/history and visible origin/priority/due. **PO44** is the separately planned drag fixture. Review native pointer dragging on another eligible free slot and English/Arabic/mobile layout before visual approval.
5. Check **Sales → Save Draft / Confirm Order** advisory summary and **History → Back** from Floor/Planning. No mandatory training or internal source IDs in ordinary dispatch.

No additional operational scenario, activation, hosted rollout, account change or Git checkpoint is authorized by this report. Owner visual/manual review and a separate checkpoint decision remain next. Stop here.
