# APS Phase 1A combined production foundation

25 November 2026. The owner approved Phase 1A after implementation and
verification in the canonical local preview database.

## Reused records

- `production_requests` owns the demand intent. Its Product Item in
  `production_orders` carries the product and quantity. A Sales request has
  one originating Sales Order line. A Warehouse-confirmed replenishment is an
  existing request type. Quality replacement lineage describes remedial work
  and is excluded from combining demand.
- Sales Order lines, finished-stock reservations, and incoming allocations
  own confirmed demand, supplied quantities, and existing commitments.
  Production can only be proposed against the current unstarted source
  quantity and its eligible Sales or replenishment balance.
- Existing Planning capabilities provide the candidate line and unit checks.
  The existing material resolver supplies verified recipe and routing
  evidence. Exact product identity is required even for pipe lengths that share
  a formula. The proposed quantity preserves the item's supported stock unit
  and valid integer piece increments.

## Draft contract

`aps_create_combined_order_draft` reserves a parent UUID for later use in
`production_orders` and links at least two existing requirements. Each link
retains the source Product Item and request, Sales line and order when
applicable, proposed quantity, eligible and undelivered quantities at creation,
priority, and the customer's own requested date. The parent retains product,
recipe revision, manufacturing evidence, candidate line and exact total. The
read contract presents customer requirements by priority, dated deadline and
order age, followed by required replenishment. Undated customer requirements
retain their Sales follow-up indicator. The entered quantities are proposals.

Both routines require factory-scoped Orders, Sales and Warehouse read
permission. Creating a draft additionally requires Orders edit permission.
Validation runs under the existing factory and structure locks. A source item
can appear in one draft, and duplicate source entries, quantity overruns,
invalid units, stale recipe IDs, distinct products and incompatible lines are
rejected. An identical actor-bound retry returns the same draft. Separate
identities and requests stay intact. Draft identity references are evidence
captured at admission. They create no new constraints on editing or deleting
actual operational records.

## Phase 1B boundary

Drafts live in a private schema. The reserved UUID has no operational order
row, so it cannot be scheduled, started, recorded, reserved against or offered
as incoming supply. Source orders remain usable independently. Draft quantities
and demand balances are labeled as creation evidence. The current resolver can
verify a current recipe for eligible source work. It supplies no historical
recipe evidence when older work has no verified revision. Optional stock,
cross-product recipe equivalence, automatic optimization, and changes to live
customer allocations are outside Phase 1A.

Phase 1B must revalidate source quantities, recipes, routes, priorities,
commitments, and any changed or missing source records. It must then materialize
operational parent work using the reserved UUID, protect any original source
work and existing holds, and introduce approved draft release, revision and
multi-line allocation behavior. There must be one set of recording, Quality,
scrap and material consumption entries per physical run. Warehouse receipt
must credit finished inventory once, allocate only eligible accepted stock
under complete-shipment rules, and keep allocation separate from delivery.
Legacy Warehouse acknowledgment retains its existing credit behavior.

## Verification

Applied `supabase/migrations/20261125090000_aps_combined_order_foundation.sql`
only to PostgreSQL 17.11 at `127.0.0.1:29719`, database
`factory_lean_quality_local`, with data in
`D:/FactoryLean/Preview/review-20261108/data`. Migration SHA-256 is
`4d9255fca5742468e010edf7e42a227d00446e61085748971c165d1a7c9ec528`.
This manually maintained preview has no Supabase migration ledger. The
previous local checkpoint, its installed Shift Handover objects and rounding
function, and unchanged hashes for all 185 earlier migration files provide the
history evidence for this application.

- `tests/aps-combined-order-foundation.local.sql` passed in rehearsal and
  against the installed schema. Draft identity, retry, original Sales and
  Warehouse demand links, independent deadlines, undated follow-up, compatible
  product and recipe, partial quantities, and priority were verified.
  Duplicate demand, mixed products, stale recipes, zero quantities and
  excessive quantities were rejected.
- Database permission checks rejected unauthorized reads and writes. Anonymous
  callers have no RPC access. Authenticated callers use the permission-checked
  RPCs and have no direct write grant on either private table.
- In two actual database sessions, the authenticated create RPC waited on
  the factory advisory lock held by a competing APS test claim and rejected
  the now-claimed source with `aps_duplicate_demand`. A separate two-session
  uniqueness check rejected the second write with SQLSTATE `23505`, leaving
  exactly one claim. Both probes used temporary APS-only markers and verified
  their removal.
- The draft UUID was rejected by both Planning and Start. A standalone order
  still scheduled normally inside the fixture. The draft created no production
  entries, material consumption or inventory movements. All 19 operational
  table fingerprints matched before and after. Seven F37 demo orders, both
  handovers, existing downtime evidence, and PO-0000298's issued 0.16 kg of
  Process Additive with zero returned were preserved. Both APS tables are empty
  after verification.

TypeScript and 64 focused existing contract checks passed during implementation.
The canonical preview remained reachable on port 29721. Phase 1A is a database
foundation with no UI. Operational activation, quantity revalidation and
allocation to live Planning, execution and inventory remain for Phase 1B,
pending separate authorization.

For product comparison, MRPeasy documents linking several customer demands to
one manufacturing order while preserving each order's booking.
[MRPeasy Customer Order Details](https://www.mrpeasy.com/resources/user-manual/crm/customer-orders/details/)
