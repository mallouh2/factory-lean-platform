# Production Recording V3 — Correction approval foundation

19 October 2026. **LOCAL COMPLETE — backend policy and UX specification; UI and hosted acceptance pending.** No Phase 3C, 3D or Phase 4 implementation is included.

## Authority and original behavior

The owner-approved correction policy supersedes Phase 2's immediate-application authority for production corrections only. Before this change, effective Orders edit plus Orders view allowed `correct_lean_production` to update effective quantities immediately. Its quantity/source/WIP pipeline and M2 dated-attribution guard were already protected, but there was no pending proposal, approval decision or separate approval authority. The existing ProductionRecording dialog assumed immediate success. M3A/M3B correctly read effective entry quantities; they could not distinguish an unapproved proposal if it were written into those effective fields.

Relevant caller chain: ProductionRecording.tsx → existing `/api/data` correction command or `source_stock_command('correct')` → protected `correct_lean_production` → quantity worker, source/receipt constraints and M2 attribution. Non-versioned History, V3 History, Quality and Warehouse projections, current Lean assessments and exports consume official entry/order/stock values. Therefore permission checks only in a new dialog would be insufficient. Pending data now lives outside every official quantity projection.

This foundation does not change Maintenance independent verification, Planning approval, Warehouse adjustments, Quality dispositions or separate Scrap/Lean cause review. Saved Lean comparisons and Loss estimates remain immutable. Ordinary recording authority and default-disabled late recording remain unchanged.

## Implemented architecture

One additive migration, `20261019114709_production_correction_approval_v1.sql`, follows M3A and requires the existing M1/M2, reporting, fulfillment-command, source-stock, Quality and Permission Package contracts. It creates:

- Private `production_correction_requests`, with factory/entry identity, immutable original-at-request and proposed values, exact source selections, requester/time, status, revision, reviewer/time, rejection reason and applied snapshot/correction link.
- Protected `production_correction_command(factory, operation, payload, request_id)` for submit/approve/reject.
- Protected `production_correction_read(factory, query)` for own-request recovery and authorized review queues. Filters include original submission UUID, request ID, entry and status; keyset pages are bounded to 100 and bound to factory, actor, query, reviewer authority and revision.
- Additive authenticated `/api/production-corrections` GET/POST and strict input/response parser. No service-role client or client-provided actor/approval fields.

The request uses exact decimal strings. Official base/applied snapshots reuse M3A's private nonmaterialized entry projection, including immutable originals, effective occurrence, Quality-rejected quantity and correction revision. Snapshot timestamp serialization uses UTC, so different session time zones do not create false stale proposals. Good, discarded production quantity, Scrap KG and unfinished quantity remain separate.

### Effective-value and posting rules

| Operation | Request/audit effect | Official operational effect |
| --- | --- | --- |
| Non-approver with Orders view/edit submits | PENDING, immutable intent and UUID receipt | None: original/effective quantities, stock, WIP, reservations, reports and saved evidence unchanged |
| Approver submits | APPROVED in the same transaction; requester may equal reviewer | Existing protected correction pipeline posts once |
| Authorized approval | PENDING → APPROVED, stores reviewer/time and actual applied snapshot | Revalidates current base, sources, commitments and all existing quantity constraints, then posts once |
| Authorized rejection | PENDING → REJECTED, mandatory rejection explanation | None |
| Stale or unsafe approval | Transaction fails; request stays PENDING | None; no automatic rebase or partial posting |
| Same UUID/same intent retry | Original command result returned after current authorization | No duplicate posting |

The official correction ledger preserves immutable original production fields and correction history. Newly approved ledger rows cannot subsequently be updated/deleted. Request identity, baseline, proposed values, source selections and requester evidence cannot be edited; only one terminal transition is permitted. Terminal decisions preserve their original actor/time on retries.

The existing fulfillment command ledger binds UUID, actor, operation and exact canonical intent. Reusing a UUID for another intent/actor fails. GET recovery uses the submission UUID after an uncertain response. The API reports write failures with uncertain transport outcome as UNKNOWN and instructs reuse of the same UUID. Durable browser draft/retry implementation is deferred.

### Reuse and concurrency

Existing quantity and M2 correction workers are retained with their correction-specific Orders edit checks changed to Orders approve. Database tests compare their bodies after line-ending normalization and prove these are authorization-only changes: no quantity arithmetic, source, WIP, KG, timestamp or attribution rewrite. The raw workers remain inaccessible to authenticated callers.

The guarded public path preserves the established factory → structure → request/business lock order and READ COMMITTED contract. It rechecks current factory scope and effective authority before/after waiting and immediately before finalization. Entry baseline includes current correction revision and Quality rejection state. A proposal made against earlier official facts fails as stale instead of overwriting newer work.

Good decreases require explicit selections through the existing source-pick contract. Pooled stock remains explicitly UNATTRIBUTED (`source_id: null`); software selection does not invent physical identity. Proposed selections reserve nothing. Approval rechecks source identity, availability, existing reservations and physical conservation; unavailable stock leaves the request pending with no effects. Existing physical-output, Quality KG, source-balance, source-receipt and recording-receipt deferred constraints are checked before returning approved success.

Factory locks also serialize relevant existing source/Quality/Sales/recording writers. Actual separate-connection tests exercise approval/approval, approval/rejection, and permission revocation while an approver is observed waiting for the factory lock. Existing M2 source, Sales, Quality, deadline, Maintenance and execution races are rerun. No independent readiness or inventory engine is added.

## Permission provisioning and revocation

The established catalog already contains **Orders approve** (`orders:approve`), with no other production command consumer before this foundation. Reuse avoids a parallel permission system. SQL requires Orders view plus Orders edit OR approve for submission; only Orders view plus approve may decide/apply. A Quality reviewer can approve without broad Orders edit.

The Production Engineer package template receives Orders approve. A Quality Engineer starting package contains only Factory view, Orders view and Orders approve; it does not imply Quality module administration or broad production editing. Existing Production Engineer template packages receive the new default once during migration. No users are assigned by job title, and no direct person grants or package assignments are replaced. Existing direct-only engineers need an explicit ordinary administrator grant/package assignment; this is intentional under person-based authorization.

Administrators may customize/revoke these stored package grants or assign them to other people using the current protected administration workflow. Later package seeding does not restore a revoked grant. Effective rights remain the union of direct grants and all assigned packages: removing one grant does not deny another surviving grant. Revoke every granting source to remove authority. Existing owner/platform access rules and scope expiry remain intact.

Future deployment preflight must inspect existing customized engineering packages and possible package-name collisions before approving the one-time defaults. No remote package content, membership, activation or effective permissions were inspected or changed in this local task.

## Security and compatibility boundaries

Private request storage uses RLS with no direct PUBLIC/anonymous/authenticated access. Public RPC execution is authenticated-only, with effective person permission and live factory-scope enforcement inside SQL. Tenant-bound entry FKs and explicit factory filters prevent foreign-entry/foreign-request access. Reviewers see authorized factory requests; ordinary submitters see only their own. API origin/size/input validation complements rather than replaces SQL authorization. Responses are private/no-store.

The old UUID-returning correction signatures remain for authorized callers. Approvers with the existing UI's Orders edit/view access keep immediate correction behavior and receive an automatically approved audit request. Existing immediate-save callers without approval now fail closed: returning a PENDING request as a correction UUID would falsely display Saved and imply quantities changed. No unrelated UI or old API authorization map was edited. An approval-only reviewer uses the additive contract until UI integration is separately approved.

Pre-policy committed corrections remain historical facts. Exact authorized retries return their original correction UUID without inventing retrospective approval records. Current reporting remains based only on official effective entries/correction ledger; pending/rejected requests are not joined into History totals, Quality, Warehouse, Lean, Loss or exports. Previously saved Lean/Loss records remain unchanged. Correction approval does not mark a Scrap observation reviewed or approve a cause.

## Reason field and global UX standard — specified only

[UX_SIMPLICITY_STANDARD.md](design/UX_SIMPLICITY_STANDARD.md) establishes the owner-directed permanent Simple by Default, Detailed on Demand rule, current-code inventory, three information levels, EN/AR/RTL/390px/accessibility requirements and ten prioritized daily workflows. AGENTS.md references this standard for future interface work. The existing Design System document is untouched and remains unapproved.

Correction UI specification: one mandatory editable free-text explanation with optional suggestions, no compulsory Other/category. Selection fills the same text field; users can edit it or enter arbitrary custom text. Current server rule is 3–2,000 trimmed characters for a reason; actual text is retained verbatim, not replaced by a category ID. This is structural validation, not an automated judgment of explanatory quality. SQL/API tests cover edited-suggestion text and arbitrary EN/AR explanations; no suggestion component, browser usability or screen-reader acceptance is claimed.

Technicians should see official versus proposed quantity and Pending approval. Approvers should save directly and see Correction approved without an unnecessary self-approval screen. A small review queue should show reference, employee, baseline/proposed values and units, explanation, time and Approve/Reject; source/audit details stay on demand. Conflicts, physical identity, required units, safety, reservations and stale-state warnings remain visible. These UI behaviors are specifications for separate authorization, not delivered screens.

The source-based inventory identifies density risks in History filters/columns, combined operational/configuration controls, repeated reference entry and ambiguous generic success messages. It does not claim observed user-study failures or redesign any screen. MRPeasy/Tulip primary-source patterns inform focused task surfaces and appended correction context, not compliance, superiority or unique market capability.

## Validation and evidence

All SQL validation uses the previously authorized portable PostgreSQL 17.11 runtime, disposable databases bound to 127.0.0.1, existing local Auth/RLS fixtures and no hosted credentials. Final fresh and upgrade paths both passed with unchanged input hashes throughout each run.

Commands:

```text
node --test tests/production-corrections.test.mjs tests/production-reporting-api.test.mjs tests/production-late-recording.test.mjs tests/production-shift-work.test.mjs tests/production-recording.test.mjs tests/production-flow.test.mjs tests/execution-queue.test.mjs tests/shift-time-windows.test.mjs tests/unfinished-production.test.mjs tests/maintenance-readiness.test.mjs tests/lazy-history.test.mjs tests/production-history.test.mjs tests/factory-navigation.test.mjs tests/permission-packages.test.mjs
pwsh -NoProfile -File tests/production-corrections/run-local.ps1 -RuntimeDirectory C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018 -Port 55470 -Upgrade
pwsh -NoProfile -File tests/production-corrections/run-local.ps1 -RuntimeDirectory C:\Users\Temp\AppData\Local\Temp\FactoryLean-Shift-M1-Runtime-20261018 -Port 55471
```

Node: **333/333 PASS**, including 54 new correction parser/API/permission/recovery tests and 279 relevant regressions. Rechecked after freezing the final SQL: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Correction-Node-regression-final.txt`.

TypeScript and isolated optimized Next.js 16.3.5 webpack build: **PASS**. Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Correction-Policy-Build-6650812f96c444d5801d32e17c5eb77a\{typecheck.txt,build.txt}`. Existing dependencies were reused; only dummy `.invalid` Supabase configuration was used. Final application-source hash comparison establishes applicability; no real application server or hosted service was started.

Both database paths apply 93 required pre-policy migrations plus this migration. The repository has 95 migration files because Export Reader is deliberately excluded from the local chain. Fresh applies the policy before fixtures; upgrade creates pre-policy records/corrections/reporting snapshots first. Schema/body/grant/RLS/gate/history snapshots are checked before/after. No historical migration is modified.

SQL covers pending/no-effects, automatic/self approval, mandatory/custom reasons, package defaults/revocation/union, anonymous and direct-table/delegate denial, cross-factory/request denial, bounded queue/recovery, exact 19-decimal Good/KG, WIP, stale/source failure rollback, immutable originals/audit/saved evidence and default-disabled recording. Upgrade additionally proves actual historical correction replay without retrospective approval. The timezone test proves UTC/Riyadh reviewer sessions share a stable baseline.

| Final path | New correction assertions/groups | Inherited SQL assertions | Total SQL assertions/groups | Actual concurrent scenarios | Actual HTTP/SQL scenarios |
| --- | --- | --- | --- | --- | --- |
| Fresh | 69 | 239 | 308 | 3 new + 16 inherited | 12, with 27 real RPC calls |
| Upgrade | 71 | 239 | 310 | 3 new + 16 inherited | 12, with 27 real RPC calls |

The inherited 239 assertions comprise 69 M3A reporting/security/temporal/multiple-entry checks, 66 M2 writer/boundary/Maintenance/startup checks, and 104 WIP/readiness/transfer/source-stock/Quality checks. Assertion groups include compound conservation/security comparisons; counts are not independent full end-to-end workflows. Both paths also compare 323 unrelated function/grant contracts, existing relation ACL/RLS/policies and activation snapshots. The two additional upgrade checks use an actual pre-policy correction, while the empty fresh historical case deliberately does not claim those checks.

Final evidence roots:

- Fresh: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Correction-Policy-213840fc46e146a687aab78ab3721484\results`.
- Upgrade: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Correction-Policy-ea05361411fc455b954861ae098ea60f\results`.

Each retains input hashes, schema/body/security checks, assertion logs, concurrency evidence, HTTP status summaries and successful final/cleanup logs. The owned PostgreSQL processes stopped, test data directories were removed and ports 55470/55471 were released. The initial development iterations exposed fixture/alias issues and input-hash failures when sources changed during a run; those runs are not the final PASS evidence. No inventory-integrity failure was observed in the final runs. No service installation, dependency download or system PATH change was required.

HTTP tests execute the actual Next handlers, installed Supabase client, authorization/parser and real SQL via fixture sessions/transport. They are **not** hosted GoTrue/PostgREST/JWT-cookie renewal, full Next router or browser acceptance. The inherited Phase 3B 5,010-row/51-page scale evidence is historical, not rerun or represented as new evidence. No broad full-project suite, hosted credentials, remote histories or UI tests were run.

## Exact task change manifest

Existing files changed only for this task's documentation/governance:

1. AGENTS.md — permanent UX/correction policy rules.
2. HANDOFF.md — current local milestone prepended, prior content retained.
3. docs/PRODUCT_DIFFERENTIATORS.md — conservative local-only parity note.

New files:

4. supabase/migrations/20261019114709_production_correction_approval_v1.sql
5. src/utils/production-corrections.mjs
6. src/app/api/production-corrections/route.ts
7. tests/production-corrections.test.mjs
8. tests/production-corrections/run-local.ps1
9. tests/production-corrections/before.sql
10. tests/production-corrections/after.sql
11. tests/production-corrections/fixture.sql
12. tests/production-corrections/policy.test.sql
13. tests/production-corrections/security.test.sql
14. tests/production-corrections/historical.test.sql
15. tests/production-corrections/concurrency.mjs
16. tests/production-corrections/http.mjs
17. tests/production-corrections/final.sql
18. docs/design/UX_SIMPLICITY_STANDARD.md
19. docs/production-correction-approval-foundation.md

Final preservation check: all 715 pre-existing project files were compared against the starting SHA256 inventory. Only the three listed governance/documentation files changed; all 94 earlier migrations and all existing application/test files match their starting bytes. Earlier HANDOFF content is preserved as an exact byte-for-byte tail; the differentiator note is append-only. Design System remains untracked/unchanged, Export Reader unchanged, and environment/link configuration hashes match. Branch/HEAD/main/index are unchanged and nothing is staged. Final working tree has 27 modified tracked and 133 untracked individual files, including prior unrelated work; 731 inventoried project files. This task adds 16 files and changes three existing documentation files, not every dirty file in the checkout.

## Remaining work and stop

No unresolved product decision blocks this local foundation. Approval self-authorization, reasons and engineering defaults follow the owner's policy. Revocation under union permissions requires removing all surviving grant sources; assignment of direct-only engineers remains ordinary administration, never automatic job-title inference.

Next Phase 3C requires separate authorization for period-aware Scrap/Lean observation/review and containment/unknown handling through existing protected consumers. It must consume only effective approved quantities, preserve separate cause/evidence review, historical versions and saved Loss/Lean results, and avoid counting both proposal and effective entry. Do not implement those consumers here.

Phase 4 separately needs the technician/reviewer UI, suggestions, permission-sensitive labels, current/proposed quantities, exact source selection and durable UUID recovery. Current backend tests do not certify EN/AR/RTL/mobile UI. Hosted deployment requires fresh authorized Local/TESTING/DEV history verification, existing package customization checks, isolated manifest/dry-run approval and hosted authentication/security acceptance. None is authorized now.

Late recording remains disabled; M1 readiness remains unavailable. Maintenance activation is unchanged. Export Reader and Design System are preserved. No hosted Supabase/Vercel access, deployment, activation or Git write is part of this task. Stop for product-owner review; do not proceed into Phase 3C/3D/4.
