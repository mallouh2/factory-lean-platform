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
