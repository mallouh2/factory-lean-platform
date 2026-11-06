# Factory Lean — Global UX Simplicity Standard

Owner-established permanent standard, 19 October 2026. **Simple by Default, Detailed on Demand.** Applies to every main screen, subpage, form, modal, drawer and operational workflow. This document specifies future design; it does not authorize implementation, approve Design System V1 or replace existing components/tokens.

## Product and task model

Factory Lean is an operational workbench for small/medium factories. Operators, planners, engineers, Warehouse employees and occasional users must understand their current work, act safely and recognize the result with minimal training. The business loop remains Plan → Execute → Capture loss → Find cause → Action → Verify → Measure value.

The interface should feel calm and precise: restrained color, clear alignment/spacing and one obvious task action. Apple-inspired clarity is a hierarchy principle, not permission to copy a visual theme, invent tokens or remove useful operational density. Use the current application CSS/components. The separate FACTORY_LEAN_DESIGN_SYSTEM.md remains preserved and unapproved.

The daily journey is **Understand → Act → Confirm**. Show what happened, its operational consequence and the next action before optional implementation details. Success is correct task completion and recovery, not fewer controls at any cost.

### Operational visual craft — owner direction, 29 October 2026

Simple must also be attractive, professional and easy to scan. Use the existing approved application typography/tokens, prominent typed quantities, compact summaries, purposeful spacing and restrained semantic color with explicit status labels. Present the operational result, work already assigned and next permitted action before supporting history. Do not turn a daily decision into a technical report or a stack of expandable panels. Keep ordinary actions direct; open a short confirmation form only when needed. Preserve critical warnings, authorization and physical consequences. Audit history stays available on demand; creating work must never visually imply physical receipt or fulfillment. Apply this principle to future work when authorized; this direction does not authorize redesigning other pages or approving the separate Design System document.

## Three information levels

1. **Essential, always visible:** page purpose, current work/status, primary action, production reference, quantities and units, critical alerts, machine stops, queue/physical blockers, required approvals and consequences. Never replace unknown evidence with a reassuring zero.
2. **Details, on demand:** supporting quantities, histories, original/corrected values, source genealogy, extended machine information and secondary actions. Use one contextual drawer or a small number of meaningful expansions; keep frequently used data visible.
3. **Advanced, authorized:** technical configuration, capability/rate setup, complex filters, specialist analysis and administration. Use existing permissions; hiding an element does not secure it.

Prefer one primary action per task surface. Keep related inputs together, prefill only from verified context, preserve selections/drafts on errors and avoid duplicate entry. Secondary actions may use an action menu; required daily actions must not become a repeated hunt through menus. Do not add a universal Beginner/Advanced toggle.

Technical IDs, hashes, raw JSON, protocol versions and database errors belong in support details, not ordinary operational instructions. Use plain labels and actionable failures. A confirmation is justified by a real destructive/physical consequence or existing approval requirement, not every save.

## Production correction UX specification — implemented locally in Phase4C

The source entry determines Product, production reference, unit, official value, current correction revision and source context. Users must not re-enter them. Show the official value beside the proposed value. Keep Meter/Piece/KG explicit; Scrap is KG, discarded production quantity is a separate field when WIP conservation requires it.

**Reason:** one editable text field, labelled “Reason for correction” / “سبب التصحيح”. Optional suggestions: data entry mistake, measurement error, duplicate recording, incorrect Scrap quantity, incorrect Good quantity and missing information. Arabic labels should express the same meanings. Selecting a suggestion fills the same editable field. Typing directly always works; no Other gate, compulsory category, reason code or second reason field. Retain the actual explanation, not only the suggestion ID. Explain an empty/too-short reason inline and preserve the draft. “Duplicate recording” is an explanation, not a new void/delete capability; existing physical-output constraints still apply.

**Technician:** entry → corrected quantity → select/type reason → Submit for approval. Result: “Pending approval” / “بانتظار الموافقة”; show “Official quantity remains …” with the correct unit. Preserve the original official value. Do not show a generic Applied/Saved toast that implies inventory changed. If an employee lacks existing correction-submission authority, explain that an authorized person must submit; job title does not grant access.

**Approver:** same compact form → Save correction. With effective Orders approve, the database approves/applies it atomically, including self-correction. Result: “Correction approved” / “تمت الموافقة على التصحيح”. No redundant self-approval screen. Correcting production does not approve a Scrap cause, Quality disposition or saved Lean/Loss evidence.

**Review queue:** default to pending work. Show production reference, employee, official-at-request value, proposed value/unit, reason, submission time, Approve and Reject. Details may show source allocations, dated occurrence, original immutable values and full audit. Current value must also be shown when it differs from the proposal's baseline. A stale proposal cannot silently overwrite newer facts: explain “The record changed. Review the latest quantity and submit a new correction.” Rejecting requires a short explanation, retained in audit. Never rebase or silently change the requested values.

If a Good decrease requires source selection, retain the existing physically identifiable source workflow. Pooled inventory remains explicitly unattributed. Proposed allocations reserve nothing; stock can change while a request is pending, so approval revalidates availability/commitments and can fail safely. A source/stock conflict must remain visible, not hidden behind an advanced panel.

**Retries/recovery:** preserve the request UUID and exact intent. A pending/approved request can be recovered by its original submission ID. Unknown response outcome must not generate a fresh UUID or clear the draft. Approval retries retain their decision UUID. Browser durable draft/retry UI remains Phase 4, not implemented by this foundation.

**Current UI compatibility:** Phase4C replaces the legacy immediate-save dialog with the protected pending/self-approval workflow and a Production review destination. Status feedback distinguishes Pending from Approved. See production-recording-v3-phase4c.md for current local verification and hosted acceptance limits.

## Responsive, bilingual and accessible acceptance

Use English/Arabic parity, correct RTL, logical placement and bidi isolation for codes/quantities. Support desktop, tablet and 390px width. Keep the current task and primary action visible before secondary details; do not simply stack every desktop control.

Required states: clear loading, no work, no matches, missing permission, validation error, stale proposal, unavailable service, pending, approved and rejected. Preserve context and provide the correct recovery action. Use native accessible controls, keyboard operation, visible focus, readable text and text/status labels alongside colors. An editable suggestion field must remain usable with keyboard and screen reader; suggestions cannot replace its text entry. Put validation next to the affected field and announce results without unexpectedly moving focus.

A first-time-user test should give only the operational goal, not software instructions. Observe whether the employee finds the task, understands units/status, completes it without help and recovers from a realistic error. Record completion, assistance, wrong turns and misunderstandings. Do not invent a universal time/click target before measuring the existing workflow. Verify in EN and AR, keyboard and 390px. No such visual/usability acceptance is claimed by the backend implementation.

## Lightweight current-code UX inventory — recommendations only

This inventory uses the existing components and navigation, not hosted/browser observation or user-study evidence. Entries identify structure/friction risks; they are not measured usability failures. Keep hidden Factory Overview/Semi-Finished navigation hidden and retain underlying logic. No feature/page is removed or rearranged in this task.

| Surface and current evidence | Default / daily action | Details on demand | Advanced / future simplification |
| --- | --- | --- | --- |
| Factory shell, FactoryApp.tsx | Current factory, page and authorized navigation | Account/support context | Keep View As and administration separate; generic Saved must not misstate pending outcomes |
| Factory Floor, FactoryFloorV2.tsx / CenterDetails.tsx | Physical machine state, effective flow and blocked work; inspect/act on affected resource | Machine detail and transfer history | Capability/topology setup stays in configuration; never merge physical status with flow |
| Production requests, ProductionOrdersV2.tsx / CreateProductionOrder.tsx | Current items and next legitimate execution action | Request/item history and material requests | Keep multi-item identity and queue order; reduce repeated reference entry |
| Production recording, ProductionRecording.tsx | Selected work, dated context, Good/Scrap KG and required WIP information | Startup/remaining-work context when relevant | Replace the all-purpose correction flow only under Phase 4 approval; no misleading pending save |
| History, ProductionHistory.tsx | Relevant rows, units and one clear selection action | Existing correction/source/history details | Eighteen defined columns and multi-mode filters create a density risk; retain specialists' filters on demand without hiding units |
| Planning/Gantt, ProductionPlanning.tsx | Waiting/scheduled work, candidate line/slot and conflicts | Replanning history, affected resource evidence | Specialist zoom/filter/slot controls remain available; keep reason/locks near the action |
| Production readiness/transfers | Queue-ready versus physically-ready and exact blocker | Resource/ownership detail | Do not hide OPEN transfer ownership or add automatic machine restart |
| Maintenance repairs, Maintenance.tsx / MaintenanceRequest.tsx | Assigned/open requests and next action | Supporting repair/history fields | Existing Repairs/Scheduling split is useful; avoid duplicated status filter decisions |
| Maintenance scheduling/actual stops | Reservation, candidate conflict, actual stop/restart and verification status | Preview evidence and physical association details | Complex capacity controls stay specialist; independent verification remains mandatory |
| Downtime capture, DowntimeCapture.tsx | Affected stopped machine, reason and resume path | Supporting notes/context | Keep physical consequences visible; avoid making configuration a prerequisite for routine capture |
| Loss review, LossImpactReview.tsx | Review status, completeness and operational conclusion | Inputs, boundary classifications and evidence changes | Model/raw diagnostics secondary; saved reviewed results immutable |
| Warehouse inventory/receiving/output, Warehouse*.tsx | Available/Reserved/Incoming by unit and receive/issue/dispatch task | Source identity, WIP locations and movement history | Min/Max/source configuration secondary; never hide unidentifiable stock or double-credit receipt |
| MaterialFlow.tsx / SourceStock.tsx | Required issue/receipt and selection quantities | Lot genealogy and past movements | Physical identification and uncommitted limits must remain at the decision point |
| Warehouse purchase / purchasing / my requests | Current request status, owner and next permitted action | Supplier/history/supporting references | Keep requester/Purchasing ownership obvious; stock versus free-text routing must remain explicit |
| Sales, SalesOrders.tsx | Commitment, shortage and fulfillment action | Production links and reservation/dispatch history | Avoid implying redistribution; commitments cannot disappear behind disclosure |
| Products, Products.tsx | Product identity, unit, weight and ordinary edit | Recipe version and theoretical requirements | Recipe/configuration is a specialist task; do not put it into daily recording |
| Quality, Quality.tsx | Accepted/rejected quantities, eligibility and rejection action | Existing history drawer and Scrap explanation | Reason-library management secondary; source eligibility and units always visible |
| Lean, LeanAnalysis.tsx / LeanProblem.tsx / LeanScrapReview.tsx | Priority, evidence status and next improvement/review action | Supporting comparison/evidence | Period uncertainty and pending review remain prominent; libraries/model controls specialist |
| Reports.tsx | Selected operational question, scope and honest result | Supporting breakdown/history | Period/area/line/machine/reason/grouping controls need task-oriented presets, not arbitrary KPI removal |
| Employees/permissions, Administration.tsx / PersonPermissions.tsx / PermissionPackages.tsx | Person, effective access and intended change | Direct versus inherited grants and audit | Sensitive specialist work; keep grant consequences/ceilings and package impact confirmation visible |
| Settings/configuration, Configuration.tsx / LineBuilder.tsx / ProductionShifts.tsx | One selected configuration task | Current definitions and revision context | Specialist setup, not default operational controls; do not conceal schedule implications |
| Suppliers, Suppliers.tsx / PurchaseSupplier.tsx | Find/select a supplier | Contact and purchase context | Avoid repeated supplier entry; preserve existing approved identities |
| Audit/support/platform/onboarding | Current authorized access or onboarding action | Action history and support evidence | Keep scopes, access consequences and audit authority explicit; no silent scope bypass |

## Future priorities by daily-work impact

1. **Production recording/correction:** reduce mode choices and make official versus proposed values unmistakable. Test a first-time technician submitting a correction and an approver saving their own. Preserve permissions, reasons, source/WIP constraints and retry identity.
2. **Start legitimate production:** put the exact queue/resource blocker beside Start. Test someone distinguishing a queued-ready item from a stopped required machine. Keep queue, lock, ownership and physical readiness rules.
3. **Warehouse receipt:** make receipt versus inventory credit clear and prefill the existing source. Test acknowledgment without duplicate stock credit. Keep unit/source/quantity validation visible.
4. **Material request/issue:** retain work context when entering from Production, show requested versus issued amount and one next action. Test partial issue. Preserve authority and stock conservation.
5. **Quality rejection:** show eligible identifiable stock and Scrap KG consequence before submission. Test a reserved or unidentified source rejection attempt. Never conceal why it is blocked.
6. **Repair progress/verification:** lead with assigned work and the next action. Test completion followed by a different verifier. Keep physical stop/restart separate from repair verification.
7. **Purchase follow-up:** use status and responsibility to guide the next permitted action. Test requester receipt versus Warehouse stock receipt without duplicate entry. Keep requester ownership and explicit sourcing decisions.
8. **Sales fulfillment:** show committed, available and incoming amounts separately. Test partial fulfillment without altering existing commitments. Keep source allocation and dispatch validation.
9. **Planning a waiting item:** show capable line/slot and conflict response first. Test an attempted conflicting move with an actionable result. Keep locks, reasons, preview/fingerprint and no cascading reschedule.
10. **Scrap/Lean review:** make evidence completeness and review task obvious before analytical controls. Test unknown period allocation and an unreviewed observation. Keep cause/approval and saved-evidence boundaries.

Do not hide routine quantities behind multiple expansions, put primary actions inside a secondary menu, or hide blockers until after Submit. Detailed comparison work, source allocation and specialist configuration can legitimately require more visible information than a routine operator task.

## Comparable product patterns

[MRPeasy's production reporting manual](https://www.mrpeasy.com/resources/user-manual/reporting/) distinguishes a detailed production-plan view from a simpler portable-device kiosk. The useful adaptation here is a focused daily task surface, not a new global mode switch or adoption of its scheduling model.

[Tulip's correction guidance](https://support.tulip.co/docs/process-data-corrections-and-review) preserves original completion records and captures correction context/reason separately. The useful adaptation is traceable original/proposed/approved facts and return to the employee's task. Factory Lean's permission-based self-approval policy remains the owner's explicit decision; no regulated-compliance claim is inferred.

These are pattern references, not evidence that Factory Lean's proposed interface has passed user acceptance or outperforms those products.

## Owner-approved implementation conventions — 20 October 2026

Use one searchable Combobox when selecting an entity; never separate Search and Select fields for the same entity. Reuse accessible existing components, keep the selected value in the same field and preserve permissions. Apply when touching the selector; no platform-wide refactor is authorized.

Tables use single-row selection with one permission/state-sensitive Actions menu above the table, no row Actions column, useful default columns and optional scoped user/table preferences. Contextual export/printing stays separate. Reveal supporting information on demand; do not aggregate unrelated production into generic summary cards.

Where a table already has a meaningful record Details destination, single-click selects and double-click opens that same read-only destination. Preserve Actions → View Details and keyboard access. Ignore embedded controls and preserve normal touch behavior. Never connect double-click to editing, approval, deletion or an opener that implicitly creates data. Tables without a record Details destination retain their current behavior; do not invent screens for this convention. See `../global-table-details-approval-alert.md` for current local coverage and legacy exceptions.

Engineering: choose the simplest correct existing contract, avoid speculative abstractions/dependencies, use focused tests and at most one reasonable browser smoke pass. Defer minor noncritical cosmetics; never compromise quantities, postings, isolation, permissions or irreversible transitions. Comprehensive whole-site acceptance belongs to final testing.


## Permanent table pagination rule — 1 November 2026

**No table may offer navigation to a nonexistent next page.** Use the matching filtered result count and real page size, or an authoritative has-more contract when counts are unknown. A full raw source chunk, limit, old page or cached metadata is not proof of another matching page. Apply eligibility/search/type filters in the same scope as pagination; combine source scopes before presenting a global page.

Disable Previous on page1;disable both controls for zero matches. Search/filter changes reset to page1 or another valid page. Polling clamps only when the current page becomes invalid;retain filters,valid selection,focus and layout. Unknown/loading/error metadata must not offer Next or invent a page count. Keep intended sorting and export scope consistent. Warehouse Requests implements this rule;other independent tables were not broadly rewritten or claimed audited.


## Semantic color and Warehouse action hierarchy — 2 November 2026

Use consistent meaningful color with labels and units:blue for physical stock/information,green for available stock or actual stock increases,amber for reservations/attention,red for actual errors/outgoing or shortages,and neutral for forecasts. Restrained token-based tints support scanning;do not make every box gray or color entire operational rows indiscriminately. A reservation-only event is never shown as a physical receipt or issue.

Keep frequent operational actions beside the work;group infrequent master-data/administration/history destinations clearly. Preserve every authorized function. Selected-item history should open the same history viewer with the item preselected;avoid a second expanded history implementation inside Details. Additional evidence remains available without obsolete cross-department shortcut clusters.
