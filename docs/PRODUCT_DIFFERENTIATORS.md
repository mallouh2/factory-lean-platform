# Factory Lean — Product Differentiators

Research and repository review: **2026-10-02, Asia/Riyadh**. Development base: `c494df9f6556bc925ccf75219a528c161e956028`, including the legitimate uncommitted Sales/Warehouse V1 work. This is the product-level evidence record, not a release certificate or marketing page. Repository code takes precedence; [HANDOFF.md](../HANDOFF.md) supplies dated verification and acceptance boundaries.

## Purpose and durable maintenance rule

Record why a small or medium factory might choose Factory Lean, what is ordinary parity, and which gaps are worth addressing. Claims concern specific implemented workflows; measured customer savings, adoption, affordability and competitor-wide superiority have not been established.

Whenever a significant feature is added or materially changed:

1. Re-evaluate its effect on competitive position.
2. Review relevant current competitors when useful.
3. Update this record only for new/changed differentiation, achieved parity, or a material competitive opportunity. A differentiator can weaken as competitors change.
4. Exclude tiny bug fixes and cosmetic changes unless they materially affect that position.

Reusable instruction for future implementation prompts:

> After implementation, evaluate whether this feature materially changes Factory Lean's competitive position. If yes, update docs/PRODUCT_DIFFERENTIATORS.md with evidence and current competitor context. Do not add ordinary bug fixes or minor UI changes.

Every update needs implementation evidence, verification/acceptance status, a precise comparison, and dated official references. Absence from reviewed public documentation is not proof of competitor absence. Comparisons below are analytical judgments, not results of competitor installations or exhaustive market testing.

## Product positioning

Factory Lean serves production engineers, planners, managers and owners in SMB factories, initially plastic pipes. Reusable factory/line/work-center/Product concepts support other configured processes, but cross-industry deployments are not yet validated. The intended loop is:

**Plan → Execute → Capture loss → Find cause → Action → Verify → Measure value → Next problem**

Current strength is connecting persisted demand, execution, machine dependencies, output disposition and reviewed loss evidence. The complete corrective-action/value-measurement loop remains unfinished.

| Alternative | Concrete reason to consider Factory Lean | Boundary |
| --- | --- | --- |
| Generic ERP | Engineer-facing line/flow/borrowed-machine facts and loss context accompany demand and delivery. | Odoo and Daftra already offer manufacturing; no claim all ERPs lack shop-floor functions. Factory Lean does not replace accounting/procurement. |
| Basic tracker or spreadsheet | Database-validated transitions, conserved WIP, explicit assignment lifecycle and immutable correction/replanning evidence. | Migration/setup and disciplined operator input are still needed; no measured adoption advantage. |
| Downtime/OEE tool | Review effective lost output/deferred work against configured demand, alternatives and buffers, alongside execution and fulfillment. | Sepasoft already models line-level loss; OEE products also support improvement. Factory Lean has no proven automatic machine-data collection advantage. |
| Larger MES | A bounded workflow for line engineers and small factories rather than a broad configurable enterprise implementation. | Simpler scope is a product choice, not demonstrated lower total cost. Enterprise genealogy, quality and integration capabilities can exceed current V1. |

## Status and classification

**V — Implemented / verified:** source and tests support the behavior; HANDOFF records verification. This does not automatically mean user acceptance or production readiness.

**A — Implemented / verified, acceptance outstanding:** implementation exists, but the named manual/product acceptance remains open. **P — Planned/deferred:** explicitly recorded direction, no completed workflow. **I — Discussed/research candidate:** recommendation only, not an approved roadmap commitment.

The initial documentation review reused preceding evidence. The subsequent Internal Production implementation ran **390/390 Node tests**, **22/22 focused Internal/Requests tests**, eleven rollback SQL suites, TypeScript and an isolated production build. Local/TESTING are now 61 aligned; DEV 11 remains historical and was not connected. Existing-account live creation, required-reason rejection, Planning inspection, reload and EN/AR details passed. Sales/Warehouse acceptance below reflects the user’s explicit acceptance of the seven earlier live scenarios, not a claim of a new full manual fulfillment replay.

Classifications:

- **A. STRONG DIFFERENTIATOR:** a meaningfully distinctive implemented combination for the target workflow; provisional comparative judgment, never global uniqueness.
- **B. COMPETITIVE ADVANTAGE:** relevant implementation choices, although comparable products have related functionality.
- **C. PARITY / EXPECTED FEATURE:** necessary capability, not a standalone reason to choose the product.
- **D. FUTURE OPPORTUNITY:** absent completed workflow worth evaluating; priorities below are recommendations only.

## Competitive matrix

Seventeen implemented capability groups are reviewed below: **3 A / 5 B / 9 C**. Overlapping groups are different aspects of the same workflow, not seventeen independent inventions. Competitor references resolve in the dated source register.

| ID / capability | Factory Lean state | Competitor examples | Classification | Comparison boundary |
| --- | --- | --- | --- | --- |
| 1 Effective loss from demand + flow context | V; calibration acceptance separate | Sepasoft, MachineMetrics, Evocon | A | Combination, not invention of flow-aware downtime. |
| 2 Explicit alternative borrowing lifecycle | V | Sepasoft, Siemens | A | Stopped borrowed machine stays assigned until explicit return. |
| 3 Quantity-scoped secondary WIP operation | A | Siemens, Tulip | A | Original normal line assignment survives; recorded operation only. |
| 4 Good/Scrap/Unfinished and traceable lots | A | Siemens, Odoo | B | Unfinished has explicit usable-stock meaning, not scrap. |
| 5 Immutable estimates versus actuals | V; manual calibration A | MachineMetrics, Evocon | B | Assumptions/actuals remain distinguishable; no proven savings. |
| 6 Unit-safe full-result History | A | MachineMetrics, Tulip | B | Physical disposition denominator and weighted shift/unit totals. |
| 7 Engineer-oriented Factory Floor | A | MachineMetrics, Tulip, Odoo | B | Job facts belong to line; physical/flow/assignment are separate. |
| 8 Delivery risk with retained promises/manual Planning | V; live-verified TESTING, uncommitted | MRPeasy, Katana | B | Explicit date semantics and bounded advisory decisions. |
| 9 Configurable flow/dependencies | V | Sepasoft | C | Enterprise tools already model complex lines. |
| 10 Good-only demand progress | A | Odoo, Siemens | C | Good quantity completion differs from execution Finish. |
| 11 Planned versus actual execution | V | MRPeasy, Odoo | C | Preserve plan; single active normal item per line. |
| 12 Reasoned replanning/lock history | V; some manual checks open | MRPeasy, Daftra | C | Auditable manual control, not unique scheduling. |
| 13 Server/timezone shift attribution | A | MachineMetrics, Tulip | C | Overnight windows and historical IDs preserved. |
| 14 Per-person authorization | V | Odoo | C | Titles/View As cannot confer authority. |
| 15 Lightweight reads/lazy histories | V; scale monitoring open | Tulip, MachineMetrics | C | Engineering quality, not a proven market differentiator. |
| 16 Sales → FG → shortage → dispatch; Min/Max | V; live-verified TESTING, uncommitted | MRPeasy, Katana, Odoo, Daftra | C | Already implemented here; common MRP functionality. |
| 17 EN/AR operational presentation | V; real-device acceptance open | Daftra | C | Arabic is expected regionally; no unique-localization claim. |
| Corrective action → verified improvement | P/I | Tulip CAPA, Odoo Quality | D | The intended loop is not yet complete. |
| Maintenance requests/planning | P | Odoo Maintenance | D | Stop reason/history is not a maintenance workflow. |

## Validated capabilities and comparison

### 1. Demand- and flow-aware production loss — A

**Factory problem:** Long machine stops can be harmless during idle time; shorter bottleneck stops can damage throughput. Counting downstream effects repeatedly overstates loss.

**Factory Lean approach:** `calculateProductionLoss` segments captured historical context at schedule/context/buffer boundaries, calls `evaluateFlow`, applies Product/unit capability rates and actual OPEN alternatives, and distinguishes effective lost output, deferred quantity/recovery workload and non-production time. Missing rates/context remain INCOMPLETE.

**Operational value:** Engineers can prioritize modeled throughput impact instead of treating every physical minute equally; managers can inspect assumptions.

**Implementation status:** V, Production Loss Impact V1. Recorded browser/SQL/calculation verification exists; old uncaptured stops cannot be reconstructed. Financial valuation and automated diagnosis are not implemented.

**Competitive context:** Sepasoft documents parallel cells and key-reason blocked/starved logic [S1]; Evocon excludes unscheduled time from OEE [S4]; MachineMetrics analyzes OEE [S2].

**Differentiation:** The small-factory combination of persisted Planning demand, explicit borrowing, buffer expiry, typed throughput and deferred work is the candidate differentiator. Flow awareness alone is parity. Reviewed sources do not establish this exact combined workflow, but could support equivalent configurations.

**Evidence:** [loss model](../src/utils/production-loss-impact.mjs), [flow model](../src/utils/production-flow.mjs), [loss regressions](../tests/production-loss-impact.test.mjs), [trusted estimate function](../supabase/functions/save-production-loss-estimate/index.ts); S1/S2/S4, researched 2026-10-02.

### 2. OPEN transfer is temporary assignment truth — A

**Factory problem:** A stopped borrowed machine can accidentally appear available to its home line, creating false capacity or an invalid return.

**Factory Lean approach:** An OPEN transfer retains the borrowed execution assignment even if the alternative stops or the transferred job finishes. Explicit transfer end reprojects the home assignment; permanent `line_id` stays unchanged. Alternatives are explicit, same-category and Product/unit-capable.

**Operational value:** Engineers see where a machine actually belongs and can return it deliberately without corrupting identity or Planning.

**Implementation status:** V; transfer/assignment/return database and live verification recorded. Starting/finishing a job changes neither physical status nor transfer lifecycle.

**Competitive context:** Sepasoft models shared/parallel process relationships [S1]; Siemens supports reconfigurable equipment and execution [S5].

**Differentiation:** Specific separation of permanent ownership, OPEN temporary assignment, physical condition and effective flow is distinctive in this implementation. The reviewed material does not establish an identical stop/return lifecycle; no unsupported claim competitors cannot do it.

**Evidence:** [assignment migration](../supabase/migrations/20260930093623_execution_assignment_consistency.sql), [return projection](../supabase/migrations/20260930094552_transfer_return_execution_projection.sql), [execution/transfer regression](../tests/production-execution.test.sql), flow model; S1/S5, 2026-10-02.

### 3. Quantity-scoped WIP work without moving the original job — A

**Factory problem:** Part of an order needs printing or finishing elsewhere, while moving the whole original job would falsify its plan and line queue.

**Factory Lean approach:** A separate operation binds a specific lot, consumed quantity, remaining-work note and compatible secondary line or independent center to the resulting declaration. Recording and assignment are atomic. It never creates a second ordinary active-line assignment or overwrites the original planned/actual times. Database checks conserve consumed quantity = Good + Scrap + new Unfinished and reject conflicting destinations/OPEN transfers.

**Operational value:** Engineers process partial unfinished output with original demand lineage; planners retain their original schedule.

**Implementation status:** A; rollback, simultaneous-consumption and controlled live checks recorded; user WIP acceptance outstanding. Assignments represent recorded processing, not advance reservations, running WIP jobs or independent Start/Finish scheduling.

**Competitive context:** Siemens documents rework/genealogy [S5]; Tulip offers configurable defect handling [S7].

**Differentiation:** The bounded same-Product quantity assignment plus preserved original job is the distinctive combination. Rework and genealogy themselves are established MES features; public material does not establish this exact mechanism.

**Evidence:** [WIP database commands](../supabase/migrations/20261001125502_unfinished_production_v1.sql), [inventory UI](../src/features/UnfinishedProducts.tsx), [WIP SQL tests](../tests/unfinished-production.test.sql); S5/S7, 2026-10-02.

### 4. Good / Scrap / Unfinished with same-Product lot lineage — B

**Factory problem:** Usable material still needing work can be miscounted as either finished demand or waste.

**Factory Lean approach:** Separate original/effective dispositions, required Remaining Work, source-linked lots/movements and partial consumption. Corrections cannot reduce created stock below already consumed quantity. No fake replacement Product or historical backfill.

**Operational value:** Engineers distinguish scrap from recoverable work; managers see available unfinished quantity and its source.

**Implementation status:** A; Recording/WIP implemented and tested; manual acceptance outstanding. Same Product and m/pcs only; no general material transformation or consumption reversal. History declaration sums are not unique stock balances.

**Competitive context:** Siemens rework/containment [S5] and Odoo quality failure handling [S12] cover related disposition concerns.

**Differentiation:** A clear bounded three-way declaration is useful for pipe operations, not novel inventory or full genealogy.

**Evidence:** WIP migration/tests above, [Recording UI](../src/features/ProductionRecording.tsx), [quantity tests](../tests/unfinished-production.test.mjs); S5/S12, 2026-10-02.

### 5. Reviewed estimates stay separate from actual results — B

**Factory problem:** Later configuration changes can rewrite apparent historical loss, and estimates can be mistaken for measurements.

**Factory Lean approach:** Trusted server recomputation saves immutable reviewed estimates from persisted context. Actual scrap/time/output remain separate with variance; comparable observations yield advisory engineer-approved future-profile calibration rather than rewriting old estimates.

**Operational value:** Managers and engineers can challenge assumptions and compare observations without losing the original basis.

**Implementation status:** V for estimation/actual review; successful manual calibration approval is A and non-blocking. Calculation tests do not prove that manual action was accepted. Legacy context gaps remain explicit.

**Competitive context:** MachineMetrics supports improvement tracking through OEE [S2]; Evocon promotes loss analysis [S4]. Those sources do not prove an identical estimate/profile approval mechanism.

**Differentiation:** Explicit provenance and estimate/actual separation are useful disciplines, not proof of superior prediction or ROI.

**Evidence:** [actuals utilities](../src/utils/production-loss-actuals.mjs), [Loss Review](../src/features/LossImpactReview.tsx), [actuals tests](../tests/production-loss-actuals.test.mjs), trusted estimate function; S2/S4, 2026-10-02.

### 6. Unit-safe, full-filtered-result Production History — B

**Factory problem:** Mixed meters/pieces, page-only totals and averaged percentages give misleading comparisons.

**Factory Lean approach:** Server filtering precedes 50-row pagination. Effective Good/Scrap/Unfinished, request/Product/unit/technician/shift/date/correction filters share full-result summaries. Physical Scrap % = Scrap / (Good + Scrap + Unfinished); shift percentages use summed output per stored shift and measurement unit. Zero-output ratios are undefined; ambiguous legacy units are excluded explicitly. Correction originals remain readable.

**Operational value:** Engineers compare like quantities and managers avoid false scrap rankings.

**Implementation status:** A; SQL/UI/full-result tests and live checks recorded; user/real-device acceptance remains open. These formulas do not redefine earlier OEE/loss metrics.

**Competitive context:** MachineMetrics has machine/shift/operation quality analytics [S2]; Tulip supports defect analysis [S7].

**Differentiation:** Transparent domain-safe summaries are a practical advantage, not a claim competitors average ratios incorrectly.

**Evidence:** [History UI](../src/features/ProductionHistory.tsx), [query/percentage helper](../src/utils/production-history.mjs), WIP migration `production_history`, [History SQL tests](../tests/production-history.test.sql); S2/S7, 2026-10-02.

### 7. Line-owned production context on Factory Floor — B

**Factory problem:** Repeating job quantities on every machine obscures the machine requiring action.

**Factory Lean approach:** Lines own current/next job, Required/Good/Remaining and planned/actual context. Machine cards emphasize physical state, flow impact and borrowing/action context; independent jobs retain their own context. Text/icons supplement status color; Product identity is separate.

**Operational value:** Production engineers can inspect a stopped machine without losing the line's demand and execution context.

**Implementation status:** A; component/desktop/390px EN/AR checks recorded. User design and applicable real-device acceptance are not universally complete.

**Competitive context:** MachineMetrics separates synchronized machine activity lanes [S3]; Tulip combines human and machine workflows [S6]; Odoo has shop-floor controls [S11].

**Differentiation:** Specific information ownership fits the target persona. Modern UI, status colors and responsive cards alone are not differentiators; no measured operator-efficiency claim.

**Evidence:** [Factory Floor](../src/features/FactoryFloorV2.tsx), [visual summaries](../src/utils/floor-visual.mjs), [execution queue](../src/utils/execution-queue.mjs), HANDOFF layout evidence; S3/S6/S11, 2026-10-02.

### 8. Delivery risk without rewriting promises or schedules — B

**Factory problem:** Forecast dates can silently become customer commitments, and urgency can trigger disruptive automatic rescheduling.

**Factory Lean approach:** Requested, independently authorized promised, buffered production target, earliest feasible and current-plan Estimated Ready stay distinct. Risk reaches Sales/Planning/Floor. Backward Find Slot suggests compatible capacity but requires normal manual confirmation; unknown overdue active completion remains unknown. Existing jobs do not cascade.

**Operational value:** Sales can see uncertainty, planners retain control, and managers see a deadline risk without a fabricated new promise.

**Implementation status:** V, implemented and live-verified on TESTING, uncommitted. The user accepted the seven recorded fulfillment scenarios; reload and EN/AR mobile checks passed. Bounded 180-day search/minute precision, not a global optimizer or guarantee.

**Competitive context:** MRPeasy documents delivery buffers/backward scheduling [S9]; Katana links priorities, allocation and manufacturing [S10].

**Differentiation:** Explicit decision/date boundaries fit manual SMB operations; backward planning and delivery-risk information are not unique.

**Evidence:** [Sales UI](../src/features/SalesOrders.tsx), [delivery context](../src/components/DeliveryContext.tsx), [latest read/forecast commands](../supabase/migrations/20261002000513_sales_fulfillment_read_consistency.sql), [Sales SQL tests](../tests/sales-fulfillment.test.sql); S9/S10, 2026-10-02.

### 9. Configurable effective flow model — C

**Factory problem:** Physical state alone does not explain a line's ability to produce.

**Factory Lean approach:** One `evaluateFlow` handles blocking, non-blocking, independent/buffer behavior, scope and explicit alternatives separately from machine status.

**Operational value:** Engineers and loss calculations reuse the same verdict.

**Implementation status:** V; flow tests cover buffers, alternative blockage and cross-line borrowing. Configuration quality matters; this is not a full discrete-event simulation.

**Competitive context:** Sepasoft explicitly documents complex equipment hierarchy, parallel thresholds and blocked/starved detection [S1].

**Differentiation:** Expected advanced operations capability; Factory Lean's particular combination is evaluated in sections 1–2.

**Evidence:** flow model, [flow tests](../tests/production-flow.test.mjs); S1, 2026-10-02.

### 10. Good-only demand progress — C

**Factory problem:** Scrap or unfinished output can falsely satisfy a customer quantity.

**Factory Lean approach:** Persisted Good drives remaining/overproduction; Scrap/Unfinished do not. Extra Good requires explicit confirmation. Quantity completion and execution Finish are distinct; Finish does not require zero Remaining.

**Operational value:** Engineers see true demand remaining; only new effective Good feeds FG fulfillment.

**Implementation status:** A for Recording acceptance; guards and controlled live tests verified. Legacy balances are preserved rather than reconstructed.

**Competitive context:** Quality/disposition distinctions are standard manufacturing concerns in Odoo/Siemens [S11/S5]. Reviewed pages do not establish identical arithmetic.

**Differentiation:** Expected correctness, not an invention of yield accounting.

**Evidence:** [progress helper](../src/utils/production-recording.mjs), [Recording commands](../supabase/migrations/20260930114159_production_recording_v1.sql), [Recording SQL tests](../tests/production-recording.test.sql), WIP migration; S11/S5, 2026-10-02.

### 11. Planning and execution retain separate truth — C

**Factory problem:** Actual delays can erase the plan and make variance meaningless.

**Factory Lean approach:** Persisted planned line/start/finish survive database-time Start/Finish; at most one ordinary active item per line. Queue derives from persisted plans. Planning lock does not block normal execution; execution never reschedules later jobs.

**Operational value:** Planners retain commitments and engineers see actual variance.

**Implementation status:** V; execution/assignment regressions and live acceptance recorded. This is manual item execution, not automated PLC integration.

**Competitive context:** MRPeasy production scheduling [S9] and Odoo work-order processing [S11] establish broad planning/execution parity, not every Factory Lean invariant.

**Differentiation:** Necessary operational foundation; explicit separation supports other advantages.

**Evidence:** [execution commands](../supabase/migrations/20260928091323_production_execution_v2_phase_one.sql), [retain plan correction](../supabase/migrations/20260928091903_keep_planning_after_actual_start.sql), execution queue/SQL tests; S9/S11, 2026-10-02.

### 12. Reasoned replanning and freeze history — C

**Factory problem:** Silent changes hide who moved a job and why.

**Factory Lean approach:** Later replanning/unscheduling stores before/after, reason, actor/time and revisions. Unscheduling retains prior-scheduling truth. Locks and database write guards apply; first scheduling differs from replanning. Rate/setup/calendar determine duration; slots are advisory. Compact unscheduled demand sits above Gantt for downward drag.

**Operational value:** Planners can explain decisions without automatic cascading changes.

**Implementation status:** V, frozen Planning rules; live native drag/persistence/unschedule recorded. First-schedule reason behavior and post-drop scroll were not newly reverified in the latest checkpoint.

**Competitive context:** MRPeasy offers production scheduling [S9]; Daftra documents plans, manufacturing and activity histories [S14/S15].

**Differentiation:** Audited controlled scheduling is expected; no claim those products lack locks or reasons.

**Evidence:** [Planning UI](../src/features/ProductionPlanning.tsx), [planning model](../src/utils/planning.mjs), [revision migration](../supabase/migrations/20260927213517_planning_lock_and_revisions.sql), [planning write guards](../tests/planning-order-write-guard.sql); S9/S14/S15, 2026-10-02.

### 13. Server-time, factory-timezone shift windows — C

**Factory problem:** Browser clocks, midnight and changing shift definitions can corrupt attribution.

**Factory Lean approach:** Server timestamp and factory timezone resolve inclusive-start/exclusive-end windows, including overnight/DST; overlapping active windows are blocked. Manual overrides require authorization/reason and preserve automatic/selected IDs. Historical IDs/NULL remain unchanged after edits.

**Operational value:** Supervisors compare recorded shifts without invented historical assignments.

**Implementation status:** A; server/DST/overnight and controlled live checks verified. Manual acceptance remains; preview can lag refresh and does not override submission authority. No payroll/employee roster or shift business-date workflow.

**Competitive context:** MachineMetrics analyzes shifts [S2]; Tulip documents timezone considerations [S6].

**Differentiation:** Sound expected attribution, not unique shift analytics.

**Evidence:** [shift migration](../supabase/migrations/20261001093627_shift_time_windows_v1.sql), [shift SQL tests](../tests/shift-time-windows.test.sql), [Shift configuration](../src/features/ProductionShifts.tsx); S2/S6, 2026-10-02.

### 14. Per-person permission authority — C

**Factory problem:** Titles and preview modes can be mistaken for permission to change production.

**Factory Lean approach:** Explicit factory/person module-action grants authorize commands and reads; role templates are configuration aids. View As cannot elevate actual grants. Membership and database checks remain authoritative.

**Operational value:** Managers can grant concrete operational actions without relying on title assumptions.

**Implementation status:** V; person/factory isolation tests and normal audited TESTING grant setup recorded. No production security certification or complete release-hardening claim. Owner permission backfill is not implemented by this work.

**Competitive context:** Odoo documents user access, groups and record rules [S13]. Sophisticated authorization exists elsewhere; different configuration models do not prove superiority.

**Differentiation:** Expected security capability, with explicit semantics useful to this product.

**Evidence:** [person permissions](../src/features/PersonPermissions.tsx), [preview intersection](../src/utils/permission-preview.mjs), [snapshot authorization tests](../tests/snapshot-authorization.test.sql), [architecture](architecture.md); S13, 2026-10-02.

### 15. Operational reads separated from large histories — C

**Factory problem:** Loading Audit/Loss context on every Floor refresh slows operational work.

**Factory Lean approach:** Lazy paginated Audit/Loss/Production History and fulfillment readers; retained operational snapshot keeps its authorization/caps. History errors stay local and refresh retains already loaded results. Some mixed histories remain in the snapshot.

**Operational value:** Operators can navigate current state without repeatedly transporting the largest histories.

**Implementation status:** V with larger-data monitoring open. Prior controlled SQL JSONB-text measurement was 7,588,943 → 252,306 bytes; this is not HTTP bytes. Prior bounded refresh run had zero timeouts, not indefinite stability.

**Competitive context:** MachineMetrics and Tulip have dedicated operational/analytical views [S3/S6]; their internal transport architecture was not inspected.

**Differentiation:** Implementation-quality enabler, not comparative speed or proprietary architecture.

**Evidence:** [consumer inventory](snapshot-loading-inventory.md), [lazy migration](../supabase/migrations/20261001080237_lightweight_snapshot_lazy_history.sql), [lazy SQL tests](../tests/lazy-history.test.sql), HANDOFF measured run; S3/S6, 2026-10-02.

### 16. Explicit production demand, FG reservation, shortage production and dispatch — C

**Factory problem:** Producing already available stock or dispatching someone else's reserved stock disconnects sales from operations.

**Factory Lean approach:** Approval reserves free FG, allocates eligible incoming, then generates exact shortage as Sales Production. New Good feeds FG receipts; Scrap/WIP do not. Dispatch records physical departure, with full-order hold or explicit complete-line early release. MTO defaults to no auto-refill; typed MTS Min/Max uses projected free stock and separate low-priority replenishment. Locks/retry IDs prevent duplicate commitments; scheduled work never moves automatically.

**Operational value:** Sales, Warehouse and Planning share quantity truth without adding full ERP scope.

**Internal demand extension:** Authorized manual creation now records `INTERNAL_PRODUCTION`, a required reason, authenticated creator/display name and server timestamp. `orders:create` remains explicit per-person authority, with a clear Internal Production label. Existing legacy origins remain unrecorded. Sales shortage and Min/Max demand stay automatic-only, and Planning remains manual. This is operational completeness/parity (C), consistent with established MRP manual manufacturing capabilities (S8/S16), not a new Strong Differentiator. The useful combination is keeping Customer Demand, Stock Replenishment and Internal Production distinct.

**Implementation status:** V, implemented and live-verified on TESTING, uncommitted; the user accepted all seven recorded scenarios, with reload, EN/AR mobile and concurrency/regression checks. Single-factory balances, one Product occurrence per order, m/pcs, no arbitrary partial dispatch or historical opening-stock inference.

**Competitive context:** MRPeasy reserves stock/incoming and creates missing manufacturing [S8]; Katana allocates stock by priority [S10]; Odoo documents Min/Max [S16]; Daftra links sales and production [S15].

**Differentiation:** Necessary SMB manufacturing parity. Specific manual-control/risk choices are evaluated in section 8. This is implemented, not a future candidate.

**Evidence:** [Internal origin migration](../supabase/migrations/20261002151519_internal_production_origin.sql), [Internal regression](../tests/internal-production.test.sql), [fulfillment migration](../supabase/migrations/20261001233948_sales_fulfillment_v1.sql) plus its five forward corrections, [Warehouse](../src/features/Warehouse.tsx), Sales UI/tests; S8/S10/S15/S16, 2026-10-02.

### 17. English/Arabic operational parity — C

**Factory problem:** Mixed-language teams need readable operations without reversed chronology or ambiguous codes.

**Factory Lean approach:** EN/AR labels, RTL chrome, LTR identifiers and Gantt chronology, shared quantity/duration meanings, responsive operational cards/forms.

**Operational value:** Teams can use the same recorded facts across languages.

**Implementation status:** V for recorded component/desktop/390px checks; applicable real-device touch acceptance remains open. No independent Arabic usability study or universal accessibility claim.

**Competitive context:** Daftra's Arabic manufacturing manuals establish regional language/operational coverage [S14/S15].

**Differentiation:** Expected Gulf/Arabic-market capability; engineer-specific workflow may help but Arabic itself is not unique.

**Evidence:** [Arabic](../src/locales/ar.json), [English](../src/locales/en.json), Floor/History/Planning tests and HANDOFF visual evidence; S14/S15, 2026-10-02.

## Candidate / planned differentiators

Keep these separate from the seventeen implemented groups:

- **P — Complete improvement loop:** root cause → responsible action → verified effectiveness → measured operational/financial value. Current capture/estimate/actual review is not a completed CAPA system. Lean data foundations do not prove an implemented end-user workflow.
- **P — Maintenance Requests/Gantt and financial analysis:** explicitly unimplemented in HANDOFF. Maintenance as a stop reason/history is not preventive scheduling; loss quantities are not demonstrated money saved.
- **I — Automated machine signals, structured quality checks, advance WIP-operation planning, selected external integrations:** current research candidates only; no roadmap approval or completed implementation asserted.
- **Not future:** Sales reservation/shortage/dispatch/Min-Max/backward suggestions now exist and are listed under verified implementation, live-accepted on TESTING. Do not duplicate them as proposals.

## Competitive opportunities

Apply the core loop before prioritizing. Recommendations require discovery, user approval and a separate implementation task. These labels rank product fit, not competitors.

| Opportunity / present gap | Official reference | Factory problem and strategy fit | Product priority / reason |
| --- | --- | --- | --- |
| Responsible corrective action, due date, evidence and effectiveness review — P/I | Tulip CAPA [S17]; Odoo continuous improvement [S18] | Stops recur when diagnosis never produces accountable verified action. Directly completes Find cause → Action → Verify. | **HIGH:** close the existing loop before adding unrelated modules; retain a small factory workflow. |
| Stop-linked corrective/preventive maintenance, capacity-aware downtime window — P | Odoo requests/calendar [S19] | Engineers need a repair task and an intentional service window. Connect Capture loss → Action → Plan. | **HIGH:** implement narrowly around machines/events; avoid a full enterprise asset system. |
| Selected machine signals with operator reason confirmation — I | Tulip OPC UA/app capture [S6]; MachineMetrics monitoring [S2/S3] | Manual capture can miss short stops and delay reliable observations. Improves evidence for Capture loss/Verify. | **MEDIUM:** pilot a few compatible machines only after integration/cost discovery; never claim current automatic collection. |
| Small structured quality checks tied to Recording/WIP — I | Odoo checks [S12]; Tulip defects [S7] | Disposition alone does not explain why output was rejected. Add reason/measurement evidence for Find cause. | **MEDIUM:** concentrate on pipe defects/checks; avoid certification/compliance scope without demand. |
| Transparent loss-value assumptions and before/after savings review — P/I | MRPeasy costs [S8]; MachineMetrics improvement analytics [S2] | Owners need a defensible value estimate, not minutes multiplied by an invented universal cost. Completes Measure value. | **MEDIUM:** validate factory-specific costs, attribution and counterfactuals first; no automatic ROI promise. |
| Advance reservation/queue for WIP operations — I | Siemens execution/rework [S5] | Recorded processing cannot show future secondary-operation workload. Could improve Plan/Execute. | **LOW:** prove planning pain first; preserve original assignment and avoid full routing-engine expansion. |
| Narrow interchange with existing business systems — I | MRPeasy customer-order CSV import [S8] | Re-entry of real demand is friction. Fits Plan when traceable, unit-safe and permission-controlled. | **MEDIUM:** choose a proven customer need; a generic integration marketplace is premature. |
| Full accounting/payroll/procurement suite or enterprise genealogy parity — I | Daftra manufacturing/cost context [S14]; Siemens [S5] | Broad administration is valuable elsewhere but enlarges scope beyond the loss-improvement loop. | **DO NOT PURSUE:** integrate existing tools where justified; avoid generic ERP duplication. |

## Future marketing / sales claims

This is an evidence bank, not polished copy. Confidence concerns implemented behavior, not commercial effectiveness or uniqueness. A-status claims must retain their acceptance qualifier until accepted.

| Potential factual claim | Evidence | Confidence / qualification |
| --- | --- | --- |
| Factory Lean distinguishes physical machine downtime from modeled production impact using captured demand and flow context. | Section 1 loss model/tests/trusted persistence | **High** for mechanics; estimates depend on inputs and missing context remains incomplete. |
| A borrowed alternative remains temporarily assigned until its transfer is explicitly ended, even if it stops. | Section 2 commands/flow/SQL regressions | **High** for current rules; not a market-uniqueness claim. |
| Unfinished quantity can be processed on a compatible secondary unit while preserving the original Product Item's plan. | Sections 3–4 WIP commands/tests/live evidence | **High** implementation evidence; manual WIP acceptance pending; same Product/unit, recorded processing only. |
| Only Good output reduces remaining production demand; Scrap and Unfinished remain separate. | Sections 4/10 quantity/SQL checks | **High** implementation evidence; execution Finish is a separate action. |
| Execution retains planned times and records actual Start/Finish with server time. | Section 11 execution guards/tests | **High** for implementation; no automatic equipment capture claim. |
| Shift and History results preserve recorded attribution and separate unlike measurement units. | Sections 6/13 resolver/full-result tests | **High** implementation evidence; manual acceptance outstanding. |
| Approved Sales demand uses available finished stock and incoming commitments before creating the remaining production shortage. | Section 16 fulfillment/SQL/live scenarios | **High** TESTING evidence; live-verified and user-accepted, uncommitted. |
| Delivery forecasts remain separate from requested/promised dates and advisory slots require planner confirmation. | Section 8 forecasts/UI/live delay scenario | **High** TESTING evidence; bounded feasibility and unknown completion limitations remain. |

### Claims intentionally rejected

- Best MES, world-first, globally unique, competitors cannot do this, or cheaper/faster than competitors: no comparative deployment/cost evidence.
- Other downtime products count only stopped minutes: contradicted by Sepasoft line modeling and Evocon production-time treatment.
- Competitors lack rework/WIP, backward planning, reservations, Min/Max, shift analytics, permissions or Arabic: official sources establish related capabilities.
- Production is automatically scheduled/rescheduled, WIP has a separate running lifecycle, every shift has historical attribution, or mixed-unit quantities form one total: false for current implementation.
- Actual loss equals estimated loss, profiles prove historical truth, calibration was manually accepted, or financial ROI is already measured: unsupported.
- AI-powered/predictive maintenance, universal real-time telemetry, full ERP/WMS/genealogy, zero future timeouts, universal mobile/accessibility acceptance: not implemented or not verified.

## Competitor evidence register

All entries researched **2026-10-02 (Asia/Riyadh)**. Official documentation/help or vendor release/product references only. Statements are narrow summaries, not audited installations. Pages may be plan/version/configuration dependent. Search-index-only entries are explicitly marked; their detailed behavior needs a direct-document or demo follow-up before stronger claims. No extra regional product is added merely to inflate the comparison.

| ID | Official source / URL | What was established and access boundary |
| --- | --- | --- |
| S1 | [Sepasoft — Downtime Detection Modes](https://docs.sepasoft.com/articles/user-manual/downtime-detection-modes) | Direct page: complex hierarchy, parallel thresholds, initial/key-reason line cause and blocked/starved handling. Strong evidence against claiming flow-aware downtime is unique. Sepasoft is a manufacturing solution in the Ignition ecosystem, not a capability inherent to every Ignition installation. |
| S2 | [MachineMetrics — What is MachineMetrics?](https://docs.machinemetrics.com/docs/getting-started/what-is-machinemetrics/) | Direct page: machine monitoring, downtime/bottleneck visibility and machine/shift/operation OEE. Product description, not proof of Factory Lean's contextual estimate method. |
| S3 | [MachineMetrics — Machines & Machine View](https://docs.machinemetrics.com/docs/product-guides/machines-machine-view-guide/) | Direct guide: synchronized execution/downtime/job/parts/program lanes, Good parts and timeline pan/zoom. Does not establish identical cross-line temporary borrowing. |
| S4 | [Evocon — Six Big Losses](https://evocon.com/articles/the-six-big-losses-in-manufacturing/) | Direct article: availability/performance/quality losses; Evocon's unscheduled-time exclusion and terminology differ from the article's framework. Do not equate its label “planned stops” with every Factory Lean planned activity. |
| S5 | [Siemens — Execution Discrete 2601 changes](https://blogs.sw.siemens.com/opcenter/whats-new-in-opcenter-execution-discrete-2601/) and [Execution Discrete product](https://www.siemens.com/en-gb/products/opcenter/execution/discrete/) | Official indexed release content supports containment/rework/scrap and genealogy integration; indexed product content supports reconfigurable execution/problem solving. Direct release fetch timed out; product fetch returned unsupported markdown. Broad enterprise context only; exact WIP mechanism not established. |
| S6 | [Tulip — Machine Monitoring](https://support.tulip.co/docs/machine-monitoring) | Direct help: machine states/attributes/reasons/triggers, OPC UA setup and human-data apps. Configurable platform, not a finished equivalence to this app. |
| S7 | [Tulip — Defect Tracking](https://support.tulip.co/docs/defect-tracking) | Official indexed help supports configurable defect workflows and root-cause context. Not proof of the same quantity conservation/assignment commands. |
| S8 | [MRPeasy — Customer Order Details](https://www.mrpeasy.com/resources/user-manual/crm/customer-orders/details/) | Direct manual: stock/future-production booking, missing-product manufacturing, shipment picking, estimated costs/dates, actual cost/profit and CSV import. Strong parity evidence for fulfillment, not identical release constraints. |
| S9 | [MRPeasy — Backward Production Scheduling](https://www.mrpeasy.com/resources/user-manual/settings/system/enterprise-functions/backward-scheduling/) | Official indexed manual: latest-time scheduling from due/delivery dates, configurable buffer and Enterprise-plan condition. Direct fetch forbidden; S8 also documents its backward option. No plan-price comparison. |
| S10 | [Katana — Sales Order Priorities](https://support.katanamrp.com/en/articles/5914297-how-to-manage-sales-order-so-priorities) | Direct help: MTS stock allocation priority, MTO-linked manufacturing and synchronized priority. Do not infer Factory Lean's immutable promise dates from it. |
| S11 | [Odoo 19 — Manufacturing](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/manufacturing.html) | Official indexed documentation: scheduling/work-order processing, shop-floor controls, scrap and related operational modules. Broad parity; not every Factory Lean guard. |
| S12 | [Odoo 19 — Quality Checks](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/quality/quality_management/quality_checks.html) and [Quality Failure Locations](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/quality/quality_management/failure_locations.html) | Official indexed help: manual/configured product/manufacturing inspections, work-order check context and failure storage. Quality control exists; not the same unfinished-lot model. |
| S13 | [Odoo 19 — Access Rights](https://www.odoo.com/documentation/19.0/applications/general/users/access_rights.html) | Official indexed help: user access, groups and refining record rules. Direct fetch failed; no claim all authorization is title-based. |
| S14 | [Daftra — Manufacturing Order Guide](https://docs.daftra.com/user_manual/دليل-أوامر-التصنيع-في-دفترة/) | Direct Arabic manual: BOM/operations/material issues/costs, finished output into warehouse and activity history. Arabic manufacturing/ERP coverage, not exact flow-impact logic. |
| S15 | [Daftra — Production Plans Guide](https://docs.daftra.com/user_manual/دليل-خطط-الإنتاج-في-دفترة/) | Official indexed Arabic manual: invoice/Sales Order links to production and quantity/product controls. Direct fetch failed; no equivalence claim about FG reservation or execution transitions. |
| S16 | [Odoo 19 — Configure Reordering Rules](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/purchase/products/reordering.html) | Official indexed manual: minimum/maximum replenishment and measurement-unit configuration, shown for purchase procurement. Establishes common Min/Max concept, not identical manufacturing trigger semantics. |
| S17 | [Tulip Library — CAPA Management](https://library.tulip.co/apps/capa-management) | Official indexed app description: root cause, actions, evidence, due dates and assignees. Useful candidate pattern; library description is not proof of effectiveness or automatic savings. |
| S18 | [Odoo 19 — Continuous Product Improvement](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/manufacturing/workflows/continuous_improvement.html) | Official indexed guidance: Quality/Helpdesk problem identification and quality alerts. Does not establish an exact Factory Lean loss-to-value loop. |
| S19 | [Odoo 19 — Maintenance Requests](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/maintenance/maintenance_requests.html) and [Maintenance Calendar](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/maintenance/maintenance_calendar.html) | Official indexed help: corrective/preventive requests, responsibility, duration, work-center blocking and calendar. Direct requests fetch timed out; narrow maintenance pattern only. |

Older [architecture.md](architecture.md) and [phase-one-improvements.md](phase-one-improvements.md) retain foundation/future labels from earlier phases. Use their invariant explanations, not their historical feature/migration counts, to judge the current product. The newest HANDOFF and forward migrations establish current Planning, WIP, Shift and Sales implementation.

## Differentiator update log

| Date | Change / classification | Competitive research change |
| --- | --- | --- |
| 2026-10-02 | Initial evidence record: 17 implemented groups, 3 Strong Differentiators / 5 Competitive Advantages / 9 Parity; 8 future opportunities. Sales V1 is implemented, live-verified and user-accepted on TESTING; uncommitted. Calibration/WIP/real-device limits retained. | Reviewed nine competitor offerings: Siemens Opcenter, Tulip, MachineMetrics, Evocon, Sepasoft on Ignition, MRPeasy, Katana, Odoo and Daftra. Sepasoft flow modeling and established MRP fulfillment narrowed uniqueness claims. |
| 2026-10-02 | Corrected Sales/Warehouse and Delivery Risk to implemented and live-verified on TESTING after explicit user acceptance. Added authorized Internal Production as parity within section 16, preserving the three distinct origins and legacy history. | Existing official MRPeasy/Odoo manual-manufacturing references support operational completeness; no new uniqueness claim or unrelated research change. |
