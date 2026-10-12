# Global table headers and alignment — 2026-10-12

Implemented locally on development, HEAD3e249c9d222a08ebe1e85c5fd401818821ed77d2; existing dirty Quality/Export/design work preserved. No business logic, accounts, permissions, records, migrations, commit/push or protected-environment operations.

## Shared implementation

Existing native tables use `.table-wrap`, `.quality-table-wrap` or `.inventory-table-scroll`; there is no shared React Table component. The horizontal-overflow wrappers previously trapped sticky headers while their unbounded height moved all rows into page scrolling. Shared global CSS now bounds long general/Quality tables to min(70dvh,100dvh−8rem), with one overflow:auto owner for both axes. Short tables retain natural height and do not acquire a vertical scrollbar. Warehouse retains its original smaller viewport-aware scroll limit. Headers stick at block-start0 of that actual scroll owner, with opaque existing surface token, border shadow and layer3. Separate borders avoid collapsed-border painting issues. Warehouse's inline-start header intersection remains layer4 over the layer1 body column in EN/AR.

All native header/body/footer cells in those wrappers use text-align:center/vertical-align:middle; row actions use centered flex justification; multiline notes, metric links and preformatted values center their blocks. Cell display remains native table-cell except the existing Quality mobile card layout. No operational text is truncated or retyped; existing bdi/unit logic remains unchanged.

Actual desktop application banner is position:static, so no fixed-navigation inset is needed. The table header sticks within its scroll area rather than becoming a global floating copy; scrolling the page moves the table as a unit. Multiple tables each own their own scroll area. Existing dropdowns/popovers/Export tools remain outside the bounded table or in the browser top layer.

## Exceptions and coverage

- Native tables in Quality, Production History, Warehouse Inventory, Purchasing, Lean/libraries/comparisons, Downtime Analysis, Reports, Configuration, Administration and Audit History inherit the shared rule. Browser minimum coverage is listed below; remaining pages were inspected in source, not separately certified live.
- Sales, Production queue lists, Planning Gantt/lists and Maintenance currently use cards/grid layouts rather than native data tables. They receive no sticky-table rule; no chart, diagram or queue redesign.
- Existing mobile cards remain: Quality <=520px repeats each cell label and centers its content, using page scrolling without a second card-container scrollbar. History, Warehouse, Purchasing and Lean retain their existing card breakpoints; hidden desktop tables stay hidden.
- A native dialog already owns scrolling: table wrappers inside it use visible overflow/no max height, so sticky headers use the dialog itself and no additional vertical scroll owner. This modal exception was source/stylesheet-tested; no existing native-table modal was exercised. A real expanded panel table was exercised instead, meeting the requested panel-or-drawer coverage.
- Print resets wrapper limits/overflow and all sticky cells to static with a scoped print-only override that also defeats more specific first-column rules, keeping table-header-group repetition. Export/Print server documents and workbook code are unchanged and their focused tests passed. No native Print dialog/download was repeated, so actual printer output is not newly certified.

## Real localhost3000 read-only browser checks

Used existing authorized Ahmed Al Mansour / Nova session. No write form submitted, permission checkbox changed, production/inventory command invoked or test record created. Navigation, language, viewport and scrolling only; Warehouse filter dialog opened and closed without applying. An employee was selected only to display existing access; no grants/packages were edited/saved, and selection was cleared before exit.

| Table | Existing rows | Verified |
| --- | ---: | --- |
| Quality |38|EN top, halfway (scrollTop4800), final (8787/max8788); aligned sticky header/body coordinates;19 High Scrap and unchanged normal zebra; all cells centered; AR desktop and768 horizontal RTL (scrollLeft−309.6);390 labelled cards, no page overflow.|
| Production History |38|EN top, middle1600, final2992/max2992; horizontal383.2 with columns aligned; AR top/final2596 and horizontal−383.2, zero centering failures;390 retains mobile cards/no overflow; filters/sort/pagination markup retained.|
| Warehouse Inventory |12|EN top, near-final800, final892.8/max893; horizontal86.4; first header/body column aligned and intersection z4; filter dialog accessible; AR final and1024 horizontal−63.2;390 uses existing cards/no page overflow.|
| Purchasing |11|EN top, middle400, final780/max780; AR desktop;768 retains horizontal table within page width.|
| Expanded legacy-template panel |16|Real existing panel/table top, final and keyboard scrolled423.2; centered cells and pinned header. No editor opened or saved.|

All measured visible native-table cells had zero text/vertical-centering failures. Header and corresponding first-body-cell x/width differences stayed below1px during scrolling, including sticky-column intersections. Header backgrounds remained opaque white on the active light palette. Header remained at wrapper top (+border) at middle/end. Quality action groups centered, warnings retained their original tint, ordinary rows retained base/alternate surfaces. Browser error/warning log empty.

Arabic RTL and numeric bdi retained; tablet horizontal overflow stays inside its table, mobile document width375<=viewport390. Desktop tested1280x800. Temporary viewport override reset at end; language restored to English, owner Quality page left available. No new cross-environment access or database inspection was needed.

## Validation and exact files

-59/59 focused Node tests:5 new shared-layout contracts plus existing Quality visual/EN/AR UI and Table Export/Print tests. Covers bounded scroll ownership, header painting, alignment, sticky intersection/RTL, modal/mobile exceptions, print resets and semantic-color preservation. Static contracts supplement, not replace, actual browser evidence.
-TypeScript passed; production build passed using isolated `.next-table-check` to preserve running development output. Build-generated tsconfig.json/next-env.d.ts restored byte-for-byte; TypeScript passed again after restoration. No configuration/dependency change retained.
-Task files: src/app/globals.css, tests/table-layout.test.mjs, this report, HANDOFF.md. All prior non-task files/migrations preserved against the pre-task hash manifest.

External evidence: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Sticky-Tables-20261012 (preservation manifests, browser-measurements.json, Quality desktop/tablet/mobile, History and Warehouse screenshots). The temporary .next-table-check build output was not ignored by Git; it was preserved in this evidence folder's build-output directory, leaving no generated build files in the worktree. Pointer-driven sidebar expansion initially selected adjacent navigation; keyboard navigation resolved it. No application defect or record mutation is inferred from that browser-control issue. Modal-specific native-table rendering and physical print remain unverified, as noted above. Owner visually approved the latest sticky headers, centered cells and responsive table refinements on 2026-10-12. The selective 69-file local checkpoint is authorized; no push or deployment is authorized. Existing verification limits above remain unchanged.
