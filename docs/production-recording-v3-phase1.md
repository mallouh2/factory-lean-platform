# Production Recording V3 — Phase 1 local implementation

## Current verification — 19 October 2026

**LOCAL COMPLETE WITH HOSTED ACCEPTANCE PENDING.** This section supersedes the historical validation and deployment-next-step statements below. The owner postponed hosting; Vercel is not a prerequisite for local progress. No hosted service was contacted during this revalidation. Historical TESTING/DEV counts and Maintenance activation are not freshly verified here.

Starting checkout: development, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, 22 modified tracked / 80 untracked files, zero staged. All 678 tracked/untracked files were hashed before work. No Phase 1 application/helper/M1 SQL changes were needed; all migration bytes, unrelated work, Design System, environment/link configuration, index and branch refs remain preserved.

### Review findings and exact changes

No Phase 1 product defect was reproduced. Three validation gaps were corrected:

1. The former fresh harness included Export Reader and created a pre-M1 factory. Both current paths exclude Export Reader. Fresh applies the 90 required baseline versions plus M1 before creating fixtures; upgrade creates the pre-existing underway-shift fixture before M1. Fresh explicitly verifies post-install factory initialization, while upgrade verifies the prospective fence.
2. Existing route tests mocked authentication and RPC. The added local HTTP integration executes the actual GET route, actual authenticated-client/authorization logic, real SQL permission checks and the real protected reader. Only the session/SQL transport is replaced with a loopback fixture adapter. Every API RPC executes as authenticated in a READ ONLY transaction with fixture claims. This is not GoTrue, PostgREST, cookie/session renewal or the complete Next HTTP routing stack.
3. Added before/after snapshots of inherited function bodies/grants, relation ACL/RLS flags and policies; positive Scrap KG, recording retry and physical receipt retry conservation checks; and input hashes to reject test-source changes during a run.

Files changed in this revalidation only:

- `tests/production-shift-work/run-local.ps1`: separate fresh/upgrade ordering, exclude Export Reader, contract snapshots, actual HTTP integration, input hash guard.
- `tests/production-shift-work/after.sql`: mode-specific new-factory/fence assertions.
- `tests/production-shift-work/compatibility-before.sql` (new): capture inherited database contracts.
- `tests/production-shift-work/compatibility-after.sql` (new): compare contracts and prove Export Reader absent.
- `tests/production-shift-work/api-integration.mjs` (new): actual route/authorization/SQL integration, boundary and conservation fixtures.
- This report and the prepended current `HANDOFF.md` section: evidence, limits and Phase 2 plan.

### Freshly executed validation

Existing PostgreSQL 17.11 portable runtime reused; two owned disposable clusters bound to 127.0.0.1 only, ports 55462/55463. No installation, service, dependency, PATH or application environment changes. Both clusters stopped and their temporary data removed; scripts and results retained outside Git.

Commands from the repository:

```powershell
& tests/production-shift-work/run-local.ps1 -RuntimeDirectory 'C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018' -Port 55462 -Upgrade
& tests/production-shift-work/run-local.ps1 -RuntimeDirectory 'C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018' -Port 55463
node --test tests/production-shift-work.test.mjs tests/production-recording.test.mjs tests/production-flow.test.mjs tests/execution-queue.test.mjs tests/shift-time-windows.test.mjs tests/unfinished-production.test.mjs tests/maintenance-readiness.test.mjs
node node_modules/typescript/bin/tsc --noEmit --incremental false
node node_modules/next/dist/bin/next build --webpack
```

The last three commands ran in an isolated source copy using installed dependencies. Build configuration used dummy `.invalid` public Supabase values; no real environment file or hosted connection was used.

Results:

- **101/101 focused Node tests PASS**, zero failures/skips; TypeScript PASS; optimized production build PASS with dynamic shift-work API route.
- **Fresh and upgrade PASS**: 90 baseline versions + M1, Export Reader absent; all test input hashes stable.
- **360 counted SQL assertions per path**: 25 temporal, 283 reader, 5 WIP, 37 readiness, 10 transfers; additional legacy shift/protected execution suites, expected-error and migration/compatibility checks passed.
- **301 inherited function definitions/grants unchanged per path**; existing relation security/policies unchanged (the two intended shift/settings wrappers are excluded from function equality).
- **31 HTTP/SQL checks per path**, including 25 actual read-only SQL RPC calls and six-page traversal of 254 executions. Observed HTTP 401 unauthenticated/unconfirmed, 403 missing/revoked/cross-factory authority, 400 invalid page, 409 stale cursor, 200 valid/current and honest OCCURRENCE_NOT_READY. Private/no-store verified. Direct and package grants rechecked.
- **Three separate-connection races per path PASS**: read/Finish, configuration lock wait, duplicate materialization. Local Maintenance gate remained FALSE.
- Active Good=2 Meter / Scrap=0.25 KG recorded once under retry; one stock credit/source and one physical acknowledgment under receipt retry; stock stayed 2 Meter, with no invented physical identification. Completed ordinary writes still rejected. WIP, Start/Finish, Planning, Maintenance readiness/transfer regressions and operational before/after conservation passed. Downtime/Loss preservation is contract/digest evidence, not a rerun of their unrelated complete suites.

Final evidence:

- Upgrade: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-680b6dfce19c4256a6902104ff842368\results`
- Fresh: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-11437e8a43004582b2b4073dcf728c7d\results`
- Node/TypeScript/build: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Revalidation-703eedecd9ce4bb08e6648ff042395bb` (`node-tests.txt`, `typecheck.txt`, `build.txt`).

The API is inspectable through the local integration harness and its saved response evidence. No final picker/UI or hosted-connected browser preview was added. Full Supabase authentication/PostgREST and hosted acceptance remain pending; standalone fixture-session evidence must not be presented as that acceptance.

### Phase 2 plan only — separate authorization required

Implement inactive M2 using the approved Phase 0 contracts, without a second quantity worker:

1. Map current writer/correction/source callers and locks; add nullable origin/occurrence/request metadata before INSERT source capture, preserving legacy UNKNOWN attribution and existing active/WIP behavior.
2. Validate versioned context, current occurrence, completed-current-shift eligibility and accepted remaining quantities inside the existing protected writer. Preserve completed status, actual/planned times and machine/transfer/downtime state. Existing-lot WIP remains its own existing operation; Scrap remains KG.
3. Preserve factory → structure → request → gate/business-row lock order; reauthorize live membership/platform-scope after waits. Flush affected deferred validations, then perform final server admission-time check before returning success. This is not a literal WAL-commit deadline.
4. Bind client UUID to actor/factory/version and immutable normalized intent. Exact committed replay returns the original receipt even after expiry/disable; changed intent conflicts. Add same-actor authorized read-only COMMITTED/UNKNOWN reconciliation with separate current corrected values; uncertain transport outcomes never generate a new UUID automatically.
5. Add a disabled factory-local V3 gate; missing/FALSE or incomplete M3 rejects late writes. No activation. Preserve corrections, source allocation, stock/Sales/WIP conservation and audit originals.
6. Test fresh/upgrade, old clients, expiry after lock waits, Finish/configuration/revocation/gate/correction races, replay/rollback/UNKNOWN and all quantity/source conservation invariants locally.

Durable browser recovery and nonblocking duplicate warnings remain approved Phase 4 UI obligations, not new Phase 2 UI work: persist exact intent before send, isolate actor/factory, reconcile after interruption, retain unresolved attempts, and warn rather than infer a duplicate physical measurement. Phase 2 supplies their server contracts.

No new product-policy decision is required under the existing approved Phase 0 contracts. Changing the server admission semantics, current-shift-only rule, legacy/WIP boundary or phase split requires owner approval. M2 implementation itself requires separate authorization. M1 hosted deployment, Vercel delivery and hosted acceptance remain deferred; completed-job late recording remains disabled. Mandatory history/manifest/security checks remain required before any future database push. Stop here; no M2/M3/UI implementation, remote operation, commit or push.

## Historical implementation and evidence — 18 October 2026

18 October 2026. **LOCALLY COMPLETE; remote verification and deployment deferred.**

## Scope and preservation

Authoritative checkout: `C:\Users\Temp\Documents\GitHub\factory-lean-platform`, `development`, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`. Initial state: 91 migrations, 22 modified tracked files, 69 untracked files, nothing staged. The 667 existing tracked/untracked files were hashed before implementation. Existing Maintenance, F-021, Export Reader, Design System and other changes are preserved. No Git staging, commit, push, branch switch or remote project contact.

User authorization explicitly limits this task to local implementation and disposable local tests. The migration-history rule still applies before any database push. No Local/TESTING/DEV alignment or current remote state is claimed here. Review the approved external Phase 0 contracts at `C:\Users\Temp\Documents\FactoryLean-Production-Recording-V3-Phase0` before future phases.

## Exact Phase 1 file manifest

- `supabase/migrations/20261018073654_production_shift_work_v3_m1.sql`
- `src/utils/production-shift-work.mjs`
- `src/app/api/production-shift-work/route.ts`
- `tests/production-shift-work.test.mjs`
- `tests/production-shift-work/run-local.ps1`
- `tests/production-shift-work/before.sql`
- `tests/production-shift-work/after.sql`
- `tests/production-shift-work/temporal.test.sql`
- `tests/production-shift-work/reader.test.sql`
- `tests/production-shift-work/concurrency.mjs`
- This document.
- A new current-state section prepended to `HANDOFF.md`; prior content preserved.

`PRODUCT_DIFFERENTIATORS.md` was reviewed; no new competitive claim is warranted for a locally implemented foundation without hosted acceptance. Its pre-existing changes are preserved.

## M1 foundation and configuration contracts

New private tables: `production_shift_schedule_revisions` and `production_shift_occurrences`. Revisions store the complete observed definition set, timezone, server actor/time, prospective boundary, predecessor, ordinal and SHA-256 definition identity. Occurrences freeze labels, business date, revision, timezone and UTC half-open bounds. Composite tenant keys, immutable UPDATE/DELETE triggers, RLS and revoked ordinary access protect both. A UUID/range GiST exclusion prevents overlapping materialized occurrences; factory/revision and factory/start indexes support resolution and identity lookup.

The existing `configure_production_shift` signature and `private.update_settings` contract remain wrappers around the inherited validation, audit and Maintenance behavior. They acquire the existing factory structure lock, recheck authority, and append only a changed full snapshot. Server time is sampled after lock acquisition. Multiple pending snapshots share a safe future boundary; the latest ordinal wins. An underway canonical occurrence keeps its full original boundaries. New definitions whose nominal start predates their effective boundary are never clipped or backdated. Already materialized future evidence cannot be redefined by configuration.

Existing factories receive only a prospective capture. If a legacy shift is underway, its observed end becomes the initial fence; it is not certified as frozen historical evidence. New factories receive an observed baseline after existing initialization. Until a whole supported occurrence starts, reads honestly report `OCCURRENCE_NOT_READY`. Untimed/unconfigured shifts and genuine gaps have separate unavailable reasons. No scheduler or historical quantity inference exists.

`shift_boundary_utc` round-trips nearby distinct UTC offsets and rejects nonexistent or repeated local endpoints. Unambiguous overnight endpoints may span seven or nine elapsed hours across DST. The pure resolver derives descriptors without inserting occurrences and prioritizes already persisted immutable bounds. Descriptor resolution reuses persisted facts before consulting timezone rules; a future timezone-data update must never reinterpret those stored facts. Unmaterialized begun occurrences still require the approved release prerequisite before a timezone-data upgrade. The private materializer verifies and compares the entire descriptor, checks the governing revision and prospective boundary, serializes with configuration, and is idempotent. It is not exposed to authenticated clients.

Legacy shift configuration rows continue to express configured intent for old recording consumers. The existing legacy resolver, output workers, shift-at-entry attribution and saved Loss results are unchanged. Future M2 must deliberately integrate canonical occurrence attribution; M1 does not silently change that behavior.

## Execution and reader contracts

`private.production_recording_eligibility` shares pure modern-line evidence checks: factory/item/line/actual-start identity, protected Planning revision evidence, consistent lifecycle and actual execution overlap. Missing/future timestamps, zero-duration completed work, conflicting line history and unsupported legacy/independent history are excluded. Historical physical machine evidence is explicitly `UNKNOWN`; current machine placement is not invented as historical proof. Existing independent-machine and WIP recording paths remain intact.

`public.production_shift_work(factory uuid, cursor jsonb default null, page_size integer default 50)` is STABLE, SECURITY DEFINER, empty search path, UTC, authenticated only. It independently requires scoped Orders view permission. Orders edit and the existing `production_recording_units` contract determine active recording metadata; the existing writer remains final transaction authority. Completed work can be selectable for preview and policy-eligible, but `late_recording_available` is always FALSE and its blocked reason is `PHASE1_READ_ONLY`.

The version-3 envelope includes factory, server/evaluation time, occurrence, expiry, pending schedule context, dataset/schedule revisions, complete/next-cursor metadata and complete display context per work item. Product/order/item/line identities remain separate. Accepted/fulfillment Good and accepted remaining quantities come from existing authoritative columns.

Active executions precede completed executions, then actual start descending and item UUID. Default page size 50, maximum 100. Keyset cursors bind factory, occurrence, evaluation time, revisions, size, ordering and context hash. They are change indicators, not authorization tokens. Changed context returns SQLSTATE `40001` and API HTTP409/restart. Every page reauthorizes. Existing `lean_source_state` already observes execution/quantity/resources; the new migration adds only missing Product labels, request labels and private schedule-revision invalidation. No new event framework or quantity ledger.

`GET /api/production-shift-work?factory=<uuid>&page_size=50&cursor=<opaque>` uses existing confirmed-user authentication and factory authorization. It rejects unknown/duplicate parameters and malformed cursors, transports cursors as bounded base64url JSON, and returns private/no-store responses. No POST/UI integration, client clock override, private table exposure or production mutation path was added.

## Local verification

All database testing used PostgreSQL **17.11**, loopback-only disposable clusters with existing repository Auth/Storage shims. This tests actual migrations, PostgreSQL authorization/RLS and protected business functions; it does **not** test hosted GoTrue, PostgREST schema exposure/cache, Supabase session renewal or remote deployment.

- Upgrade: 90 baseline migrations excluding Export Reader, a baseline factory with an underway legacy shift, then M1. Operational digest unchanged; prospective fence verified.
- Fresh chain: all 91 existing migrations, including Export Reader locally, then M1. This is a standalone fresh-install test, not authorization to deploy Export Reader anywhere.
- Both final runs passed 25 explicit temporal assertions plus expected-error checks, and 283 reader assertions (including 253 per-row uniqueness checks), complete six-page traversal, direct/package/revoked permissions, cross-factory denial, private ACLs, active recording/idempotency, completed-write rejection and a genuine authenticated read-only transaction.
- Existing legacy shift SQL suite passed using only a local fixture-ID adapter; existing WIP recording 5, Maintenance readiness 37 and transfer 10 rollback assertions passed unchanged. The existing protected Production Execution SQL regression also passed unchanged using the established local demo-fixture prelude. Total explicitly counted SQL assertions per path: 360, plus legacy shift/execution and expected-error checks.
- Actual separate-connection read/finish, configuration-lock wait and duplicate-materialization races passed. Configuration timestamps were verified after waiting; one occurrence survived duplicate materialization; stale pages explicitly restarted. Maintenance activation remained FALSE in the disposable database.
- Focused Node: **91/91 passed**, zero failed/skipped, including 16 new parser/actual-route tests and relevant recording, execution, WIP, shift and Maintenance regressions.
- TypeScript: passed in an isolated copy with no incremental writes to this checkout.
- Optimized production build: passed using installed Next **16.3.5** with `--webpack`; the new GET route is dynamic. Dummy build-only Supabase public values were used; no real environment files were copied or changed. The installed Next route-handler guide was read before implementation.

Final full-run evidence (including persisted-boundary protection, execution regression and keyset plans):

- Upgrade: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-bbc92f18beb14eccb3302d8849916e67\results`
- Fresh: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-9a63d145e0f547d0b625f5181b381f9f\results`
- Isolated build: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Build-131e43ae6fe9418c81468e4c68f6741d\build.txt`
- Focused Node log: `node-tests.txt` in that build directory.

Existing portable binaries were reused in a dedicated temporary runtime copy. The earlier minimal runtime lacked New York/Honolulu timezone files; those existing distribution files were copied from its already extracted full timezone data into the dedicated copy. No download, installation, service, PATH or application dependency change. Every owned database process is stopped and disposable cluster data removed by the runner; test scripts/results remain. Failed setup attempts are retained as diagnostics and are not passing evidence.

Measured bounded workload: 253 actual protected Start/Finish executions, one Product across distinct orders and two lines, no quantity-entry prerequisite. Full reader first-page measurements in the final upgrade/fresh runs were 45.942/52.137 ms while sharing local resources. Factory-scoped candidate index scans used the existing `production_orders_factory_id_idx` and top-N sort, 0.331/0.357 ms. The actual eligibility/interval/keyset predicate plan, including first-page context construction, measured 61.032/69.244 ms; it explicitly filtered the previous 50 sort keys. No additional speculative production index was justified at this bounded workload. This is not a large-factory scale claim.

Reproduction: use `tests/production-shift-work/run-local.ps1` with an explicit approved `-RuntimeDirectory`, an unused loopback `-Port`, and `-Upgrade` for the 90-version upgrade path. Omit `-Upgrade` for the full 91-version fresh chain. Current complete runtime copy: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018`. No remote database arguments exist in this harness.

## Release and phase boundary

Local migration files now total **92**; all 91 historical migration byte hashes are preserved. Export Reader remains byte-identical; its current remote status is unverified. The untracked Design System and all existing unrelated work remain preserved. Branch, HEAD, main ref and staging index are unchanged.

No remote environment was accessed; no deployment, feature activation, Git commit or push occurred. M2 request receipts/writer/gate and M3 reporting/UI remain unimplemented. Completed ordinary late recording is still rejected by the unchanged protected worker.

Next gate requires separate authorization for **read-only Local/TESTING/DEV migration-history verification** under AGENTS.md, exact target/dependency/grant/PostgREST checks, and a proven isolated deployment manifest excluding unrelated pending work. No alignment/content-hash equality may be inferred from local filenames. A TESTING push remains deferred. Hosted reader acceptance must subsequently use a real authorized session and respect the prospective time fence; an unavailable initial shift is not a reason to backdate evidence or create operational fixtures without approval.
