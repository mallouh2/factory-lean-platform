# Manufactured output Phase 4E — local operational acceptance

26 October 2026. **PASS for the three supported local scenarios. Shipped workflow remains INACTIVE.** No application/business SQL defect required a fix. This proves actual command execution on a fresh disposable PostgreSQL database through the existing test predicate; it is not hosted Supabase or real-factory physical acceptance, activation approval, customer shipment, or a claim that deferred reversal cases are implemented.

## Environment and method

- Branch development; HEAD bb0d20e5dd433b896dd319f56e75f0d9eb5d2862; index empty. Existing dirty work retained.
- Fresh PostgreSQL 17.11 at **127.0.0.1:55495**, database factory_lean_quality_local. Independent server address/port/database/data-directory check matches the dedicated temporary runtime. Auth/Data adapter **127.0.0.1:4303**; actual Next.js application **http://127.0.0.1:4221/**. Outgoing browser requests restricted to that app origin.
- Runtime/evidence: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4E-Preview-3a1ec8c274f34dfe96f829de5a1aae7f. SQL endpoint proof, setup logs, acceptance.json (command UUIDs, actors, HTTP status/results), evidence/*.json (actual entries, immutable events, lots, issues, movements, work and demand), final-verification.json, cross-factory-http.json and browser screenshots retained outside Git. Passwords remain only in owner-restricted local credential files outside Git.
- Executable fresh chain: 111 original files, excluding Export Reader. All **112 repository migration hashes** remain unchanged; no migration added or amended. All pre-existing application source hashes match the prior verified Phase 4D build copied into this isolated runtime. No repeated TypeScript/build/full regression campaign was justified by test-only changes.
- Bootstrap creates identities, factory permissions, configured weighted Product X (meter, 0.5 kg/m), a capable Printing work center/line, routing operation, working calendar and current verified shift. It creates the original 100 m request through the existing protected request command. Initial finished stock, stored stock, output entries and demand received are **zero**. No desired final balance is seeded. Each scenario has a separate factory.
- Production/Planning owner, independent Quality actor and Warehouse actor use effective factory grants. Normal local form authentication and authenticated identity/factory checks were executed for A and C. SQL-driven B commands explicitly SET LOCAL ROLE authenticated with its actual actor; only fixture bootstrap/diagnostic evidence uses the local database test owner. No business permission or SQL guard was bypassed.
- The pre-existing disposable-fixture predicate enables the test path only in this disposable database. The shipped predicate source is unchanged FALSE; public manufactured_output_capability returns available:false for A/B/C. Completed-shift late recording stays FALSE (all local activation rows disabled). No hosted environment was contacted.

## Scenario results and conservation

All quantities below are meters except Scrap KG. Produced quantities are technician declarations, not current stock; unfinished output is later consumed in A/B. Demand received means manufactured finished receipts attributed to the original Production Item, not customer delivery.

| Fact | A — COMPLETE | B — REPLACE then STOCK | C — Quality finding/partial receipts |
|---|---:|---:|---:|
| Original demand | 100 | 100 | 100 |
| Technician finished declarations across jobs | 90 + 10 | 90 + 10 + 10 | 90 |
| Technician unfinished declaration | 10 | 10 | 10 |
| Latest Quality-authoritative classifications | Original 90 F / 10 U; recovery 10 F | Original 90 F / 10 U; replacement 10 F; stock recovery 10 F | Original amended to 85 F / 15 U |
| Lifetime finished receipts / compensating withdrawal | 100 / 0 | 110 / 0 | 90 / 5 |
| Net finished stock | **100** | **110** | **85** |
| Lifetime unfinished receipts | 10 | 10 | 10 + 2 + 3 |
| Unfinished issued / actually consumed | 10 / 10 | 10 / 10 | 0 / 0 |
| Final stored unfinished | **0** | **0** | **15** |
| Current unfinished completion allocation | Consumed | Consumed for stock only | Original 10 unchanged; new 5 unallocated |
| Scrap KG | 0 | 0 | 0 |
| Original demand received / remaining | **100 / 0** | **100 / 0** | **85 / 15** |
| Sales reserved / available finished | 0 / 100 | 0 / 110 | **1 / 84** |

**A — PASS, actually executed.** Owner normal physical Running command, protected Planning and readiness/Start; browser V3 recording 90 finished +10 Printing; recording UUID replay. Quality actor first releases only finished, then releases the inspected unfinished; requires_production_approval:false. Warehouse actor receives 90/10 and retries the exact finished-receipt UUID. Explicit browser COMPLETE and normal Planning editor schedule. Warehouse issue/retry, readiness/Start, browser source-bound input10→finished10/Scrap0, exact recording retry, independent final Quality and actual receipt/retry, then Finish. No finished credit from recording, Quality, allocation, issue or execution completion. Input remaining0, consumed10 once, two positive FG movements, original demand100/remaining0.

**B — PASS, actually executed via authenticated public SQL RPCs.** Initial90/10 recorded/inspected/received. REPLACE10 creates normal production work, leaves original lot10 stored/intact, and exposes free_for_stock10. Normal scheduling/Start→record10→Quality→receive10→Finish makes original demand100 while old unfinished remains10 and consumption0. Separate explicit STOCK10 decision has demand_item_id NULL; schedule/issue/Start→source-bound record10→Quality→receive10→Finish yields finished110, old unfinished0, consumption10. Original demand remains100, not110. Three positive finished receipt movements; no fabricated fulfillment or automatic recovery.

**C — PASS, actually executed.** Initial90/10 recorded/received; explicit COMPLETE10 remains unissued. Physical source identification and one legitimate Sales order/approval/source reservation use public commands (no direct balance writes). Browser Quality changes only finished90→85 and adds a new5 Printing group; original10 group and allocation are unchanged. Finding pending: stock still90/10 and identified stock cannot dispatch. Warehouse browser reconciles exactly5 once, then physically receives2 and3 through the normal receipt form; exact two-meter UUID replay adds nothing. Partial handoff stays held. Final accounting RECONCILED/pending:false, finished85, stored15, work10 unchanged, new5 unassigned, demand shortage15. Original technician effective Good90, immutable entry/work and Sales reserved1/dispatched0 remain unchanged. No extra production or Scrap rejection was invented.

### Exact fixture and movement references

| Scenario | Factory ID | Original Production Item | Created work |
|---|---|---|---|
| A | 58fd2453-4dd2-4e1d-a6b2-0c300f95d204 | 2425cd42-a374-4084-8372-06cfe0b17542 | COMPLETE: d2756808-6a0c-460c-bbf0-470a9f0a1b03 |
| B | 239cdc22-f950-4694-8524-dc9b871edb38 | 6957bf02-449e-424d-9921-ea9594d75caa | REPLACE: 6fb9d0b6-bf33-4608-ac70-13fc22ff6994<br>STOCK: 475c5a49-38e8-4caf-86dd-ea7ea56a228c |
| C | c3d79a81-7ff7-4d4f-8b92-324568fd39a8 | 42538e5f-840f-4140-a54b-3fb93077cb14 | COMPLETE: 9e247393-b2c8-4452-bec1-05010d4283d2 |

- **A finished movements:** 822551ac-db82-4545-b96f-f4c6316b60e7 (+90 m, production_receipt); 04f69957-bf31-4496-900f-bf84895cf159 (+10 m, production_receipt).
- **B finished movements:** e203a803-da5a-4681-bc32-a30123e5a56f (+90 m, production_receipt); 7f4979fb-5129-4d1b-beb9-55b266919a57 (+10 m, production_receipt); 403c70b9-c56d-4f0a-ac6f-02fb58870af1 (+10 m, production_receipt).
- **C finished movements:** 77d5c21a-52b0-42f9-a7aa-cc38cb1176b5 (+90 m, production_receipt); 58cbab10-16a8-48b8-94b5-b925713066e1 (-5 m, quality_rejection).

Exact entry/output/group/lot/request/receipt/reconciliation/UUID references and all before/after snapshots are in the evidence directory; C-final-protected-readers.json shows stored5/unassigned5 and stored10/unassigned0 separately. A-final-completion-reader.json shows original demand100 received,0 remaining, work10 consumed/10 finished received.

## Focused safety evidence

**35 recorded scenario/browser/safety steps PASS**, plus **13 explicit negative checks** and three cross-factory HTTP checks. The negative results are real server/database responses, not disabled buttons:

| Attempt | Actual response / protection |
|---|---|
| Receive uninspected output | HTTP422, output_quality_required |
| Receive unreleased unfinished or over-receive | HTTP422, output_receipt_quantity |
| Warehouse actor makes Quality finding | HTTP403, permissionError |
| Quality actor receives Warehouse stock | HTTP403, permissionError |
| Foreign factory read/write | HTTP403, permissionError; no rows/data |
| Another factory's target inside authorized factory | HTTP422, output_not_found; no data |
| Cancel after actual issue / after Start | P0001 output_material_issued / output_work_started |
| Invalid source / second consumption with fresh UUID | P0001 output_input_required / output_input_quantity |
| Held identified finished dispatch | P0001 output_quality_hold; Sales reservation/dispatched quantity unchanged |
| Allocate partially received held corrected source | P0001 output_quality_hold; no recovery work/issue created |
| Reserve / dispatch an actual unfinished lot as finished | P0001 source_unavailable; original source reservation and stock unchanged |

Exact response bodies are retained in acceptance.json/cross-factory-http.json. No negative call changed affected entries/events/balances/lots/work/movements. Exact UUID retries were executed for recording, finished receipt, issue, recovery recording, recovered receipt and partial receipt. Existing concurrency tests from Phase4B/C remain prior evidence; no new concurrency campaign or direct held-input recording was claimed in this phase. The actual held allocation denial prevents that new partial handoff obtaining a legitimate recovery job; held finished dispatch was separately executed and denied.

## Browser evidence and harness corrections

Actual separate normal local logins; production groups/Printing checkbox; independent Quality/release; Warehouse initial and partial receiving/reconciliation; COMPLETE decision and existing Planning editor; History→Quality→Warehouse→Planning→original Production Order, Back navigation, authoritative100/0 demand and10 consumed; EN and Arabic RTL390px, no document overflow and no browser page errors. Read-only drill-through produced no business POST and unchanged operational snapshots. Response evidence: read-browser-responses.json; screenshots A-desktop-conservation.png/A-arabic-mobile.png.

No product defect was confirmed or fixed. Harness corrections: use actual target_line parameter; establish a future first verified shift occurrence (no backdating); use actual stock_delta movement field; preserve Actions open state; identify classification select without an over-strict wrapping-label text match; use normal keyboard navigation to leave the hover/focus sidebar; choose a genuinely future Planning start. Failed harness steps were inspected against durable state before resuming; committed Quality, decision, receipt and Finish transactions were not blindly repeated. The first-attempt evidence is retained. No SQL guard, stock ledger or application source was changed to make acceptance pass.

## Changed files / verification limits / next action

- Added tests/manufactured-output-phase4e/: deterministic initial fixture, isolated preparation, authenticated RPC/evidence helpers, browser helpers, A/B/C runners, safety, read-only browser and final assertions.
- Extended tests/production-recording-full-app/backend.mjs only to accept additional independently authenticated fixture contexts; existing single-context behavior remains the default. No app import or authorization override.
- Documentation: this report, phase4 summary and HANDOFF.
- Final independent assertions, all new/shared adapter JavaScript syntax checks and preparation PowerShell parser PASS. No application/TypeScript/package/source/migration change; prior matching optimized build reused and actually served.
- Unsupported issued/consumed/shipped/committed or physically ambiguous Quality reversals remain intentionally blocked. This phase does not add them, customer dispatch/fulfillment acceptance, arbitrary routing, hosted integration, or actual warehouse label verification. B replacement decision was SQL-command acceptance, not a separate browser REPLACE submission. Local adapter is not hosted GoTrue/PostgREST evidence.
- Preview stays running at http://127.0.0.1:4221/. Use the A owner entry in owner-restricted C:\Users\Temp\AppData\Local\Temp\FactoryLean-Output-P4E-Preview-3a1ec8c274f34dfe96f829de5a1aae7f\LOCAL-LOGIN.txt through the normal login form. Open Production History→select original90m entry→Actions→Details; related links show Quality90/10, original receipts90/10, recovery10 received and original demand100/0. C credentials show85finished/15stored and reserved1. These fixtures are already executed: do not resubmit their transactions.
- STOP after Phase4E. Next action is owner-led local review of these completed records, or a separately authorized release/activation decision. No hosted access/deployment/activation, Git write, previous migration edit, previous preview change, or Design System/Export Reader modification occurred.
