# Architecture decisions

GitHub is the source of truth. Schema changes are reviewed SQL migrations, applied in development, tested, then promoted to isolated testing and production Supabase projects. Application previews on Vercel use testing data only. Production never shares a database or credentials with previews.

The application uses Next.js App Router and TypeScript. React provides the interactive factory floor. Supabase supplies PostgreSQL, Auth and private object storage. The browser talks only to same-origin Next.js route handlers: Supabase configuration remains on the server. Requests use the signed-in user's token, never a privileged service key. RLS remains effective even if a UI permission check is bypassed.

Dependencies are selected only when necessary: Next.js supplies routing, server rendering and Vercel deployment; React supplies interactive controls; Supabase JS and SSR implement supported authentication and cookie rotation. TypeScript verifies contracts. Supabase CLI manages migration filenames and local databases. Charts use accessible HTML and SVG geometry, not a chart library. No ORM, global state library, monorepo framework, or accounting integration is required.

## Modules

- `src/app`: pages and authenticated HTTP boundary.
- `src/components`: shared presentation primitives and navigation.
- `src/features`: factory floor, work-center details, configuration, people and reports.
- `src/services`: server-only Supabase clients, permission and data access.
- `src/locales`: complete English and Arabic interface dictionaries.
- `src/utils`: deterministic manufacturing calculations.
- `supabase/migrations`: relational schema, RLS, transactional commands and audit triggers.
- `supabase/tests`: rollback-only security and database integration tests.
- `tests`: calculation, localization and configuration checks.

## Tenant and permission boundary

One membership account belongs to one factory in Phase 1. Every operational row has a factory ID. Composite foreign keys prevent references across factories. Roles belong to a factory and map module/action permissions through role permissions. Ownership is an explicit membership property; support engineers get no implicit factory access. Support grants bind a specific support user to a factory-scoped role, with disabled, temporary (expiry required), or permanent access. Permission evaluation queries current database rows rather than trusting stale JWT role metadata.

The private schema contains guarded privileged commands and authorization lookups. Exposed RPC wrappers use invoker security. Important writes require these commands; event and audit history are append-only for application users. Transactions lock a work center before closing downtime and appending a status event. Reporting clips downtime intervals to the requested time range and never fabricates OEE inputs.

## Future boundaries

Planning will consume capabilities, alternatives, calendars and order workload. Inventory will use an immutable movement ledger; available stock is on hand minus reservations. BOM and costing versions belong to products and remain independent of accounting. Lean improvements will reference downtime events and add root cause, corrective action, responsibility and verification. HR, including the Monthly Employee Hall of Fame, remains disabled in navigation until a future phase.
