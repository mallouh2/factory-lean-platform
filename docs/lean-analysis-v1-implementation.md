# Lean Analysis V1 implementation and verification

Completed implementation and automated/live verification on 2026-10-05 (Asia/Riyadh). Continued the clean development checkpoint `60ee7d3911a32930afaf319f331761d711f65555` (76 migrations, 612 Node tests). Work remains uncommitted. No commit, push, DEV connection or main change. User manual acceptance/freeze and real-device touch remain open.

## Architecture and authoritative truth

The existing Production Loss, Downtime, Recording/WIP, Shift, Sales, Maintenance, Audit and Permission Package models remain authoritative. Lean aggregates closed engineer-approved stops using existing actuals or saved segmented loss estimates; it does not introduce an alternative Production Loss formula. Original operator explanations remain separate from engineer-approved causes and notes. Unknown segmented Product attribution stays unknown.

Forward migrations add process standards, actual startup identities, reviewed abnormal Scrap observations, problem settings, initiatives/actions/templates, saved comparisons, immutable runtime contexts and private command retry/source-revision records. Composite factory references, RLS, guarded RPC transitions, expected revisions, authenticated actors/server times and append-only Audit protect state. Generic/direct writes cannot bypass transitions. Browser-provided comparison evidence is rejected.

`/api/lean` uses lazy bounded readers outside `factory_snapshot`; list/history pages are 25, library readers at most 100 and Audit pages 50. Full-period metrics collect bounded pages before normalization/sorting. Comparison sources are capped at 100 pages/10,000 rows and reject oversized requests rather than quietly truncate. Batch Sales context uses authoritative readiness/risk and typed affected quantities; Maintenance is read-only and independently permission checked.

A JWT-verified TESTING Edge Function (`lean-comparison`, deployed version 4) collects coherent authoritative sources and computes comparison evidence with the same shared domain functions as the API. Source revision checks protect both collection and persistence. Only the trusted service evidence writer can freeze an official baseline, save a manual comparison or store human verification.

Immutable production/machine/OPEN-transfer/pause/shift/timezone contexts supply runtime. Actual active production and operating `evaluateFlow` are required; pauses, blocked routes and borrowed-home gaps are excluded. Buffer expiry and actual-start boundaries split intervals. Physical machine state and Planning timestamps are not rewritten.

## Identities, recording and review

- Downtime: factory + **Machine + Approved Cause**. Another machine is another problem.
- High Scrap without downtime: factory + **Line + Product + Approved Cause**.
- An explicitly reviewed same-Product/context/time link to a physical stop merges Scrap into that stop occurrence. Temporal proximity alone does not claim causality. Uncertain attribution is labeled Associated Scrap.
- Frequency counts distinct events; 2+ within the selected period is recurring. No score combines hours, kg, pieces or meters.

New Scrap is **kg only**. Produced weight is **Good + newly recorded WIP**, multiplied by the explicit kg per matching configured production unit; manufactured kg output uses 1 kg/kg. Weight is frozen with each declaration. Missing/mismatched weights remain unknown. Separate discarded production quantity conserves WIP in its original unit. Legacy values remain readable; no historical mass is invented. Existing Good credits finished stock immediately, exactly once; Scrap is never stock or completed demand.

Each Line/Product may have an explicitly approved running percentage and startup kg standard. The allowance is shared across declarations for one actual startup ID, never allocated by shift. Expected startup remains in total Scrap without opening a problem. Running Scrap excludes legitimate allowance; excess startup remains abnormal. Monthly observed kg/startup is separate and may propose a change, but only an authorized explicit approval updates the standard. Missing standards are reported.

Recording completion prompts once for abnormal Scrap: preliminary reason, approximate time, what happened and response/how it ended. Engineer review sets Approved Cause and its own note without overwriting the original observation. The shared factory-editable cause library preserves existing reasons and seeds 30 pipe-process causes. Archived definitions retain history.

## Interface and improvement lifecycle

One primary Lean page has five summary cards, one consolidated filter area, independent sorting and paginated problem rows. The UI acceptance follow-up removes column-filter duplication, adds independent metric attention, preserves background refresh context, fits the desktop table and retains mobile cards. Full current details and superseding validation: [Lean UI acceptance verification](lean-analysis-ui-verification.md).

The full-page drill-down refreshes metrics from current sources, shows occurrence evidence and original/approved observations, Shift Details (frequency, loss, Scrap kg/rate, typed output and response/stoppage duration), Sales/delivery context, Maintenance, actions, comparisons and Audit. Original downtime response is unknown where never captured; engineer notes are not repurposed as operator responses.

One active initiative per problem contains multiple required actions, each with owner, required editable due date, type and progress. Owners can update their own progress/due date; management controls ownership and reasoned cancellation. Cancelled actions remain in history and stop blocking completion. Status derives Open → In Progress → Awaiting Verification → human Verified. One official verification covers the whole initiative, including all actions.

Suggested actions include editable bilingual templates with optional due days and previous actions for the cause across all outcomes, including failed/inconclusive attempts. Suggested dates remain editable. Monitor Only keeps the problem visible and creates no initiative automatically.

## Equal-runtime verification and recurrence

The official baseline runs from the first occurrence to the last occurrence's effective endpoint. It includes the final instantaneous occurrence and declaration exactly once; subsequent/manual adjacent windows retain half-open boundaries. Runtime is measured for the same Product and relevant machine/line. After all required actions complete, the system collects the same comparable operating runtime, clipping the final interval exactly.

Worked example (automated): 40 runtime hours, 3 occurrences, 95 loss minutes, 80 kg associated Scrap, 2,000 kg produced weight. This gives 0.075 occurrences/hour, 2.375 loss minutes/hour and 4% Scrap Rate. With only 15 comparable hours after completion, verification is incomplete and shows **25 hours remaining**. At 40 hours it compares each dimension separately. The configurable initial threshold is ±10%; conflicting dimensions remain visible, never collapsed into a score. Missing after-output weight leaves Scrap Rate unknown even if runtime is complete.

An authorized human confirms Improved / No Meaningful Change / Worse / Insufficient Data with a note. Incomplete exposure permits only Insufficient Data. Manual cutoff/exposure previews and optional saved comparisons cannot change action or official verification state.

Following a human Improved result, the reader watches the same identity for 30 calendar days. One new distinct occurrence leaves the result unchanged; 2+ displays Recurred After Verification. The watch is independent of the selected display period and paginated timeline. Previous initiatives and evidence remain intact.

## Permissions and packages

Five new registry keys: `lean:view/create/edit/approve` and `lean_standards:edit`. Effective authority remains the package/direct-grant union; no title check or View As authorization.

Default Owner package receives all five. Production Manager and Production Engineer receive Lean view/create/edit and process-standard edit (including abnormal cause review), not automatic official verification authority. Planning Engineer, Maintenance, Warehouse and Sales receive Lean view. Existing protected approved owners receive the five corresponding direct keys to preserve administration/grant ceilings. Other direct grants and package assignments are retained.

Create-only Lean users can materialize default problem identity to create an initiative without gaining monitor/threshold edit authority. Action ownership does not permit cancellation/owner changes; verification requires approve. Membership, factory/platform scope, RLS and package ceilings remain enforced.

## Migrations and Git

Local/TESTING **79/79**, every version/name matched after final verification. All **76 original SHA-256 hashes unchanged**. Three TESTING-only forward migrations:

1. `20261005064954_lean_analysis_v1.sql` — model, recording, runtime, protected readers/commands, defaults.
2. `20261005071129_lean_context_truth.sql` — original/engineer context separation, batched Sales truth and source consistency.
3. `20261005072541_lean_baseline_boundaries.sql` — effective final baseline endpoint and create-only identity authority.

Applied SQL preserved; no applied migration edited. Branch/remote refs match baseline. HEAD remains `60ee7d3911a32930afaf319f331761d711f65555`; main remains `afd2674993df4d9bedda5cf35dc5b75de3cba4b0`. DEV deliberately not queried or changed. Build-generated next-env/tsconfig restored to Git's canonical worktree content. Screenshots/build artifacts/logs remain outside tracked sources or ignored.

## Verification results

| Check | Final result |
| --- | --- |
| Focused Lean domain + rendered UI | **47/47 passed** (39 domain, 8 UI) |
| Full Node regressions | **659/659 passed**, 0 failed/skipped |
| TypeScript | Passed, noEmit/incremental false |
| Production build | Passed, isolated .next-check |
| Rollback SQL | **21 suites passed** on final schema |
| Local/TESTING alignment | **79/79**, all original 76 hashes preserved |
| Existing-account live TESTING | A–H below passed |
| Desktop/mobile EN/AR/RTL | Browser evidence inspected; no mobile page overflow |

SQL suites: Lean Analysis; Downtime; Recording; History; Execution; WIP; Shift windows; Maintenance; Sales fulfillment/stock sources; Permission Packages; snapshot contract/authorization; lazy history; Internal Production; Supply; Warehouse master/manual purchasing; requester/supplier; Planning generic-write guard. All end in rollback; latest Lean suite additionally forces deferred constraints before rollback. Its dedup fixture uses legitimate retrospective approved Downtime, not fabricated runtime. Internal Production fixture now owns a deterministic manufactured Product instead of selecting an unrelated BOTH-sourced Product.

| Required behavior | Evidence |
| --- | --- |
| Recurring identity; same cause/different machines | Domain + final rollback SQL |
| Independent High Scrap; linked stop dedup | Domain + final rollback SQL + live review |
| kg-only/matching-unit weight/WIP conservation | Domain + Recording/WIP SQL + live recording |
| Expected/excess startup; one allowance/event | Domain + SQL + live same-startup declarations |
| Observed standard does not drift | Domain + protected SQL + explicit live approval |
| Completion prompt/original observation retained | Rendered UI + live operator/engineer workflow |
| Shifts/output/response duration | Domain + Shift/Downtime SQL + live details |
| One initiative/multiple required actions | Domain + SQL + live lifecycle |
| Reasoned cancellation preserves history | SQL + rendered UI + live cancelled action |
| Same Product/equal runtime/clipped endpoint | Domain + SQL + live official comparison |
| Insufficient exposure/human-only verification | Domain + SQL + live Insufficient/Improved outcomes |
| Manual comparison independent | Domain + SQL + live optional save |
| Two-event 30-day recurrence | Domain + expanded SQL + live one/two watch |
| Monitor visible/no automatic initiative | Domain/UI + SQL |
| Sales/Maintenance remain contextual | API/source checks + respective rollback regressions |
| Person/package authority/grant preservation | Contract/SQL + package regressions + QA restoration |
| EN/AR/RTL/mobile/required dates | Rendered UI + actual browser interactions/screenshots |

## Live TESTING A–H

Used existing Nasser/Nova; no account created. Isolated QA Product `f83a6a83-ec29-416b-943a-7b3b70482327`, line `2b24e0b0-61de-4bc7-af91-877d82c4be6e`, machine `328dc03a-2565-4e8d-a285-fc51d57f3091`, actual Product Item `4e5f32a5-5f8a-4dc5-929f-7d7529311696`. Existing machines, orders, plans and transfers were not used as mutation fixtures.

A. Approved 5% running/20kg startup standard and actual startup ID. UI recorded Good100 + WIP20 at 2kg/piece, Scrap30 with startup20: produced240kg, abnormal running rate4.17%, no problem, Good credited once.

B. UI recorded startup-only5kg against the same startup. Cumulative25kg exceeded20kg; completion prompt preserved Unknown preliminary cause and original explanation. Engineer approved Cooling Water Low without replacing original text.

C. Reviewed a second normal-recording QA event with Good100/Scrap30. Same Line/Product/cause formed one recurring problem; Shift Details and read-only empty Sales/Maintenance context loaded.

D. Created multiple actions, completed progress, cancelled one with a required management reason, and preserved both. Original early QA initiative `cb823139-a56e-4ab0-ad9b-1fb04e4ed5db` exposed the final-boundary defect. It was retained unchanged and human-closed as Insufficient Data after the correction; no false improvement or rewritten evidence.

E. Corrected initiative `948377e0-a289-4966-9167-2cc84c382c28` froze 0.0669711111111111 operating hours, 2 occurrences, 35kg associated Scrap and 200kg produced within its own baseline (17.5%). Completed a manual action and bilingual template-derived action. Template due days3 proposed Oct8 and remained editable; previous inconclusive actions were offered.

F. Independent manual40h preview showed incomplete exposure and was saved once without changing official state. Then genuine comparable after-runtime completed the small QA baseline. UI human confirmed Improved at 07:46:48.220661Z on occurrence/associated-Scrap evidence, explicitly noting QA-only and unknown after Scrap Rate. This does not claim real factory savings.

G. Two subsequent distinct protected QA recordings/reviews: watch frequency1 → not recurred; frequency2 → recurred. Official evidence/history stayed intact. Refreshed detail/table agree: frequency4, associated37kg, produced444kg, rate8.33%. Total physical Scrap67kg includes normal startup/running Scrap; finished stock202 pieces and WIP20 remain separate.

H. Monthly observed startup25kg did not change approved20kg. Explicit qualified approval retained20kg while recording the observed October proposal25kg. EN/AR desktop1440/mobile390 and full detail inspected. Temporary five Lean QA grants then removed: all **92 original permission rows**, including actor/time metadata, matched original digest `1114e254a2a2f9cc2a2d9bf3d6d84d90`; no QA package assignment remains. Genuine QA production, actions, comparisons and Audit are retained.

Screenshots: `C:\Users\Temp\AppData\Local\Temp\factory-lean-analysis-20261005`: desktop-en.png, desktop-ar.png, mobile-en.png, mobile-ar.png and detail-mobile-en.png. Canonical proof uses viewport capture; browser full-page RTL capture had a canvas framing artifact. Main desktop table intentionally contains a horizontal scrollbar. Mobile content had no horizontal page overflow and new visible form controls had labels. Website remains running at localhost:3000; refreshed existing account correctly no longer shows Lean without a permanent grant/package.

## Remaining limits and next work

- No historical comparable runtime before capture; no sensor telemetry or invented exposure from calendar time.
- Legacy mass, ambiguous mixed-Product loss, missing unit weights/standards and zero output remain explicit unknowns. No historical Scrap backfill.
- Library selectors show at most the first100 definitions/people; library browsing/history are bounded and paginated. Comparison cap fails explicitly.
- Runtime may be complete while after-produced weight is absent; independent metrics remain unknown rather than auto-verifying a rate.
- No employee scoring, AI root-cause conclusions, automatic Planning changes, action-effect isolation, costing or proven savings.
- Publication-stage existing advisor warnings remain deferred; no fatal advisor findings were found.
- User manual acceptance/freeze, real-device touch and legitimate ongoing permission/package assignment remain next. No unresolved business decision.

Official product research: [MachineMetrics Production Analytics](https://docs.machinemetrics.com/docs/product-guides/production-analytics-guide/), [Downtime/Quality](https://docs.machinemetrics.com/docs/product-guides/downtime-quality-guide/), [LEI PDCA](https://www.lean.org/lexicon-terms/pdca/). Applied period presets, independent loss dimensions, historical comparisons and verification. PRODUCT_DIFFERENTIATORS section19 records the connected loop as implemented with acceptance pending, not unique technology or proven financial benefit.

## Exact task files

- `HANDOFF.md`
- `docs/PRODUCT_DIFFERENTIATORS.md`
- `docs/lean-analysis-v1-implementation.md`
- `src/app/api/data/route.ts`
- `src/app/api/lean/route.ts`
- `src/app/api/production-history/route.ts`
- `src/app/globals.css`
- `src/components/FactoryApp.tsx`
- `src/features/CenterLossProfile.tsx`
- `src/features/DowntimeCapture.tsx`
- `src/features/LeanAnalysis.tsx`
- `src/features/LeanLibraries.tsx`
- `src/features/LeanProblem.tsx`
- `src/features/LeanScrapReview.tsx`
- `src/features/LossImpactReview.tsx`
- `src/features/ProductionHistory.tsx`
- `src/features/ProductionOrdersV2.tsx`
- `src/features/ProductionRecording.tsx`
- `src/locales/ar.json`
- `src/locales/en.json`
- `src/utils/lean-analysis.mjs`
- `src/utils/lean-comparison.mjs`
- `src/utils/lean-contract.mjs`
- `supabase/functions/lean-comparison/index.ts`
- `supabase/migrations/20261005064954_lean_analysis_v1.sql`
- `supabase/migrations/20261005071129_lean_context_truth.sql`
- `supabase/migrations/20261005072541_lean_baseline_boundaries.sql`
- `tests/downtime-capture.test.mjs`
- `tests/downtime-capture.test.sql`
- `tests/internal-production.test.sql`
- `tests/lean-analysis.test.mjs`
- `tests/lean-analysis.test.sql`
- `tests/lean-ui.test.mjs`
- `tests/permission-packages.test.sql`
- `tests/production-history.test.mjs`

35 task files; no environment files, credentials, screenshots or generated build output included.
