# Factory Lean manual acceptance demo

Verified on **2026-10-05**, from official checkpoint `881210cc931dc66f7fd82ee409c7e429c2200601` on `development`. This is a disposable, fictional operating dataset, not evidence of real factory improvement. No product behavior or schema was changed.

## Environment, dates and navigation

**Localhost and TESTING use the same database**, as explicitly clarified by the user. Only `factory-lean-testing` (`silmfbpjyepalnggwulp`) was reset. There is no separate local database. DEV and PROD were neither queried nor changed.

The current demo day is **2026-10-05**. Opening balances and the initial inactive runtime context start **2026-09-05 00:00 UTC / 03:00 Asia/Qatar**. Sixteen completed jobs run from **2026-09-07 06:05 UTC to 2026-10-04 14:05 UTC**, or **September 7, 09:05 through October 4, 17:05 Asia/Qatar**. Production is sparse, on September 7, 12, 15, 19, 23, 27 and October 1, 4, on both original lines. The preserved working calendar moves Friday work to an eligible working day.

Historical source timestamps were imported with the user's explicit permission. All CHECK/FK constraints and business triggers remained enabled. Normal commands created Sales demand, stock movements, receipts, Maintenance transitions and Lean actions. Historical execution/context records supply the calculations; existing production-loss and Lean calculators derive the saved evidence. Immutable approval metadata and command/audit times retain their real import time. These are historical fixtures, not claims that users executed these commands last month. Factory registration metadata was preserved even where imported operating history predates it.

Find records by their `DEMO-*` description/customer reference, not a generated SO/PO number. Product codes are stable. UUIDs, sequence-based references, identity colors and current server timestamps change on reseed.

The home screen is **Lines & Machines**. Production material requests are under **Production orders → Request Materials**. Warehouse has its own Production Material Requests fulfillment and separate Purchasing workflow. Factory Overview and standalone Semi-Finished navigation remain hidden; WIP remains available through Warehouse and Production.

**Planning limitation:** the existing Gantt excludes completed jobs, including with a wider date range. Sixteen historical jobs, their plans, actuals and revisions are present in Planning's planned/progressed list and Production History. The requested completed historical Gantt blocks cannot be achieved by safe data seeding alone. No completed job was relabeled as planned and no UI logic was changed. Current/future jobs and free gaps are visible in the Gantt; use the native date/range controls for a wider view.

## Existing accounts and authorization

Use existing login credentials. No credentials are stored in this document and no auth accounts or temporary grants were created.

| Existing person | Useful test perspectives | Actual authorization at this verification |
| --- | --- | --- |
| **Ahmed Al Mansour** | Owner/Admin, Lean Manager, Lean Verifier; broad inspection | Existing owner/platform administrator. If the platform dashboard opens, select **Open authorized factory** for Nova. Existing direct `lean:view/create/edit/approve`, `lean_standards:edit`, `roles:edit` and protected owner/platform scope remain intact. |
| **Nasser Al Kuwari** | Sales, Planning, Production Manager/Engineer, Warehouse, Purchasing, Maintenance manager; original requester | Existing 92 direct grants include `sales_orders:view/create/edit/approve`, `orders:view/create/edit`, `warehouse:view/edit/issue`, `purchasing:view/create/edit`, `suppliers:edit`, `downtime:view/approve`, `machine_status:edit`, `maintenance:view/create/edit`. He has no Lean grant. All pending material/direct purchase requests belong to Nasser. |
| **Omar Khalil** | Maintenance worker on assigned requests | Existing approved membership and `factory:view` permit the existing own-assigned-work exception. Start/complete his assigned work; this does not confer Maintenance management or verification authority. |
| **Sara Haddad** | Inspection supported by her existing direct grants | Her historical grants remain unchanged. Do not assume Purchasing, Maintenance or Lean access from a title. |

Eight existing packages are preserved: Factory Owner/Admin, Production Manager, Production Engineer, Planning Engineer, Maintenance, Warehouse, Purchasing and Sales. There are **169 package contents, 345 direct grant rows, five memberships and zero package assignments**, unchanged from the original snapshot. The fifth membership remains rejected. Package names and the ten perspectives below are not authorization rules. Effective permission is the union of assigned packages and direct grants; there are no individual deny overrides.

`View As` can preview a perspective but cannot authorize commands. Owner/Admin can legitimately test package assignment through normal administration; remove any manual test assignments afterward. Assigning a narrow package to Nasser does not remove his broad direct permissions. Use per-person effective permissions when checking a denial.

## Fresh masters and arithmetic

| Product code | Stock/sourcing | Recorded weight | LINE 1 | LINE 2 |
| --- | --- | --- | --- | --- |
| P-032 | Manufactured, meter | 0.30 kg/m | 200 m/h | 160 m/h |
| P-050 | Manufactured, meter | 0.60 kg/m | 140 m/h | 120 m/h |
| P-063 | Manufactured, meter | 0.95 kg/m | Unsupported | 90 m/h |
| C-HDPE | Manufactured intermediate, kg | 1 kg/kg | Mixer capability 50 kg/h | No invented line rate |
| P-EXT | External purchased elbow, piece | Not a manufactured pipe | No production capability | No production capability |
| P-BOTH | BOTH sourced 50 mm stock, meter | 0.60 kg/m | 140 m/h | 120 m/h |

All identities and product-specific capabilities are new. Product identity colors use the existing UUID-based color utility. Permanent machine categories, explicit alternatives, buffers and blocking configuration were preserved. LINE 1 retains its original configured name “PVC Pipes”; it was not renamed to fit this demo. All nine existing lines and fifteen machines, including retained QA configuration, remain; historical production uses the two original lines only.

The authoritative recipe is **one new versioned C-HDPE recipe per 1 kg of compound**, linked by all three pipe Products (and P-BOTH): **0.80 kg HDPE Resin + 0.18 kg Calcium Carbonate + 0.02 kg Black Masterbatch**. The architecture does not duplicate ingredient recipes on finished pipes. For 600 m of P-032: 180 kg theoretical output → **144 / 32.4 / 3.6 kg** ingredients. Historical material requests issue exactly those quantities. Recipe calculation never automatically consumes stock.

| Warehouse material | On Hand | Minimum / Maximum | Useful condition |
| --- | --- | --- | --- |
| RM-HDPE — HDPE Resin, kg | 2056 | 200 / 4000 | Healthy; 2000 opening − 144 issued + 200 external purchase receipt |
| RM-CACO3 — Calcium Carbonate, kg | 62.6 | 70 / 250 | Below physical Minimum; 100 kg ready purchase is Incoming, so projected stock is 162.6 |
| RM-BLACK — Black Masterbatch, kg | 46.4 | 50 / 100 | Below Minimum; 10 kg merely requested suppresses duplicates but contributes no Incoming |
| AC-BEAR — Extruder bearing, piece | 0 | 3 / 10 | Zero-stock accessory; 3 ordered Incoming |
| PK-BUNDLE — Pipe bundle straps, piece | 200 | 50 / 300 | Healthy packaging |

Finished P-032 has **400 m On Hand / 400 reserved / 0 available**, plus **35 m physical WIP: 20 stored and 15 on the floor**. P-050 has **1200 m On Hand / 1200 reserved / 0 available** and **560 m active production**. P-063 has zero Finished stock; its 200 m Sales incoming is committed, so projected uncommitted stock remains zero. C-HDPE has 100 kg available and 50 kg planned demand. P-EXT has 2 pieces available; P-BOTH has zero stock and requires an explicit sourcing choice. Unlike units are never totaled together.

Scrap is kg. Scrap Rate's produced denominator is **Good weight + newly recorded WIP weight**. WIP processing conserves **100 m input = 60 m Good + 5 m discarded production quantity + 35 m remaining WIP**, with **5 kg Scrap** recorded separately. Warehouse receipt changes location, not total WIP quantity. Good immediately credits Finished inventory; physical acknowledgment cannot credit it again.

## How to use the matrix

**Inspect** leaves business state unchanged. **Consume → R** means the suggested action legitimately changes/consumes the demo; use the guarded full reseed command below to restore it. Rows refer to the exact account and permission prerequisites above; all require approved factory access. Do inspect-only tests first, then action tests. Related actions affect other rows: dispatch consumes stock/reservations; recording/finishing current production changes exposure; starting future work requires ending the existing active item first. Do not force overlapping execution or bypass server validation.

### 1. Owner/Admin

Use Ahmed, existing owner/platform scope and `roles:edit`; `employees:view` and `audit:view` for inspection.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| A1 | Employees: four approved members, one rejected | Inspect each membership and effective permissions | Existing people/statuses preserved; rejected person gains no operational access | Inspect |
| A2 | Roles & permissions: eight packages, zero assignments | Inspect package contents and direct permission sources | Package/direct sources are separate; 169 contents and 345 direct rows remain | Inspect |
| A3 | An existing approved member, Roles & permissions | Optionally assign two appropriate packages and inspect the distinct union | Direct grants remain; overlapping grants are not duplicated; no deny override | Consume; remove the two assignments manually. R intentionally preserves current assignments, so it does not undo administration changes |
| A4 | Existing direct grants, Roles & permissions | Inspect inherited versus direct sources; test package administration only as authorized owner | Grant ceilings, owner protections and per-person authorization remain | Inspect preferred; restore any legitimate admin edits manually before R |
| A5 | Audit log: fresh reset/demo history | Inspect actor/time/change for a material request, purchase receipt or initiative | Old operational audit cleared; fresh source/workflow audit remains. Around 1251 rows at verification, not fabricated metric rows | Inspect; later actions naturally add audit |

### 2. Sales

Use Nasser: `sales_orders:view/edit/approve`; creation needs `sales_orders:create`. Warehouse dispatch is a separate `warehouse:issue` action.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| S1 | Sales Orders → DEMO-S1 fully available: P-050, 300 m | Inspect reservation, then Warehouse fulfillment can dispatch | 300 m reserved, zero production shortage, ready to fulfill; dispatch reduces stock once | Inspect or Consume → R |
| S2 | DEMO-S2 partial stock: P-032, 1000 m | Open details and generated Production item | Exactly 400 m reserved, only 600 m production demand, Needs Planning | Inspect; planning/release consumes → R |
| S3 | DEMO-S3 full shortage: P-063, 200 m | Inspect request and stock | Zero Finished reservation; 200 m Needs Planning | Inspect; scheduling consumes → R |
| S4 | DEMO-S4 tight date: P-050, 1000 m | Compare Requested Date October 6 against planned completion October 10 and preserved delivery buffer | 900 m stock + 100 m Production; Late delivery risk. No automatic reprioritization or editable Promised Delivery | Inspect; explicit replan consumes → R |
| S5 | DEMO-S5 comfortable date: P-050, 300 m | Compare October 7 planned completion with October 15 requested date | Full Production shortage, comfortably feasible/On Time using current schedule | Inspect; edits consume → R |
| S6 | S1 reservation before dispatch | Use the existing Release action with a reason where offered | Legitimate release removes the relevant commitment; no fabricated terminal Sales fields | Consume → R; do before dispatch, not on terminal history |
| SH | DEMO-H0 and DEMO-H01…H08-L1/L2 in Sales history | Inspect completed/fulfilled history | 17 historical orders: stock-only, partial-stock + exact shortage, and fully produced; actual dispatch ledger backs terminal state | Inspect |

### 3. Planning Engineer

Use Nasser: `orders:view/edit`. Planning sets line and plan timestamps, never operator/technician. Execution does not overwrite the plan.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| P1 | Planning → Needs Planning: S2, S3 and PR1 compound | Select an eligible line/free slot for S2 or S3 | At least two waiting jobs; server validates rate, calendar, setup and overlap | Consume → R |
| P2 | DEMO-P2 ready to start: P-050 280 m, LINE 1, October 6 09:00–11:00 | Inspect normal future block | Explicit rate 140 m/h; free gaps remain around it | Inspect; move/unschedule consumes → R |
| P3 | DEMO-P3 locked future job: P-032 400 m, LINE 2, October 7 09:00–11:30 | Inspect lock and try normal drag/edit | Locked schedule is protected. Authorized unlock is explicit; lock does not prevent normal execution | Inspect/denial; unlock consumes → R |
| P4 | DEMO-P4 reasoned replan and historical H03-L1 | Open Planning history; optionally replan with a valid reason | Before/after line/start/finish and material_delay reason are retained; unschedule cannot erase replan history | Inspect or Consume → R |
| P5 | S2/P-032 or P-050 capability choices | Compare LINE 1 vs LINE 2 advisory durations before confirming | 200 vs 160 m/h for 32 mm; 140 vs 120 for 50 mm. Existing jobs never cascade automatically | Inspect/advisory; confirmation consumes → R |
| P6 | S3/P-063 | Inspect available lines; try an unsupported assignment only through normal UI | LINE 2 is valid at 90 m/h; LINE 1 is excluded/rejected | Inspect/denial; valid planning consumes → R |
| PH | Widen date/range and inspect planned/progressed list | Compare historical plans to Production History actuals | Both lines have 16 completed jobs and gaps; completed Gantt blocks are an existing unsupported display case | Inspect |

### 4. Production Manager

Use Nasser: `orders:view/create/edit`. Product/recipe inspection is under Products with existing authorized access.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| PR1 | Production orders → DEMO-PR1 manager assignment / compound batch: 50 kg | Inspect request, then use Planning for an eligible mixer/slot | Current authoritative state is **Awaiting Planning**, not an invented Manager-assignment status. No operator assignment is added by Planning | Inspect or Consume → R |
| PR2 | DEMO-P2 scheduled and ready, October 6 | After finishing PR3, use normal Start Production when eligible | Server actual start is separate from preserved plan; one active item per line | Consume → R; never force start over PR3 |
| PR3 | DEMO-PR3 active P-050 560 m on LINE 1 | Inspect active item/flow; optionally record output and finish normally | Sole normal active Product Item; running borrowed Extruder 2 covers stopped Extruder 1. Finish does not change physical status or end transfer | Inspect or Consume → R |
| PM1 | Products → P-032/P-050/P-063 and C-HDPE | Inspect weight, formula link, recipe version and theoretical demand | Fresh explicit master values; 600 m P-032 requires 180 kg compound and 144/32.4/3.6 kg ingredients | Inspect |

### 5. Production Engineer

Use Nasser: `orders:view/edit`, `downtime:view/approve`, `machine_status:edit`; Production requests are editable by their authenticated owner where required.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| PR4 | Production orders → History, historical 600/360/270 m jobs | Inspect Good and linked Sales fulfillment | Valid Good satisfies Finished output and credits inventory once; historical dispatch reconciles | Inspect |
| PR5 | Historical Good + Scrap declarations | Inspect weight snapshot and reviewed Scrap detail | Scrap is kg, not stock; original explanation and approved cause are distinct | Inspect |
| PR6 | H03-L1 first declaration: 540 m Good + 100 m new WIP + 3 kg Scrap | Inspect produced denominator and original lot | Produced weight is (540 + 100) × 0.30 = 192 kg; WIP does not fulfill Sales Finished shortage | Inspect |
| PR7 | H03-L1 later WIP-processing declaration | Inspect input, Good, discarded, new WIP and location history | 100 = 60 + 5 + 35 m; Scrap separately 5 kg. Remaining 35 m has 20 stored / 15 floor | Inspect; process remaining eligible WIP normally consumes → R |
| PR8 | Production orders → Request Materials → DEMO-W1/W2 | Open W1; acknowledge W2 as Nasser | W1 is 20 kg resin Requested; W2 is 5 kg calcium Issued. W2 receipt creates no second issue/movement | Consume → R |
| PR9 | Historical H03 and other completed plans/actuals | Compare dates and duration variance | H03 finishes 20 min later than plan; other jobs finish 5 min later. Planned fields remain unchanged by actuals | Inspect |
| D1 | Downtime → DEMO-D1 Bearing failure history | Inspect original reason, Approved Cause and saved Loss | Complete source-backed loss; early 30-minute stops have larger impact than later 5/10-minute stops | Inspect |
| D2 | Lines & Machines → current stopped M-02 / borrowed running M-08; historical DEMO-D2 | Inspect transfer and saved 20-min stop; optionally stop borrowed machine | Historical 20 physical minutes become 4 effective loss minutes at 160 vs 200 m/h. Borrower stays permanently LINE 2; stopping it must not end OPEN transfer | Inspect; physical change consumes → R |
| D3 | Downtime → DEMO-D3 Die blockage | Inspect six distinct 2-minute stops | Frequent low-severity recurrence; no combined Scrap/Loss score | Inspect |
| D4 | Reviewed Bearing/Cooling history | Compare operator Other/note to Approved Engineer Cause | Original explanation is retained; review does not rewrite it | Inspect |
| D5 | Current open stop and latest P-063 Scrap observation | Inspect missing approved cause; optionally review through normal form | Pending/unreviewed source is excluded from formal approved-cause recurrence until authorized review | Consume → R |

### 6. Warehouse

Use Nasser: `warehouse:view`; stock configuration/receipts and replenishment confirmation need `warehouse:edit`; material issue/dispatch need `warehouse:issue`.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| W1 | Warehouse → Production Material Requests → DEMO-W1 | Issue the requested 20 kg resin | Exactly one issue transaction; status Issued; original requester then acknowledges | Consume → R |
| W2 | DEMO-W2 issued calcium 5 kg | Inspect movement/history; return to Production as Nasser to receive | On Hand is already 62.6; acknowledgment leaves inventory unchanged | Inspect or Consume → R |
| W3 | Three historical Received requests for 144/32.4/3.6 kg ingredients | Inspect request and stock ledger | Historical confirmed issues reconcile to 180 kg theoretical compound example | Inspect |
| W4 | Warehouse item ledger → DEMO-W4 opening balances | Trace initial receipts and later issues | Ledger backs current material stock; Opening Balance is a deliberate receipt type | Inspect |
| W5 | Resin receipt B6, elbow receipt and Good receiving history | Trace External Receipt and one Good acknowledgment | Stock-linked purchase credited once; Good already credited from recording, acknowledgment adds zero | Inspect; receiving another eligible Good acknowledgment consumes → R |
| W6 | P-063 zero Finished stock, Min100/Max1000 | Open replenishment confirmation without saving, then optionally confirm | Projected uncommitted stock is zero; new STOCK_REPLENISHMENT requires a human. No automatic stock-production request exists at seed | Inspect or Consume → R |
| W7 | P-EXT elbow 2 pieces, Min10/Max50 | Open explicit external replenishment; optionally request 48 | Purchase demand, not production scheduling; request contributes no Incoming until ordered/ready | Consume → R |
| W8 | P-BOTH zero stock | Open sourcing decision and deliberately choose Production or Purchase | BOTH never silently chooses a route; resulting workflow follows explicit choice | Consume → R |
| W9 | Warehouse Inventory → P-032, P-050 and low/zero materials | Inspect primary rows and WIP/location details | Finished/reserved/available/stored WIP/active production/Incoming remain separate; material requests and Warehouse Purchasing are distinct | Inspect |
| W10 | Warehouse Outputs → S1 ready fulfillment | Dispatch 300 m | Exactly one Finished dispatch; Sales readiness/remaining reservation update coherently | Consume → R |

### 7. Purchasing

Use Nasser: `purchasing:view/edit` for management, `purchasing:create` for new requests, `suppliers:edit` for directory management. **Direct receipt and requester clarification/cancellation require the original requester Nasser**, not merely an elevated viewer. Stock receipt requires Warehouse authorization.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| B1 | Purchasing → DEMO-B1 black 10 kg, REQUESTED | Review request normally | Request suppresses duplicate demand but does not invent Incoming | Consume → R |
| B2 | DEMO-B2 direct, UNDER_REVIEW | Select supplier, ask clarification, order or reject with appropriate information | Protected lifecycle/revision/retry semantics; no auto-approval | Consume → R |
| B3 | My Purchase Requests → DEMO-B3 NEEDS_CLARIFICATION | Respond as Nasser | Only requester responds; history records question/reply and server actor/time | Consume → R |
| B4 | DEMO-B4 bearing 3 pieces, ORDERED | Mark ready when appropriate | 3 Incoming already counted; cannot requester-cancel after Ordered | Inspect or Consume → R |
| B5 | DEMO-B5 calcium 100 kg, READY_FOR_RECEIPT | Warehouse receives the linked stock purchase | One External Receipt moves 62.6 → 162.6 kg; retry cannot double-credit | Consume → R |
| B6 | DEMO-B6 resin 200 kg, RECEIVED | Inspect receipt link and ledger | Existing single receipt explains 2056 kg current stock | Inspect |
| B7 | DEMO-B7 direct, RECEIVED | Inspect original requester and receipt history | No material/Product link and no stock movement | Inspect |
| B8 | DEMO-B8 REJECTED | Inspect terminal reason/history | Terminal rejected request does not create Incoming | Inspect |
| B9 | DEMO-B9 CANCELLED | Inspect terminal requester cancellation | Cancellation history retained; no inventory credit | Inspect |
| B10 | My Purchase Requests → DEMO-B10 direct, READY_FOR_RECEIPT | Receive as Nasser; inspect typed supplier | No stock movement; “Demo on-site calibration workshop” stays request-local, not a third supplier record | Consume → R |
| B11 | My Purchase Requests → DEMO-B11 REQUESTED | Cancel as Nasser with reason before Ordered | Legitimate requester cancellation; lifecycle and reason retained | Consume → R |
| BS | Suppliers → Gulf Polymer Supply / Doha Industrial Materials | Inspect normalized names/categories and alternative selection; optionally attempt a duplicate | Two reusable suppliers; existing normalized duplicate protection remains | Inspect; directory edits need manual restoration or R (demo suppliers rebuilt) |

### 8. Maintenance

Nasser uses `maintenance:view/create/edit` for management and verification. Omar starts/completes **his own assigned work** through the existing member exception. Verifier Nasser is distinct from worker Omar.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| M1 | Maintenance → DEMO-M1 MANUAL OPEN on M-01 | Inspect then assign Omar | Manual demand alone creates no Downtime, Production Loss or physical flow change | Consume → R |
| M2 | DEMO-M2 ASSIGNED to Omar | Sign in as Omar and Start | IN_PROGRESS, server actor/time; no machine status mutation | Consume → R |
| M3 | DEMO-M3 IN_PROGRESS, Omar | Complete with a useful work note | COMPLETED / Awaiting verification; never auto-Verified | Consume → R |
| M4 | Historical DEMO-M4 MANUAL COMPLETED | Nasser independently verifies result or requests rework with note | RESOLVED produces VERIFIED; REWORK_REQUIRED returns to IN_PROGRESS | Consume → R |
| M5 | Historical DEMO-M5 DOWNTIME VERIFIED | Filter terminal history and inspect link/result | Real source downtime link, separate worker/verifier and completion history preserved | Inspect |
| M6 | Historical DEMO-M6 MANUAL CANCELLED | Inspect cancellation reason | Legitimate terminal cancellation with reason | Inspect |
| M7 | Historical DEMO-M7 failed verification, IN_PROGRESS | Inspect rework result/history; Omar can resume completion | Prior failure retained; new trial must not erase failed verification history | Inspect or Consume → R |
| M8 | DEMO-M8 DOWNTIME OPEN on M-02 | Inspect link, assign/work through normal lifecycle | Linked stop/loss is inspectable; prior terminal M5 does not create an active duplicate | Consume → R |

### 9. Lean Manager

Use Ahmed: `lean:view/create/edit`; libraries/standards require `lean_standards:edit`. Nasser's job title/View As does not supply these permissions.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| L1 | Lean Analysis, 30 days → Bearing failure / Extruder 1 | Inspect loss, frequency, runtime and history | Source-derived high time loss, zero Scrap; machine + approved cause identity | Inspect |
| L2 | P-032 mixture / P-050 quality Scrap rows | Inspect Scrap kg/rate and approved standards | High Scrap with no fabricated loss; identity is line + Product + approved cause. Independent dimensions/highlights | Inspect |
| L3 | Die blockage | Inspect recurrence/history | Six short distinct stops, low individual severity; high frequency is not an invented severe score | Inspect |
| L4 | Printing defect / Printing Station | Inspect source linked stop + 10 kg Scrap | One explicit physical occurrence with both dimensions, not two duplicate occurrences | Inspect |
| L5 | Pending P-063 quality Scrap | Open Production review, not a fabricated approved Lean row | Unreviewed cause stays outside formal recurrence | Inspect; review consumes → R |
| LT | Set Period to 7 days; expand Comparable trend | Compare current/prior equal-runtime dimensions; restore 30 days | Cooling loss/frequency unchanged; Bearing loss worse 33.33%; Die loss/frequency worse 100%; mixture frequency/Scrap improved. Current view can differ from historical initiative outcome | Inspect |
| I1 | Mechanical problem / alternative mitigation, Monitor Only | Inspect prioritization/no initiative; optionally prioritize/create an initiative | Monitoring is valid; no forced action or automatic success | Inspect or Consume → R |
| I2 | Die blockage → DEMO-I2 in progress | Inspect Maintenance and Process action types, different owners; update eligible action | Genuine In Progress state; action ownership and server revisions enforced | Consume → R |
| I3 | I2 cancelled Process action | Inspect mandatory cancellation reason/history | Cancelled action remains visible; cancellation does not pretend completion | Inspect |
| I4 | P-050 quality → DEMO-I4 awaiting verification | Inspect two completed actions and comparison readiness | Initiative awaits authorized human verification; completing actions is not success | Inspect |
| IL | Standards and libraries / prior-action suggestions | Inspect six small templates and prior Improved/No Meaningful Change/Insufficient Data outcomes | Suggestions are editable human actions, no AI root cause. Insufficient Data is the current domain's unknown-evidence outcome | Inspect; edits consume → R |

### 10. Lean Verifier

Use Ahmed: `lean:view/approve`. Manual comparison requires the currently authorized Lean view flow; saving never sets an official initiative outcome.

| ID | Start / navigate | Test action | Expected result | Modify / restore |
| --- | --- | --- | --- | --- |
| I5 | Bearing failure → expand DEMO-I5 improved history | Inspect frozen baseline and verified comparison | Equal 2.5 operating-runtime hours; events 2→1, effective loss 60→5 min, loss/runtime 24→2 min/h. Explicit fictional human Improved note remains | Inspect |
| I6 | Cooling flow → DEMO-I6 no meaningful change | Inspect frozen dimensions and human note | Loss/frequency changes 0%; official No Meaningful Change | Inspect |
| I7 | P-032 mixture → DEMO-I7 worse | Inspect separate dimensions | Scrap Rate change +290.625%, frequency −50%; official Worse is a human fixture decision, not a composite score | Inspect |
| I8 | P-063 quality → DEMO-I8 insufficient data | Inspect after-exposure readiness | Insufficient Product exposure remains Insufficient Data; cannot confirm a complete positive outcome without evidence | Inspect |
| I9 | Bearing failure after I5 | Inspect Recurred After Verification history | Three distinct September 27 / October 1 / October 4 events within 30 days after September 25 verification; previous success is not silently rewritten | Inspect |
| IC | I5 manual comparison | Inspect saved independent 2-hour comparison; optionally save a different explicit comparison | Official frozen outcome/baseline is unchanged | Inspect or Consume → R |
| IV | I4 awaiting verification | Calculate; choose an outcome with a meaningful note only if ready | Server requires authorization and complete comparison for positive/conclusive outcomes; Insufficient Data remains available when evidence is insufficient | Consume → R |

Runtime is **active actual Product production with operating effective flow**, excluding pauses/blocked flow. A physically running machine does not by itself create exposure. The initial inactive month boundary makes the current 30-day window known; it does not fabricate a second month. Some full-month prior comparisons therefore correctly remain Insufficient Data. Use 7 days for populated current/prior examples or frozen I5–I8 history for official Before/After examples.

## R — guarded reset, seed and verify

From the authoritative repository on `development`, use Node and an existing authorized Supabase Management API token supplied securely in the shell's **`SUPABASE_ACCESS_TOKEN`**. Never place that token in source, documentation or a public/browser environment variable.

```powershell
node scripts/demo-reset.mjs --target testing --day 2026-10-05
```

This recreates the October 5 fixture. After the date advances substantially, use the current demo day to shift the month and future schedules while preserving the same scenario design:

```powershell
node scripts/demo-reset.mjs --target testing --day (Get-Date -Format 'yyyy-MM-dd')
```

The explicit target accepts **only `testing`**. `local`, DEV, PROD and guessed project names are rejected because localhost shares TESTING. Guards pin project name/ref, database cluster, one demo factory, timezone, schema digest, all 79 local migration hashes, local/remote migration names and the `development` branch. A schema/migration/configuration prerequisite mismatch fails closed; do not edit guards to force a run.

Stages: controlled FK-aware deletes → new source fixtures → preservation assertions → rollback rehearsal → atomic real source reset/seed → existing calculator/persistence for 21 Loss estimates → existing Lean evidence calculations and explicit fictional human outcomes → 45 read-only acceptance assertions. No TRUNCATE, trigger disabling, migration/history repair, new auth accounts, schema changes or database push. The Maintenance worker and original-requester actors are existing approved users; permission infrastructure remains unchanged. The schema and configuration are checked before/after, except deliberate transient operational machine/order/pause state.

A source-stage error rolls that transaction back. Later derived stages are separate guarded transactions: if one fails, stop, inspect the failure and rerun the complete tool after correction; do not hand-insert metric totals. No automatic network retries. Refresh localhost after reseeding; old open details refer to discarded UUIDs.

The final SQL stages were exercised through the authenticated TESTING MCP connection, including two actual rebuilds and a final complete rollback rehearsal. The positive **Management API HTTP CLI transport has not been exercised with a shell token** in this session. Its guard/date/rollback/fail-closed logic is tested; the SQL and calculators it invokes are live-verified. Users need their existing authorized token for the documented CLI. Do not substitute a browser anon key or service-role key for a Management API token.

Operational reseed deliberately preserves current administrative changes. Restore any user-created permission/package/settings edits through their authorized admin workflow before requesting the exact original configuration baseline. It rebuilds demo Products/materials/suppliers and scenario quantities, not identical UUIDs, colors, reference numbers, audit counts or current runtime.

## Verification and coverage snapshot

| Area | Fresh result |
| --- | --- |
| Database | Local files / shared TESTING **79/79**; all 79 SHA-256 hashes unchanged; schema digest `8bfe6bc171665333961d6bfdb09de6ac` unchanged |
| Reset safety | Final guarded source rehearsal: **44 preservation/source assertions**; fresh live verification: **45 assertions** |
| Masters | 6 Products, 5 materials, one new compound recipe version with 3 ingredients, 2 demo suppliers |
| Sales / Planning | 22 Sales orders (17 history + 5 current); 25 Product Items: 16 completed, 1 active, 3 Needs Planning, 5 future scheduled; 1 locked; current and historical reasoned replans |
| Production / Warehouse | 32 production declarations across the month; 11 primary inventory rows; 35 m remaining WIP; 5 material requests (3 Received, 1 Requested, 1 Issued); ledger/reservation/Good-credit reconciliation passed |
| Purchasing / Maintenance | 11 purchases covering all 8 states; 8 Maintenance requests covering all 6 states, manual/downtime origins and failed verification |
| Loss / Lean | 22 downtime events (21 closed, 1 open); 21 READY saved Loss estimates; 8 visible Lean problems, 6 initiatives, 12 actions, 6 templates, 4 distinct verified outcomes, 1 independent saved comparison |
| Preservation | Fresh original-snapshot comparison: factory, 9 lines, 15 machines, 4 alternatives, 2 shifts, 45 causes, 5 memberships, 8 packages, 169 contents, 345 direct grants, 0 assignments unchanged; complete auth rows also preserved within reset transactions |
| Automated | Focused **225/225**; full Node **679/679**; final maintenance safety tests **4/4**; TypeScript and production build passed |
| SQL | **21 rollback regression suites passed**, including Planning guard; Supply's protected-owner removal fixture used existing non-owner Nasser in memory only (99 assertions). Suite file/business protections were unchanged; no persisted QA grants/accounts/data |
| Browser | Localhost Sales stock/shortage/date risks; Planning waiting/future/lock/replan/history; month Production History; Warehouse balances/location/requests; Purchasing states; Maintenance history/rework; Lean 7/30-day tables and frozen I5 evidence verified using existing Nasser/Ahmed accounts |

SQL suites: Lean, WIP, recording, execution, Supply, Maintenance, Sales fulfillment/sourcing, Warehouse master/manual purchase, requester ownership, suppliers, Permission Packages, production history, downtime, shifts, internal Production, snapshot contract/authorization, lazy history and Planning write guard.

New audit rows are real source/workflow audit activity (approximately 1251 at the final check); viewing/opening the authorized factory and later manual actions can add more. Auth login timestamps naturally change when existing users sign in. No temporary grants/package assignments or QA accounts remain. Browser proof and raw validation logs are outside the repository under `C:\Users\Temp\AppData\Local\Temp\factory-demo-reset-20261005`.

**Manual acceptance remains the user's next step.** The website is running at `http://localhost:3000/`. Work is intentionally uncommitted on `development`; no commit or push was made. HEAD remains the official checkpoint, and main/DEV/PROD are untouched. The completed-history Gantt display limitation and unexercised positive HTTP transport are explicitly reported above.
