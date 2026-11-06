# Historical Production approval — local inactive foundation

## 3 November2026 local policy update

The isolated4222 implementation now auto-approves only NEW historical submissions whose real actor has effective factory-scoped Orders approve, within the protected transaction. Workers without that authority remain Pending. Existing earlier-policy Pending requests retain the independent approval rule and are never retrospectively approved. Quality/receiving remain separate; ordinary late recording remains disabled. See [Factory Floor and historical V2](factory-floor-historical-v2.md) for the forward migration, exactly-once evidence, unchanged gates and isolated source location. This has not been promoted to3000 or hosted environments.

2 November 2026. This is part of the consolidated acceptance fixes, not a deployment or activation authorization. See `e2e-acceptance-consolidated-fixes.md` for final evidence and limitations.

Current-shift selection replaces the repeated declaration checkbox; the protected current-occurrence writer still validates the real server occurrence. Ordinary completed-shift admission remains disabled. Selecting Previous Shift uses a separate factory-scoped approval gate, absent/FALSE by default, and never the ordinary late-recording switch.

The reader uses the existing immutable shift schedule revisions, occurrence descriptor/resolver and plan/execution evidence calculation. It suggests the latest completed eligible occurrence in the preceding seven days. An explicit date can inspect up to 366 days, but only actual configured, verified occurrences with overlapping legitimate work are selectable. Business dates belong to the occurrence's shift-start date and captured time zone, including overnight/DST rules. It cannot certify time before a configuration revision became effective.

The submitter must have effective factory-scoped Orders view/edit. The selected technician must be that actual actor's approved membership. A pending request freezes its UUID, payload, occurrence, execution fingerprint, submitter and optional rejected-request predecessor. It creates no production entry, Quality output, stock, WIP or Scrap movement. One unresolved request per actor/item/occurrence is allowed. A rejected request is immutable; correction uses a new UUID and explicit predecessor.

Approval/rejection requires actual effective Orders approve plus the existing recording authorization. The submitter cannot approve their own request, including an owner with all grants. Job titles and selected identities do not authorize. The existing distinct union of direct/package grants is used. Approval rechecks submitter membership/edit permission and current execution/quantity fingerprint. A stale request must be rejected and resubmitted; it is never silently rebased.

Lock order is factory → structure → historical activation row → request → item, followed by the existing reentrant writer locks. The gate row is held FOR SHARE for the transaction. A row in a private, non-client-writable transaction capability table admits only the exact request/approver/transaction into the existing canonical writer. No client flag or session variable grants admission. Ordinary context checks and receipt deadlines are unchanged outside this capability. The final period guard also recognizes the immutable approved decision, preserving later integrity checks after the capability is removed.

Usable output uses `record_manufactured_output`; its existing canonical receipt, KG validation, source checks, declaration, Quality and quantity-receipt contracts remain authoritative. Measured Scrap-only declarations use the existing `record_lean_production` worker with no invented output group or stock receipt. Approval writes one immutable decision/receipt and removes the internal capability in the same transaction. An aborted approval leaves neither decision nor output. Same command UUID replays; competing decisions cannot post twice.

Entry `created_by` identifies the real approving writer; `technician_id` and the immutable historical request identify the operator. Submission/approval times remain real server times; the occurrence and `SHIFT_PERIOD` attribution preserve the claimed production period without inventing exact event timing.

The UI retains an uncertain raw request/UUID in actor/factory-scoped local storage, uses a browser lock and immediate submission guard, and can retry only that body until the outcome is known. Authoritative pending requests can also be recovered through the protected reader. Pending quantities are explicitly separated from official production. A compact Production approval queue shows operator, product/order, quantities, KG and period evidence. No late-reason field, account chooser or public activation toggle exists.

## Explicit remaining boundary

Historical recovery consumption/startup-event attribution is not certified. Today's issued input is not proof that it was available during a previous occurrence. Recovery jobs needing source consumption are excluded from selection and rejected by the command; manually adding an input lot does not bypass this. A historical issue-evidence contract is needed before enabling that case. Current recovery and same-open-shift behavior remain unchanged.

Migration: `20261102100000_historical_production_approval_v1.sql`. Apply only through a separately authorized release after migration-history verification. It depends on the existing Recording V3, manufactured-output, completion/compensation and permission contracts. Its existence does not enable any feature. Local test fixtures temporarily exercise the gate and restore it FALSE; hosted acceptance has not occurred.
