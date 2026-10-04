# Purchasing contextual actions and Supplier field verification

Verified 2026-10-04, Asia/Riyadh. Repository: `C:\Users\Temp\Documents\GitHub\factory-lean-platform`, branch `development`, HEAD `f5896f1e354554641768ea35f6a78d42f1bde17e`. Continued the existing uncommitted 73-migration / 567-test checkpoint. No commit, push, main change, DEV connection or new account.

## Implemented behavior and boundaries

The buyer reviewing an existing request needs to choose an action, explain it and confirm it. Previously the generic Reason/Reply field preceded unrelated supplier controls, and explanation-dependent buttons were disabled when empty. Purchasing now presents clickable Needs Clarification / Reject / Cancel choices, followed by one contextual explanation and explicit confirmation. Empty explanations focus the field and show action-specific inline validation without a command. Switching modes clears unrelated explanation text. The original requester's clarification reply remains available, including when that person also manages Purchasing.

One searchable, paged, keyboard-accessible Supplier combobox replaces separate search and selection. Saved selections retain their UUID. Unmatched names require Save Supplier and remain request-local; no Directory record, category or Primary/Alternative link is created. Optional Add New Supplier is visible only with `suppliers:edit`; Name is required and prefilled, Phone/Email/Notes optional. Successful creation associates the returned UUID with the request and preserves its explanation and selected mode. The existing revision guard still applies if request association conflicts; saving can be retried after resolving that conflict.

Permanent creation normalizes surrounding spaces and case within the factory. Existing matches are reused without overwriting their contacts, notes or activity. Inactive matches remain unavailable rather than being silently reactivated. Database uniqueness also protects concurrent duplicate creation. Request-local naming uses existing `purchasing:edit` authorization independently of `suppliers:edit`. Requester permissions, status lifecycle, authenticated server actor/time, retries, receipt behavior, Primary/Alternative rules and Warehouse ownership remain authoritative.

The existing layout and components were reused; no global CSS changes in this task. EN and AR labels, contextual validation, supplier suggestions and the small dialog were checked at desktop and 390px mobile viewport sizes. Actual touch-device acceptance remains pending.

## Research and product review

[MRPeasy purchase-order documentation](https://www.mrpeasy.com/resources/user-manual/procurement/purchase-orders/details/) informed keeping supplier work separate from ordering and receipt stages. This does not establish a claim that MRPeasy supports request-local supplier names. [Supabase database-function documentation](https://supabase.com/docs/guides/database/functions) informed retaining protected database commands. PRODUCT_DIFFERENTIATORS section16 records this usability extension as parity (C); classification counts and formal Purchase Order scope are unchanged.

## Forward database change

Only TESTING (`silmfbpjyepalnggwulp`) received `20261004081529_purchasing_contextual_suppliers.sql`. Local and TESTING now have **74/74** matching versions and names. All 73 previously present migration hashes and the exact submitted new SQL are preserved. DEV was intentionally not queried.

- `purchase_requisitions.supplier_text`: bounded request-local name, mutually exclusive with a saved supplier ID.
- `purchase_request_events.supplier_name`: authoritative name snapshot for future events; no historical rewrite.
- `suppliers_normalized_name`: factory-local uniqueness on `lower(btrim(name))`; preflight found no existing duplicate.
- Existing command, wrapper, reader and event functions extended narrowly. Ordering accepts either saved ID or request-local name. Supplier save resolves duplicate creation to the existing ID without overwriting its other values.
- No new RPC, account, persistent grant, role or authorization bypass. Existing protected state/revision/actor/receipt checks retained.

## Automated results

Focused Purchasing/supplier/permission/contract/UI tests: **206/206**, zero failed or skipped. Full Node: **582/582**, zero failed or skipped, net 15 above the prior 567. TypeScript passed. Final isolated production build passed with exit0; generated `next-env.d.ts` bytes restored.

Ten final-schema rollback SQL suites passed: purchasing-suppliers (**31 assertions**), purchase-requester (**75**), supply-flow (**99**), warehouse-manual-purchase (**34**), warehouse-master, sales-stock-sources, sales-fulfillment, production-recording, unfinished-production and snapshot-authorization. Scoped fixture changes were transaction-local and rolled back; existing users were reused. No permanent permission change was made for testing.

The new UI tests replace the old disabled-empty-action expectation with contextual action selection, validation and explicit confirmation; cover buyer/requester clarification, single Supplier control, normalized matching, simple dialog and grant-dependent creation. Contract tests permit the narrow request-local payload and permanent creation without forged actor fields. New SQL tests cover duplicate reuse, bounded/mutually exclusive supplier values, request-local persistence and event name snapshot, no Directory/link side effects, authorization, retries and receipt regressions.

### Requested coverage mapping

| Requested points | Evidence |
| --- | --- |
| 1–3: action before explanation | EN/AR action-mode UI tests and live dialog screenshots |
| 4–7: empty action cannot execute, focused validation | UI command-call assertions; live Reject, Clarification and Cancel validation; SQL empty-reason denial |
| 8–10: contextual labels | EN/AR UI tests for all three modes and live labels |
| 11: valid protected execution | UI confirm payload tests; SQL transitions; live rejection and clarification |
| 12: unauthorized requester denial | Purchase requester and new supplier SQL actor-denial regressions |
| 13–16: single field, filtered saved selection | UI single combobox / query / UUID tests; live existing supplier selection |
| 17–18: unmatched request-local only | Contract and SQL persistence/no-Directory assertions; live count1→1 |
| 19–21: optional action, dialog, prefilled name | Grant-sensitive UI dialog tests; live EN/AR modal |
| 22–24: optional Phone/Email/Notes | UI required-field checks; live simple form |
| 25: created UUID selected | UI callback/selection tests; live request association and database UUID |
| 26: preserve request work | Live cancellation mode and entered explanation retained after creation; parent supplier-save path retains them |
| 27–30: exact/case/space duplicates and reuse | SQL duplicate assertions and unique index; UI normalized match; live case/space match with no Add action |
| 31–33: separate permanent/local permissions | UI grant visibility and SQL deny/allow cases |
| 34–36: lifecycle, supplier references, Primary/Alternative | Existing supply99/requester75 plus new supplier31 suites |
| 37: no Warehouse supplier management | Existing requester-context UI regressions; Warehouse code unchanged in this task |
| 38–39: stock/direct receipt | Existing supply99/manual34/requester75 and new supplier31 rollback suites; no new live receipt claimed |
| 40–41: EN/AR/RTL | Both-language UI tests and desktop/mobile browser checks; real device pending |

## Live TESTING A–G

Used existing Nasser / Nova, no new account or grant. Retained QA data for manual acceptance.

- **A Reject:** PR-0000165, `QA Purchasing rejection 20261004`, 1 Piece / Maintenance. Empty Reject focused Rejection Reason and showed validation without changing status. Explicit confirmation with `QA verification: unsuitable bearing specification.` changed it to REJECTED.
- **B Clarification:** PR-0000166, `QA Purchasing supplier UX 20261004`, 2 Piece / Maintenance. Empty Needs Clarification showed contextual validation without change; confirmation with `QA verification: specify the bearing grade.` changed it to NEEDS_CLARIFICATION. Later the original requester's Arabic reply `QA verification: grade B bearing specified.` returned it to REQUESTED through the protected reply path.
- **C Autocomplete:** selected existing QA Supply Supplier by its real UUID from suggestions under the one Supplier field.
- **D Temporary name:** saved `QA Request-only Al Noor 20261004`; request supplier ID was NULL, request-local name persisted, Directory count stayed1 and category-link count stayed1. The event name snapshot retains this historical name after subsequent supplier selection.
- **E Permanent creation:** created `QA Purchasing New Supplier 20261004` with optional contacts through the small dialog. UUID `8039c9e6-dc61-4cf6-958d-a3c4b6248a83` was automatically associated with PR166. Directory count1→2, category-link count1→1. Cancellation mode and `QA preservation: keep this explanation while adding a supplier.` stayed intact. PR166 finishes REQUESTED with this supplier.
- **F Duplicate:** typing `  qa purchasing new supplier 20261004  ` offered the existing record and hid Add New Supplier. No third Directory record. Exact/case/space duplicate reuse is covered by rollback assertions; the unique index protects concurrent creation, without claiming a separate live concurrency stress test.
- **G Arabic:** contextual actions/validation, Supplier autocomplete, optional simple modal and RTL verified at390px and1440px. Final EN desktop proof also captured. A focus issue where autocomplete closure could interrupt the adjacent action was corrected using contained focus and outside-pointer handling, then rechecked.

Inventory transaction digest remained `b3b60155d2fe1a5ad68846a87eade087`; finished-goods movement digest remained `eabd9a9be8c329df9f0237ac054b0320`. No live stock/direct receipt or inventory movement in this task. Pre-existing user PR123 CANCELLED, PR124 REQUESTED and PR125 ORDERED, and earlier PR34/35/57/121/122, were left unchanged. Products, materials, Production, Planning, machine and transfer code received no new task edits.

Proof directory: `C:\Users\Temp\AppData\Local\Temp\factory-purchasing-20261004`. Includes `purchasing-final-en.png`, `purchasing-final-ar.png`, mobile validation/autocomplete/dialog screenshots and `supplier-created-preserves-work.png`. Logs: `factory-purchasing-focused.log`, `factory-purchasing-full.log`, `factory-purchasing-build.log` under the Windows temporary directory. Website remains running at localhost:3000, Purchasing open.

## Exact task file delta and preservation

The original65 dirty-file bytes were backed up at `C:\Users\Temp\AppData\Local\Temp\factory-purchasing-baseline-20261004-110604`. This task extends9 original files and adds4; the other56 remain byte-identical. This is the task delta, not the complete accumulated uncommitted diff.

Extended: `HANDOFF.md`, `docs/PRODUCT_DIFFERENTIATORS.md`, `src/features/Purchasing.tsx`, `src/features/useSupply.ts`, `src/locales/en.json`, `src/locales/ar.json`, `src/utils/supply-contract.mjs`, `tests/supply-contract.test.mjs`, `tests/supply-ui.test.mjs`.

Added: `src/features/PurchaseSupplier.tsx`, `supabase/migrations/20261004081529_purchasing_contextual_suppliers.sql`, `tests/purchasing-suppliers.test.sql`, this verification document.

## Remaining acceptance

No unresolved business decision. User manual acceptance/freeze and real-device touch remain NEEDS VERIFICATION. Existing publication-stage security advisories and previously deferred calibration, partial receipt, issue, MRP, accounting and automatic consumption remain outside this task. No commit/push/DEV authorization is implied.
