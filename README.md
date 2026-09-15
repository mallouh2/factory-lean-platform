# Factory Lean Platform

Bilingual manufacturing and Lean management application for a single factory per account.

## Current state

Infrastructure preparation only. This is not yet a working application and has not passed the Phase 1 acceptance review.

- GitHub repository: `mallouh2/factory-lean-platform` (currently public).
- Supabase development project: `factory-lean-development`, region `ap-south-1`.
- No application migrations or operational data have been applied.
- Testing and production environments are not provisioned yet.
- No Vercel deployment has been created or validated.
- GitHub write access verified with an implementation-plan commit. Application work is in progress.

## Development foundation

Node.js 22 or newer is required. Dependency versions are pinned; use `npm ci` after the lockfile is committed. Copy `.env.example` to `.env.local` and configure server-side values for the development Supabase project. Never commit populated environment files. Application routes and tests have not been implemented yet, so build/start/test scripts are reserved for subsequent milestones.

See `docs/architecture.md` for proposed module boundaries, permission enforcement, tenant isolation and future modules. These are design decisions, not claims that the corresponding features are implemented.

## Database workflow

Create migration files with `supabase migration new <name>`. Commit migrations to GitHub, apply to development, run database and tenant-isolation tests, then promote the same reviewed migrations to testing and production. Never apply undocumented SQL schema changes. Use separate Supabase projects and credentials for each environment.

## Deployment workflow

Connect this repository to Vercel. Configure Preview against the testing Supabase project and Production against the production Supabase project. Keep all Supabase configuration server-side. Verify the preview deployment with functional, permission, English/Arabic RTL and responsive tests before production promotion. Deployment setup remains pending.

## Acceptance requirements

Phase 1 includes verified authentication, factory onboarding, employee joining and approvals, configurable roles and permissions, factory structure, work centers, graphical factory floor, transactional status/downtime history, basic order visualization, six management reports, downtime Pareto analysis, audit records, scoped support access, timezone handling and an isolated Nova Plastic Pipes demo. Future planning, inventory, procurement, costing, quality, maintenance, Lean workflows and HR are reserved but not implemented.

No production-readiness score is assigned until end-to-end verification is possible. Each unimplemented or untested requirement must remain explicitly open.
