# Quality Inspection V2 final simplification — 1 November 2026

Later owner-directed modal refinement: [compact inspection report](quality-inspection-compact.md). It supersedes this page's modal layout, group editor, recalculation-button and Details descriptions; the protected calculations, follow-up and lifecycle evidence below remain applicable. The inspection now has an editable unfinished total, compact explicit groups, no recalculation action and read-only history without cross-department shortcuts.

**COMPLETE / LOCAL VERIFIED. Owner manual approval pending.** No hosted release or activation.

## Workflow and UI

The existing pending production-record selection remains the only daily queue. Single click selects; double click no longer opens the obsolete Quality Decision modal. The notification/history Details path and protected drill-through operations remain available in their existing contexts. The main page no longer contains a global follow-up form.

Selected-record and inspection summaries show the authoritative recorded finished and unfinished group totals in their production unit, plus **Production Scrap** from the protected source snapshot in KG. Missing Scrap evidence displays unknown, never a fabricated zero. Positive recorded Startup Scrap or discarded input is also displayed separately. These are recording classifications, not accepted stock. Existing groups and remaining-operation identities are retained.

**Approve as Recorded** opens a concise confirmation in the same inspection interface, showing recorded classifications and the separate Warehouse-receipt outcome. It preserves all recorded groups and Scrap; quantities are not editable in this fast path. Optional per-record follow-up is available before confirmation. **Modify inspection** opens **Production Quality Inspection / فحص جودة الإنتاج**, or **Edit Quality Inspection / تعديل فحص الجودة** for an existing decision.

The inspection order is identity → original quantities → accepted finished input → unfinished groups with required remaining operations → computed rejection → rejected-weight evidence → reason → optional Production follow-up → stable Save footer. Supporting audit/drill-through detail is collapsed. Textareas are compact and resizable; the footer is outside the scrolling body. Checkbox and label form one aligned clickable row in EN/AR and at390px.

## Quantity and weight rules

Normal inspection derives `R = T - A - U` using exact decimal strings. Negative/excess/invalid and fractional-piece results fail closed. The existing `inspectionDraft` still constructs source-bound groups, validates operations, preserves separately tracked finished groups and rejects unsupported redistribution. No independent normal rejection input remains. Existing advanced actual-total correction remains behind Advanced quantity correction; its existing backend authorization, reconciliation and conservation restrictions are unchanged.

Rejected weight uses one editable **Actual Weight of Rejected Quantity (kg)** input, with the requested natural Arabic label. It is initialized/synchronized only when the authoritative configured Product stock unit matches the inspected unit and its weight is positive. No valid conversion means no invented estimate: actual positive measured KG is required. Editing the weight marks it manual. Later rejection changes preserve the number but block Save until the inspector confirms that measurement or recalculates the suggestion. Zero rejection forces zero rejected KG and removes rejection-only weight fields. Production Scrap is never included in this calculation or rewritten by it.

Follow-up is attached to the selected inspection's existing output UUID/item/entry and protected Quality revision. It requires a Quality Note and Requested Production Action only when selected. Existing `manufactured_output_command` atomically stores the decision and follow-up with the same retained immutable retry body/UUID. Unchanged accepted output can create **NEEDS_ACTION** without rejection, replacement, WIP or Sales-demand changes. Opening it does not resolve it; ordinary follow-up is not a physical stock hold. Actual holds/reconciliation still apply independently. Inspection opening now pins the expected revision, so refresh cannot silently apply an old draft against a newly revised decision.

No database function, permission, receipt rule, stock engine or migration changed. This is a refinement of existing capability. Product Differentiators was reviewed and left unchanged; no new competitive or measured-training claim is made.

## Fresh local verification

Independent target checks used disposable PostgreSQL55500 / Auth4322 / app4238, existing synthetic accounts and protected Production commands. Six new source records contain98 total units and0.5KG separately recorded Production Scrap; a seventh long-name record is visual/invalid-submission evidence. One fixture setup failed numeric-payload validation and rolled back in full before corrected numeric fixture creation. No partial fixture was reused or historical data repaired.

| Fixture | Accepted finished | Unfinished | Rejected | Actual Quality rejected KG | Protected save |
|---|---:|---:|---:|---:|---|
| qfinal1 | 97 | 0 | 1 | 0.5 | 200 |
| qfinal2 | 96 | 0 | 2 | 1 | 200 |
| qfinal3 | 95 | 1 | 2 | 1 | 200 |
| qfinal4 | 98 | 0 | 0 | 0 | 200 |
| qfinal5, unchanged + follow-up | 98 | 0 | 0 | 0 | 200 |
| qfinal6, approve original split | 97 | 1 | 0 | 0 | 200 |

- Real UI selection and double click: no obsolete dialog. No global follow-up form; correct confirmation/context and recorded0.5KG Scrap summary.
- Weight0.5 follows rejection1→2 as1KG. Manual0.75 is preserved after quantity change, review warning/disabled Save appears, recalculation restores the configured suggestion. Zero rejection has zero weight. Exact precision/invalid/whole-piece Node cases pass.
- Read-only SQL assertions verify all six saved findings sum to98, original production entry count remains one per fixture, Production Scrap stays0.5KG, target98 remains unchanged, and original split97+1 is preserved on fast approval. All finished stock was0 after Quality approval.
- qfinal5 follow-up is linked and NEEDS_ACTION. Two concurrent original-UUID Quality retries return200/200, leaving one FINDING. Opening the real Production Quality Updates drawer leaves NEEDS_ACTION and event count unchanged.
- With that ordinary follow-up still open, two concurrent identical-UUID physical1m receipts return200/200 and credit stock **0→1m exactly once**. No unapproved quantities were credited. Existing rejection/unfinished/source contracts were reused; no automatic completion/replacement command was invoked.
- Actual invalid99-of98 submission returns **422 / output_conservation / REJECTED**, with unchanged revision and no finding. Restricted and known foreign-factory Quality writes return403; follow-up event count stays one.
- **18 focused Node tests PASS**, including the new accepted→rejected examples, exact fractions, invalid quantities, existing inspection/group protection and affected manufactured-output utilities. New guarded read-only PostgreSQL conservation assertions PASS. TypeScript and isolated optimized builds PASS. No unrelated broad suite/audit.
- Authenticated EN1440/tablet768/mobile390 and long-name AR390 screenshots inspected. Sticky footer and body scrolling allow access to required fields. Follow-up control is aligned; quantity/weight/reason and follow-up drafts remain stable through two actual30s refresh cycles in English and Arabic; textarea focus remains. Browser page-error lists empty.
- A test locator failed after filling a wrapped textarea label; no business POST had occurred. It was corrected to the actual textarea. Another test encountered the existing navigation hover panel after language switching; normal pointer movement/Escape closed it, without changing navigation code. Final browser runs PASS.
- Original owner app4222 normal-login read-only Quality/inspection smoke PASS, zero operational POSTs. All118 owner baseline table digests remain unchanged. Owner pending98m inspection was opened only for screenshot and never saved.

This is real protected PostgreSQL/RLS with the existing localhost Auth/Data adapter, not hosted Supabase GoTrue/PostgREST acceptance. The inherited disposable manufactured-path test predicate remains unchanged; both shipped activation gates stayFALSE. Existing exceptional reconciliation, source-group restrictions and unsupported-conversion measured-evidence requirements remain. No historical-shift approval feature was implemented.

## Exact incremental manifest

Modified:

- `src/features/ManufacturedOutput.tsx`
- `src/features/quality-v2.css`
- `src/utils/quality-inspection.mjs`
- `docs/production-quality-corrective-actions.md`
- `HANDOFF.md`

New:

- `tests/quality-final.test.mjs`
- `tests/quality-final/browser.mjs`
- `tests/quality-final/extra.mjs`
- `tests/quality-final/owner.mjs`
- `tests/quality-final/invalid.mjs`
- `tests/quality-final/conservation.sql`
- `docs/quality-inspection-v2-final.md`

No new migration/dependency or source environment configuration. All136 pre-task migration hashes, Design System, Export Reader and unrelated dirty work preserved. Existing Production/Planning/shift/navigation code was not changed.

## Preview and evidence

**http://127.0.0.1:4222/?view=quality** — matching `quality-final-app`, existing owner `PlanningV3@local.invalid`, unchanged credentials file:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.

Owner evidence: same runtime root `/quality-v2-final/owner-readonly.json`, `owner-inspection.png`, `owner-quality.png`, file/table baseline and preservation report. QA evidence root:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Production-End-65b76ac01c494ac6b7b57f99886b9f6f\quality-v2-final`.
`browser.json`, `extra.json`, `invalid.json`, `sql-before-receipt.json`, `conservation-result.txt` hold HTTP/source IDs and results. Screenshots: `inspection-1440.png`, `inspection-768.png`, `inspection-390.png`, `inspection-ar-390.png`, `followup-open.png`. Fixture identifiers remain in parent `quality-final-fixtures.json`. These successful write scenarios must not be blindly rerun.

Both owner4222/4304/55496 and isolated QA4238/4322/55500 remain local. development HEAD`bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, index empty. No hosted access, deployment, Git writes, localhost3000 or unrelated-preview changes. STOP for owner manual review.


## 2 November 2026 — actual total exposed in normal inspection
Original technician total and editable Quality-verified actual total are both visible. Existing protected QUALITY total input is reused; the separately approved progress/make-up fix adds forward20261102140000. Rejected = verified total minus accepted minus unfinished, with actual KG separate. Rollback tests distinguish60/58/2 from58/58/0 and confirm receiving58 only. The approved measurement shortage is now ordinary unproduced work: active execution restores ordinary remaining; ended execution offers explicit permission-protected linked make-up. No rejection/WIP entitlement or automatic work. Forward20261102140000 preserves raw evidence, progress, lineage, Sales/stock conservation and UUID allocation.45 SQL checks,3 observed races and real active/ended browser paths pass locally. see [consolidated report](e2e-acceptance-consolidated-fixes.md).
