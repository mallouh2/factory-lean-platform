# Planning policy rollout and regression repair — 4 November 2026

**COMPLETE / LOCAL VERIFIED — STOP for owner manual review.** The owner closed the native QA sign-out dialog. Final normal owner browser login and read-only Planning/Gantt, Factory Floor and historical-recording checks on4222 now PASS. No policy/inventory failure was observed. No operational test transaction was repeated.

This supersedes the unpromoted-candidate / 21-failure statements in earlier reports. No further feature work is authorized.

## Runtime and preservation

- User preview: http://127.0.0.1:4222/?view=planning. Exact existing factory/user/database identities preserved.
- Source: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/planning-rollout-app-1793742811512. Build: .next-planning-final (Webpack); owner standalone: owner-runtime. Runtime pointer: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/runtime.json. Auth4304 → verified localhost PostgreSQL55496, database factory_lean_quality_local; no hosted URL in this environment.
- Working repository remains development, HEAD bb0d20e5dd433b896dd319f56e75f0d9eb5d2862, index unchanged. Implementation remains isolated from the checkout used by the original application; repository edits are documentation only. No 3000 process/configuration changes or access; no4242 access/changes. Protected4242 was stopped at initial process inspection and was not restarted. Existing4250 preview preserved.
- Recovery: C:\Users\Temp\AppData\Local/FactoryLean-Recovery/planning-policy-rollout-20261104-1793742811512. Source copies and 2081 cold database files were SHA256-verified before writes. Existing owner/auth credentials copied without disclosure; current credential files match recovery byte-for-byte.
- All127 baseline public/private/auth.users table digests match before/after integration and authenticated owner reads. This includes memberships, permissions/packages, existing Sales/Production/Quality, reservations, custody, audit and old pending historical requests. No QA fixture was copied into4222. All143 accepted source migration files and all authoritative repository files matched the snapshot before the authorized documentation updates.
- Owner PO-0000020 item50922e50-03a4-4c0f-8d6c-fe63faf38390 was inspected read-only:10m, Printing line, planned, actual_start NULL, consumed0, no Quality hold, material request a90a1c65-884b-456f-9e96-ccb78b5e3d0c ISSUED10m. Full order/request JSON unchanged. Protected issued_time_change_safe=TRUE and exception_required=TRUE. Same-line time change is now eligible subject to explicit review and the proposed slot's normal constraints; no proposal was executed against this order.

## Phase results

| Phase | Result |
| --- | --- |
| Configurable warning | PASS: default21600s/6h;1.5h saves exactly5400s, effective factory-scoped Orders edit only, actor/UUID policy audit. Decimal input displays normalized6/1.5 rather than database trailing zeros. |
| Protected replanning | PASS: before/after line/time, signed time-to-start using existing duration formatter, actual issued/reserved evidence, one meaningful explanation and explicit unchecked confirmation. Unknown context fails closed; refresh invalidates confirmation. |
| Issued unconsumed completion | PASS: same-line time revision preserves exact material request, lot/location, allocation and issue history. No return/reissue/consumption or stock movement. Unproven custody models fail closed. |
| Unsafe execution/custody | PASS: unsafe unschedule → planning_material_custody; incompatible move → capability-specific rejection; actual started/consumed work, Quality holds, overlap and maintenance capacity remain protected. No automatic material transfer or cascading reschedule. |
| Notifications | PASS: committed exceptional revision evidence only; Production receives scheduling impact, Warehouse only actual material impact. Per-user/audience acknowledgments are retry-safe and do not rewrite Planning history. No notification on cancellation/failure. Same-scope polling retains unread rows; factory/user switches hide old rows. |
| Regression harness | PASS: all21 previous failures repaired; no tests removed or skipped. Full suite1470/1470. |
| Local integration | PASS: four exact reviewed forward files applied only to55496 after55632 testing; six key protected function definitions match QA byte-for-byte. |
| Final user-preview browser | PASS: existing owner normal login, Planning/Gantt Day/Week,6h display,Factory Floor toolbar and historical form on4222; no browser warnings/errors. |

### Transaction safety

The final forward migration retains the existing Planning/resource/permission contracts. Its outer protected confirmation writer uses the canonical factory → structure → item ordering shared with actual source consumption. The fingerprint includes policy revision, order state, actual material requests, live completion allocation/lot evidence, consumption and hold state. It is re-evaluated inside the transaction. Private admission records remain unavailable to authenticated clients. Existing exact UUID results are returned without duplicate revisions/notifications; altered UUID payload or stale context is rejected. There is no second scheduling engine or stock ledger.

The existing mandatory replanning explanation is reused. Its label now explicitly says required for exceptional changes. Current factory timezone is UTC; display uses the saved factory timezone, comparison uses authoritative UTC timestamps. Test calendars/resources were created only in the disposable clone through the fixture's protected operational commands; no owner schedule or unrelated job was advanced.

## Forward-only local migrations

Applied in this order, unchanged between the evidence directory and isolated source:

1. 20261103102938_planning_warning_policy_v1.sql
2. 20261103103513_issued_material_time_replanning_v1.sql
3. 20261103103737_planning_change_notifications_v1.sql
4. 20261103215853_planning_policy_rollout_integrity_v2.sql

The first three are the preserved earlier candidates; the fourth minimally strengthens source-state fingerprinting and lock ordering. No earlier migration was edited, renamed, repaired or replayed. Accepted isolated source now contains147 migration files. This is standalone disposable PostgreSQL evidence, not a hosted Supabase migration-history assertion. Export Reader was preserved and was not executed by this task. No hosted history was queried.

## Verification evidence

Evidence directory: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/planning-rollout-1793742811512

| Check | Current result |
| --- | --- |
| Full Node |1470 PASS,0 FAIL,0 skipped/cancelled/todo; node-final.log |
| Focused repaired Sales/Warehouse |57/57 PASS; repaired-21.log |
| New Planning API/component |31 API +12 UI PASS (included in full total) |
| Candidate rollback SQL |11 policy +8 issued-material +12 notification assertions PASS |
| New rollback SQL |41 protected contracts +2 real production-overlap assertions PASS |
| Accepted workflow SQL rerun |16 historical transitions +6 atomic/factory/quantity +2 disabled-gate assertions;19 compensation/capacity +5 authorization/stale assertions PASS |
| Total SQL assertions run |122 PASS; all assertion suites roll back |
| Real concurrent sessions |3 PASS: identical UUID waits and produces one command/revision; competing stale revision waits then rejects; actual Start plus canonical1m input consumption makes concurrent replan wait/reject, leaving9m on floor/0m Warehouse,one production entry |
| Actual authenticated HTTP |403 denied policy change;403 wrong Warehouse audience/read/ack;422 unsafe unschedule;409 changed policy fingerprint;200 separate existing worker Production unread read; all denied requests leave production rows unchanged |
| Restricted partial dispatch |Actual existing worker gets HTTP403/42501 permission_denied; null data; stock movements, reservations and Sales unchanged |
| TypeScript |PASS; typecheck-final.log |
| Isolated optimized build |PASS; build-final.log, .next-planning-final. Webpack used for the existing external dependency junction; initial Turbopack root/junction limitation was environmental, not an application failure. |
| 4222 read smoke |HTTP200 root, authenticated factory snapshot,6h policy,PO20 context, both empty departmental notification readers and historical reader. No factory-data writes;127 digests unchanged. |

QA data and guarded SQL/scripts/results remain in the evidence directory. QA uses55632/Auth4362/app4260, independently verified against its exact loopback data directory. No new user was created and no permission was changed. Concurrency writes affected only named new QA fixtures. Prior successful operational transactions were not repeated against owner data. The new QA4260/Auth4362/PostgreSQL55632 processes were stopped after verification; their data and results remain available. Existing4250 and owner4222 remain running. The owner subsequently closed the native prompt. Final4222 browser checks completed successfully and the viewport override was reset.

Temporary fixture-harness mismatches (numeric JSON type, exact error label, preexisting helper schemas) were corrected without weakening business guards; final assertions use actual protected commands and actual database responses.

### Browser acceptance

Normal existing owner login succeeded on QA4260. Actual browser interactions verified policy1.5, same-line issued-material change for QA PO-0000064, reason/explicit confirmation, actual custody rejection, Warehouse material-only notification, Arabic acknowledgment/count removal, and cancelled Gantt drag reverting the proposed schedule. New QA Production worker's real authenticated API independently sees its own unread Production changes and is denied Warehouse access/ack.

EN/LTR and AR/RTL were inspected at1440/768/390px, including compact policy, Week short-job representation and mobile confirmation/notification dialogs; no document-width overflow. Gantt Day rendering and keyboard horizontal scroll/Week/filter preservation across refresh were checked. Native drag opens the same protected reason/review without committing until confirmation; cancel restores saved values. Current-state before/after screenshots and browser-layout-results.json are retained. Timings and the real1-minute short-job marker remain unchanged.

A normal QA sign-out attempt temporarily blocked the embedded browser at its native confirmation; the owner closed it. No browser security restriction was bypassed. Final4222 normal existing-owner login and factory scope verified: Planning/Gantt Day and Week load, default warning6 displays in EN/AR, existing PO20 remains planned, Factory Floor toolbar/statuses render, Previous Shift opens its real date/shift/work options and owner-authority guidance. Older PO30 still displays Pending Approval with the independent-approver explanation. No Save, Approve, Start, Finish, issue, receipt or schedule command was submitted. Browser error/warning log is empty. Temporary viewport override reset successfully;4222 remains signed in as owner on Planning for manual review. Evidence:owner-browser-completion.json and owner-4222-final-*.png.

## All21 prior failures

| # | Previous test | Disposition and retained coverage |
| --- | --- | --- |
|1|Warehouse EXTERNAL displays authoritative replenishment state|PASS — Current WarehouseInventory authoritative replenishment projection, EXTERNAL|
|2|Warehouse BOTH displays authoritative replenishment state|PASS — Current WarehouseInventory authoritative replenishment projection, BOTH|
|3|Movement history separates reservation changes from physical stock in en|PASS — Actual WarehouseMovements physical vs reservation deltas, EN|
|4|Movement history separates reservation changes from physical stock in ar|PASS — Actual WarehouseMovements physical vs reservation deltas, AR|
|5|Warehouse external_receipt sends configured unit with no client actor/time or production command|PASS — Current factory-scoped /api/warehouses receipt with unit/UUID and no actor/time|
|6|Warehouse opening_balance sends configured unit with no client actor/time or production command|PASS — Current factory-scoped /api/warehouses opening receipt with unit/UUID and no actor/time|
|7|Warehouse presents reserved quantities for partial dispatch in en|PASS — Requests workspace opens partial-dispatch context, EN|
|8|Warehouse presents reserved quantities for partial dispatch in ar|PASS — Requests workspace opens partial-dispatch context, AR|
|9|Warehouse top actions and request directions stay distinct in en|PASS — Two workspaces, management/history grouping and distinct request directions, EN|
|10|Warehouse top actions and request directions stay distinct in ar|PASS — Two workspaces, management/history grouping and distinct request directions, AR|
|11|Warehouse partial dispatch preserves individual issue permission|PASS — Protected issue denial and zero applied actions; independently verified actual SQL/RPC HTTP403 and unchanged stock/reservations|
|12|Physical pooled dispatch submits the selected partial quantity without source picks|PASS — Partial quantity limit, exact selected quantity and UUID, no fabricated source picks|
|13|Exactly five mapped operations and one active panel; switching sends no command en|PASS — Two current workspaces; one active panel; no write from navigation, EN|
|14|Exactly five mapped operations and one active panel; switching sends no command ar|PASS — Two current workspaces; one active panel; no write from navigation, AR|
|15|Keyboard tabs follow reading direction, wrap and Home/End en|PASS — Two-tab keyboard LTR/RTL direction, wrap and Home/End, EN|
|16|Keyboard tabs follow reading direction, wrap and Home/End ar|PASS — Two-tab keyboard LTR/RTL direction, wrap and Home/End, AR|
|17|WIP receipt and authorized lot processing both retained; processing lazily resets on tab change|PASS — Current stored-unfinished dataset remains separate; browsing does not process stock; editing permissions retained|
|18|Purchase creation has exactly one contextual entry, permission preserved en|PASS — Purchasing creation in its current dedicated page with actual create permission, EN|
|19|Purchase creation has exactly one contextual entry, permission preserved ar|PASS — Purchasing creation in its current dedicated page with actual create permission, AR|
|20|Inventory management groups Add Material and Settings, separate from row Actions en|PASS — Current receipt/history/management/settings actions and view-only restrictions, EN|
|21|Inventory management groups Add Material and Settings, separate from row Actions ar|PASS — Current receipt/history/management/settings actions and view-only restrictions, AR|

Detailed per-case evidence: failure-dispositions.json. Tests update imports/read hooks and interaction boundaries to the current Warehouse architecture. They do not restore obsolete five-tab UI, remove authorization tests or replace quantity assertions with trivial renders.

## Confirmed separate issue

The existing Warehouse partial-dispatch drawer can still expose an enabled confirmation to a viewer without warehouse:issue. The protected command correctly denies it; the test now verifies rejection and no applied action, with independent actual RPC403 and unchanged inventory evidence. This is an existing UI-permission feedback defect outside the Planning rollout, not an authorization bypass. No Warehouse business-logic change was made. A separate small UI fix may be authorized later.

## Exact source manifest

Relative to the verified accepted4222 source. Absolute source root is above; hashes are in source-change-manifest.json.

- src/app/api/planning-policy/route.ts (new)
- src/app/globals.css (modified)
- src/features/PlanningChangeUpdates.tsx (new)
- src/features/PlanningWarningPolicy.tsx (new)
- src/features/ProductionPlanning.tsx (modified)
- src/features/ProductionRecordingV3.tsx (modified)
- src/features/Warehouse.tsx (modified)
- src/locales/ar.json (modified)
- src/locales/en.json (modified)
- tests/planning-policy-api.test.mjs (new)
- tests/planning-policy-ui.test.mjs (new)
- tests/planning.test.mjs (modified)
- tests/sales-fulfillment.test.mjs (modified)
- tests/warehouse-operations.test.mjs (modified)
- supabase/migrations/20261103102938_planning_warning_policy_v1.sql (new)
- supabase/migrations/20261103103513_issued_material_time_replanning_v1.sql (new)
- supabase/migrations/20261103103737_planning_change_notifications_v1.sql (new)
- supabase/migrations/20261103215853_planning_policy_rollout_integrity_v2.sql (new)

Generated local next-env.d.ts changed only its isolated build type reference; it is not an application feature or a repository edit. Runtime pointer and owner standalone/environment copies are local launch artifacts. No dependency installation/configuration change occurred. Authoritative repository documentation changed: HANDOFF.md, docs/planning-policy-and-historical-preparation.md, docs/planning-policy-rollout.md and a superseding verification note in docs/factory-floor-historical-v2.md. PRODUCT_DIFFERENTIATORS.md reviewed; this bounded Planning completion/test repair does not justify a new competitive claim.

## Gates and next action

Owner final policy remains the default6hours;1.5 was exercised only in QA. Historical-production activation remains the already authorizedTRUE; completed-shift late-recording gate remainsFALSE; Maintenance activationFALSE. Existing manufactured-output loopback-only test predicate is preserved, not newly enabled; shipped source gates remainFALSE. No account/password/permission changes,3000/4242/hosted operations,Git index/history writes,commit,push,merge or hosted deployment occurred.

Local implementation and acceptance are complete. Hand control to the owner for manual review; no promotion to3000 or new development task is authorized. The separate Warehouse confirmation-button permission-feedback defect remains documented, with server-side denial verified.
