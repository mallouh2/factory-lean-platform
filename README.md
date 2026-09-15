# Factory Lean Platform

A bilingual manufacturing and Lean management application built for one factory per SaaS account.

**Current milestone: implementation draft, not production-ready.** Authentication, factory onboarding, a graphical factory floor, work-center configuration, downtime commands, reports and administration screens are implemented in source. The application builds and its initial calculation/localization tests pass. The database migration, authenticated user flows, tenant-isolation tests and Vercel preview have not yet been validated end to end.

## Infrastructure

- Source of truth: `mallouh2/factory-lean-platform` on GitHub, currently public. Meaningful foundation and feature commits are published.
- Supabase development: `factory-lean-development`, region `ap-south-1`. No application migration has been applied yet.
- Testing and production Supabase projects: not provisioned.
- Vercel: a preview deployment was accepted, but deployment inspection returned a scope authorization error. Reconnect Vercel with access to `mrabumallouh12-9286` before continuing deployment validation.

## Local installation

Node.js 22+ is required. Install exactly the committed dependency versions:

```sh
npm ci
cp .env.example .env.local
```

Configure `APP_ENV=development`, `APP_ORIGIN=http://localhost:3000`, and the development project's `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. These variables are server-only. Do not prefix them with `NEXT_PUBLIC_`. The application never uses a Supabase service/secret key for requests. The secret-key placeholder is reserved for a future provisioning script.

After infrastructure/environment verification and successful database setup:

```sh
npm run dev
```

Open `http://localhost:3000`. To test a production build locally, run `npm run build` and then `npm start`.

## Project structure

- `src/app`: application shell and same-origin authentication/data/upload HTTP routes.
- `src/components`: navigation, shared form/dialog/status primitives.
- `src/features`: authentication, onboarding, graphical floor, machine details, configuration, reports, people, roles, settings and support.
- `src/services`: server-only Supabase client and reusable authorization/origin checks.
- `src/locales`: English and Arabic dictionaries; RTL uses logical CSS properties.
- `src/utils`: pure manufacturing/timezone/report/export calculations.
- `supabase/migrations`: versioned PostgreSQL schema, RLS, guarded commands and audit triggers.
- `supabase/tests`: rollback-only database security tests, not yet executed.
- `tests`: Node test-runner tests.
- `docs`: architecture, implementation plan, detailed requirements checklist and test evidence.

No ORM, global state framework, chart library or accounting integration is introduced. Next.js/React provide the application, Supabase JS/SSR provide supported authentication, TypeScript checks contracts, and Supabase CLI generates migration filenames. Package versions and lockfile are committed.

## Database setup and promotion

Use the committed migration unchanged in each environment. Create new migrations with `npx supabase migration new <descriptive_name>`. Never modify an applied migration or make undocumented schema changes.

1. Verify the target project is development/testing, never production by accident.
2. Link using the Supabase CLI or apply the exact committed SQL using the connected migration integration.
3. Apply `supabase/migrations/20260915100155_phase_one_foundation.sql` to development.
4. Run `supabase/tests/tenant_isolation.sql`; it creates fixture users and factories within a transaction and rolls everything back.
5. Run Supabase security/performance advisors, address findings through new migrations, and test remaining role/support/concurrency cases.
6. Provision a separate testing project, apply the same tested migrations and load fictional demo data there.
7. After preview acceptance, promote reviewed migrations to a separate production project.

The Supabase Auth email-confirmation setting must remain enabled. Configure the exact local and Vercel callback URLs in Auth before testing signup. Use `/auth/confirm` as the callback. Logo storage is private and accepts PNG/JPEG/WebP files up to 2 MB.

## Authorization

Every operational table carries a factory ID. Composite foreign keys prevent cross-factory references. RLS evaluates current memberships and role permissions in the database. The HTTP boundary validates the Supabase user and module/action permission; the database independently authorizes commands.

Factory creation establishes an owner, initial role names and downtime reasons. Membership approval cannot assign permissions beyond the approving manager's own privileges. Role-permission configuration and support-grant management currently require the owner. Module permissions support view/create/edit/delete/approve/export; limited visibility scopes remain pending.

Important operations use transaction commands rather than direct table writes. Status changes lock the work center, close open downtime, append a status event and update the current status with audit triggers. Application users have no update/delete grant on historical events or audit logs.

Support accounts have no global access. A grant binds a named account to a factory-scoped role; temporary grants require an expiry. The support selection workflow and audit of support reads are not complete yet.

## Vercel deployment

Use this GitHub repository as the source. Configure Preview to use the testing database and Production to use the production database. Never share production credentials or data with previews. Set `APP_ORIGIN` to the exact deployment origin and `APP_ENV` to the correct environment. Keep environment values in Vercel configuration, not source files. Demo aliases must never be configured in production.

The initial preview was submitted through the Vercel integration from committed source files. Automatic GitHub preview linkage still needs verification. Terminal READY status, successful auth/database interactions and browser review are required before any production promotion.

## Demo workflow

The intended demo is Nova Plastic Pipes Factory, with PVC and HDPE lines and clearly fictional data. **The demo dataset and users have not been provisioned yet.** No working demo login is claimed.

The development-only `ADMIN` username alias maps to `DEMO_EMAIL` when `APP_ENV=development` and the Vercel target is not production. It still uses real Supabase password authentication; there is no hard-coded bypass or password. Demo provisioning must use environment-supplied credentials on isolated development/testing projects only.

## Checks

```sh
npm test
npm run typecheck
npm run build
```

See `docs/test-results.md` for executed checks and `docs/requirements-checklist.md` for open requirements. A successful build is not a security or production acceptance test.

## Known limitations and next phase

Phase 1 remains incomplete: database and demo provisioning, preview scope access, negative security tests, full Arabic/RTL/mobile verification, support read auditing, rate limiting, server-audited exports, production transactions and complete report filtering remain open. Some form timestamps currently require explicit UTC input. Reports intentionally show insufficient OEE data rather than inventing values.

Future modules remain unavailable in navigation. Phase 2 should add transaction-based inventory, versioned BOM/costing, finite-capacity planning, quality and maintenance workflows, and Lean problem/action verification. HR and the Monthly Employee Hall of Fame must remain deferred until their phase is authorized. See `docs/architecture.md` for boundaries.
