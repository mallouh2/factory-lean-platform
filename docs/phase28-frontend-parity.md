# Phase 2.8 continuation — final frontend reconciliation

6 November 2026, Asia/Qatar.

**FRONTEND CORRECTIONS COMPLETE — ADDITIONAL VERIFICATION REQUIRED.**

All ten requested frontend areas have been reconciled with the documented preview lineage. No additional approved missing change was found. The already completed Quality correction is retained. Fresh native testing identified a separate Planning conflict-message defect; native saved drag/drop and edge-autoscroll acceptance remain incomplete.

Evidence: C:/Users/Temp/AppData/Local/Temp/FactoryLean-Phase28-Continuation-85fcca12.

## A. Frontend parity matrix

Source parity and browser acceptance are separate conclusions.

| Area | Latest documented design | Current integration | Status | Corrections in this continuation |
|---|---|---|---|---|
| Planning V3 | Latest material candidate plus Gantt cleanup, policy/replanning and short-duration-band refinements | Same component/helpers/CSS; unscheduled and compact scheduled lists, dialogs, warnings and protected drag paths retained | PARITY CONFIRMED in code; native saved drag/drop UNVERIFIED; conflict-feedback defect below | None |
| Production Recording V3 | Dedicated modal, exact work selection, current/original-open-shift eligibility, retained drafts/retries/recent entries | Same component; four fresh native scenarios selected completed original-open-shift work, entered quantities and expanded recent entries | PARITY CONFIRMED within tested scope | None |
| Factory Floor | Latest toolbar, delayed filter, animation-only toggle, machine controls and Recording/History navigation | Same component; delayed filter and animation toggle exercised in all four layouts; physical machine transitions were not repeated | PARITY CONFIRMED in source and listed interactions | None |
| Warehouse | Inventory/Requests, latest receipt warehouse selection, pooled dispatch, management/movement views | Receipt and Stock Movements open; quantity-only partial dispatch sheet has no physical-batch selector | PARITY CONFIRMED in source/presentation; no new receipt/dispatch commits | None |
| Sales | New Sales Order → Save Draft → deliberate Confirm Order with availability preview | Four native draft/confirmation workflows persisted successfully through actual app/API/database | PARITY CONFIRMED for creation/confirmation | None |
| Material Preparation | Orders-scoped preparation window; explicit reserve/issue/release/return/measured use with physical custody confirmations | Six-hour field remains under Orders; Warehouse request controls expose four operations and mandatory handover/return confirmation | PARITY CONFIRMED in source and listed controls; no new custody commits | None |
| Production History | Single count, filters/search, selected-record six-fact Details, contextual Quality evidence and factory-local times | Filter controls and record Details exercised in four layouts; earlier Recording→History→Back tests retained | PARITY CONFIRMED in code/listed interactions; full filter-history restoration not exhaustively certified | None |
| Sidebar and Settings | Final navigate-before-expand parents, separate chevrons, filtered nested settings and mobile close | Final recovered component remains; earlier four-layout parent/chevron/back checks retained; Settings controls opened afresh | PARITY CONFIRMED within scope | None |
| Maintenance | Phase 2.7 neutral preview guidance and scoped 401/403/400/409 behavior | Original fixes byte-identical; full/focused regressions pass; earlier actual HTTP evidence remains historical | PARITY CONFIRMED in source; no reservation gate activated | None |
| Lean, Reporting, shared UI | Latest status-key/timezone fixes, zebra/sticky tables, alignment, contextual Excel/Print | Matching source/CSS/dependencies retained; Lean page and movement/history interfaces sampled; shared regressions pass | PARITY CONFIRMED in code; export downloads/native printing not repeated | None |

Quality is not reopened: Finished remains the read-only exact-decimal result of Actual Total − Rejected − Recoverable Unfinished. Quick approval, required reasons, grouping, original technician evidence and compact layout remain as explicitly approved.

## B. Confirmed missing changes

**None additional.** Current comparison covers all 242 src files against the latest recovered material-preparation candidate: 236 match after line-ending normalization; the six differing files are fully accounted for:

- ManufacturedOutput.tsx: the owner's completed Quality calculation correction.
- LeanProblem.tsx: Phase 2.5 localization correction.
- api/data/route.ts and both locale files: Phase 2.7 Maintenance corrections.
- globals.css: exclusion of the unapproved drag-source opacity rule.

The preceding audit already compared 39 available preview source roots plus Consolidated QA final-app. That work was retained rather than restarted. No source-only file was missing from main. Older partial implementations are not replacements for the final integrated lineage.

Relevant precedence records include planning-v3.md, planning-policy-rollout.md, automatic-material-preparation-rollout.md, production-recording-selection.md, warehouse-inventory-workspace-ux.md, warehouse-receipt-ux.md (including the later V2 supersession), warehouse-management-v2.md, production-history-table-ux-v2.md and sidebar-production-material-settings.md.

## C. Corrections applied and new finding

No production source correction was justified by this continuation's parity comparison. Only this report and the current HANDOFF entry were added/updated. Existing source, tests, CSS, APIs, permissions and migrations were preserved.

### Newly confirmed Planning feedback defect — P2

A trusted desktop native drag over capacity occupied by active work raises **RangeError: Invalid time value** in planningMessage, called by onDragOver. It occurred in EN and AR desktop attempts and was reproduced in a separate English debug run. No plan command was sent.

Root cause:
- src/utils/planning.mjs:164–165 intentionally represents an open-ended operational occupancy using negative/positive Infinity. This protects capacity and must remain.
- src/features/ProductionPlanning.tsx:195 converts the selected conflict start/finish to ISO dates without checking finiteness.

The attempted capacity conflict should remain blocked and show a localized explanation. Formatting Infinity as a date fails before that feedback can complete.

This behavior also exists in the latest donor; it is not evidence of a reverted or missing integration. The authorized recovery scope does not justify silently expanding into a new product correction. A minimal **proposed, unapplied** patch is retained in evidence as PROPOSED-NOT-APPLIED-planning-finite-time.patch: format the interval only when both ends are finite, otherwise use the existing unknown-finish label. It changes no capacity or scheduling rule. A follow-up should test unbounded active occupancy in EN/AR, retain rejection and verify zero scheduling writes.

Evidence: gantt-native-results.json, gantt-debug-results.json with the browser stack, and the proposed patch. No production correction or acceptance claim is made for this defect.

## D. Excluded/ambiguous UI

- Drag-source fading remains an UNAPPROVED EXPERIMENT and stays excluded.
- Older embedded recording, outdated Quality quantity inputs/recalculation controls, mandatory pooled-dispatch batch selection and pre-final sidebar backups were not restored.
- Marketing and the unapproved global Design System were untouched.
- The owner's Quality clarification resolves the previous calculation-direction ambiguity. It is no longer a question for owner decision.
- Final visual approval remains pending for the implemented refinements. Automated success and newer timestamps were not treated as approval.

## E. Fresh browser verification

Only a new copy of the stopped synthetic disposable cluster was used. The actual server identity was independently queried and checked: 127.0.0.1:29509 / factory_lean_quality_local / evidence-directory/data; adapter 29510; app 29511. Public writers execute with authenticated actor claims and exact-destination guards. No hosted endpoint or owner runtime was used.

| Current evidence | Result |
|---|---|
| Four EN/AR × 1440/390 remaining-area scenarios | 32 successful grouped checks, plus eight queue-control checks resolved by the dedicated queue harness: 40 distinct grouped checks total |
| Sales | Four real Save Draft + Confirm Order flows; eight successful persisted application writes, verified synthetic order state |
| Warehouse/material queue supplement | Four scenarios pass pooled partial-quantity presentation, no batch selector, RESERVE/ISSUE/RELEASE/RETURN options and physical-confirmation controls; no writes |
| Recording/Floor supplement | Four scenarios pass dedicated modal, completed original-open-shift picker, quantity entry, recent disclosure, delayed filter and animation-only toggle; no production writes |
| Gantt | Four drag attempts did not submit a scheduling command. Desktop trusted drag events exposed the defect above; mobile attempts did not establish trusted native drag. A separate eligible-line attempt also produced no scheduling command and remains an automation/manual-verification gap |
| Earlier audit | 36 settled page/layout cases and four Recording/History/sidebar navigation scenarios remain prior evidence, not counted as new here |
| Quality | Prior four component-fixture scenarios remain valid for unchanged corrected code; not rerun or represented as new database acceptance |

The queue API returned valid dispatch and material rows. Initial harness checks inspected before those rows loaded; explicit readiness waits resolved them. A desktop AR pointer left over the hover-expanded sidebar also initially intercepted a tab click; moving outside the sidebar before checking resolved the harness issue. No product changes were made for those problems. A harness final-output scope error occurred after all four remaining-area scenarios were saved; consolidation preserves their saved per-case results and the successful independent queue evidence rather than claiming the initial script exited successfully.

**Correction to the earlier audit:** incomplete Planning availability was observed during loading, but settled readers do become COMPLETE without activation. It must not be described as a persistent release-gate blocker. Current native verification remains incomplete for the distinct reasons above.

No production, material, receipt, dispatch, settings, physical-machine, Maintenance or gated write was attempted by the browser. Only the eight explicit Sales create/confirm writes were allowed. No outside-origin requests were allowed. Shared table/export code parity is confirmed, but no new file download or native Print/PDF dialog acceptance is claimed.

## F. Fresh automated results

- **679/679 focused tests passed**, zero skips: Planning, Production Recording, Floor, Warehouse/Sales, material, History, sidebar/navigation, Maintenance, Lean and tables.
- **1,487/1,487 full Node tests passed**, zero skips.
- TypeScript noEmit / incremental false passed.
- Isolated optimized webpack production build passed.
- Tests are not proof of final owner visual acceptance or the unverified native Gantt flow.
- No SQL migration or standalone SQL regression suite was run: there was no database/backend change. Real database commands were exercised by Sales and protected readers.
- Main Quality and Maintenance executable files retain their verified hashes.

## G. Owner visual review

Verified combined preview: **http://127.0.0.1:29511**.

Use the synthetic account in the owner-only local file:
C:/Users/Temp/AppData/Local/Temp/FactoryLean-Phase28-Continuation-85fcca12/LOCAL-REVIEW-LOGIN.txt.

The preview is a frozen copy of the current combined executable source. It is not hosted Supabase or owner factory data. Release gates remain OFF; gated panels may be unavailable. The earlier corrected Quality component screenshots remain available at C:/Users/Temp/AppData/Local/Temp/FactoryLean-Phase28-Quality-cf8784b1/screens/. They are fixture evidence, not enabled database behavior.

Checklist:
1. Review Planning lanes, short-job bands/captions, compact lists, warnings and dialogs. Reproduce/review the documented open-ended-conflict exception before accepting native drag/drop.
2. Review dedicated Recording picker and original-open-shift completed-work explanation; recent records and History/back navigation.
3. Review Floor toolbar, delayed/animation controls and machine-action presentation without changing physical states unnecessarily.
4. Review Warehouse receiving, inventory/stock-movement details, quantity-only dispatch and material custody confirmations.
5. Review Sales Draft/Confirm hierarchy and availability preview.
6. Review History filters/details, Settings, sidebar parents/chevrons and EN/AR mobile behavior.
7. Review the corrected compact Quality form visually; do not reopen the approved calculation rule.
8. Complete native drag/drop, edge autoscroll, exhaustive contextual restoration and any necessary gated persistent-flow acceptance in a separately authorized test scope.

The app, adapter and database are intentionally retained solely for this owner review. Stop only these services with evidence-directory/stop-review.ps1 when finished. No worker is running. Snapshot/evidence retained.

## H. Git and safety

Main remains development at bb0d20e5dd433b896dd319f56e75f0d9eb5d2862. Existing dirty work and index were preserved. The continuation changes documentation only: HANDOFF.md and docs/phase28-frontend-parity.md.

A new **1,308-file post-Quality SHA-256 verified snapshot** was created before documentation changes:
C:/Users/Temp/Documents/FactoryLean-Recovery/post-quality-phase28-85fcca12.

All original donor/recovery sources and prior reports remain untouched. All 153 migration files, the Quality correction and Phase 2.7 Maintenance fixes remain unchanged. Current disposable gates are OFF. No hosted writes, migration application, gate activation, deployment, Simulation, Git commit/push/fetch/reset/stash/branch change or checkpoint occurred.

Final verified inventory: **87 modified tracked / 408 untracked status entries**. The only new untracked entry is this report. Exact file verification is recorded in evidence-directory/final-preservation.json; the Git index is unchanged.

## Final verdict

**FRONTEND CORRECTIONS COMPLETE — ADDITIONAL VERIFICATION REQUIRED.**

The requested reconciliation is complete and no further approved missing frontend change was found. Owner visual acceptance remains pending. Native Planning acceptance cannot be certified because of the confirmed conflict-feedback defect and unsuccessful saved-drop/edge-scroll verification. This does not authorize a checkpoint, release or deployment.
