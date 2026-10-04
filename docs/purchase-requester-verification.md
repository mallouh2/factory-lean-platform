# Warehouse requester controls and compact headers — 2026-10-04

## Scope and authority

Continued the exact dirty 72-migration / 536-test checkout on `development`, HEAD `f5896f1e354554641768ea35f6a78d42f1bde17e`. AGENTS, HANDOFF, relevant implementations and installed Next.js guidance were read before editing. No commit, push, branch change, main change or DEV connection. Existing dirty work was saved at `C:\Users\Temp\AppData\Local\Temp\factory-requester-baseline-20261004-101050`.

Persona: a Warehouse requester identifies what is needed and follows its delivery; a separately authorized Purchasing person manages supplier ordering. This is a bounded correction to the existing workflow. The existing supplier, inventory, Min/Max, Production, Planning, recipes, WIP and Good-credit architecture is retained.

Primary-source review: [Autodesk Fusion Operations material requests](https://help.fusionoperations.autodesk.com/en/articles/4004268-material-requests-in-the-back-office) supports separating known item identification from operational handoff. [Supabase database functions](https://supabase.com/docs/guides/database/functions) informed retention of narrow authenticated wrappers and protected private helpers. These references did not justify a supplier/lifecycle redesign. Implementation used Sol High rigor for state and authorization boundaries. PRODUCT_DIFFERENTIATORS was reviewed; this correction changes no competitive classification or material claim, so its pre-existing dirty bytes were preserved.

## Implemented behavior and actual root cause

The shared Purchasing component previously calculated `manage = !mine && can('purchasing','edit')`, without excluding its Warehouse `stock` context. The existing Nasser TESTING account independently has Purchasing permission and support scope, so Warehouse exposed Purchasing management controls. This was an interface-context defect; investigation did not find a grant based merely on Warehouse title or request ownership. Existing database checks already require per-person Purchasing edit for management actions.

Warehouse and My Purchase Requests now present requester controls even when that person independently manages Purchasing. Purchasing management remains available on the dedicated Purchasing page. Supplier readers are not loaded in requester contexts. Request details show identity/Details, quantity, unit, requester/context/date, current status, selected supplier, messages and history. Supplier Directory remains outside Warehouse.

Own cancellation requires a reason and is allowed only in REQUESTED, UNDER_REVIEW and NEEDS_CLARIFICATION. ORDERED, READY_FOR_RECEIPT and RECEIVED deny it at the database boundary. Own clarification reply remains available without arbitrary status controls. Original requesters may confirm READY direct non-stock receipt without any stock movement. Linked stock requires Warehouse edit and the existing External Receipt ledger; request completion and movement remain atomic and idempotent.

Warehouse creation has one searchable Item combobox, browsing/paged results, keyboard navigation, name/code/Arabic-name filtering and Other. Existing identities preserve stock links and authoritative units; Details is optional. Other requires Details, positive Quantity and approved Unit, defaults to Piece, permits kg/Meter and uses Details to derive the internal request display name. There is no second Item Name or Notes field, and no catalogue identity or stock is created.

The table uses automatic header/content widths, inline centered non-wrapping header controls and compact wrapping cells. No percentage column widths or forced 940px minimum remain. Nested action buttons wrap between words to prevent unnecessarily tall rows. Sticky headers, filter indications, bounded native scrolling and mobile cards remain.

## Migration and preservation

One forward migration: `20261004071613_purchase_requester_controls.sql`, applied only to TESTING `silmfbpjyepalnggwulp`. Fresh Local/TESTING histories match all 73 versions/names. All 72 previous migration SHA256 values and the exact submitted new SQL were preserved. DEV history was deliberately not queried; no claim of current DEV alignment.

No schema/table, role, account or persistent grant change. The migration extends the existing private Warehouse purchase helper for Other, extends the own-cancel predicate for UNDER_REVIEW, and updates the existing public reader for Arabic catalogue matching, own direct Warehouse request visibility and selected supplier name. Authenticated public wrappers and private-function restrictions are retained. Actor/time, request events and retry IDs remain server-owned.

Of 62 original dirty files, nine are extended by this task; the other 53 remain byte-identical. Three new files were added. HEAD, main and qa-baseline refs are unchanged. Tracked whitespace checks pass; the previously documented applied migration trailing-space exception at `20261003145325_sales_dates_inventory_sources.sql:123` is untouched. Build-generated next-env was restored byte-for-byte.

## Automated verification

- Focused Warehouse/Purchasing UI, supply contract, Sales receipt and Production recording: **191/191**.
- Full Node: **567/567**, zero failures/skips; 31 additional cases over the prior 536.
- TypeScript: passed; isolated `.next-check` production build: passed.
- Nine distinct final-schema SQL rollback suites passed: purchase-requester (**75 assertions**), supply-flow (**99**), warehouse-manual-purchase (**34**), warehouse-master, sales-stock-sources, sales-fulfillment, production-recording, unfinished-production and snapshot-authorization.
- SQL permission fixtures expire support scope and adjust existing persons' grants only inside rollback. This tests real per-person checks without weakening production authorization or creating accounts. Every fixture rolls back.
- New SQL covers four department contexts, seven denied management actions each, ownership, cancellation states/reasons, direct/stock receipt, no catalogue/stock creation, supplier progression, configured units, invalid input, retries, direct table-write denial and private helper denial.

Logs: `C:\Users\Temp\AppData\Local\Temp\factory-requester-focused.log`, `factory-requester-full.log`, `factory-requester-build.log`.

## Live TESTING A–H

Existing signed-in Nasser / Nova factory; no new account, supplier, material, Product or grant.

| Check | Evidence |
|---|---|
| A — Headers | At 1440px, all 12 title/filter pairs have equal tops and 28px control height in EN/AR. Table region/content both 1268px. Semi-Finished arrow stays inline. Long content wraps. Final screenshot inspected; action-word splitting corrected. |
| B — Known Item | PVC filtering returns matching existing Products/materials; selecting PVC Resin retains kg and optional Details with one Item field, no Notes/second name. |
| C — Other | Required Details/positive Quantity; Piece default changed to kg and back. Arabic search for راتنج returns Arabic resin matches plus أخرى. Other creates no stock identity. |
| D — Requester | PR-0000121 own Warehouse view exposes only reasoned cancellation, status/history and Close. Nasser independently retains management on Purchasing. Negative database cases use rollback persons without Purchasing edit; do not mistake View As/full-access UI for permission-negative evidence. |
| E — Cancel | PR-0000121 progressed through Purchasing to UNDER_REVIEW, then cancelled from My Purchase Requests with reason. PR-0000122 ORDERED requester view has no cancellation/status buttons. Other forbidden states are database-tested. |
| F — Stock | Pre-existing QA PR-0000057 was already UNDER_REVIEW at task start. Existing supplier selected, progressed Ordered → Ready, then Warehouse showed Receive into Warehouse and no direct Confirm Received. Its 1kg receipt completed PR57 and added exactly one material ledger entry: sum 53 → 54kg, count 3 → 4. Repeat/retry rejection and exactly-once behavior additionally pass SQL. |
| G — Direct | Other PR-0000122 (2 Piece) progressed through Purchasing to Ready, then original requester confirmed in Arabic. Status RECEIVED; NULL stock links. Material ledger remained count3/sum53 immediately after this receipt. No stock movement. |
| H — Arabic/mobile | Actual Arabic autocomplete/Other/direct receipt/status/history and desktop headers checked. EN/AR mobile cards and dialogs checked with narrow viewport; document client/content widths matched (375px). No real-device touch certification claimed. |

QA requests PR121 CANCELLED and PR122 RECEIVED are retained. Existing QA PR57 is now RECEIVED. User Production requests PR34 READY_FOR_RECEIPT and PR35 ORDERED are untouched. Final full-table digests match the baseline for production_lines, work_centers, production_orders, production_transfers, products, materials, user_permissions and memberships. Inventory is intentionally +1kg only for PR57; do not claim all movements unchanged. Website remains running at localhost:3000 with Warehouse open; temporary viewport override cleared.

Screenshots outside repo: `C:\Users\Temp\AppData\Local\Temp\factory-requester-20261004` (`warehouse-final-en.png`, `warehouse-headers-ar.png`, `autocomplete-ar-mobile.png`, `other-request-en.png`, `warehouse-requester-en.png`, `requester-ordered-mobile.png`, `direct-ready-ar-mobile.png`, `direct-received-ar-mobile.png`, `stock-ready-en-mobile.png`).

## Requested 48-test coverage

| # | Concern | Evidence |
|---|---|---|
|1|Inline label/arrow|CSS contract + A EN/AR measured geometry|
|2|No arrow below title|No-wrap CSS + A|
|3|Compact columns|Auto-width/no forced minimum contract + A|
|4|Cell wrapping|CSS contract + actual screenshots/action-word correction|
|5|Warehouse cannot review|75 SQL department/caller matrix + requester UI|
|6|Production cannot review|75 SQL department/caller matrix|
|7|Maintenance cannot order|75 SQL department/caller matrix|
|8|Administration cannot mark Ready|75 SQL department/caller matrix|
|9|Requester sees status|UI context/state matrix + D/E/G|
|10|Own Requested cancellation|UI +75 SQL|
|11|Own Under Review cancellation|UI +75 SQL + E|
|12|Ordered cancellation denied|UI +75 SQL + E|
|13|Ready cancellation denied|UI +75 SQL|
|14|Received cancellation denied|UI +75 SQL|
|15|Purchasing progresses|Existing99/new75 SQL + live PR122/57|
|16|Server permission boundary|75 SQL denied actions/table writes/private helper +99 authorization|
|17|No direct stock Received|UI +75 SQL + F|
|18|External Receipt path|75/99/34 SQL + F|
|19|One inventory increment|75 SQL + F count/sum|
|20|Stock request Received|75 SQL + F|
|21|Repeat does not count twice|75/99/34 retry/fresh duplicate SQL|
|22|Original direct requester receipt|75/99 SQL + G|
|23|No direct stock movement|75/99 SQL + G ledger baseline|
|24|Direct Received|75/99 SQL + G|
|25|One Item field|EN/AR form tests + B/C|
|26|Typing filters|UI +75 SQL name/Arabic/code + B/C|
|27|Known selection|EN/AR and keyboard UI + B|
|28|No second name field|Form/contract + B/C|
|29|Other option|EN/AR UI + C|
|30|Known stock link|75/34 SQL + F|
|31|Known Details optional|EN/AR UI +75/34 SQL + B|
|32|Configured unit|EN/AR UI +75/34 SQL + B|
|33|Other direct path|Narrow contract +75 SQL + G|
|34|Details required|EN/AR UI +75 invalid-details SQL + C|
|35|Quantity required|UI/contract +75 positive/NaN SQL|
|36|Unit required|UI/contract +75 invalid-unit SQL|
|37|Piece default|EN/AR UI + C|
|38|Valid unit changes|EN/AR UI +75 kg SQL + C|
|39|No auto catalogue item|75 SQL + live material/Product digests|
|40|Purchasing lifecycle|99/75 SQL + live PR122/57|
|41|Supplier selection|99/75 SQL + existing supplier live|
|42|Warehouse External Receipt|75/99/34 SQL + F|
|43|Duplicate protection|99/34 SQL + narrow contract retries|
|44|Min/Max unchanged|Warehouse-master/Sales-source SQL + existing Node regressions|
|45|Production requests|UI department matrix +99/75 SQL; live PR34/35 preserved|
|46|Maintenance requests|UI department matrix +99/75 SQL; existing received Maintenance request preserved|
|47|English|Actual desktop/mobile + EN UI tests|
|48|Arabic/RTL|Actual autocomplete/receipt/mobile/desktop + AR UI tests|

## Exact task delta and next step

Extended nine existing dirty files: `src/app/globals.css`, `src/features/Purchasing.tsx`, `src/features/WarehousePurchase.tsx`, `src/locales/en.json`, `src/locales/ar.json`, `tests/supply-contract.test.mjs`, `tests/supply-ui.test.mjs`, `tests/warehouse-master.test.mjs`, `HANDOFF.md`.

Added three: `supabase/migrations/20261004071613_purchase_requester_controls.sql`, `tests/purchase-requester.test.sql`, this document. Total12.

IMPLEMENTED and agent-verified. User manual acceptance/freeze and real-device touch remain NEEDS VERIFICATION. No business decision required. Prior deferred partial receipt/issue, catalogue/recipe/snapshot limits, calibration, automatic consumption, MRP/accounting and publication hardening remain unchanged. No commit/push or DEV authorization implied.
