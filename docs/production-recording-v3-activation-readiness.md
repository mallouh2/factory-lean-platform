# Production Recording V3 — Completed-work activation readiness

**27 October 2026 policy update:** ordinary reporting after execution completion is now locally verified independently of the disabled completed-shift gate, while the authoritative execution occurrence remains open. See [same-shift correction](production-recording-v3-same-shift.md). Dated gate-OFF completed-work results below describe the earlier policy; closed-shift recording remains disabled and no hosted activation is implied.

21 October 2026. **LOCAL READY. Disabled by default; no hosted acceptance or activation.**

## Scope and implementation

Continued development at bb0d20e5dd433b896dd319f56e75f0d9eb5d2862 after Phase4D. Existing dirty work was inventoried before edits. Phase0 contracts, M2 admission/recovery, Phase3D and Phase4B/4D remain authoritative. This is the missing capability-publication integration, not another recording system or permission policy.

The protected M1 reader always returned `late_recording_available=false`, and the API rejected TRUE. The existing Phase4B selector/Save already understood completed-work capability. Forward migration `20261021071031_production_recording_capability_v3.sql` replaces only `public.production_shift_work(uuid,jsonb,integer)` to read the existing private M2 factory gate: enabled TRUE, schema contract3, current verified occurrence and effective Orders edit. Missing/false/incompatible state fails closed. Orders view/factory scope remains mandatory. Rows reuse the existing shared execution/occurrence eligibility helper; only eligible completed rows receive actionable late capability. Active recording retains its existing eligibility when late mode is off.

The existing bounded cursor now binds actor, effective edit capability and published availability as well as occurrence/source/schedule revisions. A gate/authority change cannot silently combine pages. The reader remains STABLE, empty-search-path, UTC and read-only; existing EXECUTE grants survive CREATE OR REPLACE. No private table, posting helper, permission grant or activation control is exposed.

The API accepts only coherent boolean capability envelopes/rows. SQL remains authoritative even if a client fabricates capability. UI preserves the approved form, table/Details/search behavior and EN/AR styling. A vanished selected row has the existing work-changed warning. A stale enabled selection rejected by SQL now shows the existing translated completed-recording-disabled message, while retaining its UUID/draft/recovery semantics.

No writer, stock/source/WIP arithmetic, execution lifecycle, correction approval, Quality/Lean eligibility or saved snapshot changed. No supervisor approval was added. Ordinary late declarations still cannot consume existing WIP lots; genuine new WIP requires remaining work. Original line/occurrence attribution, completion status/timestamps and unidentified physical-stock state are preserved.

## Verification actually executed

- **81/81 focused Node tests**, four files: shift-work API/capability/query, existing guarded recording/error contract, exact intent/recovery/UI eligibility and History precision. Includes protected TRUE publication, unknown/inconsistent fail-closed contracts and translated stale-gate rejection. No full-platform suite.
- **36 distinct focused PostgreSQL assertions** on fresh disposable PostgreSQL17.11, loopback55479. OFF active posting; OFF completed rejection; incompatible schema; ON completed publication/posting; immutable replay/conflict/recovery; unchanged status/timestamps; Good/source/WIP/Scrap conservation; real bounded cursor invalidation on disable; view-only/no-view/cross-factory denial; private gate/reader grants; actual server deadline; recovery/replay after expiry; previous-shift exclusion during a new active occurrence; never-started scheduled work excluded during a verified active occurrence. Five boundary assertions were rerun after strengthening that last fixture;41 successful executions, not41 distinct tests.
- **99 required migrations** applied in existing order with Export Reader excluded. There are100 local files now. All99 pre-task migration bytes unchanged. Function/ACL comparison proves345 inherited functions unchanged and only the intended reader definition replaced; its ACL unchanged. The existing M2 quantity worker, live admission and lock-order functions are identical. Earlier Phase2/3D concurrency evidence remains applicable; the historical16-race campaign was not rerun. Actual stale-open-screen disable/new-write denial was exercised here.
- **TypeScript and isolated optimized Next16.3.5 webpack build PASS** on matching source; final build uses complete loopback-only configuration. No real `.env.local` copied, dependencies installed or hosted connections used.
- **One lightweight real-app Edge smoke, resumed after harness interruptions**, using normal synthetic technician sign-in and original SQL through the local Auth/Data adapter. OFF active preparation available; OFF completed Save disabled; ON eligible completed selection and Good1.5 Meter/Scrap.25 KG/new WIP1 save; lost response shown as unknown; normal reload recovery succeeds after disabling the gate; canonical same UUID replay HTTP200 and changed intent HTTP409; official History displays1.5/.25; stale enabled screen/new UUID receives HTTP503 with explicit disabled message; refreshed OFF Save disabled; EN/AR RTL390px warning/action pass. No repeated successful recording. Final resumed browser has zero page exceptions/external requests.

Actual browser entry `1298ed84-df43-47f7-b3c2-889bc92418b9`, immutable UUID `ad3f397f-22f5-4bf9-b4aa-11d02b67a373`. Seed Good25/Scrap.75/WIP2 becomes Good/finished stock/source credit26.5 Meter, Scrap1 KG, physical WIP3 Meter, exactly two entries. Completed status and both actual timestamps match frozen execution evidence. Retried/rejected submissions add nothing.

### Harness limits and diagnostics

Initial harness omitted server configuration names; login/snapshot failed before any recording. Corrected only isolated test configuration. Its synthetic technician also lacked Floor view; added only that fixture grant, keeping Orders edit/view and no approve. No retained or hosted permission change. Initial direct retry HTTP lacked Origin and was rejected before SQL. Its committed recording was recovered from immutable evidence and never resubmitted as new. A duplicate language-button locator interrupted only the remaining mobile check; it was scoped and resumed. A separately launched boundary check was cancelled by normal harness shutdown; rerun sequentially before browser, all five additional assertions pass. These diagnostics are not application defects or PASS evidence.

The browser adapter is not hosted GoTrue/PostgREST/schema-cache proof. This smoke does not repeat the complete browser campaign, cross-browser/physical-mobile or native Print tests. No claims of hosted activation readiness beyond the locally verified contracts.

## Retained preview and preservation

`http://127.0.0.1:4207/?view=lines` remains running on the existing full local app. Its actual connection was verified as loopback55476 / factory_lean_quality_local before applying the read-only forward function replacement and copying four source files. Per-table operational hashes for entries, stock, sources, WIP, recording gate and Maintenance gate match before/after. Recording gate remains FALSE/schema0, Maintenance unchanged. HTTP200 verified. This preview does not offer enabled completed-work recording.

Owned temporary4211/4293/55479 processes are stopped; test data/logs remain outside Git. Original4207/4291/55476 processes remain running. Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Activation-Ready-gOKKcn` (starting819-file hashes, function comparison, SQL counts, browser/resume results, RTL image, Node/TypeScript/build and preservation evidence). Test-only local credentials are outside the repository and are not in this report.

## Exact14-file manifest

Changed existing files:

1. src/utils/production-shift-work.mjs
2. src/utils/production-recording-v3.mjs
3. src/services/production-recording-client.ts
4. src/features/ProductionRecordingV3.tsx
5. tests/production-shift-work.test.mjs
6. tests/production-late-recording.test.mjs
7. tests/production-recording-ui.test.mjs
8. HANDOFF.md

New files:

9. supabase/migrations/20261021071031_production_recording_capability_v3.sql
10. tests/production-recording-activation/run-local.mjs
11. tests/production-recording-activation/capability.sql
12. tests/production-recording-activation/boundary.sql
13. tests/production-recording-activation/browser.mjs
14. docs/production-recording-v3-activation-readiness.md

Existing uncommitted work, branch/HEAD/main/index, historical migrations, Export Reader and untracked canonical Design System remain preserved. PRODUCT_DIFFERENTIATORS reviewed; integration of the approved inactive capability does not add a competitive claim, so no update. [Supabase function security guidance](https://supabase.com/docs/guides/database/functions) checked; existing protected helper/grant conventions retained. Changelog Markdown endpoint could not be fetched; no dependency/API upgrade undertaken.

## Hosted prerequisites / stop

Separate owner authorization is still required for current Local/TESTING/DEV migration-history verification, isolated release manifest/dry run, migration plus matching application delivery, compatible reporting/consumer checks and real hosted authentication/manual acceptance. Export Reader remains a separate release decision. Late activation is another explicit gate with a supported disable procedure and controlled fixture; never infer approval from this local result.

Persistent default remains OFF. No hosted database access/change, deployment, activation, Git staging/commit/push or new development phase. **STOP for owner review.**
