# Quality simplified interface — 2026-10-21

**LOCAL COMPLETE; product-owner visual approval pending.** No hosted acceptance or deployment is claimed.

## Delivered

- Exactly seven default columns: Date / Shift, Production Order, Product, Production Line, Shift Production Quantity, Rejected Quantity, Scrap Alert. Optional columns have actor/factory/table-scoped preferences and Restore Defaults.
- Single selection, one permission/state-sensitive Actions menu, keyboard support and double-click existing History. Searchable Product/Line/Shift comboboxes; contextual Excel and Print retained.
- Rejection keeps required reasons/Other, Scrap KG/actual override, physical source confirmation, eligible quantity and stock effect visible. Notes and secondary calculations are on demand. Details replaces History rather than nesting dialogs; follow-up forms open only when selected and authorized. Scrap evidence review stays in Lean.

## Quantity and stock contract

Shift Production Quantity sums official corrected effective Good from private.production_reporting_entries for the same factory, production item, Product, executed line, configured unit and effective dated shift occurrence. It excludes WIP and Scrap KG; it is neither accepted stock nor remaining rejection eligibility. No submission-time inference is used. Unknown/ambiguous attribution returns Unavailable rather than an invented total.

Board rows remain individual production-entry/stock receipts. A shift total may repeat across receipts and must not be added across those rows. Rejected Quantity remains the selected receipt's official unreversed rejection total. The caption explains this distinction; physical labels distinguish receipts.

The exact-decimal client limit uses protected source eligibility, never the shift total. The unchanged transactional writer independently rechecks stock, reservations, physical source and permissions. A stale failure refreshes eligibility while retaining the draft/retry identity. No inventory, correction, Lean/Loss writer or activation behavior changed.

## Migration

New forward local migration: 20261021083652_quality_shift_quantity_read.sql. It changes only private.quality_read_before_m3c(uuid,jsonb) and public.quality_read(uuid,jsonb): effective shift/date filtering and protected complete shift-Good metadata. Existing ACL preserved; 344 inherited function definitions unchanged. Local count is 101; disposable required chain is 100 with Export Reader excluded. All previous 100 migration files are preserved byte-for-byte. No remote history verification or deployment performed.

## Actual validation

- 58/58 focused Node checks: Quality view/UI/API/conservation/high Scrap/visual states, shared Details and departmental exports.
- 115 distinct standalone PostgreSQL checks: source stock24, Quality45, release fixes28, new reader13, attribution5. Includes reservations/dispatch conservation, actual Scrap KG, rework/WIP, zero-to-positive correction, permissions/factory isolation, corrected Good and unknown attribution. SQL suites roll back.
- Nine resumed lightweight full-app Edge-browser groups passed; final read-only EN/AR390px visual check passed. No page exceptions or external requests observed. One actual controlled rejection100 Meter with actual40 KG was posted: shift Good remained500, selected-source eligibility475 to375. Additional450 rejected both inline and by HTTP400 qualityUnavailable; SQL reported quality_unavailable. No additional rejection/deduction occurred.
- Preferences/reload/default reset, History/details, reason management/protected Other and contextual Excel/Print HTML200 passed. Corrective production correctly stays hidden for the browser fixture's zero shortage; its deferred form is separately component-tested with eligible shortage. No corrective production was fabricated.
- TypeScript and final isolated optimized production build passed. No full platform regression campaign.

Evidence: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Quality-UX-uWDldg. Initial harness-only failures were corrected (numeric JSON fixture, unique reason, payload/locator/navigation assumptions); successful writes were not repeated. Tests use original SQL behind a localhost protocol adapter, not hosted Supabase Auth/PostgREST certification. Native PDF, real touch/screen-reader and product-owner approval remain separate.

## Files in this task

- src/features/Quality.tsx
- src/features/quality-v2.css
- src/utils/quality-view.mjs
- src/locales/en.json
- src/locales/ar.json
- supabase/migrations/20261021083652_quality_shift_quantity_read.sql
- tests/quality-view.test.mjs
- tests/quality-ui.test.mjs
- tests/quality/quality-control.test.sql (one obsolete numeric-string fixture corrected)
- tests/production-recording-full-app/backend.mjs (local Quality command adapter allowlist only)
- tests/quality-ux/run-local.mjs
- tests/quality-ux/seed.sql
- tests/quality-ux/reader.sql
- tests/quality-ux/attribution.sql
- tests/quality-ux/browser.mjs
- docs/quality-ux-v1.md
- HANDOFF.md

## Preview and preservation

http://127.0.0.1:4207/ — open Quality through the existing Menu. The retained localhost-only application/adapter/database remain running on4207/4291/55476. Runtime restart may require normal local sign-in using existing local credentials; none were reset. Only this forward read migration and five application files were refreshed in the isolated copy. Before/after operational, permission, membership and gate digests matched; completed-work recording remains FALSE/schema0. Legacy unknown attribution or unidentified stock stays unavailable/ineligible as required.

Disposable test processes4212/4294/55480 were stopped; evidence/data retained outside Git. The retained preview cluster performed standard crash recovery after its prior interruption, without reset or repair.

Development branch/HEAD, main, index, Design System, Export Reader and unrelated work preserved. No hosted access, activation, deployment, commit or push. Product differentiators reviewed: this presentation/read correctness change adds no new competitive claim; document unchanged. Stop for visual approval; no next rollout started.
