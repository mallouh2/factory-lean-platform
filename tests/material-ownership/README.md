# Local material ownership and independent returns acceptance

These tests target only the prepared disposable **Group 472** cluster:
`D:/FactoryLean/Preview/group472-20261110/data`, PostgreSQL `127.0.0.1:29749`,
database `factory_lean_quality_local`; signed local adapter `29750`, actual Next app
`http://localhost:29751`. The owner cluster at `29719` is prohibited.

`local.cjs` verifies server address, port, database and exact PostgreSQL data
directory before every SQL session, removes inherited hosted credential variables,
and sets statement/lock timeouts. No hosted credentials or passwords are stored here.

Prerequisites: a schema-only isolated cluster seeded with synthetic factory/accounts,
`runtime.json.context` and `qa472.context`, the forward material-ownership migration,
and `fixture.sql`. The prepared QA runtime and evidence are described in
`D:/FactoryLean/Reports/Phase4B.7.2-20261110/REPORT.md`. These runners deliberately do
not create, reset or reseed a database. Preserve the review owner runtime.

Run from this folder with Node:

```
node integration.cjs
node edge-cases.cjs
node concurrency.cjs
node api.cjs
```

Core SQL (34 assertions) and edge cases (18) roll back. Concurrency uses six pairs
of independent PostgreSQL sessions, proves actual lock overlap, and commits synthetic
fixtures only. API tests (30 assertions) sign in through the real local application
using existing QA credentials from its private `local-credentials.json`. They commit
synthetic orders/returns and restore the QA deviation threshold to zero. Repeated
API/concurrency runs intentionally create new synthetic cases; they are not read-only.
The case builder retains its historical `Group471` synthetic customer-reference
prefix; the database, schema and guard are Group472.

Evidence defaults to the phase report directory. Set
`FACTORY_LEAN_MATERIAL_TEST_REPORT` to a separate evidence directory to preserve an
earlier run. Do not point any runner at an owner or hosted environment.

The consolidated-return age test sets only synthetic issuance provenance two days
apart. It proves date-independent allocation, not observation of a real multi-day
factory run. Browser EN/AR desktop/mobile evidence is separate from automated tests.
