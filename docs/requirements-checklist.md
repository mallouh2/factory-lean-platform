# Phase 1 acceptance checklist

Updated 2026-09-15. Implemented does not imply production acceptance. The user deferred Vercel and the extended security review; neither is represented as complete.

| Requirement | Current evidence / status |
| --- | --- |
| GitHub source of truth, readable modules, milestone commits | Existing repository preserved; changes published in milestones. |
| Supabase development and testing separation | Two healthy projects; six versioned migrations applied to each. Production not provisioned. |
| Documented migrations | `database-migrations.md` maps source versions to executed versions. No undocumented schema edits. |
| Vercel preview and production | Blocked by scope HTTP 403; deferred by user. Portable Node/Docker deployment supplied. Hosted acceptance pending. |
| Secrets and environment example | Server environment only; populated files ignored; secret-free `.env.example`. |
| Email/password registration and verification | Supabase Auth and callback implemented. Existing verified demo sign-in tested. Real mailbox delivery remains unverified. |
| Factory creation, editable name/logo, timezone | Creation/onboarding implemented; private logo and settings functional test supplied. Factory timestamps and DST unit-tested. |
| Unique join code and regeneration | Guarded commands; old-code invalidation verified in database rollback test. |
| Employee requests, approval, rejection, role assignment | Implemented with backend permission checks; included in functional workflow test. |
| Initial roles and configurable custom permissions | Module/action matrix, delegated permission ceiling, reusable authorization service. Boolean permissions; arbitrary “limited sales” row rules not defined or implemented. |
| Tenant isolation and secure backend writes | Existing RLS, same-factory foreign keys, guarded commands and baseline database tests passed. Extended security acceptance deferred. |
| Sessions, password hashing, verification | Supabase Auth; validated server sessions. Production cookie/HTTPS verification awaits hosting. |
| Validation, upload restrictions, rate limits | Database constraints and allowed fields; private image validation; persisted join-code limits and provider auth limits. Broader abuse/load review deferred. |
| Scoped support access | Disabled/temporary/permanent grants, explicit factory selection, expiry, email-based grant entry. App reads/exports logged; raw API read audit proposal deferred. |
| Immutable history and audit trail | Status/output events and audit logs retained; important commands audited. Baseline write-denial tests passed. |
| Factory → area → line/cell → work center → operator | Flexible center types, parent hierarchy, operator assignment history implemented. |
| Work center operational/configuration fields | Product/order/operator, times, rates/cycles/capacity, notes, icons, alternatives, capabilities and downtime metadata implemented. |
| Two graphical factory lines and machine detail | Clickable floor/status text/icons, details and last ten status events; browser verified. |
| Status colors plus accessible text | Six distinct labeled statuses; large operator controls. Complete assistive-technology audit still pending. |
| Downtime categories, Other description, subreason | Seeded reasons, backend required Other description, preserved stop/resume events. |
| Restart plan, responsible person, alternative/transfer | Editable plan with audit history; no replacement of original stop timestamps. |
| Production orders and production output | Order progress and immutable, retry-safe output ledger; rejected quantity supported. |
| Clickable management KPIs | Daily ledger output, configured daily targets, running/stopped, downtime and active/delayed orders. No fabricated daily production. |
| OEE foundation | Observation model and validated calculation; insufficient-data state. Full collection workflow deferred. |
| Downtime analytics and Pareto | Duration clipping, machine/line/category/reason, mean/frequency, cumulative Pareto; time/area/line/machine/reason filters. |
| Six management reports | Downtime, utilization, production, operator activity, line and daily summary. All report tabs browser verified. |
| Utilization | Running/observed event coverage; unobserved time is not silently assumed productive. |
| Search/date filters/export | Report search and factory-zone windows; authorized, audited CSV with formula escaping. PDF/XLSX are future adapters. |
| Nova demo factory | Marked DEMO DATA; five areas, two lines, twelve work centers, three pipe products, materials and fictional inventory transactions. |
| Demo users and ADMIN alias | Owner/manager/operator/support accounts in isolated projects. Development-only ADMIN alias; passwords outside GitHub. |
| English and professional Arabic | Paired dictionaries, Arabic names, full RTL, factory timezone display. Dictionary parity and Arabic/mobile browser checks passed. |
| Responsive navigation and touch controls | Desktop sidebar, mobile drawer, large machine/status buttons; 390px Arabic layout checked. |
| Loading, empty states, useful errors | Implemented in screens/forms; errors preserved in dialogs and onboarding. |
| Archive confirmation and dependent guards | Confirmation UI and database active/dependent record checks; histories retained. |
| Modular architecture and dependency restraint | Feature/components/services/locales split; existing minimal runtime dependencies retained. |
| README/local install/deployment/environment instructions | Updated README, architecture, migration map, demo credential generator and test documentation. |
| Future Lean tools | Linked improvement-action foundation; 5 Why/Kaizen/5S/SMED/etc. not exposed as finished modules. |
| Future inventory/BOM/costing/procurement | Relational extension models, versioned BOM and transaction ledger; no advanced workflows claimed. |
| Future finite-capacity planning | Capability/rate/alternative foundations; scheduler, calendars and Gantt deferred. |
| Future HR/hall of fame and other modules | Disabled roadmap navigation; explicitly not implemented. |
| Feature, UX, language, database and code reviews | Results in `test-results.md`; remaining acceptance boundaries listed below. |
| Evidence-backed overall score of at least 9/10 | Not awarded. Extended security, real email and hosted deployment acceptance remain open. |

## Outstanding acceptance work

1. Restore deployment scope or choose a reachable Node hosting destination; validate preview before production.
2. Verify real signup email delivery, confirmation redirects and factory creation using that hosted origin.
3. Complete the user-deferred security/encryption review, production operational checks and broader accessibility/load testing.
4. Define row-level “limited” permission semantics when the future Sales module is specified; Phase 1 permissions are module/action grants.

Advanced operator workflows, PDF/XLSX exports, scheduling and the other future modules remain deliberately outside Phase 1. Password recovery is a recommended follow-up; it is not represented as implemented.
