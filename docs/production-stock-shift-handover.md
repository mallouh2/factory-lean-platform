# Group 1C — Production Stock and Shift Handover

Approved scope: shared raw-material custody, shift reservations, theoretical actual
consumption and one handover screen. Groups 3–7 are unchanged. This is manufacturing
workflow parity, not a claim of measured savings or a hosted release.

## Operational contract

Production creates one independent PSR request with multiple raw materials and
editable quantities. Warehouse confirms actual physical partial deliveries from its
existing request queue. A delivery debits Warehouse once and credits shared Production
Stock once. It changes custody, not consumption. No Production Order is required.

Reservations are a derived current-shift projection, separate from physical stock.
The existing server shift resolver, Planning capability rate/unit/setup and working
calendar bound expected output by remaining order quantity and remaining scheduled
shift time, less already recorded Good and new WIP. The approved BOM's allowance is
used for forecast only. Current stock is allocated to active work first, then planned
start/ID order. Unused stock remains when reservations expire or work finishes.
Schedule, shift revision, route, capability, BOM and product-weight changes refresh
the projection; admission and physical writes always refresh under the same lock.
The local preparation worker also refreshes active work. Exact shortages block Start
in the database; no current-shift output requires a schedule/shift review.

**Owner decision: actual Scrap replaces estimated waste in consumption.** Each new
confirmed eligible recording consumes `(Good + new WIP) × frozen kg/unit + actual
Scrap kg`, apportioned by frozen raw BOM quantity/batch factors. Startup kg is already
included in Scrap and is never added twice. Consumption debits Production Stock only.
Existing manufactured-source completion/rework and compound-stock inputs retain their
original contracts; ambiguous legacy input-lot custody fails for reconciliation.
Approved corrections post only the difference using the original frozen factors;
pending/rejected corrections change no official quantities or inventory. Negative
physical stock and spending another order's booking/return hold are blocked.

The structure lock serializes deliveries, reservations, consumption, adjustments,
returns and counts. Writers reject stronger stale snapshot isolation. Actors and
exact intents bind retry UUIDs. The browser retains uncertain stock commands across
refresh and permission/transport failures and offers the same command for recovery.

Existing independent raw returns also accept shared Production Stock as a source.
Only unused, unreserved quantities may be requested. Pending returns hold custody;
partial physical Warehouse receipt transfers it once. Cancel releases only the
unreceived remainder. Legacy line-custody returns retain original provenance.

## Handover

The two-sided handover is available in the canonical local review preview. It
organizes raw counts, outstanding produced goods, line/equipment notes and
order notes on one screen. Outgoing submission retains the existing immutable
raw count and adds a linked goods and notes snapshot. Another authorized
Production user records an independent receipt. Both users and actual shift
occurrences are retained, including when receipt crosses a shift boundary.
Submitted counts are immutable, with one submission per occurrence and one
receipt per submission. Earlier raw-only handovers remain available in History.

The owner accepted the four-section workflow for Group 7 on 24 November 2026.
Raw physical counts use approximate whole kilograms. Discrepancies compare
against the same rounded quantity shown on screen. Exact stock, reservations,
consumption and historical handover evidence retain their original precision.
Produced goods retain their unit and quantity precision. The incoming form
starts with the outgoing counts and records an independent receipt after the
technician verifies the quantities and explicitly confirms. A qualifying
difference still requires an explanation. Equipment notes offer applicable
Maintenance requests and the database validates the association on save.

The approved forward migrations are `20261124120000_two_sided_shift_handover.sql`
and `20261124150000_shift_handover_whole_kg.sql`. They were verified in the
canonical local preview.

Outstanding quantities come from the source production, Quality and Warehouse
ledgers across shifts. Manufactured Output separates uninspected or held work,
released finished goods, and recoverable unfinished quantities. It subtracts
posted physical receipts. The legacy reader uses unacknowledged finished-stock
postings. Rework physically available in the source ledger remains distinguishable
from approved finished goods. Counts record evidence and never post inventory,
release Quality, acknowledge Warehouse, or change production execution or plans.

The focused local review is documented in
`D:/FactoryLean/Reports/Project-Continuity/SHIFT-HANDOVER-REVIEW.md`.
The workflow uses the established compact operational handoff and distinct
physical custody cues. [Tulip Shift Summary Reporter](https://support.tulip.co/docs/fr/shift-handoff-summary) · [Fusion Operations WIP Inventory](https://help.fusionoperations.autodesk.com/en/articles/422489-how-to-use-the-work-in-process-wip-inventory)

### Original raw-material handover contract

Production's incoming engineer counts every listed raw material, including zero.
The immutable handover stores server shift/actor/time, expected physical stock,
reserved/unreserved quantities, actual quantities, signed kg/percentage differences
and investigation notes. Expected zero has an undefined percentage. Significant
differences use the existing deviation threshold and require notes. A changed
physical-stock identity requires a refreshed count. **A handover never adjusts stock.**
Warehouse keeps the separate authorized adjustment action with a physical confirmation,
signed quantity and meaningful reason.

General and follow-up notes stay in Handover. Optional references validate the current
factory's line, machine, Product Item and existing Maintenance request. Maintenance
references require Maintenance view permission and never create a duplicate request.
Acknowledgments retain each person's evidence; unresolved follow-up notes stay first
until explicitly resolved with a note. History is paged and immutable.

## Forward cutover and safety

The migration defaults the workflow OFF. An explicit owner-only ENABLE command
activates one factory after active execution has stopped. It does not convert old
issues, balances, entries or historical transactions. Historical per-order custody
remains separate, visible and protected; blocked orders need evidence-based owner
reconciliation, never invented opening balances. A previously empty legacy order becomes eligible after all unused custody is
physically returned, with no historical consumption or live reservation. The original
legacy return worker retains its protected actor/intent retry after its compatibility
rename. Historical consumed/recorded work still needs explicit reconciliation.
Newly admitted empty planned orders
retain a stable cohort so their first recording cannot change their custody contract.

Owner preview activation is limited to its explicitly verified disposable local
factory; separate synthetic QA activation was confined to its own isolated database. No hosted activation, migration, data write, Git operation or deployment
is authorized by this document. The local review uses the existing synthetic Auth/Data
adapter, original SQL/RLS and standalone PostgreSQL; hosted Supabase certification and
broad staged acceptance remain pending.

Research adapted only the custody/consumption separation in [Fusion Operations
Material Staging](https://help.fusionoperations.autodesk.com/en/articles/3995169-how-does-material-staging-work)
and physical/available/booked distinctions in [MRPeasy Items](https://www.mrpeasy.com/resources/user-manual/stock/items/).
No lot/site/MRP or order-specific staging complexity was added.

Local evidence: `D:\FactoryLean\Reports\Group1C-20261111` (focused SQL, actual overlapping
sessions, browser screenshots, TypeScript/build and owner preservation). Final local
status and limitations are recorded in its `REPORT.md` and CURRENT-HANDOFF.md.

## Reservation refresh clarification — 11 November 2026

An eligible empty planned order can acquire current-shift reservations after later
stock delivery; recreating the order is unnecessary. Keep the existing delivery,
schedule, shift/requirements and preparation-worker hooks. Start revalidates and
allocates under the existing factory/structure locks. One server-resolved occurrence
is reused only within that locked batch; a newly opening occurrence can trigger one
bounded rebuild before readiness/admission. Forecasts retain the approved BOM,
rate/calendar/setup and remaining-shift arithmetic, never the whole multi-day target.

Floor refreshes while awaiting supply and explains exact separate legacy custody.
Available shared stock cannot erase an older unreturned issue. PO-0000298 retains
0.16 kg of issued additive; the owner confirmed it is still held by Production or
uncertain. Preserve the blocker until physical disposition is verified and reconciled
through an appropriate authorized operation. Never fabricate a return or adjustment.
Review the order's current schedule after reconciliation.

Forward migration: `20261111100931_production_stock_readiness_refresh.sql`.
Focused checks, real concurrency and shift-boundary evidence, browser results and
preservation limits: `D:/FactoryLean/Reports/Group1C-Hotfix-20261111/REPORT.md`.
