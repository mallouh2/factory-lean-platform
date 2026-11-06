> **4 November2026 update:** The Planning candidates and all21 stale Sales/Warehouse tests are now integrated/repaired on local4222; full1470 Node/122 SQL/3 concurrency scenarios/TypeScript/build pass. Existing Floor/historical behavior and all owner data are preserved. Final4222 authenticated API and normal owner browser checks PASS after the owner closed the native QA dialog; Planning/Gantt,6h policy,Floor and historical form verified read-only,with no console errors. See [current rollout report](planning-policy-rollout.md) for exact evidence and boundaries. Earlier dated candidate/failure statements below remain historical evidence.

# Planning policy candidates and historical permission acceptance — 3 November 2026

Overall broader task: **PARTIAL.** Historical permission/activation subtask: **COMPLETE / LOCAL VERIFIED**. Stop before promoting the unfinished Planning candidates. This report supersedes the earlier statement that4222 historical approval remainsFALSE.

## Live4222 changes

Existing factory 3ab24bb6-654e-40ab-a8bd-e0c8ca5c62c8; existing worker 4dea0a6e-971b-4d77-b3de-da494a1b5cd6, PlanningV3-worker@local.invalid, Local worker. Authenticated existing owner used protected set_user_permissions through /api/data:HTTP200. Exactly four direct grants added: orders:view,orders:edit,lines:view,centers:view. Existing factory:view retained; no grants removed. Whole direct-grant before/after comparison confirmed no other additions/removals. Effective orders:approve remainsFALSE. Membership remains approved/non-owner. Existing local credentials match the recovery copy byte-for-byte. No accounts/passwords/packages/roles changed.

Owner separately authorized these four grants. The broader brief authorized conditional historical activation. After successful isolated acceptance, only private.historical_recording_activation for this factory was enabled. Live current-shift late-recording gate remainsFALSE; inherited loopback manufactured predicate unchanged; shipped source gateFALSE. Owner data counts at activation:production_entries11,manufactured_outputs10,finished_goods_movements25 before and after. No owner production, Quality or stock transaction was executed.

Actual4222 normal worker login/read HTTP200, availableTRUE,12 eligible shift choices, previous-shift form visible. Evidence:historical-4222-read.json,historical-4222-worker-enabled.png,permission-before.json,permission-result.json,historical-activation.json in C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/planning-policy.

## Independent historical write verification

Existing worker and owner identities were copied into a byte-verified disposable local clone, not new accounts. Temporary browser4248/Auth4356/PostgreSQL55626; never4242. Real normal separate logins and unchanged protected application/API code:

- Worker SUBMIT HTTP200/PENDING:5e8bc23e-da7b-4f4c-a03e-34205d9af033.
- Pending creates no official recording or Quality output.
- Same worker APPROVE HTTP403/permissionError; no decision row.
- Independent existing owner APPROVE HTTP200/APPROVED.
- Exactly one production entry e4c39792-a3a5-4aff-89df-6bfe44d928ce and one Quality-eligible manufactured output.
- Zero finished-stock movements for that entry.
- Existing historical rollback SQL suite:30/30 assertions PASS, including independent approval, retries, rejection and Scrap-only no-stock behavior. This is local PostgreSQL/adapter evidence, not hosted Supabase.

Evidence:historical-browser-result.json,historical-worker-pending.png,historical-sql-results.txt. A browser test initially waited for an optional overproduction checkbox when1m did not exceed remaining work; no submission occurred. The selector was corrected, then the actual workflow passed once. Successful transactions were not replayed blindly.

## Unpromoted Planning candidates

Source is isolated C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\integrated-qa-v3. Existing running standalone4222 remains the previous verified build; no candidate Planning SQL was applied to55496. Candidate manifest: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/planning-policy/candidate-manifest.json. Three CLI-created forward drafts, currently tested only on disposable55626:

1.20261103102938_planning_warning_policy_v1.sql:factory default6h,exact numeric seconds/decimal hours,protected Orders-edit setter and audit,protected current-state reader,fingerprinted explicit exception command and UUID receipts,history-trigger enforcement.11 rollback checks PASS.
2.20261103103513_issued_material_time_replanning_v1.sql:same-line unused issued unfinished-source proof; current-stage execution/entries/consumption/hold/location checks; no material moves; cross-line capability and unscheduling custody rejection.8 rollback checks PASS against cloned PO20. This candidate proves the existing unfinished-lot case; unproven other custody models fail closed.
3.20261103103737_planning_change_notifications_v1.sql:derive departmental unread changes from committed existing Planning revision/command evidence,per-person per-audience immutable acknowledgments; no duplicate event subsystem.12 assertions PASS including Phase2 cases and4 notification checks.

Candidate UI/API:compact Planning setting; before/after confirmation/preparation checkbox; existing reason reused; Production/Warehouse change drawers; EN/AR strings. TypeScript passed. Browser/production-build/concurrency acceptance of these new candidates is NOT complete. No live PO20 schedule or material association changed. No candidate features should be claimed live yet.

## Test repair state and remaining work

Five CSS bootstrap harnesses repaired with in-memory esbuild output paths; two API mocks now implement actual same-origin checking with valid request origins. Their suites run instead of failing at import. Newly exposed Product color assertions targeted obsolete full-bar color declarations; common Product identity palette assertions remain,matching the approved shared Gantt surface. Planning reason-save test now exercises the protected context/new command contract. Planning+color focused92/92 PASS.

Latest candidate full Node:1413 tests,1392 PASS,21 FAIL. Remaining21 are the previously diagnosed12 Sales/Warehouse and9 Warehouse operations stale component-boundary/mock cases. They are NOT fixed and must retain receipt/dispatch/reservation/permission assertions when retargeted. No assertions were deleted to hide those failures. Increased total reflects formerly unbootable suites now executing.

Next required work:finish those21 harness repairs; add focused policy API/component and custody/concurrency tests; build candidate in a separate output; authenticated EN/AR/mobile/polling/drag verification on disposable fixtures; fresh owner-data comparison; only then apply the reviewed forward candidates and matching build to4222. Do not redo historical write acceptance or grant further permissions. Do not integrate3000.

## Recovery and environments

Recovery C:\Users\Temp\AppData\Local/FactoryLean-Recovery/planning-warning-1793701588063:2077 cold-copied database files SHA256-verified while only55496 was briefly stopped; copied source/credentials retained.55496 restarted successfully. No destructive restore executed. checkpoint.json contains file hashes. This cold copy was used to start disposable55626; actual data directory/loopback target verified before writes.

3000 untouched;4242 retains original process30384/database55620/Auth4340; hosted untouched.4222 application process9880 retained,Auth4304 unchanged,database55496 resumed after checkpoint. Temporary4248/4356/55626 stopped after acceptance; test data/evidence retained. No Git write operations,commits,pushes,repairs or migration-history edits. Relevant repository documentation only updated; protected Design System/Export Reader/unrelated dirty work preserved.
