# Table Details and correction approval alert

20 October 2026. **LOCAL COMPLETE; owner review pending.** No Phase4D, hosted operation, migration, activation or Git write.

## Behavior and coverage

One small shared row handler selects on single click and opens an explicitly supplied existing read-only Details destination on double-click. It ignores nested buttons, links, labels, inputs, editable content and ARIA controls. Touch taps retain selection and never open Details through synthesized double-click. Enter opens Details and Space selects where the table uses the shared keyboard handler; History retains its existing arrow/selection keyboard model and Actions menu. No handler invokes a business command.

| Table | Existing destination | Notes |
| --- | --- | --- |
| Production History, including responsive cards | History Details | Existing seven columns, filters, column preferences, pagination, exports and Actions preserved. |
| Corrections & Approvals | Request Details | Approval/rejection still requires an explicit authorized command. |
| Quality production | Rejection history | Requires existing Quality History access; rejection button remains independent. |
| Purchasing, My Requests, Warehouse stock purchases | Existing purchase Details | Same opener as the existing Open button; protected reader unchanged. |
| Lean problems with a persisted problem ID | Existing Lean problem detail | Double-click bypasses no authorization and never calls the old Open helper that may create a problem. Occurrence-only rows keep their explicit existing action. |

Exceptions are deliberate: Planning/Gantt, Production Requests, Maintenance and Sales use cards/buttons/timelines, not selectable data-table rows. They keep existing navigation and touch behavior. Warehouse catalogue has contextual unit-breakdown/WIP/configuration actions but no general record Details view; none is invented. Configuration, employee/permission matrices, Lean standards, report/analysis tables and Audit History have editing, aggregates or separate inline old/new disclosures rather than one record Details destination; no unrelated conversion or new screen. Existing legacy action columns are retained rather than redesigning those workflows in this bounded change.

## Pending navigation

Production → Corrections & Approvals shows an amber, token-based accent and explicit localized count plus Pending text only for effective Orders view + approve. Zero, loading, unavailable and failed counts produce normal navigation. The foreground/background pair remains explicit and readable over light/dark surrounding surfaces; it does not rely on color alone. No animation, toggle or continuous polling.

GET `/api/production-corrections?factory=…&pending_count=1` checks confirmed authentication and factory-scoped Orders view + approve before reusing the existing protected `production_correction_read` with PENDING and page_size1. It returns only `{total}`, never request metadata/rows. Existing SQL direct/package grants, scope checks and writers are unchanged; no new database function/migration. Refresh occurs on view entry, snapshot refresh and successful queue decisions. Errors do not invent zero or retain an apparent actionable count. Counts are a snapshot, not a live subscription.

## Actual verification

- **118/118 focused Node tests** across seven Node test files: row/control/touch/keyboard behavior; count authorization, bounded parameters and no metadata disclosure; zero/error/loading/invalid counts and actor/factory identities; existing correction, History and navigation regressions.
- TypeScript PASS. One isolated optimized Next16.3.5 production build PASS with loopback-only build environment. No build replaces the running preview's output.
- One lightweight in-app browser pass, actual local Next routes and original protected SQL: History single selection/double-click and toolbar open the same Details; Corrections double-click opens Details without deciding; Quality double-click opens existing rejection history; EN/AR, RTL and narrow responsive presentation verified. Local owner session retained. No all-site/cross-browser, full dark-theme or physical touch-device acceptance claimed. Purchasing/Lean bindings are typechecked and use the tested shared handler; their populated browser scenarios were not rerun.
- Actual HTTP fixture test signs in through normal local `/api/auth` using existing local accounts. Technician count request403 returns only permissionError; owner200 returns only total. One tagged technician proposal raised pending count1→2. UI rejection of only that proposal lowered badge2→1; pre-existing pending request untouched. Proposal `8eefbaed-f71c-4a52-a5e6-95eaaea76d5f` is REJECTED with no correction ID/applied posting.
- Read-only before/after checks: six production entries, gross Good40.75 Meter, official Scrap2.21 KG, WIP2 Meter; finished on-hand38.25 Meter and reserved0 unchanged by this test. These are current fixture values, not the older Phase4C snapshot. No inventory writer, source identity or permission was changed by this task.

The existing disposable local Auth/Data adapter is not hosted GoTrue/PostgREST evidence. Zero-count/error/permission count presentation is covered in focused tests; the owner's real existing pending request was not resolved merely to force a zero. Export/print workflows were not submitted again. Existing relevant tests and unchanged source retain those behaviors.

## Files

Implementation: `src/components/useTableDetails.tsx`, `src/utils/table-details.mjs`, `src/hooks/useCorrectionPending.ts`, `src/components/FactoryApp.tsx`, `src/app/api/production-corrections/route.ts`, `src/features/ProductionHistory.tsx`, `src/features/ProductionCorrections.tsx`, `src/features/Quality.tsx`, `src/features/Purchasing.tsx`, `src/features/LeanAnalysis.tsx`, `src/features/production-corrections.css`.

Tests: `tests/table-details.test.mjs`, `tests/correction-pending.test.mjs`, `tests/production-corrections.test.mjs`, `tests/table-ux-local-http.mjs`. The HTTP fixture script explicitly creates one pending local proposal for UI rejection; do not rerun unnecessarily.

Documentation: this report, `docs/design/UX_SIMPLICITY_STANDARD.md`, `HANDOFF.md`. Product Differentiators reviewed; no competitive capability claim changed.

Preview: http://127.0.0.1:4207/?view=productionCorrections . Owned4207/4291/55476 remain running. Evidence/build/preservation manifest: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Table-UX-hEgudx`. Existing migration bytes, Design System, Git index/HEAD and unrelated dirty work preserved. No hosted access, deployment, activation, commit or push. Stop for owner review.
