# Manufactured Output isolated acceptance

Run `node tests/manufactured-output-activation/run-local.mjs <absolute-config.json>` only against an explicitly owned, loopback-only cold copy of the Phase 4B rehearsal database. This runner mutates synthetic local fixtures. It does not provision a database or contact hosted services.

Required configuration: marker `FACTORY_LEAN_PHASE4B3_DISPOSABLE`, `root`, child `data` directory, `repo`, portable PostgreSQL `bin`, nonstandard `port`, database `factory_lean_quality_local`, prior Phase 4B evidence directory `prior`, and the exact 90 `baseline` / 62 `upgrade` migration filenames. The cold copy must contain the unchanged Phase 4B `mp_test` and `late_test` fixture helpers, 491 public/private functions, and no activation migration or deferred Export Reader. Historical migration hashes must match the original evidence inventory.

Every SQL connection verifies server address, port, database and data directory. Inherited database/platform credentials are removed. The runner applies the real candidate once, checks default-disabled privileges, executes the protected lifecycle, operational failures, seven independently connected blocking races and real local HTTP route checks. No manufactured predicate is overridden. HTTP uses fixture authentication/PostgREST transport into real SQL; it does not certify hosted JWT, Deno or browser behavior.

Results and failure logs remain under the owned evidence root. A passed scenario is recorded only after its conservation assertions. Rerun the complete acceptance on a fresh cold copy after changing migration bytes. Stop the explicitly identified disposable PostgreSQL process with its exact data directory after evidence collection; the runner leaves this final service cleanup to the operator and pauses all newly activated synthetic factories on successful completion.

`--continue` resumes a failed harness run only when the installed migration identity still matches the exact source hash. It preserves prior failure evidence and does not reapply the migration or rebuild fixtures. It is unsuitable after implementation changes.
