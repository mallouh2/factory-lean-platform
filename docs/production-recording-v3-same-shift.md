# Production Recording V3 — reporting after execution completion

31 October 2026: the shared form now also opens from Factory Floor End Production, with gross recording totals and UUID-safe recording-then-finish recovery. Ordinary eligible completed-work recording and all shift deadlines below remain unchanged; End is not offered again. See [completion UX verification](production-recording-completion-ux.md). Closed-shift activation remains FALSE.

27 October 2026. **COMPLETE / LOCAL VERIFIED.** Supersedes the older completed-work gate policy only for ordinary reporting in the still-open authoritative shift. Closed-shift reporting remains disabled. No hosted verification, release or activation occurred.

## Cause and correction

Request PO-0000031 contains item PO-0000032 (`12997086-8586-4aa7-8a28-d21d2b8e9bca`). Its legitimate execution finished at10:48:57UTC inside the08:56:52–12:56:52UTC occurrence, with no recorded output. The reader returned eligible execution but `can_record:false / RECORDING_DISABLED`; protected SQL rejected it and the form disabled Save. All completed executions were classified as gated `LATE_ORDINARY`. This was not a permission, adapter or timezone failure.

Forward `20261027111000_production_same_shift_completion_v3.sql` replaces three existing definitions:

- `private.recording_v3_context`: admits completed execution through the current open occurrence and existing execution, line, permissions, context, declaration and deadline checks. Retains gate-row-before-item lock ordering and server time. Does not reopen execution, change timestamps or activation rows.
- `private.production_recording_eligibility`: binds the context fingerprint to item entry count as well as existing state. Even zero-Good Scrap/unfinished declarations invalidate a stale different-UUID submission. Exact same-UUID receipt recovery precedes admission. Explicit refreshed additional declarations retain existing cumulative semantics.
- `public.production_shift_work`: publishes permission-aware `same_shift_recording_available` separately from unchanged late-mode capability. Cursor context discriminator changes to invalidate pre-policy cursors; shared execution/occurrence logic remains authoritative.

The internal receipt kind remains `LATE_ORDINARY` for compatibility, without authorizing a closed shift. Existing final clock/deadline validation rolls back a transaction that crosses shift end while waiting for locks. Recovery of an already committed receipt after shift end creates no additional output.

Parser and `canRecordWork` consume the additive protected capability, failing closed for invalid/missing eligibility. One EN/AR explanation says execution is complete but reporting remains allowed until shift end. API forwarding, source genealogy, input restrictions, units, measured Scrap KG, Quality and inventory engines are reused. No new workflow/button/approval.

## Changed files

- `supabase/migrations/20261027111000_production_same_shift_completion_v3.sql`
- `src/utils/production-recording-intent.mjs`, `src/utils/production-shift-work.mjs`
- `src/features/ProductionRecordingV3.tsx`, `src/locales/en.json`, `src/locales/ar.json`
- `tests/production-same-shift.test.mjs`
- `tests/production-same-shift/{prepare-local.ps1,before.sql,integration.sql,timezone.sql,concurrency.mjs,browser.mjs}`
- This report, activation-readiness cross-reference and `HANDOFF.md`.

## Verified evidence

Independently verified disposable localhost targets only: separate SQL55497 and retained preview PostgreSQL55496/Auth-Data4304/Next.js4222. Existing portable PostgreSQL reused; no installation or hosted access.

- **91/91 focused Node tests PASS:** same-shift capability/parser/UI, shift-work, late-recording and shift windows.
- **20 positive SQL assertions PASS**, plus eight expected rejections including the before-migration failure. Covers after-shift/never-started work, stale context including zero-Good output, changed same-UUID intent, restricted/foreign-factory actors, active recording, unchanged execution timestamps, source occurrence, Scrap KG, no premature stock credit and protected Quality visibility.
- **Three real concurrency groups PASS:** simultaneous same UUID gives one entry/replay; different UUIDs with the same context give one entry/stale rejection; writer waiting beyond actual shift end creates no entry. No mocked clock or extended shift.
- Asia/Qatar factory-local attribution and exact half-open shift-end boundary PASS.
- TypeScript and isolated optimized Webpack production build PASS; matching build now serves4222. Other previews and3000 untouched.
- Actual owner browser login and protected workflow PASS: separate **PO-0000033 / PO-0000034**, **Same-shift reporting QA**, normally planned/started/finished, then Save HTTP200. Exactly one entry `c13dcf06-b966-4806-866e-90f55c572cf0`: **2 Meter finished,1 Meter unfinished,0.1 KG measured Scrap**. Quality output `bbd41910-1771-4073-b4f9-c42b615ef34c` shows source/groups and “Inspection required”, `quality:null`. Zero Quality/RECEIPT events and zero finished stock movements. STOPPED before inspection approval/receiving.
- Original PO32/request rows exactly match initial evidence; zero entries. Protected reader and EN/AR RTL form allow reporting while the original shift remains open. Browser harness label/panel selectors corrected; initial invalid machine payload rejected without mutation, then valid configuration succeeded. Saved committed operations were reused rather than repeated. Final browser run:zero page exceptions.

Standalone PostgreSQL and local authentication/protocol adapter evidence is not hosted GoTrue/PostgREST acceptance. Shipped manufactured-output capability and completed-shift late gate remain FALSE/schema0; pre-existing disposable manufactured predicate simulation unchanged.

## Owner continuation

Preview: http://127.0.0.1:4222/. Existing account `PlanningV3@local.invalid`; unchanged credentials in owner-restricted `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.

Factory Floor → Record Production → PO-0000031 / PO-0000032 → actual finished/unfinished quantities and Scrap KG → Save production → Done. Then Quality → select its production record → Actions → Inspect / amend. Original occurrence closes **27 October at12:56:52UTC /15:56:52Qatar**. Do not extend it. Separate already-recorded PO34 remains available for manual Quality inspection if the original window expires.

Evidence is in retained preview root `same-shift-recording/`: original rows, before/after readers/UI, browser responses, Quality screenshot, final stock/gate assertions, TypeScript/build logs and preservation manifest. SQL results remain in `C:\Users\Temp\AppData\Local\Temp\FactoryLean-SameShift-SQL-3c588e5927f449708aafd3d71a1b984b`; temporary SQL server stopped after validation; data removal was blocked by automatic approval review (blocked by policy), so data and results are retained.

113 local migrations; all112 previous migration bytes, Export Reader, Design System, Planning and owner-adapter work preserved. Product differentiators reviewed:bounded correction adds no competitive claim. No remote-alignment claim, hosted access, activation, deployment or Git write. STOP after this fix.
