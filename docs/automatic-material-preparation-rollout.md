# Automatic material preparation — local rollout, 4 November 2026

**Status: COMPLETE locally on 4222; owner manual acceptance pending.** No hosted release, source promotion to 3000, Git checkpoint or new account was performed. Native HTML5 drag/drop remains a manual acceptance check; it is not claimed as a browser PASS.

## 1. Current environment and continuity

- Authoritative repository remains on development at bb0d20e5dd433b896dd319f56e75f0d9eb5d2862, with its existing dirty work/index preserved. Repository edits in this task are documentation only.
- Active 4222 source: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/material-preparation-candidate-1793769667321. Runtime: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/material-preparation-candidate-1793769667321/.next-material-release/standalone. The candidate is copied from the previously accepted 4222 source; it is not the original 3000 checkout.
- Existing owner PostgreSQL: 127.0.0.1:55496 / factory_lean_quality_local; Auth4304; application4222. Every writing tool verifies loopback host, port, database and exact data directory.
- Disposable acceptance only: PostgreSQL55640 / Auth4368 / application4268. No QA products, orders, lines or quantities were imported into the owner database.
- Ports3000 and4242 were not accessed, changed or restarted. No hosted TESTING/DEV/Simulation/PROD access.

## 2. Existing architecture reused

Existing Product recipes, protected material_requests/supply readers, raw inventory_transactions/reservations, finished balances and identified source allocations, Planning confirmation/history/fingerprint, Production Recording V3, Quality release, quantity receiving and Sales fulfillment remain authoritative. There is no second inventory ledger, automatic recipe consumption, new permission system or per-warehouse balance model.

## 3. Product/manufacturing-stage configuration

Products → Physical production inputs selects one reusable default or configured work-center stage:

- COMPOUND_STOCK: request only the finished Product's compound stock in KG.
- DIRECT_RAW: request only its configured compound recipe's actual raw ingredients.
- COMPOUND_MANUFACTURE: request the compound Product's own recipe ingredients.

Product weight per stock unit and the versioned recipe determine theoretical requirements. No inference from the presence of both compound/raw records. Multiple matching configured stages, missing route/recipe/weight or incompatible units produce an actionable order/product warning. Only automatic generation is blocked; explicit valid manual material requests remain usable. Changing requirements after preparation requires review instead of silently resizing commitments. Configuration is factory-scoped, Orders-edit protected, revisioned and immutably audited. See production-material-inputs.md.

## 4. Independent preparation setting

Planning → Custom date range and zoom contains the independent Material preparation window, default6 hours, positive decimal input (1.5/4.25 verified). The original owner's **Planning Change Warning Window is7 hours** and remains7; it was not reset to the historical6-hour documentation default. Changing one setting does not change the other. No unrestricted activation toggle was introduced.

## 5. Prompt and durable generation

A committed schedule reconciles that item immediately under the existing structure lock. An independent, localhost-only Node worker processes bounded/fair batches every15 seconds with factory→structure lock ordering, lock/statement timeouts and transaction rollback on failure. It runs without an open browser page and has no public scheduler RPC grant. It validates current schedule, holds, physical-input configuration, manual quantities and existing automatic identities before creating a System REQUESTED record. Completion/rework source-lot jobs keep their existing source request; their recipes are not exploded again.

A unique factory/item/physical-input key prevents duplicate automatic requests. Manual requests subtract from the same physical requirement. Recipe/configuration or manual-demand changes that make existing automatic commitments inconsistent fail closed for further automatic preparation. No automatic stock reservation, issue, approval or consumption occurs.

Actual background proof: a new disposable order was scheduled outside6 hours, entered the window naturally, and the running worker created exactly one10 kg request with actorNULL after the QA page was closed. Evidence: durable-worker-proof.json.

## 6. Warehouse lifecycle and pooled inventory

Warehouse Requests retains its original counted/paged queue and export. Its protected reader now includes preparation progress and the Production Order reference; managed partial issues remain visible instead of disappearing under the legacy ISSUED filter. Fully consumed requests leave the actionable queue. The service augments only visible material items in bounded groups.

Warehouse-issue permission authorizes explicit partial Reserve, Confirm physical issue, Release reservation and Return unused material. Product/compound stock uses existing physically identified source choices. Historical unattributed stock is not assigned an invented origin. SQL enforces revision, factory, source identity, available/uncommitted quantity and Quality holds. Return requires physical confirmation and a reason and restores the exact source; it never fabricates unattributed stock.

Reservation increases Reserved/decreases Available without changing On Hand. Physical issue reduces On Hand and reservation exactly once, recording an existing-ledger stock-out and Production custody. Existing purchasing/opening/receipt behavior and pooled balances are unchanged. Expected incoming is not physical availability.

## 7. Actual consumption

Factory Floor → selected job → Record Production → Production materials shows requested/reserved/handed-over/measured-use quantities. An active legitimate execution and Orders view/edit authorize recording measured use up to unconsumed issued custody. It does not deduct Warehouse stock again and does not create or alter Good/Scrap/WIP. Existing Good/Scrap/Quality/receiving writers remain unchanged.

Browser proof, disposable raw material: before additional actions OnHand97, Reserved5, Issued3, Consumed0; reserve2 gives97/7/3/0; issue1 gives96/6/4/0; measured use1 gives96/6/4/1 with **zero production entries fabricated**. Available remains90 after the handover because physical stock and its reservation decrease together.

## 8. Postponement, return and re-reservation

Moving outside the preparation window releases only eligible unissued reservations, leaves stock/custody untouched, preserves request identity and marks awaiting re-reservation. Re-entry reactivates the same request; Warehouse must reserve again. Both affected departments see committed release/reactivation events. Manual managed requests also resume correctly.

Issued material never returns automatically. Partial return is limited to physically returned, unconsumed custody and is actor/UUID protected. The existing same-line/unstarted/zero-consumption rescheduling exception now recognizes verified raw/compound custody as well as the previous source-lot contract. Started/consumed/held/retired work, unsafe unscheduling and incompatible lines remain blocked. A line move requires explicit release/return of managed custody first. No reassignment bypass was added.

## 9. Notifications

The existing Plan & material updates surface carries request creation/reactivation/postponement to Warehouse and Production; reservation, physical issue, release and return updates reach Production. Planning changes reach Production; Warehouse receives a change only when an actual request/preparation existed at the committed revision. Later request creation does not retroactively invent Warehouse involvement. Failed transactions/retries generate no duplicate events. Factory/audience permissions and per-person acknowledgments are enforced in SQL. Previous finding PO56 had no material activity and was not classified as a missing-notification defect.

## 10. Factory time correction

The existing authorized owner used the normal update_settings API to change only the owner factory's timezone from UTC to Asia/Qatar, preserving its name/logo/calendar and absolute timestamps. The supported prospective shift-revision fence remains intact; dated historical shift evidence was not rewritten. Existing presentation helpers now also handle precise event inputs with seconds/milliseconds. Previously browser-local Lean/production event inputs use the factory IANA zone. Historic occurrence boundaries remain stored evidence; ordinary timestamp display uses the current factory clock.

## 11. Historical preservation

No stored timestamp had3 hours added. Qatar09:00UTC→12:00 display and local round-trip, overnight date rollover and existing DST gap behavior were tested. Browser schedule edit11:00–17:00 persisted08:00–14:00UTC with exactly6 hours. No existing owner's planned/actual production or historical record was edited.

## 12. Timezone labels

Ordinary Planning range/start/editor and Production/History shift displays no longer append UTC/GMT/IANA names. Labels remain available in real timezone configuration and technical export metadata. Timezone semantics were preserved rather than hidden by string replacement on saved values.

## 13. Gantt scale

The stored-time percentage geometry was already correct. The misleading visual was the fixed-width dark short-job caption, which could look like occupancy at either zoom. The compact caption is now a white labelled surface with an accent; its separate colored duration band uses the exact parent width. No minimum caption width inflates time occupancy. Lane colors, priorities, warnings, selection and existing drag/scroll code remain unchanged.

Actual1440px browser proof for the same six-hour job: Day25% /292.80px; Week3.57143% /39.16px, with a separate168px Week caption. EN/AR and390px layouts were inspected. A guarded form reschedule committed correctly and preserved duration/history. Native automation attempted HTML5 drags but produced no drop; **live drag and edge-auto-scroll remain owner manual checks**, while their existing automated regressions pass. This was not classified as an application defect without evidence.

## 14. Protected SQL, concurrency and authorization

**150 assertions passed:**21 configuration +64 integrated material/stock/source/demand/notification +5 existing security +19 existing capacity +41 affected Planning/Quality/recovery/maintenance regressions. No inventory integrity failure occurred. New integrated tests exercise the complete protected Sales→Production→raw reservation/issue→measured use→Good→Quality→Warehouse→identified Sales dispatch chain and compound manufacture→identified compound partial issue/return/use. Deferred source conservation is forced before rollback.

**4 independent-connection races passed:** stale reservations; concurrent identical-UUID issue; partial issue versus postponement; simultaneous scheduler runs. Exactly one issue stock-out/retry receipt and correct100=OnHand+Issued were verified. Failed stale transactions return40001 without extra stock movements.

**9 authenticated HTTP checks passed** on disposable QA: protected reads; actual403 Warehouse/configuration/issue/cross-origin/cross-factory denials; decimal configuration retry; normal timezone setting. Unauthorized writes leave progress unchanged. Effective direct/package permission implementation and private raw-table/scheduler restrictions are preserved.

The older release fixture required its missing local helper setup, explicit no-policy precondition, exact-command notification checks (new routing intentionally includes ordinary committed changes) and classification-based group selection rather than random UUID-array indexes. Business assertions were retained. The stale nested export mock was updated to the existing counted/selective reader contract; it was not weakened to accept incomplete paging.

## 15. Node evidence

Full root Node suite: **1476/1476 PASS, zero skips** against final source. Focused material/time/Gantt and nested Warehouse tests: **17/17 PASS**. Logs and test scripts are retained at C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/material-preparation-investigation-1793769418083. No meaningful test was deleted.

## 16. TypeScript/build

TypeScript noEmit PASS; isolated optimized production build .next-material-release PASS. Turbopack rejected the inherited dependency junction as outside its root; the existing supported Webpack build was used without installing dependencies or changing the application configuration. A standalone-copy junction permission error was resolved by serving the verified standalone directory directly. The six SQL scripts were not retried or repaired. Build-generated metadata is not a feature or Git staging proposal.

## 17. Browser evidence

Normal existing owner login, Product default/stage input choices, independent decimal4.25-hour UI save (warning7unchanged), real partial reserve/issue and Production measured use, Arabic acknowledgment, Qatar operational timestamps, Day/Week/short labels, EN/AR desktop and390px passed in disposable QA. Screenshots and exact before/after quantities are retained. No QA browser console warnings/errors were observed. Final4222 normal owner login, Planning settings6/7, Qatar-no-suffix UI, original-only factory resources and Warehouse reads passed; no artificial fixtures appear in4222.

## 18. Exact local source/migration manifest

Six forward scripts applied only to disposable55640/fresh55641 and owner55496 after verification:

- `20261104052136_production_material_preparation_v1.sql` — SHA256 `df84339b27dc5d5bc7223ffca7038c6b20ebdb6f520afbdd66e8b52b2bd79646`
- `20261104053521_production_material_lifecycle_v1.sql` — SHA256 `c2d5dbc5f848184ad50c851e026cd0a54e877671730ff730af7652fa304f8e8c`
- `20261104053953_production_material_operations_v1.sql` — SHA256 `4a9e546868aa29a22485580a6bb22bd6d7e094c0d09d598b0b3bd029eecff82e`
- `20261104054443_production_material_operation_binding_v1.sql` — SHA256 `813d5c4c8141d54e32646c43d220024111271cf91859143f485dbf55dd05346c`
- `20261104054743_production_material_integration_v1.sql` — SHA256 `4450406a9b9b107e00ac1b220a899281fd6f383987057d742b7d7af7cf49b11d`
- `20261104062431_production_material_request_projection_v1.sql` — SHA256 `d7134b1b4dc8873454000d9b7cf6f09c362d8891a24f6d74b0132c5edb4e5444`

All147 older accepted-source migration hashes, including Export Reader, are unchanged. These are local SQL application results, **not a claim about hosted migration counts/history**. Export Reader was not applied by this task. Exact changed-source manifest (relative to the isolated accepted4222 baseline):

- `scripts/local-material-preparation-worker.mjs` (new)
- `src/app/api/production-materials/route.ts` (new)
- `src/app/globals.css` (modified)
- `src/features/HistoricalProductionRecording.tsx` (modified)
- `src/features/LeanProblem.tsx` (modified)
- `src/features/LeanScrapReview.tsx` (modified)
- `src/features/MaterialPreparation.tsx` (new)
- `src/features/PlanningChangeUpdates.tsx` (modified)
- `src/features/ProductionHistory.tsx` (modified)
- `src/features/ProductionPlanning.tsx` (modified)
- `src/features/ProductionRecording.tsx` (modified)
- `src/features/ProductionRecordingV3.tsx` (modified)
- `src/features/Products.tsx` (modified)
- `src/features/SourceStock.tsx` (modified)
- `src/features/WarehouseRequests.tsx` (modified)
- `src/locales/ar.json` (modified)
- `src/locales/en.json` (modified)
- `src/services/warehouse-requests.ts` (modified)
- `src/utils/manufacturing.mjs` (modified)
- `src/utils/warehouse-request-rows.mjs` (modified)
- `supabase/migrations/20261104052136_production_material_preparation_v1.sql` (new)
- `supabase/migrations/20261104053521_production_material_lifecycle_v1.sql` (new)
- `supabase/migrations/20261104053953_production_material_operations_v1.sql` (new)
- `supabase/migrations/20261104054443_production_material_operation_binding_v1.sql` (new)
- `supabase/migrations/20261104054743_production_material_integration_v1.sql` (new)
- `supabase/migrations/20261104062431_production_material_request_projection_v1.sql` (new)
- `tests/material-preparation/configuration.test.sql` (new)
- `tests/material-preparation/integrated.test.sql` (new)
- `tests/material-preparation.test.mjs` (new)
- `tests/warehouse-final/export.test.mjs` (modified)

Documentation updated in both the authoritative repository and isolated source: `HANDOFF.md`, `docs/automatic-material-preparation-rollout.md`, `docs/production-material-inputs.md`, `docs/planning-v3.md`, `docs/warehouse-management-v2.md`, `docs/PRODUCT_DIFFERENTIATORS.md`.

## 19. Recovery and evidence

Recovery reused, not recreated: C:\Users\Temp\AppData\Local/FactoryLean-Recovery/material-preparation-1793769454685. It contains4313 previously SHA256-verified files, including2098 cold database files and the accepted/authoritative source snapshots. Evidence pointer: %TEMP%/FactoryLean-Material-Preparation-location.txt → C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/material-preparation-investigation-1793769418083. owner-migration-results.json records each of the6successful local scripts. **Do not rerun promote-owner.mjs.** Fresh-chain validation started from the cold recovery and applied all6 unchanged scripts successfully; the validator was stopped.

## 20. Owner preservation

Immediately after migration, all127 original table digests match, normalizing only the newly added automatic_requirement_key=NULL field on pre-existing request rows. The supported timezone command subsequently changes the factory timezone/updated_at, appends exactly one shift configuration revision and one audit entry, and appends one ordinary Lean runtime observation with its source revision update. All old audit/runtime/shift rows remain. The other122 table digests match exactly, including auth.users, all membership/direct/package grants, source/stock/reservations, Sales, production/Quality/downtime/Loss and activation tables. Factory fields other than timezone/updated_at are unchanged. PO30 remains its original pending5m/0KG submission; PO20 source/custody and all existing schedules remain unchanged. No owner rows were deleted or QA data imported.

## 21. Remaining acceptance and limits

- Already-generated automatic requests are frozen if recipe/physical-input evidence changes; automatic rebasing or deleting commitments is deliberately not provided. The visible review block must be resolved under a separately reviewed disposition, not by silently changing issued material. Configure the correct single matching stage before scheduling.
- Owner manual acceptance, particularly native drag/drop and edge auto-scroll, is pending. Automated regressions pass; no fabricated live-drag result is claimed.
- Existing owner Products have no inferred physical-input route. Configure valid recipe/weight and explicit input stage in Products before expecting automatic requests. The missing-route warning is intentional; stock/reservations remain untouched.
- This is local preview infrastructure. The background worker requires the4222 local runtime process; no hosted cron, deployment or operational release is claimed.
- No new broad Warehouse redesign, per-warehouse stock-outs, automatic replacements, general purchasing Quality gate or completed-shift late activation was added.

## 22. Manual handoff

Open **http://127.0.0.1:4222/?view=planning**. Existing owner credentials are unchanged in the existing owner local credential file. Products → Physical production inputs configures master data. Planning → Custom date range and zoom shows preparation6 hours and existing warning7 hours. Warehouse → Warehouse Requests handles reserve/partial issue/return. Factory Floor → selected job → Record Production → Production materials records measured use separately from output. The user now performs manual acceptance.

Keep4222 application/Auth/database and its material worker running. Runtime pointer: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/runtime.json; worker health: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/material-worker-status.json. If restarting later, first check listeners and the recorded owner process IDs; use existing local credentials/runtime only. Do not rerun migrations, reset fixtures or start a second worker. Disposable QA processes are stopped after evidence collection; fixtures/results are retained.

**Boundaries:** 3000 untouched; 4242 preserved;hosted environments untouched; no account/password/permission changes;unrelated historical/late/Maintenance/manufactured-output gates preserved;no Git commit,push,reset,stash,clean,merge or deployment;no owner data loss. Repository Design System remains untouched/untracked. STOP for owner review.
