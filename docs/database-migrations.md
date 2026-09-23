# Database migration history

On 2026-09-23, the existing Development and Testing migration-history versions
were aligned with the source filenames in `supabase/migrations/`. This was a
history-only repair: the already-applied SQL was not run again.

Testing also records `20260919120000_work_center_categories`, whose schema was
already live, and `20260923075311_separate_alternatives_and_preserve_open_transfers`.
The latter's recorded version had been `20260923075609`; its SQL and live
functions were checked before the history repair. Testing now has one recorded
version for each local migration, in the same order.

Development is aligned through `20260916135000_platform_session_continuity`.
The category and separate-configuration migrations remain pending there. A
future migration push can apply those source files in order.

For fresh databases, apply the source migrations in filename order.

`supabase/proposals/audited_support_reads.sql` is **not applied** and is not part
of setup. Its broad policy rollout was rejected by automatic review. The user
subsequently deferred detailed security work until feature completion.
