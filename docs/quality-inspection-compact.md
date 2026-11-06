# Compact Quality inspection — 1 November 2026

**6 November 2026 owner clarification:** retain the compact layout, but Accepted Finished is a read-only result: **Actual Total − Irrecoverably Rejected − Recoverable Unfinished**. Quality edits Actual Total, Rejected and Unfinished with existing reason, weight, group and conservation validation. This business rule supersedes the earlier editable-Finished/computed-Rejected preview. Matching-record quick approval and original technician/audit evidence remain unchanged. Final visual acceptance is separate from approval of this calculation rule.


**COMPLETE / LOCAL VERIFIED; STOP for owner visual approval.** Focused modal redesign; protected Quality, Production and Warehouse writers are unchanged.

## Design and operational flow

The modal now reads as one inspection form:

1. Product first, then explicitly labelled **Execution**, **Request**, and line. RequestPO-0000021 and executionPO-0000022 are no longer two unexplained references.
2. Three compact recorded cards: finished, unfinished and Production ScrapKG. Values come from the protected production-record source/groups, including valid production corrections, never the inspector's new classifications. Unknown Scrap remains unknown.
3. Editable **Rejected Quantity** and **Unfinished Quantity**, with read-only **Accepted Finished Quantity** calculated from the verified actual total. Desktop uses three columns; narrow screens keep the two classification inputs together with computed Finished on its own row. The existing Actual Total correction remains above them.
4. Unfinished group details appear only for positive unfinished output or an incomplete group draft. Each compact card contains quantity, required remaining-operation checkboxes, optional note and Remove. Add Unfinished Group stays inside that section.
5. One **Actual Rejected Weight (kg)** input appears only for positive rejection. The Recalculate Suggested Weight action and separate estimated-weight presentation are gone.
6. The existing required manual-inspection reason, optional linked follow-up and a persistent **Cancel / Save Quality Decision** footer. Read-only inspection history and the existing protected advanced-total correction are secondary, collapsed controls.

Existing Approve as Recorded remains the faster classification-preserving confirmation. A manual inspection still requires the meaningful reason required by the protected command; its textarea is compact. Follow-up notes appear only when checked. Actual validation, pending retry state and required evidence remain visible. The existing advanced total-correction path was retained rather than silently deleting a protected capability.

All Production Details, Receiving, Completion/Replacement and Original Order shortcut rows are removed from the inspection modal. Its history contains read-only date/revision/reason evidence. Full audit/source relationships and authorized drill-through remain in existing record/history views; `OutputDetails` and its underlying protected routes were not deleted.

The brief [Tulip Frontline QMS comparison](https://support.tulip.co/docs/frontline-qms-1), reviewed1November, supports a bounded selected-unit/results/evidence flow. This adaptation keeps Factory Lean's existing quantity and follow-up contracts; it does not claim competitor-wide superiority or measured training savings. Existing tokens/components and UI/UX/frontend review skills were used. Product Differentiators was reviewed; no material competitive capability changed.

## Protected quantity and group behavior

Rejected remains exact-decimal `T - A - U`. For zero/one unfinished group, editing the unfinished total creates/resizes that group while retaining its existing operation identity. Zero removes the draft groups. With multiple groups, changing the total never silently redistributes their quantities: Save remains blocked until explicit group quantities match the entered total. Group edits/removal update a matching total; incomplete/new groups remain visible and invalid until completed. Required operations, whole-piece/precision rules, separately tracked finished groups and backend reconciliation protections remain authoritative.

Operations are never merged by display name. Labels use their exact routing-step ID, available real routing position and machine name. Missing sequence is not inferred from array order. When otherwise indistinguishable, an explicit operation ID distinguishes them. Local duplicate Printing steps1/2 on one printer were exercised; both remained separate and could be allocated to different unfinished groups. Missing routing context may therefore expose a technical ID as the honest fallback.

Suggested KG uses only the existing authoritative matching-unit positive Product weight. Untouched weight follows rejected quantity automatically. Manual measurements stay intact; later quantity changes require explicit measurement review or editing before Save. Zero rejection submits zero rejectedKG. Production Scrap is separate and never rewritten or counted as Quality rejection. No conversion means measured evidence is required under the existing validation.

Existing per-record follow-up, pinned expected revision, immutable UUID body/recovery, factory-scoped effective permissions and quantity-independent NEEDS_ACTION→IN_PROGRESS→RESOLVED lifecycle remain. No activation or new business writer/stock ledger was introduced.

## Fresh acceptance evidence

Tests used independently verified disposable PostgreSQL55500, Auth/Data adapter4322 and app4238. Existing accounts/grants were reused. Six independent Sales-linked98m fixtures were created through the existing protected Production workflow, each with0.5KG Production Scrap. A second genuine routing step used the same Printing work center to test duplicate labels; no existing resource capability/topology was changed.

| Scenario | Accepted | Unfinished | Rejected | Protected result |
|---|---:|---:|---:|---|
| Entire output | 98 | 0 | 0 | 200; no unfinished/weight section |
| Partial rejection, measured override | 96 | 0 | 2 | 200; manual1.25KG retained after review |
| Unfinished + rejected | 94 | 1 | 3 | 200; selected real remaining operation, suggested1.5KG |
| Unchanged output + follow-up | 98 | 0 | 0 | 200; one linked NEEDS_ACTION finding |
| Two unfinished groups | 94 | 0.6 +0.4 | 3 | 200; distinct operation IDs and groups preserved |

- Actual manual1.25KG was not overwritten when accepted quantity changed. With a valid reason already entered, Save was disabled until review. No recalculation button exists.
- Fresh read-only PostgreSQL assertions verify all five findings conserve98; one original production entry per fixture; Production Scrap0.5KG unchanged; no automatic new Production Order for the fixture products; the two unfinished groups remain distinct.
- All stock was0 after Quality classification. Concurrent original-UUID Quality replays return200/200 and retain one follow-up FINDING. Opening the real Production follow-up leaves NEEDS_ACTION. With ordinary follow-up still open, concurrent same-UUID physical1m receipts return200/200 and credit0→1m exactly once.
- Two distinct stale-UUID attempts with an old expected revision return409. Restricted and known foreign-factory Quality writes return403, with follow-up count unchanged. Existing invalid-conservation/operation/unit regressions pass; no SQL checks were weakened.
- **22 focused Node tests PASS**, covering labels/fallback identity, multiple groups, exact conservation, invalid/whole-unit states and affected manufactured-output utilities. Saved-result PostgreSQL assertions PASS. TypeScript and exact-source isolated optimized builds PASS. No unrelated broad suite or security audit.
- EN1440/768/390, AR1440/768/390, long names, keyboard focus, labelled checkboxes and contained body/footer inspected. Desktop ordinary inspection fits with quantities and Save visible. Positive unfinished output exposes only its compact group section. English and Arabic drafts/focus survive two real30s refresh cycles. The final identity header explicitly stacks product before references, including long Arabic names.
- Original owner4222 normal-login read-only modal smoke PASS; no operational POST, no browser error. Original118 baseline table digests unchanged. No owner inspection was saved.

These are local adapter + real PostgreSQL/RLS tests, not hosted Supabase integration. Existing exceptional source reconciliation and advanced correction limits remain. Shipped manufactured-output and closed-shift late-recording gates both remainFALSE; inherited disposable test predicate is unchanged. User visual approval and any future hosted acceptance remain separate.

## Before/after and review

Preview **http://127.0.0.1:4222/?view=quality**, matching `quality-compact-app` under the existing owner runtime. Existing PlanningV3@local.invalid credentials:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.

Before: same owner runtime `quality-v2-final/owner-inspection.png`.
After: `quality-compact/owner-inspection.png`.
QA evidence root:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Production-End-65b76ac01c494ac6b7b57f99886b9f6f\quality-compact`.
Screenshots `case1-1440.png`/`case1-390.png` show the ordinary form; `case3-1440.png`/`case3-390.png` show unfinished work. Final Arabic screenshots `final-ar-1440.png`, `final-ar-768.png`, `final-ar-390.png`. `browser.json`, `extra.json`, `visual.json`, `conservation.txt` contain HTTP/UUID/fixture results. Parent `quality-compact-fixtures.json` retains all test IDs. Successful write scenarios must not be blindly replayed.

## Exact incremental manifest

- Modified `src/features/ManufacturedOutput.tsx`, `src/features/quality-v2.css`, `docs/quality-inspection-v2-final.md`, `HANDOFF.md`.
- New `src/features/QualityUnfinishedGroups.tsx`, `src/utils/quality-operation-labels.mjs`, `tests/quality-compact.test.mjs`, `tests/quality-compact/browser.mjs`, `extra.mjs`, `owner.mjs`, `visual.mjs`, `conservation.sql`, and this report.

**13 files, no migration/dependency/source-environment change.** All136 pre-task migration hashes, prior dirty work, Design System, Export Reader, Production Recording, Planning/Gantt, shifts, navigation and existing receipt rules are preserved. development HEAD`bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, index empty. No hosted operations, deployment, Git writes, localhost3000 or unrelated-preview changes. STOP for owner visual review.
