# Factory data export and table readability

## Implemented product behavior

**Factory Settings → Export Factory Data** downloads one `.xlsx` workbook. The existing `factory:export` permission controls the action; export also requires factory/workflow view access so RLS cannot silently omit unauthorized modules. The Owner/Admin package already includes these permissions. No operational package or direct grant is changed. One new forward migration adds the bounded export reader; no already-applied migration is edited.

The authenticated server uses a fixed table/column allowlist, a factory predicate on every table query, ordered pages of 500, exact counts and duplicate-key detection. Warehouse inventory and Lean Problems use their existing authorized paginated readers. No history is added to `factory_snapshot`. Most native tables retain ordinary RLS reads. Fourteen tables intentionally allow only protected functions: the new factory_export_page SECURITY DEFINER reader checks export plus every included view permission on every page, admits only fixed datasets/columns, and binds the factory predicate. Existing direct table privileges and RLS remain unchanged; PUBLIC/anon execute is revoked. The application uses no privileged database key. Export authority is checked again before delivery.

The workbook includes metadata, factory/people/packages/direct grants, configuration, products/materials/versioned recipes/capabilities/rates, Sales/reservations, planned and actual Production, corrections/Scrap/WIP, Downtime/approved causes/Loss, Warehouse movements/requests, Purchasing/suppliers, Maintenance, Lean standards/problems/initiatives/actions/templates/comparisons/verification and Audit event metadata. Names supplement common identity references. Frozen headers, filters, wrapped text, restrained alternate rows and factory-local timestamps support inspection. WIP units come from source recordings; Meter/Piece/kg stay separate. Blank measurements remain unknown.

Lean Problems cover the last **365 days**, matching the existing aggregate-reader limit; this period is stated in Export Metadata. Other selected operational tables include their available histories. An export is a sequence of live reads, **not a transactionally consistent database backup**. Detected count/source-revision changes fail with a retry message; concurrent edits that preserve counts can still appear across sheets. Pause edits when preparing a controlled export.

Bounds: 100,000 records per reader, 1,000,000 exported data cells overall and Excel’s 32,767-character cell limit. Exceeding a bound fails clearly without truncating history or silently shortening cells.

No passwords, auth tables, environment files or credentials are selected. Raw Audit before/after payloads are excluded. Credential-named nested evidence fields and recognizable privileged token/connection-string patterns are removed defensively. Cell strings remain literal strings, never user-supplied formulas or hyperlinks. The response is private/no-store.

## Shared presentation

`globals.css` defines one operational table row palette: base, alternate, hover and selected. Native tables in `.table-wrap` and Warehouse’s bounded scroll region share it. Sticky Warehouse identity/action cells follow their row surface; low-stock styling retains its stronger semantic treatment. Lean’s independent amber/red/blue metric cells remain unchanged. Desktop Production request rows use the same palette. Downtime’s review list uses these colors while retaining its explicit selected state.

Reviewed surfaces: Sales, Planning lists, Production, Production History, Warehouse, material requests, Purchasing, Maintenance, Downtime, Lean, users/packages and Audit. Existing Sales/Planning/Maintenance/material-request card layouts remain cards; mobile cards are not zebra-striped. Wrapping, compact numbers, existing widths, RTL and sticky-header behavior are preserved.

## Product context and limits

Owner/Admin is the user for the export; factory staff need readable operational rows. The action belongs in settings rather than daily navigation, with progress, local error/retry and explicit browser download. EN/AR labels and RTL worksheet views are supported; worksheet names/column headings remain English and bilingual stored names are included.

[MRPeasy’s official manual](https://www.mrpeasy.com/resources/user-manual/one/) documents configurable data tables and CSV export. This supports treating readable application export as expected capability/parity, not a unique differentiator. No archive automation, automatic device save, deletion, accounting or operational business-rule change is introduced.

Future retention is separately documented in [Data Retention & Monthly Archive](data-retention-archive.md). Live Simulation verification passed: 59-sheet authenticated application download independently opened, correct scenario counts and secret/literal-cell checks; export denied to all nine operational accounts by both HTTP and the protected RPC. All ten accounts signed in through the real UI. The UI reported workbook-ready; IAB download-event observation was unavailable, so the workbook artifact was saved from the same authenticated application endpoint. TESTING was not queried or modified. Migration 80 is applied only to Simulation and awaits separate TESTING authorization.

The Simulation security advisor identifies the authenticated SECURITY DEFINER endpoint as an intentional API surface, like the existing protected command/readers. Its fixed allowlist, complete grant checks, factory predicate and denied anon/direct-table access are covered by rollback tests; do not remove these checks or replace them with a privileged app key. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
