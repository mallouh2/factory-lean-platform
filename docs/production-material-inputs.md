# Current rule — 10 November 2026, Group 1B

Warehouse owns material quantity recording and reconciliation. Production material views are read-only. Use independent raw-material returns rather than an action on the original issue. The dated operator measured-use step and return instructions below are retained as historical evidence and are superseded by [the current accounting and return contract](material-accounting-independent-returns.md). The current owner preview is on D: at port 29721; old 4222 references below describe earlier verification.

---

# Physical production inputs and local material preparation

Locally implemented only in the isolated4222 source. See [verified rollout](automatic-material-preparation-rollout.md) for exact paths, migrations, evidence and release limits.

## Configure once, reuse for work

In Products, open **Physical production inputs**. Pick the product default or an existing work-center stage, then choose one physical input model:

| Physical operation | Choice | Warehouse request |
| --- | --- | --- |
| Make the finished Product from stored compound | Use compound stock | Compound KG only |
| Make the finished Product directly from raw ingredients | Make product directly from raw ingredients | Raw recipe ingredients only |
| Manufacture the compound itself | Make compound from its recipe ingredients | Its own recipe ingredients |

Set the real stock unit, Product KG per unit and compound recipe first. Do not enter both compound and its ingredients for the same stage. Orders-edit authority is checked in SQL; defaults/stage choices, revisions and retries are audited. Do not configure multiple matching stages on one production line without an unambiguous manufacturing model.

A missing/ambiguous route produces a visible warning; it never guesses, reserves or issues material. An explicit valid manual request is not blocked merely because automatic setup is missing. Existing automatic requests retain their frozen evidence; later recipe/input changes do not silently rebase prepared or issued commitments. A review block is intentional; a separate protected disposition would be needed to change those commitments.

## Daily workflow

1. Plan a legitimate capable line/start using existing Planning protections.
2. Inside the independent preparation window (default6hours), the committed plan/background worker creates the remaining physical request. Existing manual requests count; there is no automatic stock reservation.
3. Warehouse → Warehouse Requests → selected Production reference. Reserve an available quantity. OnHand stays unchanged; Reserved increases and Available falls.
4. Confirm physical issue only after real handover. Partial issue reduces OnHand/Reserved and increases Production custody. Product stock uses physically identifiable source labels.
5. Factory Floor → selected work → Record Production → Production materials → Record measured use. Enter actual measured consumption; this does not deduct Warehouse stock or record Good/Scrap again.
6. Record output and complete Quality/receiving/Sales under their existing independent rules.

Postponement beyond the window preserves the request and releases only unissued reservations. Stock already handed over stays in custody until measured use or an authorized physical return. Re-entry reuses the request and requires Warehouse to reserve again. For a line change, first release/physically return managed materials; no automatic custody reassignment occurs.

## Configuration, clocks and alerts

Planning → Custom date range and zoom has two independent decimal fields. Material preparation defaults6h; the current owner's existing warning policy is7h. The local worker runs every15seconds independently of browser pages; do not start duplicate workers. Check runtime.json and material-worker-status.json in the owner runtime root before restarting anything.

Factory timezone is an IANA setting, now Asia/Qatar for the4222 factory. Normal screens show factory-local clocks without timezone-name suffixes. Absolute UTC instants and dated shift evidence remain unchanged; normal settings append the existing prospective revision rather than rewriting history. Export/configuration metadata may retain timezone names.

Plan & material updates distinguishes request/reservation/physical-handover/release events. Production receives relevant plan/material changes; Warehouse is notified only after actual request/preparation involvement. Acknowledgment marks only the current user's audience entry; it does not delete history.

## Safety and acceptance

Raw and compound KG, finished Meter/Piece, Scrap KG and unfinished lots retain their existing distinct contracts. No automatic consumption, general inbound purchase Quality gate, per-warehouse balances, replacement production or late-recording activation was added. SQL protects factory/person permissions, stale revisions, UUID retries, Quality holds, source availability and concurrent commands. The owner now performs manual4222 acceptance, including native Gantt dragging/edge auto-scroll, which was not established by the embedded browser's drag automation.
