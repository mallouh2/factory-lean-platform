# Warehouse material accounting and independent raw returns

Phase 4B.7.2 / Group 1B, 10 November 2026. Locally implemented and tested; hosted
deployment and hosted migration alignment remain **NEEDS VERIFICATION**.

## Authority and quantities

Production records output, Scrap, unfinished work and production events. Its material
panels are read-only, including for an owner using that interface. Existing per-person
Warehouse permissions authorize quantity posting: Warehouse `issue` for reservation,
physical handover and return receipt; Warehouse `edit` plus `view` for consumption
reconciliation. Orders edit alone cannot post measured consumption through API/RPC.
Owner permissions are preserved.

The protected physical-input route, recipe version, output stock unit/weight and pipe
identity determine the theoretical requirement. Existing prepared requirements retain
their frozen evidence. Issuance transfers physical stock once from Warehouse to
Production. Recording/Manufactured Output does not provide verified per-ingredient
actual measurements and does not automatically consume raw material. Never infer
actual consumption from issuance, Good quantity, Scrap or WIP.

Warehouse can explicitly reconcile a raw request's **cumulative accounted consumption**,
including a justified downward correction to zero. A reason and immutable before/after
events are required. The total cannot exceed gross issued less received returns and
pending return holds. Reconciliation makes no Warehouse inventory transaction. The
existing manufactured-input source-specific consumption command remains Warehouse-only;
the new independent return model covers RAW_MATERIAL identities only.

For each raw issuance provenance:

```
Production physically held = gross issued - accounted consumption - received returns
Available for new return/consumption = physically held - pending return allocation
Warehouse ledger delta = -physical issues + confirmed physical return receipts
```

An original issue remains fulfilled after a separate return. Gross issue history never
decreases. Start readiness additionally excludes returned and return-held quantities;
it retains the existing full approved item admission rule. A bounded partial-run
quantity contract is not implemented. Partial issuance and fractional quantities work.

## Warehouse issuance

The default is the eligible remaining BOM requirement, bounded by actual reserved or
available stock. The legal maximum is separate from that default, allowing authorized
extra feedstock. A configurable percentage in existing Warehouse Stock Settings
controls variance warnings. Zero (the initial value) warns on every difference.
Excess above that threshold requires a reason and is audited, without overriding
stock, units, compatibility, factory isolation, revision or custody protections.
An ordinary partial handover reports the unissued remainder and retains its audit.

After complete issue there is no default quantity form or raw return action. Additional
issue and reconciliation require explicit Warehouse actions. Fresh legacy generic raw
issue commands must use this protected workflow; previously committed retries replay.

## Independent return lifecycle

Production uses **Request Raw Material Return** on Factory Floor or Production Orders.
Select material, source Production line/custody, destination RAW Warehouse and quantity;
an explanation is optional. Selecting an original order is unnecessary. The command
allocates available compatible unused provenance in deterministic issuance order,
including multiple orders and older shifts/dates on the same line. It creates an
independent `MRR-` identifier and pending custody hold, without a Warehouse credit.

Warehouse finds that request in the existing Warehouse Requests search/filter/export.
Physical receipt requires the actual quantity and a confirmation; partial receipts
remain pending. Each committed receipt credits Warehouse once and removes exactly the
same quantity from Production custody. Retry IDs bind actor and exact intent. Stale
revisions fail; genuine concurrent issue/consume/return commands serialize using the
existing factory then structure locks. Returns never reopen orders, reverse output,
change Sales allocations or manufacture missing historical custody. The creator may
cancel the unreceived remainder with a reason; received history is retained.

Source order quantities and dated provenance remain internal and available on demand.
Warehouse details show actors, request/receipt quantities and timestamps. Return
events are immutable and client roles have no direct private-table write grants.

## Identities and explicit limits

PO-0000295 is the owner's parent Production Request; PO-0000296 is its single executable
Product Item. Warehouse already referenced 296 correctly. Factory Floor now uses the
item as its primary identity and labels the parent separately. No order was merged,
recreated or removed. Planning, Gantt and execution ordering algorithms were unchanged.

Warehouse raw balances remain factory-wide; a chosen Warehouse is receipt-destination
metadata, not a newly invented per-Warehouse balance engine. The existing raw model
has no lot dimension. Unassigned or unaccounted historical material is not fabricated.
Existing conservative line-reassignment protection retains original issuance history,
including after full return; resolving that separate Planning disposition needs review.
Quality holds, source compatibility, manufactured activation and physical receiving
remain independent. Customer Returns and Groups 2–7 are outside this phase.

Forward migration: `supabase/migrations/20261110060820_material_accounting_independent_raw_returns.sql`.
Evidence, including limits of synthetic multi-day provenance testing:
`D:/FactoryLean/Reports/Phase4B.7.2-20261110/REPORT.md`.

Product research informed the separate handover/receipt and material-quantity views:
[MRPeasy inventory](https://www.mrpeasy.com/resources/user-manual/stock/inventory/) and
[Odoo three-step manufacturing](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/manufacturing/basic_setup/three_step_manufacturing.html).
These are workflow references, not evidence that Factory Lean implements their full MRP.
