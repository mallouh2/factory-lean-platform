# Quality Control V1 — implementation record

Status: IMPLEMENTED / LOCALLY VERIFIED — 2026-10-10. Supabase service integration, remote deployment and user acceptance remain NEEDS VERIFICATION. No deployment or acceptance is claimed.

**Targeted release follow-up:** QV-01 final-state deferred rework KG validation, QV-02 accepted/shared future projection with replacement de-duplication and preserved Sales commitments, and QV-03 active bilingual reason search/paging with permanent Other are implemented. Final local checks: focused23/full713 Node tests, TypeScript/build, 114 standalone PostgreSQL assertions and8 transaction/concurrency scenarios passed. Current evidence and open deployment gates are at the top of [Quality V1 verification](quality-control-v1-verification.md); the original implementation chronology below is retained. No remote deployment, commit or push.

## Authorized scope and baseline

- Authoritative checkout: development, `3e249c9d222a08ebe1e85c5fd401818821ed77d2`.
- Starting tracked tree is clean. Preserve the untracked canonical `docs/design/FACTORY_LEAN_DESIGN_SYSTEM.md` byte for byte.
- 80 existing local migrations; remote state is historical and will not be queried. The export-reader migration is still pending separate TESTING authorization.
- No Simulation, security workspace, remote database, account, commit or push operation.
- User explicitly approved minimal source tracking with physical source selection on 2026-10-10. Historical pooled stock remains UNATTRIBUTED; no inferred FIFO or historical batch reconstruction.

## Frontend thinking gate

| Question | Decision |
|---|---|
| Project / stage | Active Lean operations product for small factories; preserve the operational application. |
| Users / objects | Quality inspectors and authorized Production/Warehouse people; recorded output, identified source stock, rejection, kg Scrap, reserved WIP. |
| Surface | Compact operational workbench, not a dashboard or marketing surface. |
| Entry / first decision | Quality navigation → select actual production/shift context → choose identifiable available source stock. |
| Information priority | Recorded gross Good, Quality rejected, accepted Good, unit, actual line/shift, eligibility, history and action. |
| Primary task / success | Reject an exact available source quantity atomically, record actual kg or reserved WIP and create one actionable notification. |
| Friction / recovery | Explicit physical-identification and stock-commitment errors; preserve the draft, refresh eligibility and retry with the same command ID. |
| Mobile action | Inspect a compact production row/card and open the same rejection drawer. |
| Foundation / references | Existing native dialogs/drawers, fields, tables, status tokens and CSS. MRPeasy lot-specific rejection/service orders and Fusion Operations waste/rework traceability. |
| Temperament / vocabulary | Restrained industrial SaaS; Good, accepted quantity, Scrap kg, Rework, source label, unavailable. |
| Must not appear | UUIDs, implementation contracts, invented stock attribution, role-based authorization, hero cards or 3D. |
| Risks / verification | Mixed physical stock, stale source allocations, double credit, correction/rework conservation, midnight shifts, EN/AR/RTL. Local transactional SQL, focused Node/component tests, TypeScript, isolated build and offline browser fixtures. |

References: [MRPeasy Quality Control](https://www.mrpeasy.com/resources/user-manual/settings/system/professional-functions/quality-control/), [Fusion Operations Rework](https://help.fusionoperations.autodesk.com/en/articles/5845450-rework-button).

## Implemented bounded extension

1. Extend the existing finished-stock ledger with receipt provenance, physically confirmed source quantities, movement allocations and source-aware reservation allocations. Initialize only an UNATTRIBUTED bucket from current balances; leave historical movements and reservations intact.
2. New manufactured receipts retain the actual entry/item/Product/unit/shift context. Receipt provenance alone does not assert physical traceability. Warehouse must confirm a physically identifiable label and quantity; mixed/unidentified stock is ineligible for source-specific Quality rejection.
3. Guard every finished-stock delta at the existing movement boundary, including Sales dispatch, material issues, stock adjustment and production correction. Existing product balances remain stock truth; source quantities must conserve that balance. Preserve existing full-line dispatch semantics, including partial orders and multi-source picks.
4. Add immutable factory-scoped Quality reasons/rejections, actual kg snapshots/override evidence, item acceptance adjustments and one persistent rejection notification. Rejection, stock debit, WIP/Scrap and notification share one transaction, lock and actor-bound retry identity.
5. Extend existing unfinished lots and consumption for Quality-origin reservations to their original item. Keep gross declarations and completed lifecycle history unchanged; corrective production is an explicit linked authorized task, never automatic reopening or replanning.
6. Add authenticated bounded readers/commands, per-person Admin permission definitions, compact EN/AR Quality UI and narrowly scoped Warehouse source selection.
7. Run isolated SQL and focused regressions first, then TypeScript/build and scoped Ponytail Review. Record actual results and limitations here; update HANDOFF and differentiator classification only once implementation evidence exists.

No parallel inventory totals, costing, full WMS, automatic scheduling, legacy traceability backfill or remote fixture execution.

## Verification and next step

Final evidence, coverage, file manifest, portable PostgreSQL provenance and cleanup are in [Quality V1 verification](quality-control-v1-verification.md): 19 focused Node tests, 709 full Node tests, TypeScript and production build passed; 86 transactional SQL assertions and five concurrency scenarios passed against isolated PostgreSQL 17.11. Actual components were checked in an offline English/Arabic browser fixture, including mobile RTL, failure/refresh/retry and physical source picks. This is synthetic UI evidence, not a hosted database test or user acceptance.

Two new forward migrations are uncommitted and unapplied remotely. All 80 existing migration hashes and the untracked canonical design file remain unchanged. Remote migration alignment was deliberately not queried. Obtain separate TESTING authorization before checking remote histories, applying pending forward migrations, or running existing-account integration/manual acceptance. No commit or push is authorized.
