# Production Recording V3 — Phase 3D Local Integrated Acceptance

20 October 2026. **LOCAL ACCEPTANCE PASS — Phase3D complete.** Both final frozen-input installation paths pass. No hosted acceptance, activation or Phase4 implementation is claimed.

## Authority, environment and preservation

Owner authorization: Phase3D local integrated acceptance, including narrow additive compatibility fixes and test-harness corrections. AGENTS, current HANDOFF, Phase1/2/3A/3B/3C and correction-foundation reports, UX_SIMPLICITY_STANDARD and external Phase0 contracts/model/test matrix remain authoritative. Implementation continues the current checkout rather than rebuilding any completed phase.

Starting state: development, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, 30 modified tracked files,150 untracked individual files, zero staged,748 project files and96 migrations. A new complete SHA256 inventory was captured before changes in `C:\Users\Temp\AppData\Local\Temp\FactoryLean-M3D-Preservation-ce442695faca4d9387a4567b645b5442\baseline.json`. This capture does not depend on recovered hashes from an earlier task.

Existing portable PostgreSQL17.11 is reused. Every cluster has a unique owned temporary directory, an unused port, verified loopback-only address127.0.0.1, database `factory_lean_quality_local`, local fixture credentials and a clean initdb. The manifest is checked before SQL. Real `.env.local` is never loaded by the test application; subprocess configuration uses loopback/dummy values. Actual routes are compiled with a fixture session/transport adapter, not started against the real hosted-connected application.

**Migration order:**90 pre-V3 migrations, then exactly:

1. `20261018073654_production_shift_work_v3_m1.sql`
2. `20261019063715_production_late_recording_v3_m2.sql`
3. `20261019091907_production_reporting_v3_m3a.sql`
4. `20261019114709_production_correction_approval_v1.sql`
5. `20261019124124_production_scrap_lean_consumers_v3_m3c.sql`

All95 required files are applied in existing order. The96th local file, `20261006072000_factory_export_reader.sql`, is excluded. No migration is changed, renamed, repaired or added. Fresh installs apply M1 before factory fixtures. Upgrade creates actual pre-V3 active production, Good/Scrap, a correction, a physical acknowledgment, an exact Scrap review and a historical saved comparison before M1, then applies all five V3 migrations. Previous values remain unchanged, new historical attribution stays UNKNOWN, and an actual pre-policy correction UUID replays without inventing approval history. Fresh has no pre-policy replay case; it is explicitly not applicable there.

## Recovery protection

The sealed Phase2 recovery archive remains untouched. Before changing application source for the discovered defects, a separate local snapshot was created and every archive entry rehashed:

`C:\Users\Temp\Documents\FactoryLean-Development-Backups\Phase3C-Pre3D-Repair-20261020-e32f5885`

755 files at capture time; `recovery.zip` SHA256 `20B9BCE6CBE7C9339EBAC71E0CA0AB8E8D3CA48845B66B357D0341BD456F86C5`. It includes the complete initial748-file state plus seven new acceptance harness files present then. Ignored environment/credential files and Git internals are excluded. `manifest.json` and `RESTORE.txt` explain verification and selective recovery; no automated restoration is authorized or performed.

## Confirmed defects and minimum fixes

### M3D-01 — Zero-exposure baseline blocked before human verification

The integrated flow created a valid period-only initiative and persisted a baseline through the actual local Lean Edge calculation. That baseline has zero measured operating exposure. The existing comparison helper already returns incomplete evidence for zero/unknown baseline runtime, and protected persistence allows only INSUFFICIENT_DATA for incomplete verification. The Edge handler rejected zero desired hours before reaching that existing behavior, returning HTTP400 `leanInvalid`.

Only official saved zero-exposure baselines now select the existing incomplete comparison branch. Manual zero-hour requests and negative exposure remain invalid. Existing permission, human outcome, source revision, trusted persistence and retry checks remain unchanged. No runtime is invented, no formula changes and no saved baseline is rewritten. Five focused tests execute the actual bundled Edge handler; the integrated PostgreSQL path exercises normal action completion and actual protected verification persistence with a zero-exposure baseline.

### M3D-02 — Numeric JSON rounded at the recording HTTP boundary

Actual handler reproduction accepted the numeric token `0.1234567890123456789` but forwarded `0.12345678901234568` to its RPC after ordinary JavaScript JSON parsing. PostgreSQL itself retains exact numeric; a correct SQL-only test did not prove the HTTP boundary. Reproduction evidence: `precision-before.json` in the preservation directory.

The V3 recording path retains raw request text, runs the existing shape/type/permission checks, and then re-emits only measurement number tokens using the existing exact JSON tokenizer and native `JSON.rawJSON`. The installed Supabase client preserves those tokens when serializing the RPC body. SQL still receives numeric JSON, as required by the existing immutable canonical-intent contract; caller-supplied quantity strings remain rejected. No SQL writer, posting arithmetic, unit rule, authorization, gate or canonicalization is changed.

The V3 receipt/recovery fetch adapter also preserves numeric measurements as decimal strings before the installed client parses them, restoring integer protocol-version fields. This follows the existing History/correction exact-string representation. Database receipts remain untouched and immutable; clients must retain the exact outgoing request, not reconstruct it from a recovery receipt. Existing unversioned active requests retain their existing behavior. Phase4 must use the V3 contract for lossless new recording; this does not claim a retrofit of every legacy numeric consumer.

Six focused tests cover the actual handler, numeric versus quoted input, unchanged legacy behavior, exponent/negative-zero tokens, exact receipt/recovery transport and untouched unrelated/error responses. The integrated HTTP-to-SQL scenario submits19-decimal Good and Scrap numeric literals, checks exact SQL-backed History and recovery values, and retries the original raw body without another credit. Current Node24.19.0 supports native raw JSON; future application release must retain a compatible runtime. No rounding fallback is added.

### Harness corrections, not product defects

- PostgREST maps a JSON null cursor to SQL NULL. The new fixture adapter initially forwarded JSON null literally and was corrected.
- Planning columns are `start_time` and `expected_finish`; an initial acceptance query used conceptual names and was corrected.
- Existing generic POST commands do not share the new read endpoint's cache-header contract. Read/no-store checks remain required; assertions no longer misclassify legacy POST header behavior.
- Five older request mocks exposed only `.json()`. They now also expose `.text()` for the actual raw-body handler. No authorization or business assertion is removed.
- The pre-policy replay regression must select actual pre-policy corrections, not UUIDs created by current auto-approval tests. Upgrade scopes it to the real old fixture; fresh marks it not applicable.
- Platform fixture setup reuses existing default causes rather than duplicating their names. No production catalog or unrelated application module is changed.
- Diagnostic-only fixtures restore temporary M2 schema3 readiness even when the full concurrency cleanup is intentionally omitted. Final full runs still exercise the original cleanup path.

Diagnostic failures and changed-input runs are not final PASS evidence. No stock-integrity failure has been hidden or an assertion weakened to bypass a business rule.

## Integrated business scenario

One independently created disposable factory uses real Planning and Start, actual shift-work API output, approved worker membership, a separate package-authorized engineer, and the same authoritative production entry throughout:

| Stage | Primary entry Good | Primary Scrap KG | Factory finished stock | WIP |
| --- | --- | --- | --- | --- |
| First active V3 recording | 30 Meter | 30 | 30 Meter | 2 Meter |
| Second entry after a dropped committed HTTP response | 30 Meter | 30 | 31 Meter | 2 Meter |
| Technician correction pending | 30 Meter | 30 | 31 Meter | 2 Meter |
| Engineer approves exact correction | 31.1234567890123456789 Meter | 20.1234567890123456789 | 32.1234567890123456789 Meter | 2 Meter |
| Engineer self-submits another correction | 32.1234567890123456789 Meter | 21.1234567890123456789 | 33.1234567890123456789 Meter | 2 Meter |
| Later approved Scrap-only correction | unchanged | 22.1234567890123456789 | unchanged | 2 Meter |
| Normal Finish, then local-fixture late Good | unchanged | unchanged | 35.1234567890123456789 Meter | 2 Meter |
| Additional exact numeric HTTP declaration | separate entry | separate entry | 35.2469135780246913578 Meter | 2 Meter |

Reservations remain0 in this isolated scenario. Stock/source credit equality and no negative/overcommitted balances are asserted. A pending/rejected correction posts nothing; approval and self-approval post once. The original entry fields and historical review remain traceable. A separate Scrap re-review is required after quantity approval. Quality shows official current KG separately from stale analytical provenance. Orders-only workers cannot read Quality/Lean data.

The actual existing Lean command creates the period-only initiative; the actual local Edge calculates/persists baseline evidence, a normal action is completed, and authorized human verification records INSUFFICIENT_DATA without invented operating exposure. A subsequent approved correction/re-review leaves the entire saved initiative unchanged. Inherited cases additionally preserve saved comparisons and Loss snapshots and cover exact-only/mixed/unreviewed/stale/ambiguous/missing evidence.

Warehouse acknowledgment and its UUID retry add no stock. Normal Finish retains Planning timestamps. Local-only late admission retains completed status and original actual completion. Gate-disabled committed replay remains valid. Additional inherited source/Quality/Sales races verify real protected decreases, physical source selection, reservations and WIP processing. Recording provenance alone never claims physical stock identification.

## Acceptance coverage and limits

| Group | Local evidence |
| --- | --- |
| A — Shift/eligibility | Actual protected reader/API,253 distinct started jobs over6 pages, same Product across items/lines, completed-current-shift membership, zero-entry work, exclusions, frozen occurrence and temporal cases |
| B — Recording/deadlines | Existing active and V3 guarded paths, Good/WIP units and Scrap KG, exact transport, actual late output with retained execution, timed lock/expiry rollback plus exact-boundary resolver checks |
| C — Idempotency/recovery | Same/changed/concurrent UUIDs, actual response dropped after commit, same-actor recovery, UNKNOWN/invalid intent, source balance races and Warehouse retry |
| D — Corrections | Real worker pending/reject/engineer approve/self-approve, reasons, original/current/audit, package/direct/union/revoked authority, terminal races and stale baselines |
| E — Conservation | Exact finished/source/WIP effects, pending/rejected no-effects, source selection and Sales/Quality serialization, acknowledgments and alternative/transfer regressions |
| F — History | Exact original/current/period/submission facts, dated typed summaries, partial/unknown allocation, audit pagination,5010-row HTTP traversal, private/no-store and backward compatibility |
| G/H — Quality/Scrap/Lean | Operational versus reviewed evidence, separate re-review, actual initiative/Edge verification, current version2 and incompatible saved versions, saved historical preservation |
| I — Security | Actual local authenticated/anonymous roles, effective factory grants, private helpers/RLS/grants, masked provenance, revoked access, schema/gate enforcement and ordinary HTTP authorization |
| J — Platform | Relevant Node plus existing rollback SQL for Planning/execution, alternatives/transfers/WIP, Purchasing/Warehouse/suppliers, Maintenance/Loss, downtime, Quality and Lean; existing contextual-export contracts only |

Deadline truth is the final authoritative database admission check (`accepted_at < occurrence end`), not a browser click or a promise of WAL/HTTP completion before that instant. A committed request can reconcile after expiry; an expired in-flight request before final admission rolls back. Historical overnight/DST fixtures test frozen interpretation; they do not claim that the writer supports arbitrary backdating.

Two distinct request UUIDs can represent the same physical measurement. This accepted residual risk is not solved by request idempotency. Phase4 durable intent and nonblocking similarity warnings remain required; no new blocking approval is introduced.

Fixture Auth/PostgREST transport and the local Deno host stub execute real handlers, installed clients, SQL and Edge calculation. They do not verify GoTrue, JWT/cookie renewal, deployed PostgREST/schema-cache behavior, the full Next router, browser usability or a hosted Loss model. Those remain deferred rather than PASS.

## Final execution evidence

All figures below were executed against the current application and test inputs. Historical Phase3C figures are not substituted for reexecution.

| Verification | Fresh | True pre-V3 upgrade |
| --- | --- | --- |
| Ordered migration installation | 90 baseline +5 V3, PASS | 90 baseline, historical fixtures, then5 V3, PASS |
| M1 temporal/reader assertions | 308 | 308 |
| M2 writer/boundary/Maintenance/startup assertions | 66 | 66 |
| M3A reporting/scale assertions | 73 | 73 |
| Correction policy/security assertions | 58 | 58 |
| Pre-policy correction replay assertions | Not applicable | 2 |
| M3C consumer assertions | 99 | 99 |
| WIP/Maintenance readiness/transfers assertions | 52 | 52 |
| Maintenance Loss assertions | 22 | 22 |
| Quality source/release/high-Scrap assertions | 86 | 86 |
| Purchasing/Warehouse/supplier/requester assertions | 239 (99+34+31+75) | 239 |
| New upgrade/preservation/final-gate assertions | 4 | 15 |
| **Counted SQL assertions/groups** | **1107** | **1120** |
| Additional execution/downtime rollback suites | 2 PASS; no instrumented assertion total | 2 PASS; no instrumented assertion total |
| Preserved existing function contracts | 337 | 337 |
| Concurrency/deadline scenarios | 25, plus1 Maintenance-gate preservation check | Same |
| Actual handler/client/SQL HTTP scenarios | 130 /397 RPC calls | 130 /397 RPC calls |
| New complete production-to-Lean HTTP chain (included above) | 29 /145 RPC calls | 29 /145 RPC calls |
| Large History API traversal | 5010 unique records /51 pages | Same |
| Final input hashes / cleanup | Stable / owned server stopped, data removed | Same |

Concurrency accounting is3 M1 races,16 M2 concurrency/deadline cases,3 correction races and3 consumer races. The additional M1 Maintenance-gate preservation probe is not reported as another race. HTTP accounting is31 M1/25 RPC,28 M3B/138 RPC,12 correction/27 RPC,15 M2/30 RPC,15 M3C/32 RPC and29 integrated/145 RPC. Assertions are distinct from scenarios, RPC calls and function contracts; these categories must not be added into one inflated test count.

Relevant Node suite: **931/931 PASS across51 files**, zero failed/cancelled/skipped/todo,6387.25ms. This includes the11 new actual-handler precision/Edge regressions and the older request-adapter checks; it is not a full-project test claim. TypeScript PASS; isolated optimized Next16.3.5 webpack production build PASS. All169 application inputs used by that build match the checkout. No real environment file or hosted credential was copied into the build. Whitespace and final preservation checks pass.

Evidence roots:

- Fresh: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Acceptance-M3D-1e2e17cbf15247c0b0e20f5160b654b3\results`
- Upgrade: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Acceptance-M3D-0480212c27a740c7aa58c0bc07db461c\results`
- Node, typecheck, build and final preservation: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-M3D-Preservation-ce442695faca4d9387a4567b645b5442`

The final run summaries explicitly report `IntegratedOnly=False`; diagnostic partial runs are not acceptance evidence. Each root retains its isolation/migration/input manifests, SQL logs, HTTP reports, concurrency reports and shutdown log. The M3B textual success log retains the5010/51 traversal and138 RPC result. Its original generic `http.json` filename is subsequently reused by the inherited M2 harness, so that file contains M2 evidence; no M3B latency distribution is reconstructed or claimed from it. Full M3B timing capture can be improved in a later harness-only task; the required traversal, bounds and two-RPC-per-page assertions executed successfully.

Measured performance (fresh / upgrade):

- New integrated HTTP median313.30 /295.60ms; p95566.96 /543.97ms.
- Existing M3C consumer HTTP median257.82 /270.03ms; p95747.40 /729.33ms.
- Consumer SQL protected page41.801 /42.566ms; bounded candidate5.347 /5.438ms.
- Large History SQL protected first page100.940 /91.489ms; candidate index plan0.340 /0.246ms.

The previous Phase3C consumer SQL page43.345 /48.223ms and HTTP median218.78 /235.20ms, p951221.76 /1187.25ms are historical comparisons using the same local harness family. Phase3B's prior protected page120.218ms is also historical. Both current databases ran concurrently on the same Windows host; fixture contents and local load differ, so these measurements neither prove a performance improvement nor hosted equivalence. Filtered full totals still scale with matching records. The current large traversal asserts at most100 rows per page, exactly2 RPCs per page, bounded bytes, no duplicate IDs and complete coverage; it does not use an N+1 supplement.

No final test failed. Fresh pre-policy replay is explicitly not applicable rather than silently skipped. Earlier diagnostic failures are recorded under the fixes/harness section and are superseded only by the complete frozen-input reruns. Pending checks are real hosted Auth/PostgREST/Edge deployment behavior, browser/manual EN/AR/390px acceptance and Phase4 UI/recovery/export integration. They are outside this local gate, not local PASS claims.

Final preservation:758 project files,35 modified tracked/160 untracked individual/zero staged. Exactly10 initial files changed (the four application files, five test mocks and prepended HANDOFF) and10 files were added, matching the20-file manifest below. No initial file is missing. All96 migration hashes, Git index/HEAD/main, real environment/link files, Design System, Export Reader and unrelated file hashes match the baseline. The entire previous HANDOFF remains an exact byte suffix. Both recovery ZIP hashes match their sealed values. Ports55474/55475 have no listener; both owned data directories were removed. No hosted migration alignment is claimed from these local checks.

## Phase4 readiness checklist — specification only

- Keep the existing Factory Floor overview; launch one focused recording task, with a desktop modal and390px full-screen mobile experience.
- Show actual current-shift work, clear Product/order/line identity, frozen date/period, Good unit and Scrap KG. Keep blockers and mandatory errors visible; put source/history details on demand.
- Use existing per-person authority. Worker corrections show PENDING; approved engineers self-submit without a second approval. Use one editable required explanation, optional editable suggestions and no compulsory category/Other workflow.
- Use the canonical History/correction APIs for current/original/proposed distinctions, recent entries, review queue and supporting details. Source decreases still require real physically valid selections.
- Persist the exact outgoing V3 request body/UUID before sending; isolate it by actor/factory, recover after interruption, retain unresolved attempts and never generate a replacement UUID automatically. Treat exact decimal strings in receipts/recovery/History consistently.
- Treat independent duplicate measurements as a nonblocking warning. Do not infer source traceability, production time or permission from UI labels.
- Provide EN/AR, RTL, keyboard/screen-reader support and390px manual acceptance. No screen or visual acceptance is delivered here.
- **Release dependency:** the M1 reader intentionally still reports late-recording availabilityFALSE/PHASE1_READ_ONLY, even though disposable writer tests can exercise the private gate/schema3. The persistent gate remainsFALSE/schema0. Matching capability/readiness publication and activation integration require a separately authorized release step; Phase4 must not infer permission to record completed work merely from row membership or a client flag. No unrestricted activation toggle is introduced.
- **Hosted dependency:** fresh authorized three-way migration-history verification, isolated deployment manifest/dry run, coordinated application/Lean Edge delivery and real authentication acceptance remain separate gates. No remaining user-policy decision is manufactured by this local test phase.

## Task change manifest

Application source:

1. src/app/api/data/route.ts — V3 numeric-token preservation after existing validation; matching receipt transport.
2. src/app/api/production-recording-status/route.ts — exact recovery transport.
3. src/utils/production-recording-v3.mjs — bounded existing-tokenizer/native-JSON transport, existing parser/failure contracts retained.
4. supabase/functions/lean-comparison/index.ts — official zero-exposure baseline compatibility only; local source, not deployed.

Existing test mocks, only `.text()` added:

5. tests/internal-production.test.mjs
6. tests/maintenance.test.mjs
7. tests/permission-packages.test.mjs
8. tests/supply-contract.test.mjs
9. tests/warehouse-master.test.mjs

New acceptance tests:

10. tests/production-acceptance-edge.test.mjs
11. tests/production-acceptance-precision.test.mjs
12. tests/production-acceptance/run-local.ps1
13. tests/production-acceptance/before.sql
14. tests/production-acceptance/upgrade-before.sql
15. tests/production-acceptance/upgrade-after.sql
16. tests/production-acceptance/platform-fixture.sql
17. tests/production-acceptance/integrated.mjs
18. tests/production-acceptance/final.sql

Documentation:

19. docs/production-recording-v3-phase3d.md
20. HANDOFF.md — current milestone prepended; previous content retained.

No UI, export, migration, environment, dependency or unrelated operational implementation is changed. PRODUCT_DIFFERENTIATORS was reviewed: these are compatibility corrections and verification within existing capabilities, not a new competitive claim; its prior dirty content remains preserved.

## Stop boundary

Stop after the final evidence and owner report. No hosted access, credentials, activation, deployments, Git writes, Phase4 UI or additional development is authorized. Default late recording and existing Maintenance activation remain unchanged.
