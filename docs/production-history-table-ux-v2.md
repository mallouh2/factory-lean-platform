# Production History — Table UX V2

## Owner-review cleanup — 20 October 2026

**LOCAL COMPLETE; awaiting owner review.** This section supersedes the earlier summary/Details/aggregate limitations below, which describe the first V2 iteration.

- Removed the entire combined summary, including its disclosure, and duplicate record count. One count remains with pagination; contextual export/printing is unchanged. Seven default columns, selection, toolbar Actions, filter/sort/page behavior and scoped preferences remain intact.
- Details keeps the six operational facts and concise order/item/product identity. No original-values panel for untouched entries. Actual correction history alone is available through View Correction History, using the existing authorized evidence; KG and production-unit values remain separate. No Phase 4C UI or writer change.
- New read-only SECURITY INVOKER RPC production_history_product_scrap(factory, entry) resolves the selected entry to its production request and product, then sums official effective_scrap_kg across matching items and entries. It uses original Orders view authorization, existing RLS and factory predicates throughout. The current request/product unique index permits one such item; the join also supports multiple distinct matching items without summing other products. Existing request and entry indexes suffice. No correction-log join/double counting, row/page/filter dependence, writer or new posting pipeline. Unknown evidence returns null, genuine zero remains zero. PostgreSQL numeric::text and the existing exact decimal formatter preserve precision.
- Forward-only local migration: 20261020133000_production_history_product_scrap.sql. Required because neither existing legacy nor V3 readers expose this exact request/product aggregate. Applied only to the existing disposable localhost PostgreSQL preview; no hosted operation. Missing migration/service fails closed to unavailable with retry, never a page-sum fallback.
- The existing authenticated GET History API accepts scrap_total_entry, validates UUID, checks Orders view before RPC and uses private/no-store responses. Details loads lazily, aborts obsolete requests and keys results to actor/factory/entry/refresh. No extra production data is stored in preferences.
- EN/AR labels, mixed identifiers/quantities with bidi isolation, locale percent formatting, compact spacing and empty load/filter containers corrected. User-entered names are not translated: this local fixture still has an English stored Arabic shift display name (Current shift) and English employee names. These are fixture/catalogue data, not UI labels; no arbitrary translation or operational data rewrite was performed.
- Global single-searchable-selector, single-selection table and focused engineering/test policies recorded in UX_SIMPLICITY_STANDARD.md. Existing selectors and other tables were not refactored. PRODUCT_DIFFERENTIATORS reviewed; no material new competitive claim warranted.

**Validation:** 136/136 focused Node tests (History component/helpers, aggregate API, reporting API, departmental exports); 14 PostgreSQL assertions in a fully rolled-back synthetic transaction. SQL covers >50 recordings, 15 KG Product A versus 8 KG Product B in one order, exclusion of same Product in another order, pending/rejected/approved corrections, exact decimals, repeat approval, missing evidence, inventory non-posting, real authenticated grants/RLS, restricted-user/factory denial and anon revocation. Existing request/product uniqueness prevents duplicate matching items in today's schema. Original 96 migration bytes unchanged; 97 local files after the new reader. TypeScript and isolated optimized Next build PASS. One lightweight real full-app browser smoke: normal disposable-owner login, no summary, one count, preserved preferences, Restore Defaults, seven columns, single selection/Actions, six-field Details, no audit for an untouched entry, English/Arabic and real protected 1.90 KG total. No native Print dialog or repeat download. This is standalone PostgreSQL plus the guarded local Auth/Data adapter, not hosted Supabase integration or fresh cross-browser/mobile acceptance.

**Cleanup file manifest (17):** HANDOFF.md; docs/design/UX_SIMPLICITY_STANDARD.md; docs/production-history-table-ux-v2.md; src/features/ProductionHistory.tsx; src/features/production-history-v2.css; src/components/TableExport.tsx (optional scope-count visibility, default unchanged elsewhere); src/app/api/production-history/route.ts; src/utils/production-history-view.mjs; src/locales/en.json; src/locales/ar.json; supabase/migrations/20261020133000_production_history_product_scrap.sql; tests/production-history.test.mjs; tests/production-history-view.test.mjs; tests/production-history-scrap-api.test.mjs; tests/production-history-scrap.sql; tests/production-recording-full-app/backend.mjs; tests/production-recording-full-app/prepare.ps1 (96 non-Export migrations for future fixture setup).

The old Phase4B conservation script assumes every later entry is 1.25 Meter/0.05 KG, so its quantity assertion is inapplicable to the owner's preserved 10 Meter/1 KG entry. A temporary read-only copy used the already documented five-entry/38.75/1.90/2 baseline, retaining every ledger/source/reservation/receipt/gate check; it passed. Repository verification script and all preview recordings were preserved. No test-data cleanup/reset occurred.

**Preview:** http://127.0.0.1:4207/?view=productionHistory . Full-app preview and local fixture remain running. Gates disabled; no late recording, Phase 4C, other-page redesign, hosted access/deployment, Git write, commit or push. All SQL test postings rolled back; preserved five-entry preview remains 38.75 Meter Good, 1.90 KG Scrap and 2 Meter WIP.


20 October2026. **LOCAL COMPLETE, with the evidence-availability limits below. Product-owner visual acceptance pending.** This is the first scoped implementation of the approved Table UX V2; no other tables were redesigned and Phase4C was not started.

## User journey and visual basis

Production employees and supervisors scan the official History, choose one record and open Details or an already supported permitted operation. Default information is the production reference, Product, attributable period/shift, typed Good and Scrap KG/rate. Supporting information stays on demand. The approved Phase4A application tokens, Inter/IBM Plex Sans Arabic, compact controls, native disclosure/dialog behavior, sticky headers and390px support are reused; no dependency or parallel table framework was added.

Brief comparable-product review supported compact overview/detail separation and preserving explicit report periods: [Evocon reports](https://evocon.com/feature/reports/) and [MRPeasy statistics](https://www.mrpeasy.com/resources/user-manual/production-planning/statistics/). These are workflow references, not evidence of Factory Lean superiority. PRODUCT_DIFFERENTIATORS was reviewed; this bounded UX implementation does not justify a new differentiation claim, so that existing file was not changed.

## Default view and actions

Exactly seven default columns, in this order:

1. Date.
2. Shift.
3. Production Line.
4. Production Order.
5. Product.
6. Good Production, with the entry's configured/frozen unit.
7. Scrap, in KG with the compatible-weight percentage in parentheses, or a neutral unavailable indicator.

No Actions or correction-status column is available. One toolbar Actions menu starts disabled. Pointer, Enter/Space and Up/Down/Home/End support single-row selection and a restrained selected state. Another row replaces the selection. Query, actor/factory changes or disappearance on refresh remove stale selection and close Details. Background refresh retains same-query rows; actions remain unavailable while a relevant load/error is unresolved. Empty/error/loading states and retry remain explicit.

Actions contains View Details and the existing correction entry point only when current effective Orders edit allows it. Invocation checks the current selected result and live UI permission again; actual correction submission still goes through the unchanged protected server/database authorization and approval/source contracts. No new correction workflow, approval screen, account, grant or inventory command was implemented.

The six-field compact native Details dialog uses a full-screen layout on390px mobile. Order/request, item code and Product identify the selected record. The existing historical/audit content remains behind History & original values. Language switching inside the modal changes labels as well as direction, and close restores focus to Actions.

## Evidence and time bases — no invented values

| Display | Source and meaning |
|---|---|
| Date | Frozen effective occurrence business date if already supplied; otherwise actual stored effective production-period dates in the factory timezone. A multi-date period is shown as a range. Missing production attribution stays unavailable; created_at is never substituted. |
| Shift | Existing protected History shift association/name. Existing catalogue-name and missing Arabic-name behavior is preserved; no historical name, shift boundary or Arabic business-data translation is invented. |
| Good | Existing official effective_good and the entry's stored unit, preserving approved corrections and excluding pending proposals. No Meter/Piece/KG aggregation or current-Product unit guess. |
| Total Good at this recording | Persisted running_good snapshot for that item at recording time, not today's cumulative total or a reconstructed chronology. Missing remains unavailable. |
| Remaining at this recording | Persisted remaining_quantity snapshot and recorded unit; no current target used to invent a historical remainder. |
| Responsible technician | Existing technician_name, distinct from submitter_name. |
| Submitted by | Existing submitter_name; never substituted with the responsible technician. |
| Unfinished output in this entry | Explicit effective_unfinished and unit. Explicit zero means None; missing means unavailable. This is recorded unfinished output, not a claim about the current physical lot location or remaining WIP stock. |
| Total order Scrap · KG | Exact decimal sum of official effective_scrap_kg for the selected order item only, **only when the entire unfiltered History result is present in one complete page**. Other items are excluded. Any missing KG, active filter, incomplete/paginated result or absent order identity yields unavailable instead of a partial order total. Scope is the loaded authorized result, not an unverified live value. |

The existing legacy History reader has no protected item-specific cumulative KG summary. A reliable always-available total in filtered/paginated History requires separate authorization for a small protected item-summary read extension. That portion is deliberately not implemented. No additional backend reporting capability or migration was added merely to fill a field.

Date/shift attribution in older records may be absent. The existing reader does not always supply a frozen business-date/name projection; the UI uses the actual production-period evidence it has and exposes the date basis in its title rather than inferring an exact production instant or business date. A period range is not claimed to be an exact timestamp.

Existing filters and sorting remain on their original protected contracts. In particular, their date basis is **submission date/time**, now labelled explicitly in the filter chooser/sort option; displaying production attribution does not silently change filter, sorting or export semantics. Hidden-column filters remain reachable through Filters. Existing category search, pagination and correction-status filtering are preserved.

### Scrap percentage

The formula is the existing History/Quality/M3 rule: **100 × effective Scrap KG / recorded produced_weight_kg**. The recorded output-weight basis represents Good plus newly recorded WIP output weight; meters or pieces are never a direct denominator. Only RECORDING_CONFIG or VERIFIED_HISTORICAL weight evidence with a positive KG denominator and known nonnegative Scrap is eligible. Unknown/missing conversion or zero output yields a neutral dash. No current recipe, current weight, retrospective conversion or new loss policy was introduced.

Exact decimal text remains intact when supplied, including the full-value title on long Good values. The existing legacy reader's native JSON numeric transport is unchanged; the formatter does not reconstruct digits already lost by that pre-existing transport. Existing exports retain their precision checks. No new financial/inventory arithmetic or measurement posting was added.

## Column preferences and exports

Columns supports the seven defaults plus existing technician, submitting employee, submission time, unfinished quantity and an authorized Machine field. Machine is offered only with Centers view and resolves only the recorded work-center reference from the authorized snapshot; no current line-to-machine inference is made for historical line entries.

Preferences use `factorylean:table:v2:production-history:<actor>:<factory>` in local browser storage. Only column identifiers are stored. Removed/unknown/unauthorized identifiers are ignored; at least one visible column is required; invalid data restores defaults. User changes persist immediately without the initial-hydration overwrite race. A storage failure retains the current layout and reports that it could not be saved. Factory/user changes do not inherit another scope's layout. Other tables are unaffected.

Excel/Print remain the existing separately authorized all-matching-rows reports, with existing filters, sort, permissions, limits and precision protection. Production History had no server-side selected-column export contract; the chooser therefore affects this table only, as its help text states. No client-supplied report columns or new export bypass were added. PDF remains the existing Print/browser destination.

## Executed local evidence

- **309/309 focused Node tests**,11 files, zero failures/skips: Production History, new presentation helper, reporting API, correction/consumer contracts, lazy History, table export/core Batch1, recording UI, permission preview and factory navigation. Existing assertions were adapted only for the intentionally removed row/status columns and toolbar filter access; underlying filter, pagination, background-refresh, error, audit and export coverage remains.
- **17/17 actual Microsoft Edge155.0.4283.62 full-application scenarios**: seven columns; pointer/keyboard selection; six-field Details; existing allowed correction action; preference persistence/minimum/defaults; sorting; selection cleared by refresh/pagination; official values vs pending proposals; missing weight/date/WIP evidence; incomplete order totals; long names/decimal values; loading/error/retry; EN/AR/RTL/reload;390px full-screen Details; protected Excel and Print responses; independent worker preferences; real restricted-user HTTP403/no rows.
- **TypeScript and isolated optimized Next16.3.5 webpack build PASS** on the final inputs. No repository environment file was copied into the build.
- Final browser suites: zero uncaught page exceptions and zero external browser requests. The isolated full application runs the actual Next/authenticated API source and original PostgreSQL functions/RLS behind the guarded local Auth/Data protocol adapter; it is not GoTrue/PostgREST or hosted acceptance. Empty/error/long-data/pending-proposal edge cases are confined to browser responses, not database changes. Factory preference isolation is tested by key/allowlist unit cases; no second factory was created for a browser claim.
- Real Excel/Print API responses returned200; no unnecessary file download or native print dialog was opened. Existing server authorization/revocation/cross-factory/precision/export-limit regressions passed. Chrome/Firefox remain PENDING because unavailable.
- Read-only current-fixture check: Good38.75 Meter = finished stock38.75 = source credit38.75 = ledger38.75; reserved0; recorded WIP2 Meter; Scrap1.90 KG; five preserved synthetic entries. No recording, correction, inventory, Quality or operational transaction was submitted by this task. Current records were preserved rather than reset to the earlier four-entry fixture. V3 late-recording and local Maintenance activation remain disabled.

Evidence directory: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-History-UX-V2-fa8f23189d7e4f5c8970da66d677e802`. It contains baseline hashes, final preservation evidence, browser run directories/results/screenshots, read-only stock evidence and build-location reference. Final full Edge run: `edge-1792485097964`. Node log: `%TEMP%\FactoryLean-History-UX-V2-node.txt`. Additional final in-app owner-review screenshots confirm the integrated screen after the scoped caption/heading accessibility polish. Diagnostic selector/transport/HMR failures were corrected; they are not passing cases.

## Exact task files

Modified baseline files:

1. `src/features/ProductionHistory.tsx` — approved table, single selection, menus, scoped preferences and six-field Details; existing filters/audit/export retained.
2. `src/features/ProductionRecording.tsx` — forward the existing language callback to History/Details only.
3. `src/app/globals.css` — one import of scoped History styles.
4. `src/locales/en.json` — History labels/help.
5. `src/locales/ar.json` — matching Arabic labels/help.
6. `tests/production-history.test.mjs` — updated approved rendering, retained filter/refresh coverage and read-only/selection regressions.
7. `tests/production-recording-full-app/backend.mjs` — bounded products/factory metadata reads and single-object response support required by existing export contracts, still under original authenticated SQL/RLS; no production adapter import or grant changes.
8. `HANDOFF.md` — current scoped outcome and stop boundary.

New files:

9. `src/features/production-history-v2.css` — token-based scoped table/menu/dialog/mobile styling; no unrelated page styling.
10. `src/utils/production-history-view.mjs` — column allowlist/preferences, honest period display, existing mass-ratio presentation and complete-result-only KG total.
11. `tests/production-history-view.test.mjs` — presentation/evidence/precision/preference regressions.
12. `tests/production-history-ui/browser.mjs` — real local application/Edge acceptance, with guarded browser-only edge cases.
13. `docs/production-history-table-ux-v2.md` — this report and explicit limits.

## Preservation and owner handoff

Started on development/HEAD bb0d20e5dd433b896dd319f56e75f0d9eb5d2862 with786 individually hashed project files,43 modified tracked/188 untracked individual/zero staged and96 migrations. Final comparison permits only the13 task files above. All unrelated work, historical migrations, Export Reader, Design System, environment/link metadata, HEAD/main/index are preserved. No Git staging/commit/push/merge/reset/stash/branch change, hosted access, migration, activation or deployment occurred. The original prior recovery backups remain untouched.

Verified real preview: **http://127.0.0.1:4207/?view=productionHistory**. The ordinary signed-in local owner session is open in the complete application. Select a row → Actions → View Details; try Columns, restore defaults, EN/AR, refresh and mobile. This is not the disconnected4190 component harness. The local server remains running.

Owner approval is pending. An always-available item-level Scrap summary or a fuller frozen business-date/name projection needs separately authorized read-only backend work; missing evidence remains honest in this implementation. No Phase4C, other-table rollout, feature activation, hosted deployment or Git checkpoint is authorized. **STOP for visual review.**
