# Production Recording V3 — Phase4B-FIX

20 October2026. **READY FOR OWNER VISUAL REVIEW. Owner acceptance remains pending.** Local implementation/verification only; Phase4C/4D and completed-work activation remain deferred.

## Diagnosis before repair

The original4190 preview was a deliberately small component harness: `fixture.tsx` mounted ProductionRecordingV3 in a plain main element, not FactoryApp. Two launcher buttons were expected from that harness, but it was unsuitable as the owner's complete application acceptance environment.

Clicking History was reproduced before edits and unmounted the React tree. The captured exception was `TypeError: Cannot read properties of undefined (reading 'length')` in LeanScrapReview. The harness returned `{startups:[]}` for every Lean API mode; recording_review requires `{rows,total}`. Its History endpoint also returned a generic403 instead of a usable fixture History envelope. The harness now supplies the existing contracts, with a real-component regression verifying an explicit empty History rather than a blank screen.

Independently, the **actual Next application History module rendered correctly** through its real authenticated route and original SQL, showing the seeded25 Good Meter/0.75 Scrap KG/2 WIP Meter. Neither ProductionHistory nor LeanScrapReview required a production rewrite.

The full application had no separately reloadable History destination or normal menu item; its Floor action only opened a modal. Minimal integration now reuses existing `ProductionRecording surface="history"` as the productionHistory root view, mapped to existing Orders permissions. Floor, normal navigation and the recording modal's Recent section reach that same view. Explicit root query links support direct loading, refresh and browser back without inventing a Next pathname.

Actual Edge then exposed two narrow application issues:

- FactoryApp initialized English and persisted it before reading stored Arabic under development Strict Mode. Persistence now waits for initial preference loading. A focused Strict Mode regression and real reload test pass.
- Recovered success displayed an enabled Done button while its supporting receipt/report refresh was still in progress. A click could be ignored by the existing in-flight guard. Done now stays disabled until that work completes; protected receipt/quantity logic is unchanged.

## Complete application and isolation

Verified real application: **http://127.0.0.1:4207/**.

- Factory Floor: **http://127.0.0.1:4207/?view=lines**.
- Production History: **http://127.0.0.1:4207/?view=productionHistory**.
- Component-only regression harness:4190, clearly labelled; not the owner deliverable.

Runtime: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Full-App-Phase4B-FIX-91f4aacd7c7842c2a5c4e61cbd77e9b2`.

The actual application source/assets run in a disposable copy, using installed Next16.3.5 and the ordinary login form, Supabase SSR client, cookies, authenticated API handlers, permissions and protected database functions. No test adapter is imported into production application code. The repository's hosted configuration was identified safely, preserved and never used by this application instance.

PostgreSQL17.11 binds only127.0.0.1:55476. The bounded test-only Auth/Data protocol adapter binds127.0.0.1:4291. The copied application's environment contains only loopback endpoints and a dummy local public key, with no hosted credentials. Signed local sessions are issued only after normal sign-in with generated disposable credentials, stored outside Git under owner-only directory access. The adapter requires a guarded temporary runtime/database identity and rejects production use. SQL executes as authenticated with the verified fixture user's claims and original grants/RLS. Read RPCs are explicitly bounded; only the existing recording writer is admitted. Unrelated operational mutations are intentionally unavailable.

This is **not real GoTrue/PostgREST or hosted authentication acceptance**. Browser requests to nonlocal origins are blocked by the automated tests. No hosted project connector, database command, CLI deployment or hosted login was used. No source environment file, dependency or authentication implementation changed.

The95 original required migrations were installed only in the disposable database; Export Reader was excluded. All96 authoritative migration files are unchanged. Both private Maintenance and V3 activation gates remain FALSE, with V3 schema contract0. The ordinary active-production path is exercised; completed-work recording remains disabled.

Fixture: Local Visual Acceptance Factory - SYNTHETIC, LINE A - Pressure pipes with active PE100 pressure pipe work, idle LINE B - Packaging and an independent machine. The complete real Floor displays their physical states, flow, queue and existing operational controls. Capability, schedule, execution, physical state, shift and recording setup use existing test/production contracts; there is no simulated Floor component replacing FactoryApp.

During preparation a past/current shift occurrence was correctly rejected as OCCURRENCE_NOT_READY because it began before schedule publication. The fixture was corrected prospectively through the existing shift configuration contract, without altering historical timestamps or weakening readiness. Adapter null/GET JSON argument conversion and one missing read-only fulfillment RPC were also corrected locally. Failed diagnostic clusters/logs were preserved; the first failed owned server was stopped. Only the final running runtime is the owner-review environment. These diagnostics are not counted as passing tests.

## Executed verification

| Check | Current result |
|---|---|
| Focused Node,11 files |300/300 PASS, zero skipped |
| Actual installed Microsoft Edge155.0.4283.62, complete Next application |17/17 PASS |
| Actual Edge, isolated real-component/controlled HTTP regressions |26/26 PASS |
| TypeScript, incremental disabled |PASS |
| Isolated optimized Next webpack build after final TSX change |PASS,27 static pages generated |
| Read-only local SQL conservation/receipt/source/gate check |PASS |
| Browser uncaught exceptions / external requests in final suites |0 /0 |

Full-app scenarios include normal owner login; two lines/three machine cards; populated History through real SQL; Floor/menu/recent navigation; direct query links; reload/back; empty/loading/503 with safe retry;640px desktop modal and focus return; authoritative current-shift/disabled-late reader; in-session EN/AR validation; Arabic History and preference persistence; real commit with intentionally lost HTTP response and protected recovery without repost; advisory similarity;390px Arabic full-screen modal/Floor/mobile History without document overflow; separate restricted login with explicit denied page and actual HTTP403 History/reporting responses containing no rows.

Final HTTP evidence includes200 for Auth/data/Fulfillment/Lean/History/status/reporting/shift-work/unfinished;401 only before normal login;503 only browser-injected History failures;403 only the restricted checks. Final suites have no unexpected API or uncaught rendering errors. Chrome/Firefox were unavailable and remain PENDING. Browser automation does not certify physical mobile keyboards, screen readers or hosted services.

The component suite preserves exact-decimal submission, mandatory WIP/source controls and conservation inputs, shift expiry, edit denial, recovery/retry identity, storage failure, advisory duplicates, translated success/error messages, keyboard trapping, reduced motion and390px Arabic layout. Its enabled-completed fixture is explicitly synthetic; it does not activate the real SQL gate.

Seed quantities were25 Good Meter,0.75 Scrap KG,2 WIP Meter, reserved0. Three separate controlled diagnostic/final recording intents each added1.25 Good Meter and0.05 Scrap KG. Final totals: **28.75 Good Meter,0.90 Scrap KG,2 WIP Meter, reserved0, available28.75 Meter**, four entries including the seed. Each request UUID has exactly one entry/receipt. Final recovery issued one POST and then one protected status read; no recovery repost occurred. Good equals stock ledger deltas and finished-source credit. No physical label or identified stock was invented. Diagnostic writes are retained as explicit disposable evidence, not deleted or passed off as retries of one quantity.

No SQL/business/API contract changed in this fix, so the earlier Phase4B fresh/upgrade/concurrency evidence remains historical applicable evidence rather than newly executed counts. No unrelated Warehouse/Quality/security audit was repeated. PRODUCT_DIFFERENTIATORS was reviewed; these acceptance repairs add no new competitive capability, so no edit was needed.

Commands: `node --test` with production-recording-ui, production-reporting-api, production-shift-work, production-late-recording, production-corrections, production-consumers, lazy-history, permission-preview, factory-navigation, navigation-overlay and production-history test files; the two browser scripts; `tsc --noEmit --incremental false`; isolated `next build --webpack`; portable psql with `verify.sql` under READ ONLY/ROLLBACK.

Evidence:

- Runtime `edge-evidence/results.json`, screenshots, `conservation-results.txt`, final preservation manifest.
- Component final run: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Phase4B-Visual-b2410bb3-58d8-4782-9efb-441df51845c4`.
- Node final log: `%TEMP%\FactoryLean-Phase4B-FIX-node-results.txt`.
- Build location: `%TEMP%\FactoryLean-Phase4B-FIX-build-location.txt`.

## Exact task manifest

Modified existing files, relative to the verified post-Phase4B snapshot:

1. `src/components/FactoryApp.tsx` — existing History view/menu/query integration and preference-initialization race.
2. `src/features/types.ts` — optional shared History navigation callback.
3. `src/features/ProductionRecordingV3.tsx` — common History destination from Floor/Recent; safe Done availability.
4. `src/utils/permission-preview.mjs` — existing Orders grant mapping for History.
5. `tests/factory-navigation.test.mjs` — URL navigation harness and Strict Mode Arabic regression.
6. `tests/permission-preview.test.mjs` — History permission mapping/no privilege grant.
7. `tests/production-recording-ui/preview.mjs` — correct Lean/History mock envelopes.
8. `tests/production-recording-ui/browser.mjs` — exact blank-screen regression.
9. `docs/production-recording-v3-phase4b.md` — factual failed-owner-acceptance update/link; historical evidence preserved.
10. `HANDOFF.md` — bounded current milestone and review instructions.

New files:

11. `tests/production-recording-full-app/prepare.ps1` — guarded isolated database/application preparation.
12. `tests/production-recording-full-app/seed.sql` — synthetic operational fixture using existing contracts.
13. `tests/production-recording-full-app/backend.mjs` — local-only Auth/Data protocol fixture, original SQL authorization.
14. `tests/production-recording-full-app/browser.mjs` — complete-app Edge acceptance.
15. `tests/production-recording-full-app/verify.sql` — read-only conservation/receipt/gate evidence.
16. `tests/production-recording-full-app/README.md` — reproduction, isolation and owned-server stop instructions.
17. `docs/production-recording-v3-phase4b-fix.md` — this report.

## Preservation and stop

Pre-Phase4B758-file recovery ZIP was reverified (SHA2562C5DD17938106488FC7447D4F353992CDB2A8B5905B34D3124C08BBEB37F59E2). Before this repair, a separate779-file recovery was created and every ZIP entry rehashed: `C:\Users\Temp\Documents\FactoryLean-Development-Backups\Phase4B-FIX-PreRepair-20261020-095133-e95dcab5`, ZIP SHA2565290208AF881FE811397E6822F40E3227E0795CE4CE74299CEDD643D5F9E98D1. Ignored confidential configuration/index were protected separately with owner-only access. Neither backup was overwritten.

Final preservation compares every779 baseline file and permits only the17 task files above. Existing Phase1–3D, Maintenance/F-021, Export Reader, all96 migration bytes, canonical untracked Design System, environment/link metadata, HEAD/main/index and unrelated work remain unchanged. No staging, commit, push, reset, stash, branch switch, deployment or remote access occurred.

Automatic approval review rejected one combined failed-cluster cleanup/start command with “blocked by policy”; no further reason was supplied and it did not run. The safer path stopped only the verified owned failed server and retained its diagnostic data. No deletion workaround was attempted.

The full app/adapter/database remain running locally for review. The in-app browser is signed in normally as the local synthetic owner. Close the modal to inspect Floor; use Record Production, switch EN/AR, open History from Floor/menu/Recent, reload the History link and inspect390px layout. If another browser needs login, use the owner-only runtime `LOCAL-LOGIN.txt`, never hosted credentials. Save changes only in this explicitly disposable fixture.

Owner visual approval, hosted authentication/PostgREST acceptance, real operational data, Chrome/Firefox and physical mobile/accessibility acceptance remain pending. No completed-work activation, Phase4C/4D, hosted deployment or next feature is authorized. **STOP for owner review.**
