# Manufactured output — Phase 3 receiving and inventory

Status: **LOCAL COMPLETE / INACTIVE**, 25 October 2026. This is local Phase 3 acceptance, not hosted acceptance or permission to activate. Phase 4 Planning/completion integration and final cutover acceptance remain outstanding.

## Implemented contract

- New forward migration `20261024181109_manufactured_output_receiving_v3.sql`. All 103 preceding migration files are unchanged; 104 local files. Export Reader remains excluded from disposable test chains and untouched.
- Protected `receive_manufactured_output` validates effective Warehouse permission, current Quality revision/release, physical confirmation, location and exact positive quantity. Factory/structure locks, authorization after lock waits, immutable UUID intent/replay and transaction rollback protect the complete stock/receipt/Sales operation.
- Production recording and Quality release do not credit stock on an enrolled source. Receipt credits the existing finished balance/movement/source contracts once. Unidentified stock remains unattributed until normal physical identification; selecting software metadata does not claim physical traceability.
- Unfinished receipts create separately classified existing unfinished lots, with available quantity equal to stored quantity. Metadata retains output/group, original demand, operation snapshot, unordered missing operations, handling restriction and location. Compatible pools expose their original allocations. No second inventory ledger, finished-stock credit, duplicated floor stock or mandatory roll/coil label.
- Partial receipts leave a visible difference; they do not fabricate Scrap KG or physical loss. Immutable original receipts remain available alongside compensating adjustments.
- Incoming Sales commitments convert to stock reservations only at receipt, using existing Sales priority and reservation functions. Existing source-selected dispatch remains authoritative. Completed-but-unreceived output remains projected supply; received supply leaves incoming once. Replacement netting applies to future execution, separately from physical output awaiting receipt. The extracted private future-quantity helper preserves existing replacement arithmetic and is not a second reservation engine.
- Quality can amend unreceived quantities and withdraw safely available, physically identifiable, unreserved finished stock using existing source picks and negative movements. Wholly unused stored unfinished lots can be reduced with paired quantity/location movements. New Quality classification requires a new group identity and subsequent physical receipt; original movements/classifications are never rewritten.
- Legacy boolean acknowledgment, legacy Quality rejection, direct unclassified WIP receiving and unintegrated classified-lot processing cannot bypass the new boundary. Legacy immediate Good posting, purchased/external receipts and opening balances remain on their existing paths. No historical synthetic reconciliation/backfill was implemented.

## Interface and API

Warehouse → existing **Production Receipts** tab provides three essential columns, selection/Actions, quantity receipt, location, optional difference note, physical confirmation and on-demand history. The five Operations tabs and existing contextual exports remain. Optional source identification reuses the existing physical-identification dialog. Classified unfinished pools are on demand and remain allocated to original demand.

The authenticated manufactured-output API transports decimal strings losslessly to PostgreSQL numeric. Receipt retries persist the exact actor/factory request in session storage before submission; uncertain outcomes retry the same UUID/body. Confirmed rejection clears the pending retry and presents an actionable error. EN/AR, RTL and a 390px viewport were checked. The implementation reuses existing Warehouse components and the prior approved UX patterns; no unrelated design system/CSS redesign.

## Reconciliation limits

- Reserved, shipped, consumed or physically unidentifiable source quantities cannot be withdrawn. The failed transaction changes neither Quality authority nor inventory. Existing correction proposals/history remain intact; a failed Quality submission is not an approved determination or a fabricated server audit event.
- Phase 2 Production corrections after any receipt/disposition still fail closed; Production cannot override Quality. This phase supports protected Quality reconciliation, not arbitrary post-receipt Production rewriting.
- Classified unfinished lots with prior consumption or a live material request cannot be reduced. Completion/issue/Planning allocation requires Phase 4, so old unclassified processing is blocked.
- One unfinished group retains its original storage location. A subsequent receipt to a different location is rejected; multi-location split/transfer is not silently inferred.
- An existing disposition blocks reclassification. There is no new disposition UI, automatic replacement creation, automatic machine action, Scrap estimate or Sales redistribution.

## Verification

Fresh PostgreSQL 17.11, loopback-only disposable database, complete local chain excluding Export Reader. Existing test Auth shim supplies identities; PostgreSQL executes the real functions, grants/RLS and transactions. This is **not** hosted Supabase Auth/PostgREST acceptance.

| Layer | Result | Evidence |
| --- | --- | --- |
| Phase 3 PostgreSQL | 46 assertions PASS | Exact receipts, rejection/partial amendment, compensation, incompatible/compatible pools, source/demand retention, Sales conversion/dispatch, completed and linked-replacement forecasts, 19-decimal quantity |
| Affected Phase 2 PostgreSQL | 38 assertions PASS | Existing recording, Quality, corrections/security regressions in rollback transaction |
| Concurrent/security tests | 6 groups PASS | Observed lock waits: overlapping receipts, same UUID, Quality/receipt stale revision, permission revocation; private grants/context cleanup and disabled gate |
| Focused Node | 26/26 PASS | Phase 2/3 helpers, Warehouse operations/view tests |
| TypeScript | PASS | Isolated copy, noEmit, incremental disabled |
| Production build | PASS | Isolated optimized Next.js Webpack build, 28 routes |
| Browser | 4/4 PASS | Normal local owner login, five tabs, actual 92+3 receipts, Arabic/RTL390px; no uncaught browser errors or authenticated API failures |

SQL evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P3-SQL-2f8da2a9cf0c4124beb5432b6d6f5768\results`. Input hashes are retained. Owned test database stopped and data removed; scripts/results retained. An initial additional regression had a test SQL quoting typo, corrected before the final fresh passing run.

Browser/evidence root: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P3-Preview-35f2ff47962d407d8652e28509f1854f`. `browser/results.json` includes responses and screenshots. Two actual receipt events total 95 Meter for its test output: 100 recorded, 5 rejected, 95 received, 0 pending; no duplicate submission. Later smoke runs reused those receipts without writing them again. Initial pre-login `/api/data` 401 is expected authentication behavior, not an authenticated error. A menu-state selector and that pre-login assertion were corrected in the harness before final verification.

TypeScript/build logs: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P3-Preview-e59a44a741f94b5a81f97cedb750ebc6`. Final forecast SQL was subsequently checked in the fresh PostgreSQL run; TS/build inputs did not change. Its unused initial preview server is stopped. Automatic approval review rejected deletion of that initial disposable preview directory without a detailed reason; data was left intact rather than retrying deletion.

## Local review

Preview: **http://127.0.0.1:4216/**. Separate isolated application copy; local Auth/Data adapter4298, PostgreSQL55489, all bound to127.0.0.1. Credentials are restricted local files under the preview root (`LOCAL-LOGIN.txt`); no passwords are in the repository or this report. Use its owner account through normal login → Warehouse → Production Receipts → select the row → Actions → Details. Receipt history shows92 then3. Completed receipt is disabled; another deterministic released fixture is needed for a new write test, not a replay of the completed example.

Only disposable fixture code substitutes the private disabled predicate to exercise the future path. The shipped predicate and public capability remain FALSE; late recording remains disabled. The local protocol adapter is a test harness, not production authentication. Original4207/4214 previews were not modified or restarted. This preview's interrupted local processes were restarted without resetting its data; its two receipts were reverified afterward.

## Exact Phase 3 file manifest

Existing files extended (6):

- `HANDOFF.md`
- `src/app/api/manufactured-output/route.ts`
- `src/features/ManufacturedOutput.tsx`
- `src/features/WarehouseOutputs.tsx`
- `src/utils/production-recording-v3.mjs`
- `tests/production-recording-full-app/backend.mjs`

New files (11):

- `docs/manufactured-output-phase3.md`
- `src/features/ManufacturedReceiving.tsx`
- `src/utils/manufactured-receiving.mjs`
- `supabase/migrations/20261024181109_manufactured_output_receiving_v3.sql`
- `tests/manufactured-output-phase3.test.mjs`
- `tests/manufactured-output-phase3/browser.mjs`
- `tests/manufactured-output-phase3/concurrency.mjs`
- `tests/manufactured-output-phase3/integration.test.sql`
- `tests/manufactured-output-phase3/prepare-preview.ps1`
- `tests/manufactured-output-phase3/preview-fixture.sql`
- `tests/manufactured-output-phase3/run-local.ps1`

Prior dirty work preserved, development HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`. Export Reader/Design System unchanged. PRODUCT_DIFFERENTIATORS reviewed; inactive integration does not establish a new customer-facing competitive claim, so unchanged. No hosted access, activation, deployment or Git write. Remote migration alignment is not verified by this local work. Stop after Phase3; do not begin Phase4 or activation.
