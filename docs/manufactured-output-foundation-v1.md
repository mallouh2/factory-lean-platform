# Manufactured output — inactive backend foundation

24 October 2026. Local Phase 1; **not an operational posting integration**.

## Scope and authority

The owner's corrected policy requires Quality inspection/release only for factory-manufactured finished and recoverable unfinished output intentionally entering Warehouse storage. Purchased raw materials, external receipts, opening balances and other non-production receipts retain their existing workflows. There is no general inbound-inspection project or deferred gate for those paths. Machine-to-machine WIP transfers remain outside Warehouse receiving.

Current application behavior remains immediate Good credit plus a non-crediting Warehouse acknowledgment. This migration does not redirect that behavior. It adds no production-facing UI, public mutation RPC, activation toggle, permission grant, stock backfill or new inventory ledger. The protected capability returns `available:false` unconditionally. Enabling this foundation requires a separate integration migration, not flipping a client flag.

## Minimal architecture

Two private, RLS-enabled, directly inaccessible tables:

- `manufactured_outputs`: immutable source entry/item/Product/unit, frozen source context, declaration groups, configured operations and posting version `RECEIPT_V1`.
- `manufactured_output_events`: immutable declaration, Quality determination, movement-backed receipt, unfinished disposition and informational acknowledgment events. Actor/time, UUID intent/result and monotonically checked output revision are retained.

These are handoff/audit facts, not balances. Inventory remains in existing finished-goods balances/movements and unfinished lots/location movements. Existing unmarked production entries retain legacy posting semantics; no historical row is reclassified or recredited.

Configured `production_routing_steps` of kind `work_center` supply operation identities. Their names/work-center references are frozen when output is declared. The **set** of selected step IDs is canonicalized; position is not used to impose execution order. Duplicate, foreign/unconfigured or null operation selections fail. A line-level routing step is not guessed to mean Printing/Cutting. Products without explicit work-center steps cannot declare unfinished groups until ordinary configuration supplies those operations. This is not a new routing engine or automatic SKU generator. Distinct group IDs preserve separate restrictions and genealogy even when their missing-operation sets match.

## Internal protected contracts

`private.manufactured_output_command(factory, operation, target, payload, expected_revision, request_uuid)` is revoked from PUBLIC, anonymous, authenticated and service-role callers. It is a future protected-adapter primitive, not an application endpoint.

| Operation | Authority and behavior |
| --- | --- |
| DECLARE | Existing Orders view/edit; same-transaction newly inserted production entry; no earlier stock credit, stored/consumed WIP, correction or Quality rejection. Finished/unfinished groups must exactly match source effective quantities. |
| QUALITY | Quality view/create for the initial determination; Quality view/edit for revisions. Accepted groups plus rejected production-unit quantity equal declared physical output; each group's release is bounded by its quantity. No Production approval and no stock/Scrap movement. |
| RECEIPT | Warehouse edit, physical confirmation/location context, fresh revision, positive exact quantity within remaining group release. Requires a matching existing finished or unfinished inventory movement inserted in the **same transaction**. No second credit is issued by this primitive. |
| DISPOSITION | Existing Orders view/edit, as used by protected Planning. Records bounded COMPLETE/REPLACE quantities with reason. Completion retains original demand ownership; replacement releases the chosen quantity from that demand while preserving origin. No job creation, scheduling, reservation or fulfillment mutation. |
| ACKNOWLEDGE | Orders view; identifies an actual Quality revision. Informational read acknowledgment only; never approval of the already-authoritative determination. |

The initial declaration does not imply Quality acceptance. A rejected production-unit quantity is not automatically Scrap KG. Disposition/Scrap posting belongs to later integration. Partial release is represented separately from accepted quantity; unreceived released output remains outstanding, not automatic loss.

Permissions reuse the existing factory-scoped union of direct grants and permission packages. There are no title-based checks, new grants or membership modifications. A live approved membership/support/platform-scope check supplements the existing permission helper, including clock-based scope expiry. Authorization is checked before locks, after waits and before appending the event. Read Committed is required. Lock order is factory advisory lock → structure advisory lock → source/output row. Future posting adapters must take the same locks **before** creating inventory movements.

Retries check current authorization, actor and original UUID intent and return the original immutable result before mutable state checks. Different intent/actor conflicts. Revisions protect races between Quality, receipt and disposition; exact PostgreSQL numeric arithmetic is used throughout. Unique movement references prevent binding one inventory movement to multiple receipts.

## Safety boundaries and compatibility

- No inherited business function, permission definition or grant is replaced. Non-production receiving and current Sales reservation conversion remain unchanged.
- New declarations cannot adopt already credited entries, including an entry credited moments earlier in the same transaction. Historic entries are not backfilled.
- A conditional source-entry guard rejects changes to an enrolled new source. It affects no unmarked legacy entries. Source fingerprint comparison also fails closed if dependent source context changes. This deliberately blocks unsafe correction rather than pretending a production correction can override Quality.
- Quality revisions are allowed before receipt/disposition. Once either occurs, explicit reconciliation is required and is **not implemented** in Phase 1. Received/committed/shipped/consumed material cannot be silently rewritten by this foundation.
- Existing stored-WIP location movements are reused. A lot cannot be bound to different classification groups. The existing one-normal-lot-per-entry constraint is unchanged: later integration must safely support multiple classified groups and processing/issue selection before enabling production use.
- Physical confirmation and receiving location do not invent a roll label or identified stock. Existing finished sources remain UNATTRIBUTED until the established physical-identification workflow applies. Genealogy alone is not proof of physical segregation.
- A replacement decision does not fulfill demand. It records release of an unfinished allocation; later recovery needs an independently authorized demand/stock destination. Actual completion/replacement task creation and reassignment are not implemented.
- Disabling/failing capability cannot route pending `RECEIPT_V1` output back to immediate-credit behavior: there is no callable activation/recording adapter in this phase, and enrolled source corrections fail closed.

## Verification

Runner: `tests/manufactured-output/run-local.ps1 -RuntimeDirectory <existing portable PostgreSQL runtime>`.

The runner creates a new localhost-only PostgreSQL cluster on an unused port, installs the unchanged 100-file baseline (Export Reader excluded), inserts existing legacy fixture state, checks the new migration, runs focused SQL and real multi-connection tests, then stops/deletes only its owned cluster data. Scripts, input hashes and results remain outside the repository.

**Important test boundary:** the fixture simulates a future deferred-credit recording adapter by temporarily disabling only the legacy `finished_goods_receipt` trigger while creating synthetic source records in this disposable database, then restores it immediately. Other recording/authorization/KG constraints remain installed. The test-only receipt adapter posts through existing balance/movement/source infrastructure and binds the movement in one transaction. Neither adapter is in the migration or application. These tests establish foundation contracts, not completion of recording integration, Sales allocation integration or hosted Supabase acceptance.

Final frozen run: **54 SQL assertions PASS**, plus **4 real multi-connection races PASS** (overlapping receipts, identical-UUID receipts, Quality/receipt revision race, permission revocation during an observed lock wait). Three additional authenticated/security groups passed: unauthorized Quality/receipt and cross-factory denial, package/direct grant union and edit restriction, private-call denial and incompatible isolation rejection. Exact 19-decimal quantities, immutable history, source conservation, no premature reservations, legacy credit preservation and exempt opening/external/raw-material receipts are covered.

Upgrade preservation passed for **346 existing function bodies/grants/configurations** and **105 existing tables' data/security**. All 101 pre-existing repository migration files remain unchanged. The new migration makes 102 local files; no remote migration count was queried or claimed.

Final evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-SQL-3e2c153a5254412590bcc3016bbb5bdb\results`. Input hashes, SQL output, race summary and cleanup confirmation are retained there. The owned cluster was stopped and its data removed. Existing preview services/data were not used or changed. Earlier development runs exposed a PowerShell NOTICE-handling issue, an ambiguous SQL variable, and fixture code/overproduction mistakes; they are not claimed as passing evidence. Final review added an explicit null-disposition guard and regression before the frozen successful run.

No TypeScript, UI, API or build inputs changed; TypeScript/build and unrelated suites were not rerun. Standalone PostgreSQL authorization uses the established local auth shim; this is not hosted GoTrue/PostgREST acceptance.

## Exact change manifest

- `supabase/migrations/20261024072457_manufactured_output_foundation_v1.sql`
- `tests/manufactured-output/run-local.ps1`
- `tests/manufactured-output/before.sql`
- `tests/manufactured-output/after.sql`
- `tests/manufactured-output/fixture.sql`
- `tests/manufactured-output/foundation.test.sql`
- `tests/manufactured-output/concurrency.mjs`
- `docs/manufactured-output-foundation-v1.md`
- `HANDOFF.md` (new current section only)

## Required next integration (separate approval)

1. Protected recorder enrollment/cutover, including Good, multiple unfinished groups and immutable UUID recovery, with immediate credit disabled only for genuinely new enrolled output.
2. Effective Quality consumers, rejection/Scrap KG disposition and notification UI; preserve original declarations, existing review eligibility and immutable Lean/Loss evidence.
3. Complete atomic finished/WIP Warehouse receipt adapters, source identity and group-safe lot issuance/processing. Convert incoming Sales commitments only after eligible actual receipt; update forecasts for recorded/released-unreceived quantities without duplicate replacement forecasts.
4. Correction/reinspection/reconciliation before release, after release, after receipt and after reservations/dispatch/consumption. Preserve old retry outcomes and protect legacy positive adjustments at cutover.
5. Real completion/replacement Planning tasks, explicit lot input/demand allocation and later recovery destinations. Never alter queue order, OPEN transfer ownership or `evaluateFlow`.
6. End-to-end local acceptance of the whole chain before any separately authorized deployment or activation. Non-production receipts remain exempt and unchanged.

`PRODUCT_DIFFERENTIATORS.md` was reviewed; an inactive internal foundation adds no shipped competitive claim, so it was not edited.
