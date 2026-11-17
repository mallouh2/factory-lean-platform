# Group 2: execution, machine status and line flow

Locally implemented on11November2026; owner manual acceptance and hosted rollout
remain pending. This explicitly supersedes the earlier rule that execution never
changes physical machine status. It does not change transfer lifecycle.

Start atomically associates participating machines using the original execution
assignment and moves eligible Idle machines to Running. Finish idles machines that
have no associated active work. Legitimate stops/setup/offline and open downtime
are preserved. Direct Running without active work is rejected. Status transitions
retain the original audit/history and factory/structure serialization. No output,
material consumption, order or downtime history is invented.

Line status requires current active execution and existing evaluateFlow results;
no-demand lines show Idle even if an old pause flag remains. Pause/Resume is offered
only for active work and enforced in SQL. Resume preserves later manual stops and
borrowing ownership. A new explicit Start clears a stale idle pause; it never
resumes prior completed work. Dashboard and Floor use the same persisted physical
machine statuses; effective flow remains separately blocked/clear/buffered.

The existing Floor stop form captures planned activity or unplanned reason plus
required production-impact confirmation. Backend role/impact configuration and
explicit assigned routing requirements validate the selection. A critical machine
cannot be declared harmless; noncritical configured machines may stop while work
continues. Existing compatible OPEN alternatives remain supported; no transfer is
automatically created, ended or reassigned. Buffer behavior remains in evaluateFlow.
An open stop's immutable captured impact is reused by that same flow/loss engine,
so later configuration edits do not rewrite its effect. Scheduled-stop linking
retains original permissions, approval and actor/intent replay; no scheduling feature
was added. An active order stays active during a stoppage; flow is blocked, not
silently finished. Existing recording of previously produced output is preserved.

Forward migration:20261111051107_execution_machine_status_sync.sql. Focused evidence:
D:/FactoryLean/Reports/Group2-20261111/REPORT.md. Full regression/performance/site-wide
QA remains final staged acceptance work. Group3–7 and Customer Returns are outside scope.

Brief workflow comparison: [MachineMetrics downtime guide](https://docs.machinemetrics.com/docs/product-guides/downtime/downtime-guide/)
separates machine state, reason classification and production context. Factory Lean
reuses its existing stop form and adds one validated impact choice rather than a new
workflow or telemetry/OEE claim.
