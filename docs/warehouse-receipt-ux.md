# Inspected-production receipt UX — 1 November 2026

## Warehouse V2 update — current local preview

The later V2 implementation supersedes the three-card/free-text-location presentation described below. Eligible finished production is first/default; deliberate category selections and independent drafts survive refresh. One **Available to Receive / الكمية المتاحة للاستلام** summary uses the exact protected source/group entitlement. Release and prior-receipt totals/history are secondary Details. Quantity Received Now defaults to available and remains editable; a new compatible factory-scoped **Receiving warehouse / المستودع المستلم** selector replaces free text. Physical confirmation remains required. Finished/unfinished use green/teal; held/invalid states remain visible. After a known commit, another receipt waits for its revision read-back; original-UUID recovery remains independent of archived warehouse status.

New factory warehouse definitions and immutable receipt provenance are locally verified. Existing external/opening stock forms also select a compatible destination and reuse their existing ledger, without Quality inspection. Pooled stock, historical unassigned receipts and automatic Purchasing paths remain intact. No per-warehouse current balances are claimed. Full current report,27-file manifest,tests/screenshots and compatibility boundaries: [Warehouse V2](warehouse-management-v2.md). Earlier sections below retain the preceding frontend-only task's historical evidence.

**COMPLETE / LOCAL VERIFIED; STOP for owner review.** Frontend-only cleanup of the inspected-production receipt screen.

## Screen and wording

The request drawer now opens as **Receive inspected production / استلام إنتاج مفحوص**, with one active receipt category at a time. Product and authoritative Production Order reference are grouped with a clear Finished production / Stored unfinished production badge. Multiple eligible categories use explicit selection buttons; separate category forms remain mounted but hidden, preserving independent quantity/location/note/confirmation drafts when switching and refreshing. A successful partial receipt retains that selected category rather than silently moving to another one.

Three compact, typed cards show **Released quantity / Previously received / Remaining to receive** from the protected receiving reader. Arabic uses **الكمية المصرّح بها / المستلم سابقاً / المتبقي للاستلام**. The ordinary inputs are **Quantity received now / الكمية المستلمة الآن** and **Storage location / موقع التخزين**. Receipt note is optional and collapsed. Only unfinished production shows its remaining operations and applicable identification/restriction context, as a secondary line.

The ambiguous square was **not removed**: it represents required physical-receipt confirmation. It is now one aligned, clickable checkbox/label: **أؤكد أن هذه الكمية استُلِمت فعلياً** / **I confirm this quantity was physically received**. Confirm remains disabled without a valid positive eligible quantity, location and explicit confirmation. No quantity is automatically assumed received.

One clear Confirm receipt / Cancel footer follows the form. The receipt-only sheet fits its content with a bounded scrolling body; it does not leave a full-height blank area below the actions. Its footer stays in normal flow so it cannot cover the physical-confirmation control. Other request drawers and exceptional reconciliation retain their existing layouts. The selected-request duplicate product heading was removed. Repeated prose, stacked finished/unfinished forms and the always-expanded note were replaced by the focused structure; critical holds, unknown-result recovery and authorized exception handling remain visible.

The same category form is reused for the existing secondary receipt modal. Request-host busy state now tracks the production receipt so close/cancel cannot interrupt a live submission. No permission is inferred from presentation. Current finished receipt, stored-unfinished receipt and exceptional physical reconciliation remain separate protected operations.

## Unchanged protected behavior

`receive_manufactured_output` and its existing factory authorization, Quality release, exact quantities/units, source groups, holds, revisions, ledger effects and atomic UUID receipts are unchanged. The existing session-stored immutable command body is retained before POST. An unknown result blocks another receipt; retry sends the original body/UUID, including its exact category. No new API, backend, schema, migration, ledger, automatic stock credit or combined multi-category transaction exists. Purchased-material and opening-stock flows are untouched.

Location/note limits remain200/2000 characters. The component's disabled state now reflects those same existing parent checks. Invalid quantity guidance is next to the form. The old per-category behavior is preserved: successful receipt clears quantity/confirmation, while useful location/note drafts remain. Production, Quality, Sales demand and original recorded Scrap are not rewritten by receiving.

## Verification

- **17 focused Node tests PASS**: exact partial/maximum receiving, Arabic numeric input, unit/zero/negative/excess rejection, exact-target API context/auth and Warehouse request presentation/hold boundaries. TypeScript and optimized isolated builds PASS. React/frontend review and whitespace checks PASS. No unrelated broad platform suite.
- Mutations used existing disposable QA factory/source **qcompact3** on independently checked PostgreSQL55500/Auth4322/app4238. Existing source Quality release was94m finished +1m unfinished; no new account, permission, release or fixture source was invented.
- Real UI selected finished output, entered2m/location, verified Confirm disabled before physical confirmation, then switched to unfinished, entered0.4m/location and switched back. Finished2m and its confirmation persisted. Category drafts also survived two real30s refresh cycles with field focus retained.
- The protected finished receipt committed200; a test-injected503 simulated a lost/unconfirmed reply. The first response listener incorrectly observed that synthetic response while awaiting retry. Recovery continued from the captured immutable UUID, without creating another receipt. Authenticated UI retry returned200. Read-only SQL confirms **one2m event**, finished stock2m, and summary **94 released /2 received /92 remaining**.
- Separate unfinished UI receipt returned200. Summary is **1 released /0.4 received /0.6 remaining**. SQL confirms exactly two receipt events total, with quantities2 and0.4 and distinct receipt UUIDs. These are separate category transactions, not one atomic combined receipt; finished stock is2, not2.4.
- Final exact-source screenshots inspected for both categories at1440,768,390 and Arabic390. No page horizontal overflow. Finished form has no unfinished-operation line. Explicit checkbox alignment and conditional note were verified. Final unfinished mobile sheet is760px tall within a1000px viewport, at top12/bottom772; no giant trailing white drawer area. All required controls remain reachable through the bounded body.
- Original owner4222 normal-login drawer before/after checks PASS with zero operational POSTs. All118 baseline table digests, credentials, previous136 migration hashes and unrelated dirty files remain unchanged. Both shipped activation gates stayFALSE; the inherited disposable manufactured-output test predicate is unchanged.

This is existing localhost Auth/Data adapter + real protected PostgreSQL evidence, not hosted Supabase acceptance. No full security audit or deployment-readiness claim is made. User visual approval remains pending.

## Exact files changed

Modified:

- `src/features/ManufacturedReceiving.tsx` — category layout, precise labels, per-category draft retention and existing command reuse.
- `src/features/WarehouseRequests.tsx` — receipt-specific title/duplicate-heading removal, Cancel and busy-close coordination.
- `src/features/warehouse-v1.css` — scoped card/form/checkbox/category/action styling and content-height receipt sheet.
- `docs/warehouse-final-cleanup.md`, `HANDOFF.md` — current-state pointers.

New:

- `tests/receipt-ux/browser.mjs`
- `tests/receipt-ux/recover.mjs`
- `tests/receipt-ux/owner.mjs`
- `tests/receipt-ux/visual.mjs`
- `docs/warehouse-receipt-ux.md`

**10 files. No migration, dependency or source environment change.** Successful write tests must not be blindly rerun; the captured original receipt UUID and evidence are retained for recovery.

## Preview and evidence

**http://127.0.0.1:4222/?view=warehouse** → **Warehouse Requests** → select an inspected-production receipt.
Existing owner **PlanningV3@local.invalid**, unchanged local credentials:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.
Matching isolated build is `receipt-ux-app` in that existing runtime.

Owner evidence: same runtime `/receipt-ux/before-owner.png`, `after-owner.png`, JSON smoke/baseline/preservation reports. QA evidence:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Production-End-65b76ac01c494ac6b7b57f99886b9f6f\receipt-ux`.
`browser.json`, `visual.json`, `conservation.json` retain source/UUID/results. Final images: `final-Finished-1440.png`, `final-Finished-ar-390.png`, `final-Stored-1440.png`, `final-Stored-ar-390.png`.

No hosted TESTING/DEV/Simulation/Production access, deployment, Git writes, localhost3000 or unrelated-preview operations. development HEAD`bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, index empty. Owner Warehouse/Production/Quality data and all prior work preserved. STOP for review.
