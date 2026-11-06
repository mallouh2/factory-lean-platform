# Consolidated end-to-end acceptance fixes — 2 November 2026

**Status: PARTIAL, local only. No release/activation recommendation.** The approved Quality measurement-shortage integration is COMPLETE locally. Historical recovery-input/startup evidence remains unsupported and fail-closed. Owner SO-0000005 and its 1,030 m delivery have not been replayed or edited.

1. **Overall:** implemented the bounded Planning, Recording, Requests/Sales and inspection-interface changes; added an inactive ordinary historical-approval path. The owner subsequently approved measurement-only shortage as unproduced work; that bounded integration is implemented and verified.
2. **Per-phase:** Planning implementation locally verified subject to the final visual evidence below; Recording implemented; Warehouse/Sales implemented; Quality receipt/demand/progress integration passes local tests; ordinary historical approval passes local tests, historical recovery is BLOCKED; final verification is documented below without implying hosted acceptance.
3. **Root causes:** native queue-card drag image disagreed with the time-scaled schedule overlay; queue placement and existing-item grab offset were conflated. Guidance keyed by poll timestamp replaced its content; availability messages also changed its height. Recording waited for sequential summary/report reads after committing. Warehouse remounted Requests and its dispatch source calculated unrelated inventory/material projections. Receipt/Sales labels were unconditional. Actual Quality total was already protected in SQL but hidden under Advanced. Closed-shift approval did not exist.
4. **Gantt:** new queue pointer maps to proposed start; existing-item offset is measured in timeline time. A transparent native image removes the misleading card. The interval and detached annotation are separate; one minute remains one minute. Drop revalidates the last displayed start/finish with existing scheduling logic and rejects changed duration. Planning, locks, reasons, capability and maintenance guards remain intact.
5. **Customer target:** existing protected backward calculation supplies the recommendation, including safety buffer. It is first and distinct from earliest available. Selection uses current capability/calendar/conflict validation and requires an explicit later Save. An out-of-view candidate first offers a read-only timeline check; unknown/unavailable candidates cannot be selected. Current reader does not itself include Maintenance, so no unverified SQL suggestion is called selectable.
6. **Factory time:** creation/settings use IANA country/region choices, with Qatar → Asia/Qatar and explicit multi-zone selection. Existing absolute timestamps are never rewritten. Existing protected settings and shift-revision boundary rules remain. The isolated QA factory uses Qatar metadata; original owner factory metadata was preserved. Captured older shift occurrences retain their original zone rather than being reinterpreted.
7. **Planning controls:** normal Lock Plan removed; historical authorized Unlock and underlying protection retained. Close/إغلاق and Remove from Schedule/إزالة من الخطة use existing dismissal/replanning handlers. Closing does not remove work.
8. **Refresh:** guidance data is keyed by actor's factory/item scope, not polling timestamp. Same-scope content stays during refresh; a stable status area and range-based check action avoid poll-dependent geometry. Freshness still disables protected selection. No scroll-restoration loop, global scroll lock or disabled polling was added. Final measured cycles appear below.
9. **Recording timing:** disposable fixture baseline Save → success 946 ms; initial revised run 586 ms; optimized application run 373 ms. A later optimized save under concurrent validation took1,099ms. These individual samples show variance, not a guaranteed speedup or broad benchmark. Rollback SQL profile: manufactured command ~149 ms; canonical recording ~79 ms; permission authorization/context/constraints remain included. Total EXPLAIN ~224 ms also included the test payload/reader construction. Ordinary success now verifies the immutable receipt, acknowledges durable intent, closes and shows a small toast; refetches continue asynchronously. Save & End retains completion-only recovery after a confirmed save, with no resubmission of quantities.
10. **Requests timing:** same 80-request QA data, 50 visible rows/42,855 response bytes, HTTP 200 in every sample. Before API: 8,885 / 8,679 / 15,987 ms; after: 3,161 / 1,993 / 2,638 ms. Median 8,885 → 2,638 ms (~70% reduction); small localhost sample, not hosted performance. The new dispatch-source reader returns the identical existing order details/count and avoids inventory/material calculations. All sources still use complete bounded counts before matching-result pagination. Cached tab return measured ~66–96 ms; stale actions/export remain disabled until revalidation. Earlier first-useful QA table measurements were ~6.0–6.6 seconds; final measurement is recorded below. Owner's different five-row baseline is not used as an apples-to-apples comparison.
11. **Labels:** completed/zero-remaining receiving uses Close, unsaved receiving Cancel. Completed Sales shows Delivery confirmed and existing actual dispatched quantity. No Sales or receipt transaction was changed to achieve this.
12. **Quality:** original technician total stays visible; verified actual total is part of ordinary inspection, not Advanced. Existing SQL already accepts it. 60 actual / 58 accepted gives 2 rejected with measured KG; 58 actual / 58 accepted gives zero rejected. Original production remains60 in immutable evidence. Current finished output58 and ordinary unproduced remaining2 preserve target60. Active work can record2 normally. After execution ends, effective Orders view/edit/create/approve may explicitly create unscheduled linked make-up after confirming all output is recorded. Typed MEASUREMENT uses existing immutable work/compensation records, allocates no material lot or rejection entitlement, and never creates/starts work automatically. Receiving exposes exactly 58 released/remaining and no pre-receipt stock credit. Stale revision, replay and permission checks remain.
13. **Historical approval:** Current/Previous choice, suggested completed occurrence, editable date/shift, per-date actual configured shifts, no lateness reason. Pending is excluded from official production and Quality. Actual actor binding, independent effective approval, rejection/new-UUID resubmission, period evidence, private admission capability, immutable decisions and safe retries are documented in `historical-production-approval-v1.md`. The gate is FALSE after testing.
14. **Protection:** no new Scrap ledger, source-consumption system, auth bypass or stock-credit path. Existing canonical writers perform constraints. Direct/package permission SQL checks and actual operator HTTP denial are separate evidence. Manufactured receipt/Quality protections remain. Historical recovery inputs are refused rather than assigned invented provenance.
15. **Regression scope:** focused tests only; no full platform/security suite or hosted scenarios. Node/client, standalone PostgreSQL/local Auth adapter and browser evidence are distinguished. No claim of real Supabase/PostgREST hosted equivalence.
16. **Visual evidence:** actual browser screenshots are outside Git under the disposable QA `screenshots` directory. Exact sizes/languages and unresolved visual checks are recorded below.
17. **Checks:** final counts and paths below. Twelve stale Warehouse assertions in the older `sales-fulfillment.test.mjs` harness also fail against the pre-task application source; they are not newly passing. Nine guidance fixtures were updated for the stable scope key. The selected affected Sales/guidance tests pass. Broad unrelated suites were not rerun.
18. **Manifest:** generated from per-file pre-task hashes, not from the already-dirty Git HEAD diff; see the exact list below.
19. **Forward migrations:** `20261102100000_historical_production_approval_v1.sql` adds inactive approval and narrowly scoped canonical-writer admission; `20261102113000_warehouse_dispatch_requests_reader_v1.sql` adds a protected read-only source. No historical migration was edited. `20261102140000_quality_measurement_shortage_v1.sql` adds derived measurement/finished adjustments, protected progress and explicit make-up. Local total is141; no remote alignment is claimed.
20. **Preview:** new isolated review application http://127.0.0.1:4242, Auth 4340, PostgreSQL 55620. Credentials: the existing `LOCAL-LOGIN.txt` in the runtime directory identified by `%TEMP%\FactoryLean-Consolidated-location.txt`. The original owner preview on 4222 remains unchanged and running. No passwords are in this report/repository.
21. **Remaining:** Historical recovery input/startup provenance is unsupported and rejected; ordinary historical output and measured Scrap-only are covered. Hosted deployment/acceptance and owner manual approval are not performed. Obsolete synthetic balances are not backfilled. The new generated-expression migration uses PostgreSQL17 syntax; any future authorized release must verify engine compatibility and migration histories. No activation recommendation.
22. **Preservation:** final hash/digest evidence below checks all 138 original migration files, Design System, Export Reader, original owner tables, branch/HEAD and empty index. Isolated QA fixtures do not alter owner records. Existing local fixture overrides are explicitly distinguished from shipped gates.
23. **Boundaries:** no hosted Supabase, deployment, Git writes, branch change or localhost:3000 operation. No original preview or unrelated project was restarted. Normal local authentication reused existing accounts; temporary QA permission fixtures were rolled back/restored. No passwords/accounts reset or created.
24. **Activation:** both shipped gates remain disabled/unchanged; ordinary completed-shift gate is FALSE. Existing inherited localhost-only manufactured test predicate remains TRUE solely as it was before testing; it is not shipped activation. New historical-approval gate is FALSE. Do not activate or consolidate into the owner's environment on the strength of this partial report.

## Final verification evidence

- Final focused Node aggregate107/107 PASS. Previously verified74 Planning and24 selected Sales/guidance checks remain applicable; no full-suite claim. Twelve stale Warehouse harness failures reproduce against pre-task source; they were not fixed or falsely reported passing.
- Standalone PostgreSQL:45 measurement/conservation/permission checks,8 Quality checks and30 historical approval checks PASS, rolled back. Measurement45 also pass on separate55621 following a fresh forward migration and final progress-reader refinement. Historical harness now selects real available capacity instead of an arbitrary fully-produced first row.
- Three actual make-up races observed lock waits: identical UUID returns one job; distinct UUID cannot allocate2 twice; competing recording on the ended original is rejected. One allocation and one original entry. Previous two historical-approval races remain verified separately.
- Normal browser: Quality60→58/zero rejection200; explicit ended make-up2→one planned linked item200 (PO-0001232); active Quality200, ordinary additional2→200, auto-close/toast, raw62/current finished60/remaining0, no recovery allocation or stock before inspection/receiving. Restricted actual-login make-up POST403 and allocation count unchanged. No browser JS errors.
- Both Sales-linked SQL paths preserve target60: receipt58 reserves58; ordinary or linked accepted2 receipt reaches on-hand/reserved60 and converts original incoming exactly60. Mixed48 finished+10 unfinished+2 unproduced keeps ordinary2 and unfinished entitlement10 separate. True rejected2 yields measurement0 and recovery2.
- TypeScript PASS; isolated optimized build PASS. Preview4242 uses only loopback4340/55620. Separate migration-check55621 stopped normally; original owner4222 remains running.
- Visual evidence: existing13-screen Planning/Quality matrix, final12-screen Quality/Recording matrix and12-screen ended make-up/Quality matrix cover EN/AR1440/768/390. Final allocated make-up read-only smoke also passes: no duplicate create action or recovery coverage classification. Actual-total precedes classification; original60/current58/remaining2 are distinct. No document overflow. Actual native120min preview and one-minute07:00–07:01Z save verified. Not every scheduled-offset/Week/narrow native-drag combination was executed.
- Two real30s Sales-linked Planning polls preserved334.59375px guidance, drawer node, focus, draft inputs and scroll. Requests filter/node retained across tab switches; no polling disable/global scroll workaround. Final first useful table1,898.8ms, cached return74.3ms. Matched-data API median8,885→2,638ms; localhost samples only.
- Preservation: all138 prior migration hashes, Design System, Export Reader, AGENTS.md and122 owner table digests unchanged; no prior file removed. development HEADbb0d20e5dd433b896dd319f56e75f0d9eb5d2862/index empty. Owner SO-0000005 remains completed/1030m dispatched.
- Evidence: directory named by %TEMP%/FactoryLean-Consolidated-location.txt contains final-sql.json,measurement-fresh-migration.txt,measurement-concurrency.json,measurement-browser.json,measurement-active-browser.json,measurement-denied-browser.json,final-gates.json,visual.json,planning-final-poll.json,requests-api-before/after.json,warehouse-browser.json,build-final.log,screenshots/. Original owner runtime/e2e-consolidated/preservation.json holds final preservation. Successful write fixtures must not be blindly replayed.


## Exact current-task file manifest

70 current-task files, compared against pre-task file hashes (not the already-dirty HEAD diff):

```text
HANDOFF.md
docs/PRODUCT_DIFFERENTIATORS.md
docs/e2e-acceptance-consolidated-fixes.md
docs/historical-production-approval-v1.md
docs/manufactured-output-phase4.md
docs/planning-v3.md
docs/production-recording-v3-phase4b.md
docs/quality-inspection-v2-final.md
docs/refresh-layout-stability.md
docs/warehouse-management-v2.md
src/app/api/historical-production/route.ts
src/app/api/manufactured-output/route.ts
src/app/api/production-completion/route.ts
src/app/globals.css
src/components/FactoryTimezone.tsx
src/components/SalesPlanningGuidance.tsx
src/data/factory-timezones.json
src/features/Administration.tsx
src/features/HistoricalProductionRecording.tsx
src/features/ManufacturedOutput.tsx
src/features/ManufacturedReceiving.tsx
src/features/MeasurementMakeup.tsx
src/features/Onboarding.tsx
src/features/PlatformDashboard.tsx
src/features/ProductionPlanning.tsx
src/features/ProductionQualityCompletion.tsx
src/features/ProductionRecordingV3.tsx
src/features/SalesOrders.tsx
src/features/Warehouse.tsx
src/features/WarehouseRequests.tsx
src/features/warehouse-v1.css
src/locales/ar.json
src/locales/en.json
src/services/production-completion-client.ts
src/services/warehouse-requests.ts
src/utils/historical-production.mjs
src/utils/planning.mjs
src/utils/production-completion.mjs
src/utils/production-recording-v3.mjs
supabase/migrations/20261102100000_historical_production_approval_v1.sql
supabase/migrations/20261102113000_warehouse_dispatch_requests_reader_v1.sql
supabase/migrations/20261102140000_quality_measurement_shortage_v1.sql
tests/e2e-consolidated/baseline-browser.mjs
tests/e2e-consolidated/browser.mjs
tests/e2e-consolidated/fixture.mjs
tests/e2e-consolidated/historical-browser.mjs
tests/e2e-consolidated/historical-concurrency.mjs
tests/e2e-consolidated/historical.sql
tests/e2e-consolidated/historical.test.mjs
tests/e2e-consolidated/local.mjs
tests/e2e-consolidated/measurement-active-browser.mjs
tests/e2e-consolidated/measurement-browser.mjs
tests/e2e-consolidated/measurement-concurrency.mjs
tests/e2e-consolidated/measurement.sql
tests/e2e-consolidated/phase1.test.mjs
tests/e2e-consolidated/planning-browser.mjs
tests/e2e-consolidated/planning-poll.mjs
tests/e2e-consolidated/preservation.mjs
tests/e2e-consolidated/profile.mjs
tests/e2e-consolidated/quality.sql
tests/e2e-consolidated/recording-browser.mjs
tests/e2e-consolidated/requests-performance.mjs
tests/e2e-consolidated/setup.mjs
tests/e2e-consolidated/visual.mjs
tests/e2e-consolidated/warehouse-browser.mjs
tests/planning.test.mjs
tests/production-compensation-api.test.mjs
tests/production-completion.test.mjs
tests/sales-fulfillment.test.mjs
tests/warehouse-requests-pagination.test.mjs
```
