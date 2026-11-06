> **4 November2026 update:** The Planning candidates and all21 stale Sales/Warehouse tests are now integrated/repaired on local4222; full1470 Node/122 SQL/3 concurrency scenarios/TypeScript/build pass. Existing Floor/historical behavior and all owner data are preserved. Final4222 authenticated API and normal owner browser checks PASS after the owner closed the native QA dialog; Planning/Gantt,6h policy,Floor and historical form verified read-only,with no console errors. See [current rollout report](planning-policy-rollout.md) for exact evidence and boundaries. Earlier dated candidate/failure statements below remain historical evidence.

# Factory Floor toolbar and historical Production approval V2

3 November 2026. **COMPLETE / LOCAL VERIFIED; awaiting owner manual acceptance.** Only the isolated 4222 runtime is updated. This is not a hosted release or approval of the unfinished Planning rollout.

## Running state and preservation

- Preview: http://127.0.0.1:4222/?view=lines
- Source: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/floor-historical-v2-app
- Verified standalone build: .next-release/standalone; owner runtime.json now names this source.
- Owner PostgreSQL: 127.0.0.1:55496 / factory_lean_quality_local; Auth adapter4304 unchanged. Existing credentials: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/LOCAL-LOGIN.txt. No passwords copied into this report.
- Recovery: C:\Users\Temp\AppData\Local/FactoryLean-Recovery/floor-historical-v2-1793706456299. Candidate source946 files and cold database2077 files were byte/hash verified before changes. The cluster was resumed normally after that checkpoint.
- All122 existing owner business tables match the checkpoint under an identical ordered row digest. Two initial aggregate-order differences were checked against a separate read-only clone: every row was identical. No owner operational acceptance writes were performed.
- Port3000 source/process/configuration/database untouched. Port4242 process30384 and its files/database untouched. No hosted access, accounts/password/permission changes, Git index/ref writes, commits, pushes or deployments.
- Historical approval remains TRUE on this previously authorized local factory. Completed-shift late recording remains FALSE; all unrelated gates and inherited loopback-only manufactured test predicate are unchanged. Shipped defaults remain disabled.
- Pre-Planning checkpoint source was used because integrated-qa-v3 contains unpromoted candidates. Those source changes and planning-policy migrations20261103102938/103513/103737 remain preserved in their original directories; none was applied to55496 or promoted here.

## Toolbar

The previous machine-status filters, separate summary and icon-only motion control are one compact toolbar. Header and real line/machine summary are aligned on opposite sides, with a secondary labelled animation button. Uniform44px filter targets wrap into two columns at390px; selected All is restrained slate rather than an operational color.

Running is green #16a34a; Stopped red #dc2626; Delayed amber #f59e0b; neutral uses existing slate/gray tokens. Affected remains a separate real blocked-flow filter, with explanatory text; it is not renamed Delayed. Its toolbar indicator is amber, while existing flow/card semantics are unchanged. Delayed uses the existing executionTiming result for an ACTIVE job assigned to a machine past planned finish. Counts are explicitly labelled as machine filters, not a claim that machine count equals line count.

Pause animations changes only the existing diagram-motion state. Its tooltip explicitly says live data continues updating. No polling or physical machine control was changed. Dark mode is not implemented by this existing surface; no dark-theme claim is made.

Design reference: [Evocon Factory Overview](https://evocon.com/feature/factory-overview/) supports readable live status hierarchy; Factory Lean retains its own physical/flow, assignment and permission contracts. PRODUCT_DIFFERENTIATORS.md was reviewed; this bounded usability/approval refinement adds no new competitive claim.

## Protected historical approval

New forward migration: **20261103115126_historical_production_auto_approval_v2.sql**, only in the isolated source/evidence migration directory and applied to the disposable55628 test cluster and authorized4222 cluster55496. All142 prior source migration files are byte-identical. Export Reader is preserved; no hosted migration status is asserted.

The existing command still requires factory-scoped authenticated membership and Orders view/edit. Only a NEW valid SUBMIT whose real server actor has effective Orders approve is routed into the existing APPROVE transaction. Direct and package grants both work; role labels/client flags confer nothing. No permission was granted to any live account.

A private RLS-protected, non-client-writable immutable audit captures request, factory, membership, actual approving user, orders:approve authority, SUBMIT_AUTO_APPROVAL mechanism, transaction and server timestamp. The self-submission exception in both the command and deeper recording context requires this exact trusted request/actor/factory/current-transaction audit. Old pending self-approval and ordinary worker self-approval remain denied.

Factory/structure/gate/request/item locking and existing canonical quantity, occurrence, context, source and KG checks remain authoritative. The new submission, audit, canonical receipt, decision and Quality output commit together. Injected writer failure rolls all of them back. Same UUID returns the original receipt; no second Production or Quality insertion is attempted. Quality inspection and physical receiving remain separate; no stock is credited by these test approvals.

### Existing owner record

PO-0000030 request cdc294fe-b55a-45cd-b62a-a94baa674940 remains Pending:2026-11-02, Good5m, Scrap0KG. Original submitter/payload/audit are unchanged. It has zero decisions, zero production entries and zero auto-approval audit rows. It is visible with an explanation that another authorized approver must review this earlier-policy submission. No second5m record or retrospective decision was created.

## Submission UX

Known excess shows the remaining typed threshold and an unchecked required confirmation; submitting focuses that checkbox before any POST. Invalid quantities and an existing same-actor/item/shift Pending request are rejected locally without losing input. SQL remains final authority.

Saving blocks duplicate clicks without displaying an early unconfirmed warning. Confirmed worker success closes the ordinary modal and says Sent for Production approval. Confirmed authorized success closes it and says Production recorded and approved; sent to Quality. No blocking Done popup is added. Unknown replies retain the actor/factory-scoped original raw UUID/body; Check submission status reads the protected result and completes without another insertion. Transport errors use localized actionable feedback, not raw timeout text.

Current/Previous shift selection and established blue/white selected styling remain. Same-scope background reads no longer disable a populated historical form, preventing polling from removing input focus. Server revision/fingerprint validation remains in force.

## Verification

| Evidence | Result |
| --- | --- |
| Final focused Node: Floor, historical form, relevant Recording tests | **90/90 PASS**, including14 new tests |
| Protected PostgreSQL assertions | **27 PASS**:16 protected transitions,6 atomic/factory/quantity,3 package/immutable-audit,2 disabled-gate |
| Concurrent same-UUID owner submissions | **PASS**, observed database lock wait; one request/decision/audit/entry/Quality output, zero stock credits |
| Normal browser worker1m | Pending, modal closes; protected normal-auth HTTP approval attempt403, decision count0→0 |
| Independent owner approval of that browser request | Authenticated HTTP200, exactly one Quality output, no stock |
| New owner browser1m | Auto-approved without separate approval click; modal closes |
| Normal-auth owner HTTP submission and retry |200/200, original receipt and one Quality output |
| Delayed browser0.2m result | Client timed out; original request retained; Arabic Check Status recovered APPROVED and success toast; exactly one entry/Quality output, zero stock |
| Excess validation | Visible remaining threshold, unchecked confirmation focused, input preserved |
| EN/AR1440/768/390 | Filters/counts, keyboard focus, RTL and44px targets verified; no page overflow |
| Final refresh stability |105.7 seconds across at least two30s cycles: input focus,0.3m unsent draft, shift/item selection and enabled state unchanged |
| Final4222 owner read-only smoke | Existing password login, pending record, toolbar and console PASS; no operational POST |
| TypeScript and isolated optimized build | PASS; final build .next-release |

Full Node baseline review ran **1403/1424 PASS,21 FAIL** before the last three feedback/refresh tests were added. The same baseline failures are12 in sales-fulfillment.test.mjs and9 in warehouse-operations.test.mjs, stale mocks/imports for current Warehouse components/readers. They are preserved, classified in baseline-failures.json and not attributed to this task. The final90 focused tests cover the last refinements. Do not claim the full suite is green.

One build attempt encountered Windows EBUSY while the acceptance server used that build directory. A separate .next-release directory was built and verified successfully. Native sign-out temporarily blocked the embedded browser; normal sign-out/login recovered, without an authentication bypass.

These are real local PostgreSQL and local Auth/API-adapter results, not hosted Supabase/PostgREST acceptance. Existing historical reader returns at most100 requests; this fixture's actual Pending count is1. No new large-history pagination contract is claimed. Historical input-lot/startup evidence remains excluded as previously documented.

## Evidence and exact changed files

Evidence directory: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/floor-historical-v2-evidence

Core isolated source:
- src/features/FactoryFloorV2.tsx
- src/features/HistoricalProductionRecording.tsx
- src/features/ProductionRecordingV3.tsx
- src/app/globals.css
- src/locales/en.json
- src/locales/ar.json
- supabase/migrations/20261103115126_historical_production_auto_approval_v2.sql

Tests:
- tests/historical-floor-v2.test.mjs (new interaction tests)
- tests/factory-floor-ui.test.mjs (rendered toolbar/count/timing tests plus existing harness repair)
- tests/maintenance-machine.test.mjs
- tests/product-colors.test.mjs
- tests/production-recording.test.mjs
- tests/shift-time-windows.test.mjs
- tests/manufactured-output-phase4b.test.mjs
- tests/manufactured-output-phase4c2c-api.test.mjs

The last six are previously prepared compatibility repairs reused from the preserved candidate: CSS bootstrap, origin-check mock and obsolete Gantt palette assertions, not changes to those business workflows. The new fixture SQL and concurrency/HTTP scripts plus results are preserved in the evidence directory; never blindly repeat successful writes.

Repository documentation only:
- HANDOFF.md
- docs/historical-production-approval-v1.md
- docs/factory-floor-historical-v2.md (this report)

Exact SHA256 values are in changed-files.json. No application source or migration was promoted into the protected authoritative checkout/3000 environment.

Screenshots: owner-4222-en-1440.png, owner-4222-ar-1440.png, corresponding768/390 images; historical-excess-en.png; historical-recovered-ar.png. All are in the evidence directory. Standalone read-only comparison and ephemeral4250/4358/55628 acceptance processes are stopped after verification; data/scripts/results remain.4222/4304/55496 and4242 are left running.

STOP: owner manual acceptance only; no next development or checkpoint task.
