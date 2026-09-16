# Factory Lean

A bilingual manufacturing and Lean operations application for one factory per SaaS account. The existing application is preserved: Next.js, Supabase and GitHub remain the foundation. Vercel is deferred at the user's request; the application can run as a normal Node.js server, with a Docker deployment option.

## What works

- Supabase email/password authentication and an email-confirmation callback.
- Factory creation, editable profile/logo/timezone, join codes, employee requests and approvals.
- Thirteen starting roles, custom roles and configurable module/action permissions.
- Areas, production lines, production cells, machines, manual tables and nested work centers.
- Product capabilities, alternative work centers and operator assignment history.
- A graphical factory floor, status filters, daily production targets and clickable KPIs.
- Atomic status changes, downtime reasons/subreasons, restart plans, responsibility and transfer information.
- Production orders and an append-only output ledger with retry protection.
- Six management report views, Pareto analysis, date/location filters and server-authorized CSV export.
- Factory-scoped support grants, expiry and application access auditing.
- English/Arabic dictionaries, RTL layout, responsive navigation and touch controls.
- A fictional Nova factory: five areas, two lines, twelve work centers, three products, eight materials and future-module seed relationships.

See [requirements](docs/requirements-checklist.md) and [test evidence](docs/test-results.md) for the exact verification status. A functioning development application is not a production security certification. Detailed security/encryption review is explicitly deferred until after feature acceptance.

## Infrastructure status

GitHub repository: `mallouh2/factory-lean-platform` (public, source of truth).

| Environment | Supabase project | Status |
|---|---|---|
| Development | `factory-lean-development` / `jjcvfysjmqimvnumxasm` | Healthy; six migrations; fictional demo |
| Testing | `factory-lean-testing` / `silmfbpjyepalnggwulp` | Healthy; same six migrations; separate credentials and test data |
| Production | Not provisioned | Deferred until feature acceptance and deployment review |

Vercel project inspection still returns HTTP 403 for `mrabumallouh12-9286/factory-lean-platform`. No working hosted preview or production URL is claimed. This does not prevent local development, testing or portable Node deployment.

## Local installation

Use Node.js 22 or newer (Node 24 was used for verification):

```sh
npm ci
cp .env.example .env.local
```

Set `APP_ENV=development`, `APP_ORIGIN=http://localhost:3000`, `SUPABASE_URL`, and `SUPABASE_PUBLISHABLE_KEY` for the development project. All application environment variables stay on the server. No service-role key is used by the application.

```sh
npm run dev
```

Open `http://localhost:3000`. For an optimized build:

```sh
npm run build
npm start
```

`APP_ORIGIN` must match the actual browser origin, including the port. Configure the exact `/auth/confirm` URL in Supabase Auth's redirect allowlist and keep email confirmation enabled. Outbound email delivery and hosted callback behavior still require verification with the eventual deployment and mail configuration.

## Database installation

Apply the six files in `supabase/migrations/` in filename order to a **new empty** Supabase project. Use Supabase CLI migrations or the connected migration integration; never apply undocumented schema changes. Do not run proposal files.

The existing development and testing databases already have all six migrations. The connected integration assigns execution timestamps different from the original filenames: [migration mapping](docs/database-migrations.md). Do not blindly run `supabase db push` against these existing projects or reapply migrations. Reconcile the documented migration history first if switching to CLI deployment.

Create subsequent migrations with:

```sh
npx supabase migration new descriptive_change_name
```

The schema includes factory isolation, permissions, status/downtime/output events, audits, private logo storage and relational foundations for future inventory, BOM, costing, procurement and Lean improvements.

## Demo setup

The development Nova factory and its users are already provisioned. The requested `ADMIN` alias resolves to `DEMO_EMAIL` only in development; it uses actual Supabase authentication and the password supplied privately by the user. No password or bypass is compiled into the application. Set `DEMO_EMAIL=admin@nova.example.test` in development only.

Demo accounts:

| Account | Purpose |
|---|---|
| `admin@nova.example.test` | Factory owner; development `ADMIN` alias |
| `manager@nova.example.test` | Factory manager |
| `operator@nova.example.test` | Technician/operator |
| `support@nova.example.test` | No automatic factory access |

For a new development/testing project, set `APP_ENV` and supply the owner's `DEMO_PASSWORD` through your shell's environment or secret manager, then run:

```sh
node scripts/create-demo-credentials.mjs
node scripts/seed-demo.mjs
```

The first command creates an ignored credential file, with generated passwords for the other demo accounts. The second produces ignored `.env.demo-seed.sql`. Apply that file only to the selected non-production project using the connected SQL integration or a PostgreSQL client, then apply `supabase/seeds/nova_targets.sql`. These are documented seed operations, not schema migrations. `DEMO_CREDENTIAL_FILE` selects a separate credentials file for testing. Keep the generated files private; never commit them. Credentials do not change on an ordinary seed rerun.

## Try the application

1. Sign in as the development owner and confirm the **DEMO DATA** banner.
2. Open the factory floor and select the stopped Cutting Machine.
3. Inspect its reason, operator, restart information and recent status history.
4. Update its restart plan, then change its status to Running. The downtime event closes; history remains.
5. Select a center with an active order and record newly produced/rejected quantities.
6. Open Production orders to set a daily target or add an order; use Products to manage product data.
7. Open Work centers to configure a manual station/cell, parent, operator, capabilities and alternatives.
8. Open Reports; compare dates and locations, switch through all six reports and export downtime CSV.
9. Use Factory settings to view/regenerate the join code. Approve a requesting employee and assign a role.
10. Switch to Arabic and check the reversed layout. Resize to tablet/mobile to use the navigation drawer.

OEE shows **Insufficient data** until valid observations exist. Production quantities are total output, including rejects; good output is total minus rejects. Daily targets are explicit dated records, not an assumed sum of lifetime order targets.

## Structure

```text
src/app/             Next.js pages and same-origin HTTP routes
src/components/      Navigation, dialogs, fields and status indicators
src/features/        Factory floor, configuration, people and report screens
src/services/        Supabase sessions and reusable authorization
src/locales/         English and Arabic dictionaries
src/utils/           Timezone, downtime, utilization, OEE and CSV calculations
supabase/migrations/ Applied schema and business-command migrations
supabase/seeds/      Fictional data templates without real credentials
supabase/tests/      Transactional database checks
supabase/proposals/  Unapplied proposals reserved for the later security review
tests/               Calculation and functional-flow checks
docs/                Architecture, requirements, test evidence and migration mapping
```

Next.js/React provide the UI/server, Supabase JS/SSR provide provider-supported sessions, and TypeScript checks the source. There is no ORM, chart library, global-state framework or monorepo tooling. No new production dependency was added for the completion work.

## Roles and permissions

Permissions live in database tables, not role-name checks in components. The reusable `can(module, action)` presentation check and server/database authorization use the same matrix. Actions are View, Create, Edit, Delete, Approve and Export. Owners retain factory control; delegated managers cannot grant permissions they do not hold.

Operator status controls use the `machine_status` module, separately from engineering/configuration edits. Employee approval, role changes, support grants and configuration changes are auditable. Support grants refer to a verified account by email, bind a factory-scoped role, and may be disabled, temporary or permanent. Temporary access requires expiry. Direct support API-read auditing is reserved for the later security review; application snapshot reads and exports are already audited.

## Running checks

```sh
npm test
npm run typecheck
npm run build
node scripts/check-standalone.cjs
node scripts/check-feature-flows.cjs
node scripts/check-browser.cjs
```

`supabase/tests/tenant_isolation.sql` and `operational_security.sql` are rollback-only checks already exercised during development. Detailed security expansion is now deferred as requested. `supabase/tests/administration_workflow.sql` passed the remaining administration commands in a rollback transaction. The interrupted HTTP run was supplemented with successful focused support/archive checks against standalone Node; see the evidence report.

The browser harness and functional-flow checks run against `.env.testing` and a separate ignored credentials file. They exercise the real application and Supabase, not mocked dashboard data. See [test results](docs/test-results.md) for commands, environment requirements and actual outcomes.

## Deployment without Vercel

The optimized application runs on any compatible Node hosting service. Set the server-only environment variables at runtime, use a dedicated production Supabase project, and place the service behind HTTPS.

The included Dockerfile uses Next.js standalone output, excludes real environment files, and runs as a non-root user:

```sh
docker build -t factory-lean .
docker run --env-file /secure/path/factory-production.env -p 3000:3000 factory-lean
```

The Docker recipe is provided; a Docker daemon is not available in this workspace, so an actual image build is not claimed. The standalone Node build can be verified independently. Preview/testing deployments must use the testing Supabase project. Production must never contain demo credentials or data.

## Known limitations and Phase 2

- Hosted preview/production deployment and real email-delivery acceptance remain open.
- The detailed security, encryption and production readiness review is deferred by the user.
- Permissions are module/action booleans; advanced within-module scopes are not implemented.
- Snapshot screens load up to 5,000 records per table and warn when this limit is reached. Narrowed, server-paginated screens are needed before large-history production use. CSV exports page independently and reject more than 20,000 matching events.
- Refresh is polling every 30 seconds; no PLC/IoT integration is claimed.
- OEE observation collection and full operator order workflows belong to later phases; the foundation and honest insufficiency behavior are present.
- PDF/Excel, inventory operations, procurement workflows, planning Gantt, advanced Lean tools, AI recommendations and HR/Hall of Fame are deliberately not exposed as finished features.

Phase 2 should build transaction-based inventory, versioned BOM/standard-vs-actual costing, finite-capacity planning, maintenance/quality workflows and verified Lean corrective actions. Keep costing separate from accounting.

## Private hosted trial

The optional Sites adapter deploys this same source and Supabase-backed application to a private Cloudflare Worker. `npm run build:sites` builds the adapter; the existing `npm run build` / `npm start` Node workflow remains unchanged. GitHub remains the source of truth; Sites receives a deployment mirror of the same commit.

The registered trial origin is `https://nova-factory-lean.sandy-cream-0608.chatgpt.site`. Its runtime uses the fictional development factory, server-only Supabase configuration and the existing development ADMIN alias. It is a private demo, not the production factory environment. Publication success is confirmed by the hosting service before handing the URL to the owner.

Additional pinned development dependencies are required only to adapt the existing Next.js routes to Workers: Vinext/Vite, Cloudflare's Vite plugin/Wrangler, and matching React build plugins. No product UI or business logic was replaced. The adapter preserves Next's generated route declarations after building.

The owner has deferred the expanded security/encryption review until all planned phases are complete. Existing authentication, authorization, RLS and history protections remain enabled. Phase 2 waits for hands-on Phase 1 feedback.
