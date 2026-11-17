# Material custody / Start acceptance

These are the actual Group 1 SQL and independent-session test sources. They require the explicitly prepared disposable Phase 471 cluster, not the owner's preview or a hosted backend. `qa-local.cjs` verifies loopback, port 29739, database name and exact data directory before each transaction. It strips inherited database/Supabase credentials. Companion fixture IDs are synthetic, not credentials.

Prepared cluster: `D:\FactoryLean\Preview\group471-20261109\data`; PostgreSQL binaries: `D:\FactoryLean\Preview\review-20261108\pgsql\bin`. The isolated cluster is stopped after acceptance. It contains the schema-only rehearsal, synthetic masters, current-shift configuration and `qa471.context` described in the report. This is not a clean-checkout bootstrap. Do not substitute an active owner database, run old reset scripts or copy owner operational rows.

After deliberately starting and verifying that prepared test cluster:

```powershell
node tests/material-start-guard/integration.cjs
node tests/material-start-guard/deferred.cjs
node tests/material-start-guard/extra-sql.cjs
```

The first two tests roll back their operational fixtures. The extra test rolls back deliberately mismatched reservations and commits one isolated planned item for stronger-isolation denials. `fixture.sql` is the fixture builder only; it neither starts legacy work nor applies a migration. Do not run it against an owner factory.

`concurrency.cjs` uses independent PostgreSQL sessions and observes actual Lock waits. It commits synthetic race cases and gives each run a new synthetic case suffix. Accepted races and balances are retained in the report. Rerunning needs sufficient synthetic stock and a valid fixture; it is not a reset/cleanup facility.

`MATERIAL_GUARD_EVIDENCE` can name an existing evidence output directory; otherwise query/results are written under the isolated runtime. No secrets are emitted. Real HTTP/browser acceptance, worker contention and pipe lifecycle regression evidence are separate from these SQL assertions.
