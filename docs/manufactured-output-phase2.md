# Manufactured output Phase 2 — Production and Quality integration

24 October 2026. **LOCAL COMPLETE / INACTIVE for positive ordinary shift output.** This is a parallel, locally testable workflow, not an activated replacement for existing production accounting. Warehouse posting and Planning completion integration remain outside this phase.

## Contracts implemented

- `record_manufactured_output` reuses V3 shift/context authorization, exact numeric transport, existing execution validation and immutable UUID receipts. The raw intent and original finished/unfinished groups are preserved in the Phase 1 declaration. Unordered missing-operation sets use configured Product routing work centers; no new routing engine or SKU combinations.
- A private, transaction/backend/actor-bound context suppresses legacy finished credit and aggregate available-WIP creation only for this protected adapter. Arbitrary client settings cannot establish this context. Existing recording paths retain their immediate-credit behavior.
- The protected Quality command reuses Phase 1 classification, quantity conservation, revisions, release entitlements and immutable events. Quality can reclassify, split, reject, partially release and amend. A decision accounts for the entire source quantity; release may cover only part. Unreleased quantity is not Warehouse stock. Reclassification/rejection does not fabricate Scrap KG or deduct nonexistent inventory.
- Original, corrected and current Quality classifications are distinct. Quality is authoritative in the new output reader without Production approval. Production receives informational updates with original/current results, reasons, actor/time and per-person read handling. Reading is not approval or task completion.
- Existing Production correction proposals/approval are reused. Supported pre-receipt finished quantity, Scrap KG and recording-context corrections preserve audit, invalidate prior Quality release, and require reinspection. A newer output revision makes pending proposals stale. Unfinished-group resizing/work-note changes and corrections after receipt/disposition fail closed; no invented reconciliation.
- Factory/person/package checks, factory → structure → source locking and post-wait authorization/gate checks remain authoritative. Enrollment crossing the shift deadline rolls the whole transaction back. No duplicate Good, available WIP, source or stock movement on retry.
- New public RPCs are authenticated-only; private tables/helpers have no client execution/write grants. `/api/manufactured-output` exposes only the reader, recording, Quality and informational acknowledgment commands. No receiving or demand-disposition API was added.

## UI and recovery

Existing V3 recording adds optional unfinished groups, configured missing-operation checkboxes, exact quantities and a clear Quality/Warehouse waiting message. Existing Quality gains a bounded record selector and Actions/Details/inspection dialog. History adds original/current/Quality detail without default table columns. EN/AR/RTL and 390px layouts reuse existing components and styles.

Recording retains existing actor/factory durable intent recovery. Quality/acknowledgment persist the immutable pending UUID/body in actor/factory-scoped session storage before submission; unknown outcomes retry the same intent. Confirmed stale decisions display refresh guidance rather than overwriting newer facts. No automatic fallback to immediate-credit recording.

## Activation and future dependencies

The shipped `private.manufactured_output_enabled` predicate is constant FALSE. The existing public Phase 1 capability also stays FALSE. There is no activation toggle or hosted activation. Only the dedicated disposable preview/test databases replace the private predicate to exercise this path.

Before eventual activation, subsequent authorized phases must implement atomic physical receiving/stock credit and Sales conversion, multi-group unfinished issuance/genealogy and input-bound completion/replacement, post-receipt correction reconciliation, and coordinated consumer cutover. Legacy Production/Floor/Sales/report counters still follow their existing contracts; they are not evidence of new Quality-effective accounting. New unfinished output is neither finished demand nor Sales availability.

Ordinary V3 recording excludes `input_lot_id`; that existing restriction remains. Input-bound processing continues through the separate existing WIP workflow, with no historical conversion. The new source requires positive physical output: standalone zero-output/Scrap-only recording is not exposed by this adapter. Existing inactive-rollout workflows remain intact. These limits must be resolved as appropriate before coordinated activation, not hidden by a fallback.

Purchased materials, external supplier receipts, opening stock and direct machine WIP transfers are outside this manufactured-output Quality gate. No general inbound inspection system was added. Synthetic historical balances were not reconciled or backfilled; they may be reset under separate authorization before activation.

## Verification

| Evidence | Result |
| --- | --- |
| Focused Node: new output helpers + V3 intent + correction view | 45/45 PASS |
| Fresh disposable PostgreSQL 17.11 integration | 38 assertions PASS |
| Actual concurrency/security/gate groups | 6 PASS |
| Full application browser scenarios | 5 PASS, no uncaught browser errors |
| TypeScript, incremental disabled | PASS |
| Isolated optimized Next.js Webpack build | PASS, 28 routes |
| Whitespace check | PASS |

SQL covers 100 finished, 90+10, 90+6+4, exact 19-decimal quantities, UUID recovery/conflicts, Quality changes/releases/rejection, informational reads, correction approval/reinspection, stale proposals, invalid-operation rollback and shift-deadline rollback. A small deterministic legacy fixture still credits 2 finished exactly once and retains 4 available WIP; an invalid ordinary V3 input-lot attempt changes neither. No historical synthetic balance reconciliation.

Concurrency covers duplicate recording UUIDs, competing Quality revisions, permission revocation during lock wait, authenticated/private access and context leakage, gate changes during a wait, and restored shipped-FALSE denial. Test-owned SQL cluster stopped and data removed; scripts/results retained.

Evidence locations:

- SQL: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P2-SQL-111b203c0e374d08b7437c8d4a0b4ee8\results`
- Build/typecheck and pre-task file hashes: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-Phase2-6bd14dc7536e4e89b29a56ff8e91562a`
- Browser: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P2-Preview-dc90af0f71804fffb5da74e9fbff509f\phase2-browser`

Browser testing used the real application and protected SQL with normal synthetic local sign-in, through the existing localhost-only Auth/data adapter. This is not hosted Supabase GoTrue/PostgREST integration evidence. Initial browser execution recorded 90+6+4, Quality changed it to 85 finished plus 15 unfinished with 40 released, and Production marked the notice read. Later smoke passes reused these facts instead of repeating writes. Arabic mobile History Details renders original and effective results. Database tests separately prove stock conservation.

## Local preview

Open `http://127.0.0.1:4214/`. Synthetic local credentials are in the preview directory's restricted `LOCAL-LOGIN.txt`; never copy them into Git or reports. Use Production → Record output, Quality → Quality determination, and Production History → select record → Actions → Details. Existing fixture remains available for read review; new recording still obeys live execution and shift eligibility.

This preview uses only `127.0.0.1:4296` and disposable PostgreSQL `127.0.0.1:55485`, database `factory_lean_quality_local`. Its runtime marker is `FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY`. Original preview `4207/4291/55476` was untouched. The dedicated preview is left running for owner review; the automated SQL cluster on 55484 was removed.

## Exact task file manifest (21)

Existing files modified (9):

- `HANDOFF.md`
- `src/features/ProductionCorrectionDialog.tsx`
- `src/features/ProductionHistory.tsx`
- `src/features/ProductionRecordingV3.tsx`
- `src/features/Quality.tsx`
- `src/services/production-recording-client.ts`
- `src/utils/production-recording-intent.mjs`
- `src/utils/production-recording-v3.mjs`
- `tests/production-recording-full-app/backend.mjs`

New files (12):

- `docs/manufactured-output-phase2.md`
- `src/app/api/manufactured-output/route.ts`
- `src/features/ManufacturedOutput.tsx`
- `src/utils/manufactured-output.mjs`
- `supabase/migrations/20261024075746_manufactured_output_recording_quality_v2.sql`
- `tests/manufactured-output-phase2.test.mjs`
- `tests/manufactured-output-phase2/browser.mjs`
- `tests/manufactured-output-phase2/concurrency.mjs`
- `tests/manufactured-output-phase2/fixture.sql`
- `tests/manufactured-output-phase2/integration.test.sql`
- `tests/manufactured-output-phase2/prepare-preview.ps1`
- `tests/manufactured-output-phase2/run-local.ps1`

103 local migrations; all 102 previous migration file hashes unchanged. Export Reader and Design System unchanged. Prior dirty work preserved; branch development / HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`. No hosted access, activation, deployment or Git write. PRODUCT_DIFFERENTIATORS reviewed: inactive integration does not justify a new customer-facing differentiation claim, so unchanged. Stop after Phase 2; no Warehouse/Planning phase started.
