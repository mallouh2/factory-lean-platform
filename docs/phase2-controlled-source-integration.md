# Phase 2 — controlled source integration, 5 November 2026

**INTEGRATED — VALIDATION INCOMPLETE.** All five approved source groups are integrated into the authoritative checkout. Automated checks below pass. Fresh browser/native-drag acceptance and dedicated Planning/material concurrent-session coverage remain unverified on this combined checkout. This is not deployment or final owner acceptance.

## Baselines and preservation

- Main: `C:\Users\Temp\Documents\GitHub\factory-lean-platform`, `development`, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`; no Git commit/index/ref operation.
- Donor: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\material-preparation-candidate-1793769667321`.
- Immutable preservation: `C:\Users\Temp\Documents\FactoryLean-Recovery\preservation-20261105-093046-381e3db6`.
- Preflight rehashed all 5,901 preserved files and included main/donor source files: zero backup failures or baseline drift. Recalculated implementation delta: 876 identical, 38 different, 24 donor-only, no main-only files.
- Integration used context-checked per-file unified patches and exclusive creation for new files. Git normalized some existing files' line endings; their normalized text matches the reviewed donor changes.
- Two shared dependencies (MaterialPreparation and factory-time conversion) preceded Planning callers. Bilingual strings were brought forward with compensation. Cumulative shared-file hunks span several stages; migrations retain their independent chronological identifiers.
- The unused donor CSS `data-drag-source` opacity rule was deliberately excluded with the unaccepted drag-source-fading experiment. No component attribute implementing that experiment was imported.

## Integration and fresh automated evidence

| Group | Recorded paths | Focused Node results |
| --- | ---: | ---: |
| Compensation/manufactured-output corrections | 9 | 52/52 |
| Planning policy, protected replanning, notifications | 13 | 140/140 |
| Historical approval and Factory Floor | 6 | 101/101 |
| Material preparation and Warehouse/recording integration | 22 | 133/133 |
| Sidebar, settings, timezone and UI consistency | 10 | 108/108 |
| Shared dependencies installed before callers | 2 | Covered by subsequent groups |

Total implementation: **38 changed + 24 added paths; zero removed**. This report and the current HANDOFF entry are additional documentation changes. Exact path/hash/method manifest: evidence `integration-files.json`.

- Full root Node suite: **1480/1480 PASS, zero skips/failures**. Focused group counts overlap and must not be added to that total.
- Main TypeScript: `tsc --noEmit --incremental false` PASS.
- Optimized Webpack production build PASS in evidence `build-app`, copied from combined main source with existing dependencies and **no environment files**. Generated Next types/config remain in that isolated copy; main config/dependency files were not replaced.
- `git diff --check` PASS. React hooks/retry/loading/permission contracts reviewed with the existing operational UX standard; no redesign or new commercial differentiation claim.
- SQL: all **153 migrations installed in order into a fresh disposable PostgreSQL 17.11 cluster**. The 141 old files and 12 donor additions retain exact SHA-256 contents.
- SQL suites: material configuration **21**, integrated material/receipt/Sales flow **64**, Quality control **45**, Quality release fixes **28**, high-Scrap **34**: **192 assertions PASS**.
- Existing Quality concurrent-session runner: **7 scenarios PASS**, including competing rejection, stock-out, Sales source reservation/retry, deferred KG COMMIT rollback and permission revocation while waiting.

## SQL isolation and fixture limits

Actual database name, server address/port and data directory were queried and compared before application SQL. Target was `factory_lean_quality_local`, loopback port **10136**, exact evidence-owned `sql-retry/data`. No existing owner database was cloned, reset, seeded or modified.

The previously cached official EDB archive matched SHA-256 `80379b2c04d51c30225532e0ae04509899141e9957ed096fe749d7fd9df8f82f`; tools were extracted only into evidence `portable-postgres`. No installed runtime, service, PATH or dependencies changed. An initial fresh helper hung on inherited process pipes; only that task-owned helper/cluster was identified and stopped, and the corrected runner used file-backed process output.

The donor material SQL suite inherited helper/data assumptions from its old preview. Initial standalone attempts failed for missing payload helpers and warehouse defaults. The successful evidence-only adapter supplied the existing fixture payload functions, the fresh factory/actor context and default warehouses through the protected warehouse command. A manufactured-output test predicate existed only within the rollback transaction; its FALSE shipped value was verified afterward. Repository tests and migrations were not rewritten to hide these setup failures. This verifies the SQL contracts, not hosted GoTrue/PostgREST services.

Both task-created clusters are stopped. Retained logs/data are disposable evidence, not a production runtime. No material worker was started.

## Remaining acceptance and release boundaries

- No fresh authenticated browser preview was operated. Owner ports 3000/4222/4242 and their Auth/database/worker bindings were not used to validate the integration. Node component/API tests are not screenshots, native drag/drop, touch or real session acceptance.
- Recheck combined-source EN/AR at desktop and 390px: navigation/chevrons, timezone edits, historical status/retry, compensation conflicts, material custody and native drag/autoscroll. Existing older screenshots do not prove these current rendered results.
- Dedicated Planning/material concurrent-session and authenticated HTTP acceptance were not repeated; the 7 live races above cover Quality/source stock only.
- Hosted migration history, Edge Function versions, scheduler infrastructure and activation prerequisites remain NEEDS VERIFICATION. Added migration files were not pushed anywhere.
- Legacy Good posting and manufactured receipt-first posting remain separate. Shipped manufactured, Maintenance and outside-shift gates remain disabled. No preview test predicate, credentials, generated config or QA-only component was promoted.
- Preserve all existing dirty work. Owner acceptance and scoped checkpoint authorization are still required before a commit. No Phase 3 deployment is authorized.

Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Phase2-caa77716736843ef99af87edfb27327f` (preflight, patches, per-stage tests, full Node/build/typecheck logs, source-safety verification and independently guarded SQL results). Product Differentiators was reviewed; the existing capability classifications remain applicable and were not inflated by source integration.
