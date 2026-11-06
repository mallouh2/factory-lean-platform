# Production Recording V3 — Phase 3C

20 October 2026. **LOCAL COMPLETE WITH PENDING ACCEPTANCE.** Scrap/Quality/Lean backend consumer integration and the owner-approved focused initiative-baseline compatibility amendment are implemented and locally verified. No unresolved local Phase3C blocker was found. Late recording remains disabled. No Phase 3D/4, UI, export integration, hosted access, activation or Git write is included.

## Authority and preservation

Continued the approved M1/M2/M3A/M3B and correction-approval foundation on development, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`. Initial state: 731 tracked/untracked project files, 27 modified tracked files, 133 untracked individual files, zero staged and 95 local migrations. Existing unrelated work must remain preserved.

Reviewed AGENTS/HANDOFF, the four phase reports, correction foundation and UX standard, external Phase0 CONTRACTS section10 / DATA_MODEL section8 / M3 migration matrix, and the sealed Phase2 recovery readiness report. The latest owner brief narrows the earlier broad Phase3 readiness scope: **no screen implementation, operational dashboard rewrite or Excel/Print wiring here**.

One new forward migration: `20261019124124_production_scrap_lean_consumers_v3_m3c.sql`. The local repository now has **96** migrations; the disposable chain executes 95 because Export Reader is excluded. No previous migration is amended. Remote histories, current remote activation and deployment state were not queried.

## Dependency map and gaps

| Consumer | Verified prior behavior / gap | Phase3C treatment |
| --- | --- | --- |
| M2 writer, source capture, correction command | Official entry fields change only through existing protected posting; pending proposals are private and ineffective | Unchanged; regression-tested, including source/WIP/Quality/Sales races |
| M3A/M3B History and production summaries | Correct effective values/periods, but reviewed Scrap could follow a later correction automatically | Shared view withholds stale reviewed KG; additive `observation.review_current` is retained by the existing parser. Existing filters, pagination, precision and API contracts stay intact |
| `lean_command` Scrap observation | Existing exact-only form cannot represent approved period-only evidence | Add the Phase0-required SHIFT_PERIOD form to the existing command/API whitelist; copy authoritative entry occurrence/bounds server-side, keep exact occurred_at NULL and reject exact downtime links/forged periods |
| `private.lean_occurrences` | NULL observation times could disappear; original current KG could appear reviewed after a correction | Preserve source/review identity, expose precision/period/provenance and separate current-review eligibility; changed current quantities remain unknown until existing authorized re-review |
| `lean_read` entries/occurrences/problems/pending | Exact created_at/occurred_at filtering and assumed machine history; pending queue excluded already-reviewed but changed evidence | Reuse one containment helper/window adapter, preserve partial/unknown rows, avoid inferring current machines as past V3 evidence, expose changed evidence through the existing review queue |
| `/api/lean`, comparison helpers and local `lean-comparison` Edge source | Exact/submission-time sums, floating transport and v1-only comparison basis | Reuse current metric/runtime formulas with period-aware scoping, exact KG sums and v2 production-basis evidence; incompatible saved versions remain incomparable |
| Existing Lean initiative command | Baseline selection used `min(occurred_at)`; reviewed period-only evidence has no exact time | Owner-approved local amendment derives bounds from eligible reviewed production periods or original exact-event expressions; stale/unreviewed/ambiguous evidence cannot supply a baseline |
| Quality board/high-Scrap reader | Already uses official effective Good/KG, protected sources and existing standards | Keep the original reader as a revoked delegate and add bounded-page production provenance. Lean review metadata is available only with Lean view. No threshold/rejection/notification changes |
| Saved Lean/Loss, Maintenance, Warehouse acknowledgments | Existing protected immutable or conserved operational truth | No writer/formula/schema change; snapshots, function/grant contracts and relevant regressions verify preservation |
| Floor/Dashboard/Reports, History/export and Scrap/correction forms | Existing screen wiring and legacy presentation, some declaration-time views | No TSX/UI/export change authorized. Canonical V3 period summaries exist; broader screen/rollout acceptance remains deferred. Do not treat old screens as new V3 visual acceptance |

No consumer joins pending/rejected correction values into official totals. No duplicate Scrap system, inventory ledger, runtime engine, prioritization formula or approval workflow is added.

## Correction and review semantics

| State | Operational quantity | Eligible current reviewed Scrap |
| --- | --- | --- |
| No correction | Official original/effective value | Existing review policy |
| Pending/rejected correction | Previous effective value | Existing review policy unchanged |
| Approved correction | New official effective value; protected posting once | An earlier Scrap review is retained but cannot automatically approve the new evidence |
| Existing authorized Scrap re-review | Current official value unchanged by review | Current quantity becomes eligible under the existing reviewed-cause/abnormal-Scrap rules |

The private review-current helper checks the immutable correction ledger against the stored server review time. It does not edit or reset an earlier decision. Operational History/Quality still show the newly corrected KG; reviewed KG is withheld when a later correction exists. Quality may expose `EVIDENCE_CHANGED_AFTER_REVIEW` to a Lean-authorized reader. M3A's existing observation status remains REVIEWED as historical fact, with the separate current-review boolean preventing ambiguity.

Correction approval still uses effective Orders approve, including configurable engineering package grants and self-approval. Scrap evidence review still uses the existing Lean edit authority. There is no new Quality approval stage or negative Scrap-review state: the existing schema has pending observation and reviewed approved-cause evidence. Unauthorized/invalid review attempts remain rejected; permanent Quality stock rejection/reversal and recoverable rework retain their separate existing semantics.

## Period attribution and quantities

The additional observation payload uses `time_precision: SHIFT_PERIOD` with the existing ID, entry, cause, explanation and response. The database copies effective occurrence and production bounds after normal factory/Orders edit checks and established factory/structure locking. Actor/time and UUID retry identity remain server controlled. It rejects caller-supplied bounds, timestamps or downtime links in this form. Existing exact observations and other commands delegate to the existing protected implementation, with only the separately approved initiative-baseline amendment below.

A period describes possible physical production, not a uniform distribution. Full containment permits quantity allocation; intersection without containment yields PARTIAL and NULL allocated quantities/frequency. UNKNOWN evidence remains explicitly scoped by recorded time, never converted into physical time. Zero-width valid active bounds retain their exact boundary semantics. JavaScript boundary comparisons retain microseconds; no prorating, synthetic midpoint, midnight or submission-time substitution.

Frozen occurrence business date/timezone and original versus effective provenance remain in canonical V3 History/summary and Quality production metadata. Existing Lean shift rollups retain their recurring-shift dimension; source occurrences retain their dated keys/periods. They are not relabelled as new dated-occurrence UI. Canonical production summaries continue grouping the actual occurrence/Product/line/unit tuple.

Good units remain Meter/Piece/KG and typed separately. Scrap stays KG. Exact numeric strings survive SQL/client/HTTP/Edge transport; aggregate decimal operations reuse the existing decimal utility. Existing percentage/runtime/change formulas remain unchanged. The new evidence contract reports READY, INCOMPLETE or NA and distinguishes measured zero, missing mass, unknown allocation and unreviewed evidence. Runtime coverage remains separate from quantity completeness.

Historical V3 line attribution never uses present machine membership as historical physical proof. V3 entry reads return no inferred machine IDs when supported machine evidence is absent. Legacy exact assertions retain their existing meaning; legacy production-period attribution is explicitly UNKNOWN.

## Historical evidence and security

Saved Lean v1 comparisons, initiative baseline/verification evidence and saved Production Loss records are not recalculated or migrated. Current evidence is version2 with production basis and explicit incompleteness. A v1 saved baseline cannot silently compare with a v2 current calculation; metric changes remain insufficient. The existing trusted persistence contract and human verification rules are unchanged. The local Edge source changes transport/calculation inputs only; it was not deployed or used against remote records.

Normal authenticated clients, per-person/package union and factory scope remain authoritative. Orders-only users cannot read Lean; Quality-only users can read the existing operational board without Lean evidence. Pending correction storage remains private. New private functions/views and old delegates have no anonymous/authenticated bypass access; public read grants/search paths remain as before. Existing table ACLs/RLS/policies are preserved. No service-role bypass replaces normal authorization.

Consumers remain reads: no production, source, stock, WIP, Sales, Maintenance, downtime, review decision or saved-estimate write occurs while reading. The new observation command creates only the already-required observation/retry/audit evidence; correction posting remains in the existing approval transaction.

## Approved initiative compatibility amendment

The historical initiative branch in `20261005072541_lean_baseline_boundaries.sql` selected `min(o.occurred_at)` and `max(greatest(o.ended_at,o.occurred_at))`. A reviewed SHIFT_PERIOD observation intentionally has NULL occurred_at, so period-only evidence failed closed with `lean_baseline_missing`. The historical migration remains untouched.

The new M3C migration amends only that selector and its current-Scrap-review predicate in the revoked existing delegate. Eligible period rows contribute authoritative period_start/period_end; exact rows retain the original timestamp expressions. The existing factory, mechanism, cause, resource and Product predicates remain unchanged. A stale Scrap review contributes nothing; unreviewed rows never enter qualified occurrences, and ambiguous Product attribution cannot match the requested Product. Missing or nonpositive aggregate bounds still raise `lean_baseline_missing`. Mixed evidence is a bounds envelope, not an additional quantity aggregation; original event and period identities/precision remain intact.

`initiative.test.sql` exercises period-only, exact-only, mixed (including a later unreviewed source), unreviewed-only, ambiguous and missing evidence, plus stale review, authority denial, intent collision and exact UUID retry. The function-preservation check compares the delegate against the previous body with exactly the two approved substitutions; unrelated command branches cannot silently change. Existing factory locks, permissions, retries, action lifecycle and trusted evidence persistence remain protected.

The same-factory historical regression creates an initiative through the actual command, stores explicit incomplete source-based baseline evidence through the existing service-only persistence contract, completes a normal action, and verifies with INSUFFICIENT_DATA under existing authority. It saves a comparison and then approves a source correction. The complete saved initiative (including baseline/verification), comparison and fictional saved Loss row must remain byte-equivalent while current Good/KG change. A subsequent separate Scrap review qualifies the current value without changing the saved initiative. This is protected lifecycle/persistence compatibility evidence; the trusted test payload and fictional Loss snapshot are not a new Loss-model calculation, hosted human approval or browser acceptance claim. The normal authenticated persistence attempt is separately denied. Actual Warehouse acknowledgment and exact UUID retry leave Good/source/stock unchanged; a later approved correction preserves that acknowledgment and updates source credit once.

## Local validation

All databases use the previously authorized portable PostgreSQL17.11 runtime, a unique disposable directory, database `factory_lean_quality_local`, and verified 127.0.0.1 connection target. No hosted environment file or credential is used. Tests may enable the gate only inside disposable late-admission fixtures, then restore FALSE/schema0; this is not application activation.

Commands:

```text
pwsh -NoProfile -File tests/production-consumers/run-local.ps1 -RuntimeDirectory C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018 -Port 55472 -Upgrade
pwsh -NoProfile -File tests/production-consumers/run-local.ps1 -RuntimeDirectory C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018 -Port 55473
```

Focused Node: **441/441 PASS**, including39 new consumer tests and affected M1/M2/M3B, correction, Lean/F-021 presentation, Quality/high-Scrap, WIP/readiness and Permission Package regressions. Reexecuted after the approved fix: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-M3C-Node-approved.txt`. This is not the full-project suite.

TypeScript and isolated optimized Next16.3.5 webpack production build: **PASS**, reexecuted after the approved fix in `C:\Users\Temp\AppData\Local\Temp\FactoryLean-M3C-Build-9a33759d67a04f2e8628a9a6cc358f82` (`typecheck-approved.txt`, `build-approved.txt`, `final-application-hashes.json`). Current affected application inputs were hash-matched to the isolated copy. Existing dependencies and dummy `.invalid` Supabase values only; no actual application server or hosted writer was started.

SQL covers ordinary/late Scrap, overnight local date, exact KG, unknown legacy versus zero, pending/rejected/self-approved/sequential corrections, separate evidence review, foreign factory/package restrictions, protected sources and conservation. Real late admission uses the existing guarded worker in the disposable fixture. Historical overnight rows are explicitly fictional constrained reader inputs, not proof that the writer permits historical backdating.

The bounded scale fixture records205 small declarations through the normal writer and traverses all consumer pages without duplicates/truncation. EXPLAIN/ANALYZE and HTTP timings are local measurements, not hosted performance promises. Existing 5,010-row Phase3B traversal remains historical evidence and is not represented as reexecuted here.

Actual separate-connection races cover uncommitted approval versus concurrent reads, stable read snapshots across a committed approval, and existing Scrap review waiting for correction locks. Inherited correction/M2 races retain source/Sales/Quality/deadline checks. Actual Next handlers, installed client, authorization, parser, local Edge source and PostgreSQL are exercised together; fixture sessions/transport and a local Deno host stub do not prove hosted GoTrue/JWT-cookie/PostgREST/Deno deployment or browser acceptance.

Diagnostic iterations corrected reserved-word/aggregate syntax, fixture aliases, same-statement time windows and expected audit effects. A prior High-Scrap contract check detected an unnecessary timezone function setting; it was removed to retain the existing function configuration exactly. Initial build type errors were fixed. Diagnostic/changed-input runs are not final PASS evidence; no integrity constraint was removed or weakened.

### Final frozen-input evidence

Both complete runs exited0; the runner hashes all SQL/test inputs and affected application files before execution and checks them again at completion.

| Executed checks | Fresh path | Upgrade path |
| --- | --- | --- |
| New Phase3C SQL assertions, including29 initiative/lifecycle/Warehouse checks | 99 PASS | 99 PASS |
| M3A reporting/security/temporal/multiple-entry assertions | 69 PASS | 69 PASS |
| Correction policy/security assertions (39 policy +19 security) | 58 PASS | 58 PASS |
| M2 writer/boundary/Maintenance/startup assertions | 66 PASS | 66 PASS |
| WIP recording/readiness/transfer assertions | 52 PASS | 52 PASS |
| Quality source/release-fix/high-Scrap assertions | 24 +28 +34 PASS | 24 +28 +34 PASS |
| SQL assertions/groups above, excluding function comparisons | **430 PASS** | **430 PASS** |
| Existing function-body/grant contracts, with only approved substitutions | 337 PASS | 337 PASS |
| Actual separate-connection races: M3C / correction / M2 | 3 /3 /16 PASS | 3 /3 /16 PASS |
| Actual HTTP scenarios: M3C / correction | 15 /12 PASS | 15 /12 PASS |
| HTTP SQL RPC calls: M3C / correction | 32 /27 | 32 /27 |

Final fresh evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Consumers-M3C-31eb9f34167347308fc0eb3562b8e76e\results`.

Final upgrade evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Consumers-M3C-603376ce38064dada561b99d6c76c9ec\results`.

Local protected-entry page SQL: fresh43.345ms / upgrade48.223ms. Scoped occurrence SQL: fresh4.617ms / upgrade5.263ms. M3C HTTP scenario median: fresh218.78ms / upgrade235.20ms; p95: fresh1221.76ms / upgrade1187.25ms. These include disposable process/connection/fixture overhead and are not hosted measurements. No new per-row network call was introduced.

Final checks confirm full historical-row/security preservation during migration, read-side operational/audit/gate digest preservation, historical saved Lean/Loss equivalence, no negative stock or reservation violation, all V3 fixture gates FALSE/schema0, and unchanged Maintenance activation. Test-only M2 gate schema3 is intentionally cleaned back to0 by inherited concurrency fixtures; the migration itself preserves complete pre-test gate rows. Owned PostgreSQL processes stopped, disposable data directories removed, evidence/scripts retained.

Preservation comparison covers the original731 project files. Exactly five existing application sources above and the prepended HANDOFF change belong to this task; no original file is missing. Final inventory748 files: six existing changed by this task and17 new. All95 prior migrations, Design System, Export Reader, environment/link files, Git index/HEAD/main and unrelated dirty files retain their captured state. The initial five edited-source hashes were recovered after tool-state reset from the preceding successful preserved build; other captured files were still untouched. This limitation is recorded in the external baseline inventory rather than claiming an uninterrupted in-memory snapshot.

The Phase2 recovery ZIP remains untouched, SHA256 `F3D862EC88B4375E6AC9A1A23B7B5970DD829453E67713503AD3573A30EAA5C2`. Whitespace checks cover tracked changes and all17 new files. No credentials or environment files were created in the project.

## Exact task manifest

Existing files changed:

1. src/app/api/lean/route.ts — protected consumer transport/period-aware enrichment.
2. src/utils/lean-comparison.mjs — scope-aware current metrics and versioned evidence; existing formulas reused.
3. src/utils/lean-contract.mjs — approved period observation input whitelist/validation.
4. src/utils/production-reporting.mjs — shared exact transport and additive review-current parsing.
5. supabase/functions/lean-comparison/index.ts — local-only matching consumer transport/evidence version.
6. HANDOFF.md — current milestone prepended; prior content retained.

New files:

7. supabase/migrations/20261019124124_production_scrap_lean_consumers_v3_m3c.sql
8. src/utils/exact-json.mjs
9. src/utils/production-periods.mjs
10. src/utils/production-consumer-transport.mjs
11. tests/production-consumers.test.mjs
12. tests/production-consumers/run-local.ps1
13. tests/production-consumers/before.sql
14. tests/production-consumers/after.sql
15. tests/production-consumers/consumers.test.sql
16. tests/production-consumers/periods.test.sql
17. tests/production-consumers/security.test.sql
18. tests/production-consumers/performance.test.sql
19. tests/production-consumers/concurrency.mjs
20. tests/production-consumers/http.mjs
21. tests/production-consumers/final.sql
22. tests/production-consumers/initiative.test.sql
23. docs/production-recording-v3-phase3c.md

Product differentiators reviewed: this is compatibility/traceability work within existing capabilities, not a new competitive classification or superiority claim. No differentiator document change is required.

## Remaining acceptance and stop

Phase3C is backend consumer integration, not a new user interface or release activation. Existing correction/observation forms, operational screen wiring and Excel/Print remain outside this brief. No visual EN/AR/RTL/mobile or first-time-user acceptance is claimed; the permanent simplicity standard still governs that future work.

The smallest separately authorized Phase3D scope is a bounded local integrated acceptance pass over the canonical reader, period observation, correction/review and current/saved evidence contracts, with an explicit checklist of deferred screen/export wiring and release-readiness gates. Reuse this evidence; do not repeat unaffected audits or automatically add UI/export implementation. Hosted authentication, coordinated migration/application/Lean Edge deployment, three-way migration-history checks and activation remain separate approvals. Do not begin Phase3D automatically.

Late recording stays FALSE/schema0; M1 late capability remains unavailable. Maintenance activation and the Loss-saving Edge source are unchanged. Export Reader, Design System, recovery checkpoint and all unrelated work remain preserved. Stop for owner review: no Phase3D/4, hosted access/deployment, activation or Git operation.
