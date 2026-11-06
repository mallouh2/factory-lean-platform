# Final Warehouse cleanup and Factory Floor Quality alerts

1 November2026 receipt-only refinement: [inspected-production receipt UX](warehouse-receipt-ux.md). One visible category now replaces the stacked forms, with independent retained drafts, compact released/received/remaining cards, explicit physical confirmation, collapsed note and content-height sheet. Existing separate partial transactions, holds, source stock and unknown-UUID recovery are unchanged. The October screenshots/layout below are historical.

28 October 2026 — **COMPLETE / LOCAL VERIFIED / OWNER VISUAL REVIEW PENDING.**

This report covers the seven requested corrections only. It is not a hosted release, a green full-platform suite, or completion of the earlier fresh-shift operational acceptance scenario.

## Final preview

- URL: `http://127.0.0.1:4222/?view=lines`.
- Existing owner: `PlanningV3@local.invalid`; normal local login verified.
- Unchanged, owner-restricted credentials: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.
- Matching isolated build: `warehouse-final-app` under that directory; runtime/process pointers identify the active build. Earlier build directories are retained.
- Actual owner-preview database: loopback `127.0.0.1:55496`, `factory_lean_quality_local`, independently checked against its data directory. Existing authenticated adapter `4304` remains running without restart or credential changes.
- Mutation acceptance used a **different disposable database**, `127.0.0.1:55498`, with a separate synthetic factory and normal test logins at temporary `4232`/`4316`. These temporary processes are stopped after verification; scripts, fixtures and evidence are retained outside the repository. No operational writes were made to the owner's manual-review factory.

## Completed corrections

1. **Floor:** one compact bell/button replaces inline Quality evidence. Neutral with no unread changes; attention/count with unread changes. List rows show order/product, quantity summary, reason, time and read state. Opening the list makes no acknowledgement. Opening one notice uses the existing actor-bound protected ACK command, durable UUID recovery and current revision. Matching approvals remain absent. Global counts cover all notification pages, not just the first 50. The lossless API's integer-string count is safely validated/restored without converting production quantities.
2. **Direct receiving:** selecting the exact request opens its operational form immediately. Separate finished and stored-unfinished categories show released/received/remaining quantities, location and actual receipt confirmation. Each category retains its own existing protected partial transaction. No nested legacy selection table and no decorative Reject command. Quality holds remain visible; authorized physical reconciliation is a separate exceptional destination. Unconfirmed commands retain their UUID and block another receipt. Exceptional pending commands cannot be retried as an ordinary receipt. Category buttons use normal document flow so a sticky control cannot obscure the physical-confirmation checkbox on mobile.
3. **Duplicate removal:** no bottom Additional Actions, old receiving/source-issue/Purchasing shortcuts or duplicate Unfinished Products cards. Normal source-specific issue is integrated into its selected request using the existing source picker/command. Non-production stock receiving/configuration remains in its existing inventory context. Purchasing itself is unchanged and remains accessible through its module and authorized item actions.
4. **Stored WIP:** structured routing classification resolves names through the existing factory operation-label contract. No UUID, JSON or free-text classification guessing. Compatible product/unit/canonical unordered operation sets pool only with compatible restrictions and hold/accounting state. Unknown classifications remain separate with an explicit fallback and diagnostic count. Stored quantities, recovery reservations, held availability and Floor material remain distinct. The main owner has a real row showing **10 on hand / 10 reserved / 0 available**; those reservations were not changed.
5. **Projection:** the observed `-60 Meter` is a legitimate forecast shortage. `UX-UNIFIED` has physical stock/reserved/available all zero; SO-0000004 has 40 dispatched and 60 outstanding, with no eligible accepted incoming for the remaining requirement. Existing authoritative projection subtracts uncovered demand from free stock and eligible incoming. The table, Details and unit breakdown now say **Expected shortage: 60 Meter** rather than implying negative physical stock. No ledger, forecast formula or replenishment command was changed or clamped.
6. **Consistent workspace:** Inventory inspects balances; Requests handles selected receiving/issue/dispatch. Scoped column preferences, selection, double-click/Details, readable availability, search, type filters, keyboard access and EN/AR/RTL remain. Exact decimal comparison/subtraction prevents string-ordered Sales quantities from hiding outstanding requests. Mobile table overflow stays within the table, not the document.
7. **Export/Print:** existing protected export service now supports stored WIP and Requests. Requests export explicitly covers the current department-page and its search/type filters; WIP export explicitly covers all stored classifications. WIP search is labelled as search of displayed classifications. These are bounded scopes, not a new global request/search engine. Existing authorization, origin checks, two-pass change detection, limits, formula/HTML protection and final permission recheck remain.

## Four necessary forward read migrations

All are local only. None adds a business writer, ledger, activation switch, account grant or inventory movement.

| Migration | Missing protected read metadata supplied |
|---|---|
| `20261028101832_quality_notification_summary_v1.sql` | Global total and actor-specific unread count |
| `20261028101835_warehouse_unfinished_classification_read_v1.sql` | Structured canonical stored-WIP classification and compatible pooling |
| `20261028124725_warehouse_output_receipt_origin_read_v1.sql` | Manufactured-vs-legacy output origin, preventing a second legacy acknowledgement entry for new receipts |
| `20261028133240_warehouse_receipt_operation_labels_v1.sql` | Direct/queue receiving uses the same authoritative EN/AR operation labels as Quality/WIP |

Local files: **126**; all **122** prior migration hashes unchanged. Read-metadata application preserved operational-table digests on both local databases. There is no claim about current remote migration alignment; no remote environment was accessed. Export Reader remains unchanged and was not deployed.

## Actual acceptance evidence

### Controlled receipts and notification state

Separate disposable factory `8800fdfc-35bc-47c4-967d-994fd8c98881`, output `28e6f951-ed3c-4a15-9467-6c3dc173bbd9`:

| Quantity | Before | After |
|---|---:|---:|
| Finished physically received for this output | 0 m | 5 m |
| Stored unfinished physically received | 0 m | 4 m |
| Remaining finished release | 89 m | 84 m |
| Remaining unfinished release | 10 m | 6 m |
| Newly received unfinished physical/available quantity | 0 m | 4 m / 4 m |
| Already-held, unrelated fixture stock | 10 m | 10 m, still held |

The recorded production remains 90 finished + 10 unfinished; the existing Quality finding remains 89 finished + 10 unfinished + 1 rejected, with separately measured 0.5 KG. Receiving adds no Scrap or production. Two successful receipt events total 9 m across the two categories; they are not one combined atomic receipt.

Finished receipt UUID `91a2bd7a-bb66-460b-99af-746f89efc27c` committed HTTP 200, then its response was deliberately lost. Retrying the identical body/UUID returned HTTP 200 and retained **one** 5 m credit. Unfinished receipt UUID `02860bf7-6121-42db-8561-7bfcbd78d59a` separately returned HTTP 200 for 4 m. Test continuations used the journal and original UUID, never a repeated new transaction.

Three material notices returned separate ACK HTTP 200 responses and counts **3 → 2 → 1 → 0**. List opening alone produced no ACK. Refresh retained zero for that actor; a separate normal observer login still had three unread. A matching approval generated none. A separate 51-notice SQL boundary test verified 50/1 pagination with a correct global count.

Held receiving remained disabled. The observer's protected Warehouse read/write returned **403**, with no stock/event changes. Known separate-factory notification/WIP reads and receipt write returned **403**, with no rows or new events. No permission was granted to make these tests pass.

### Test results

- **110/110 focused Node checks PASS**, including eleven new notification/export/presentation tests, existing receiving/export/sidebar checks and bilingual shortage Details tests.
- **18 new standalone PostgreSQL assertions PASS**: matching/material notices, per-user ACK/retry, >50 boundary, classification labels, unordered pooling, different restrictions, reservations/holds and authenticated-only read execution.
- Relevant existing WIP, partial pooled dispatch, hold/identified-source rejection and direct/package permission suites PASS. Partial dispatch exercises 20 + 20 + 60 actual shipments, reservation/incoming conversion, no invented source attribution and stock conservation.
- **Two actual concurrent dispatch groups PASS**: same UUID replays one dispatch; competing UUIDs cannot spend the same stock. Database lock waits were observed.
- One old dispatch-safety fixture initially failed `output_measured_weight` because it omitted the now-required measured Scrap evidence. It now supplies an explicit synthetic measured **0.5 KG** for its one rejected meter; its protected hold-denial assertions are unchanged and pass. No production validation was weakened.
- Actual authenticated browser acceptance PASS: compact notification states, list vs individual ACK, exact partial receipt/lost-response retry, named WIP, held receipt, Excel/Print HTTP 200, independent user denial, known foreign-factory denial, EN/AR390, dialog Escape and no document overflow.
- Original owner preview read-only smoke PASS: normal login, Floor/list, direct receipt selection, Inventory filters, 10/10/0 WIP and shortage 60. Operational digest unchanged; zero attempted business POSTs, zero post-login API/page errors. The normal unauthenticated initial `/api/data` 401 precedes login and is recorded separately.
- Final TypeScript and isolated optimized production build PASS. Active build source hashes match the repository source. Screenshots were inspected, including the final mobile receipt's separate confirmation controls.

### Historical harness failures — separately preserved

The unchanged original Sales/supply/Warehouse harnesses contain **88 tests: 69 PASS / 19 FAIL**. Exactly the same 19 names fail against the byte-matching, untouched pre-task `sidebar-v2-app/src` snapshot. Twelve failures assume old root-level stock/movement/receiving/dispatch controls or hook positions; seven assume five Warehouse tabs, lower WIP processing and bottom purchase actions. They do not demonstrate a new ledger failure. No original failing expectation was silently rewritten; the separate semantic two-workspace test was updated for the explicitly requested removal of duplicate actions. Real SQL/browser checks cover the protected replacement paths. This is not a green full-suite claim.

## Incremental files

Modified (preserving pre-existing content/work):

`HANDOFF.md`; `src/components/NavigationIcon.tsx`; `src/features/ManufacturedOutput.tsx`; `src/features/ManufacturedReceiving.tsx`; `src/features/ProductionRecordingV3.tsx`; `src/features/StoredUnfinishedInventory.tsx`; `src/features/Warehouse.tsx`; `src/features/WarehouseInventory.tsx`; `src/features/WarehouseItemDetails.tsx`; `src/features/WarehouseRequests.tsx`; `src/features/warehouse-v1.css`; `src/locales/en.json`; `src/locales/ar.json`; `src/app/api/table-export/route.ts`; `src/services/table-export-operational.ts`; `src/types/table-export.ts`; `tests/operational-ux/dispatch-safety.sql`; `tests/unified-ux/warehouse-workspace.test.mjs`; `tests/warehouse-view.test.mjs`.

Added:

`docs/warehouse-final-cleanup.md`; `src/features/QualityUpdateButton.tsx`; `src/services/table-export-warehouse.ts`; `src/utils/warehouse-presentation.mjs`; `src/utils/warehouse-request-rows.mjs`; the four migrations above; `tests/warehouse-final/{readers.sql,notification-boundary.sql,pooling.sql,label-reader.sql,preview-fixture.sql,affected-sql.mjs,apply-label-reader.mjs,presentation.test.mjs,export.test.mjs,browser.mjs,preview-read.mjs}`.

Evidence outside Git: `warehouse-final` under the owner-preview root contains the before-file snapshot, manifests, build/typecheck/Node logs, browser journal/HTTP evidence and final owner screenshots. The separate SQL runtime root contains SQL/concurrency results. No passwords, screenshots or generated build output were added to repository files.

## Preserved boundaries / remaining limits

- `development`, HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, empty index. No missing baseline files; unrelated dirty work, Sidebar/Planning, shared owner adapter, Export Reader and Design System preserved.
- Shipped manufactured-output capability remains **FALSE**; completed-shift late recording remains **FALSE**, schema contract **0**. Existing disposable helper simulation is unchanged; this is not activation of the shipped workflow.
- Original owner credentials, memberships and 102 effective grants unchanged. New isolated SQL fixtures use their own synthetic users/factory; they do not change the owner's review factory.
- No hosted access, deployment, activation, Git write, dependency installation, port 3000 operation or unrelated preview restart.
- Earlier pre-admission shift / outstanding 60 m full-production acceptance remains unverified. It was not bypassed, backdated, reopened or relabelled PASS here. This bounded Warehouse/notification task does not resume it.
- Owner visual approval remains pending. Do not automatically checkpoint, deploy, consolidate environments or start more Planning work.

## Manual review

Refresh port 4222. Open **Factory Floor → Quality Updates**; the existing two unread changes remain for the owner, and opening only the list must not clear them. Open **Warehouse → Requests** and select one inspected Production Receipt to review its direct form. Open **Inventory → Stored Unfinished / WIP** for named classifications/reserved availability. Search finished inventory for **Unified acceptance pipe** and inspect the **Expected shortage: 60 Meter** explanation. Switch Arabic and use a 390px viewport. Any actual receipt confirmation is a real local operation, not merely opening Details.

Product Differentiators reviewed: these are presentation/protected-read corrections to existing capabilities, so commercial claims remain unchanged. **STOP for owner review.**
