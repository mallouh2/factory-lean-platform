# Post-F34.1 — Production Plan and Actual Execution

Local implementation, 16 November 2026. Owner manual acceptance and hosted
rollout remain separate gates. Existing manufactured-output, Planning, machine,
Maintenance, permission and Production Stock contracts continue to apply.

An authorized person with effective Orders view/edit can remove an unstarted
order from its line or interrupt active work when actual priorities change.
Job title supplies no authority. Floor owns actual execution actions; Planning
owns explicit Unschedule/Reschedule and may display execution history. The existing
Planning reason and exceptional-change review remain in the unschedule path.
Locked unstarted plans still require the existing unlock
action. Finish Production and line Pause retain their separate meanings.

## F38/F42/F35 current clarification — 16 November 2026

Current assignment, not an ever-scheduled flag, determines mandatory Planning reasons. A wholly unassigned order may be assigned again without an explanation; preserve its replanned revision and unassigned BEFORE tuple. Changes to an assigned plan and unscheduling retain all existing reasons/impact safeguards. Normal Start/Resume does not require a timing reason. Identify a priority override only against earlier currently executable work; exclude genuine blockers and recheck under admission locks. Reasons/actors/time variances remain audited independently of Planning.

The Floor selector uses true-duration bars packed by interval overlap and a separate selected-order details panel. Native short-order selection, keyboard, touch, scales, scrolling and RTL do not edit the plan. F12 Planning lanes are unchanged.

Before arming selected execution, verify current-shift dispatch requirements against physical stock minus pending returns and other orders' valid bookings. The selected order's own valid booking is included, never subtracted twice. Do not preempt another order's booking merely to give ARMED execution priority. Preserve the existing source/compound admission path. The protected Start and allocation locks still enforce final readiness and concurrency. Reservation evidence is a read-only view of retained forecasts, with current/stale/historical labels; it cannot reconstruct overwritten historical booked amounts. No historical record or physical custody is backfilled.

## F44 operational interaction — 16 November 2026

Ordinary Start/Resume uses one click on the Floor card, fresh context and the existing protected command. Show loading immediately; retain the actor/factory/item/UUID intent before writing and reconcile ambiguous responses without inventing a retry identity. Exact rejected material/custody blockers appear inline. Only a verified, identified earlier-eligible priority override opens the reason form; Pause & Release remains reasoned and output-confirmed. Selection/history remain read-only and execution never edits the plan.

F43 bar text requires measured fit; short bars have no text inside. Their ID/product-only annotations have independent nonoverlapping label lanes; sequential production bars remain on one time track. F33 shared-stock management stays global, with read-only planned-shift reservation summaries on visible cards. A planned-window forecast is not the full remaining-work dispatch requirement, and an elapsed plan does not imply that safe selected execution requires rescheduling.

## State and identity

- **Unstarted unschedule:** existing confirmed Planning revision, reason and
  impact acknowledgement return the same item to the unscheduled queue. No
  deletion, replacement order, production start or material reconciliation.
- **Pause Order & Release Line:** require a meaningful reason, a fresh order
  fingerprint and acknowledgement that all actual output/Scrap was recorded.
  Preserve the first `actual_start`, quantities, entries, Quality and stock
  postings. Set protected interruption metadata; status becomes `planned` with
  **line/start/finish and all Planning revisions unchanged**. The interface labels
  this **Paused — line released**. Keep it in its scheduled line selector. Only
  historical paused items with no assignment need explicit Planning again.
- **Reschedule:** reuse the original capability, calendar, overlap, lock,
  Maintenance and reason/history validators. Duration uses authoritative ordinary
  remaining work, including existing WIP/compensation rules; never the full target
  again. Rescheduling alone does not resume work.
- **Resume:** start the same item with a new server-stamped current-run identity.
  No intervening reschedule is required when its approved assignment is retained.
  The first actual start stays unchanged. Pending earlier-run recording and
  Finish intents are rejected; authorized committed recording retries still
  recover their original result. Existing correction/frozen-consumption contracts
  remain unchanged.
- **Explicit priority dispatch:** Floor can choose another scheduled eligible
  item while a line is idle. A reasoned command overrides only queue order.
  The original planned window is retained, and actual run times are recorded
  separately. Normal Start still respects chronological queue order. Existing
  one-active-item, machine/stop/transfer, material, Quality and Maintenance guards
  apply to every Start/Resume.

If no ordinary work remains, use the existing Finish/review workflow; do not pause
the item into a state that cannot resume. An open machine transfer must be ended
through its own existing workflow before interruption; F34 never ends it. A
legitimate machine stop/downtime remains open and blocks unsafe new execution.
The original next-Start logic clears stale idle-line pause intent only after its
normal readiness checks.

## Material and recording conservation

Unused shift reservations are derived bookings and are released/recalculated
under the existing factory lock. Physical Production Stock, Warehouse balances,
consumption and historical custody never move on interruption/resumption.
Active work receives booking priority before an armed explicit dispatch, followed
by other planned work. All allocation uses current authoritative availability.

Explicit dispatch/resumption has a protected effective run window calculated
from remaining work and the existing line/product rate, setup and working
calendar. Shift forecasts clip that window to the authoritative current shift;
old runs' output is not subtracted a second time. Actual output/Scrap still uses
the original confirmed-recording consumption path and frozen correction factors.
Shortages remain exact and actionable; no unconfirmed inventory optimism.

An issued legacy order can be unscheduled before first Start without erasing its
custody. Before clearing its assignment, capture the **recorded pre-release line**
as immutable provenance. Existing independent raw returns continue to show and
allocate that held custody against its recorded line. This is not a claim that
physical disposition was verified. Conservative historical line-reassignment
restrictions remain; reassigning the same recorded line is supported.

**PO-0000298:** its separate 0.16 kg additive custody remains unresolved. Removal
from the line is permitted when unstarted and properly acknowledged; Start stays
blocked until authorized evidence-based reconciliation and current-shift/schedule
readiness. No owner order or historical custody is changed automatically.

## Boundary, audit and recovery

New nullable order fields distinguish current run and interruption. No historical
orders are backfilled. Private command receipts bind factory, actor, item, request
UUID, exact intent, backend and transaction; client-set session flags cannot
authorize exceptional transitions. Factory then structure locks serialize
recording, release, reservation and Start decisions. Stale fingerprints fail
before applying the action. Same actor/UUID/intent retry returns its original
result; changed intent or actor cannot reuse it.

Private run history preserves line, planned/effective window, actual run start/end,
actors, reason and cumulative before/after evidence. Closed runs and recorded
custody origins are immutable. For work already active before F34, the original
start actor/count snapshot is explicitly unknown, never invented. Existing
Planning revisions remain independent and unchanged by execution. Start/Resume
reasons are read from immutable command receipts so a subsequent pause/Finish
cannot obscure the reason the order was selected. Line Pause retains its existing
downtime/audit contract. Browsing a different dropdown option is local inspection,
not an operational command; confirmed selected-order Start/Resume is audited.

Floor uses one permission-protected, revision-bound paged scheduled-order reader
per factory. A separate **Select Production Order** line sub-screen positions
unfinished scheduled/paused work on a horizontal approved-time timeline, with
order/product/time/required/remaining/status and basic blocker information. Completed,
cancelled, zero and unknown remaining quantities are excluded from executable
selections. The reader retains history for other Floor calculations. Exact thin
duration markers are separate from readable card annotations; no minimum card
width inflates the approved duration. Desktop/mobile, EN/AR and scrolling share
the same read-only selection contract, with no Planning editor or automatic switch.
Selection never changes the actual running job; that job remains separately visible.
Start stays disabled until the complete current list is loaded and the line is free.
The server revalidates the selected assignment and authoritative materials under
the original locks; material availability is explicitly checked at Start, never
claimed ready from an approximate timeline hint. No stock is optimistically committed. Paused
orders are excluded from automatic reservation refresh until a protected Resume
arms their new current run. Physical stock is retained.

## Routine reasons, explicit changes and trustworthy outcomes

First scheduling already uses the existing reason-free Planning command. A
previously scheduled item returning from the unscheduled queue is a revision,
not a first schedule. Explicit revisions/unschedule retain reason and exceptional
impact review. Routine Start/Resume of the earliest unfinished scheduled order
on that line accepts an empty reason. Clock deviation alone does not require an
operator explanation. Pause & Release and intentional later-order override still
require a reason. The backend classifies the queue again under existing locks;
the browser cannot waive a required explanation. Starting another order while
one is active remains forbidden; explicitly release/finish the current job first.

New command receipts record whether a reason was required in their immutable
before-state evidence. A routine reason stays empty; no invented operator note.
Actual-versus-planned start/end variance is derived from preserved run times in
execution history. The existing dispatch_override field still authorizes the
protected actual-run window; it alone is not an intentional-priority metric.
No historical receipt/run or original plan is backfilled or rewritten.

The application submits through an atomic outcome wrapper around the original
protected command. A returned **REJECTED** result proves that command's
subtransaction rolled back, preserving material-error details in the local
adapter and allowing a specific user message. A **COMMITTED** receipt confirms
the action independently of whether the subsequent screen refresh succeeds.
Transport/unrecognized responses are **UNKNOWN**, never silently treated as a
failed Start. Read the actor/item/request-bound receipt and current state; absence
of a visible receipt may mean a transaction is still in flight. Retain the exact
intent/UUID in actor/factory/item-scoped browser storage across close/reload;
recovery reads do not submit another write. An explicit retry reuses that same
identity. Existing database fingerprints, singleton line, stock and retry locks
remain authoritative, including cross-client races.

Definitive rejection also has durable UUID finality. The wrapper holds admission
locks outside the failed command subtransaction and stores the rejected result
in the existing private command audit. That audit-only receipt cannot authorize
execution. A delayed wrapped or direct command with the same actor/item/intent/UUID
must retain the original rejection even after stock or the queue changes. A fresh
reviewed attempt uses a new UUID. Lost-rejection recovery validates the same exact
intent and sanitizes its material details. Historical failed attempts are not backfilled.

PO298's reported Start attempts returned HTTP422; no actual start/run/command was
committed. A rollback-only local reproduction confirmed production_stock_legacy_review
with 0.16 kg Process Additive still held. The old raw error key lacked a locale
mapping and the local adapter discarded SQL detail; that produced a misleading
refresh warning. The wrapper/API now distinguish rejection, exact shortages/custody,
unknown outcome and confirmed-success refresh failure. Zero shortages are not listed.

Recording readers project the current-run start for admission and retry identity.
Checked Finish takes the expected current-run timestamp under the same locks.
The legacy two-argument Finish remains available for untouched first executions;
it rejects F34 dispatch/resumed runs. The application uses checked Finish for all
new requests and retains its original lost-response recovery.

Unrecorded quantities from a closed interrupted run are not silently backdated or
attached to a later run. Record them before interruption; any later historical
correction/admission must use existing authorized evidence/review workflows.

## Verification and boundaries

Forward migration: `20261115070926_f34_production_execution_interruption.sql`.
F34.1 adds function-only `20261116053103_f341_plan_execution_separation.sql`.
Post-F34.1 adds function-only `20261116061538_post_f341_execution_outcomes_reasons_selector.sql`.
Final retry audit adds function-only `20261116072048_execution_rejected_receipt_finality.sql`,
preserving the first installed migration unchanged. No new table or historical row update.
It performs no table/history backfill and does not restore assignments previously
cleared through F34 or explicit owner Planning actions. It supersedes the original
F34 pause-clears-assignment behavior; the dated F34 report remains historical evidence.
F34.1 evidence: `D:/FactoryLean/Reports/F34.1-20261116/REPORT.md`.
Post-F34.1 evidence: `D:/FactoryLean/Reports/Post-F341-20261116/REPORT.md`.

**F37 — owner-accepted multi-order comparison:**
Lean opens the selected period across all production lines and orders. Each line has
a planned and an actual track on the same scale. The report compares the original
approved plan by default and can switch to the latest approved plan for every order.
Order details show original and latest approved intervals, actual runs and recorded
execution reasons. Both comparison modes use the existing revision ledger. Missing
history remains explicit.

**Future Planning Gantt visual reference:** The owner approved F37's timeline,
production bars, line organization, colors and spacing, readable time axis, short-bar
labels, hover and keyboard focus details, and responsive presentation as the reference
for a future Planning Gantt improvement. Planning must preserve scheduling, drag and
drop, rescheduling, conflict validation and operational behavior. This is design
direction for future work.

Group 6 is complete and owner-approved. Group 6A covers the Lean, Downtime and
Startup improvements. All seven Group 6B controlled validation scenarios passed.
Group 6C covers F37. Live improvement effectiveness still requires comparable
operating evidence.

Focused API/client/Planning/Floor checks, rollback lifecycle/accounting/ACL tests,
real independent-session races and EN desktop/AR mobile browser evidence are in
`D:/FactoryLean/Reports/F34-20261115/`. The report records final results, local
promotion preservation and remaining acceptance limits. No broad regression or
hosted certification is implied. No source cleanup, Git mutation, hosted write,
deployment, factory reset, inventory backfill or alternative-machine workflow.

Bounded references: [MRPeasy shop-floor Pause/Finish](https://www.mrpeasy.com/resources/user-manual/reporting/my-production-plan/details/),
[MRPeasy order scheduling](https://www.mrpeasy.com/resources/user-manual/production-planning/manufacturing-orders/),
[Fusion Operations machine work](https://help.fusionoperations.autodesk.com/en/articles/17781317-machines-view-in-mobile-app).
These support a simple operational distinction; no competitor-wide feature or
productivity claim is made.
