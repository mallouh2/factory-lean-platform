# Maintenance Planning — Phase6 activation integration (2026-10-14)

**LOCAL COMPLETE; NOT ACTIVATED OR DEPLOYED.** development/bb0d20e remains unchanged; zero staged, all prior dirty work preserved. New forward `20261014123640_maintenance_activation_integration_v1.sql`;91 local files,90 previous migration bytes preserved. Export Reader and untracked Design System unchanged. No remote project access or operations in this phase, no accounts/grants, commit/push/merge or main change. TESTING89 migrations, Loss Edge v2 ACTIVE, real Maintenance/Gantt/Loss read acceptance and activation FALSE were verified in the preceding authorized release stages; not re-queried here. Phase6 SQL is pending, separately from Export Reader.

## Contracts

The new private reader adapter delegates to the frozen Phase4 context and preserves the original SHA256 fingerprint, scope, revisions, occupancy and permission checks. It replaces the hardcoded availability with strict protected gate state and existing Orders edit authority. Disabled/missing gate returns false; advisory preview/gaps remain readable while inactive. Private predecessor/helper execution stays revoked for ordinary callers. No activation UPDATE, administrative toggle, writer signature/grant change, machine action, downtime creation or Loss calculation change.

The protected command retains its existing body, actor-bound retries, individual/package permissions, revisions, fingerprint and atomic capacity/configuration checks. Two changes only: take a shared gate-row lock after the established factory structure lock and before item rows for confirm/reschedule; coalesce a missing gate to false at the existing gate check. Concurrent admin gate UPDATE serializes against these commands. Disable-first is observed by the waiting command and rejects a stale activated preview; command-first completes atomically and disable waits until commit. Deactivation is not retroactive cancellation of an already committed reservation. An eventual administrative gate update must keep its transaction narrowly scoped and must not acquire structure/item locks after the gate row. There is no such writer exposed to users.

Original successful identical retries still return their recorded request ID even after deactivation, without creating another reservation/history row; they are authenticated replays, not new confirmations. Different actor/payload remains rejected. Unknown or manipulated client/API flags cannot replace SQL authority. Old transaction snapshots still fail closed.

Existing drawer now requires board activation, explicit true preview activation/confirmation capability, fresh matching eligible CLEAR/complete preview, factory/Maintenance/Orders grants, mutable planned request and current schedule revisions. New confirmation must match the persisted proposal window; edits require saving a proposal and obtaining a new preview. Confirmed/invalidated rescheduling uses the existing time/reason/proof payload and requires a nonempty reason. Both button and event handler enforce these conditions, including Enter/form submissions. Busy/loading/stale/expired/unknown/denied state cannot authorize submission. Inactive banners are conditional in the existing queue/drawer/Gantt. EN/AR, RTL/layout and emergency corrective workflow retained; no new strings/styles or scheduling engine.

## Evidence and limits

-101/101 focused Node tests: actual drawer button/handler contracts, inactive/unknown/malformed/stale/expired/edited/denied cases, EN/AR rescheduling reason and gate change, existing Maintenance reader/API/confirmation/UI and Planning regressions.
-159 standalone PostgreSQL assertions:18 activation,33 existing confirmation contract,49 planned-stop association,37 readiness,22 Loss. Gate false and missing-row refusal; true permits only valid authority/proof/no-conflict; view-only reader stays unavailable; successful retry replay adds no revisions; required reschedule reason and production conflicts retain original errors.
-Two real two-connection activation races passed with observed Lock waits and no deadlock. Final local gate false.
-TypeScript, isolated production build and whitespace checks passed. Generated tsconfig/next-env restored byte-identical; build output/evidence outside Git. All90 earlier migrations and unrelated source files preserved.

Approved portable PostgreSQL17.11 reused on localhost55448. Owned clusters stopped and temporary data removed; scripts/results retained. Initial local fixture runs failed on an incorrect schedule-ID expectation (RPC returns request ID) and failure to restore a deliberately deleted gate before the next case; corrected fixtures, without changing production checks. Final run3 passes all suites/races. Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Activation-20261014` and `FactoryLean-Quality-Postgres-activation-20261014-run3/results`. No repeated hosted browser acceptance, full suite or remote Auth/PostgREST test. Focused component events use isolated controlled React state, not a hosted persistence claim. Product Differentiators reviewed; inactive integration changes no deployed competitive claim.

The existing localhost3000 development server was paused before edits to prevent hot reload/hosted polling. It remains stopped; restarting against TESTING is a separately authorized release/read step. Remaining: deploy the new migration and matching UI, then separately approve narrow activation and hosted operational/write acceptance (including independent verifier authority). No activation begins here.

## Exact Phase6 files (13)

- `HANDOFF.md`
- `docs/maintenance-planning-v1-backend.md`
- `docs/maintenance-planning-v1-ui.md`
- `src/features/MaintenancePlanning.tsx`
- `src/features/ProductionPlanning.tsx`
- `src/features/maintenance-planning-types.ts`
- `src/utils/maintenance-planning.mjs`
- `supabase/migrations/20261014123640_maintenance_activation_integration_v1.sql`
- `tests/maintenance-activation.test.mjs`
- `tests/maintenance-planning-readers.test.mjs`
- `tests/maintenance-planning/run-local.ps1`
- `tests/maintenance-planning/activation.test.sql`
- `tests/maintenance-planning/activation-concurrency.mjs`

# Maintenance Planning V1 — Phase 5E (2026-10-14)

**LOCAL PHASE 5E COMPLETE — ACTIVATION BLOCKED.** Development HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862` unchanged; zero staged. All pre-existing work retained. New forward `20261014074140_maintenance_operational_board_v1.sql`; 90 local migration files, all 89 earlier SQL bytes preserved. Remote histories were not queried. Export Reader and untracked Design System untouched. No remote environment, activation, deployment, Git commit/push/merge or main change.

## Operational reader and completeness

Protected `planning_operational_board` requires factory + Maintenance view, plus Orders view for the combined domain. Private helper is revoked from ordinary callers. One set-based scoped projection includes relevant production, proposed/confirmed maintenance, persisted machine/line resources, actual current LINK physical stops, retained holds, overruns, missed/invalidated reservations and relevant released windows. It includes old active holds by effective overlap, without unrestricted completed history. Actual OPEN transfers determine borrower resources even when stopped. Resources are deduplicated; independent routing remains product-specific. Production active occupancy is conservatively open-ended; original saved Planning dates remain separate display facts. Unscheduled current operational requests/items are included for the waiting queue.

Pages are deterministic kind/UUID keysets, at most 100 rows each, with factory/range/resource/domain identity, exact scoped count, SHA256 context, evaluation time and expiry. Mutation between pages or expiry rejects with `maintenance_board_changed` (HTTP409). Evaluation is bounded at 10,001 scoped rows: exceeding 10,000 returns explicit INCOMPLETE/SCOPE_LIMIT with no fabricated complete rows. More than100 linked physical stops on one schedule, missing confirmed resources or contradictory released/open-stop state produce INCOMPLETE/UNKNOWN_OCCUPANCY. Users must narrow scope or resolve unknown evidence; these bounds never silently declare capacity free. Range is finite and at most31 days.

Each individual partial page remains INCOMPLETE, including the final partial page; the client labels COMPLETE only after every expected row is collected with matching identity/context/count and known occupancy. Failures return ERROR/no rows, with denied response data cleared. Snapshots expire after60 seconds or the next confirmed-window boundary. Incremental records and retained previous display during refresh are display-only. Resource snapshot incompleteness also disables dependent advice. API makes one protected RPC per page; no N+1 per-record RPCs. Original Phase3B Preview/Gaps functions, occupancy writer contracts and all older migration files remain unchanged.

## Existing Planning integration

Production Planning and Maintenance queue use the protected operational source instead of the capped generic collections. The legacy500-row history/board endpoint and compatibility hook remain, but neither operative page uses them. Existing drawer, tables, conflict/history/replanning/permission rules remain. Advice, free gaps, load, drag and Smart Slot require complete current horizon and resource context; candidates outside that horizon are not described as available. Manual Planning beyond the viewed range retains the existing protected server validation with an explicit warning, without a local free-capacity assertion. No second scheduling engine or Production Start/Loss changes.

The existing Gantt shows proposal, confirmed, invalidated, continuing hold, overrun and released state. Linked actual elapsed physical stops have a separate strip bounded by their original timestamps/current time, never future reserved time. Machine details use the existing drawer. Machine/line reservations are not counted twice. Original approval and physical timestamps are preserved. EN/AR, RTL and mobile use existing styles.

## Fresh local evidence and limits

- Focused Node/API/Planning/UI/reader regressions:110/110 passed (`node-third.txt`). Includes601 records/seven pages, partial/stale/expiry/unknown/cross-factory handling, actual API401/403/409/404/503/no-store/one-RPC behavior, scoped advice and original Planning interactions.
- Standalone PostgreSQL17.11:47 new board assertions plus13 existing resource-reader assertions passed, final `FactoryLean-Quality-Postgres-board-20261014-run6/results`. Covers551 relevant proposals and551 production rows,701 unrelated historical records of each type, scoped pagination, real retained hold after physical closure, missed/invalidated state, authoritative occupancy comparison, released physical evidence, stale same-count mutation, denied/cross-factory reads and helper grants. Existing Preview/Gaps resource tests remain passing.
- EXPLAIN ANALYZE/BUFFERS/JSON on600 relevant records plus6,000 unrelated histories: scoped helper45.792 ms, protected first page/context96.374 ms. Existing indexes retained; no added index justified by this fixture. Security-definer FunctionScan is visible in the outer plan; this is local fixture evidence, not a hosted performance guarantee or proof of every internal index scan.
-12 actual-component isolated browser checks passed:601/seven-page loading, stale/unknown/denied/wrong-factory refusal, physical/reserved distinction, dedup, old historical snapshot independence, incomplete resources, view-only and Arabic390 RTL/no horizontal page overflow. Loaded EN desktop/AR mobile screenshots inspected. All fixture writes reject. No real3000/3001 session accessed.
- TypeScript and isolated production build passed; generated build configuration restored. Owned local test server/database processes removed and disposable test data removed; scripts and evidence retained outside Git at `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Board-20261014`.

Hosted Supabase authentication/PostgREST/RLS integration, matching migration deployment and real user/physical acceptance remain separately authorized activation prerequisites. Existing Maintenance activation remains disabled. No claim of hosted completion or remote migration alignment. Product Differentiators reviewed; bounded inactive completeness correction does not change competitive claims. Stop after Phase5E.

## Exact Phase5E task files (24)

- `HANDOFF.md`
- `docs/maintenance-planning-v1-backend.md`
- `docs/maintenance-planning-v1-ui.md`
- `src/app/api/maintenance-planning/route.ts`
- `src/app/globals.css`
- `src/features/MaintenancePlanning.tsx`
- `src/features/MaintenanceTimelineBlock.tsx`
- `src/features/ProductionPlanning.tsx`
- `src/features/maintenance-planning-types.ts`
- `src/features/useOperationalPlanningBoard.ts`
- `src/locales/ar.json`
- `src/locales/en.json`
- `src/utils/maintenance-planning-view.mjs`
- `src/utils/planning-operational-board.mjs`
- `src/utils/planning.mjs`
- `supabase/migrations/20261014074140_maintenance_operational_board_v1.sql`
- `tests/maintenance-planning-ui/board-browser-check.mjs`
- `tests/maintenance-planning-ui/fixture.tsx`
- `tests/maintenance-planning-ui/preview.mjs`
- `tests/maintenance-planning/board-performance.sql`
- `tests/maintenance-planning/board.test.sql`
- `tests/maintenance-planning/run-local.ps1`
- `tests/planning-operational-board.test.mjs`
- `tests/planning.test.mjs`

# Maintenance Planning V1 — Phase 5D (2026-10-14)

**LOCAL PHASE 5D COMPLETE — ACTIVATION BLOCKED.** Continue development/bb0d20e unchanged; preserve every previous dirty file. One forward migration `20261014065225_maintenance_loss_context_v1.sql`, 89 local migrations, all 88 older SQL files byte-preserved. Remote migration state is historical/unqueried. No TESTING/DEV/PROD/Simulation access, activation, deployment, staging, commit, push, merge or main modification. Export Reader and canonical untracked Design System preserved.

## Calculation and recorded evidence

The existing `production-loss-impact.mjs`/`evaluateFlow` calculator remains the only estimator. Loss model V1 stays V1; additive maintenance policy version1 is recorded separately. An omitted maintenance context retains the exact legacy result shape and arithmetic. Verified NONE/UNLINK and contextual unplanned relationships receive no planned-maintenance exclusion. Genuine planned treatment requires explicit current LINK, exact event/machine, frozen confirm/reschedule revision with matching resources/approval, valid original boundaries and effective planned classification. Mere window overlap/configured alternatives never qualify.

Original approved boundaries are new segmentation points. Physical duration, approved overlap, outside-window interval and verified scheduled non-production minutes are separate; maintenance_segments are explanatory evidence, not additional causal loss roots. Inside-window production conflicts retain calculated genuine impact and force INCOMPLETE. Outside-window demand uses existing Product rates, actual flow, actual same-item OPEN alternative and known buffer coverage. Unknown demand/routing/topology/capacity cannot become verified zero. Relevant unscheduled or active work extending beyond/starting earlier than its recorded plan is incomplete. New context snapshots carry explicit completeness/version/routing; old snapshots are neither updated nor treated as complete. Routing changes reuse the existing recorder. Shutdown/restart Scrap is still calculated once per event, independently of interval count; existing actual-versus-estimate and deferred/recovery rules remain intact.

Explicit historical early-start LINK corrections now accept genuine overlap with the original frozen approval using the existing protected correction path. They do not extend approval, change classification/timestamps, permit open released-schedule reassignment, or loosen the normal scheduled-stop selection window. This is a minimal forward replacement of the existing append validator, not scheduling redesign. Legacy events with insufficient captured context remain incomplete; no backfill or recalculation is performed.

## Protected review, persistence and history

- `production_loss_maintenance_context(factory,event)`: Factory view + Downtime view; exact factory/event scope, frozen approved machine evidence and historical comparison state. No Maintenance ledger SELECT grant or administrative permission required.
- `production_loss_review_inputs(factory,event)`: Factory view + Downtime edit, one authorized database snapshot of the event, immutable samples, current classification, actuals, frozen association and relevant saved observations. Bounded10000 samples/observations, fail-closed; SHA256 input_hash uses UTC serialization. It exposes only the required scoped bundle, not unrestricted ledgers.
- The existing trusted Edge Function accepts identities only, verifies the real user, uses this protected reader with that JWT and calls the shared calculator. Service credentials are used only for the existing persistence RPC. Full-table service reads were removed. Known denied/incomplete/stale/locked errors retain explicit403/422/409 responses; the Next command route preserves them with existing localized error keys.
- Existing five-argument service-only `persist_production_loss_estimate` retains its signature. It uses the existing effective direct/package permission contract, Factory view + Downtime edit, structure-first lock, refreshed authority, then the closed event row lock before exact input_hash/association/classification comparison and insertion. Classification and actual-observation RPCs minimally wrap their unchanged predecessors with the same structure-first lock; private predecessors are revoked. Read Committed writes supported; old transaction snapshots fail closed. No hash supplies authority.
- Immutable one-result-per-event constraint and UPDATE/DELETE rejection remain. Exact original actor/input/result retries return the original ID, including after a later correction; different actor/payload cannot create or replace another review. Reviewed zero-demand scheduled stops need complete snapshot-bound maintenance segments; ordinary estimates retain their nonempty production assumptions requirement.
- New saved results retain full frozen maintenance evidence and classification revision. Changed evidence returns EVIDENCE_CHANGED_AFTER_REVIEW. Legacy records without a recorded baseline return EVIDENCE_COMPARISON_UNKNOWN. Saved result delivery skips historical calculation/context/comparator reads and calibration; the original result is always displayed. Corrections only append association/classification evidence. No new estimate, Lean occurrence or stock movement is created by a correction.

## Focused local verification

Final focused Node83/83 passed, zero failures/skips:21 new maintenance-policy tests,8 trusted-handler tests, and existing Loss actuals/calculator, lazy history, maintenance associations and production-flow regressions. The saved-history regression now explicitly asserts no historical recalculation while preserving classification previews for unreviewed events. Trusted-handler tests execute the real handler with synthetic public/service requests; they prove input-only bodies, scoped reader, server denial, no write on missing/wrong-factory input, and explicit stale409 without blind retry. They are not GoTrue/PostgREST acceptance.

Standalone PostgreSQL17.11 verification uses the previously approved portable runtime, localhost55446, disposable fixture database, actual migrations excluding Export Reader and the local Auth/Storage shim. Final rollback SQL:22 new Loss assertions +49 preserved actual-stop +5 recording =76 passed; the real calculator/persistence/race checks below also pass. Actual calculator results are passed to the real service-only persistence RPC. Tests cover frozen scope, package-only read/save, view-only/cross-factory/private-helper denial, early historical overlap and multiple linked events, failed insertion rollback/retry, immutable review bytes, positive unplanned Lean occurrence conservation, identical retries, old snapshots and nonempty Good/WIP/source/movement/allocation preservation. Seven two-connection races observe real lock waits: association/classification/actuals/closed-event approval first reject stale saves; persistence first retains result then warns; identical retry creates one row; authority revoked during wait denies. No deadlocks. Test fixtures respect the existing distinction between planned-stop approval and unplanned cause approval; no production constraints were changed for fixture setup.

Eight real-component isolated browser checks pass, no page errors: physical/approved/outside/effective metrics, reviewed-zero save eligibility, identity-only rejected write, incomplete evidence/no save, changed/unknown historical warnings with original results, view-only controls, denied reads, EN desktop and Arabic390px RTL/no horizontal overflow. Both loaded screenshots were visually inspected using the existing CSS module and global styles. All browser writes rejected; no real localhost3000/3001 session or hosted service exercised. TypeScript and final isolated production build pass; generated configs restored and build output outside Git. Owned test processes/data are removed after testing.

Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Loss-20261014` and the final `FactoryLean-Quality-Postgres-loss-20261014-run7/results`. Scripts remain in tests. Public Supabase/PostgreSQL guidance reviewed; no project tools/connections used. PRODUCT_DIFFERENTIATORS reviewed without changing deployed capability classification or prior claims.

## Exact Phase5D files

Modified:
- HANDOFF.md
- docs/maintenance-planning-v1-backend.md
- docs/maintenance-planning-v1-ui.md
- src/app/api/data/route.ts
- src/app/api/loss-review/route.ts
- src/features/LossImpactReview.tsx
- src/locales/en.json
- src/locales/ar.json
- src/utils/production-loss-impact.mjs
- src/utils/loss-review-delivery.mjs
- supabase/functions/save-production-loss-estimate/index.ts
- tests/lazy-history.test.mjs
- tests/maintenance-planning/run-local.ps1
- tests/maintenance-planning-ui/fixture.tsx
- tests/maintenance-planning-ui/preview.mjs

New:
- supabase/migrations/20261014065225_maintenance_loss_context_v1.sql
- tests/maintenance-loss.test.mjs
- tests/maintenance-loss-trusted.test.mjs
- tests/maintenance-planning/loss.test.sql
- tests/maintenance-planning/loss-concurrency.mjs
- tests/maintenance-planning-ui/loss-browser-check.mjs

## Remaining boundaries

This completes local Phase5D only. Matching migration/Edge/Next deployment, hosted JWT/RLS/PostgREST/session acceptance and real physical/factory/user acceptance require separate authorization before activation. Existing missing historical snapshots cannot be repaired by this feature and remain incomplete; old saved evidence comparisons can remain unknown. Existing500-row board bounds remain a separately scoped limitation. No historical Loss recalculation, costing, recurring PM, Production Start redesign, schedule redesign or Phase5E work. Stop after the report.

# Maintenance Planning V1 — Phase 5C (2026-10-14)

**LOCAL PHASE 5C COMPLETE — ACTIVATION BLOCKED.** Continued development/bb0d20e and preserved all Phase5B/earlier dirty work. One new forward migration `20261014054829_maintenance_production_readiness_v1.sql`;88 local files,87 previous SQL files byte-exact. No remote project query, deployment, activation, staging, commit, push or main change. TESTING82 is historical/unqueried. Export Reader remains unchanged/excluded; untracked Design System preserved.

## Protected preparation interlock

Existing `start_product_item(factory uuid,item uuid) returns uuid` signature and original queue/one-active-item/line/Planning lock/timestamp/assignment rules retained. Minimal structure-first wrapper rechecks existing Orders edit authority after waiting; no new write permission. Private predecessor is revoked from ordinary callers. A before-active-transition guard shares the existing structure lock and checks released maintenance through one private scoped condition adapter. It protects other authorized active-transition writers too; it does not rewrite the ordinary execution engine.

Applicable machines come from RELEASED schedule MACHINE resources, current required line topology (blocking/buffer and meaningful impact), explicit Product work-center routing and actual OPEN borrower routes. Historical LINE reservations continue to govern capacity before release through existing occupancy; a released historical line alone does not make an unrelated/now-independent machine a physical prerequisite. No universal effective-running-flow requirement, buffer/future-route simulation or hypothetical alternative credit. `evaluateFlow`, transfer creation/return and the authoritative execution assignment projection remain unchanged; incoming ownership reuses `execution_center_order`.

IDLE permits preparation; RUNNING uses existing eligibility. STOPPED/OFFLINE/SETUP or an unavailable required machine reject Start. An open current linked downtime event is never cleared by a status label or alternative. Actual OPEN transfer ownership remains binding even if its alternative stops; a new item cannot appropriate a machine held for another item. A legitimate explicitly returned transfer restores ownership under existing rules, retaining a manually stopped alternative until its normal physical state action. Unrelated lines/products/independent machines and ordinary production without released maintenance retain existing behavior.

`execution_physical_not_ready` includes a safe explicit machine identity/status and one reason: PHYSICAL_STATUS, OPEN_LINKED_STOP, TRANSFER_OWNERSHIP or MACHINE_UNAVAILABLE. The existing API returns localized HTTP409 with that bounded condition. Ordinary permission/queue failures retain their original contracts. Supported Start writes use Read Committed; Repeatable Read/Serializable fail closed with40001 rather than accepting an old transaction snapshot. No global isolation settings changed. The standard command path holds structure before item/line/center locks, serializing maintenance verification, status/restart and transfer operations. Later physical changes may occur after a valid Start; the guard validates at transaction linearization, not future uptime.

## Nonbinding reader and minimal Floor UI

Protected stable `production_start_readiness(factory uuid,item uuid) returns jsonb` requires Factory view plus Orders view, without exposing Maintenance notes or requiring Maintenance administration. It returns exact factory/item, persisted queue-head eligibility, scoped post-maintenance physical readiness/machine/reason, and current maintenance occupancy. One current clock evaluation, no writes or write locks. The existing Start capacity guard still checks both the persisted plan and intended working-calendar execution span; the new reader does not duplicate that calendar/duration engine or promise future availability. Start always rechecks its authoritative conditions.

Existing Floor queue labels now say Queue ready. A small shared control displays physical preparation readiness/current maintenance block and exact machine, with EN/AR/RTL, explicit Refresh and recheck-after-Start. View-only staff see information without a Start action. Loading/unavailable/wrong-scope/denied/blocked reads cannot claim ready or enable Start. This local UI requires the matching new reader/schema before hosted acceptance; no hosted availability is claimed. Existing native styling/layout reused; no Floor redesign, automatic restart, recurring maintenance or Loss calculation changes.

## Focused verification

- Fresh89/89 Node checks: new preparation control, scope/permission/i18n, existing execution queue/Floor rendering/machine/flow regressions. Zero failed/skipped.
- Fresh standalone PostgreSQL:37 new readiness assertions +32 existing reservations +5 recording +10 transfers =84 assertions. Existing complete `tests/production-execution.test.sql` also passed/rolled back against a new isolated local demo fixture, including execution rollback/projection/queue/history/permissions. No TESTING scenario or real account selected.
- Eleven actual two-connection races with observed Lock waits: restart/stop/Start ordering, verification release and failed hold, duplicate Start, authority revocation, transfer-versus-home Start in both directions, stopping an OPEN borrower and explicit transfer return. No deadlock/stale unsafe Start. Additional checks: manually stopped alternative preserved after return, read-only readiness, old-snapshot rejection. Private activation gate finishes false.
- Fourteen actual-component browser checks: IDLE/RUNNING, six blockers, rejected synthetic Start followed by refresh, wrong scope/read denial, no-maintenance case, view-only authority and loaded EN desktop/AR390px. Zero page errors/no horizontal page overflow; screenshots reviewed. Synthetic reads and rejected writers, not hosted authenticated persistence or full Floor physical acceptance.
- TypeScript, final isolated build, whitespace and baseline preservation pass; generated configs/types restored byte-exact and build/browser evidence outside Git. Owned test processes stopped and disposable PostgreSQL data removed; existing portable17.11 reused, no installation/service/dependency/system PATH change.

SQL evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-readiness-20261014-run6\results`; remaining evidence `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Readiness-20261014`. Initial local checks exposed a fixture variable-name collision, a reasonless fixture replan and a reader statement-time mismatch inside a long transaction; fixtures were corrected and the reader aligned to the existing current-clock capacity contract. No weakened application checks. Normal tests derive approvals/physical stops/closure/verification via existing public commands. One explicitly labelled fixture-owner-only inconsistent historical release verifies fail-closed handling of an open linked stop; it is not a supported application write or a security bypass.

Quantity/state comparisons include nonempty Good/source/WIP fixtures, finished/source movements/allocations/reservations and preserved downtime/saved Loss rows. Start writes only its normal execution/assignment facts; no duplicate Good/Scrap/WIP, stock movement, downtime rewrite or recalculation. Package-only view/edit grants pass; denied callers/cross-factory IDs/private-body access fail. Local Auth/Storage shims are not GoTrue/PostgREST acceptance.

## Remaining boundaries

Activation remains disabled. Matched hosted schema/RPC/session/RLS/physical user acceptance, Phase5D Loss interpretation/presentation and later scoped reader bounds remain separately authorized work. PRODUCT_DIFFERENTIATORS reviewed; no deployed/classification claim change warranted, file preserved. No Phase5D work. Stop after local Phase5C.

## Exact Phase5C files

Modified:
- `HANDOFF.md`
- `docs/maintenance-planning-v1-backend.md`
- `docs/maintenance-planning-v1-ui.md`
- `src/app/api/data/route.ts`
- `src/features/FactoryFloorV2.tsx`
- `src/locales/en.json`
- `src/locales/ar.json`
- `tests/maintenance-planning/run-local.ps1`
- `tests/maintenance-planning-ui/fixture.tsx`
- `tests/maintenance-planning-ui/preview.mjs`

New:
- `supabase/migrations/20261014054829_maintenance_production_readiness_v1.sql`
- `src/app/api/production-readiness/route.ts`
- `src/features/ProductionStartReadiness.tsx`
- `tests/maintenance-readiness.test.mjs`
- `tests/maintenance-planning/readiness-fixture.sql`
- `tests/maintenance-planning/readiness.test.sql`
- `tests/maintenance-planning/readiness-concurrency.mjs`
- `tests/maintenance-planning-ui/readiness-browser-check.mjs`

---

# Maintenance Planning V1 — Phase 5B (2026-10-12)

**LOCAL PHASE 5B COMPLETE — ACTIVATION BLOCKED.** Continued development/bb0d20e with all earlier uncommitted work retained. One new forward migration `20261012124447_maintenance_actual_stop_associations_v1.sql`; 87 local files, all 86 previous migration bytes and the untracked Design System preserved. No remote contact, activation, deployment, staging, commit, push or main change. TESTING82 remains historical/unqueried. Export Reader is excluded from local execution and must not deploy incidentally.

## Association and physical-stop contracts

- `stop_machine_for_maintenance(factory uuid,work_center uuid,nature text,reason uuid,activity text,notes text,schedule uuid,expected_revision integer,expected_request_revision integer,request_id uuid) returns uuid`: explicit selection only. Requires Factory view, Maintenance view and Centers edit OR Machine Status edit, using existing effective per-person/package grants. Private activation remains false. Under the existing factory structure lock, reload permissions/request/schedule, validate both revisions, confirmed current window and exact MACHINE resource/configuration, call the unchanged physical stop RPC, append the link and store the existing actor-bound command retry. Returns the one physical event. Failure rolls all effects back. Successful identical replay returns that event even if subsequent schedule revisions changed; different actor/payload conflicts. Already-stopped machines create no new event. Ordinary emergency stops keep the existing command and do not require a maintenance selection.
- `correct_maintenance_stop(factory uuid,event uuid,schedule uuid,approval_revision integer,operation text,reason text,expected_revision integer,request_id uuid) returns uuid`: Factory view AND Maintenance edit AND Downtime edit; mandatory reason, event revision and actor-bound retry. LINK validates a genuine same-factory event against the explicitly recorded confirm/reschedule revision and MACHINE scope/window. UNLINK copies the prior frozen approval. Closed events may be relinked/reassigned using historical approval evidence; an existing open link must be physically closed before removal/reassignment, preventing correction from releasing an unsafe hold. Legacy-unknown nature is rejected rather than guessed.
- `maintenance_stop_context(factory uuid,machine uuid default null,maintenance_request uuid default null,history_page integer default 1) returns jsonb`: exactly one scope. Floor choices require physical stop authority and Maintenance view; eligible current approved windows only, inactive gate gives none. Detail uses existing request visibility plus Downtime view. Current links/choices are capped at100 and fail closed on overflow; immutable history has25-row pagination and includes later corrections/reassignments to previously associated events. API responses are private/no-store.

Append-only `maintenance_stop_associations` stores event revision/previous link, LINK/UNLINK, factory/schedule, immutable approved revision/window/resources, planned-versus-contextual-unplanned relationship, actor/name/server time/reason/retry, and IDs/timestamps/model versions/result hashes of any reviewed Loss evidence. Current truth is the highest event revision; multiple genuine events per schedule are supported. Composite factory FKs, uniqueness, RLS, revoked direct table/helper rights and an UPDATE/DELETE rejection trigger protect the ledger. Existing request MANUAL/DOWNTIME origin, original downtime classification/timestamps and saved Loss rows are never rewritten. New supersession references annotate association history only; Loss math/presentation remains Phase5D.

## Lifecycle and existing UI

The shared occupancy calculation adds open linked stops to retained capacity, including a contextual stop beginning before its window; no unlike quantities or duplicate reservation rows. Protected schedule/request triggers reject active-stop release, cancellation, rescheduling and successful verification. Unplanned invalidation and failed independent verification remain allowed. Completion retains the existing hold. Closing a physical event is still an explicit existing machine-state action; verification never restarts a machine. No Production Start readiness change or automatic physical action.

Factory Floor adds one optional native selector, explicit choice, unchanged ordinary stop path and stable linked retry identity. Maintenance Details adds actual events, approval/relationship, immutable paginated history, saved-review notices and a reason-required closed-event unlink action. Historical relink/reassignment is available through the protected correction RPC; no separate association editor/redesign is added. Existing native controls, styles and EN/AR/RTL remain. Server validates final selection even if the displayed choice becomes stale; no automatic fallback from a selected operation to an ordinary stop. Scoped detail responses fail closed.

## Verification and limits

- Fresh focused code/API/Maintenance/Downtime/Floor/flow tests:134/134, zero failed/skipped.
- Standalone PostgreSQL17.11:49 new actual-stop assertions;147 preserved Maintenance assertions across lifecycle/reservations/recording/transfers/readers/confirmation (137 in run3,10 transfers in final run8):196 passed. Checks include forced post-stop append failure/rollback, replay/conflicting payload, wrong machine/factory/time/revision, existing and package authority, multiple stops, immutable corrections/estimate preservation, active reschedule/unschedule/cancel/verification guards, contextual emergency compatibility, unchanged production records and nonempty shared Good/WIP/source/balance ledgers.
- Real multi-connection races:7 new stop/correction +4 existing Maintenance +20 existing confirmation =31; lock waits observed, no deadlocks/duplicates. Includes identical stop/correction retries, competing writes, stop versus release, approval change and authority revocation during waits. Additional old-snapshot denial and final disabled-gate check.
- Actual-component isolated browser:8 scenarios, zero page errors; EN desktop and AR390px with actual loaded stop rows, no horizontal page overflow. Explicit/no-implicit selection, correction reason/retry, open-stop safety, history, permission UI and denied readers. Synthetic reads; every browser writer rejected. This is not hosted Auth/PostgREST acceptance or actual full-Floor persisted stop execution.
- TypeScript, final isolated production build and whitespace/preservation checks pass. Generated build configuration/types restored exactly, output outside Git; running app/simulation build directories untouched.

Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Stops-20261012`; disposable SQL `FactoryLean-Quality-Postgres-stops-20261012-run3/results` and final `run8/results`. Reused the approved portable runtime; no install, service, PATH/dependency change or remote clients. Initial fixture failures concerned running-before-confirmation, statement-time setup, package ID/helper authority and composite balance keys; fixtures corrected without weakening application checks. All owned clusters stopped/data removed, logs/scripts retained. Browser fixture stopped after checks. Existing loss calculation source and Production Start function unchanged.

Activation is still blocked. Phase5C readiness, Phase5D Loss interpretation/presentation, later reader bounds and separately authorized hosted Supabase/physical acceptance remain. No activation/deployment recommendation or full Maintenance Planning completion claim. Stop after Phase5B; no Phase5C implementation.

## Exact Phase5B files

Modified:
- `HANDOFF.md`
- `docs/maintenance-planning-v1-backend.md`
- `docs/maintenance-planning-v1-ui.md`
- `docs/PRODUCT_DIFFERENTIATORS.md`
- `src/app/api/data/route.ts`
- `src/app/api/maintenance/route.ts`
- `src/features/FactoryFloorV2.tsx`
- `src/features/MaintenanceRequest.tsx`
- `src/locales/en.json`
- `src/locales/ar.json`
- `tests/maintenance-planning/run-local.ps1`
- `tests/maintenance-planning-ui/fixture.tsx`
- `tests/maintenance-planning-ui/preview.mjs`

New:
- `supabase/migrations/20261012124447_maintenance_actual_stop_associations_v1.sql`
- `src/features/MaintenanceActualStops.tsx`
- `src/utils/maintenance-stops.mjs`
- `tests/maintenance-stops.test.mjs`
- `tests/maintenance-planning/stops.test.sql`
- `tests/maintenance-planning/stops-concurrency.mjs`
- `tests/maintenance-planning-ui/stops-browser-check.mjs`

---

# Maintenance Planning V1 — Phase 4 (2026-10-12)

**LOCAL PHASE 4 COMPLETE — ACTIVATION BLOCKED.** This section is the current milestone; all earlier entries below retain their dated historical evidence. Continued development at bb0d20e5dd433b896dd319f56e75f0d9eb5d2862 with prior uncommitted work preserved. One new forward migration: `20261012105338_maintenance_preview_confirmation_v1.sql`. All85 prior migration files preserved byte-exact;86 local files now. No remote history query or deployment. TESTING82 is historical, not confirmed-current. Export Reader remains excluded from local SQL execution and must never be deployed incidentally.

## Protected contract and locking

Existing public `maintenance_planning_command(factory uuid, maintenance_request uuid, operation text, payload jsonb, expected_revision integer, request_id uuid) returns uuid` signature retained. `confirm` and `reschedule` require payload `context_hash` (64 lowercase hex SHA256) and positive integer `request_revision`; expected_revision is still the schedule revision. Confirm uses the persisted proposed window and rejects caller start/end fields. Reschedule binds the exact new normalized window and retains its required reason. Other command shapes remain unchanged.

Factory view, Maintenance view, Orders edit and Orders view authorize these capacity commands, before and after the existing factory structure advisory lock. Request and schedule row locks follow that structure lock, then current request/schedule revisions and shared context are reloaded. Revision/hash mismatches raise SQLSTATE40001 maintenance_preview_stale; the command API returns HTTP409 `{error:mpPreviewStale, conflict:STALE_CONTEXT}` without raw details. Missing proof raises22023 maintenance_preview_required. Configuration, duration/window, lifecycle, OPEN transfers, completeness and shared authoritative capacity checks remain mandatory after proof validation. A fresh hash for BLOCKED or UNKNOWN context cannot authorize a reservation. Ordinary callers cannot bypass this with old confirm/reschedule payloads or direct table writes.

Actor-bound identical successful retries return the stored result before changed-revision comparison and append no resources/history/command. Changed retry payload or actor is rejected. The approved fingerprint/request revision are preserved in the existing protected command ledger, linked to the recorded schedule history retry ID; no new audit table. Persistence failures roll back schedule, resources, immutable history, audit and command ledger together.

The shared stable reader context and command evaluation use the same version4 fingerprint. SHA256 over canonical JSONB includes factory ID, exact candidate range, persisted request/schedule and revisions, derived machine/whole-line scope, factory timezone/calendar, selected and relevant whole-line/alternative machine topology, categories/positions/dependency/buffer/archive state, current physical states/assignments, ordered capabilities/alternatives, relevant explicit Product routing, actual OPEN transfer identities/ownership and relevant effective Production/Maintenance occupancy. Arrays are deterministically ordered; serialization runs in UTC. Evaluation timestamp, activation flag and actor permissions are excluded. Time-dependent changes to effective missed/held occupancy still invalidate the context when their actual scheduling meaning changes. Configuration hash remains separate metadata. Fingerprint is change evidence, never an authorization token or replacement for SQL enforcement.

Normal configuration, planning, execution, transfer, lifecycle and schedule commands retain the existing structure-first lock. Two previously uncoordinated fingerprint inputs now use minimal wrappers: public configure_working_calendar and private update_settings (used by unchanged public update_settings). Their public signatures, settings permissions, validation and data semantics are preserved; structure serialization precedes inherited factory row locks. The inherited private base functions are revoked from ordinary callers. No topology editor, calendar redesign or physical automation added.

A confirmation/reschedule in Repeatable Read or Serializable is rejected with40001 because its earlier transaction snapshot cannot promise to reload commits observed during the structure-lock wait. The supported write boundary uses PostgreSQL Read Committed (Read Uncommitted has PostgreSQL's same semantics). See [PostgreSQL isolation documentation](https://www.postgresql.org/docs/17/transaction-iso.html). No isolation setting is changed globally or per hosted database. Readers remain stable/read-only and nonbinding.

## Drawer and compatibility

Latest matching server preview is carried into the existing drawer and confirmation/reschedule payload builder. Identity binds factory, request, request/schedule revisions, factory timezone, snapshot and draft window. Edited, delayed, wrong-scope, loading/error and expired responses cannot retain CLEAR or confirmation-ready state. Expiry is60seconds; malformed local times fail closed. Same-window rechecks send the hash; stale409 explains refresh/re-preview in EN/AR. Confirmation/rescheduling remain unconditionally disabled in this local milestone, including with inactive gate. Proposals do not reserve capacity or require an authoritative preview. No simulated successful UI reservation.

Conservative unknown independent routing behavior is preserved. The older transfer fixture now explicitly records independent routing and establishes a valid non-overlapping Production window before requesting its preview; this is local test-fixture setup, not a production topology or QA scenario change. Legacy regression fixtures use a disposable-only adapter that obtains a real preview or replays the exact stored retry payload; every underlying command still enforces JWT actor permissions. New Phase4 concurrency confirmations invoke the actual public RPC directly with a separately captured preview. No test helper is in an application migration. Routing mutation has no application writer; its concurrency test is an explicitly serialized disposable fixture-owner mutation, not a claim of hosted routing UI acceptance.

## Current verification and evidence

- Focused Node/API/Maintenance/Planning/Execution queue/flow/Floor/table tests:168/168, zero failed/skipped.
- Standalone PostgreSQL rollback:33 new contract assertions,50 preserved reader/resource assertions,64 Maintenance and148 Quality/source/High-Scrap assertions:295 passed. Includes zero-to-positive KG/Sales/source conservation regressions, valid confirmation/rescheduling, invalid proof, revisions, original permissions/factory isolation, forced post-reservation persistence failure and retry-after-rollback.
- Actual multi-connection races:20 new Phase4 +4 Maintenance +8 Quality/source +2 readers =34 passed. New checks cover two users on one request, identical retry, production/Maintenance booked after preview, capability/alternative configuration, target/sibling/archive topology, explicit routing, calendar/timezone, request/schedule revisions, reservation and request cancellation, confirmed rescheduling, adjacent bookings, actual OPEN ownership and permission revocation while waiting. Wait-event evidence proves second connections actually blocked on locks; no deadlock or stale acceptance in these scenarios. Additional old-snapshot denial and three reader read-only/gate checks passed.
- Actual-component browser:26/26 (13 preserved,6 reader,7 new contract), zero page errors; EN/AR desktop/tablet/390px. Synthetic GETs and every operational write rejected; no hosted or persisted browser-success claim.
- TypeScript and final isolated production build passed. Distinct build directory, never the running .next directory; generated tsconfig/next-env restored byte-exact and build outputs moved outside Git. Initial out-of-project Turbopack output attempts failed; successful final build used a checked separate in-project output and preserved its artifacts outside Git.
- Git/current-file whitespace,85 prior SQL hashes, untracked Design System bytes, branch/HEAD/main/staging preservation checked. No account credentials or environment files added.

Evidence outside Git: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Contract-20261012` (focused-final,typescript-final,build-final-complete,three final browser logs/proof,preservation); SQL rollback `FactoryLean-Quality-Postgres-contract-20261012-run5/results`; final concurrency `run8/results`. Run5 rollback suites all passed, then its authenticated regression adapter failed schema access; fixture-only grants/order were corrected. Run7 verified preserved races and most new cases but expected rejection for an identical reschedule retry; that test was corrected to distinct retry IDs. Final run8 passed all concurrency scenarios. Production migration bytes are identical between final rollback and concurrency runs. These are local service shims, not GoTrue/PostgREST/hosted accounts. Existing portable PostgreSQL17.11 only, loopback55444; owned clusters stopped and disposable data removed. Isolated browser fixture4205 stopped; localhost3000/3001 untouched. No installation, service, dependency or system PATH change.

## Remaining activation blockers

Preview-to-confirmation binding is now verified locally. The private activation gate stays false; there is no activation command or migration UPDATE. Hosted Supabase/PostgREST/session/RLS acceptance and real physical/factory readiness still require a separately authorized deployment and acceptance phase. Actual-stop association/Production Loss context and legacy500-record queue/Gantt pagination remain separately scoped, unchanged follow-ups. No full Maintenance Planning V1 completion or release/activation recommendation. PRODUCT_DIFFERENTIATORS reviewed; no material hosted differentiation claim changed, so its existing content is preserved.

## Exact Phase4 files

Modified relative to the Phase3B starting snapshot (22):

- `HANDOFF.md`
- `docs/maintenance-planning-v1-backend.md`
- `docs/maintenance-planning-v1-ui.md`
- `src/app/api/data/route.ts`
- `src/features/MaintenancePlanning.tsx`
- `src/features/MaintenancePlanningReaders.tsx`
- `src/features/maintenance-planning-types.ts`
- `src/utils/maintenance-planning.mjs`
- `src/utils/maintenance-planning-readers.mjs`
- `src/locales/en.json`
- `src/locales/ar.json`
- `tests/maintenance-planning.test.mjs`
- `tests/maintenance-planning-readers.test.mjs`
- `tests/maintenance-planning/fixture.sql`
- `tests/maintenance-planning/concurrency.mjs`
- `tests/maintenance-planning/run-local.ps1`
- `tests/maintenance-planning/reservations.test.sql`
- `tests/maintenance-planning/lifecycle.test.sql`
- `tests/maintenance-planning/recording.test.sql`
- `tests/maintenance-planning/transfers.test.sql`
- `tests/maintenance-planning-ui/preview.mjs`
- `tests/maintenance-planning-ui/readers-browser-check.mjs`

New (5):

- `supabase/migrations/20261012105338_maintenance_preview_confirmation_v1.sql`
- `tests/maintenance-planning-contract.test.mjs`
- `tests/maintenance-planning/reader-contract.test.sql`
- `tests/maintenance-planning/contract-concurrency.mjs`
- `tests/maintenance-planning-ui/contract-browser-check.mjs`

No staging, commit, push, main modification, activation, deployment or TESTING/DEV/PROD/Simulation operations. Stop after the Phase4 report.

---

# Maintenance Planning V1 — backend phase, 2026-10-12

## Phase 3B — current local reader milestone (2026-10-12)

**LOCAL PHASE 3B COMPLETE — ACTIVATION BLOCKED.** One new forward migration `20261012085636_maintenance_planning_readers_v1.sql`; all84 earlier migration bytes preserved,85 local files now. No remote history query, deployment, activation, commit or push. Previous TESTING82 is historical and must be freshly verified only in a separately authorized deployment task. Export Reader is still excluded from disposable SQL tests and must not be incidentally deployed.

Implemented protected stable SECURITY DEFINER/empty-search-path RPCs:

- `maintenance_planning_preview(factory uuid,maintenance_request uuid,candidate_start timestamptz,candidate_end timestamptz,expected_request_revision integer,expected_schedule_revision integer,expected_context_hash text DEFAULT NULL) RETURNS jsonb`.
- `maintenance_planning_gaps(factory uuid,maintenance_request uuid,search_start timestamptz,search_end timestamptz,expected_request_revision integer,expected_schedule_revision integer,window_minutes integer DEFAULT NULL,result_limit integer DEFAULT 10,after_start timestamptz DEFAULT NULL,expected_context_hash text DEFAULT NULL) RETURNS jsonb`.
- `maintenance_planning_history(factory uuid,maintenance_request uuid,page_size integer DEFAULT 25,before_revision integer DEFAULT NULL,through_revision integer DEFAULT NULL) RETURNS jsonb`.

Preview/gaps require factory:view + maintenance:view + orders:view through the existing per-person effective-grant/approved-membership/scoped-support rules. History requires factory:view + maintenance:view. No grants were assigned to people or packages. Private helpers revoked from PUBLIC/anon/authenticated; no direct-table access added. Actor display names are recorded names, not Auth profiles. Whitelisted historical topology excludes raw capabilities/alternatives/Auth payloads.

Shared `private.maintenance_occupancy` supplies resource- and effective-range-filtered, set-based intervals. Existing `maintenance_capacity_conflict` signature, maintenance-before-production/first-reference precedence and reason keys retained; protected command signatures unchanged. Machine/current line/explicit Product routing/actual OPEN borrower mapping reuse the original predicates. One reservation row despite machine + line resources. Active/unknown production is open-ended; missed/invalidated/actual holds remain protective; released/proposed records do not occupy. Stored valid Production windows already include setup/calendar; maintenance duration is continuous elapsed time, with no alternative/buffer credit. Unknown independent routing/current unassigned-running machines or missing configuration/duration fail uncertain instead of inventing capacity.

Readers use one statement snapshot and captured statement timestamp, no write locks or audit/history/command writes. Scope records above10000 yield INCOMPLETE, never usable suggestions. Gap sweep materializes occupancy once, uses a running maximum to merge nested overlaps, then returns ordered openings; no per-minute/per-candidate SQL calls. Search max31days, results max20, optional explicit elapsed-window slack; cursors require the same range/request/context hash. Occupancy completeness and suggestion-list pagination are separate. Safe conflict explanations are bounded (preview50, gaps20) with completeness flags. New gap/preview reads are independent of the legacy500-record board cap.

Preview returns eligibility, timezone, revisions, scope, duration/slack, physical readiness now, configuration/context hashes, coded conflicts/unknowns, binding:false and confirmation_available:false. Missing duration without an explicit end returns end:null, not a made-up estimate. History page max50, descending revision cursor and fixed high-water; before/after windows/states, reason, stored actor/time and recorded scope. Before-scope is available only for matching adjacent revision evidence, first proposal records no prior schedule, gaps return NOT_RECORDED. No current configuration substitutes for missing history. Existing current reader gains additive capability metadata without changing its paging/signature/grants.

Fresh validation:161/161 focused Node/API/Planning/Maintenance/Execution/flow/Floor/table regressions, zero failed/skipped. Final standalone PostgreSQL reader suites50 assertions (37 reader +13 resource), existing Maintenance64 and Quality/source/High-Scrap148 assertions (262 total across these unchanged/current suites). Full run6 verified existing regressions and concurrency; targeted run7 reverified readers after the no-invented-end correction. Actual races: existing4 Maintenance +8 Quality/source +2 new reader races =14; three additional authenticated read-only/gate checks passed. Existing test-only confirmation fixtures temporarily enable the gate solely in disposable regression state; application migration/default remains disabled, final reader race confirms false before cluster stop. No hosted users or Supabase Auth changes; existing local Auth/Storage shims are not GoTrue/PostgREST integration.

TypeScript and final isolated production build passed; generated config/type files restored byte-exact, build artifacts outside Git. Nineteen actual-component browser checks passed (13 preserved +6 reader), zero page errors, desktop/tablet/EN/AR/390px. Browser responses are labelled synthetic READ fixtures with all writes rejected, not database persistence/hosted acceptance. Portable PostgreSQL reused on loopback55443, no install/service/PATH/dependency change; owned clusters stopped and data removed. Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Readers-20261012` and `FactoryLean-Quality-Postgres-readers-20261012-run6/results`, `run7/results`.

Activation blockers remain: exact preview-to-confirmation context binding is not implemented; final writes still revalidate legality under their existing locks, without binding to the earlier displayed context. Actual-stop/Loss-context integration and hosted permissions/PostgREST/physical workflow acceptance remain separate. Legacy queue/Gantt collection still caps500 records and fails closed; scoped board pagination remains follow-up work. No full Maintenance Planning V1 completion claim.

Exact Phase3B files: this document, HANDOFF.md, docs/maintenance-planning-v1-ui.md; new migration above; src/app/api/maintenance-planning/route.ts; src/app/globals.css; src/features/MaintenancePlanning.tsx, MaintenancePlanningReaders.tsx (new), maintenance-planning-types.ts; src/utils/maintenance-planning-readers.mjs (new); src/locales/en.json and ar.json; tests/maintenance-planning-readers.test.mjs (new); tests/maintenance-planning/{readers.test.sql,reader-resources.test.sql,readers-concurrency.mjs} (new), run-local.ps1; tests/maintenance-planning-ui/{preview.mjs,browser-check.mjs,readers-browser-check.mjs (new)}. Prior work retained; no applied migration edit or unrelated business change.

Phase 2 now adds local queue/proposal/Gantt/availability UI without changing this backend migration or activating it. Exact implementation and missing protected preview/history readers: [maintenance-planning-v1-ui.md](maintenance-planning-v1-ui.md). Status **PARTIAL — BACKEND DEPENDENCY REQUIRED**. The backend-only scope/results below describe the preserved Phase 1 evidence.

## Status and boundaries

Implemented locally on development from pushed checkpoint `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`. No frontend scheduling controls, recurring PM, future alternative allocations, actual-stop associations or Production Loss changes. Confirmation and planned starts are **inactive by default**. This is not the complete Maintenance Planning feature or hosted acceptance.

New forward migration: `20261012062208_maintenance_planning_reservations_v1.sql`. The original 83 migration files are preserved. Repository now has 84 files; last recorded TESTING state remains 82 applied, not freshly queried. Export Reader and this new migration are not deployed by this task. The disposable local runner explicitly excludes `20261006072000_factory_export_reader.sql`.

## Persistence and authorization

Existing Maintenance Requests receive nullable CORRECTIVE/PLANNED kind, positive estimated elapsed minutes, optional finite preferred start/end and planning notes. NULL kind preserves historical uncertainty. Origin remains MANUAL/DOWNTIME; downtime-origin requests cannot be reclassified as PLANNED. Old request payloads and emergency corrective progress remain valid.

Three protected entities hold current schedules, machine/line resources and immutable schedule revisions. One current schedule per request; resources use factory-scoped foreign keys and unique machine/line indexes. Proposed windows have no capacity. Confirm/reschedule uses server-derived scope and timestamps, expected schedule revision and the existing actor-bound Maintenance command ledger. Details use the request revision. Repeated identical commands add no reservation or history; changed payload/actor/revision under the same retry ID is rejected. Reschedule/unschedule requires a reason; neither moves production.

Request creation requires maintenance:create; detail changes maintenance:edit; capacity commands maintenance:view AND orders:edit, with factory:view and post-lock checks. Planned start/completion keep existing manager/own-assignee authority. Independent verification keeps the existing manager grant and exclusion of assignee/completer. New tables and inherited private base functions have no direct authenticated writes/execution bypass. The application has no activation command.

## Shared conflict and lock contract

`private.maintenance_capacity_conflict` returns a structured reason/reference; the assertion wrapper raises that reason with JSON DETAIL. It checks half-open overlap, persisted production and maintenance, explicit Product routing machine references and actual OPEN transfer ownership. Both maintenance confirmation and production interval guards use it. Authorized API callers receive localized safe error keys, not internal SQL.

The selected machine is always reserved. Any line-affiliated machine also reserves whole-line capacity because the existing scheduler cannot commit partial-line routing/throughput. A line-less, configured independent machine reserves only itself; assignments/routing/OPEN ownership still participate in conflict checks. Configured alternatives and buffer minutes do not grant future capacity or fabricate an OPEN transfer. A candidate involving unresolved actual transfers is rejected. Missing machine/category/line, invalid windows and unknown execution duration produce explicit errors.

Plans preserve setup, working calendar, existing rate checks, locks, reasoned revisions and persisted timestamps. Structure serialization precedes production item/line locks. Small wrappers retain inherited validation bodies for Planning, generic writes, plan locks, capability/alternative configuration and physical status commands; private base functions are revoked from ordinary callers. Current execution/transfer functions already use structure-first locking. The migration also adds row-boundary guards so generic writes cannot evade maintenance overlap protection. Privileged raw multi-table SQL is not an application scheduling interface.

## Execution, holds and revalidation

Production early starts validate a conservative intended finish using full target quantity, slowest usable rate, setup and working calendar. This is a conflict bound, not a fabricated actual completion time. No maintenance relevant to the resource means existing execution remains unchanged. Transfers into exclusive reserved capacity are rejected; permanent line ownership and OPEN-transfer lifecycle are not rewritten.

Planned maintenance starts require an enabled gate, CONFIRMED/non-invalidated schedule, prepared physical machine, matching configuration evidence, no unresolved transfer or active conflicting production, and enough remaining approved time for the estimate. A window may include explicitly proposed extra time beyond the estimate; a late start with insufficient time must be rescheduled. No start timestamp is backdated.

Start records a separate actual hold. COMPLETED and failed verification retain it; independent VERIFIED releases it without changing physical machine status. In-progress work cannot be unscheduled/cancelled to release its hold. A confirmed missed window does not silently free future capacity when its end passes: the reader exposes `missed_window`, and the planner must explicitly review/reschedule/unschedule. Actual elapsed overruns are separately exposed. Proposed cancellation is audited without capacity reservation.

New output is protected at production-entry INSERT, covering completed-item WIP reprocessing on independent machines. Historical correction UPDATEs remain outside this execution guard; no Good/Scrap/WIP/source arithmetic was changed.

Machine topology/category/archive changes, relevant capability/alternative edits, line archival and unexpected physical stops invalidate confirmed readiness with retained approval/history. Scope checks also include a reserved machine's current line, so reassignment cannot hide the reservation. Existing unexpected breakdown recording and CORRECTIVE/legacy repair remain available. Physical stops are explicit existing commands only; there is no automatic downtime or loss generation.

## APIs and exact task files

- `src/app/api/data/route.ts`: command validation, per-person checks and safe conflict keys.
- `src/app/api/maintenance-planning/route.ts`: protected paginated current schedule/resource reader, inactive/missed/overrun status.
- `src/utils/maintenance-planning.mjs`: backend command shape and permission contract.
- `src/utils/maintenance.mjs`, `src/features/maintenance-types.ts`: additive request fields.
- `src/locales/en.json`, `src/locales/ar.json`: conflict messages; no scheduling UI.
- New migration above; this document, HANDOFF.md and PRODUCT_DIFFERENTIATORS.md.
- `tests/maintenance-planning.test.mjs`: 9 code/API/locale tests.
- `tests/maintenance-planning/fixture.sql`, `reservations.test.sql`, `lifecycle.test.sql`, `transfers.test.sql`, `recording.test.sql`, `concurrency.mjs`, `run-local.ps1`: disposable PostgreSQL fixtures, rollback tests, real concurrency and guarded cleanup.

## Verification

- Focused Node/API/UI/domain regressions: **165/165** (includes 9 new tests), zero failed/skipped. Maintenance/Planning/queue/flow/Factory Floor/Downtime/Loss presentation behavior retained.
- Recording, unfinished/WIP and Quality domain/API regressions: **65/65**, zero failed/skipped.
- Standalone PostgreSQL: **64 new assertions** across four rollback suites (32 reservations,17 lifecycle,10 transfers,5 recording), plus **148 existing Quality/source/High-Scrap assertions** across five rollback suites.
- Four actual multi-connection Maintenance races: identical retry, competing reservations, production versus confirmation, capability edit versus planning; no double booking/deadlock in these scenarios.
- TypeScript passed; isolated production build passed. Generated config/type files restored exactly and TypeScript passed after restoration; build output retained outside Git.
- Existing **8/8 Quality/source concurrency regressions passed**, including competing Sales reservations, reserved-stock rejection protection, atomic KG correction/rollback/replay and authority revocation while waiting. Total actual multi-connection scenarios: **12/12**.

SQL uses existing portable PostgreSQL 17.11 on unused loopback-only port55443, with no installation/service/PATH/dependency changes. Test Auth/Storage schemas are local service shims, not real GoTrue users. Activation is enabled only inside the disposable local test database; no application activation endpoint exists. Failed local runs were stopped/cleaned, then corrected; no remote retry or history repair. All local operational fixtures are disposable; test scripts/results are retained. Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Maintenance-Planning-20261012` and final `FactoryLean-Quality-Postgres-maintenance-20261012-run8/results`.

## Activation dependencies and remaining work

Keep confirmation disabled until separately reviewed activation. Next phases must connect the existing Planning UI/gap/load/Gantt consumers to complete maintenance occupancy, add bounded schedule-history presentation, and integrate explicit actual-stop links and Loss context without misclassifying intentional idle. Cross-machine future allocations, physical buffer proof and a routing optimizer remain deferred.

Real Supabase sessions, PostgREST signatures/schema availability, authenticated hosted permissions, actual factory workflows and physical readiness have not been tested in this phase. Local roles and rollback evidence do not substitute for that acceptance. No TESTING/DEV/PROD/Simulation contact or deployment, commit/push/main change is authorized here. Deployment requires separate approval and fresh intended-project history verification; never apply Export Reader incidentally.
