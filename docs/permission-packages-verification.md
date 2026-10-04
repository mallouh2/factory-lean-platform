# Permission Packages V1 — verification record

Verified 2026-10-04 (Asia/Riyadh). Implementation continued the clean `development` checkpoint `9fa3354869249548502dc0cbfaa8ad2acdbc55af` with 74 aligned Local/TESTING migrations and 582 Node tests. No commit, push, branch/main change, DEV connection or Lean Analysis implementation.

## Architecture, scope and decisions

1. Existing architecture: `permissions` is the actual module/action registry; `user_permissions` holds direct person/factory grants. Legacy `roles`/`role_permissions` are copy-once configuration aids, independent of job titles. Approved membership, support expiry and explicit private platform access windows guard current permissions. No existing individual deny model was found.
2. New model: `permission_packages` holds factory-local named definitions and revision/server actor/time metadata; `permission_package_permissions` references actual registry rows; `member_permission_packages` is a many-to-many membership/package association. Composite factory FKs prevent cross-factory links; unique keys normalize repeated permissions/assignments. Application clients have scoped SELECT privileges and no direct writes to the new tables.
3. Effective rule: `private.effective_person_permissions(f,u)` returns SQL UNION of direct grants and all assigned package contents. `private.has_permission` preserves existing membership/support/platform-scope guards and consumes that result. Existing `can_access`, `access_matrix`, snapshot, UI/API and RLS gates retain their interfaces.
4. Multi-package behavior: any combination of available packages supplies the union of registered permissions. A person can retain zero packages and use existing direct grants.
5. Duplicates: SQL UNION resolves each module/action once. Unique assignment/content keys and normalized arrays prevent duplicate rows. Removing one package preserves permissions supplied by another package or direct grant.
6. Individual grants: independent, explicitly marked additions. Direct saves remove only explicitly omitted direct grants and insert only new grants; retained rows preserve original creation actor/time. Package assignment never writes `user_permissions`. Both grant sources remain visible where they overlap.
7. V1 override choice: additive only. No individual deny or exclusion of package-inherited permissions. To reduce inherited access, unassign the package or use a deliberately customized package. This is documented in the UI and follows the inspected model.
8. Default packages: eight broad functions, only existing registered keys. Exact initial contents are listed below. The Owner/Admin package contains all92 existing definitions, including legacy definitions that do not imply every action has a distinct current product workflow. No `production:view/manage` or Lean permission was invented.
9. Factory customization: own EN/AR names, description and contents; custom creation remains factory-local. Editing an assigned definition changes access for all its assigned persons in that factory; UI shows affected count and requires impact acknowledgment. Other factories retain independent definitions.
10. Administration: actual `roles:edit` authorizes definition/assignment/direct writes. The actor must hold every permission being granted, including package contents; factory-owner status alone is not a bypass. Existing owner member protections remain. Registered platform administration must use the existing guarded `open_platform_factory` access window; expired scopes cannot manage another factory. Approval also requires `employees:approve`, valid same-factory role and atomic existing approval behavior.
11. Compatibility: migration creates definitions without assigning packages or changing existing users/direct grants. Every baseline person/registry gate matched previous direct-grant decisions; actual snapshot reads were exercised with package-backed authority. Existing roles/support behavior remains separate.
12. Audit: existing `audit_logs`/`private.audit_change` records definition, content, assignment and removal changes with authenticated actor/server time and old/new rows. Existing direct-grant audit records actual additions/removals. Identical retries do not create duplicate business changes. Migration seeding has no human actor; it is not misrepresented as a member action.
13. UI: function selection first; advanced direct/inherited/both-source inspection and distinct effective preview; separate package/direct saves. Catalogue details/create/edit, bilingual names, actual registry checkboxes, grant ceiling disabled choices, assigned impact confirmation, conflict feedback, aborted stale member/factory reads and immediate double-submit protection. Existing member approval supports multiple packages independently of its job/position role. Approvers lacking `roles:edit` retain their previous approval flow without package management. Legacy templates are explicitly labeled copy-once.
14. Files: exact22 task files are listed below; no unrelated/generated/environment file is part of the task.
15. Migrations: TESTING-only `20261004114712_permission_packages_v1` and `20261004120533_permission_package_locked_authority`. The second rechecks `roles:edit` after acquiring the factory lock, closing the revocation-while-waiting gap; the already-applied first migration is immutable. Local/TESTING76 version/name pairs align; all74 baseline migration files and submitted SQL preserved. DEV deliberately not queried.
16. RPC/API/database: public SECURITY INVOKER wrappers `save_permission_package`, `set_member_permission_packages`, `set_member_direct_permissions`, `approve_member_packages`, and `permission_package_page`; guarded private SECURITY DEFINER helpers use an empty search path. Revisions/expected package/direct sets reject stale updates; caller-generated definition UUID plus identical-state retry handling prevents duplicate creation. Existing direct setter now performs differential writes under the same factory lock. GET `/api/permission-packages` is authenticated, guarded by the database reader and private/no-store; existing POST `/api/data` enforces strict contracts and matching permission checks. Anonymous execution and internal effective/seed helper access are revoked.
17. Tests: new Node test file30 cases and rollback SQL600 assertions. Existing16 requested coverage areas map to baseline preservation, one/multiple packages, duplicate normalization, removal retention, direct additions, engineer union, factory isolation, denied assignment/edit, authorized owner/admin, audit, existing gates, unchanged memberships/grants, localization and actual desktop/mobile inspection.
18. Focused run: **185/185** across permission packages/preview, Supply API/UX, Maintenance and Production Loss tests. Dedicated packages **30/30**.
19. Rollback SQL: package suite **600 assertions**, plus twelve existing suites: snapshot authorization, generic Planning guard, Execution, Downtime Capture, Maintenance, Warehouse master, Sales fulfillment, Supply flow99, Production Recording, Purchasing suppliers31, requester75 and Unfinished Production. All passed; temporary factory/grant/membership/platform-scope/audit fixtures rolled back. Package suite also checks actual snapshot authority, all92 registry gates, rejected membership, same-factory reads, direct-table write rejection, grant ceilings, idempotency, stale conflicts and approval rollback.
20. Full Node: **612/612** passed on final source.
21. TypeScript: **passed**.
22. Production build: **passed**, isolated `.next-check`; generated `next-env.d.ts` bytes restored. Logs are outside the repository in `C:\Users\Temp\AppData\Local\Temp\factory-permission-packages-{node,focused,build}.log`.
23. Live TESTING: A–H results and restoration are recorded below. Existing Nasser browser session and Omar membership reused; no new account.
24. Unresolved business decision: **none**. Existing permission granularity is a limit: Planning, Production execution and Product configuration share `orders`; independent separation requires a later permission-design task. Individual deny rules, package deletion/archival and release hardening remain outside V1. New registry permissions and new packages can be accepted without redesigning these tables/resolver; existing default contents do not silently adopt new permissions.

## Initial default contents (exact existing registry keys)

### Maintenance

`centers:view`, `dashboard:view`, `downtime:view`, `factory:view`, `lines:view`, `maintenance:create`, `maintenance:edit`, `maintenance:view`.

### Factory Owner / Admin

`audit:approve`, `audit:create`, `audit:delete`, `audit:edit`, `audit:export`, `audit:view`, `centers:approve`, `centers:create`, `centers:delete`, `centers:edit`, `centers:export`, `centers:view`, `dashboard:approve`, `dashboard:create`, `dashboard:delete`, `dashboard:edit`, `dashboard:export`, `dashboard:view`, `downtime:approve`, `downtime:create`, `downtime:delete`, `downtime:edit`, `downtime:export`, `downtime:view`, `employees:approve`, `employees:create`, `employees:delete`, `employees:edit`, `employees:export`, `employees:view`, `factory:approve`, `factory:create`, `factory:delete`, `factory:edit`, `factory:export`, `factory:view`, `lines:approve`, `lines:create`, `lines:delete`, `lines:edit`, `lines:export`, `lines:view`, `machine_status:approve`, `machine_status:create`, `machine_status:delete`, `machine_status:edit`, `machine_status:export`, `machine_status:view`, `maintenance:create`, `maintenance:edit`, `maintenance:view`, `orders:approve`, `orders:create`, `orders:delete`, `orders:edit`, `orders:export`, `orders:view`, `purchasing:create`, `purchasing:edit`, `purchasing:view`, `reports:approve`, `reports:create`, `reports:delete`, `reports:edit`, `reports:export`, `reports:view`, `roles:approve`, `roles:create`, `roles:delete`, `roles:edit`, `roles:export`, `roles:view`, `sales_orders:approve`, `sales_orders:create`, `sales_orders:edit`, `sales_orders:view`, `settings:approve`, `settings:create`, `settings:delete`, `settings:edit`, `settings:export`, `settings:view`, `suppliers:edit`, `support:approve`, `support:create`, `support:delete`, `support:edit`, `support:export`, `support:view`, `warehouse:edit`, `warehouse:issue`, `warehouse:view`.

### Planning Engineer

`centers:view`, `dashboard:view`, `factory:view`, `lines:view`, `orders:edit`, `orders:view`.

### Production Engineer

`centers:edit`, `centers:view`, `dashboard:view`, `downtime:edit`, `downtime:view`, `factory:view`, `lines:view`, `machine_status:edit`, `maintenance:create`, `maintenance:view`, `orders:edit`, `orders:view`, `reports:view`.

### Production Manager

`centers:view`, `dashboard:view`, `downtime:edit`, `downtime:view`, `factory:view`, `lines:view`, `machine_status:edit`, `maintenance:create`, `maintenance:edit`, `maintenance:view`, `orders:create`, `orders:edit`, `orders:view`, `reports:export`, `reports:view`.

### Purchasing

`dashboard:view`, `factory:view`, `purchasing:create`, `purchasing:edit`, `purchasing:view`, `suppliers:edit`.

### Sales

`dashboard:view`, `factory:view`, `sales_orders:approve`, `sales_orders:create`, `sales_orders:edit`, `sales_orders:view`.

### Warehouse

`dashboard:view`, `factory:view`, `orders:view`, `warehouse:edit`, `warehouse:issue`, `warehouse:view`.

## Live TESTING A–H and restoration

Factory Nova; authenticated browser actor Nasser Al Kuwari; member Omar Khalil. Browser View As was not used as authorization. Omar's permission checks used his actual authenticated database subject with `SET LOCAL ROLE authenticated`; no separate Omar browser login is claimed.

| Check | Observed outcome |
| --- | --- |
| A — one package | Browser saved Planning Engineer to Omar; one persisted assignment. Original seven direct grants unchanged. |
| B — inherited access | Existing `can_access(orders,edit)` became true; self reader showed six inherited keys and eight distinct effective permissions. |
| C — overlap | Browser added Production Engineer alongside Planning. |
| D — union | Both Planning and Production gates allowed; thirteen distinct effective permissions. Shared `orders:view/edit` appeared once. |
| E — remove one | Browser removed Production. `orders:edit` remained true from Planning; Production-only `centers:edit` became false; eight effective keys remained. |
| F — direct addition | Browser added one direct `maintenance:view`; it became effective alongside unchanged Planning, giving nine keys. |
| G — unauthorized management | Omar's authenticated assignment call was rejected with42501 `permission_denied`; no mutation. SQL suite additionally verifies definition edit/direct-write/cross-factory/ceiling denial. |
| H — EN/AR | Actual1440×900 and390×844 layouts inspected. RTL/LTR member selection, package choices, catalogue, creation editor and multi-choice approval checked. Mobile document width375 at viewport390: no page-wide overflow. Approval/editor dialogs were inspected and cancelled. |

Restoration: browser removed the QA direct Maintenance grant and final Planning assignment. All member fields match the baseline; every original direct row, creation actor and time matches digest `b49809ecf5a2a7b84d254f8e4516f340`. Zero assignments remain; eight default package definitions remain unmodified. No retained QA account/package or business inventory/production mutation. Six genuine audit entries remain: package INSERT2/DELETE2 and direct-grant INSERT1/DELETE1, all with Nasser's actor and server times. SQL fixtures and temporary platform scopes rolled back.

Screenshots: `C:\Users\Temp\AppData\Local\Temp\factory-permission-packages-20261004`, including stable mobile Arabic, English creation editor and desktop/mobile approval images. The website stays running at localhost:3000. Manual factory freeze and physical-device touch acceptance remain separate from these automated checks.

## Exact changed files

- `AGENTS.md`
- `HANDOFF.md`
- `docs/architecture.md`
- `docs/PRODUCT_DIFFERENTIATORS.md`
- `docs/permission-packages-verification.md`
- `src/app/api/data/route.ts`
- `src/app/api/permission-packages/route.ts`
- `src/app/globals.css`
- `src/components/FactoryApp.tsx`
- `src/features/Administration.tsx`
- `src/features/PersonPermissions.tsx`
- `src/features/MemberPackageApproval.tsx`
- `src/features/PermissionPackageControls.tsx`
- `src/features/PermissionPackages.tsx`
- `src/features/usePermissionPackages.ts`
- `src/utils/permission-packages.mjs`
- `src/locales/en.json`
- `src/locales/ar.json`
- `supabase/migrations/20261004114712_permission_packages_v1.sql`
- `supabase/migrations/20261004120533_permission_package_locked_authority.sql`
- `tests/permission-packages.test.mjs`
- `tests/permission-packages.test.sql`

## Product/UI review

Persona: owner/authorized administrator choosing a member's operational functions and inspecting exceptions. Function-first assignment removes repeated permission-by-permission setup; details stay available inside an advanced view. Existing handwritten CSS and native forms/dialogs are reused; no new dependency or authorization identity tied to a title.

Official references reviewed2026-10-04: [Tulip user management](https://support.tulip.co/docs/add-and-manage-users), [MRPeasy users](https://www.mrpeasy.com/resources/user-manual/settings/human-resources/users/), [Supabase database functions](https://supabase.com/docs/guides/database/functions), [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security). They support role-first administration, inspectable rights and database-enforced boundaries. Permission packages extend administration parity in PRODUCT_DIFFERENTIATORS section14; no new superiority, savings or publication-readiness claim.
