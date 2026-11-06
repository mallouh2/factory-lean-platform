# Production Recording V3 — Phase 2 local implementation

19 October 2026. **LOCAL COMPLETE WITH HOSTED ACCEPTANCE PENDING. Late recording remains disabled by default.**

## Scope and preservation

Owner authorization is local implementation and disposable localhost validation only. Hosting/Gate C/deployment are postponed. No hosted environment, CLI credential renewal, deployment, Git staging/commit/push, or unrelated implementation is part of this milestone.

Started on development at bb0d20e5dd433b896dd319f56e75f0d9eb5d2862, with 22 modified tracked files, 83 untracked files and zero staged. All 681 tracked/untracked files were hashed before Phase 2. All 92 prior migration files, Export Reader, Phase 1, Design System and unrelated pending work remain preserved. One new forward M2 migration makes 93 local migration files; no current remote migration alignment is claimed.

Approved contracts: C:\Users\Temp\Documents\FactoryLean-Production-Recording-V3-Phase0 (CONTRACTS, DATA_MODEL, MIGRATION_DESIGN, TEST_MATRIX). Phase 1 remains locally complete. No M3, recording UI, browser draft storage or activation was implemented.

## Exact change manifest

- supabase/migrations/20261019063715_production_late_recording_v3_m2.sql — inactive gate, additive metadata, shared protected writer, immutable receipts, recovery reader, audited attribution and source capture.
- src/utils/production-recording-v3.mjs — strict context/status query validation and bounded error/outcome mapping.
- src/app/api/production-recording-status/route.ts — authenticated private/no-store recovery GET.
- src/utils/lean-contract.mjs — additive versioned recording context and explicit dated-correction proof.
- src/utils/quality-contract.mjs — the same dated-correction proof through the existing source-selected correction path.
- src/app/api/data/route.ts — V3-specific response/error semantics, preserving existing unrelated command handling.
- tests/production-late-recording.test.mjs — context/query/permission-error/uncertain-outcome contract tests.
- tests/production-late-recording/run-local.ps1 — owned loopback cluster, fresh/upgrade paths, source hashes, tests and safe cleanup.
- tests/production-late-recording/fixture.sql — local-only protected execution/shift fixtures and assertions.
- tests/production-late-recording/compatibility-before.sql
- tests/production-late-recording/compatibility-after.sql — inherited entry/function/grant/RLS/policy preservation.
- tests/production-late-recording/writer.test.sql — posting, gates, replay, permissions, corrections and conservation.
- tests/production-late-recording/boundary.test.sql — real successive occurrences, multi-shift declaration and dated correction.
- tests/production-late-recording/maintenance.test.sql — historical declaration versus current WIP under a live Maintenance hold.
- tests/production-late-recording/startup.test.sql — immutable startup/configuration replay and complete expiry rollback.
- tests/production-late-recording/concurrency.mjs — real separate connections, observed waits, in-flight status and final state assertions.
- tests/production-late-recording/http.mjs — actual Next handlers/authorization/SQL over loopback, including lost-response recovery.
- This report.
- HANDOFF.md — current Phase 2 section prepended; older content retained.

PRODUCT_DIFFERENTIATORS.md was reviewed. An inactive backend foundation does not justify a new competitive claim; its pre-existing contents remain unchanged.

## Writer and deadline

public.record_lean_production retains its signature and invoker boundary. The private Lean wrapper normalizes original intent, serializes factory → structure → request and checks a committed receipt before mutable startup/configuration/eligibility work. It delegates to one extended quantity worker body. The old private worker signature delegates to that body with NULL attribution and remains revoked from ordinary callers. The migration verifies the exact inherited worker body before replacing it; no historical migration or runtime text patch repairs old SQL.

V3 ordinary input adds exactly recording_context: version 3, execution_key, occurrence_key, context_hash and current_shift_quantity_confirmed. Client-supplied mode, actor, period/timestamps, resource proof and other unknown keys are rejected. The existing M1 resolver/eligibility helper is reused. Protected modern-line execution, current occurrence, correct line/unit, fresh per-item fingerprint, explicit spanning-shift declaration and approved technician remain mandatory.

For new late requests, the private per-factory gate must be enabled TRUE and schema_contract_version=3. Migration defaults and new-factory initialization are FALSE/0. Missing/disabled/incompatible state rejects in SQL independently of UI data. Tests simulate readiness only in their disposable fixtures; M3 is not implemented or certified. The M1 read API still advertises late recording unavailable. No user-facing activation switch exists.

A shared gate-row lock precedes the item lock, after existing factory/structure/request serialization. Administration is a short gate-row-only operation, with no reverse factory/structure acquisition. Reentrant inherited locks retain established ordering. Every new V3 write requires Read Committed and rechecks live authority after waits. Existing person/package grants remain the permission catalogue; temporary platform/support scope is additionally checked against clock_timestamp rather than stale transaction now(). An independently valid approved-member branch stays valid.

Original metadata is present before entry INSERT and source/stock triggers. Active production periods end at the exact saved server recording timestamp; late periods end at verified execution finish, bounded by their frozen occurrence. The final KG/physical/source constraints are explicitly flushed after all final values. Then acceptance time/receipt are persisted, deferred receipt finalization is flushed, and live permission/shift time is checked again after triggers. Expiry rolls back the entire command, including Good, source/Sales/WIP, startup and receipt. Named constraint modes are restored; checks are never disabled or bypassed.

This is a server admission deadline, not a promise that WAL commit or HTTP delivery occurs before shift end. No client-click grace period exists.

## Receipts, recovery and immutable evidence

The existing unique factory/request UUID remains the committed ledger; no pending-job/retry subsystem was added. Versioned canonical intent includes actor/factory/command, normalized UUIDs/numeric representations/defaults/qualified startup time, exact notes and existing semantic trims. Same UUID with changed intent/actor conflicts. Exact authorized replay returns the original immutable receipt even after expiry, disable or subsequent quantity/attribution correction, with no new startup/Good/source/lot work.

New calls, including legacy active and existing-lot WIP, receive request receipts. Pre-M2 legacy replays retain the inherited behavior and are not retroactively assigned request/occurrence evidence. Legacy/WIP timing stays UNKNOWN without ordinary V3 proof.

GET /api/production-recording-status?factory=<uuid>&request_id=<uuid> requires a confirmed authenticated user, Orders view/edit, live factory access and same actor. Its protected SQL reader performs no DML, advisory locking, scope renewal or pending-row insertion. It returns COMMITTED with immutable receipt and separately corrected current values, or UNKNOWN. UNKNOWN includes uncommitted/absent/rolled-back requests; it is not proof of failure. Other actors cannot discover an owner's receipt through this reader.

V3 HTTP responses are private/no-store: observed 401 authentication, 403 denial, 409 intent conflict, 422 validation, 200 UNKNOWN/COMMITTED. Known SQL rejection is distinguished from uncertain transport/server failure; uncertain failure remains UNKNOWN. A dropped response was recovered through status and same-UUID replay without duplicate credit.

New original entry/request/KG-at-initialization evidence and finalized receipts are protected against mutation/deletion. Effective attribution requires corresponding before/after correction evidence; correction attribution and source origins are immutable once populated.

## Source, corrections and operational compatibility

V3 source capture uses the original frozen occurrence/execution, labels, date and timezone during the existing INSERT posting. It does not call the mutable recurring-shift date resolver for V3. Quantity correction retains origin and uses only the existing movement delta. Physical identification stays zero until explicit Warehouse identification. Historical pooled stock and nullable legacy attribution are not backfilled.

The existing correction path additionally accepts corrected_occurrence_key for a V3 change_shift. It must identify an already frozen, same-factory occurrence matching the requested recurring shift and overlapping the original supported execution before recording time. Recurring shift ID alone cannot invent a date. Previous/corrected occurrence/period are appended to the existing correction ledger; original receipt/source remains unchanged. Quantity-only corrections retain attribution; existing source selection, reasons, KG and consumed-WIP checks remain authoritative.

The Maintenance INSERT guard exempts only independently revalidated late ordinary declaration with NULL input lot. It never exempts present WIP processing. Late output may create genuine new WIP under the existing remaining-work rules; it cannot consume an old lot through late context. Existing active/independent/WIP eligibility, OPEN transfers and current capacity checks remain.

No automatic Start/Finish, reopening, machine restart, transfer, downtime, scheduling or Loss operation was added. Existing Good/Scrap KG/WIP/accepted/Sales arithmetic is reused. Stock credit and physical acknowledgment remain distinct.

## Final local evidence

Both final full paths passed with identical final migration/test inputs:

- Upgrade: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Late-M2-a67a72e6f71240448a5ba9d29cce4d0b\results
- Fresh: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Late-M2-2bcc7260618e45c3a88148659dba58cc\results
- Node/TypeScript/build: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Late-M2-Build-e476c84f80a84c44be584ede263a7707

Per database path:

- 91 pre-M2 migration files plus M2; Export Reader excluded. Upgrade creates the active acceptance fixture before M2; fresh creates it after M2. Both include the bounded older pooled-stock fixture before the historical source migration, preserving its real legacy semantics.
- **66 M2 SQL assertions:** writer 46, boundary 8, Maintenance 5, startup 7. Maintenance/startup assertions run in separate rollback transactions, so displayed cumulative totals must not be summed as disjoint totals.
- **104 inherited SQL checks:** WIP recording 5, Maintenance readiness 37, transfers 10, source-stock 24, Quality release fixes 28.
- **16 separate-connection concurrency/deadline scenarios:** in-flight UNKNOWN plus exact replay serialization; final-posting and lock-wait expiry rollback; replay after actual expiry/disable; both gate orderings; grant revocation; temporary support/platform expiry; independent membership branch; both Finish orderings; competing output; unsupported old snapshots; source correction; Quality rejection; Sales reservation.
- **15 HTTP/SQL checks**, 29 real SQL RPC calls, including dropped-response recovery. Actual Next GET/POST handlers and authorization execute over loopback; only Auth session/SQL transport is adapted to fixture identities. Business RPCs run as authenticated with fixture claims; status/authorization RPCs run in READ ONLY transactions.
- One existing legacy entry, 302 unrelated function/grant contracts and existing relation ACL/RLS/policies preserved.
- Test input hashes stable throughout each final run; owned PostgreSQL stopped and disposable data removed. HTTP server/session adapters closed.

Fresh **175/175 focused Node tests**, zero failures/skips; TypeScript and isolated optimized production build passed. App source used in the build matches current application files. Dummy .invalid Supabase values only; no real environment file copied. Tests ran with existing portable PostgreSQL 17.11 bound to 127.0.0.1 on unused ports 55464/55465. No dependency download, Windows service or PATH changes.

Reproduction from the repository (existing approved runtime):

~~~powershell
& tests/production-late-recording/run-local.ps1 -RuntimeDirectory 'C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018' -Port 55464 -Upgrade
& tests/production-late-recording/run-local.ps1 -RuntimeDirectory 'C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018' -Port 55465
node --test tests/production-late-recording.test.mjs tests/production-shift-work.test.mjs tests/production-recording.test.mjs tests/production-flow.test.mjs tests/execution-queue.test.mjs tests/shift-time-windows.test.mjs tests/unfinished-production.test.mjs tests/maintenance-readiness.test.mjs tests/lean-analysis.test.mjs tests/quality-api.test.mjs tests/quality-conservation.test.mjs
node node_modules/typescript/bin/tsc --noEmit --incremental false
node node_modules/next/dist/bin/next build --webpack
~~~

The last two commands ran in the isolated build copy, not the authoritative checkout. -SkipConcurrency supports focused harness diagnosis only; final full evidence above used SkipConcurrency=False. Earlier exploratory fixture/harness failures are retained as diagnostics, not passing evidence. These included an incorrect fixture role/grant, missing test rejection mass, an ESM import extension and NextRequest loopback-origin normalization; application security checks were retained. Final active-period attribution was corrected to the saved recording instant and explicitly regression-tested.

## Remaining phase boundaries

No unresolved local Phase 2 safety/product-contract blocker remains under the approved contracts. Standalone PostgreSQL and a fixture session adapter do not certify GoTrue, cookies/session renewal, PostgREST exposure/cache, the full Next routing stack, real-browser recovery or hosted acceptance.

M3 precision-aware reporting/Scrap review and compatibility readiness remain unimplemented. Durable browser drafts/reconciliation UX and nonblocking similarity warnings remain Phase 4 work. Independent new UUIDs are not proof of distinct physical measurements. The unchanged legacy interface cannot silently date a V3 shift correction without the new explicit proof.

Keep gate FALSE/0. Do not enable late recording until matching later consumers/UI and separately authorized acceptance are complete. No hosted work, history verification, build/deployment, activation, Git write or next implementation phase is authorized by this report. Mandatory history verification before any future database push remains in force. Stop after local Phase 2.
