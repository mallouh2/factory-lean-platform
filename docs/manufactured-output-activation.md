# Manufactured Output factory activation

Phase 4B.3 is a local implementation and isolated acceptance phase. No hosted migration, deployment or factory activation is authorized by this document. Migration `20261107080452_manufactured_output_safe_activation_v1.sql` replaces the permanent disabled predicate with an explicit private, default-disabled state. Deployment alone creates no factory rows and no inventory.

## Accounting and state

- `NEVER_ACTIVATED`: missing state or no first activation; existing legacy accounting remains authoritative.
- `ENABLED`: new eligible production must use protected manufactured enrollment. Recording and Quality release do not credit finished stock. Physical receipt credits only the released quantity, once.
- `PAUSED`: permanent first activation remains. History stays readable and original authorized committed requests may return their immutable result. New manufactured mutations fail atomically. Legacy admission stays closed. Pause does not reverse stock, cancel commitments or stop ordinary existing-stock Sales/Warehouse workflows.

The original technician measurement remains historical evidence. Quality calculates Finished = Actual Total − Irrecoverably Rejected − Recoverable Unfinished. Finished is not an editable Quality input. Ordinary Sales uses pooled quantity dispatch; this change introduces no mandatory batch selection.

The operator transition and manufactured writers serialize in the existing factory → structure order, then protected state/record locks. Fresh quantity writes require Read Committed, preventing a stale higher-isolation snapshot from bypassing first activation. Missing state always means disabled. The first activation timestamp cannot be cleared, changed or deleted through normal SQL. A database owner can, by definition, alter database safeguards; this primitive is not a defense against a malicious database owner.

## Privileged operator procedure for a separately authorized future rollout

1. Verify the exact hosted project, factory UUID, migration histories, application version and Lean Edge version under the future task's authorization. Keep the controlled write freeze required by Phase 4B.1 throughout migration/application/Edge cutover. Existing old application/Edge writers are not certified compatible.
2. Apply the approved migration chain with Export Reader still excluded unless separately reviewed. Verify that all factories remain disabled before any explicit activation.
3. Check a clean synthetic pilot factory: supported Product units/route, appropriate per-person Production/Quality/Warehouse grants, compatible active warehouses, and no available unclassified legacy WIP. Do not delete, relabel, convert or backfill historical WIP. Activation rejects any available lot whose `manufactured_group_id` is null. Unsupported carryover input also fails closed after enrollment.
4. Review old-client behavior, retry queues, existing legacy inventory/receipts and current activation revision. Obtain separate authorization for that specific factory. No browser or service-role activation endpoint is provided.
5. As the approved database owner/operator, in a fresh Read Committed transaction, invoke the private primitive with the verified factory UUID, expected revision and meaningful reason. For a missing row the expected revision is zero:

```sql
begin isolation level read committed;
select private.set_manufactured_output_activation(
  '<verified factory UUID>'::uuid, true, <verified expected revision>,
  '<approved activation reason>'
);
commit;
```

6. Verify the returned revision/first activation and immutable audit record, then exercise the authorized pilot lifecycle before ending the write freeze. Pause uses the same primitive with `false` and the current revision. Re-enable uses `true` and the next current revision, preserving the first timestamp. Never clear the row or rewrite history as rollback.

The function is SECURITY INVOKER in `private`. No execution or table rights are granted to PUBLIC, anon, authenticated or service_role. It uses server timestamps, `auth.uid()` where supplied by an approved operator session, and the actual database role. A direct database console may have a null Auth actor; the role and required reason remain recorded. Activation is not granted by job titles, View As, permission packages or the public capability reader.

## Recovery, legacy coexistence and limits

Existing protected RPCs retain actor/factory authorization, normalized intent and request identity checks before committed-result recovery. Same request with different intent or actor is rejected. Fresh private ledger writes hit the shared pause guard, so any earlier public-table work in that transaction rolls back too. Readable does not mean writable.

The shared `production_entries` INSERT boundary prevents new positive Good/WIP output from old wrappers or direct privileged inserts after first activation, including version-one rows with default zero `good_quantity` but positive `produced - rejected`. Existing revoked RPC/table privileges remain revoked. Already-credited legacy requests, approved legacy corrections and non-crediting Warehouse acknowledgment preserve their original accounting. Scrap-only zero-output recording is outside manufactured enrollment. Historical corrections never enroll an old entry for a second manufactured credit.

Source identification and ordinary existing-stock dispatch remain their independent Warehouse contracts; pausing does not roll back physical inventory. Reconciliation still requires supported physically identifiable, uncommitted stock. Reserved, dispatched, consumed or unidentifiable material cannot be silently reversed. Consumed-WIP rewriting remains unsupported (`output_reconciliation_scope`). No generalized carryover conversion, per-warehouse balance ledger or full physical batch genealogy is introduced.

Pause is the supported operational stop, not a database down migration. A fresh request may encounter another existing validation before the pause guard; every actual protected manufactured write still fails. Committed retries do not become a general permission to create new work. Unrelated Planning/Execution transitions remain governed by their existing contracts.

## Local verification scope

Use the runner and prerequisites in `tests/manufactured-output-activation/README.md`. Acceptance uses the actual candidate, existing protected production/Quality/receipt/Sales SQL and explicit privileged transitions on owned disposable PostgreSQL. No predicate override is acceptance evidence. Full execution results, hashes, balances, observed race sessions and limitations are recorded in the Phase 4B.3 evidence report referenced by `HANDOFF.md`.

The HTTP fixture exercises actual installed SDKs and Next route handlers over loopback into protected SQL. Its Auth/PostgREST adapter is synthetic. It does not certify hosted JWT/RLS transport, Deno Edge runtime, browser interaction or owner manual acceptance. EN/AR feedback reuses existing interface structure; no redesign is included. Product differentiation was reviewed: factory activation is deployment/accounting control, with no new competitive capability or measured customer benefit claim, so `PRODUCT_DIFFERENTIATORS.md` remains unchanged.
