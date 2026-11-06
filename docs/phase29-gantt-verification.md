# Phase 2.9 — Gantt drag-and-drop verification

6 November 2026, Asia/Qatar.

**GANTT VERIFIED — READY FOR GIT CHECKPOINT REVIEW.**

The owner has given general visual approval of the integrated frontend. This task did not reopen those designs. The approved Quality calculation, Maintenance fixes and other frontend implementations remain preserved.

Evidence: C:/Users/Temp/AppData/Local/Temp/FactoryLean-Phase29-37d5e6d5.

## A. Root cause and correction

A native drag over a line occupied by active work raised **RangeError: Invalid time value** in planningMessage/onDragOver. A read-only reproduction against the earlier review implementation captured trusted drag events and the browser stack before the correction.

The authoritative operational projection intentionally represents unknown occupancy bounds as negative/positive Infinity (src/utils/planning.mjs:164–165). This correctly protects capacity. The Planning component tried to convert those values into ISO dates when constructing the conflict explanation.

**Minimal fix:** src/features/ProductionPlanning.tsx now formats only finite conflict bounds. An unknown start stays unknown; an unknown finish uses the existing localized “Finish unknown” label. The production-order identity and conflict rejection remain visible. No scheduling validation, capacity calculation, timestamp, API mapping or business rule changed.

Two actual-component interaction regressions in tests/planning.test.mjs reproduce the open-ended conflict in EN and AR. They failed with the original RangeError before the fix, then passed while asserting a blocked target, localized order/unknown-finish feedback, zero scheduling commands and unchanged input state.

Native post-fix checks reproduced the protected rejection in both languages without browser errors or API commands. The raw exploratory harness reports “no valid drop” for these negative cases; protected-native-results.json records the verified expected rejection. This is not counted as a successful scheduling drop.

## B. Gantt acceptance matrix

| Scenario | Browser result | API / database result | Persistence | Status |
|---|---|---|---|---|
| Eligible unscheduled work, EN1440 | Trusted native pointer drag, valid preview, release/drop | Actual plan_product_item HTTP200; saved line/start/finish exactly match preview | Row remains scheduled after reload | PASS |
| Eligible unscheduled work, AR1440 | Same native interaction in RTL | HTTP200; exact preview/DB match | Reload confirmed | PASS |
| Scheduled unstarted work moved, EN/AR1440 | Native drag opens required reason/review dialog; reason submitted | Protected revision HTTP200; correct before/after times, actor, reason and one new revision | Reload confirmed in both languages | PASS, 2 cases |
| Mobile EN/AR390 | Supported order drawer: line/start selection and Save Schedule | Actual HTTP200; stored schedule and initial revision checked | Reload confirmed in both languages | PASS, 2 cases |
| Open-ended active capacity conflict | Native desktop EN/AR rejection displays order and unknown finish | No scheduling command; no false success | No mutation from gesture | PASS, 2 cases |
| Started execution | Existing interaction guards retained; protected HTTP exercised | HTTP422 planning_already_started | Order digest unchanged | PASS |
| Locked work | Existing drag/edit guards retained; real public lock used on task fixture | HTTP422 planning_locked | Unchanged by rejected revision | PASS |
| Conflicting line capacity | Protected revision requested an occupied interval | HTTP422 planning_overlap | No order changes | PASS |
| Existing confirmed Maintenance reservation | Used a retained durable synthetic reservation; no gate activation | HTTP422 maintenance_capacity_reserved | No order changes | PASS |
| Invalid timestamp/window input | Malformed timestamp rejected by route | HTTP422 | No order changes | PASS |
| Stale Planning fingerprint | Deliberately obsolete fingerprint submitted | HTTP409 planning_changed | Winner remains unchanged | PASS |
| Material-custody restrictions | Physical issue changes fingerprint; explicit acknowledgment remains required | Waiting stale replan rejects; missing custody acknowledgment returns HTTP422 planning_confirmation_required | No rejected schedule mutation | PASS |
| Insufficient / missing authentication | Real isolated app requests with existing synthetic viewer / no session | HTTP403 / HTTP401 | No order changes | PASS |
| Pointer cancellation and scrolling | Native vertical edge down/up; center stops; horizontal edge scroll; Escape/release stabilizes position | No scheduling command on cancellation | Original unscheduled item unchanged | PASS, EN/AR |

Six successful browser scheduling actions were committed: two initial native drops, two native reschedules and two supported mobile form schedules. Those are distinct from the protected rejection checks and setup commands.

Initial native scheduling observed vertical movement of 424/425 pixels, proving the target was reached through the actual drag-scrolling path. Dedicated cancellation checks observed downward movement of 306/287 pixels, stopped in the center, returned upward and stopped after Escape/release. Horizontal edge movement was 1,033/1,069 pixels. Horizontal overflow was exercised with a narrow viewport using a desktop pointer; mobile acceptance uses the supported drawer, not a claim of touch-drag support.

The previous automation's dragTo calls mixed source/target scrolling and did not establish successful persistence. Using real mouse down/move/up, the application's edge-scroll path and the actual preview established trusted dragstart/drop behavior and successful authoritative writes. No injected DragEvent, programmatic scheduling-state update or mocked response was counted as native acceptance.

Twelve pre-existing unrelated orders in the isolated connected factory remain byte-for-byte equal to their before-native snapshot. No cascading move occurred.

### Real concurrency

**4/4 real PostgreSQL overlapping-session races passed.** Each observed the second session waiting on a lock while the first held its real protected write:

1. Two planners request the same line interval: one succeeds; the other rejects and stays unscheduled.
2. Competing protected revisions: stale second fingerprint rejects; it cannot overwrite the winner.
3. Identical concurrent retry UUID: both receive the same result and only one revision is added.
4. Physical material issue while replanning waits: the stale custody fingerprint rejects the replan.

These are genuine independent authenticated SQL/RPC sessions, not sequential requests described as races. Material setup used the existing public configuration/reserve commands and one bounded invocation of the normal preparation processor in the disposable cluster. No background worker or release override was started.

## C. Fresh test results

| Check | Result |
|---|---|
| Focused Gantt/Planning/API/permission/material/Maintenance suites | **244/244 PASS**, zero skips |
| Full Node suite | **1,489/1,489 PASS**, zero skips |
| Specific Planning component suite | **77/77 PASS**, including the two new regressions |
| TypeScript | PASS, noEmit / incremental false |
| Optimized isolated webpack production build | PASS |
| Successful native desktop scheduling/rescheduling | **4/4 PASS**, EN/AR |
| Supported mobile scheduling alternative | **2/2 PASS**, EN/AR390 |
| Native protected conflict feedback | **2/2 PASS**, EN/AR |
| Scrolling / cancellation scenarios | **2/2 PASS**, EN/AR |
| Protected real-application HTTP rejection checks | **9/9 PASS**, including unauthenticated extra check |
| Real concurrent-session races | **4/4 PASS** |
| Unrelated original order rows | **12/12 unchanged** |

Initial test/harness corrections are retained in evidence. The new regression was first registered before its asynchronous fixture initialization; that harness placement was corrected, after which the expected pre-fix failure was the actual RangeError. A rejection harness initially expected HTTP409 for missing material acknowledgment; the established route correctly returns validation HTTP422. Its expected classification was corrected without changing product behavior or replaying already committed setup unnecessarily.

Actual application HTTP used the synthetic local signed-session adapter and original authenticated public database commands. It is not hosted Supabase Auth/PostgREST/RLS acceptance. No hosted readiness or new standalone SQL-suite count is claimed.

## D. Files changed

1. **src/features/ProductionPlanning.tsx** — finite-bound guards in conflict-message date formatting only.
2. **tests/planning.test.mjs** — EN/AR regression cases for open-ended active occupancy and no-write rejection.
3. **HANDOFF.md** — current milestone, owner approval, test results and runtime boundaries.
4. **docs/phase29-gantt-verification.md** — this acceptance report.

No CSS, translation, shared calculation helper, API route, migration or unrelated feature changed. Drag-source fading remains excluded.

The existing owner-review source on port29511 received only the tested Planning display correction, after its prior hash was checked against the pre-change snapshot and its old file was preserved. This was a local preview update, not a hosted deployment or database change. A read-only native conflict smoke against that updated preview shows localized feedback without an exception.

## E. Safety and preservation

- Main branch **development**, HEAD **bb0d20e5dd433b896dd319f56e75f0d9eb5d2862** unchanged. No index/ref/history mutation.
- New verified **1,309-file pre-change snapshot**, including the post-Quality and Maintenance corrections:
  C:/Users/Temp/Documents/FactoryLean-Recovery/phase29-37d5e6d5.
- Existing recovery packages, latest donor sources and unrelated uncommitted work preserved.
- All **153 migration files** unchanged. No migration application, schema change, grant, account creation or gate activation.
- The prior review preview at 29511 and its actual database binding were checked. The database was copied with an online PostgreSQL backup into a new task cluster; the original services were not stopped or reset.
- Write-capable verification used only **127.0.0.1:29529 / factory_lean_quality_local / evidence-directory/data**; adapter29530, app29531. Actual server-side destination was checked by the runtime and within writing adapter transactions.
- All manufactured, Maintenance, historical and ordinary-late activation settings remained disabled. Maintenance conflict tests reused already persisted synthetic reservations.
- Phase 2.9 test app, adapter and database are stopped; data/evidence retained. Existing review app29511/Auth29510/DB29509 remain running.
- No hosted modifications, deployment, commit, push, branch switch, reset, stash, rebase, Simulation or Git checkpoint.

Final inventory: **87 modified tracked / 409 untracked status entries**; index unchanged. Exact preservation checks are recorded in final-preservation.json in the evidence directory. Incremental whitespace verification passed.

Review URL: **http://127.0.0.1:29511/**. Existing synthetic login instructions remain at C:/Users/Temp/AppData/Local/Temp/FactoryLean-Phase28-Continuation-85fcca12/LOCAL-REVIEW-LOGIN.txt.

## F. Final readiness verdict

**GANTT VERIFIED — READY FOR GIT CHECKPOINT REVIEW.**

Recommend a final scoped Git checkpoint preparation review of the combined dirty tree, preservation manifest and intended file groups. No checkpoint was executed. This conclusion is local Gantt acceptance and does not claim deployment or hosted production readiness.
