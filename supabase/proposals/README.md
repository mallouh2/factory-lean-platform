# Deferred security review

The user requested feature completion before a detailed security review on 2026-09-15.

`audited_support_reads.sql` is an unapplied proposal, deliberately outside migrations. Automatic review rejected its broad restrictive-policy rollout. Do not apply it as part of ordinary setup. Reassess and test its read-path impact during the later security phase.

Current support access still requires explicit scoped, expiring grants. Application snapshot reads and exports are audited. Comprehensive auditing of direct API reads by support accounts remains part of the deferred review.
