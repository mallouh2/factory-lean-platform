# Group 2 focused local acceptance

Run `node integration.cjs`, `node isolation.cjs`, `node concurrency.cjs` in this
folder only against the prepared synthetic Group472 runtime. The exact guard
requires PostgreSQL127.0.0.1:29749, database factory_lean_quality_local and
D:/FactoryLean/Preview/group472-20261110/data. Owner29719 is prohibited.
Requires runtime.json.context, qa472.context and fixture.sql in that isolated
database, with the Group2 migration applied. No automatic reset or reseed.

Integration:24 assertions inside ROLLBACK. Isolation:3 stronger-isolation
denials without mutations. Concurrency:4 independent-session races prove actual
lock waits and commit only new synthetic cases. Plan fixture line changes occur
before material issuance, preserving the original custody guard. Run once unless
a failure/change justifies repeating. Existing evidence/data is not deleted.

Evidence defaults to D:/FactoryLean/Reports/Group2-20261111; override with
FACTORY_LEAN_STATUS_TEST_REPORT to retain earlier runs. Existing local credentials
remain outside source. Do not redirect to owner/hosted databases or bypass guards.
No full regression suite is required for this bounded development group.
