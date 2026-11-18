# F47 / F48 — stable sequence and explicit confirmed return (18 November 2026)

This section supersedes Group 3's manual-stop-first handback requirement below. Implemented locally; owner acceptance and hosted alignment remain pending.

Machine Details and the Floor machine drawer offer one Return Production to Original Machine form. Require a meaningful reason and confirmation that original equipment has recovered and been checked, all output/Scrap is recorded, and physical handover is safe. The server binds the exact loan/actual-transfer reference, order and equipment state, revalidates capability, actual line availability, required equipment, Maintenance, person permissions and current-shift materials under existing admission locks. A different unresolved original stop is not closed as the old failure. Rejections roll back all release/recovery/return effects; exact rejected or committed UUIDs retain finality. Unknown outcomes must recover the same actor/intent-bound receipt.

For an open machine loan, the actual order already remains on the borrowing line. Idle a healthy running replacement through the ordinary audited status transition, creating no downtime. Existing recovery and finish-transfer/projector/loss triggers close the original failure and loan, run the original and restore the spare assignment. Preserve any genuine spare stoppage and paused donor; do not resume the donor automatically. The whole order/run, recorded output, Quality, consumption and physical stock remain unchanged. Generic Resume on an open original loan cannot bypass this confirmed workflow.

For a true F20 actual-line transfer, the most recent committed transfer identifies the original equipment/line. Recover that original only after confirmation, interrupt the alternative execution, restore actual destination and resume the same item atomically. Keep approved line/timestamps/revisions, first start, cumulative quantities and accounting. One active order per line and one open run per item remain protected. Pending return ownership retains bookings through the internal pause, then normal current-shift reconciliation runs at the destination rate. Unsupported routing/source-work or genuine inventory/Maintenance/custody blockers remain blocked. This is an explicit return, not automatic routing or Planning.

Return command evidence stores mode, original forward reference, actor, reason, server times, before-state and confirmed outcome. Execution history includes returns alongside forward moves and runs. Public readers/writers retain factory/person permission checks; private helpers have no client grants. Existing audited tables are reused; no new inventory or transfer model or historical backfill.

Display sequence follows saved position then immutable machine ID. This resolves legacy tied positions consistently in Floor, management and row wrapping, without state/timestamp/locale dependence. No saved positions or dependency/loss semantics are rewritten. evaluateFlow remains the sole engine. Tied numeric ranks retain their existing semantics; configure distinct positions explicitly if a stricter dependency order is intended.

Evidence: D:/FactoryLean/Reports/F47-F48-20261118/REPORT.md. Migrations: 20261118065833_safe_production_return.sql, 20261118072832_confirmed_return_trigger_guard.sql and 20261118073454_preserve_alternative_return_downtime.sql; identity-verified local QA/owner installation only. The second guard closes the same confirmation bypass for all original-machine status writers, without editing the already applied first migration. The third rejects a Running/open-downtime inconsistency on a borrowed spare rather than silently closing its genuine stop while idling it. No hosted or Git operation is authorized by this contract. Older sections retain dated implementation evidence.

---

# F20 hotfix — actual alternative-line handover (17 November 2026)

This section supersedes the earlier Group 3 limitation below. Implemented and locally verified; owner review and Git approval for this hotfix remain pending.

A stopped source machine offers configured destination machines with their home line, physical availability, product/rate/unit compatibility and actionable blockers. Select a scheduled or active item with remaining work and a destination, enter a reason, and confirm all actual output/Scrap has been recorded for an active run. The protected production_line_transfer_submit command revalidates under the existing factory/Maintenance/structure/equipment locks, interrupts the source if active, sets only actual_line_id and starts/resumes the same item on the destination. An empty destination schedule is valid. A new run is never invented for an unstarted source; the first run is at the destination.

Approved line_id, planned timestamps, product routing/BOM and every plan revision are immutable during handover. Logical fixed equipment maps through audited actual handovers for recording/capability checks; other fixed dependencies outside the destination remain blockers. Existing machine borrowing is separately labeled Replace machine on the current route. Neither lifecycle automatically ends the other, resumes a stopped original, fabricates output or reconciles custody. Explicit Planning revisions remain separate and may choose the next route for interrupted planned work; previous actual runs remain historical.

One active actual item per line and one open run per item are enforced. Parent TRANSFER_LINE intent stores equipment/line/source-downtime/source-run evidence; child Interrupt/Start/Resume commands preserve existing run audit and actors. Exact actor/item/intent UUID receipts are durable: committed replay is identical, rejected identities never execute later, unknown transport outcomes require receipt recovery. Generic actual destination edits are blocked. Source-recording drafts reject after transfer; already committed recordings still replay without double consumption. No optimistic stock update is shown.

Shared Production Stock custody stays physical and unchanged; current-shift destination-rate bookings revalidate atomically, preserve existing ownership during the handover and recalculate normally after activation. Production entries, manufactured/Quality history, consumption, first actual start and remaining quantities are preserved. Unsupported source-WIP/compound-stock arrangements require a separately reviewed physical-source workflow and remain blocked. No automatic historical migration/reconciliation, arbitrary routing editor or automatic return workflow is included.

Only local forward schema installation is verified. Evidence/test limits and the owner's Product B capability blocker: D:/FactoryLean/Reports/F20-20261117/REPORT.md. F37 comparison reporting is future work.

---

# Group 3 — machine alternatives and operational clarity

Implemented locally on 17 November 2026. Owner review of this group remains pending; the owner authorized its Git checkpoint and push. This reuses existing transfer/status writers and does not change database definitions or Planning.

## Equipment continuity

Factory Floor and Machine Details use the same live transfer picker. The original must have active work, a physical Stopped state and an open downtime; its line cannot be paused. Alternatives must be explicitly configured, in the same category, non-archived, physically Idle, capable of the current product at a positive compatible rate, and free of another open transfer. The protected server revalidates permissions, assignments, maintenance and compatibility under existing locks. A displayed candidate is not a reservation.

Compatible spares on the same line, independent equipment and cross-line equipment admitted by the existing rules are supported. A paused donor can lend an eligible idle machine; the transfer retains its previous order. Permanent machine line assignments and approved order schedules never move. Critical/blocking, non-blocking, independent and buffer effects remain governed by `evaluateFlow` and the configured stop impact. No automatic substitute, new routing engine or cross-line Planning transfer is introduced.

**Physical handback:** stop a running replacement through the existing Stop Machine action, retaining the required reason/impact, then return production to the original machine. Return is disabled while the replacement is Running or its state is unknown. Existing backend triggers reject a premature handback atomically (`execution_no_active_work` for a free spare, or `line_paused` for a paused donor). Explicitly stopping the replacement first permits return, restores the prior assignment and preserves legitimate stops. No silent stop, automatic end-transfer or fabricated downtime is performed. Returning equipment does not Resume a paused donor line.

Transfer history retains original/replacement, order, reason, actor, creation, original-return and end timestamps; open ownership remains visible even if the replacement stops. Transfers preserve output, Scrap, Quality, consumption, reservations and historical custody. PO-0000298's unresolved 0.16 kg custody is unchanged.

## Interface

F43.1 keeps true-duration production bars on their actual tracks. Every ID/product label starts at the same height below the bars, wraps, and is packed horizontally without overlap. Leader lines preserve association. The scroll surface and time ticks extend at the same scale when labels need room; saved positions/durations are untouched. Very short orders retain native keyboard/touch selection, zoom and EN/AR/RTL support. Planning's F12 Gantt helper is unchanged.

Machine Details prioritizes physical status, current line/work, assignment availability and configured stop impact; timing, history and Maintenance remain on demand. Machine Edit keeps identity/assignment visible and moves rates, notes, alternatives, capabilities, loss/cost and flow settings into native disclosure sections. Controls remain mounted, retain values/permissions and use their existing commands. No operational data is saved merely by opening or closing a section.

## Verification and limits

Focused Node checks, TypeScript, rollback-only transfer contracts, an observed-lock competing-spare race and EN/AR browser checks are recorded in `D:/FactoryLean/Reports/Group3-20261117/REPORT.md`. Synthetic operational writes used only the identity-verified QA database on port 29749. Owner application-table fingerprints are checked separately. No migrations, hosted writes, deployment, reset, full regression suite or broad performance campaign is included. Existing local checks do not establish hosted alignment or final release acceptance. F37 and Groups 4–7 remain future work.
