# F-021 — Monitor Only synchronization (2026-10-17)

Status: **BLOCKED for remote deployment / complete hosted verification**. Local correction remains implemented; see the dated final release gate below.

## Root cause and correction

LeanProblem previously mounted an uncontrolled defaultChecked checkbox before its asynchronous detail response arrived. Save read that DOM value and could submit false with the latest revision even when the stored value was true. The header also used the older selected-row flag.

The prioritization form now uses controlled authoritative values until a user edits them. It is keyed by factory/problem identity, disables interaction for missing/loading/error data, captures the original revision with the draft, and does not overwrite unsaved edits during background refresh. Untouched/reverted values do not issue commands. An immediate-submit guard prevents duplicate calls. Successful writes remain locked until a newer authoritative revision arrives. Cancel explicitly discards edits and requests fresh detail. The header uses refreshed persisted monitor state. A configured zero threshold remains zero.

Backend permission checks, expected_revision, actor audit, initiative links, verification snapshots and all SQL are unchanged. No migration is needed.

## Files

- src/features/LeanProblem.tsx
- tests/lean-prioritization.test.mjs
- docs/f021-monitor-only-verification.md
- HANDOFF.md (additive current-state note)

## Local validation

89/89 focused Node tests passed: 12 new prioritization regressions plus existing Lean UI/analysis/presentation/API, lazy-history, Maintenance activation and readiness tests. The new cases cover delayed true, initial false, untouched save, both deliberate transitions, threshold-only save, zero threshold, refresh, retained edits/base revision, failed-save recovery, duplicate submits, separate problem instances, malformed/unavailable values, EN/AR markup and refreshed status with immutable initiative evidence.

TypeScript passed. An isolated optimized Next.js webpack build passed, including all 23 pages/routes and Maintenance/Production readiness routes. The default isolated Turbopack build refused a node_modules junction outside its filesystem root; webpack is a documented CLI option and required no application configuration change. Generated configuration changes were confined to the isolated workspace and restored there.

These are component/hook/API tests with local doubles, distinct from the authenticated acceptance below. Stale revision submission retains the original expected_revision and simulated rejection preserves edits. Existing lazy-history tests verify aborting/masking out-of-order responses. The 12 new regressions were rerun after owner login: 12/12 passed; component bytes remained unchanged, so the previous broader validation still applies.

## Release baseline and delivery

Authoritative development HEAD remains bb0d20e5dd433b896dd319f56e75f0d9eb5d2862. Backup verified at C:\Users\Temp\Documents\FactoryLean-Development-Backups\20261017-085018-6e6bd45b.

Isolated release reference: **f021-3279dcf04046**.
Workspace: C:\Users\Temp\AppData\Local\Temp\FactoryLean-F021-Release-20261017-093915.
Component SHA-256: 3279dcf04046c029221dd85dabd255028177cb980a467fe8761cb2ea2bcdf32e.

Before publication, all 665 original project files and Git index/status matched the task-entry baseline. The isolated copy included the existing dirty Maintenance Phases 1-6 baseline. Comparison of all 671 non-Git snapshot files, including essential ignored configuration, found only LeanProblem changed; the regression test was new. The release patch was inspected before copying only the component and test back.

The existing application is Next.js development on localhost:3000, with its server module under the authoritative repository. Its Supabase configuration and project identity were verified as factory-lean-testing / silmfbpjyepalnggwulp. Publication was a focused source/HMR update to this existing local TESTING application, not a Vercel or other remote-host deployment. HTTP GET / returned 200; the emitted client chunk includes the corrected form. No historical clean checkout replaced the current deployed application baseline. The optimized isolated build is validation evidence, not a remotely published artifact.

Maintenance activation was TRUE before and after delivery, unchanged. No flags were changed. No Edge Function, migration or other service was deployed.

## TESTING evidence and limitation

Read-only TESTING checks before/after delivery matched:
- Lean initiatives digest: a737e11a8861fcf94cbabd27e39ba9ff.
- Lean problem settings digest: 1bc92780dadbe781c4997f35f0221a5e.
- lean_problem_settings audit count: 7.
- Maintenance activation: TRUE.

The user resolved the native sign-out confirmation and signed in normally as Ahmed Al Mansour. The application confirmed Factory owner / Full Access for Nova. No credentials were exposed or permissions changed.

An existing synthetic monitor-only Mechanical problem on Extruder 1 is identifiable from the manual acceptance seed and has zero initiative links:
problem 2a0935f7-37ba-40d5-8a66-695eaa42295d, factory bab9b5da-d78d-4be7-b6d4-bb6afc388c3a. Initial revision 1, monitor_only true, threshold 10. Its September occurrence requires the 90-day view. Only this authorized seeded fixture was edited, through normal owner UI.

Authenticated results:

- Initial asynchronous detail resolved to checked true / threshold 10; untouched Save disabled.
- Deliberate true to false persisted at revision 2, header became Occurrence. Audit 0b6076f8-f713-486f-bb17-bb28a9285db9, 07:44:40.9342 UTC.
- Second normal tab saved threshold 10 to 11 without changing false, revision 3. Audit 35a646ac-4f34-4b85-89c8-32a3523dc635, 07:47:46.481878 UTC.
- Original tab retained its unsaved true / 10 draft and original revision while the second tab saved. One stale submission eventually showed a generic failure, with no settings or audit mutation. Exact HTTP status/SQLSTATE was not captured, so this does not prove the stale-specific rejection reason. Cancel discarded the draft and reloaded false / 11. No blind retry was made.
- Owner deliberately restored true / 10 through Arabic UI, revision 4. Audit b35b9889-918b-4d2a-be87-3f05842666b7, 07:52:09.005681 UTC. All three successful audits attribute Ahmed (c94a7c99-7833-51da-aa7c-1edd2592ce71); total settings audits 7 to 10, exactly one per successful save.
- Fresh English mobile detail showed true / 10 and disabled untouched Save. Switching to Bearing failure showed false / 10 and its Verified status, then returning showed Monitor Only. No state leaked between problems.
- English mobile DOM width and scroll width both 375px. Arabic RTL rendered correctly, and the restoration saved successfully in Arabic. Later language/desktop refreshes continued showing Loading history with controls disabled; complete settled desktop/Arabic refresh acceptance remains unverified. No browser warning/error logs were captured. The stale request produced a generic server command error; root cause is not established within this bounded task.

Final read-only database checks: fixture true / 10 / revision 4; settings audit count 10; activation TRUE; all initiatives digest a737e11a8861fcf94cbabd27e39ba9ff and all nonfixture settings digest cfbc389f70b30cd0cfbe766a5d98de86 match the pre-write baseline. Existing initiative verification evidence remains unchanged. Only normal platform scope/access audits and the three documented fixture saves were exercised; no operational Production/Maintenance/Inventory writes.

Evidence directory: C:\Users\Temp\AppData\Local\Temp\FactoryLean-F021-Release-20261017-093915\evidence. Includes restored-monitor-only-mobile.png and stale-response.png. The Arabic loading screenshot is not proof of settled readiness.

Remaining gap: obtain the exact stale-command response and complete a settled desktop/Arabic refresh check. Final owner tab displayed "Data could not be refreshed. The last loaded view is shown." with the restored true / 10 values and untouched Save disabled. The existing generic command error banner also remained from the failed stale attempt. No broader fix, SQL change or additional deployment was attempted. Core F-021 persistence scenarios pass, but full hosted sign-off remains pending these limitations. The temporary second tab was closed, viewport reset, and the owner's session left open in English. Final screenshot: evidence/final-owner-restored-state.png.

## Master defect-register update

F-021: IMPLEMENTED — HOSTED VERIFICATION PENDING. Controlled, identity-scoped prioritization fixes asynchronous checkbox/header state. 89 focused Node tests, TypeScript and isolated build passed; 12 new tests reran successfully. Existing localhost TESTING delivery f021-3279dcf04046 preserves Maintenance activation TRUE. Owner tested both transitions, threshold-only save, persistence, audit attribution and problem switching; seeded fixture restored true / 10 at revision 4 with exactly three legitimate audits. Initiatives/nonfixture settings unchanged. Stale submission failed without mutation, but exact rejection reason and settled desktop/Arabic refresh remain unverified. No migration, remote-host deployment, permission change, commit or push. Historical Simulation QA unchanged.

## Final verification and release gate — 2026-10-17 follow-up

Status: **BLOCKED for remote deployment and complete hosted sign-off**. The checkbox correction remains implemented and locally validated. This section supersedes earlier unresolved observations without deleting their history.

### Refresh and stale-command investigation

The current owner browser opened the Mechanical problem with true / 10, untouched Save disabled, a complete occurrence and no refresh warning. Thus the earlier warning is not continuously reproducible. No further TESTING write test was submitted.

Read-only TESTING PostgreSQL logs establish that the earlier stale submission reached private.lean_command and raised lean_conflict / SQLSTATE 40001 at the problem revision comparison. Between 07:48:29.824 and 07:55:29.995 UTC there were 39,745 such errors, not 39,745 user submissions or successful writes. A second bounded aggregate through 07:59:59.995 counted 63,646 errors in the public-wrapper context. Sample records identify the same authenticator/PostgREST 14.5 backend PID 3307468 and session. A read-only activity snapshot during this follow-up still showed that backend executing lean_command, with ClientRead wait; the tiny per-statement age does not measure the age of the surrounding request.

At 07:55:15.996 UTC a statement timeout (57014) was logged without context. At 07:56:38.633 UTC factory_snapshot explicitly timed out while assembling factory data. The local Next development log also contains factory_command_failed and factory_snapshot_failed. These establish real backend rejection/timeouts during the affected period; browser automation alone is not an adequate explanation. They do not prove which timeout corresponds to every failed Lean-detail request or the internal cause of the repeated executions. No browser network response body/status for the original failure was captured. Exact repeated-execution ownership and its causal relationship to the refresh timeout remain unresolved.

The protected public wrapper delegates directly to private.lean_command, with no SQL retry loop. The installed postgrest-js fetchWithRetry implementation excludes POST retries and does not retry response-processing errors. These observations narrow the investigation, but do not prove the service-side retry mechanism. No backend process was terminated, service restarted, role setting changed, SQL amended or retry policy altered.

The application already maps the exact lean_conflict message to localized leanConflict text. It cannot honestly classify an untyped transport/timeout error as a stale revision. Therefore no speculative UI error translation was added. Backend revision protection demonstrably rejected the command; the user-facing actionable-conflict path is still unverified because a normal conflict response was not observed. Fixing the repeated server execution may require a protected RPC/error-contract change and a new forward migration; that part is stopped under the user's explicit boundary. A bounded follow-up should first identify the PostgREST retry/error handling and capture its actual HTTP response, then propose the minimum non-retrying semantic-conflict contract if needed. Do not blindly repeat stale writes or apply a migration.

### Current state and focused validation

Fresh read-only checks: TESTING has 90 applied migration versions; local has 91, with only Export Reader 20261006072000 absent remotely. This verifies version alignment, not remote content-hash equality. Maintenance activation remains TRUE. Fixture remains true / 10 / revision 4, settings audit count 10. Initiative digest a737e11a8861fcf94cbabd27e39ba9ff and nonfixture settings digest cfbc389f70b30cd0cfbe766a5d98de86 still match. No fixture, account, grant, operational record or activation writes were performed during this follow-up.

Fresh focused run: **90/90 Node tests passed**, including 13 prioritization tests. Added one regression combining a rejected stale save, failed refresh, retained draft, disabled submission, explicit discard/reload and a fresh revision on subsequent edit. These use test doubles and are not hosted SQL proof. Existing out-of-order/abort, initiative preservation, permissions, Maintenance activation/readiness cases remain covered. TypeScript passed in the isolated workspace. A fresh optimized webpack build passed all 23 routes/pages. Authoritative source/config files matched the isolated build input; the extra test added afterward does not affect the application bundle. Isolated generated tsconfig/next-env changes were restored. Full-project/remote state-changing suites were not run.

This follow-up changes only tests/lean-prioritization.test.mjs, this report and the relevant HANDOFF prefix. No application/locale/SQL files were changed. The previous component SHA/release reference f021-3279dcf04046 is unchanged.

### Remote release safety

Vercel metadata lists project factory-lean-platform, ID prj_kl5BPuvmAXAGiJHtPQipqCjZngo2, team team_mTb1cwEwsaixiHdvo6rg3Xix. Deployment-history inspection for that exact scope failed HTTP 403. No installed Vercel CLI was found for the documented fallback. No .vercel project link or vercel.json exists in the checkout.

README identifies an old Sites trial as using the development database; it is not an authorized TESTING target and was not opened or modified. No current hosted TESTING URL/revision or matching Maintenance baseline could be established. Therefore no remote release workspace based on that unknown baseline, deployment, rollback promotion or Git release commit was created. The isolated local validation workspace includes the current dirty Maintenance baseline; it is not automatically approved for remote publication.

Remote deployment: **NOT PERFORMED**. Actual new remote revision: **NONE**. Local HMR delivery remains f021-3279dcf04046. Rollback must first identify the existing TESTING deployment/artifact and preserve that exact compatible revision; never roll back to the old clean Git HEAD or change activation/database history blindly. Hosted acceptance remains incomplete.

### Updated development recovery snapshot

New snapshot: C:\Users\Temp\Documents\FactoryLean-Development-Backups\20261017-122047-f021-52483abc
ZIP: C:\Users\Temp\Documents\FactoryLean-Development-Backups\20261017-122047-f021-52483abc.zip
SHA-256 manifest: snapshot recovery/original-file-hashes.json and adjacent -ARCHIVE-MANIFEST.json / .zip.sha256.
Authoritative backup outcome: snapshot VERIFICATION_REPORT.json and adjacent -ARCHIVE-VERIFICATION.json, generated by full source/copy and streamed ZIP-entry verification.

The owner/SYSTEM-restricted backup parent protects the snapshot, ignored essential local configuration and ZIP. Source, Git metadata, all modified/untracked work, Maintenance changes, 91 migrations and Design System are included. Only regenerable dependencies and Next build caches are excluded and documented. The old 20261017-085018-6e6bd45b backup is preserved. Recovery instructions restore to a new empty directory, not over the active checkout.

No source changes, Git staging/commit/push, remote deployments, migrations or environment changes occur as part of snapshot creation. Final verification results are reported separately after the archive completes.

### Defect-register recommendation

F-021 **BLOCKED** at remote release/complete hosted acceptance. Core checkbox correction passes local and prior owner persistence checks. Confirmed stale SQL guard remains intact; repeated backend conflict execution and snapshot timeouts require separate bounded backend diagnosis before more write acceptance. Hosted target/revision access is also blocked by Vercel 403. Do not mark FIXED AND VERIFIED. DEV, PROD, Simulation, activation, historical migrations and prior QA reports remain untouched.
