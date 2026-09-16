# Phase 1 improvement release — 16 September 2026

This extends the existing application and database. No factory, membership, machine, order, or operational history was replaced. Existing permission grants were copied to individual users once; roles are now optional templates.

## Using the changes

1. Sign in with the existing development ADMIN account. Its alias is case-insensitive in development only. Passwords are unchanged and are not stored in source.
2. The platform dashboard lists factories. Choose **Open factory** to create an audited access window. **Create factory** creates a separate tenant without changing the administrator's original membership.
3. Open **Lines & Machines**. Expand **Create / edit line** or **Add / edit machine** to create records. Drag the dotted machine handle into a line, use arrows to reorder, or use **Move to** on touch screens. Moving a machine preserves its ID and history.
4. Choose **Configure** on a machine. Set stop impact to **Entire line**, **Downstream only**, or **No effect**. A buffer can keep production moving for its configured coverage time. Independent machines need no line. Save the arrangement; concurrent edits reject stale drafts.
5. Configure alternatives after saving the arrangement. An alternative is a candidate, not an automatic transfer.
6. Stop a blocking machine with a reason. Dashboard indicators show affected flow separately from each machine's recorded operating state. Whole-line impact includes upstream machines.
7. Open the stopped machine, select an idle configured alternative, enter a reason, and **Transfer production**. An active order is required. The command starts the alternative atomically and records original, target, order, actor, reason and time. Resuming the original records its return. An alternative stopping ends its mitigation interval.
8. **Roles & permissions** opens person-level access. Select an employee, optionally apply a template, customize and save. Merely approving membership or assigning a title grants no permissions. At minimum, give `factory:view` plus the pages/actions that employee needs. Owner grants are preserved to avoid administrative lockout.
9. Enable **Who can see and control what?** for a labeled, colored permission matrix. Template editing below it changes templates only, never existing employees.
10. Downtime shows reasons ranked by impact with a donut and selectable drill-down. Dates use factory timezone. Durations are human-readable, including Arabic.

## Data and permission architecture

- `user_permissions` is the final per-person allow-list, gated by approved membership or explicitly granted, unexpired support access. Job titles cannot grant access by themselves.
- `private.platform_admins` is an explicit allow-list, not editable user metadata. The existing verified development demo owner is the only bootstrap entry. There is no public platform-promotion endpoint.
- `private.platform_scopes` stores audited 30-minute factory access windows. Normal factory members remain tenant-isolated through existing RLS and composite foreign keys. Platform reads through the application and writes are audited.
- `work_centers` adds dependency behavior, buffer coverage and stop impact scope. Sequence provides downstream relationships. IDs and event history survive rearrangement.
- `production_transfers` records mitigation intervals and the original's return separately. Active originals/targets are unique. A checkbox cannot fabricate a transfer.
- Downtime captures line, order, rate, blocking and impact scope at event creation. Old unknown context remains unknown rather than being backfilled with today's configuration.
- Product stage supports raw, WIP, semi-finished and finished products. `production_routing_steps` supports line, warehouse/WIP and independent-machine steps with tenant-safe references. No inventory or scheduling workflow was added.
- Maintenance is a stop reason. Old maintenance history remains readable; new maintenance operational states are rejected.

## Impact ranking

The transparent priority proxy combines observed stop minutes, blocked minutes, configurable blocking weight and frequency allowance, plus equivalent production minutes when a rate is known. Factory configuration stores the weights (`impact_blocking_weight`, `impact_frequency_minutes`). Valid transfer intervals and buffer coverage reduce blocked minutes. Production-loss values are explicitly estimates, not measured losses; unknown rates display insufficient data. Unlike product quantities are not summed into a factory production-loss KPI.

## Verification evidence

| Requirement / regression | Evidence |
|---|---|
| Create factory, line, products and machines | Transactional Supabase acceptance test |
| Assign, reorder and preserve machine identity | Layout RPC acceptance; component drag/drop, move and reorder checks |
| Whole-line / downstream / no impact / independent | Pure flow tests and bilingual configuration checks |
| Buffer coverage and exact expiry | Pure timestamp boundary test |
| Configure alternatives, stop, transfer, resume | Real Supabase transaction, including immutable status history |
| Alternative interruption and original return | Transfer history acceptance test |
| Duration presentation and timezone / DST | English/Arabic unit tests and UI drill-down |
| Donut, reason drill-down, dates and notes | Isolated browser component fixture |
| Per-person permissions and same-role different access | Real RLS/command acceptance test; permission UI fixture |
| Platform lists/opens/creates factories | Real database tests and authenticated HTTP checks |
| Factory admin / operator isolation | Existing tenant and operational SQL regression suites |
| Support grant, expiry, approval and archive | Existing administration/operational SQL regression suites |
| Audit history | Transfer, platform access, status and archive assertions |
| English / Arabic RTL | Browser component checks; matching locale-key test |
| Responsive content at 390, 768 and 1280 widths | Component fixture sizing; no 390/768 content overflow observed |
| Authentication and existing status/archive commands | Real Next HTTP server against isolated testing project |
| Existing OEE, production ledger idempotency and CSV safety | Regression unit and SQL tests |

Automated suite: 18 unit tests. SQL fixtures roll back completely. HTTP checks add an archived fictional QA machine to testing only. Browser QA uses the real components with isolated fictional data and does not substitute for a fully authenticated browser journey. Real-device touch testing and a complete signed-in browser walkthrough remain recommended before wider rollout. Expanded security review remains deferred as requested; necessary tenant and authorization checks were tested.

## Limits and decisions

- This is Phase 1: routing data foundations only; no inventory transactions UI, finite-capacity scheduler, or complete maintenance module.
- Dependency flow uses ordered lines, not arbitrary branching process graphs. Configuring whole-line/downstream/no effect covers the requested cases.
- Buffers are time coverage estimates, not live inventory measurements. Lost production is estimated from configured rate, not a sensor measurement.
- An alternative must be idle and free (or assigned the same order) to accept a transfer. Actual running states remain explicit; returning the original does not silently stop the alternative.
- Factory data snapshots retain the existing 5,000-row warning limit; large-scale report pagination is a later capacity task.
- The platform access window lasts 30 minutes and is renewed, with an audit event, when the authenticated app reads the explicitly selected factory. The development admin account must not be deployed as a production bootstrap account.
- Database advisor: private control tables intentionally have RLS without client policies. Leaked-password screening is disabled in the test project; its review is deferred. [Supabase guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Before Phase 2, agree on routing branches, real buffer quantity tracking, factory-specific impact weights, and the desired production hand-back workflow after an original machine resumes.
