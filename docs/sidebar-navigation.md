# Sidebar navigation correction — 28 October 2026

**COMPLETE / LOCAL IMPLEMENTATION VERIFIED — owner visual approval pending. Stop after this navigation task.**

Supersedes the rejected grouped sidebar in `unified-operational-ux.md`. It does not change that report's outstanding production/shift acceptance or authorize a checkpoint. Repository remains `development`, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, with existing unrelated dirty work preserved.

## Intended user and design decision

A factory employee needs to choose a daily task quickly, identify the current destination and return to work. The shell should not require a department expansion followed by an identically named page. Keep the existing native buttons, SVG icon mechanism, page modules and effective-permission checks; correct the structure before styling it. No new icon, animation or UI dependency.

The approved application visual language in `docs/design/APPROVED_APPLICATION_UI.md` and `src/styles/design-tokens.css` supplies the palette, Inter/IBM Plex Sans Arabic, spacing, radii and motion. The separate proposed Design System document was not edited. Light navigation uses white surfaces, ink text, blue selected state and subtle borders; dark-system preference uses existing dark surface/text/mint tokens only within navigation. No global page-theme conversion.

Bounded industry references: [Tulip's operator access separation](https://support.tulip.co/docs/user-management) separates daily operator work from editor/configuration access; [MRPeasy's manufacturing workflow](https://www.mrpeasy.com/resources/manufacturing/) retains familiar manufacturing-order and stock tasks. The recommendation is task-first navigation and contextual equipment configuration, not copying an ERP menu or changing Factory Lean authorization. No competitive or measured training-efficiency claim.

## Exact owner navigation

| Entry | Behavior / destinations |
| --- | --- |
| Sales | Direct → existing Sales Orders. |
| Warehouse | Genuine two-destination disclosure → Inventory, Warehouse Requests. Each opens its actual existing workspace. |
| Purchasing | Main label directly opens Purchasing. Separate chevron reveals Suppliers and My Purchase Requests; no duplicate Purchasing child. |
| Production | Factory Floor, Production Orders, Production History, Products. |
| Planning | Direct. |
| Quality | Direct. |
| Maintenance | Direct. |
| Lean Analysis | Direct. Existing Downtime destination is accessible through a permission-aware contextual action within Lean, with Back to Lean; Floor downtime capture remains untouched. |
| Factory Administration | Factory Settings, Employees, Roles/Permissions, Audit Log, Support, as authorized. No new HR module. |

Permission filtering occurs **before** deciding whether a group needs disclosure. A sole permitted destination is one direct button with no chevron or duplicate child. Purchasing without secondary access is direct; a restricted user with only one permitted secondary destination reaches that leaf directly. A downtime-only person retains an authorized direct Lean-labelled entry to the existing Downtime screen without acquiring Lean permissions. No new permission keys or grants.

Lines & Machines is absent from the main sidebar. The existing **Manage Lines & Machines** action remains visible in Factory Floor for existing Lines/Centers create/edit permission holders, with a distinct equipment icon. It opens the unchanged LineBuilder forms/routes and returns to Floor. The shell callback also checks the same effective permissions. No module removal or reconstruction.

Management Reports, Overview, Semi-Finished Products and the old top-level material requests remain absent from normal navigation. Their underlying code is retained. Unfinished roadmap/HR placeholders are no longer displayed in navigation.

## Interaction and presentation

- Semantic, distinct major icons: Sales receipt, Warehouse building, Purchasing bag, Factory Floor factory, Orders clipboard, History clock, Products package, Planning calendar, Quality shield/check, Maintenance wrench, Lean chart, Administration settings. Shared 20px SVG/stroke alignment; only directional chevrons/control arrows mirror in RTL.
- Clear selected child and related group state, readable labels, restrained hover and visible keyboard focus. Long labels wrap rather than truncate. Minimum 44px navigation controls; Arabic 16px IBM Plex Sans Arabic, English 14px Inter labels, using the existing approved scale.
- Desktop rail expands on hover/keyboard focus and has an explicit expand/collapse control. Choosing a destination returns to the rail so the overlay cannot cover the next task's Back/control. Expanded sidebar scroll position is retained on later pointer expansion. Opening navigation does not resize the workspace or remount its page.
- Genuine submenus animate with a CSS grid track; collapsed content is inert and hidden from assistive technology. Native buttons support keyboard activation; sidebar labels/selected destination remain accessible in the compact rail.
- Mobile drawer closes after navigation, including contextual History. Escape closes it and returns focus to Menu; Tab/Shift+Tab are trapped among visible non-inert controls. Background workspace is inert and body scrolling is locked only while the drawer is open, then restored.
- Width/transform, submenu and chevron transitions use the existing 180ms small-motion token; reduced-motion preference removes them. Correct closed/expanded chevrons in LTR and RTL. One sidebar scrollbar, no nested submenu scrollers.
- Department navigation now retains supported view state in browser history. Back restores the prior department and Warehouse Inventory/Requests selection. Existing contextual Production History Back remains intact. Current route authorization still applies to restored/deep-linked destinations.

## Current verification

**43/43 focused Node tests PASS:** sidebar model/component behavior, dynamic single-child flattening, EN/AR labels, Purchasing primary/secondary distinction, allowed-only menu combinations, inert submenus, navigation shell/API failure behavior, Permission Packages presentation masks, overlay focus/body-scroll cleanup and existing History readers. Existing tests were adapted only where the approved main-sidebar Lines & Machines button no longer exists or the focus-trap fixtures needed inert/visibility behavior.

**TypeScript PASS; isolated optimized Webpack production build PASS.** Final served source matches the repository source. React review: state lives in the navigation presentation component, permission filtering does not mutate grants, hooks are unconditional, closed controls cannot receive focus, no heavy imports/dependencies or new data reads in the navigation model.

**Actual authenticated loopback browser PASS:**

1. Existing full-access owner signs in normally; authenticated identity checked. Sales, Planning, Quality, Maintenance and Lean each open directly. No single-child disclosure or duplicate parent/child destination.
2. Purchasing main/secondary destinations, Suppliers location, existing Administration screens, all four Production destinations and contextual Manage Lines & Machines opened successfully. Back returns to Floor; no configuration was saved. History Back returns to its origin.
3. Warehouse Requests/Inventory open the matching real panels. Browser Back restores the preceding Warehouse panel and ordinary department.
4. Major destination SVG shapes are distinct. Desktop collapse/hover expansion, final light/dark sidebar, selected state and 390px English/Arabic RTL drawer were inspected. Visible navigation text contrast is at least **4.5:1**, icons at least **3:1**, against their computed normal/selected backgrounds in light and dark. This is a bounded navigation contrast check, not a full accessibility audit.
5. Mobile focus trap, Escape/focus restoration, close after navigation, no document horizontal overflow, and reduced motion PASS. Final screenshots inspected after transitions/fonts settled. The installed frontend skill's shared `visual_lint.mjs` is unavailable; browser assertions, computed contrast, page exceptions and screenshot inspection provide the bounded evidence instead.
6. Existing restricted viewer signs in normally. No Quality or Administration destination and no Manage Lines & Machines action. Direct Settings deep link does not reveal the configuration UI. Protected Quality read returns **HTTP 403**, no rows.
7. A real existing foreign factory UUID, obtained read-only with no membership for either tester, was used. Owner and viewer protected foreign-factory Quality readers return **HTTP 403** without rows. The existing generic snapshot contract returns **HTTP 200 with the caller's own authorized factory**, rather than changing to the requested foreign factory; `can_access` for that foreign factory is false. Do not misreport this safe fallback as a 403 or a data leak.
8. Operational/permission row digests remained unchanged across browser checks. Only observed POST requests were the two normal `/api/auth` logins; no business mutation endpoint was invoked. No permissions/packages/accounts/passwords/memberships changed. Owner still has 102 effective permissions.

No page exceptions or unexpected API failures in the final run. Initial unauthenticated snapshot **401** and deliberately denied **403** requests are expected. Pre-existing Next standalone/start warning remains in local server logs; it did not prevent successful rendering or authenticated reads. Early harness assumptions about the Downtime label, dynamic locator indexes and snapshot status were corrected; those were not backend defects. The desktop overlay/Back obstruction and long-label truncation found during inspection were corrected and reverified.

No inventory, Quality accounting, Planning SQL, migration, concurrency or unrelated platform suites were rerun for this navigation-only task. No first-time-user or owner visual approval is claimed.

## Exact incremental file manifest

Existing source files modified:

```text
src/app/globals.css
src/components/FactoryApp.tsx
src/components/useNavigationOverlay.ts
src/features/FactoryFloorV2.tsx
src/locales/en.json
src/locales/ar.json
```

New source files:

```text
src/components/NavigationIcon.tsx
src/components/OperationalNavigation.tsx
src/utils/operational-navigation.mjs
```

Tests:

```text
tests/factory-navigation.test.mjs             updated navigation callback expectation
tests/navigation-overlay.test.mjs            updated inert/scroll/focus fixtures
tests/sidebar-navigation.test.mjs             new focused model/component tests
tests/sidebar-navigation-local.mjs            new opt-in read-only local browser acceptance
```

Documentation: this report, a dated supersession note in `docs/unified-operational-ux.md`, and a new top entry in `HANDOFF.md`. These 16 incremental paths do not describe all prior uncommitted work. No migration or dependency changes.

## Preview and manual review

**http://127.0.0.1:4222/** — `sidebar-v2-app` isolated optimized build; existing loopback Auth/Data adapter 4304 and disposable PostgreSQL 55496 retained. Root marker, actual SQL server address/port/database/data-directory and browser/server configuration were independently verified local before access. Other previews and localhost:3000 remain unchanged.

Existing owner: **PlanningV3@local.invalid**. Verified unchanged local credential file:

`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`

Refresh the preview to load the new bundle. Hover the compact rail or use Expand navigation. Click Sales/Planning/Quality/Maintenance directly. Expand Production and use Factory Floor → Manage Lines & Machines, then return without saving. Open Warehouse's two destinations and Purchasing's main label versus secondary chevron. In Lean, open Downtime and return. Review Arabic at 390px and use Escape to close the drawer. Operational writes are not needed to approve this sidebar.

Evidence outside Git: preview root `sidebar-v2/` contains `before-files.json`, final preservation manifest, `focused.txt`, `build.txt`, `typecheck.txt`, `browser.json`, `desktop-en.png`, `desktop-dark.png`, `mobile-en.png`, `mobile-ar.png` and `restricted-en.png`. Earlier failed screenshots/logs are diagnostics; `browser.json` PASS and named final screenshots are current evidence. Credentials are never printed or copied to tracked documentation/tests.

## Safety / remaining issues

No known remaining sidebar implementation blocker; owner visual review pending. Prior unified operational fresh-shift acceptance remains PARTIAL and was not resumed. No business-record, backend-contract, Supabase-schema, RLS, permission or account modification. All 122 pre-task migration files byte-identical; Export Reader, Design System, shared preview owner adapter and unrelated work preserved. Both shipped manufactured-output and completed-shift late-recording activation gates remain **FALSE** (late schema contract 0); existing disposable helper simulation unchanged.

No hosted access, deployment, activation, Git writes, dependency installation or port 3000 changes. Branch/HEAD/index unchanged. Product differentiators reviewed; navigation correction adds no material commercial capability, so those claims remain unchanged. Stop for owner visual review; no checkpoint, hosted acceptance or other development begins automatically.
