# Current TESTING integration notice — 2026-10-11

Pending Nasser POST checks now executed after server/browser recovery: actual rejection write returns400/permissionError (existing command endpoint convention); both Quality datasets' Excel/Print requests return403 and only permissionError JSON. All rejection/balance/movement/source digests unchanged. Cross-factory remains BLOCKED / NOT TESTED because only one TESTING factory exists. Full owner acceptance remains incomplete; see latest integration report.

Latest actual session: Nasser's Quality navigation is absent and protected board/history/reasons requests return403. Warehouse remains accessible under its existing view grant. These are real read denials; Quality write-command/cross-factory scenarios remain unexercised. Prior sign-in-pending notices below are superseded.

Latest continuation: user reports Print working after manual testing; native-modal control interruptions recovered after closure and are not a proven product defect. Actual denied-session checks await Nasser's sign-in after read-only grant/package/platform-scope verification. No further inventory transactions or successful Excel exports were repeated. Full hosted acceptance remains incomplete for the separately listed gaps.

The two Quality migrations below are **now applied to TESTING**, explicitly authorized in order, with79 →81 history; Export Reader remains pending among82 repository files. They are no longer editable drafts. Actual authenticated Scrap/reserved-rework/Warehouse/correction scenarios passed, including exact10/0/0 →7/3/0.75kg correction. Global stock/source conservation errors0. Five EN/AR departmental XLSX downloads passed. **Full hosted acceptance remains INCOMPLETE**: native print/restricted-account/completed-item and other explicitly listed checks remain blocked/unexecuted. See [the current integration report](quality-export-testing-integration.md) for exact PASS scope, synthetic audit references, narrow fixes and fresh60/60 tests. Earlier local/standalone results below are historical evidence, not full hosted acceptance.

# Quality V1 — targeted release fixes, 2026-10-10 (historical local milestone)

This record supersedes the earlier implementation-only results below for QV-01/QV-02/QV-03. Continued the preserved dirty Quality work on `development`, HEAD `3e249c9d222a08ebe1e85c5fd401818821ed77d2`. No commit, push, remote database operation, Simulation/3001 operation or hosted QA data change.

## Findings and corrections

- **QV-01:** the immediate entry trigger compared corrected discarded units with the previous KG before `correct_lean_production` wrote the new KG. A private, initially deferred constraint trigger now re-reads the final entry and validates positive finite KG for discarded Quality-origin rework at transaction completion. Piece and already-rejected Good guards remain immediate. Existing correction workers, immutable originals, correction audit, source allocations and Good/WIP movement logic remain intact. Exact 10/0/0 → 7/3/0.75, failed-mass rollback and actor-bound retries pass, including a real authenticated-role COMMIT failure followed by successful correction/replay.
- **QV-02:** `finished_inventory_projection` was omitted from the acceptance rewrite, while Warehouse subtracted accepted active quantities from gross total future quantities. The shared projection and its callers now use one private calculation of exclusive accepted future output: linked corrective subtree work covers its parent's gap and contributes once, including nested work under completed ancestors. Warehouse's Incoming/active split uses the same calculation; there is no cosmetic zero clamp on Incoming. Under the existing factory transaction locks, outstanding Sales promises covered by newly linked replacement work move to that item without changing Sales totals, stock reservations, received history or released history. Root recovery limits also prevent a separate branch from promising the same shortfall twice. Gross production, original lifecycle and schedules remain separate and unchanged.
- **QV-03:** the drawer's unpaged reason read returned only the first 100 records, with archived records consuming places and Other sorted last. The drawer now requests active-only, bilingual literal search and 100 ordinary reasons per page. Other and a previously selected active reason are returned outside that page/search limit. Other cannot be archived at the database boundary or in its editor; historical snapshots remain immutable. The API validates the retained-selection UUID, and loading/error states block submission. EN/AR search wording, native controls and RTL are preserved.

## Current final verification

| Check | Result | Evidence scope |
| --- | --- | --- |
| Focused Quality Node | **23/23 passed** | Includes four new reader/UI boundary tests: active paging beyond 100 in EN/AR, exact 100 boundary/loading, active/search/page/selection API contract. |
| Full Node | **713/713 passed**, zero skipped | Rerun after final UI wording; no product test failures. |
| TypeScript / production build | **Passed / passed** | Final `tsc --noEmit` after restoring generated config; isolated Next production build includes `/api/quality`. |
| Standalone PostgreSQL SQL | **114 assertions passed** | Source24, Quality45, boundary17, new release28; all 82 migrations applied to a fresh disposable cluster. |
| PostgreSQL transaction/concurrency checks | **8 scenarios passed** | Existing five, competing Sales source reservations, reservation retry/Quality free-stock boundary, deferred KG validation at real COMMIT with rollback and replay. |
| Offline browser | **Checked** | Actual drawer: English 1440×900 and Arabic 390×844, paging, Other, retained selection, search beyond100, RTL and no horizontal overflow; no captured warning/error logs. Synthetic data, no Supabase connection. |
| Preservation | **Passed** | Original80 migration hashes unchanged, source migration unchanged since this task began, canonical Design System unchanged; pre-existing Quality changes preserved. |

The new SQL cases cover active rejection, accepted Warehouse/shared projections, replacement/nested replacement without duplicate future output, Sales promises and corrective receipts, cross-branch recovery limits, archived reasons, EN/AR search and permanent Other. The existing suites retain legacy UNATTRIBUTED stock, partial-order/multi-source dispatch, reservations, issues, shipped-stock denial, source conservation, Scrap KG and reserved WIP/rework coverage. These are local code/database tests, not real Supabase service integration.

Reused the approved portable PostgreSQL17.11 runtime; no reinstall, service, PATH or dependency changes. Final cluster: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-20261010-release7`, loopback-only `127.0.0.1:55439`. SQL/concurrency logs are in its `results` directory. Node/build/TypeScript logs, pre-task file backups, preserved build output and English/Arabic screenshots are outside Git at `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Release-Fixes-20261010`. Early failed runs remain evidence of corrected test setup/recovery-limit issues, not passing results. Owned PostgreSQL processes and data were removed after each run; offline preview4202 and its tab were closed, viewport restored. Application3000 was left running.

**Migration state:** 82 local files; original80 hashes unchanged. Only the unapplied `20261010063309_quality_control_v1.sql` draft was amended; `20261010061827_quality_source_stock_v1.sql` was preserved. The preceding review reported a read-only TESTING history of79; it was not queried again in this corrective task and does not establish current alignment. Export-reader80 and Quality81/82 require fresh history verification and separate deployment authorization. No applied migration was edited.

**Task file delta:** `src/features/Quality.tsx`, `src/app/api/quality/route.ts`, EN/AR locales, the Quality-control draft migration; `tests/quality-ui.test.mjs`, `quality-api.test.mjs`, `tests/quality/{quality-control.test.sql,pre-source-fixture.sql,release-fixes.test.sql,concurrency.mjs,browser-fixture.tsx}`; this record, implementation record and HANDOFF. No new product capability warrants changing the existing differentiator classification. Applied bounded UI/UX/frontend and Supabase/PostgreSQL guidance; no new full audit or opt-in Ponytail review was run.

**Readiness:** the three reported blockers are resolved locally. Ready for a **separately authorized TESTING deployment and Supabase integration validation**, subject to first verifying the intended project's actual migration history and reviewing all pending migrations. GoTrue/session claims, PostgREST schema/error behavior, hosted permission/navigation/export/rework flows, real warehouse labeling, touch-device behavior and user acceptance remain open. No production readiness or user approval is claimed. Stop here; deployment, commit and push remain unauthorized.

---

# Earlier Quality Control V1 implementation verification, 2026-10-10

## Authority and result

IMPLEMENTED / LOCALLY VERIFIED, uncommitted on `development`, unchanged HEAD `3e249c9d222a08ebe1e85c5fd401818821ed77d2`. No remote deployment, hosted QA account, commit, push, branch switch or Simulation/security-workspace operation. User explicitly approved the minimal source extension and portable PostgreSQL testing.

The original 80 migration SHA-256 hashes match the pre-work manifest. There are now **82 local files**, including two new, remotely unapplied drafts:

- `20261010061827_quality_source_stock_v1.sql`: receipt provenance, physical identification, UNATTRIBUTED conservation, source reservations/allocations and universal finished-stock movement protection.
- `20261010063309_quality_control_v1.sql`: reasons, immutable rejection/reversal history, kg Scrap, reserved WIP, accepted-production counters, corrective tasks, notifications and protected readers/commands.

This is not Local/TESTING alignment. TESTING's last documented 79 is historical; the existing export-reader migration and these two drafts remain subject to separate TESTING authorization. No remote histories were queried. `main` remains `afd2674993df4d9bedda5cf35dc5b75de3cba4b0` and was not modified.

The pre-existing untracked `docs/design/FACTORY_LEAN_DESIGN_SYSTEM.md` is byte-identical: SHA-256 `B69AFBC54CFBB2383A79503C8DD0A7BF7A2B1FBDBE2749155F3FD1D2A983C27B`. Dependencies, environment files and the original migration bytes are unchanged. Build-generated edits to `next-env.d.ts` and `tsconfig.json` were restored byte for byte.

## Transactions and product behavior

- Existing `finished_goods_balances` remain stock truth. Historical pooled stock starts UNATTRIBUTED; historical receipts receive no guessed batch. New manufactured credits retain exact Production entry/item/Product/unit/actual shift context. External/opening stock remains UNATTRIBUTED. Receipt provenance alone grants no physically identifiable quantity.
- Warehouse confirms the actual label and counted quantity, identifying existing credit without crediting it again. A label must correspond to stock identifiable in the warehouse. When identification is lost through mixing, an explicit audited action returns free identified quantity to UNATTRIBUTED without changing stock; it cannot silently restore lost provenance.
- Full-order and ready-line dispatch, manufactured Product material issue, negative adjustment and Good correction preserve explicit source allocations. Legacy unknown-stock callers remain valid; they cannot silently debit an identified batch. Source reservations coexist with existing pooled Sales commitments. No separate finished-goods location-transfer subsystem exists in the baseline; the universal movement trigger protects every actual finished-stock outflow path.
- Quality rejects only physically identified, currently free source quantities. Shipped/consumed stock and Sales commitments cannot be replaced with unrelated stock. All event, acceptance, inventory, WIP and notification effects share one transaction and actor-bound retry ID. Factory locks serialize competing stock commands; permissions are checked after waiting for those locks.
- Default Scrap kg uses the existing Product `unit_weight_kg` only when `stock_unit` matches the recorded production unit. Decimal strings/BigInt previews and PostgreSQL `numeric` preserve exact quantities. Actual positive kg is editable; default, actual, unit-weight snapshot, override flag, actor, server time and note remain linked. Missing configured weight requires manual kg. Piece rejection and Quality-origin rework quantities are integers.
- Quality Scrap is an additional immutable kg ledger, shown separately on the Quality board after reversals. It does not overwrite original Production Scrap or enter Production Loss estimation. Existing Lean/Reports queries were not extended to add this new ledger to their aggregates; no claim that those aggregates include Quality Scrap is made.
- REWORK creates reserved stored WIP for the original Product Item, not Scrap. The existing Material Request → Warehouse issue → Production Recording workflow consumes it. Child WIP inherits the reservation; unrelated items cannot use it. Rework Good credits once; failed production-unit quantity is separate from actual Scrap kg. Quality follow-up displays warehouse/floor quantities and current rework recording results.
- Gross recording and completed/planned timestamps remain unchanged. Net accepted Good and replacement fulfillment are separate derived quantities. An explicit authorized corrective item is linked to the original rejection, initially unplanned; it does not reopen or reschedule the original. Outstanding recovery controls resolution, while acknowledgments and immutable reversal records remain auditable.
- Reasons support factory-specific bilingual naming, duplicate checks, archive/reactivate and immutable reason snapshots. Other requires a description; approved-reason creation requires its own grant. Per-person Quality/History/Reasons grants use the existing permission registry and package union.

## Final checks

| Check | Final result | Scope |
| --- | --- | --- |
| Focused Quality Node | **19/19 passed** | Decimal/contract 6, UI 8, authenticated reader/API boundary 5 |
| Full Node | **709/709 passed**, zero skipped | All `tests/*.test.mjs`; includes affected Production, Warehouse, Supply, Sales, permissions, Planning and Lean checks |
| TypeScript | **Passed** | `tsc --noEmit`; repeated after restoring build-generated config |
| Production build | **Passed** | Isolated `.next-quality-check` output; `/api/quality` compiled |
| Source SQL | **24 assertions passed** | Legacy pooled stock, no invented sources/double credit, allocation/reservation, multi-source and partial-order dispatch, issue, mixing and atomic failure |
| Quality SQL | **45 assertions passed** | Scrap default/override/missing weight, Piece/decimal validation, reversal, reason history, rework, completed item, explicit replacement, notifications, shifts and tenant boundaries |
| Boundary SQL | **17 assertions passed** | Unknown/shipped stock, reserved quantities, correction source, authenticated permissions, create-only Other, protected tables/context and deferred conservation |
| Real concurrent PostgreSQL sessions | **5 scenarios passed** | Identical retry, competing rejections, rejection versus stock-out, rejection grant revoked while waiting, adjustment grant revoked while waiting |
| Browser components | **Checked offline** | English desktop 1440×900; Arabic mobile 390×844; labeled rows, source picks, Other, Scrap/default override, Rework, view-only actions, native Escape, disabled busy actions, retained failure draft/refresh/retry; no captured console errors |
| Scoped Ponytail Review | **Lean already. Ship.** | Read-only final Quality/source/integration diff; no safe complexity reductions. This phrase is the skill result, not deployment or user acceptance. |

The first full Node run exposed seventeen Planning fixture failures caused by fixed October 8 dates becoming past dates and one obsolete dispatch assertion. Only the Planning test process clock was frozen at October 7; Planning product behavior is unchanged. The Sales test now verifies that dispatch requires source picks. Final counts above were rerun after those fixes and final UI edits. Earlier implementation/test-harness failures are retained in temporary logs and are not reported as passing evidence.

The user-required 23 Quality cases are covered across the focused decimal/UI/API tests and the three SQL suites: meter/piece default and override mass; decimals and fractional Piece denial; missing mass; source availability; one debit and kg record; reserved Rework; 10 → 7 Good + 3 discarded/0.75 kg; retries/races; shipped stock; Sales conservation; completed history; exact notifications; tenant/person grants; Other; archived reason snapshots; overnight shifts; atomic rollback; and existing recording/correction behavior. The full Node regressions additionally exercise existing Good/Scrap/WIP UI logic. This coverage does not substitute for remote Supabase integration.

## Portable PostgreSQL and cleanup

Docker's Linux engine was unavailable (`hasNoVirtualization: true`). User-approved portable PostgreSQL **17.11** came from [EDB's binaries page](https://www.enterprisedb.com/download-postgresql-binaries), linked by [postgresql.org Windows downloads](https://www.postgresql.org/download/windows/), via official HTTPS `get.enterprisedb.com/postgresql/postgresql-17.11-5-windows-x64-binaries.zip`. Download SHA-256: `80379B2C04D51C30225532E0AE04509899141E9957ED096FE749D7FD9DF8F82F`. This records downloaded-byte identity and official linked provenance; it is not a publisher signature/checksum verification claim.

The dedicated temporary roots are outside all Factory Lean repositories. A fresh cluster listened only on **127.0.0.1:55439**; no service, PATH or application dependency change. All 82 migrations installed unchanged. A test-only bootstrap supplies minimal Auth/Storage DDL and `auth.uid()`/`auth.role()` claim functions, then exercises the actual application authorization, RLS, triggers and transactions. It does not run Supabase GoTrue, PostgREST or Storage services and does not bypass application permissions.

Final SQL transcripts: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-20261010-run17\results`. Final Node/TypeScript/build logs and baseline hashes: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-20261010\results`. Reproducible test scripts remain under `tests/quality/`.

All owned PostgreSQL processes and disposable data directories were stopped/removed; final ports 55439 and 4202 have no listener. The temporary offline component server and tab were closed, viewport override reset. Browser proof remains outside Git under `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-UI-20261010` (`english-desktop.png`, `arabic-mobile.png`). The fixture uses synthetic client responses, denies all other endpoints and imports no Supabase client or credential. It is not a live acceptance test. The real application/simulation ports were not operated.

Automatic command review rejected recursive removal of the generated build directory. A reversible move preserved it at `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-Postgres-20261010\build-artifacts`, removing it from the checkout without deleting its contents. No generated build files, screenshots or database data remain in the product diff.

## File manifest and skills

Product changes: `src/app/api/data/route.ts`, new `src/app/api/quality/route.ts`, scoped `src/app/globals.css`, `src/components/FactoryApp.tsx`, `src/components/ui.tsx`; new `src/features/Quality.tsx`, `src/features/SourceStock.tsx`; existing `MaterialFlow.tsx`, `ProductionRecording.tsx`, `Warehouse.tsx`, `WarehouseOutputs.tsx`, `useSupply.ts`; EN/AR locale files; new `quality-contract.mjs`, `quality-quantities.mjs` and existing `production-recording.mjs`.

Tests: new `tests/quality-api.test.mjs`, `quality-conservation.test.mjs`, `quality-ui.test.mjs`; updated `planning.test.mjs`, `sales-fulfillment.test.mjs`; `tests/quality/local-bootstrap.sql`, `pre-source-fixture.sql`, `source-stock.test.sql`, `quality-control.test.sql`, `quality-boundary.test.sql`, `concurrency.mjs`, `run-local.ps1`, `cleanup-local.ps1`, `browser-fixture.tsx`, `preview.mjs`. Documentation: this record, `quality-control-v1-implementation.md`, `PRODUCT_DIFFERENTIATORS.md`, `HANDOFF.md`. Two draft migrations listed above. Canonical Design System remains unrelated/unmodified/untracked.

Applied skills: `ui-ux`, `frontend-design-codex`, installed better-web-ui frontend-design guidance and repository `.better-web-ui.md`, Supabase, computer-use, and scoped `ponytail-review`. `ponytail-lite` was read; its bounded small-fix scope was not used to simplify critical database behavior. No missing skill or tool is claimed to have run.

## Open gates and exact next step

**NEEDS VERIFICATION:** real Supabase claim/session behavior, PostgREST RPC signatures/schema reload, actual authenticated navigation and permission administration, source labeling discipline in a real warehouse, hosted end-to-end rework/corrections/export coexistence, touch devices, and user manual freeze. The previous hosted rollback suites were not rerun because their QA fixtures target a remote environment prohibited in this task. No financial/certification, enterprise genealogy or automatic equipment behavior is claimed.

The next deployment step requires **separate explicit TESTING authorization**. First inspect the current branch/diff and compare migration version/name/history against the intended TESTING project, keeping DEV read-only unless separate authorization permits more. Review the pending export-reader plus the two new Quality drafts and actual Supabase integration dependencies. Apply only approved missing forward migrations to TESTING; never edit applied bytes or repair/reconcile history to force alignment. Then use an existing approved TESTING account and controlled rollback fixtures to verify per-person Quality/History/Reasons, real receipt/source selection, partial dispatch/material issue/correction, Scrap/rework/reversal, concurrency, notifications, EN/AR/mobile, and stock conservation. Obtain user manual acceptance/freeze before any separately authorized checkpoint or push. No step in this paragraph is authorized by the current task.
