# Current extension — 10 November 2026, Group 1B

The owner manually accepted Start after actual Warehouse handover in Group 1. The existing guard remains; readiness now also excludes separately returned or return-held custody. Warehouse owns raw reconciliation, Production is read-only, and raw returns have independent MRR requests. Original issue history remains fulfilled. See [the current contract](material-accounting-independent-returns.md). Earlier instructions below are dated history and are superseded only where this extension explicitly changes authority and return accounting.

---

# Material custody and new execution starts — Group 1

Implemented locally on 9 November 2026. This is a forward repair of the existing material-request workflow, not a new module or hosted release.

## Operational contract

Reservation retains stock in Warehouse. An explicit physically confirmed ISSUE deducts Warehouse stock once and creates Production custody. It is not consumption. Explicit measured CONSUME uses Production custody without deducting Warehouse a second time. RETURN requires physical confirmation and an explanation. Existing per-person permissions, source identities, revisions, actor-scoped retry receipts and audit remain authoritative.

The request reader exposes decimal-string eligible bounds for each action. Warehouse defaults to reservation when unreserved, physical issue when reserved, and the legal source-specific maximum when one source is selected. The operator may reduce the amount, including fractions. Missing authority, zero, invalid and excessive quantities cannot be submitted. The transaction independently rechecks eligibility and reservation factory/material/order identity.

New execution starts require the entire approved item's physical input requirement in same-order Production custody: issued minus consumed, matched by factory, material/product identity and unit. The requirement comes from the existing product weight, configured physical-input route, approved output quantity and recipe factors. Warehouse stock and reservations alone never satisfy Start. Changed frozen requirements and missing route/recipe/weight/unit configuration fail closed. Existing completion/rework source-lot safeguards continue to own existing-source work; raw inputs are not exploded twice.

The protected Start wrapper locks the factory before the existing structure/queue checks. A production-order transition trigger enforces the material guard for alternate update paths as well. Stronger snapshot isolation is rejected with a retryable stale-readiness result, matching the existing Start contract. Existing physical-machine, Maintenance, queue, planning and Quality safeguards remain in force.

Start currently accepts only factory and item IDs. It has no authorized partial-run output quantity, bound execution allowance or staged-input authorization. This phase does not infer one from arbitrary custody. Partial handovers remain supported; a new Start requires the full approved item requirement. Partial output recording and explicit measured consumption remain supported after admission. A bounded partial-run contract requires a separate approved design.

## Lifecycle and legacy work

Within the preparation window, an actionable unreserved request is Requested, a reserved request is ready for issue, and fractional handover remains partial until fulfilled. A genuine future postponement releases only the unissued reservation, explains the preparation-window reason and reuses the same request on valid re-entry. It never invents a physical return.

An obsolete awaiting flag on eligible current/active work projects Requested with a recheck explanation. Authorized RECHECK reconciles the existing request and creates the existing audit receipt; it does not hand over or consume stock. Cancelled/rejected requests stay closed. Completed work with missing issue or unused custody projects a closed material-review state, rather than Deferred. Lifecycle explanations are read projections over existing request/progress state.

Legacy active/completed recordings, Quality results and movements are preserved. No automatic historical issue, consumption, reopening or stock correction is performed. Collect real physical evidence and authorize a separate reconciliation when historical custody is missing.

## Evidence and boundaries

Forward migration: `20261109124108_material_custody_start_guard.sql`. Evidence: `D:\FactoryLean\Reports\Phase4B.7.1-20261109\REPORT.md`. Focused test sources: `tests/material-start-guard`; decimal UI tests: `tests/material-action.test.mjs`.

Owner preview: `http://127.0.0.1:29721/`. Hosted TESTING/DEV/Production/Simulation, Vercel and Edge behavior remain unverified and unchanged by this phase. Machine synchronization, alternative-machine transfers, Gantt, Quality UI, Lean Analysis and Customer Returns remain outside Group 1.
