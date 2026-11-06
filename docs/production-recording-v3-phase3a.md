# Production Recording V3 — Phase 3A

19 October 2026. **LOCAL COMPLETE — Phase 3A only.** Local protected database/read contracts; hosted acceptance and later consumers remain deferred. Late recording stays disabled by default.

## Authority, recovery and preservation

Authorized scope is Phase 3A. No Phase 3B API/history/export wiring, Phase 3C operational/Lean consumer integration or Phase 3D acceptance rollout. No recording UI or browser recovery work. No hosted access, deployment, activation or Git write.

Started on development / bb0d20e5dd433b896dd319f56e75f0d9eb5d2862, 24 modified tracked / 98 untracked / zero staged, 93 local migrations. Existing work is retained. The existing Phase 2 recovery directory and RESTORE instructions were checked, and recovery.zip still matches SHA256 F3D862EC88B4375E6AC9A1A23B7B5970DD829453E67713503AD3573A30EAA5C2. The backup was not changed or duplicated.

Approved scope references: external FactoryLean-Production-Recording-V3-Phase0 CONTRACTS sections 5, 6 and 10; DATA_MODEL sections 5–9; MIGRATION_DESIGN M3 matrix; TEST_MATRIX I/R groups; PHASE3-READINESS.md in the existing recovery directory. The current owner brief further limits this checkpoint to database and read contracts, preserving all existing business writers.

## 3A.1 — Contract and source map

- Production Request is production_requests; each independent item is production_orders. Actual execution is distinct from Planning. M1 supplies protected execution identity/current-shift work, including zero-entry work. No quantity row or planned schedule creates execution evidence.
- M1 immutable private production_shift_schedule_revisions/production_shift_occurrences supply dated identity, frozen EN/AR labels, timezone and UTC bounds.
- M2 production_entries owns recorded time, immutable original quantity/receipt/execution/occurrence and current audited effective attribution. production_entry_corrections owns actor/time/before/after deltas. Existing entry identity is the grouping unit, not each correction row.
- finished_goods_sources owns immutable source origin and physical identification; source movements/receipts, acknowledgment, WIP lots and Sales/Quality acceptance remain authoritative. No stock quantity is derived or posted by the reporting layer.
- lean_scrap_events owns observation/review identity; unreviewed observations are separate from reviewed Scrap. Existing lean_saved_comparisons/initiative evidence and Production Loss records remain immutable saved evidence.
- Existing per-person/package union and Orders reporting permission remain authoritative. There is no new reporting permission or grant. Lean view is additionally required for the versioned Lean relationship field. The existing Planning package genuinely includes Lean view; an Orders-only fixture must use appropriate direct grants rather than assume its package is restricted.

## 3A.2 — Minimum forward database changes

Migration: `supabase/migrations/20261019091907_production_reporting_v3_m3a.sql`, generated using the installed local Supabase CLI. No old migration is edited.

Every new object has a bounded reason:

1. Four additive lean_scrap_events columns (time_precision, occurrence_key, period_start/end), same-factory occurrence FK and shape constraint: existing occurred_at alone cannot express approved period-only facts. Old events default to asserted EXACT without changing their time, review or quantities. Exact observations still require occurred_at. SHIFT_PERIOD requires NULL exact time, complete bounds and no exact downtime link.
2. private.production_observation_period_guard: SQL CHECK cannot validate another table's entry/period/factory identity. This trigger validates a new period relationship against M2 effective facts and freezes identity/period across subsequent review updates. It never writes entries or quantities. Existing observation/review commands are unchanged and still create exact-time observations; period submission integration is explicitly deferred.
3. private.production_reporting_entries: nonmaterialized private view joining existing entry/item/request/Product/line, frozen occurrences, observation and existing Quality rejection/reversal facts. Shared by entries/summaries; it is not stored reporting state or an inventory model. Its accepted Good follows the existing entry-level Quality interpretation, while parent fulfillment/replacement counters are not summed as physical output.
4. private.production_reporting_history: one protected engine for versioned entries, summaries and separately paged corrections. Existing History lacks these occurrence/precision contracts; a shared function avoids separate aggregation/filter logic for each future consumer.
5. Existing production_history implementation moves unchanged to a revoked private delegate. The original public signature remains and delegates every non-versioned call to it. Only explicit reporting_version=3 uses the new contract. No new public endpoint or reporting service is introduced.

The public function is authenticated-only, SECURITY DEFINER with an empty search path and independent Orders view check; internal reader/view/delegate/trigger helper are revoked from PUBLIC/anon/authenticated. Existing table ACLs, RLS flags and policies stay unchanged. No new persistent table or materialized view, no broad user grants and no speculative index. Existing factory/created-at, occurrence and correction/source indexes are reused pending measured plans.

## History/read contract

Existing public.production_history(factory, filters, sort_key='date', sort_direction='desc', page=1).

Legacy filters/sorting/paging remain unchanged when reporting_version is absent. For the new opt-in contract, page stays 1 and the legacy sort arguments stay at their defaults; paging is by cursor instead.

New filters:

- reporting_version: 3.
- mode: entries (default), summary or corrections; corrections requires entry UUID.
- time_basis: recorded (default) or production.
- from/to: inclusive local date filters. For production they mean frozen occurrence business dates, preserving the entire overnight occurrence. Recorded dates use the factory timezone.
- Alternatively from_at/to_at: qualified exact UTC/offset instants, half-open. Do not mix dates and instants. Default is the last 30 days, frozen in the returned cursor. Maximum interval per request is 366 days; historical ranges remain accessible through adjacent requests, never silently capped.
- Optional product, line, entry UUID and occurrence key, page_size 1–100 (default 50), cursor.

Rows retain request/item/Product/line identities and EN/AR labels; actual recorded_at and actor; frozen original/effective occurrence/period; execution snapshot and evidence status; original/current Good, accepted Good, discarded production quantity, Scrap KG, WIP, source/input-lot IDs, observation/review status, and correction count. Corrections are a separate complete paginated mode rather than an unbounded nested history array.

New quantity/mass fields are exact decimal strings, preserving PostgreSQL numeric precision. No unlike units are combined. Scrap rates require a known positive denominator, known allocation and a supported snapshot basis. RECORDING_CONFIG is explicitly labelled and is not certified historical physical weight. Missing denominator/basis yields NULL, never an invented zero rate.

Entries are ordered deterministically by recorded timestamp/id; summaries by occurrence/Product/line/unit tuple; correction audits by timestamp/id. Cursors bind factory, normalized query/window, source revision and last key. Real source changes invalidate traversal with SQLSTATE 40001. Totals cover the full filtered set; only the bounded page is serialized. Query completeness is distinct from allocation/attribution completeness.

For production-instant windows, a fully contained period can be allocated. An intersected uncertain period is returned without proportional allocation: total Good/Scrap/rate remain unknown, while declared/unallocated quantities remain visible. Legacy/WIP rows without occurrence evidence use an explicit UNKNOWN bucket scoped to the recorded window. They are neither silently dropped nor assigned invented production dates. No historical machine placement is inferred from today's topology.

Zero-entry work remains the existing protected production_shift_work contract. Quantity history correctly has no invented row or output for it. The two readers preserve separate work and declaration semantics.

## Scrap, corrections and Lean evidence

Recorded Scrap KG and observation identity/precision/review status are exposed separately. Only reviewed observations supply reviewed_scrap_kg, and only callers with Lean view receive the Lean relationship object. This version-2 relationship describes provenance, basis and allocation; comparison_status is NOT_CALCULATED. It is not a new approved analysis or a replacement for saved version-1 comparisons.

Existing source origin/receipt remains original after correction; current effective totals use the entry once. Observation period is frozen as its evidence snapshot. Corrections remain their existing authorized, reasoned and audited workflow. Saved Lean/Loss evidence is not recalculated, migrated or overwritten.

Period-only storage can be exercised by trusted local fixtures to validate constraints. Ordinary period observation submission, existing lean_occurrences/Lean consumer NULL-time handling, comparison calculations and future evidence persistence remain Phase 3C work. Therefore V3 enabled/schema readiness remains FALSE/0; this checkpoint does not certify compatible consumers or enable late writes. Existing business writers and M1 capability flags remain unchanged.

## Local validation

Both final complete fresh/upgrade paths passed with identical final migration/test inputs. Earlier diagnostic runs found fixture assumptions, SQL fixture alias errors and PostgreSQL's JSON function argument limit after expanding row metadata; these were corrected before the final runs and are not passing evidence. The permission fixture checks the actual Planning package grants and separately verifies an Orders-only direct grant. Same-statement test reads use an explicit end instant after fixture writes; normal API reads occur in separate requests.

The runner uses the existing PostgreSQL 17.11 portable runtime, binds 127.0.0.1 only, asserts the disposable database name/host and excludes Export Reader. It never reads hosted environment credentials. Historical overnight fixtures are explicitly fictional frozen reader inputs with constraints/triggers enabled, not evidence of historical operational writer admission. Normal active/late/writer/replay/concurrency compatibility is exercised separately through unchanged protected functions.

Final commands:

~~~powershell
& tests/production-reporting/run-local.ps1 -RuntimeDirectory 'C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018' -Port 55466 -Upgrade
& tests/production-reporting/run-local.ps1 -RuntimeDirectory 'C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018' -Port 55467
node --test tests/production-late-recording.test.mjs tests/production-shift-work.test.mjs tests/production-recording.test.mjs tests/production-flow.test.mjs tests/execution-queue.test.mjs tests/shift-time-windows.test.mjs tests/unfinished-production.test.mjs tests/maintenance-readiness.test.mjs tests/lean-analysis.test.mjs tests/quality-api.test.mjs tests/quality-conservation.test.mjs
~~~

Final evidence:

- Upgrade: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Reporting-M3A-df86870113a94fe4bbb17c69029eda61\results`.
- Fresh: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Reporting-M3A-6cc91229fc934f9699d5bb0ad2fc8e50\results`.
- Node: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-M3A-Node-63c8a8ccde9d430980ead14a71cb6387.txt`.

Executed results:

| Scope | Result |
| --- | --- |
| Focused Node | 175 passed, zero failures/skips |
| New reporting SQL | 78 assertions per path, including complete pagination, precision, isolation, correction and saved-evidence checks |
| Permission subset | 14 checks per path: effective direct/package/revoked/cross-factory authority, Lean boundary, helper/view revocations and actual anon/authenticated role denial |
| Historical quantity correction subset | Two assertions per path: original/effective separation and preserved frozen observation period, using the existing source-selected correction command |
| M2 production compatibility | 66 assertions per path: writer 46, boundary 8, Maintenance 5, startup 7 |
| Inherited WIP/readiness/transfer/source/Quality SQL | 104 assertions per path: 5/37/10/24/28 |
| Total counted SQL | 248 per path (78 + 66 + 104); subsets above overlap and must not be summed again |
| Actual concurrency/deadline scenarios | 16 per path, separately counted; no concurrency skip in final runs |
| Migration paths | 92 pre-M3A required versions plus M3A = 93 per disposable chain; Export Reader absent |
| Prior-data/security comparison | 324 unrelated function definitions/grants and existing table ACL/RLS/policies preserved; upgrade additionally preserved seven entries, two observations and two populated saved evidence records |
| Read side effects | Full entry/order/stock/source/reservation/WIP/Quality/Maintenance/audit/occurrence/gate digests unchanged by reads; actual authenticated READ ONLY transaction passed |
| TypeScript/build | Not rerun: no application, API, TypeScript, Edge or dependency source changed. Phase 2's prior successful results remain historical, not fresh test claims |

The large case inserts 5,001 genuine Scrap-only legacy declarations plus a normal protected legacy Good declaration and normal V3 records, with all constraints/triggers enabled. It traverses more than 50 pages without missing/duplicate IDs. Separate protected Good/stock/WIP/Quality tests retain the conservation coverage. One earlier all-Good fixture setup was cancelled/rolled back because it spent unnecessary time generating stock movements; no security/constraint checks were disabled to accelerate the final fixture.

Measured query plans under shared local test load: existing `production_entries_factory_id_created_at_id_idx` supports the bounded candidate query (index-only backward scan plus incremental sort), 0.991 ms upgrade / 1.024 ms fresh. Protected first-page RPC with complete filtered totals measured 194.497 / 232.000 ms. Temp spill was visible (approximately 3 MB written per measured RPC); complete totals still scale with matching rows. This is a bounded local measurement, not a claim of constant-time full totals or large-factory hosted performance. No speculative index was justified. Narrower ranges remain available without silent truncation.

All 103 input hashes were stable during each run and matched current inputs before final formatting. Extra EOF blank lines in new test files were subsequently removed without changing any parsed statement; the upgrade results include eof-finalization.json with tested/final hashes and that check. The tested migration is unchanged. No suites were repeated for this whitespace-only finalization. Both owned servers stopped and their disposable data directories were removed; logs/scripts remain. Standalone PostgreSQL roles/Auth shims are not GoTrue, JWT/cookie renewal, PostgREST exposure/cache or real-browser acceptance. No new HTTP endpoint or transport-adapter acceptance is claimed for M3A.

## Changed files and deferred work

Exact 13-file change manifest:

- `supabase/migrations/20261019091907_production_reporting_v3_m3a.sql` (new).
- `tests/production-reporting/run-local.ps1` (new).
- `tests/production-reporting/before.sql` (new).
- `tests/production-reporting/after.sql` (new).
- `tests/production-reporting/seed.sql` (new).
- `tests/production-reporting/reporting.test.sql` (new).
- `tests/production-reporting/security.test.sql` (new).
- `tests/production-reporting/temporal.test.sql` (new).
- `tests/production-reporting/multiple.test.sql` (new).
- `tests/production-reporting/performance.test.sql` (new).
- `tests/production-reporting/final.sql` (new).
- This report (new).
- `HANDOFF.md` (current section prepended; prior content retained).

No application/API/UI/Edge source, historical migration, Design System, Export Reader or existing test file is edited. PRODUCT_DIFFERENTIATORS was reviewed; this inactive backend checkpoint does not justify a competitive claim or changing its pre-existing work.

Final preservation: 24 modified tracked / 110 untracked / zero staged; branch/HEAD/main/index unchanged. Of all 696 pre-existing project files only HANDOFF changed, and its complete prior bytes remain as the unchanged tail. All 93 prior migration hashes and ignored private environment/link configuration match the recovery manifest. The recovery archive hash still matches. Tracked diff and new-file whitespace checks passed; no owned PostgreSQL process/data remains.

Next smallest Phase 3B scope, after separate authorization: extend the existing History query parser/service/API to transport this reviewed opt-in contract and basis/cursor metadata, then add the minimum History display/export parity in bounded steps. Existing old-filter features must remain compatible; do not silently map unsupported filters. No Phase 3B work is started here. Operational/Lean consumers, full acceptance rollout, modal/durable browser retry and hosted deployment remain separately deferred.
