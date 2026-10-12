# Quality High-Scrap integration — 2026-10-11

## Authorized TESTING deployment and live visual verification — 2026-10-11

**PASS: deployed only `20261011114452_quality_high_scrap_reader.sql` to factory-lean-testing / silmfbpjyepalnggwulp.** Fresh preflight81 applied matched83 local versions/names; target absent. Supported installed CLI2.117.0 used an isolated workdir containing81 applied files plus only the approved reader. Explicit `--project-ref silmfbpjyepalnggwulp`, dry-run, `--skip-vault`, no seeds/custom roles; exactly one migration listed and applied. No authoritative blanket push, MCP-generated timestamp, raw untracked DDL or migration-history repair. The supported CLI initialized its temporary login role for the connection; it did not change application accounts or permissions. Post-deployment82 applied, exact version20261011114452/name quality_high_scrap_reader registered, all81 earlier entries preserved. Administrative Export Reader20261006072000 remains the sole pending repository migration. Local83 files unchanged.

Approved file SHA256 `9cc6480818ab8aac3c72d23fd495de86db95a5c53adf0e96d4cef775a1f629db`. Fresh isolated PostgreSQL testing used this exact unchanged file; dependency schema inspected remotely before application, all required fields/functions already applied, no Export Reader dependency. Existing permissions/non-board modes match the earlier deployed reader. Deployed body matches the approved SQL exactly; MD5 `3d53c240de9444bd0b68a8645d49971b`. Signature remains quality_read(uuid,jsonb), STABLE SECURITY DEFINER/empty search_path, authenticated execute allowed/anon denied. All public table ACL/RLS and policy digests unchanged. Production entries, permanent Quality rejections, finished balances and Lean-standard digests unchanged; recording/Lean assessment functions unchanged. No data backfill, standards rewrite or production accounting change.

### Actual hosted owner results

Existing normal owner session verified Ahmed Al Mansour / Factory owner in Nova, Full Access; board reloaded through normal navigation after deployment. Successful live rendering of the newly returned assessment confirms protected RPC/PostgREST availability through the application; direct browser navigation to API was previously blocked and was not bypassed or repeated as payload capture. No assertion of an independently captured HTTP status/body.

| Result | English | Arabic |
| --- | ---: | ---: |
| Matching production entries | 38 | 38 |
| Valid actual Scrap percentages | 38 | 38 |
| High Scrap | 19 | 19 |
| Within configured standard | 15 | 15 |
| Missing captured standard, actual percentage still visible | 4 | 4 |
| Calculation unavailable | 0 | 0 |

Filtered additional Quality Scrap remains7.10kg. Existing records match source-derived examples below: PO1584 original100m, gross60kg, Production Scrap0/Quality Scrap6.10kg =>10.17%, running2%, allowed1.20kg/excess4.90kg, warning; corrected rework Good7m/gross4.20kg/Scrap0.75kg =>17.86%, allowed0.084kg/excess0.666kg (display0.08/0.67), warning; PO1757 Good10m/gross6kg/Quality Scrap0.40kg =>6.67% and missing-standard label. Normal P06390m/gross85.5kg/Scrap0 =>0%, running2%, allowance1.71kg, no warning. All use stored historical weight/mass, not current Product weight or accepted Good. No remaining unavailable row/input gap exists in this population. Four QA entries remain genuinely unconfigured, with actual rates0%,100%,0%,6.67%; no standard fabricated. Unknown shift/date in historical rows remains explicit and is not a missing mass.

Desktop1280x720 verified: whole-row warning tint on all19 high rows, transparent cells retaining tint, warning icon/High Scrap and Arabic توالف مرتفعة, allowance/excess, ordinary neutral zebra rows, missing-standard EN/AR. Pointer hover on a read-only Scrap cell and keyboard focus within a warning row strengthen its warning tint and preserve High Scrap. Quality rows expose no selection control/aria-selected state, so hosted selected-row interaction is NOT APPLICABLE; existing shared selected-row CSS reviewed without injecting state. Arabic document/computed RTL and Latin IDs/percentage bdi direction verified, page width1265<=viewport1280. No styling changes. Missing-calculation display remains locally regression-tested; no incomplete live fixture was invented. Temporary filters/language restored to English/all rows at end. Owner visual approval remains separate.

### Startup and permissions limits

**NOT VERIFIED on hosted records:** zero startup events and zero startup-associated/positive-startup entries in Nova. Exact deployed reader retains captured event revisions and prior-declaration sharing across pages/shifts; all Scrap stays in actual rate, only remaining approved event allowance reduces abnormal evaluation, excess remains abnormal, textual cause alone creates no allowance. Local real-role rollback tests cover these rules; they do not manufacture hosted startup acceptance.

**PASS owner access / BLOCKED hosted Quality-only identity:** read-only direct/package union inspection of existing Nova memberships found no approved non-owner quality:view account. No user created, password reset or grant changed. Owner implicit authorization is not represented as Quality-only proof. Fresh local authenticated-role tests pass reader access without direct Orders/Lean reads; grants/RLS/policies and factory-scoped joins unchanged remotely. **BLOCKED hosted cross-factory scenario:** TESTING contains one factory, no second authorized fixture; local foreign-factory denial/filter tests pass. Elevated inspection is not ordinary-user authorization evidence.

### Validation, preservation and evidence

Fresh focused82/82; standalone PostgreSQL148 rollback assertions (reader34, boundary17, Quality45, release28, source24) plus8 concurrency/transaction scenarios passed. Used the existing approved portable runtime only; fresh loopback database stopped/data removed. TypeScript/build were already verified against unchanged application code in the diagnosis; not rerun or represented as fresh deployment tests. No full-suite rerun, source/config/dependency/migration edits or application deployment.

External evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-High-Scrap-Deployment-20261011` (isolated migration/hash manifest, migration histories/function/security/data comparisons, English/Arabic DOM/row counts and screenshots); SQL results `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-scrap-deploy-20261011\results`. Initial fresh isolated --linked dry-run could not resolve the legacy link marker; explicit supported --project-ref dry-run succeeded before any migration execution. One application, no retry/repair. English/Arabic screenshots `quality-high-english-final.png`, `quality-high-arabic.png`.

Preserved development/HEAD3e249c9 and mainafd2674, all earlier dirty work and83 local migrations. Documentation-only repository changes in this task: this report, Quality UI report and HANDOFF. No operational TESTING records changed; no Simulation/localhost3001, DEV, PROD, main, GitHub, commit/push/checkpoint operation. localhost3000 HTTP200. Stop after this one deployment; await owner visual approval before checkpoint.

## Owner browser follow-up — 2026-10-11

Owner-authorized normal login using the existing local TESTING credential record succeeded. The authenticated Menu identifies Ahmed Al Mansour / Factory owner, Full Access, in Nova Plastic Pipes Factory; Quality navigation and board access work. No password is recorded in this report or diagnostic evidence. Browser input initially timed out on Omar's Sign out; a fresh tab subsequently showed the normal signed-out login form, which was used without clearing sessions, impersonation or an authentication bypass.

The actual hosted board shows **38 rows and 38 Calculation unavailable cells**, with filtered additional Quality Scrap7.10kg. The three representative rows below are present: PO1584 original Good100/rejected23/accepted77; corrected rework recorded10/current7/rejected0/accepted7; PO1757 original Good10/rejected2.5/accepted7.5. This closes the owner-identity/access and live-render gap recorded in the earlier diagnosis below. It does not demonstrate the unapplied reader's output.

Direct authenticated navigation to the exact board GET endpoint `/api/quality?factory=bab9b5da-d78d-4be7-b6d4-bb6afc388c3a&mode=board&page=1` was blocked by the embedded browser with `net::ERR_BLOCKED_BY_CLIENT`. No alternative request, token extraction or browser-security workaround was attempted. Fresh direct payload capture is therefore **BLOCKED by browser access**, not an application defect or a passed HTTP response. The already inspected deployed function and API source establish the missing-field path; the live render agrees with it. No further code/test/migration correction was needed.

Saved external evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Scrap-Diagnosis-20261011\owner-quality-dom.txt` and `owner-quality-board.png`. This follow-up changed documentation only; no application/operational records, permissions, passwords or migrations were modified, and no deployment/commit/push occurred. Leave the owner Quality board available. Separate deployment approval remains required; administrative Export Reader remains excluded.

## Latest TESTING diagnosis and bounded local correction — 2026-10-11

**Confirmed deployment gap, not missing gross measurements in the current board.** Read-only project inspection verified `factory-lean-testing / silmfbpjyepalnggwulp`, ACTIVE_HEALTHY. Local83 versus TESTING81; all81 versions/names match in ascending order, no foreign versions. Pending: `20261006072000_factory_export_reader.sql` and `20261011114452_quality_high_scrap_reader.sql`. No migration applied, history repaired or hosted record/function changed.

Deployed `public.quality_read(uuid,jsonb)` is exactly the applied Quality migration definition: `prosrc` normalized-LF MD5 `6c033e133be18ce2e42ec68e12f8e808`; full function-definition MD5 `7b0488ed812d1adf65f18f53171835ae`. STABLE SECURITY DEFINER, empty search path, authenticated execute allowed/anon denied. Its board exposes recorded/current/rejected/accepted Good, Product names/code, current Product weight and Line/source/shift context, plus a whole-filter Quality Scrap aggregate. It has **no nested per-row `scrap`**, captured gross KG/weight, Production Scrap KG, per-entry permanent Quality Scrap, captured standard/revision or startup assessment. `/api/quality` returns the RPC data directly. Local Quality calls `qualityScrapState(row.scrap)`; absent input yields MISSING_DATA. Visible quantities and the reader's current Product weight cannot safely substitute for the missing historical measurements or allocate the aggregate Scrap to one entry.

### Source-to-reader diagnosis

All **38** current Nova board entries were inspected, not just the three examples. All have captured gross KG and historical KG/unit;34 have captured running standards,4 do not. No gross-mass/weight gaps in this current population. All are Meter entries. Historical timestamps can predate the Lean migration because this is synthetic fixture data; their stored snapshots were inspected directly. Three representative entries:

| Case | Entry / item / Product / Line | Stored production and losses | Supported result after reader deployment |
| --- | --- | --- | --- |
| A: sufficient measurements and standard | `bcf9f597-db25-4721-b858-5717d1e58f01`; item `c61042fb-8da2-4c93-a3c7-ce8afde4970c` / PO-0001584 (request PO-0001583); Product `8dcecb46-7a0b-449a-993f-8a833b1962a7` / P-050; Line `a0c244e3-9d87-52d9-8b12-1a278f6e86d6` / LINE1 | 2026-10-10T22:31:14.949291Z, shift1/date unknown; Good100m/new WIP0 × captured0.60=60kg; Production Scrap0; unreversed Quality Scrap6.10kg; startupKG0/no event; running2%,revision1 | Actual10.17%; allowance1.20kg; running excess4.90kg; HIGH. Unavailable now because the protected reader omits all calculation fields, not because source measurements are missing. |
| B: genuine missing standard | `e5247c6f-700c-4abb-99a0-418ced2d833a`; item `03ae132c-40ca-42e7-8146-c434828a9487` / PO-0001757 (request PO-0001756); Product `7c8d0101-3a20-40a9-91ec-b84a7a5f7dc1` / QA-QUALITY-E2E-TEST; Line `2b24e0b0-61de-4bc7-af91-877d82c4be6e` / QA Lean Line | 2026-10-11T06:13:38.144183Z, shift1/date2026-10-11; Good10m/new WIP0 × captured0.60=6kg; Production Scrap0; unreversed Quality Scrap0.40kg; startupKG0/no event; captured/current running/startup standards and revisions NULL | Actual6.67% with Standard not configured. Deployment supplies the rate but cannot create an approved standard; no default or standard configuration performed. |
| Additional real case: corrected rework | `588673a4-8366-4a77-becd-f3b2b83372a7`; same item/Product/Line as A | 2026-10-10T22:35:59.410080Z, shift1/date unknown; original Good10, corrected Good7m/new WIP0; captured0.60, corrected gross4.20kg; Production Scrap0.75kg; Quality Scrap0; startupKG0/no event; running2%,revision1 | Actual17.86%; allowance0.084kg; running excess0.666kg; HIGH. Rework snapshot Scrap is not added again. This is not a fabricated startup case. |

**Case C unavailable:** Nova has zero `lean_startups`, zero entries with a startup ID/positive startup KG, and zero Lean Scrap events whose preliminary/approved reason contains Startup. No remote fixture created. A third real non-startup row is documented above; hosted startup acceptance remains NOT TESTED. The current browser is Omar Khalil with no Quality navigation. Owner sign-in was requested; no logout, impersonation, permission change or authentication bypass performed. Therefore a fresh authenticated Quality API payload/render comparison is BLOCKED pending owner sign-in. Function definition and stored-source inspection confirm the reader gap; these are not represented as a successful hosted Quality request or rendered board.

### Actual percentage and local corrections

Actual percentage =100 × (effective Production Scrap KG + unreversed permanent Quality Scrap KG) / gross produced KG. Gross means current effective Good + newly recorded WIP before Quality acceptance deductions, consistent with Lean corrections; original production remains separately recorded. Standards/startup comparison are independent of the raw ratio. Before this correction the helper already retained rates without standards, but unnecessarily required Line/Product identity and a separate weight even when authoritative gross KG existed; startup-completeness failure could also hide the more specific missing-standard label.

Local helper now calculates raw percentage independently, rejects nonfinite ratios, and gates comparison separately. Missing standard shows its bilingual label while retaining a known rate, even if comparison context is incomplete. Incomplete Line/startup context with a known baseline shows Calculation unavailable alongside the actual rate. Missing production KG and losses remain unknown.

The confirmed-unapplied reader migration was amended **locally only**: prefer `production_entries.produced_weight_kg`; if NULL, derive gross mass only from that entry's captured positive `weight_kg_per_unit` and known nonnegative effective Good/new WIP. Unknown WIP is not zero; current Product weight is never used. Added `captured_produced_kg` and `mass_source` (CAPTURED/HISTORICAL_WEIGHT/UNAVAILABLE) for provenance. Exact running comparisons use the same chosen mass. No source snapshot/backfill, accounting, historical migration, standard or production workflow changed. This derivation is not needed for the current38 rows but covers supported historical gaps safely.

### Startup rule findings

The recording UI submits explicit `startup_id`, `startup_at` and `startup_kg`; protected recording verifies the factory/item/Line and event time, and snapshots startup `standard_kg`/revision. Positive startupKG without an event is rejected. Later corrections preserve the event and captured weight/standards. `lean_startups` has no reason column: reason classification is separate `lean_scrap_events` preliminary/approved cause linkage, not the allowance source. Selecting a reason named Startup alone grants no allowance and removes no actual Scrap.

All actual Scrap remains in the raw rate. Only `min(current startupKG,max(0,captured allowance−prior startupKG))` is excluded from abnormal running assessment. Prior declarations include all earlier shifts/pages for that exact factory/event. Cumulative startup above the captured standard remains independently abnormal and explicitly labelled as an event total. Zero events means zero allowance, not one allowance per shift. Missing event/standard context never invents allowance or healthy status. Existing remote recording/assessment function hashes stayed unchanged.

### Fresh validation and preservation

- Focused82/82, including independent actual-rate/missing-standard/context tests and a textual Startup reason without event; EN/AR/RTL component assertions passed.
- Standalone PostgreSQL148 rollback assertions across five suites (34 reader assertions),8 concurrency/transaction scenarios passed. New Meter/Piece historical derivation, unchanged result after current Product weight edits, unknown WIP/mass and exact comparison tested; existing Quality-only/direct-access/isolation/conservation/startup sharing and pagination assertions passed. Disposable loopback cluster stopped/data removed using existing approved runtime; no reinstall or remote writes. Local Auth/RLS shim is not hosted Supabase acceptance.
- TypeScript and production build passed; isolated `.next-check` build verified. An initial build used the default output directory before the command was corrected. localhost3000 still responds HTTP200, same server/session retained; generated config/type files restored exactly. Full Node763/763 remains the preceding implementation result and was not rerun for this bounded correction.
- Exact-diagnostic projection of all38 read-only inspected source rows through the local helper:19 HIGH,15 NORMAL,4 MISSING_STANDARD;38 calculable actual rates. This is local source projection, not a hosted new-reader test.
- Before/after TESTING digests of production entries, Quality rejections, finished balances and Lean standards match; reader/recording/assessment function hashes match. Branch development, HEAD3e249c9 and mainafd2674 preserved. Existing dirty work retained; no commit/push/checkpoint or Simulation/DEV/PROD operation.

Task files: `src/utils/quality-ui.mjs`, the unapplied reader migration, `tests/quality-high-scrap.test.mjs`, `tests/quality-ui.test.mjs`, `tests/quality/high-scrap.test.sql`, this report, `docs/quality-ui-refinements.md`, `HANDOFF.md`. Evidence outside Git: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Scrap-Diagnosis-20261011`; local SQL results in `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-scrap-diagnosis-20261011\results`.

### Proposed TESTING deployment, not executed

1. Obtain explicit approval for the amended `20261011114452_quality_high_scrap_reader.sql` only; administrative Export Reader remains excluded.
2. Reconfirm exact TESTING project and migration history; verify all83 local files and81 existing version/name matches, and preserve all applied bytes.
3. Use an isolated deployment workdir with the81 existing versions plus only the approved High-Scrap migration. Dry-run must list exactly that file; stop on any discrepancy. Keep operational writers idle during application.
4. Apply once only after approval; stop on failure without repair/reset/blind retry. Expected TESTING82 applied;83 repository files with Export Reader still pending.
5. Check definition, privileges and PostgREST schema, then use normal owner/Quality-only sessions for read-only board/API/render verification. Expected current source outcomes above retain4 missing-standard states, without changing standards. Startup hosted scenario requires separate controlled-fixture authorization because none exists.

The amended reader resolves missing fields for the inspected population; it does not supply absent standards, create startup evidence or complete blocked authenticated/hosted acceptance. STOP before deployment/checkpoint.

## Current result: implemented and verified locally; not deployed

Owner authorized one local forward-reader migration. Created `supabase/migrations/20261011114452_quality_high_scrap_reader.sql`. Preserved dirty `development`, HEAD `3e249c9d222a08ebe1e85c5fd401818821ed77d2`. All 82 earlier local migration files remain byte-identical, including the two applied Quality migrations. Local files now total 83. TESTING's saved 81 applied count is historical evidence, not freshly queried here; Export Reader and this new reader migration remain pending. No remote connection, data/schema change, commit or push occurred.

### Protected reader and calculations

`quality_read` adds a versioned nested `scrap` object only to returned board entries. Existing fields, modes, permission checks, filters and pagination remain compatible. It exposes captured Product/Line/unit, production mass and KG/unit, Production Scrap, unreversed permanent Quality Scrap, running standard/revision, actual startup event and captured startup standard/revision, prior/cumulative startup KG, allocated allowance and exact numeric running-boundary/excess results. Joins and aggregates require the requested factory and exact entry/event identities. The bounded returned page is supplemented in one statement snapshot; startup history includes earlier shifts and pages. `SECURITY DEFINER`, empty search path and authenticated-only execution remain protected. No table grants, extra Orders/Lean permission, write function, table or backfill added.

The entry grain and formulas documented below are implemented. Gross mass is captured Good plus newly recorded WIP times matching captured KG/unit, never accepted Good or Meter/Piece as a KG denominator. Permanent Quality SCRAP joins once, excludes reversals and REWORK, and does not re-add reprocessing snapshots. Running standards and startup allowances retain their captured revisions. Only a recorded startup grants allowance, consumed by prior declarations before this row. Running excess uses exact PostgreSQL numeric comparisons; the UI reuses `abnormalScrap` for startup-adjusted display. Cumulative startup excess is labelled separately as an event value; it is not a new debit or additive row loss.

### UI and incomplete data

Quality uses the protected inputs for NORMAL/HIGH/MISSING_STANDARD/MISSING_DATA. HIGH rows use the existing entire-row warning surface, icon and bilingual High Scrap label; actual/adjusted rates, normal running percentage, allowed KG and calculable excess are shown explicitly. Normal rows preserve zebra styling. Missing captured standards show Standard not configured; missing mass, weight, startup context or reader fields show Calculation unavailable. A known raw rate can still be shown when only its baseline is missing. Unknowns never become zero or healthy; current standards/weights never reconstruct missing historical snapshots. Without the unapplied reader migration, live old-contract rows honestly remain unavailable.

### Fresh verification

- Focused Node: **80/80**; full Node: **763/763**, zero failures/skips. Covers independent Line/Product standards, revision snapshots, below/equal/above/zero boundaries, Meter/Piece mass, startup sharing/excess, incomplete inputs, permanent losses and warning styling.
- Standalone PostgreSQL: **142 rollback assertions** across five suites, including **28 new reader assertions**; **8 concurrency/transaction scenarios** passed. All 83 migrations installed only in a disposable loopback cluster using the already approved portable runtime. Fresh cluster stopped and test data removed; scripts/results preserved. Quality-only authenticated-role reads succeed, direct Lean/Orders reads and Lean RPC remain denied, foreign-factory reads fail/return no foreign row, and before/after inventory/source/entry/rejection digests match. These are local Auth/RLS-shim tests, not hosted GoTrue/PostgREST integration.
- TypeScript and isolated production build passed. No dependency/configuration change retained.
- Browser: actual Quality component with two saved, rolled-back PostgreSQL outputs and explicitly labelled state variants, **no Supabase connection or writes**. English/Arabic and RTL labels/`bdi`, desktop1280 and narrow390 (page375 with scrollbar), two HIGH rows, normal/unknown non-warning rows, warning-over-zebra backgrounds, responsive cards without page overflow and dark row palette verified. No browser error/warning logs. Dark palette is row-level evidence, not certification of a complete application dark theme. Native screenshot API worked; full-page screenshot API was unavailable. Owner visual approval and hosted acceptance remain separate.

Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-High-Scrap-20261011`; database results: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-high-scrap-20261011-run2\results`. Temporary offline preview stopped and tab closed; original localhost3000 session/server preserved.

### Exact task files and next gate

Changed existing files: `src/features/Quality.tsx`, `src/utils/quality-ui.mjs`, `src/locales/en.json`, `src/locales/ar.json`, `tests/quality-ui.test.mjs`, `tests/quality-visual-states.test.mjs`, this report, `docs/quality-ui-refinements.md`, `HANDOFF.md`. Added: the single forward migration, `tests/quality-high-scrap.test.mjs`, `tests/quality/high-scrap.test.sql`. Shared CSS, API routes, business-write/accounting functions, standards, remote accounts and unrelated work are unchanged by this task. Product Differentiators reviewed; this completes the existing loss signal without a new competitive claim.

Locally ready for a separately authorized TESTING deployment. Reconfirm target/history and the exact approved migration set before any future deployment; do not deploy Export Reader incidentally. Hosted Quality-only PostgREST behavior and owner visual acceptance are still unverified for this new extension. No local implementation blocker remains. Stop; no checkpoint, commit, push or deployment authorized.

## Historical investigation before owner authorization

Status: BLOCKED before implementation by the prohibition on creating a new migration without owner approval. Existing stored data supports reuse; no new threshold system, inventory model or calibration engine is required. Verified local branch `development`, HEAD `3e249c9d222a08ebe1e85c5fd401818821ed77d2`; all existing dirty work preserved. No remote connection or database write occurred. This record supersedes the separate total-Scrap-threshold proposal in the earlier UI report.

## Verified implementation

| Concept | Actual source and behavior |
| --- | --- |
| Product + Line normal Scrap | `public.lean_standards`: `factory_id`, `line_id`, `product_id`, `running_percent`, `startup_kg`, `revision`, `created_by`, `created_at`, `approved_proposal_month`, `approved_observed_kg`. Unique `(factory_id,line_id,product_id)`. Defined in `20261005064954_lean_analysis_v1.sql:28`. Nullable standards stay unknown; zero is a valid explicit standard. |
| Historical declaration baseline | `public.production_entries`: `running_standard_percent`, `scrap_standard_revision`, `weight_kg_per_unit`, `produced_weight_kg`, `effective_scrap_kg`, `effective_startup_kg`, `lean_startup_id`. `private.record_lean_production` captures the actual item's Line/Product standard and matching unit weight (`20261005064954_lean_analysis_v1.sql:345`). `private.correct_lean_production` recomputes mass using captured weight while retaining captured standards (`:386`). |
| Actual startup | `public.lean_startups`: `factory_id`, `line_id`, `item_id`, `product_id`, `occurred_at`, `standard_kg`, `standard_revision`. Recording validates the event against the item/line/start time and snapshots its standard. One event can span declarations and shifts; shifts themselves do not create allowance. |
| Expected vs abnormal | `private.lean_scrap_assessment(factory,entry)` (`20261005064954_lean_analysis_v1.sql:423`), plus `producedWeight`, `scrapRate`, `startupPerformance`, `abnormalScrap` in `src/utils/lean-analysis.mjs:15`. `recordingScrapAttention` in `src/utils/lean-presentation.mjs:23` consumes earlier declarations before the displayed period. |
| Manual baseline / approval | `src/features/LeanLibraries.tsx:21`, `/api/lean`, `public.lean_command` → `private.lean_command`. Latest command definition is `20261005072541_lean_baseline_boundaries.sql:45`. Explicit `lean_standards:edit`, expected revision, factory lock, Audit and incremented revision; no automatic overwrite. |
| Lean startup observation / proposal | Latest `private.lean_read` in `20261005071129_lean_context_truth.sql:59` groups actual startup KG by Line/Product/factory-local month and averages totals per startup. UI copies an observed value into an editable approval draft; approved month/observed KG is stored by the command. This is implemented basic advisory/manual review, without a minimum reliable-sample gate or a general running-percentage calibration engine. |
| Separate Production Loss calibration | `production_loss_profiles` in `20260929213952_production_loss_impact_v1.sql:154` uses Work Center + Product shutdown/restart quantities. `suggestScrapCalibration` (`src/utils/production-loss-impact.mjs:332`) requires at least five matching READY observations, returns an advisory average with `requires_approval`. `LossImpactReview.tsx:267` invokes `configure_production_loss_profile`; RPC requires `centers:edit` and `downtime:edit`. These are stop-specific estimates, not the Line/Product running Scrap threshold. Existing immutable estimates retain historical context. |

Versioning means captured recording/event snapshots plus Audit, not an effective-dated standards-history table. Revised standards affect subsequent capture. Missing legacy snapshots cannot be reconstructed from today's standard or current Product weight. No backfill is proposed.

## Correct reusable calculation

The current Quality board is one **production entry with shift context**, not one aggregate per whole shift. Preserve that grain; do not apply one standard to a mixed Product/Line total.

For an entry, let `P` be captured `produced_weight_kg` (effective Good + newly recorded WIP × captured matching KG/unit). Quality rejection does not rewrite gross production; accepted Good is not a substitute denominator.

Let `S` be current Production `effective_scrap_kg` plus the sum of **unreversed SCRAP** Quality rejections' `actual_scrap_kg` for that exact factory/entry. Production and Quality store separate losses. REWORK rejection, recoverable/reserved WIP and discarded Meter/Piece quantities are not Scrap KG. Do not add `quality_rework_records.actual_scrap_kg` again: those snapshot the same reprocessing entry's Production Scrap. Read each rejection once before joining other records; no multiplying aggregates by source or movement joins.

For a recorded startup, legitimate allowance for this declaration is:

`A = min(entry effective_startup_kg, max(0, captured startup standard_kg − prior declarations' effective_startup_kg))`

Prior declarations use `(created_at,id)` order, same factory/startup, including records outside current page/filter/shift. Without an actual startup ID, `A = 0`. Missing startup standard/context remains unknown. Quality losses do not acquire an additional startup allowance.

Reuse the existing abnormal-Scrap rules: raw rate `100 × S / P`; startup-adjusted rate `100 × (S − A) / P`; normal running standard is captured `running_standard_percent`. Running excess is `max(0, S − A − P × standard / 100)`, with strictly greater-than boundary. Cumulative startup excess remains separately abnormal under Lean's existing rule. Show raw and adjusted values with explicit labels; a raw rate exceeding the running percentage alone must not trigger a warning when justified startup allowance explains it. Missing required mass/baseline must not be shown as healthy or given a fabricated warning/comparable percentage.

## Exact reader dependency and minimal approval scope

`src/app/api/quality/route.ts:4` calls `public.quality_read(factory,query)` with the authenticated client. Applied `20261010063309_quality_control_v1.sql:399` board returns Good/rejected/accepted/source/shift context and **current Product** weight, but omits historical produced mass, Production Scrap, recorded standard/revision, startup details and per-entry Quality Scrap. Its `quality_scrap_kg` is a filtered aggregate, not allocatable to each row.

An API-only supplement cannot support the existing Quality permission contract:

- `production_entries` direct SELECT RLS requires `orders:view` (`20260915122053_phase_one_completion.sql:55`).
- `lean_startups`/`lean_standards` SELECT requires `lean:view` (`20261005064954_lean_analysis_v1.sql:144`).
- `lean_read` entries requires `lean:view`; recording-context requires `orders:view` (`20261005071129_lean_context_truth.sql:36`). Private `lean_scrap_assessment` is not callable by authenticated clients.
- Quality tables have no authenticated direct SELECT; Quality history uses separately protected readers (`20261010063309_quality_control_v1.sql:420`). Requiring extra grants, privileged server reads or a history permission to view this board would change/bypass the existing permission contract.

**Smallest proposed change:** separately approve creation of ONE new forward migration extending only the existing protected `quality_read` board projection. Retain `quality:view` and factory checks, filters/pagination and existing fields. Add nested read-only assessment inputs/results for returned entry IDs: captured production KG/mass/weight/standard/revision, actual startup ID and frozen standard/revision, prior/cumulative startup KG and allocated allowance, per-entry unreversed permanent Quality Scrap KG, explicit comparability/gap state. Source every join/aggregate by factory and entry/startup identity; calculate within the reader's single database statement snapshot. No new tables, stored thresholds, write RPC, table grants, data backfill or accounting changes.

Then adapt the existing UI helper/indicator to `abnormalScrap` and wire the existing whole-row warning style, actual/normal/excess labels and EN/AR unknown states. Preserve independent startup warning semantics and no mixed-product comparison. Add the requested integration regressions, including Quality-only authorization, other-factory denial, historical snapshot reuse and shared startup allowance across pages.

Both Quality migrations are already applied and must remain byte-identical. A new migration is necessary to change the hosted function definition even though this extension is read-only. **No migration file was created.** Approval to prepare the local forward migration is separate from any later TESTING deployment; no deployment is requested or performed here.

## Current live feature and verification boundary

`src/features/Quality.tsx:34` still invokes `QualityScrapIndicator` without inputs. The current helper in `src/utils/quality-ui.mjs` is a visual raw-ratio placeholder and must not receive the running standard without startup adjustment. High-Scrap highlighting is **NOT integrated with actual data**. Live rows remain unavailable; distinct missing-standard/mass messages are still pending integration.

Fresh existing focused tests: **55/55 passed**, zero failed/skipped: Lean domain, Lean presentation/API, Quality API and Quality visual states. Covers existing mass/unit rules, unknowns, startup sharing/excess, frozen-standard behavior and protected reader errors; it does not establish the proposed integration, full requested new cases, hosted SQL or visual acceptance. No new tests were added. TypeScript/build/full suite were not rerun because no application implementation was changed. Prior UI 754/754 and build results remain historical evidence, not this task's results.

Task changes are documentation only: this report, correction of `docs/quality-ui-refinements.md` and the bounded latest `HANDOFF.md` entry. All 82 local migration hashes and all pre-existing non-documentation files match the task preservation baseline. Remote 81 TESTING history is carried from the saved integration report, not freshly queried. No TESTING data, Simulation, DEV, PROD, main, GitHub, commit or push operation. Stop for owner approval of the read-only forward-reader extension; checkpoint and visual approval remain separate.
