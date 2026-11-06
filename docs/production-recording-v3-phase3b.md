# Production Recording V3 — Phase 3B

19 October 2026. **LOCAL COMPLETE WITH PENDING ACCEPTANCE.** Parser/service/authenticated read integration only. Hosted GoTrue/PostgREST acceptance is deferred; late recording remains disabled by default. No existing interface changed.

## Authority and preservation

The current Phase 3B brief supersedes the broader export/UI suggestions in the earlier Phase 3 readiness plan. Approved Phase 0 contracts, Phase 1/2 reports and the Phase 3A SQL contract remain the basis. No material product decision or SQL contract amendment was required.

Started on development / bb0d20e5dd433b896dd319f56e75f0d9eb5d2862 with 24 modified tracked files, 110 untracked individual files, zero staged and 94 migrations. All 708 existing tracked/untracked project files were hashed before changes. No Git write, remote environment access, hosted credential renewal, deployment, activation or dependency installation was performed. No historical or new migration was edited or added.

Final preservation verification: 26 modified tracked / 117 untracked / zero staged. HEAD, branch, main and index hashes match the starting state. Only the four existing files in the change manifest differ; seven files were added and none deleted. The complete prior HANDOFF bytes remain as its unchanged tail. All 94 migration hashes, Design System, ignored environment and Supabase link configuration remain unchanged. All other existing project-file hashes match.

## Dependency map and implementation

| Boundary | Existing contract | Phase 3B action |
| --- | --- | --- |
| History screen | ProductionHistory.tsx → legacy query parser → /api/production-history → readProductionHistory | Untouched; existing filters, paging and numeric KG supplement retained |
| Departmental exports | table-export-operational.ts uses the same legacy History service | Untouched; no V3 export wiring |
| Protected reporting | Public production_history, explicit filters.reporting_version=3 → private M3A reader | Reused unchanged; no private helper exposed |
| New reporting query/payload | No application transport for M3A entries/summary/corrections | New production-reporting.mjs validates the query and response, preserving exact decimals, frozen attribution, unknowns and continuation |
| Reporting service | Existing authenticated Supabase server client | New readProductionReporting makes one bounded GET RPC, without legacy numeric supplements or TypeScript aggregation |
| Authentication | authenticatedClient → supabaseServer → confirmed getUser; authorize → can_access | Optional request-local fetch adapter passed through the existing helpers; authentication, cookies, keys and permission checks unchanged |
| Reporting API | Next route conventions and shared historyError | New GET-only /api/production-reporting; Orders view checked at API and independently by SQL |

Read the installed Next 16.3.5 route-handler guide before implementation. Supabase and PostgreSQL skills were applied to session authorization, protected schema boundaries and cursor pagination. Existing library source was inspected rather than assuming its transport behavior. No new UI/workflow was designed, so no competitor/UI redesign work was needed. PRODUCT_DIFFERENTIATORS was reviewed; this inactive transport addition does not justify changing its existing claims or pending work.

### Endpoint and filters

GET /api/production-reporting?factory=UUID&reporting_version=3

Modes: entries (default), summary, corrections. Corrections requires entry UUID. time_basis is recorded (default) or production. Product, line, entry and occurrence filters map directly to approved SQL. Inclusive local from/to dates or qualified half-open from_at/to_at instants are supported; the two forms cannot be mixed. SQL remains authoritative for timezone/window validation, a maximum 366-day resolved interval and frozen occurrence allocation. page_size is 1–100, default 50. No implicit full-history scan in TypeScript.

Order/request and item identities are returned on entry rows. Order/item filters are not supported by M3A and are explicitly rejected along with legacy-only numeric, technician, sort and page filters. They are not approximated through client filtering. Clients needing those legacy filters retain the existing endpoint.

All query keys must be known and unique. UUIDs, dates, qualified instants, enums and cursor shape/size are validated. The service serializes JSON filters explicitly for the installed client's GET RPC encoding. Stable ordering is owned by SQL, not sorted again in the service.

### Exact transport and response

M3A entry and summary quantities are already decimal strings. Its correction audit uses to_jsonb(c), so correction numerics and bigint revisions would lose precision through ordinary JavaScript JSON.parse. No database change was needed: a request-local fetch adapter preserves raw JSON numeric tokens as strings before postgrest-js parses the versioned production_history GET response. JSON strings/escapes are indivisible lexical tokens. It performs no rounding, quantity arithmetic or decimal-to-Number conversion. The installed Supabase client was tested with a 19-decimal quantity and a revision above JavaScript's safe integer limit.

The adapter leaves Auth, authorization, legacy RPCs and SQL error bodies unchanged. It uses the normal SSR client, session and publishable key; there is no service role, separate database connection or authorization bypass in application code. The protected payload has a 2 MiB transport safety ceiling, returning unavailable rather than partial success. Current 100-row measurements are far below it. GET read RPCs are supported by [PostgREST's documented read-only function interface](https://docs.postgrest.org/en/stable/references/api/functions.html#calling-with-get).

The response parser validates contract_version=3/evidence_contract_version=2, factory, requested mode/basis, required row fields, units, decimal strings/nulls, counts, periods and continuation/completeness. Small count/version fields are converted only after safe-integer validation; revisions stay exact strings. Unsafe counts fail explicitly instead of rounding. Unknowns remain NULL, never zero. Entries retain original/current/accepted quantities, recorded timestamps, frozen original/effective occurrences, periods, source/input-lot references and observation status. No source ID is interpreted as proof of physical Warehouse identification.

Occurrence materialization timestamps and unrecognized future audit fields are omitted through explicit response field selection. Frozen revision/shift/date/timezone/EN/AR identity remains. Correction rows retain their existing entry_id and audit actor/time/request and before/after attribution. Good/discarded/WIP correction quantities use the referenced entry's production unit; *_kg fields are KG. Audit rows do not invent a separate unit or duplicate the parent entry; callers obtain its unit/identity from the entries mode.

M3A remains authoritative for accepted output, Quality deductions, period allocation and summary groups. No unrelated unit totals, parent/replacement fulfillment calculation, inventory posting or Scrap review/approval was introduced. Lean provenance stays NULL for Orders-only users; reviewed provenance remains version 2 / NOT_CALCULATED and does not overwrite saved comparisons or Loss.

SQL cursors bind factory, query/window, source revision and last key. The API wraps them in bounded base64url transport, preserving exact revisions; SQL validates them again. Continuations are not authorization tokens. A changed source/query returns HTTP 409 reportingChanged/restart=true, rather than silently mixing pages. Page completion and attribution/allocation completeness remain separate.

### Errors and caching

Private, no-store on success and every handled error. Shared History conventions: 401 missing/unconfirmed session, 403 permission/factory denial, 400 malformed/unsupported query, 404 missing-resource SQL signal, 503 unavailable/incompatible backend. New stale-cursor mapping is 409 with an explicit restart instruction. SQL/internal details and credentials are not returned. Only GET is exported; Next's unsupported-method handling was confirmed by the installed route guide/build, with the fixture HTTP adapter additionally checking its 405 dispatch.

## Executed local validation

Runtime: existing portable PostgreSQL 17.11, bound only to 127.0.0.1:55468. The runner checks the disposable database name and address; it does not load .env.local. The fixture contains synthetic local users/configuration only. Initial fixture grants and test operations are not hosted account changes.

Final database evidence:

C:\Users\Temp\AppData\Local\Temp\FactoryLean-Reporting-M3A-735b900ee7734f678adac7bac92ff043\results

| Scope | Freshly executed result |
| --- | --- |
| Focused Node | 249/249, zero failures/skips: 67 new Phase 3B cases plus 182 relevant History/authentication/M1/M2/flow/WIP/readiness regressions |
| M3A SQL | 78 assertions, including 14 permission checks, historical corrections, decimal precision, unknowns, complete paging and saved evidence |
| Inherited writer/conservation SQL | 170 assertions: M2 66, WIP/readiness/transfers/source/Quality 104; total 248 with M3A |
| Concurrent transactions/deadlines | 16 actual separate-connection scenarios, including Finish/replay/expiry, authority, source/Quality/Sales conservation |
| HTTP → client → authorization → service/parser → SQL | 28 scenarios, 138 real RPC calls; actual Next handlers/authorization and installed Supabase client with fixture Auth/HTTP transport |
| Additional correction pagination | Four checks, two real authenticated READ ONLY SQL pages; unique audits, exact decimals, correct entry/factory and unchanged digest |
| TypeScript | Passed, including in the isolated source copy |
| Optimized production build | Passed in the isolated copy; new dynamic /api/production-reporting included |
| Whitespace and preservation | Checked separately at finalization; no migration changes or unrelated source edits |

The 28 HTTP scenarios verify no/unconfirmed authentication, missing permissions, an actual existing second-fixture factory, unsupported/invalid queries, Orders-only Lean masking, current active/late entries, historical overnight identity, submission date separation, precise historical correction, effective summaries, partial/unknown allocation, Product/line/entry/occurrence filters, distinct lines/items and Meter/Piece groups, empty results, legacy History response, stale/query-mismatched cursors, GET-only exports and all-state preservation.

HTTP traversal returned exactly 5,010 distinct entries on 51 pages without gaps/repeats. Every large page made exactly two RPCs: can_access and one protected reader. No N+1 supplements, unbounded application loading or in-memory pagination. Maximum response 211,568 bytes. Successful HTTP median 456 ms, p95 584 ms, maximum 671 ms, including separate psql process/connection and authorization overhead in this fixture adapter. Reader transport median 297 ms / p95 416 ms also includes process/connection overhead. The direct protected SQL first-page plan measured 120.218 ms; the previous Phase 3A 195–232 ms result is historical under different local load, not a hosted comparison or claimed speed improvement. Full filtered totals still scale with matching rows; no constant-time total claim.

Read-state digest before and after all HTTP requests: ccc4a5ed8f13051f39e8a8611f8d0b9e. Entries, corrections, orders, stock/source/reservations, Sales allocations, WIP, Quality, Scrap/Lean/Loss, downtime/transfers, Maintenance, audits and frozen shift/V3 activation state are included. Effective grant rows and the separate Maintenance activation row were also compared unchanged. All business RPC reads execute as authenticated in READ ONLY transactions. Both local servers from the diagnostic/final runs were stopped and disposable data removed; evidence/scripts remain.

The final run is a fresh local installation of the 93 required files, excluding Export Reader. No SQL changed in 3B, so the previously successful Phase 3A upgrade path was reused as historical evidence rather than rerun. Phase 1's complete SQL/hosted acceptance results were not reclassified as fresh; relevant current read behavior and Node regressions were executed. This is not a full-project Node run or a hosted performance/acceptance claim.

Commands:

~~~powershell
pwsh -NoProfile -File tests/production-reporting/run-local.ps1 -RuntimeDirectory 'C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018' -Port 55468 -ReportingApi
node --test tests/production-reporting-api.test.mjs tests/production-late-recording.test.mjs tests/production-shift-work.test.mjs tests/production-recording.test.mjs tests/production-flow.test.mjs tests/execution-queue.test.mjs tests/shift-time-windows.test.mjs tests/unfinished-production.test.mjs tests/maintenance-readiness.test.mjs tests/lazy-history.test.mjs tests/production-history.test.mjs tests/factory-navigation.test.mjs
~~~

The standalone corrections.mjs script was additionally run against this owned database while it was active, before subsequent concurrency fixtures. It takes the existing runtime bin directory, local port and evidence directory. It selects an existing entry with two corrections; it creates none. The main runner invokes the HTTP suite automatically with -ReportingApi; it does not invoke this supplemental script.

Node evidence: C:\Users\Temp\AppData\Local\Temp\FactoryLean-M3B-Node-regression-final.txt.

Build/typecheck evidence: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Reporting-M3B-Build-8ba38724393d4324b8e3386731ccfd23. No real environment file was copied; dummy .invalid Supabase values only. Application/helper sources match the final checkout. Later Node-only test additions do not change the built application.

Two diagnostic issues were corrected before the final results: GET JSON filters require explicit serialization in the installed client; the Maintenance activation snapshot must use its actual singleton schema, not a presumed factory_id. The first database run stopped at that fixture snapshot, cleaned itself and is not claimed as a passing integration run. Diagnostic evidence remains at FactoryLean-Reporting-M3A-33d8cefee7aa4052a42471f6529acae0/results. No database contract, permission safeguard or test constraint was weakened.

## Exact change manifest

New:

1. src/utils/production-reporting.mjs
2. src/services/production-reporting.ts
3. src/app/api/production-reporting/route.ts
4. tests/production-reporting-api.test.mjs
5. tests/production-reporting/http.mjs
6. tests/production-reporting/corrections.mjs
7. docs/production-recording-v3-phase3b.md

Existing files changed:

8. src/services/authorization.ts — optional server fetch adapter only.
9. src/services/supabase.ts — optional adapter passed into the existing SSR integration.
10. tests/production-reporting/run-local.ps1 — opt-in actual HTTP suite before cleanup.
11. HANDOFF.md — current section prepended; all previous content preserved.

## Limits and stop

Fixture-session testing is not hosted GoTrue, JWT/cookie renewal, PostgREST schema/media behavior, the full Next HTTP router or browser acceptance. Those remain explicitly pending; no hosted service was contacted. Decimal transport is verified through the actual installed client and local SQL adapter, not a hosted gateway. No UI/manual testing is claimed because no interface changed.

Phase 3C, Phase 3D, Phase 4 UI/durable recovery/similarity warnings, Excel/Print integration and hosted deployment remain deferred. No operational quantities, saved Loss, Maintenance behavior, permission model or gate defaults changed. Export Reader and Design System remain preserved. M1 still advertises late recording unavailable; V3 migrations still default FALSE/schema 0. No new activation surface exists.

Next smallest Phase 3C scope after separate authorization: map existing Scrap/Lean consumers that assume exact occurred_at, then add period-aware observation/review and unknown/contained-window handling through the existing protected contracts, preserving old evidence versions. Do not enable late recording or start the recording UI. Phase 3B stops here for owner review.
