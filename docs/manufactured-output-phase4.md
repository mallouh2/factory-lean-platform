# 29 October2026 — Compensation/completion gap closed locally

The new20261029110000/114500/115500/120500 forward extensions implement the approved active same-job allowance, ended rejected-only linked replacement, exclusive mixed/replace-all coverage and safe unused-allowance transfer to Planning. Fresh completion actually executed through scheduling → Warehouse issue → exact4m input consumption →4m output → Quality → receipt. Actual browser cases received909/100/909m without changing original demand; separately reusing released4m for stock leaves original fulfillment capped by its independent demand link. Quantity and Scrap KG remain separate. Partial baseline100/50 has actual next2m allowance attribution, and pending inspection is distinct from accepted/received output. Changed Quality evidence, holds and irreversible source/commitment restrictions fail closed; no cancellation/revision bypass is added for new compensation work.

48 SQL assertions/23 expected rejections,4 real concurrency groups,22 focused Node tests, authenticated browser flows, TypeScript and isolated production build PASS.131 local migration files; all127 existing hashes preserved. Shipped gates FALSE, no hosted or Git writes. This closes the bounded compensation/completion paths, not a hosted release or approval of every historical Phase4 limitation. Current exact evidence/manifest and manual preview: [Production compensation report](production-quality-corrective-actions.md). Earlier partial findings below are historical.

# Manufactured output — Phase 4 completion and replacement

28 October follow-up: [Operational UX corrections](operational-ux-workflow-corrections.md) supersede only the affected Quality/dispatch/overdue-replanning/navigation presentation and contracts. Local verification is separate from owner acceptance; earlier dated evidence below remains historical. No hosted activation or migration edits.

26 October 2026. **PARTIAL OVERALL / LOCAL ONLY / SHIPPED GATE FALSE.** Phase4D completes supported legacy-screen detail/drill-through integration after Phase4C-2C. Unsupported physical states, hosted deployment/acceptance, full activation and owner acceptance remain separate work. This is not activation approval.

## Phase 4E — local end-to-end operational acceptance

**PASS locally for A/B/C supported scenarios**, with shipped gates still FALSE. A actual COMPLETE finishes original100m; B replacement fulfills100m and later stock-only recovery gives110m without duplicate demand; C Quality85/15, exact debit5/partial receiving2+3, unchanged allocation10 and new5 unassigned.35 scenario/browser/safety steps,13 negative checks,cross-factory denials and EN/AR390px PASS. No product source/migration fix; deterministic fresh PostgreSQL and normal actor logins/public protected commands,not desired final balance seeds. Full quantities,IDs,evidence,limits and next approval gate: [Phase4E acceptance](manufactured-output-phase4e-acceptance.md). Overall release/activation and unsupported physical reversal coverage remain separate.

## Phase 4D — legacy screen integration and drill-through

**COMPLETE locally for supported manufactured-output records.** Existing History retains its seven default columns, filtering/sorting, selection, Details, preferences and contextual export controls. Its Details now links exact Production entry → Quality inspection → Warehouse receipt → recovery/replacement decisions → original Production Item/request. The common contextual drawer reuses existing feature components. Back returns to the previous related record; closing leaves the original screen, selected row and filters mounted. Opening the real scheduling editor remains an explicit action through existing Planning, not a parallel scheduler.

Quality shows original technician classification independently from the latest authoritative result and accounting-applied classification. Original recording no longer presents its initial zero release as a current Quality release. Focused inspection hides the redundant one-record selector/pagination; applied classification, remaining demand and immutable history stay on demand. Warehouse retains all five operational tabs and ordinary receiving/reconciliation. Its receipt Details distinguish historical received quantities from server-provided stored/on-floor unfinished quantities. Stock-source Details offers links only when the protected source reader supplies an actual enrolled output ID; legacy/unattributed/non-production stock gets no invented Quality genealogy.

Planning retains its queue, Gantt, editor, reasons and Change/Cancel protections. Unfinished sources use single selection, toolbar Details and double-click Details instead of a per-row Actions column. Held active work is distinct from collapsible retired-decision history. Work links preserve source output, source entry, original item and selected work UUID. The original-order contextual view explicitly shows only the linked Production Item and technician-recorded progress, not a false complete-request item count, Quality-accepted quantity or received stock.

### Read contract and safety

New forward `20261026091412_manufactured_output_drillthrough_read_v4d.sql` is read-only:

- Exact entry filtering in existing Quality/Production readers; ordinary unfocused modes, status/recovery and options remain compatible.
- `manufactured_receiving_context` and `manufactured_completion_context` reuse current reader query definitions with the exact source filter applied before limits. Work optionally filters its exact UUID under that output. Scoped and ordinary projections are tested for exact equality. Existing private stock, finding/hold, receipt and demand functions remain calculation authority.
- Orders-only completion summary uses existing `output_work_demand`/`output_demand_received`, including child-work ownership, rather than client calculations.
- `manufactured_output_order_read` authorizes factory/Orders view and reads the actual enrolled item/request/product keys independently of a truncated snapshot.
- Existing source reader returns an enrolled output pointer; unfinished receipt groups expose stored and on-floor quantities from their actual lot. No physical label becomes a new universal requirement.
- New readers retain effective person/package authorization and disabled-gate behavior, revoke anonymous/public/service-role execution and grant authenticated execution only. The API validates UUID/context binding and uses the existing authenticated client/exact-number transport. Client permission checks merely control links; every destination reauthorizes in SQL. Cross-factory IDs return no records.

No writer, inventory movement, source allocation, reservation, Quality release, demand calculation, transfer, queue or saved business evidence changed. All ten existing protected writer definitions were fingerprinted before/after and remain identical. No concurrency suites repeated because execution contracts were not changed.

### Current verification

- **78 focused Node tests PASS:** 13 new navigation/API checks plus 65 affected recording/reconciliation/decision regressions. Exact UUID routing, independent permissions/factory scope, exact decimal transport, malformed/missing targets, bound work IDs and unchanged ordinary API routes are covered.
- **21 standalone PostgreSQL checks PASS:** exact output/entry/item/request/work relationships, ordinary-versus-focused projection equality, authoritative versus applied/received distinction, stored/on-floor values, unchanged original Good, stock-source pointer, held/retired work, cross-factory empty results, independent destination permissions, anonymous denial, shipped disabled behavior, and unchanged writer definitions.
- **TypeScript and final isolated optimized Webpack build PASS.** Actual authenticated local browser checks: History Details/selection/seven columns/export presence; Quality/receipt/Planning/original-order links; return without another History load; held scheduling unavailable; retired history accessible; source-stock links; five Warehouse tabs; EN and AR/RTL390px without document overflow. History and Warehouse double-click Details remain verified. No page exceptions/unexpected API errors; initial unauthenticated snapshot401 is expected.
- **Four actual HTTP403 read denials** under a separate restricted local fixture login: Quality, receiving context, completion context and original order. Responses contain only `permissionError`, no protected data. Browser read navigation leaves event, lot, finished-stock, order, work and late-gate digests unchanged. No business command was submitted by the browser checks.

Deterministic preview: original90 finished +10 unfinished; previous10 decision retired, new10 decision held; latest Quality94/6; applied/received90/10; stored unfinished10/on-floor0; remaining finished demand10. The unreceived extra four are not finished stock. Original gross Good remains90. This intentionally pending fixture demonstrates the distinction; it was not physically reconciled during Phase4D.

Local evidence/preview root: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4D-Preview-21cfaa60c36b4470a31e963c18611b5c`. Use reader-tests-final.txt, build-final.txt, typescript-final.txt, browser/results.json, screenshots and denials.json. Source-preservation/Node evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4D-796880aca01b45dea0d56307f47ad1cf`. Early read-projection alias/setup quoting and browser selector issues were corrected in the new local work; failed preparation evidence retained and its owned server stopped. No historical migration was edited and no successful operational transaction repeated. Normal synthetic login uses owner-restricted LOCAL-LOGIN.txt. This is original SQL behind the test-only loopback Auth/Data adapter, not hosted GoTrue/PostgREST acceptance.

Manual read verification: open `http://127.0.0.1:4220/`, use that preview's local owner credentials, then Production History → select row → Actions → Details → Quality inspection → Production receipt → Back → Recovery/replacement work → Original Production Order. Close to return to the same History row. In Warehouse stock Details, expand Sources and open the same receipt. Switch Arabic and inspect at390px. Review only; this phase does not authorize operational acceptance writes.

**Preserved:**112 local migrations/all111 preceding hashes unchanged; shipped manufactured-output/public capability and completed-shift late gates FALSE/schema0. Only disposable fixture helpers simulate the inactive workflow locally. Prior4219 and older previews untouched; new4220/4302/55494 bind only127.0.0.1. Export Reader, Design System, unrelated dirty work, development HEAD/index preserved. No hosted access, deployment, activation or Git writes. PRODUCT_DIFFERENTIATORS reviewed; no change to competitive claims.

**Remaining:** unsupported issued/consumed/shipped/committed or ambiguous reconciliation remains blocked by existing contracts. Legacy unenrolled records deliberately have no fabricated release/provenance; their active immediate-credit path remains unchanged while disabled. Hosted acceptance, multi-user operational acceptance, owner visual approval and activation require separate authorization. Do not begin unrelated polish, cleanup or activation.

Exact Phase4D manifest (29 files; no deletions):

```text
HANDOFF.md
docs/manufactured-output-phase4.md
src/app/api/manufactured-output/route.ts
src/components/FactoryApp.tsx
src/features/ManufacturedCompletion.tsx
src/features/ManufacturedOutput.tsx
src/features/ManufacturedOutputExplorer.tsx
src/features/ManufacturedReceiving.tsx
src/features/OutputDemandDetails.tsx
src/features/OutputRecordLinks.tsx
src/features/ProductionHistory.tsx
src/features/ProductionOrdersV2.tsx
src/features/ProductionPlanning.tsx
src/features/ProductionRecording.tsx
src/features/types.ts
src/features/warehouse-v1.css
src/features/Warehouse.tsx
src/features/WarehouseItemDetails.tsx
src/utils/output-navigation.mjs
src/utils/production-recording-v3.mjs
supabase/migrations/20261026091412_manufactured_output_drillthrough_read_v4d.sql
tests/manufactured-output-phase4d-api.test.mjs
tests/manufactured-output-phase4d.test.mjs
tests/manufactured-output-phase4d/before.sql
tests/manufactured-output-phase4d/browser.mjs
tests/manufactured-output-phase4d/denials.mjs
tests/manufactured-output-phase4d/integration.test.sql
tests/manufactured-output-phase4d/prepare-preview.ps1
tests/production-recording-full-app/backend.mjs
```

## Phase 4C-2C — Quality reconciliation API and UI integration

**COMPLETE locally for supported contracts.** Quality edits/splits existing classifications through the protected QUALITY command. Quality and Production details/notifications distinguish the latest authoritative finding from accounting-applied classification; pending reconciliation is never presented as pending Production approval or completed inventory movement. Original technician evidence and immutable history remain available. Acknowledgement remains informational.

Warehouse Production Receipts retains its existing navigation and quantity-based receiving. Its selected-record Actions now includes **Reconcile Quality adjustment**. Finished-to-unfinished requires selecting a physically identified source returned by the server and confirming physical separation. Unfinished reclassification uses the exact protected lot/location and a meaningful physical-identification attestation. UNCHANGED requires a reason only. The same protected command owns withdrawal, locks, permissions and immutable UUID receipt; no TypeScript inventory algorithm or new ledger exists. Corrected stock is credited only by subsequent ordinary, possibly partial receipts. Unknown responses retain the exact stored request and UUID; definitive stale revisions require refresh/review.

Planning marks affected completion/replacement work as held, disables scheduling that held work, and retains existing eligible Change/Cancel Decision forms and exact issued/started/locked/committed blockers. It never resizes an allocation or automatically creates/schedules a successor. Original shortage remains visible; a new six-unit decision is explicit. Quality, Warehouse and Planning authority remain separate in SQL.

### Necessary read-only contract extension

Forward migration `20261026082816_manufactured_output_reconciliation_read_v4c2c.sql` adds private `output_reconciliation_action` to the existing Warehouse reader. Earlier readers exposed accounting/findings but not the supported physical action/source choices. The helper calls the existing `output_reconciliation_spec`, reports its exact blocker, returns existing physically identified eligible finished sources or the exact unfinished lot/location, and exposes no independent authenticated execution grant. Existing protected writers and gates are unchanged; the command revalidates under its established locks. No new public RPC, security flag or business mutation is introduced.

### Verification and limitations

- 65 focused Node tests passed: six new API invocation/error cases, six presentation/exact-transport cases and 53 affected prior regressions. Authenticated calls are forwarded to original RPCs; malformed privilege fields, missing finding/revision, permissions, stale state, unsupported physical states and unknown outcomes are covered.
- Seven new standalone PostgreSQL reader assertions passed on a fresh 110-file executable chain (Export Reader excluded): B1 exact amount/identified source; no second action after apply; B2 retirement blocker; exact lot/location/amount after separate cancellation; Warehouse read denial; private-helper grant protection. Previous B1/B2 integrity/concurrency evidence is reused because their protected contracts were not edited. No broad concurrency suite repeated.
- Normal local owner login/browser workflow executed Quality 90 finished + 10 unfinished → finding 94 + 6; Planning cancelled the original wholly unissued ten; Warehouse withdrew four unfinished units; normal receiving confirmed two then two finished units. Observed stock was 90/10 → 90/6 + 4 awaiting receipt → 92/6 + 2 awaiting receipt → 94/6. Original demand still needs six; reserved zero throughout; original gross Good remains 90; exactly one RECONCILE and four lifetime receipt events (two original, two corrected), no residual mutation context. Final receipt deliberately lost its HTTP response and the form retried the same UUID successfully without a second credit. The Warehouse reconciliation committed during an earlier harness timing failure; its verified state was resumed without repeating that withdrawal.
- Three real authenticated local HTTP 403s: Quality finding, Warehouse reconciliation and Planning allocation using a separate restricted fixture login. Event/lot/balance/work digests unchanged. Browser also verified authoritative notification-reader data. EN desktop and AR/RTL390px forms exercised. Early harness failures were configuration/selector/timing issues, not claimed product failures; committed actions were inspected before continuing. No inventory transaction was repeated to manufacture a passing result.
- TypeScript and isolated optimized Webpack production build passed; the final status/mobile refinements also passed the final rebuild and read-only Production History/Warehouse AR390px smoke (no page/API errors; initial unauthenticated snapshot401 expected). Existing five Warehouse tabs, navigation, column preferences and exports were not redesigned.

Evidence/preview: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4C2C-Preview-66e9557e1c3347099868bbaf6faf8ca1` (reader-tests.txt, build logs, browser/results.json, denials.json, final-state.json). Preview `http://127.0.0.1:4219/`, adapter4301/PostgreSQL55493 bound to loopback. Normal local fixture credentials are owner-restricted in LOCAL-LOGIN.txt outside Git. This is original SQL behind a test-only Auth/Data API adapter, not hosted Supabase certification. Test helpers simulate the inactive predicate only in this disposable database; shipped manufactured-output/public capability and completed-work activation remain FALSE. Earlier previews untouched.

Remaining unsupported cases: issued/consumed/shipped/committed physical undo, multiple unresolved findings, ambiguous/multiple source reconciliation and unsupported partial original receipts. Exact reader/command blockers remain enforced. No allocation resizing, automatic replacement, purchased-material Quality gate, legacy cleanup or activation. Acknowledgement cannot release a hold. Owner visual acceptance and coordinated hosted deployment remain unperformed.

Files: manufactured-output API; ManufacturedOutput/ManufacturedCompletion/ManufacturedReceiving; shared OutputAccounting; scoped warehouse-v1 mobile rules; output-reconciliation presentation helper; exact-response transport allowlist; the read-only migration; two focused Node files and five local fixture/browser/SQL files; test-only adapter allowlist; this report and HANDOFF. All preceding 110 migration bytes, Export Reader, Design System and unrelated work preserved. No hosted access, deployment or Git writes.

Manual check: open4219, sign in using its LOCAL-LOGIN.txt owner account, then Quality → select the production record → Details (latest versus applied). Warehouse → Production Receipts → select record → Details shows confirmed94/6 and resolved status. Planning → completion/replacement shows retired ten, stored six and remaining demand six. Future writes require a fresh controlled fixture; do not replay the completed scenario as new work.

Exact C2C file manifest (19 files; no deletions):

```text
HANDOFF.md
docs/manufactured-output-phase4.md
src/app/api/manufactured-output/route.ts
src/features/ManufacturedCompletion.tsx
src/features/ManufacturedOutput.tsx
src/features/ManufacturedReceiving.tsx
src/features/OutputAccounting.tsx
src/features/warehouse-v1.css
src/utils/output-reconciliation.mjs
src/utils/production-recording-v3.mjs
supabase/migrations/20261026082816_manufactured_output_reconciliation_read_v4c2c.sql
tests/manufactured-output-phase4c2c-api.test.mjs
tests/manufactured-output-phase4c2c.test.mjs
tests/manufactured-output-phase4c2c/browser.mjs
tests/manufactured-output-phase4c2c/denials.mjs
tests/manufactured-output-phase4c2c/integration.test.sql
tests/manufactured-output-phase4c2c/prepare-preview.ps1
tests/manufactured-output-phase4c2c/read-smoke.mjs
tests/production-recording-full-app/backend.mjs
```

## Implemented

- Forward migration `20261025024857_manufactured_output_completion_v4.sql`: immutable links between the existing output/source, production request/item and material request. Original material origin is independent of current demand ownership. No additional inventory ledger.
- Protected `plan_manufactured_completion` supports COMPLETE for original demand, REPLACE using new production, and STOCK recovery of freed material. Effective factory/person/package permissions, exact quantities, revision, reason and immutable UUID intent are checked inside the factory/structure/row transaction. Reauthorization after lock waits prevents stale grants from authorizing work.
- COMPLETE reserves its exact source quantity for an ordinary linked material request. Warehouse issue moves stored quantity to the floor once, without consumption or finished credit. Production Start requires the issued source, capable resources and existing protected execution eligibility. Existing Planning scheduling, calendar, queue, locks and Maintenance guards remain in force; no automatic rescheduling or machine restart.
- V3 records recovery against its bound input lot. Actual input, discarded production units and Scrap KG remain separate. Existing input conservation is reused. Partial quantity processing leaves the rest available; partial operations produce a new unfinished group containing the remaining unordered operation set. Unperformed operations cannot silently disappear.
- Resulting output must be inspected/released by Quality and physically received before finished stock/demand changes. A child unfinished receipt inherits current demand; subsequent STOCK recovery retains material origin but has no original-demand allocation. Unsupported unit conversion fails safely.
- Sales incoming commitments for the original item convert to existing stock reservations at the linked finished receipt. Other Sales demand cannot take a completion forecast dedicated to that original demand. Recording, scheduling and physical issue do not fulfill the original shortage.
- Planning's protected reader shows source, operations, stored/unassigned quantities, receipt-based shortage, work and progress. The work record continues displaying original demand received/still needed after the input lot is consumed. Existing historical gross production remains historical, not rewritten as received stock.
- The existing Planning editor schedules capable completion work. EN/AR, RTL, mobile cards, reason/quantity/operation selection and durable same-UUID retries reuse current UI contracts. The recorder displays required actual input and discarded quantity for recovery. No new routing engine, physical-label mandate or non-production Quality gate.

## Acceptance evidence

Real PostgreSQL 17.11 on disposable loopback databases; original SQL grants/RLS and authenticated actors are exercised. Local browser authentication uses the existing test-only adapter, not hosted GoTrue/PostgREST.

| Layer | Verified result |
| --- | --- |
| Phase 4 PostgreSQL | 47 assertions: 10 integration, 23 scenarios, 14 Sales/source/reader checks |
| Affected Phase 2/3 PostgreSQL | 38 + 46 assertions passed on the final fresh chain |
| Concurrency/security | 7 groups passed: duplicate decision, competing allocation, repeated issue, repeated consumption, permission revocation during observed lock wait, private-table/read denial, disabled gate/context cleanup |
| Focused Node | 119/119 passed; affected Planning/Phase 4 subset 75/75 rerun after the final demand display change |
| TypeScript/build | Final isolated TypeScript and optimized Next.js Webpack production build passed |
| Browser | Normal owner login, real shortage reader, completion decision, existing Planning schedule, Arabic 390px and real recovery recording exercised; final authenticated read-only checks passed without repeating writes |

Exact conservation examples:

- Target 100, received finished 90, unfinished 10: issue/record leaves original received demand 90; inspected receipt of recovered 10 changes it to 100 once.
- Split processing 4 then 6 conserves the original input. Cutting + Printing to Printing retains ten physical units on the successor lot, zero on the consumed parent, then fulfills only after final Quality/receipt.
- Replacement fulfills original demand once. Later freed-material recovery with input 10, output 9, discarded 1 and Scrap 0.25 KG yields total stock 109 while original fulfilled demand remains 100.
- Sales stock/reserved 90/90 plus incoming 10 becomes stock/reserved 100/100 at receipt, available zero. A competing Sales order cannot take dedicated completion supply.
- Two source shares of 10 and 7 remain separate despite compatible Warehouse presentation; replacement frees only its selected share. Package/direct authorization and cross-factory denial are covered.

Final SQL evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4-SQL-676c2c02df6b46feaefa92ef2b230e7c\results`. Its server is stopped and disposable data removed; scripts/results remain. Earlier final-chain evidence preceded the last two reader assertions. Node/preservation evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-Phase4-3cc8b8e0efdf46ca9b5b7cc1240fe205`.

Browser qualifications: the first fixture's shift expired during testing; the existing next-shift eligibility guard was respected. A second fixture was created without rewriting the first. The complete second flow reached successful recording, but the final HTTP assertion found the local adapter omitted `production_plan_revisions`. The adapter now exposes that read with original authenticated SQL/RLS. A read-only continuation verified history HTTP 200, consumed input 10, received finished 0, original demand received 90/still needed 10 and no page exceptions. No issue/start/record transaction was repeated to obtain a clean result. Initial unauthenticated snapshot HTTP 401 is expected. Browser `results.json` is older evidence; use `http-diagnostic.json`, `recording-confirmed.png` and `final-read-results.json` for the final sequence.

## Remaining scope and activation blockers

1. **Post-allocation Quality changes:** Phase4C-2A supersedes the original inability to publish a finding. B1 supports source-identifiable finished withdrawal. B2 adds separate authorized Phase4B whole-decision retirement followed by Warehouse reconciliation of one fully stored unfinished group and confirmed corrected receiving. Safe reduction, changed operations and splits are supported without resizing existing work. Issued/consumed/committed or ambiguous states, multiple unresolved findings remain protected/deferred; C2C now exposes supported API/UI actions; no historical physical facts are reversed.
2. **Pre-issue cancellation/change — resolved locally in Phase4B-2:** wholly unissued, never-started COMPLETE/REPLACE work can be retired through the protected decision command below. Generic material/order cancellation remains blocked. Issued/started work, partial undo, STOCK decision cancellation, Quality amendments and physical returns remain outside this restricted contract.
3. **All-Scrap recovery — resolved locally in Phase 4A:** issued, source-bound recovery can consume input with zero usable output and positive measured Scrap KG. Empty usable groups are retained in immutable recording evidence; no zero-quantity physical lot, Warehouse receipt or finished credit is fabricated. See the Phase 4A evidence below.
4. Whole-system activation still requires coordinated legacy consumer/counter cutover and separate hosted/user acceptance. The new Planning shortage is receipt-based; old gross-production displays are not certification of demand fulfillment. No historical synthetic reconciliation/backfill is required.
5. Work cards show the latest 100 work records, with 50-row source paging. Multi-line automatic routing, arbitrary conversion and physical roll/coil traceability are not claimed. New linked work has no automatically inherited business deadline; planners must inspect the original request. The current dialog exposes source/order identifiers and Quality/allocation history, not a complete linked original-order/Quality drill-through.
6. Existing Planning/Maintenance enforcement is reused; this task did not repeat the complete Maintenance/transfer concurrency campaign. Cross-browser, physical mobile, screen-reader and hosted Supabase acceptance remain unverified.

## Retained local preview and manual next steps

URL: **http://127.0.0.1:4217/**. Owned app/Auth adapter/PostgreSQL ports: 4217/4299/55490, bound to loopback. This is a separate app copy; 4207/4214/4216 were not modified. Root:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P3-Preview-d7dea0ad343643dbaac4efcfcabfa9a1` (the inherited P3 directory name does not identify its current Phase 4 fixture).

Normal synthetic owner credentials are in its owner-restricted `LOCAL-LOGIN.txt`; do not use hosted credentials. The private test predicate permits manufactured output only in this disposable fixture; shipped capability remains FALSE and completed-shift late recording remains disabled. No operational activation is authorized or claimed.

Current second fixture: original **PO-0000066**, recovery **PO-0000068** (`02f093db-2030-4e95-8ef3-805cbd26027c`), source lot `9bf457ff-82ac-469a-b10e-ea48ce941b26`, material request `ef0de4c2-ea65-42fe-bd9d-d12978b45781`, line **Maintenance test line**, Product **Pipe**, missing configured operation **Main extruder**. Names are deterministic synthetic configuration; they are not claims about a physical printing machine.

1. Sign in normally, open Planning: recovery input processed 10, finished received 0, original demand received 90/still needed 10. The job remains active; no duplicate recording is needed.
2. Open Quality's manufactured-output inspection and select the recorded output of PO-0000068. Inspect/release the actual finished 10 through the existing form.
3. Warehouse → Production Receipts → physically receive that released 10. Only then should original demand show 100 received/0 still needed and finished stock increase from 90 to 100.
4. Finish the recovery item through normal Production execution. Do not repeat its input recording. Test original-remaining-operation and replacement paths using a separate disposable fixture, not by rewriting this completed consumption.

The first fixture and its work remain preserved separately in `runtime-first-fixture.json` and `FIRST-FIXTURE-LOGIN.txt`. Browser/SQL details are local evidence, not automatic owner approval.

## Phase 4A — all-Scrap unfinished recovery, 25 October 2026

**COMPLETE for this bounded local gap; overall Phase 4 remains PARTIAL and inactive.** No work on allocation cancellation/revision, legacy displays, broader Quality workflows or hosted activation.

Root cause: the Phase 2 declaration required `total > 0`, and `private.manufactured_outputs.quantity` also required a positive usable quantity. The client `outputGroups` helper rejected an empty list before the server was reached. The underlying input processor already supports `input = Good + discarded + unfinished`; this arithmetic and its existing consumed movement were reused.

Forward migration `20261025171342_manufactured_output_all_scrap_recovery_v4a.sql` changes only the existing recovery validator, declaration body and private output evidence constraint. The exception requires an issued/received source-bound COMPLETE/STOCK work item, positive actual input equal to discarded production units, zero Good/unfinished, no usable output groups and finite positive measured Scrap KG. An ordinary recording or replacement job cannot use this exception. The declaration must belong to the current protected recording transaction. Zero usable quantity is immutable evidence of the failed manufacturing result, never a new physical stock lot.

The existing V3 form supplies its recovery evidence to the same group validator. It accepts empty groups only for a valid all-discard recovery, retains exact numeric transport and the durable UUID receipt/status recovery. Missing/zero/negative/non-finite Scrap evidence and unsupported quantities reject. KG is the entered measured value; no Meter/Piece-to-KG equality or inferred default mass was introduced. Existing configured units and lower-level conservation rules remain authoritative.

| Example state | Stored input | Floor input remaining | Finished stock | Usable recovered output | Scrap | Original finished shortage |
| --- | --- | --- | --- | --- | --- | --- |
| Before issue | 10 Meter | 0 | 90 Meter | 0 | 0 KG | 10 Meter |
| Issued | 0 | 10 Meter | 90 Meter | 0 | 0 KG | 10 Meter |
| All-Scrap committed | 0 | 0 | 90 Meter | 0 | 0.75 KG measured | 10 Meter |
| Same UUID retried | 0 | 0 | 90 Meter | 0 | Same 0.75 KG | 10 Meter |

Original demand allocation is not released or redirected. The work can finish after its input is fully processed even though its usable yield is zero. No replacement work is generated. Original entry, source link, issue, one consumed movement, actor/time and immutable receipt retain the evidence. A changed payload with the same UUID rejects; a new UUID cannot reuse consumed input. Public activation capability remains FALSE and the completed-shift activation table remains disabled/schema0.

**Final validation:**

- 45 new PostgreSQL assertions PASS, including full all-Scrap, invalid KG, overconsumption, source mismatch, UUID conflict/recovery, no stock/receipt, exact remaining demand, finished execution, unauthorized/cross-factory calls and no automatic replacement.
- Partial all-Scrap consumes only 4 of 10; the remaining 6 later produces 3 finished and 3 unfinished. After Quality/receipt, original demand received is93/still needed7. Effective package grants authorize the actual worker recording; denied access changes no source quantity.
- 38 affected Phase2 +10 Phase4 integration +23 Phase4 scenario assertions PASS. These retain full usable recovery, partial operations/unfinished output, input issue and replacement/source rules. No broad platform suite.
- Two actual concurrent-write scenarios PASS with observed lock waits: the same UUID replays one consumption/Scrap entry; distinct UUIDs cannot consume the exhausted source twice. The authenticated role's unauthorized attempt also rejects without consuming source.
- 49/49 focused Node tests PASS: all-Scrap group validation, exact KG transport, retained UUID intent, existing positive/unfinished cases, V3 retry/recovery and existing UI contracts. Final TypeScript and isolated optimized Next.js Webpack build PASS. No browser/hosted or visual-layout acceptance is claimed for this validation-only UI change.

Final SQL evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4A-SQL-6173451d2b0a44d8860194883bcd247d\results`. Dedicated PostgreSQL17.11 on127.0.0.1:55491, verified database `factory_lean_quality_local`. The fresh complete chain excluded Export Reader. Before fixtures, the shipped manufactured-output predicate and late-recording gate were verified FALSE; RPC/private-table grants were checked. Disposable fixture-only predicates permit exercising the inactive path. Owned test server stopped and data removed; scripts/logs retained. Standalone PostgreSQL with test identities is not hosted Supabase Auth/PostgREST proof.

Node/build and task-relative preservation manifest: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-Phase4A-66c6dd95e2d84128b2263bb521332843`.

Exact Phase4A files (relative to this repository):

- `supabase/migrations/20261025171342_manufactured_output_all_scrap_recovery_v4a.sql` (new)
- `src/utils/manufactured-output.mjs`
- `src/features/ProductionRecordingV3.tsx`
- `tests/manufactured-output-phase4a.test.mjs` (new)
- `tests/manufactured-output-phase4a/integration.test.sql` (new)
- `tests/manufactured-output-phase4a/concurrency.mjs` (new)
- `tests/manufactured-output-phase4a/run-local.ps1` (new)
- `docs/manufactured-output-phase4.md`
- `docs/PRODUCT_DIFFERENTIATORS.md` (remove the now-outdated zero-output limitation only)
- `HANDOFF.md`

106 local migration files; all105 preceding migration files remain byte-identical. Existing active posting, protected allocation/cancellation behavior, Quality authority, activation flags, Export Reader, Design System and other dirty work preserved. Existing previews were not updated or restarted. No hosted access, deployment, Git write or feature activation. Stop after Phase4A.

## Phase 4B-2 — protected decision revision, 25 October 2026

**COMPLETE for the approved restricted local scope; overall Phase4 remains PARTIAL and inactive.** No reversal of physical work or relaxation of post-allocation Quality amendments. The original Phase4/4A checkpoints above are historical evidence; this section supersedes their absence of a cancellation path.

Forward `20261025190956_manufactured_output_decision_revision_v4b.sql` adds RETIRE events to the existing private immutable output history, with one retirement per work item and the original UUID intent/result. `manufactured_completion_work` remains immutable. The transaction-private REVISION context temporarily excludes the retiring work while the existing creation primitive validates its successor, then the immutable event becomes the permanent evidence. No new stock/Scrap ledger or generic workflow engine.

`revise_manufactured_completion` accepts CANCEL or CHANGE, exact source-output revision and a reader-provided state containing material revision, Planning revision, schedule/lock and execution facts. CHANGE retains quantity and origin/demand, creates a new identity through `plan_manufactured_completion`, and leaves it unscheduled. CANCEL creates no replacement. `output_work_allocations` and the shared live-work predicate drive creation limits, reader totals and the underlying DISPOSITION entitlement; historical events remain readable without reserving the quantity again.

Authorization uses existing effective factory scope, Orders view/edit, Orders create for CHANGE, and Warehouse issue when a material request must be cancelled. Permissions are checked again after lock waits and before saving the result. The actor never gains Warehouse authority through the wrapper. Factory advisory → structure/fulfillment → source/lot/work/request rows retain existing lock discipline. Same UUID/actor/intent replays the complete result even after retirement; changed intent rejects. Revision/state conflicts and any failed successor roll back all changes.

Only planned, never-started work with no entries/output and a wholly unissued REQUESTED material request qualifies. Actual issue timestamps, movement pointer and existing issue-command evidence are checked, so a REQUESTED label alone cannot erase physical issue history. Current whole-request issue behavior is unchanged. Source inspection/receipt is permitted; downstream output/Quality/receipt is blocked. Replacement reversal also requires physically stored, uncommitted input and no dependent STOCK recovery; direct Sales incoming on the retiring item blocks the command. Original-demand commitments are preserved.

Scheduled work is unscheduled by the existing `revise_product_plan`, with required reason and immutable history. Locks and elapsed planned starts reject; no automatic unlock or slot transfer. The original request/item remains in history, cancelled. Retired work cannot be generically reactivated, scheduled, issued, recorded or deleted. Existing execution guards may reject first with their original error. The new command's newly exercised supply-cancellation branch exposed an existing `reason=reason` ambiguity; the forward migration replaces only that assignment with the identical payload normalization. Supply authorization, revisions, audit and state rules remain authoritative.

The existing Planning work cards expose server-authorized Change Decision/Cancel Decision, explicit blocking reasons and a single reason dialog. The dialog displays original demand, work, quantity/unit, material status and unscheduling consequence. REPLACE→COMPLETE uses current authoritative missing operations. Durable session storage retains both creation and revision UUIDs; an unknown response is retried with the same intent. Retired work remains visible with reason/successor history. EN/AR/RTL and existing dialogs/tokens are reused.

**Final evidence:**

| Verification | Actual result |
| --- | --- |
| New PostgreSQL | 79 assertions: 58 transition/authorization/rollback, 21 commitment/physical/generic-guard checks |
| Affected PostgreSQL | 130 assertions: 45 Phase4A, 38 Phase2, 10 Phase4 integration, 23 Phase4 scenarios, 14 Sales/source checks |
| Concurrency/security | 10 groups PASS, including 8 observed lock-wait scenarios: same UUID, competing decisions, both issue outcomes, both Start outcomes, Planning revision and Warehouse permission revocation; authenticated cross-factory and disabled-gate checks |
| Node | 57/57 PASS: 8 new API/transport tests plus 49 affected recording/recovery checks |
| TypeScript / build | Isolated TypeScript and optimized Next.js Webpack production build PASS; built application inputs match final source |
| Browser | 4 full-app groups PASS: normal synthetic login/reader, COMPLETE→REPLACE, Arabic390px REPLACE→COMPLETE, committed cancellation with lost response/reload/same-UUID recovery |

SQL uses the existing portable PostgreSQL17.11 runtime on verified disposable `factory_lean_quality_local`,127.0.0.1:55491. Fresh chain executes106 migrations, excluding Export Reader. Before fixtures the shipped manufactured predicate, late gate/schema0 and RPC/private-table grants are checked. Test fixture predicates alone exercise the inactive writer. The concurrency suite restores the predicate FALSE; context count zero. Server stopped, data removed, scripts/logs preserved. This is standalone PostgreSQL/authenticated-role evidence, not hosted Supabase Auth/PostgREST acceptance.

Final SQL evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4B-SQL-6877da29b02c458ea21092866f1dd781\results`.
Task-relative preservation, Node, TypeScript/build logs: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4B-18b7282ee23f47f9b5765ab6c011fbf0`.

Separate built preview: **http://127.0.0.1:4218/**, Auth adapter4300/PostgreSQL55492, loopback only. Root `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4B-Preview-01b627eeba1d4ccfb48a8452fd451c67`; owner-restricted `LOCAL-LOGIN.txt` contains only generated local test credentials. No hosted credentials. Browser logs/screenshots in `browser/`; no page exceptions. The deliberately aborted response tests recovery, not an application fault; the initial unauthenticated401 is expected. Existing `next start` emits its standalone-output startup warning but served the complete tested application; no deployment is implied.

Browser final state: received90, stock90, stored/physical10, three retired decisions, zero live allocations, zero contexts and zero enabled late gates. There is still a10 Meter finished shortage. No issue, Scrap, production or additional receipt was generated by these revisions. Browser private fixture predicate alone permits testing; shipped capability remains FALSE. Previous4217 and other previews were not updated/restarted.

Manual check: sign in normally using this new preview's local credentials → Planning → Finish the remaining order. Historical work cards show cancellation reasons. To exercise a new decision, use the still-stored10 and create COMPLETE, then choose Change Decision or Cancel Decision before issue. Review the reason and scheduling warning. No source can be issued twice or become finished stock through the decision form.

Exact Phase4B-2 file manifest:

- `supabase/migrations/20261025190956_manufactured_output_decision_revision_v4b.sql` (new)
- `src/app/api/manufactured-output/route.ts`
- `src/features/ManufacturedCompletion.tsx`
- `src/utils/production-recording-v3.mjs`
- `tests/production-recording-full-app/backend.mjs` (test adapter allowlist only)
- `tests/manufactured-output-phase4b.test.mjs` (new)
- `tests/manufactured-output-phase4b/integration.test.sql` (new)
- `tests/manufactured-output-phase4b/guards.test.sql` (new)
- `tests/manufactured-output-phase4b/concurrency.mjs` (new)
- `tests/manufactured-output-phase4b/run-local.ps1` (new)
- `tests/manufactured-output-phase4b/prepare-preview.ps1` (new)
- `tests/manufactured-output-phase4b/browser.mjs` (new)
- `docs/manufactured-output-phase4.md`
- `HANDOFF.md`

107 local migrations; all106 preceding files, Phase4A, Export Reader and Design System preserved. Differentiators reviewed: existing manufacturing/WIP parity classification still applies, no new competitive claim or edit warranted. No hosted access, feature activation, deployment, Git commit/push/staging/reset/branch operation. Stop after Phase4B-2. Separate authorization is needed for post-allocation Quality revision, legacy consumer/drill-through work or eventual activation/hosted acceptance.

## Phase 4C-2A — authoritative findings and operational holds, 26 October 2026

**COMPLETE for bounded backend Batch 1 / LOCAL ONLY / INACTIVE.** This is not completion of physical post-allocation reconciliation or Phase4 as a whole. No application UI was changed or activated.

Root cause: both the Quality command and `output_reconcile` rejected any historical DISPOSITION. Inventory readers also treated the latest Quality result as applied accounting. Forward `20261026055212_manufactured_output_quality_holds_v4c2a.sql` separates those facts using the existing immutable QUALITY events. No new inventory, Scrap or notification ledger, mutable finding table, user-facing activation control or background job.

`output_finding` returns the latest inspected result. `output_quality` returns the latest safely applied result, retaining correction invalidation. Supported pre-allocation reconciliation continues through the unchanged `output_reconcile`. Only its three known physical/dependency blockers become pending; its exception subtransaction rolls back any attempted movements. Unexpected SQL errors propagate and roll back the command. Existing authorization, immutable UUID intent/replay, source revisions, final permission checks and original technician evidence remain protected.

A pending event records `accounting_applied=false`, previous applied revision, blockers and affected source-group quantities. It is authoritative immediately, with `requires_production_approval=false`. The existing Quality-event notification/per-person ACK mechanism delivers it to Production once. ACK and subsequent findings cannot clear an unresolved hold. Physical application/hold resolution requires the separately authorized Phase4C-2B contract; this batch exposes no clearing/reconciliation command.

`output_hold_rows` derives cumulative holds from pending events and propagates affected work dependencies to child manufactured output. Changed/decreased/deleted groups are held conservatively as whole source groups; a finished group holds its entry-bound finished source. Unchanged groups remain usable. A pending new group is not applied stock, a received lot or additional allocated work. The 90/10→85/15 example retains physical/applied stock90 and stored10, preserves the unchanged ten allocation, records the extra five as inspected-only and holds the affected finished source. No extra receipt, Scrap or production is fabricated. Consumed input and shipped quantities are never restored.

Protected boundaries:

- `plan_manufactured_completion` and the private DISPOSITION primitive reject held groups.
- `output_material_guard` and `output_lot_guard` reject stale issue/receipt/negative lot deltas; issue and source consumption cannot bypass the existing ledgers.
- `output_work_guard` rejects Start; `output_recovery_validate` rejects recording against held work. Related pre-receipt Production corrections cannot invalidate a pending finding/hold.
- `receive_manufactured_output` rejects held groups and still selects only the applied Quality release. New unapplied groups have no receipt entitlement.
- `source_assign_reservation`, `reserve_finished` and `source_movement` enforce holds for source assignment, positive reservations and every negative finished movement, including Sales dispatch, finished-material issue, adjustment and old pooled clients. Direct table writes remain unavailable to authenticated callers.
- If affected production stock is still unidentified, its Product/unit unattributed pool is conservatively unavailable; no batch is guessed. Separate identified sources remain usable. Raw balances, receipts and existing reservations remain unchanged. Free stock excludes held stock and only non-overlapping commitments, preventing double subtraction.

The existing structure/fulfillment transaction lock serializes publication with downstream work, including entry points that do not acquire the factory advisory lock. No structure→factory acquisition was introduced. Existing public authorization and post-wait checks remain. Two indexes support pending-event and work-genealogy lookups. New helpers are private, explicitly revoked from public/anon/authenticated/service_role; existing RPC grants and RLS remain unchanged.

Readers add explicit finding/applied/pending/held/blocker data. Inspection/history/Production notifications show the authoritative finding; Warehouse receiving uses applied classifications and actual receipt movements. Completion and finished-source selectors exclude held availability; Start readiness adds a separate `quality_hold` fact without rewriting physical/queue readiness. Forecasts exclude held work/pending receipts, while original Sales commitments remain visible. Shared Warehouse availability/projections account for holds. External/opening receipt posting is untouched: the existing receipt-time optional reservation skips held supply rather than rejecting a valid non-production receipt. No Purchasing command or inbound Quality requirement was added.

Final validation on the exact frozen SQL/test inputs:

| Layer | Result |
| --- | --- |
| New PostgreSQL | 59 assertions PASS: findings/applied separation, unchanged technician and work evidence, UUID conflict/replay, notifications/ACK, source/issue/Start/consumption/receipt/dispatch denial, transitive downstream holds, unchanged ten allocation, safe existing compensation, reservation overlap, separate same-Product source, unidentified pool fallback, external receipt, unordered operations, split/REPLACE, direct/package permissions, factory isolation and unexpected-error rollback |
| Affected PostgreSQL | 209 assertions PASS: Phase2 38; Phase4 integration10/scenarios23/Sales14; Phase4A45; Phase4B58+21 |
| Concurrency/security | 14 groups PASS, with13 observed lock waits: same UUID; competing findings; both issue, Start, source-assignment, dispatch and actual Sales approval outcomes; Quality edit revoked during wait; disabled gate/context cleanup |
| Node | 53 focused existing tests PASS: Phase2, Phase4A/4B and recording UI/intents/exact transport |
| TypeScript/build/browser | Not rerun: no application, API, TypeScript, dependency or UI changes. No hosted/browser acceptance claimed |

SQL evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4C2A-SQL-a2083db618fa440cba5f80c12ab2b7a5\results`. Existing PostgreSQL17.11, disposable database `factory_lean_quality_local`,127.0.0.1:55491; original grants/RLS and authenticated-role concurrent RPCs. Fresh107 executable migrations exclude Export Reader. Shipped predicate/grants verified before the test-only fixture override; manufactured predicate restored FALSE and late activation remains FALSE/schema0. Owned server stopped and disposable data removed; scripts/results retained. Standalone PostgreSQL is not hosted Supabase Auth/PostgREST acceptance.

Task preservation/Node evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4C2A-ff81aae7eb5440d292d02fcf2e7a0f5e`. Exact files:

- `supabase/migrations/20261026055212_manufactured_output_quality_holds_v4c2a.sql` (new)
- `tests/manufactured-output-phase4c2a/integration.test.sql` (new)
- `tests/manufactured-output-phase4c2a/concurrency.mjs` (new)
- `tests/manufactured-output-phase4c2a/run-local.ps1` (new)
- `docs/manufactured-output-phase4.md`
- `HANDOFF.md`

108 local migrations; all107 preceding file hashes unchanged. Existing active behavior without findings, Export Reader, Design System, unrelated work and prior previews preserved. Differentiators reviewed: expected manufacturing parity remains, no new comparative claim. No hosted access, deployment, activation, Git staging/commit/push/reset/stash/branch changes. Remaining: Phase4C-2B physical reconciliation/cancellation orchestration, Phase4C UI, legacy integration/drill-through and eventual hosted/user acceptance. Issued/consumed/shipped corrections remain recorded and held, not physically undone. No automatic replacement, Scrap KG adapter or late-recording activation. Stop after Batch1.

## Phase 4C-2B1 — safe physical reconciliation, 26 October 2026

**COMPLETE for the first bounded backend reconciliation path / LOCAL ONLY / INACTIVE.** No allocation revision, UI integration or activation. The historical Phase4C-2A section records its original no-resolution boundary; this section supersedes that boundary only for the following safe path.

Forward `20261026063417_manufactured_output_safe_reconciliation_v4c2b1.sql` adds authenticated `reconcile_manufactured_output(factory,target,finding,payload,expected_revision,request_id)`. `finding` is the immutable QUALITY event UUID, exposed by protected accounting readers; mutation UUID is independent. Payload contains only `source_id`, `physical_confirmation=true` and a meaningful reason. The command derives the exact quantity from reviewed classifications, not a caller-supplied stock delta. Effective factory scope and Warehouse view/edit are required before and after locks. Quality edit alone grants no Warehouse authority. Warehouse actors do not approve or rewrite the Quality finding.

Supported delta: one fully received finished group decreases (or disappears), exactly matching one new separately identified, fully Quality-released unfinished group. Every other old group, including quantity, release, unordered operations and restriction, remains unchanged. Rejected quantity does not change. The candidate must be the current authoritative, single unresolved finding, without an inherited parent hold. Source entry/Product/unit, physical identification, available identified quantity, aggregate unreserved quantity and immutable receipt history are rechecked. Existing completion/replacement links and material requests are not changed, cancelled, resized or superseded.

The factory advisory → fulfillment/structure → output/source/lot → original item lock discipline is retained. Existing `output_reconcile` performs the exact debit and records the existing manufactured-output adjustment. A transaction-private APPLY_FINDING context, unavailable to application callers, permits only the validated source-bound `quality_rejection` movement and exact quantity through the existing hold guard. All ordinary holds and pool restrictions remain enforced. The new immutable RECONCILE event links the finding, old/new groups, mutation intent, quantity and the original finished movement. Existing event movement constraints explicitly allow that audited reconciliation movement while preserving the exact RECEIPT and other-event rules. No second ledger, Scrap KG record or manufacturing event.

Durable stages for the 100 Meter example:

| Stage | Net finished received / stock | Stored unfinished | Pending handoff | Existing allocation | Finished demand still needed |
| --- | --- | --- | --- | --- | --- |
| Finding pending | 90 / 90 | 10 | Inspected finding only | 10 | Accounting10; finding requires reconciliation |
| Withdrawal committed | 85 / 85 | 10 | 5 released, not received | Same10 | 15 |
| Warehouse confirms2 | 85 / 85 | 12 | 3 | Same10; new2 held | 15 |
| Warehouse confirms remaining3 | 85 / 85 | 15 | 0 | Same10; additional5 unallocated | 15 |

After the withdrawal, the applied accounting classification/release entitlement references the existing immutable finding, while the overall reconciliation remains AWAITING_RECEIPT. The remaining finished85 is no longer held by the fulfilled withdrawal obligation. A separate whole-group hold protects the new handoff, including partially received quantities, until all5 are received. This conservative batch does not allocate or issue a partial handoff. The existing `receive_manufactured_output` accepts only this exact protected, current released entitlement with normal physical confirmation, location, quantity caps, original demand and source genealogy. Each receipt links back to the reconciliation/finding and its original unfinished movement/lot. The final receipt resolves the handoff by immutable received-quantity evidence; no new manufacturing event or synthetic return is invented.

`output_quality` projects the applied finding after withdrawal; original events are unchanged. `output_accounting` distinguishes finding/applied revisions, PENDING/AWAITING_RECEIPT/RECONCILED, remaining quantity, current reconciliation and historical handoffs. Holds clear per resolved finding/group, never by a newer finding or ACK. Further inspection during an incomplete handoff blocks obsolete receiving and keeps that older handoff visible. A completed finding no longer counts as unresolved; other pending findings and ancestor holds are not erased. Exact UUID replay returns the original committed withdrawal/receipt even after later progress; current readers supply the current stage. Different intent or stale revision rejects. Same-finding/new-UUID repetition cannot debit again.

Final local evidence:

| Layer | Result |
| --- | --- |
| New PostgreSQL | 60 assertions PASS: 90/10→85/15, separate2+3 receiving, original allocation/demand/source conservation, no automatic work or Scrap, immutable original entry, movement links, retry/conflict/rollback, identified-only5, insufficient/reserved/shipped/unidentified stock, Warehouse/package separation, stale/multiple findings, deferred allocated classification, full finished-share removal, exact fractional quantities and factory isolation |
| Affected PostgreSQL | 268 assertions PASS: Phase2 38; Phase4 integration10/scenarios23/Sales14; Phase4A45; Phase4B58+21; Phase4C-2A59 |
| Concurrency/security | 12 groups PASS,11 observed lock waits: same/different withdrawal UUIDs, same/competing partial/final receipts, both source assignment and dispatch orderings, both inspection orderings, post-wait Warehouse edit revocation and disabled gates/context cleanup. Pre-withdrawal stock-out/assignment attempts remain denied; post-withdrawal operations use only remaining eligible stock |
| Node | 53 affected recording/exact transport/Phase2/4A/4B tests PASS |
| TypeScript/build/browser | Not rerun: no application, API, TypeScript, dependency or UI changes. No hosted/browser acceptance claimed |

Fresh108 executable migrations exclude Export Reader. Existing portable PostgreSQL17.11 on verified disposable `factory_lean_quality_local`,127.0.0.1:55491; authenticated-role RPCs for concurrency, original grants/RLS. The isolated fixture alone overrides the private predicate. Shipped manufactured-output and late gates verified FALSE/schema0; predicate restored FALSE, contexts zero. Owned server stopped and disposable data removed, logs/scripts retained. Final SQL evidence:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4C2B1-SQL-dfc330050c7c411f87fa11ba1bdf1aeb\results`.

Task baseline, Node and preservation evidence:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4C2B1-fe4568abe5984ada8b2f99daba2710d4`.

Exact six-file task scope:

- `supabase/migrations/20261026063417_manufactured_output_safe_reconciliation_v4c2b1.sql` (new)
- `tests/manufactured-output-phase4c2b1/integration.test.sql` (new)
- `tests/manufactured-output-phase4c2b1/concurrency.mjs` (new)
- `tests/manufactured-output-phase4c2b1/run-local.ps1` (new)
- `docs/manufactured-output-phase4.md`
- `HANDOFF.md`

Unsupported/B2 or later: changed/decreased/deleted allocated unfinished groups; changed operations/restrictions; allocation cancellation/resizing/splitting; issued/consumed undo or shipped-stock recall; inherited holds; multiple unresolved findings; more than one changed finished/new handoff group; partially received original finished shares; unfinished quantity not fully Quality-released; other rejection/Scrap changes. These return precise blockers and retain the authoritative finding and holds. Multiple/new findings during an incomplete handoff require later protected resolution, not a forced receipt. No generic reversal or automatic discrepancy processing. The new SQL RPC is backend-only; Next.js command/UI integration is deferred.

109 local migrations; all108 previous hashes preserved. Development HEADbb0d20e5dd433b896dd319f56e75f0d9eb5d2862 and empty index preserved. Export Reader, Purchasing, Design System, unrelated work and running previews untouched. Differentiators reviewed: ordinary manufacturing parity remains, no new competitive claim. No hosted access, deployment, activation, Git staging/commit/push/reset/stash/branch change. OverallPhase4 remains PARTIAL. Stop after B1; B2/UI require separate authorization.

## Phase 4C-2B2 — pre-issue allocated unfinished reconciliation, 26 October 2026

**COMPLETE for the bounded local backend / INACTIVE — STOP.** This section supersedes B1's exclusion of safe pre-issue allocated unfinished changes. No generic reversal, automatic cancellation, new allocation engine, UI integration or activation.

Forward `20261026072144_manufactured_output_allocated_reconciliation_v4c2b2.sql` extends the existing B1 specification and `reconcile_manufactured_output` command. Quality publishes an authoritative finding through the existing command. The affected live allocations are read through `output_affected_allocations`, reusing the exact Phase4B `output_work_revision_state` eligibility/state rather than computing another cancellation policy. Planning details require Orders view; Warehouse authority does not expose unrestricted Planning state.

**Separate authorized actions:**

1. Quality records its immutable finding/reason; it never calls Planning or Warehouse on that actor's behalf. Existing notices/ACK remain informational.
2. An actor with the existing Orders and linked-request Warehouse permissions calls Phase4B `revise_manufactured_completion` with CANCEL, fresh source/Planning/material state and UUID. Whole work/request retirement, protected unscheduling, required reason/history, lock/elapsed/started/issue/dependency checks remain unchanged. This task adds no cancellation wrapper. Holds and physical quantities persist after cancellation.
3. Warehouse calls the existing reconciliation RPC with the finding UUID, current output revision, independent mutation UUID and source-lot payload. New mode UNFINISHED_RECLASS requires `source_lot_id`, exact recorded `source_location`, `physical_confirmation=true`, a meaningful `identification_note` attesting actual segregation/identifiability, and reason. No source is inferred from pooled quantities or a software selection alone. Warehouse must not attest identification if the physical sources are mixed/unknown.
4. Existing `output_reconcile` withdraws only the changed amount from the old stored unfinished lot and records its existing negative unfinished movement/adjustment. Explicit protected context permits only those exact quantity deltas and unchanged lot identity. Existing lot classification metadata, source entry and historical work are never overwritten. Required corrected quantities remain pending, not stock.
5. Existing `receive_manufactured_output` confirms each Quality-released target using normal physical receiving, revision/UUID/cap/location checks. Only then do corrected stored lots or finished stock exist. Retained/source and new unfinished groups stay held until all affected receipt obligations are complete. Eligible quantities then return to ordinary explicit Planning; no new job or schedule is generated.

Supported single-source transformations:

| Finding / result | Physical accounting and allocation consequence |
| --- | --- |
| 90finished/10stored →94finished/6unfinished | Retire whole10 decision. Withdraw4 stored units, leaving6 held and finished stock90. Confirm finished4 through existing receiving: stock94, stored6, original finished shortage6. Create a separate6 decision only by explicit authorized action |
| Printing10 →Printing+Cutting10 | Retire eligible old work. Withdraw old10, keeping immutable old group/lot identity in history at zero remaining; confirm10 under a new Quality group identity. New explicit Planning uses the corrected unordered operations |
| Printing10 →Printing6/Cutting4 | Retire affected whole work. Retain6 under unchanged identity and handoff4, or withdraw10 and confirm separately identified6/4 under new identities. No double stock, automatic jobs or arbitrary pooled redistribution |
| Equivalent canonical operation sets | UNCHANGED accounting event with quantity0 and no movement/physical confirmation. Original valid work survives; no retirement/reclassification |
| Incompatible unstarted REPLACE | Existing Phase4B cancellation is required; no in-place resize. Completed accounting restores correct demand/stock ownership without duplicate fulfillment. Untouched allocations on other identifiable sources remain usable |

Only one fully received, fully stored, unconsumed old unfinished source is reconciled per finding. All affected live COMPLETE/REPLACE/STOCK or unbound disposition entitlements must first be retired through supported contracts; B2 does not override Phase4B's refusal to retire dependent STOCK work. Unchanged groups retain their source, quantities, allocations and genealogy. Target groups must be fully Quality-released and their exact increments must sum to the withdrawal. A changed classification requires a new immutable group identity, not overwriting an old group in place. Mixed source changes, insufficient quantity, missing/mismatched location/physical identification, partial original receiving, unreleased targets, parent holds and multiple unresolved findings fail closed with specific codes.

The original factory → structure/fulfillment → source/lot → production/material locking and post-wait permission checks remain. Source/Quality, Planning/material, UUID and quantity protections are reused. The new event shapes allow exactly the original B1 finished movement, a B2 unfinished movement, or a zero-movement UNCHANGED event. Constraints for receipts/other operations, private RLS/ACLs and immutable audit remain enforced. No new inventory table, Scrap KG posting, output production entry, permission definition or automatic redistribution was added.

**Progress correctness:** `output_handoffs` normalizes legacy B1's single target and B2's explicit target increments. Progress now counts immutable RECEIPT events linked to their reconciliation UUID, not net stock after future adjustments. This fixes the specific hazard where a later safe withdrawal from a previously received B1 lot could reopen the old completed handoff. Receipts to existing finished groups count only newly linked quantities, not old90. New inspection during a pending handoff blocks stale receipt even where old finished stock is unaffected. Original stock/commitments remain visible and usable when safe. Reader metadata retains historical handoffs, remaining quantities, current finding/application and affected decision eligibility. No unsafe history is rewritten to clear a hold.

Final evidence:

| Layer | Result |
| --- | --- |
| New PostgreSQL | 71 assertions PASS:51 allowed/handoff/identity/revision/permission checks plus20 blocked/Sales checks. Covers primary94/6 and new explicit6, operation change, both split representations, equivalent sets, REPLACE retirement, physical identification, locked/elapsed schedules, issued/started/consumed/inspected/received work, STOCK dependency, Sales commitment, original incoming conversion, historical progress, unrelated source issue and isolation |
| Affected PostgreSQL | 328 assertions PASS: Phase2 38; Phase4 integration10/scenarios23/Sales14; Phase4A45; Phase4B58+21; Phase4C-2A59; B1 60. One B1 expected blocker changes from allocation_scope to allocation_retirement_required for the newly supported pre-issue path; the original test still verifies no stock mutation before cancellation |
| Concurrency/security | 14 groups PASS,13 observed lock waits: cancel/issue orderings; cancel/Warehouse revision handoff; duplicate/competing withdrawals; amendment/reconciliation orderings; split receipt race; competing explicit6 decisions; both Sales dispatch/final receipt orderings; post-wait Warehouse edit revocation; disabled gates/context cleanup |
| Node | 53 focused existing recording/transport/Phase2/4A/4B tests PASS |
| TypeScript/build/browser | Not rerun: no application/API/TypeScript/dependency/UI changes. No hosted or browser acceptance claimed |

SQL evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4C2B2-SQL-28f8fd2315214f70b3d0d21745edaec8\results`. Fresh109 executable migrations exclude Export Reader. Existing portable PostgreSQL17.11 on verified disposable `factory_lean_quality_local`,127.0.0.1:55491; original RLS/grants, authenticated-role public RPC concurrency. Private predicate overridden only by disposable fixtures; shipped predicate/public capability and late activation remain FALSE/schema0. Owned server stopped/data removed, scripts/results retained; contexts zero. Standalone PostgreSQL is not hosted Supabase Auth/PostgREST acceptance.

Task baseline/Node/preservation evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4C2B2-d11335aada934f0ab8aa995d870e1faf`.

Exact eight-file scope:

- `supabase/migrations/20261026072144_manufactured_output_allocated_reconciliation_v4c2b2.sql` (new)
- `tests/manufactured-output-phase4c2b2/integration.test.sql` (new)
- `tests/manufactured-output-phase4c2b2/blocked.test.sql` (new)
- `tests/manufactured-output-phase4c2b2/concurrency.mjs` (new)
- `tests/manufactured-output-phase4c2b2/run-local.ps1` (new)
- `tests/manufactured-output-phase4c2b1/integration.test.sql` (one expected blocker)
- `docs/manufactured-output-phase4.md`
- `HANDOFF.md`

110 local migrations; all109 previous migration hashes unchanged. Development HEADbb0d20e5dd433b896dd319f56e75f0d9eb5d2862, empty index, Export Reader, Design System, Purchasing, unrelated work and previews preserved. Differentiators reviewed: manufacturing parity remains, no new comparative claim. No hosted access/deployment/activation or Git writes. Remaining: UI/API integration and legacy consumer integration, eventual separately authorized hosted/user acceptance, and explicitly blocked physical/ambiguous states. No issued returns/started undo, general multi-source or multi-unresolved-finding framework, new Scrap adapter, automatic replacement/scheduling or late activation. Stop after B2.

## Original Phase 4 task file manifest (before Phase 4A)

Modified existing files:

- `src/app/api/manufactured-output/route.ts`
- `src/app/layout.tsx`
- `src/features/ManufacturedReceiving.tsx`
- `src/features/ProductionPlanning.tsx`
- `src/features/ProductionRecordingV3.tsx`
- `src/utils/production-recording-v3.mjs`
- `tests/planning.test.mjs`
- `tests/production-recording-full-app/backend.mjs`
- `HANDOFF.md`
- `docs/PRODUCT_DIFFERENTIATORS.md`

Added:

- `src/features/ManufacturedCompletion.tsx`
- `src/features/manufactured-completion.css`
- `supabase/migrations/20261025024857_manufactured_output_completion_v4.sql`
- `tests/manufactured-output-phase4.test.mjs`
- `tests/manufactured-output-phase4/allocations.test.sql`
- `tests/manufactured-output-phase4/browser.mjs`
- `tests/manufactured-output-phase4/concurrency.mjs`
- `tests/manufactured-output-phase4/fixture.sql`
- `tests/manufactured-output-phase4/integration.test.sql`
- `tests/manufactured-output-phase4/prepare-preview.ps1`
- `tests/manufactured-output-phase4/run-local.ps1`
- `tests/manufactured-output-phase4/scenarios.test.sql`
- `docs/manufactured-output-phase4.md`

At the original Phase4 checkpoint: 105 local migrations; 104 preceding files preserved byte-for-byte. Phase4A adds the forward migration documented above. Export Reader remains excluded from the local executable chain. Design System and unrelated dirty work preserved. No hosted access, Git write, deployment or activation. Stop here; no later phase started.

## 2 November2026 — approved measurement-only shortage

Recorded60 corrected by Quality to actual58/accepted58 leaves unproduced2, not rejected or unfinished material. Active execution keeps ordinary remaining2. Ended execution exposes explicit make-up through effective Orders view/edit/create/approve and recording-complete confirmation. Existing immutable compensation/work ledger uses separate MEASUREMENT source; no lot/rejection release or automatic job/start. Raw60, Quality58 and target60 remain distinct; resulting output still requires protected Quality/receipt. Factory/fulfillment/structure locks, revision/UUID intent, global demand cap and source recording guard prevent duplicates. New forward20261102140000; no obsolete-data backfill, cancellation/revision redesign or activation.45 SQL checks/3 races/actual browser active and ended flows PASS. See consolidated report for exact evidence and remaining historical/hosted limits.
