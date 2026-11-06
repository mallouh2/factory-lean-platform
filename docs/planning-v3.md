# Gantt connector cleanup and lane identity —31 October2026

**LOCAL COMPLETE; owner visual review pending — STOP.** This supersedes the connector styling below. The stray elbow came from `.planning-gantt-compact .planning-job-caption::before`, with a second reverse-edge rule. Both pseudo-element rules were removed. The separate168×44px label,12px gap and exact saved-duration marker remain; no time-geometry or collision-layout calculation changed. The small blue mark is still the actual scheduled interval, not a stray connector.

Each production line now receives a narrow4px accent at the line-name edge, an8% white-blended header tint and a4% canvas-blended track tint. Six existing chart-series tokens are reused; the current five preview lines are distinct. The palette cycles for larger line sets. Tones are assigned from the full nonarchived line set sorted by stable ID, independent of filtering or server row order. No semantic job-state, warning, HIGH badge, focus or drop-feedback color is replaced. The accent follows the label's logical edge in EN/AR. No new controls or workflow.

**Verification:** focused Gantt/Planning/workspace/refresh Node suites PASS; TypeScript and exact isolated optimized webpack build PASS. Actual owner login/read-only browser checks PASS at1440/768/390 English and390 Arabic: connector pseudo-content `none`, exact one-minute band, readable timing/priority/warnings, keyboard/caption selection, distinct five-lane computed accents/backgrounds, stable tone after filtering, Day/Week and Previous/Next. Existing dragstart transfers the correct item ID and dragend cancels cleanly, without dropping or saving owner work. Readiness is awaited normally; no disabled control is overridden. Prior protected schedule/replan/permission evidence remains applicable because its source/contracts are unchanged; no new scheduling transaction or SQL test was needed for this visual-only change.

Final4222 app: two real30s refresh cycles at desktop English and390 Arabic preserve page/scroll, chart/bar identity, lane tones, range/focus and open drawer/draft. Existing raw visual-lint heuristic findings remain documented below; the removed connector no longer paints. Actual navy label/secondary text contrast remains13.90:1/8.12:1. No browser exceptions or owner business POSTs.

Exact six-file task manifest: `src/app/globals.css`, `src/features/ProductionPlanning.tsx`, `tests/planning-gantt-industrial.mjs`, `tests/planning-gantt-stability.mjs`, this report and `HANDOFF.md`. Evidence is in the existing preview root's `gantt-cleanup/`: before/after responsive screenshots, after-week-ar.png, after-visual.json, stability.json and preservation.json. Original evidence remains intact. No dependency, migration, other module or scheduling/business-rule change.

Running: **http://127.0.0.1:4222/?view=planning**, matching external `gantt-cleanup-app` under the existing FactoryLean-Planning-V3 temp root. Same owner and credentials; main Auth4304/database55496 retained without restart. All118 owner table digests,135 migration hashes,credentials,Export Reader,Design System and unrelated dirty work unchanged. Both shipped gates FALSE. No hosted access,deployment,Git writes,3000 or unrelated-preview operations. STOP for visual review.

# Modern Industrial Gantt refinement —31 October2026

**LOCAL COMPLETE; rendered owner approval pending — STOP.** Applies only to the existing approved Gantt, following the approved Blue & Navy direction. No scheduler, API, permission, inventory, database, migration, theme-wide or other Planning-layout change.

## Visual and time geometry

Scoped Gantt variables reuse the canvas/brand/teal/dark-surface tokens with approved local header `#E7EDF6`, grid `#D7E1EE`, navy `#253B58` and secondary `#526981`. Normal planned bands are solid brand blue with white text; active bands are teal, including active work with a separate lateness warning. Conflict warnings remain explicit. HIGH/URGENT stays a restrained amber text badge, independently of status. Grid/date/line-column divisions are stronger, current time is amber, and hover/focus is restrained. Completed styling is muted slate, but completed jobs remain in History rather than being newly added to the active Gantt. No application-wide palette replacement.

Exact clipped percentage coordinates still come solely from saved start/finish and the active window. No duration minimum or timestamp rewrite. A short production interval uses a true-width,16px-high mark and a detached168×44px navy annotation separated by12px and a thin elbow connector. The annotation displays item reference, actual clock interval and shared human duration, plus existing priority/lock/warning information. It is explicitly distinct from the duration band. Unknown finishes remain unknown. Clock labels use factory timezone and retain hours/minutes even in Week view; full dates/times/duration remain in title, accessible name and the existing drawer. Explicit Show on timeline and keyboard focus bring the annotation into view on mobile; refresh never invokes this navigation.

Presentation packing now reserves the union of marker, connector and annotation, with stable ID tie-breaking. Adjacent short jobs gain only necessary annotation subtracks in the same production-line lane; saved times/assignments never move. Existing maintenance-caption geometry and occupancy contracts are preserved.

## Verified evidence

- Read-only actual owner PO-0000050 remains planned/HIGH/replacement6m, saved **31Oct06:58–06:59UTC**. Width is **0.0694444%** of Day and **0.00992063%** of Week, independent of the168px callout. Actual rendered Day band is approximately0.81–0.83px at the tested track widths. PO-0000020 completion10m and PO-0000052 internal stock2m remain unscheduled; no bars or receipts invented.
- **129/129 focused Node tests PASS**: exact/clipped coordinates, Day/Week/narrow scales, detached geometry, stable collision packing, unknown timing, existing scheduling/Printing/calendar/capability behavior, operational readers and refresh lifecycle. **TypeScript and exact isolated optimized webpack build PASS.** No unrelated broad suite repeated; prior documented Sales harness failures remain historical and separate.
- **Six current standalone PostgreSQL assertions PASS**, rollback-only on independently verified disposable55499: four duration boundaries, prior saved interval unchanged and confirmed-maintenance overlap rejection. No SQL source/migration changed.
- Fresh separate QA fixtures on55499/Auth4320/app4237: protected request/manual Save/native queue drag **200**, native short-caption replan **200**, mandatory reason and protected history **200/two revisions**. Capability **400/planningIncompatibleLine**, locked **400/planningLockedMessage**, real restricted-user and known foreign-factory-context **400/permissionError**, with denied targets unchanged. Foreign-context coverage uses a known existing foreign factory with the local fixture item, not an invented foreign operational order.
- Two close2min jobs have disjoint44px-high annotations on separate tracks. A real3600m/361min planned fixture has exact25.0694% Day width, solid blue and white text; Week width follows the new scale. An existing active QA job renders teal, without starting/completing production for the test. Fixtures and IDs are retained in `industrial-browser.json`; no stock/output/receipt write.
- Actual owner screenshots inspected at1440/768/390 English and390 Arabic; Day/Week, Previous/Next roundtrip, selection/keyboard/drawer and LTR time chronology in RTL PASS. No document overflow outside the intended timeline scroller, authenticated API failure or page exception. Owner browser blocks all business POSTs after login.
- Final port4222 optimized build observed through **two real30s polling cycles each at1440 English and390 Arabic**: document height/scroll, horizontal scroll, timeline/bar node identities, range, focus, drawer selection/scroll and unsaved input remain stable. Automatic polling remains enabled and unchanged.
- Shared visual lint raw results retained. Its overflow flags correspond to the intentional scroller, detached visible-overflow caption/connector and tiny warning glyph (12px client height/14px scroll height, overflow visible). The transparent time-button ancestor triggers a contrast heuristic; actual text is painted on opaque navy/blue surfaces. Computed caption text contrast is13.90:1 and secondary clock text8.12:1; screenshot review confirms readable text. These heuristic findings are documented, not silently suppressed or counted as application failures.

This is real localhost application/SQL/auth-adapter evidence, not hosted Supabase acceptance or customer usability proof. Prior research/approved structural design are reused; no new workflow or product differentiation claim is introduced.

## Preservation, runtime and complete task manifest

All118 owner public/private/auth table digests unchanged;135 prior migration hashes, Export Reader, Design System, existing credentials and unrelated dirty work preserved. Both shipped manufactured-output and completed-shift recording gates remain FALSE; the inherited disposable test predicate is unchanged. QA identities/grants remain unchanged. No hosted access, deployment, activation, Git write or3000/3001 operation. Separate QA services stopped afterward; main Auth4304 and database55496 kept running.

Preview: **http://127.0.0.1:4222/?view=planning**. Exact matching external app: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\industrial-release-app`. Existing owner: `PlanningV3@local.invalid`; unchanged owner-restricted credentials file: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`. No passwords in repository or evidence.

Evidence directory: that preview root's `gantt-industrial/`, including before/after1440-en,768-en,390-en,390-ar PNGs; after-week-ar.png; after-visual.json with raw lint/computed contrast; stability.json and preservation.json. Separate QA root retains industrial-browser.json and industrial-busy-day.png,industrial-busy-week.png,industrial-active.png. Original prior-task evidence remains untouched.

Exactly11 repository files changed for this task, relative to its preserved dirty starting state:

```text
HANDOFF.md
docs/planning-v3.md
src/app/globals.css
src/features/ProductionPlanning.tsx
src/utils/planning-gantt.mjs
tests/planning-gantt.test.mjs
tests/planning-gantt-browser.mjs
tests/planning-gantt-replan.mjs
tests/planning-gantt-stability.mjs
tests/planning-gantt-industrial.mjs
tests/planning-gantt-industrial-fixtures.mjs
```

No known new functional blocker. Owner visual approval remains pending. STOP; no automatic next task/checkpoint.

# Gantt visual redesign —31 October2026

**LOCAL COMPLETE; owner visual approval pending — STOP.** This section supersedes the former Gantt presentation below. The three Planning sections, their data and protected scheduling contracts remain intact.

## Before and implemented design

The old line column repeated Current/Next production cards, operational status/load percentages and supporting text. It dictated tall rows while short scheduled jobs were reduced to hard-to-select fragments. Bar colors varied by Product. The minimum0.3% width exaggerated short intervals, and the principal reference could be the parent request rather than the actual Production Item.

The timeline now has one compact primary lane per line, a fixed sticky line name, concise visible-job count and a chronological time axis. Current/Next panels, live production progress, repeated Product cards and load meters are removed from the Gantt only. Factory Floor and underlying data are untouched. The owner example capture shrank from1044px to697px high at the same1300px panel width; screenshot dimensions are preserved in the evidence directory. Empty lanes stay compact. Visual subtracks are added only where time bands or their labels overlap; Production and Maintenance can share a visual track when they fit. This layout is presentation, not a scheduling algorithm or permission decision.

Saved order intervals are clipped to the selected window with exact percentage coordinates. Short jobs keep a true-duration mark plus a separate readable,44px-high selectable caption. The caption is not a longer time reservation. Long bars show order/Product and typed quantity/status when space permits. Parent request linkage remains available in context, while the displayed bar reference is the actual item code. Unknown saved timing stays unknown: no invented one-hour interval or current timestamp. Unknown-time work has an explicit unpositioned warning entry. Maintenance continuing holds, physical-stop strips, overrun and protected capacity remain intact.

Planned/active/conflicting states use existing semantic tokens, with explicit text/context, HIGH/URGENT text badges, lock indication and visible warning markers. Product-derived decorative colors were removed from saved Gantt bars. Closed hours and day boundaries remain visible. Arbitrary window starts show minutes accurately; local midnight separators retain factory timezone meaning. The axis remains LTR in Arabic; line/caption/drawer text supports RTL. Day-boundary calculation is memoized to avoid repeating timezone conversion during drag previews.

**Find scheduled work** explicitly navigates to upcoming saved work, or the most recent saved work when none is upcoming. **Show on timeline** in the existing drawer locates that item. These actions change only the view; there is no automatic viewport reset during refresh. A visible in-view count/timezone distinguishes the current time window from the full scheduled queue. Day/Week, custom range/zoom, pan, keyboard/horizontal scrolling and native drag remain. The existing drawer supplies scheduling actions and now explicitly shows saved line/start/finish. Saved bar tooltips describe saved evidence rather than a prospective duration recomputed using current rates. Prospective rate/setup calculations remain in the existing drawer Details and preview paths.

Research: resource-oriented charts and date navigation are documented in [MRPeasy Production Schedule](https://www.mrpeasy.com/resources/user-manual/production-planning/production-schedule/) and [Autodesk Fusion Operations Scheduling101](https://help.fusionoperations.autodesk.com/en/articles/6187683-scheduling-101). These informed the presentation only. Existing components/CSS/tokens were reused; no Gantt dependency or new scheduling engine. Product differentiators reviewed: no new competitive-capability claim for this bounded UX correction.

## Read-only owner verification

- PO-0000050: actual6m replacement, HIGH, Extrusion line,31Oct06:58–06:59UTC, originalPO-0000036. Exactly one bar with item referencePO50; its one-minute width is0.0694444% in a24h window, rather than the former0.3% minimum. Drawer shows saved timestamps/source correctly. Its parent request remainsPO49; no record or schedule was rewritten.
- PO-0000020:10m unfinished completion, normal, unscheduled. PO-0000052:2m internal stock, normal, unscheduled. Neither appears as a scheduled bar. Their unified queue entries remain.
- Existing saved intervals, source relationships, quantities, priority values, lock/replan history,118 public/private/auth table digests and credentials remain unchanged. All135 prior migration files, Export Reader and Design System bytes remain unchanged. No new migration.
- Completed/cancelled/retired work stays in existing history; a new historical timeline/lifecycle was not introduced.

## Verification and exact limits

**126/126 focused Node tests PASS:** Gantt geometry/clipping/narrow labels/unknown timing, presentation track sharing, time-window navigation, actual work/priority labels, existing calendar/rate/finish, Printing invalid/no-fit safety, manual/drag/replan guards, operational board completeness, permission/API handling and refresh lifecycle. Superseded Current/Next/load-meter/setup-display assertions were updated to the approved presentation; pure capacity, setup/calendar and protected-write assertions remain. TypeScript and the exact isolated optimized webpack build PASS. No unrelated historical suites were repeated; prior documented Sales harness failures remain separate and were not relabelled green.

**Six current standalone PostgreSQL assertions PASS** using the existing rollback-only scheduling test:10m→2min,10.1m→3min,.1m→2min,20m→3min, earlier saved3min interval preserved, and a confirmed Maintenance reservation rejects overlapping scheduling without persisting it. No activation was changed and the test reservation rolled back. No production SQL or migration was edited.

**Actual browser/SQL QA PASS** on separate verified disposable55499/Auth4320/app4237 using existing users/resources. Two new small internal requests automatically appeared via normal polling. Printing manual Save200 and native queue-to-Gantt drag200 persisted correct2min planned intervals. An existing Extrusion fixture remained usable without changing its schedule. Native drag of the new scheduled caption opened the mandatory reason dialog; authorized revision200 and protected history200 produced two revisions while preserving quantity and actual execution. Capability400/planningIncompatibleLine, locked400/planningLockedMessage, actual restricted-login400/permissionError and known foreign-factory-context400/permissionError left targets unchanged. Foreign testing used an existing foreign factory with the local fixture item, not an invented foreign order. No stock/Quality/production output/receipt transaction occurred. Existing identity/permission-table digests remain unchanged. QA runtime is stopped afterward; fixtures/results retained.

**Actual owner browser PASS** at1440,768,390 English and390 Arabic: bar placement/caption click, saved-time/source drawer, explicit view navigation, correct priority/type, no duplicate/unscheduled bars, no document overflow or page errors. No owner business POSTs. Before/after screenshots inspected. Shared visual-runtime lint found no low contrast, tiny text or console errors on the scoped Gantt. Its raw overflow flags are the intentional horizontal scroller and separate compact captions outside true-width buttons; screenshots confirm captions are visible. Findings were retained, not silently suppressed.

**Two real30s refresh cycles in desktop and Arabic390** retain document height/scroll, timeline identity/horizontal position, bar identity, range start, focus, selection/open drawer and unsubmitted input. No missing bars or authenticated read errors. Polling interval and shared refresh lifecycle are unchanged. These are real local application/SQL/auth-adapter tests, not hosted Supabase acceptance. No measured customer training or production-factory performance claim is made.

## Evidence, manifest and handoff

[Before desktop](C:/Users/Temp/AppData/Local/Temp/FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/gantt-redesign/before-desktop.png) · [After desktop](C:/Users/Temp/AppData/Local/Temp/FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/gantt-redesign/after-1440-en.png) · [Tablet](C:/Users/Temp/AppData/Local/Temp/FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/gantt-redesign/after-768-en.png) · [Mobile](C:/Users/Temp/AppData/Local/Temp/FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/gantt-redesign/after-390-en.png) · [Arabic mobile](C:/Users/Temp/AppData/Local/Temp/FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2/gantt-redesign/after-390-ar.png). Full traces: preview-root/gantt-redesign/owner.json,stability.json,visual-lint.json,preservation.json. Separate QA root has gantt-browser.json and gantt-protected-sql.txt. No credentials in artifacts/reports.

Complete task-specific14-file manifest, relative to the preserved dirty starting checkout:

```text
HANDOFF.md
docs/planning-v3.md
src/app/globals.css
src/features/ProductionPlanning.tsx
src/features/MaintenanceTimelineBlock.tsx
src/locales/en.json
src/locales/ar.json
src/utils/planning-gantt.mjs
tests/planning.test.mjs
tests/planning-gantt.test.mjs
tests/planning-gantt-owner.mjs
tests/planning-gantt-browser.mjs
tests/planning-gantt-replan.mjs
tests/planning-gantt-stability.mjs
```

**Running:**http://127.0.0.1:4222/?view=planning, matching gantt-release-app; existing PlanningV3@local.invalid and unchanged restricted credentials file C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt. Main database55496/Auth4304 retained; no Auth restart/session reset. Both shipped gates FALSE; inherited disposable manufactured-output test predicate unchanged. No hosted application/database access, deployment, activation, Git writes,3000/3001 change or unrelated-preview restart. Only public product documentation was browsed. Preserve all uncommitted work. Stop for owner visual approval; no further redesign/checkpoint is authorized.

---

# Final Planning workspace and refresh integration —31 October2026

**LOCAL COMPLETE / OWNER MANUAL ACCEPTANCE PENDING — STOP.** Ordinary Planning contains exactly three operational sections: Unscheduled Production Orders, Interactive Gantt, and Scheduled/In-Production Orders. The legacy completion/replacement decision table and separate work/retired cards are unmounted, with no replacement accordion. Completed/cancelled/retired work is excluded from active presentation; existing source/history contexts remain available. The scheduling engine, native Gantt, protected writers, source allocations and original demand are unchanged.

Work type is now an explicit EN/AR table column in both queues. Normal/Internal Stock/Completion/Replacement/Stock Recovery classification uses authoritative request/work relationships, never names. HIGH/URGENT semantic badges with visible text are consistent in both queues and the drawer. Current owner data was read, not assumed: PO-0000020 is10m COMPLETE, normal, unscheduled, originating PO-0000018; PO-0000050 is6m REPLACE, HIGH, scheduled on Extrusion31Oct06:58–06:59UTC, originating PO-0000036; PO-0000052 is2m internal stock, normal, unscheduled. Each has one lifecycle-table row. PO50's Gantt block correctly uses its parent request PO-0000049 and persisted start. Its elapsed schedule was not rewritten.

Unique decision access remains outside ordinary scheduling: Production → Quality Updates → linked job Details opens the protected source/work context (actual owner PO36→PO50 browser GET200, zero business POSTs). Production History → recorded output Details → Recovery/replacement work also retains source-scoped STOCK recovery and protected cancel/change commands, including sources without an existing job. No generic Warehouse row is guessed to be a specific source.

**Justified reader migration:**20261031120000_planning_work_metadata_v1.sql. The old manufactured_completion_read work query independently limited its newest100 jobs while has_more paginated source rows only. Removing its mounted cards without replacing that metadata supply would lose older work type/holds/capability information. The new protected STABLE SECURITY DEFINER reader requires effective factory:view and orders:view, empty search_path, revoked public/anon/service-role execute and explicit authenticated execute. Active-work UUID keyset pages100 carry a complete-set hash/count; changing, duplicate or incomplete page collections fail closed. It reuses existing enabled/held/retired/capable-line functions. No new stock/readiness/scheduling engine or writer. Local files now135; all prior134 migration hashes are unchanged. Installed/tested only in the verified disposable local databases; no hosted-history alignment claim is made.

Background updates no longer insert loaders/banners or remove load indicators around retained data. Page identity, current work, filters, selection, focus, drawers and unsubmitted input remain stable. Actual before/after measurements,32-file task manifest,280 passing focused Node tests, seven PostgreSQL assertion groups, exact build/TypeScript, live QA scheduling/drag/replan and known12 pre-existing Sales-harness failures: see [refresh-layout-stability.md](refresh-layout-stability.md). Thirty-second automatic polling remains active; no scroll restoration hack or application timer change.

**Preview:**http://127.0.0.1:4222/?view=planning; stable-planning-final-app. Existing PlanningV3@local.invalid, unchanged restricted credentials file C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt. Main55496/Auth4304 preserved. Owner table digests, credentials/grants and all unrelated dirty work preserved; both shipped gates FALSE, existing disposable predicate unchanged. No hosted access, deployment, Git writes,3000/3001 or unrelated-preview changes. Product differentiators reviewed; this bounded maintenance adds no competitive-capability claim.

---

# Planning V3 — simplified scheduling workspace

## 31 October2026 — Printing crash and focused scheduling drawer correction

**COMPLETE / LOCAL VERIFIED / OWNER REVIEW PENDING — STOP.** This section supersedes older drawer/scheduling verification below; the three-part page layout is unchanged.

### Verified defects and minimal fixes

1. **Actual owner PO-0000020 / Printing line:** normal authenticated reproduction threw `RangeError: Invalid time value` in `Date.toISOString → localDay → nextWorkingTime → finishAfterWorkingMs → ProductionPlanning`. The protected operational board reports the existing active PO-0000021 with open-ended reserved occupancy. Selecting Printing can return `planningNoFit`, clearing the proposed start. The render then evaluated `finishAfterWorkingMs(NaN, duration, configuredCalendar, zone)` before checking whether a start existed. Owner Product X is genuinely capable on Printing (6000m/hour); this was not evidence of bad equipment configuration or missing permission. Capture: preview-root/planning-fix/reproduction.json,crash.png,operational.json,snapshot.json. Initial pre-login401 is normal; authenticated readers were200.
2. **Corrected boundary:** finite-start check precedes manual scope/calendar calculation. Working-duration helper returns unknown for nonfinite inputs rather than formatting an invalid Date; no-fit suggestions with nonfinite bounds are excluded. Line selection rechecks the existing eligible set; errors leave the drawer usable and Save disabled. Actual reserved/unknown capacity remains blocked. No active job was finished/released/replanned to manufacture availability.
3. **Additional directly relevant finish defect:** real disposable Extrusion Save200 persisted3min while UI expected2min for10m at600m/hour plus1min setup. SQL numeric `10/600*60` evaluates to `1.00000000000000000020`; CEIL adds an unintended minute. New forward `20261031110000_planning_duration_rounding_v1.sql` changes only the existing protected inner planner's expression to `ceil(target.target_quantity * 60 / slowest)`. It retains the function's exact other source, authorization, locks, capabilities, calendar, conflict/revision logic and grants. All existing saved intervals/history remain unchanged, including the first successful3min test schedule. Subsequent verification used a fresh item, never rewrote that success. Production Start's existing conservative intended-maintenance window is unchanged; this is prospective Planning arithmetic only. SHA256:b94f8d0440a904c15b14b2578d9008fff184a1681457ace45e1b8206a8104ec3.

### Drawer and visual changes

Visible order reference, product, prominent typed quantity, authoritative work type, origin, priority and requested deadline are consolidated at the top. Missing deadline says **No requested deadline**. Completion/replacement/stock recovery derive from protected work relationships; legacy replacement linkage is retained. Other stock/Sales/Warehouse origins derive from request_type, never a request name or Quality prose. HIGH and URGENT badges use semantic tokens with readable text; the queue uses the same badge. Existing individual permissions still govern access/actions.

Removed all five OutputRecordLinks department shortcuts from ordinary scheduling, plus the redundant Request/priority/deadline accordion and repeated handoff text. Underlying routes/components/history stay intact. Original-order reference is available as concise contextual Details, with no department button. One line selector, one start, calculated finish, automatic available starts and Save/Cancel remain. Current configured factory timezone is UTC, explicitly labelled once; it is not reinterpreted as the browser/Qatar timezone. Missing timezone is explained and prevents ordinary Save. Rate/setup calculations stay under Details. Existing cross-line specialist advice is retained only there as **Compare line alternatives**, not a repeated Search for Time action. Lock/unlock/history and all blockers remain accessible when applicable.

Scoped existing CSS/token architecture preserves EN/AR/RTL, desktop,768px and390px. Header close control is44px, date/select fields remain contained, natural drawer scrolling retains access to Save. No sidebar, main Floor, Warehouse, Quality or Planning-board redesign. Product differentiators reviewed: bounded correctness/UX maintenance warrants no competitive capability claim.

### Current verification evidence

- **105 affected Node tests PASS:** Planning engine/interactions/presentation, operational board and Maintenance view. Includes selected capable line with empty/invalid start under a real working calendar, no-fit/invalid-duration safety, workflow/source classification, capabilities, locks, replanning reason/history, overlap and scoped source completeness. The prior advanced-slot test was updated to the actual contextual comparison control; no business assertion was removed.
- **Six new standalone PostgreSQL assertions PASS:** four protected prospective quantity/duration boundaries (10→2min,10.1→3min,.1→2min,20→3min including setup), existing3min schedule untouched, confirmed maintenance-reservation blocker rejects without persisting a schedule. Maintenance reservation is a rollback-only fixture; no activation gate changes or surviving confirmation. No production, stock or Loss recalculation.
- **One real concurrent capacity race PASS:** observed transaction lock wait, first2min schedule accepted, competing same-slot schedule rejected `planning_overlap`; no double booking. SQL actual actor/grants and existing lock order are used.
- **Actual browser Save200:** separate capable Extrusion, Printing and legitimate HIGH replacement jobs persist correct line/start/finish and appear in Gantt. No execution/receiving follows. Original replacement demand remains909. Incompatible line400/planningIncompatibleLine, locked schedule400/planningLockedMessage, actual restricted login400/permissionError and known existing foreign-factory context400/permissionError. No invented foreign IDs; that QA copy has no foreign operational jobs, so the latter uses a known foreign factory context with the local fixture item, not a claimed foreign-job acceptance test. Exact known successful saves are recovered/read, not blindly resubmitted.
- **TypeScript and final isolated optimized webpack build PASS.** Authenticated desktop/tablet/390px English and Arabic screenshots inspected. Current owner PO20 Printing displays the legitimate capacity blocker, not a black screen; full reload/blank start/EN-AR390/tablet all PASS. All118 owner table digests unchanged across schema install and read-only browser checks; zero owner business POSTs/page exceptions. Existing compensation/Quality/stock/account permissions remain. Both shipped gates FALSE; inherited disposable helper predicate unchanged.

Standalone local Auth/Data adapter evidence, not hosted Supabase acceptance. Initial harness failures included cold compilation, Save label casing, Gantt's request reference versus item reference, and unavailable foreign operational rows. They were corrected without repeating successful schedules. The duration mismatch was a real SQL defect and is recorded separately, not dismissed as a harness error.

**Owner operational limitation:** Printing remains legitimately reserved by active PO21 with unknown actual finish. Normal authorized execution must finish/release that work before an available slot can be offered there; no queue skipping, forced completion or historical timestamp change was performed. The normal capable/free Printing path was positively verified on an isolated test line. Hosted rollout and wider time-zone configurations were not tested.

### Files, preview and preservation

Incremental17-file scope: `src/features/ProductionPlanning.tsx`, `src/utils/planning.mjs`, `src/utils/planning-workspace.mjs`, `src/app/globals.css`, `src/locales/en.json`, `src/locales/ar.json`, `tests/planning.test.mjs`, `tests/planning-workspace.test.mjs`, new migration above, `tests/planning-drawer-fixture.sql`, `tests/planning-drawer-rounding.sql`, `tests/planning-drawer-concurrency.mjs`, `tests/planning-drawer-browser.mjs`, `tests/planning-drawer-owner.mjs`, `tests/planning-drawer-install-local.mjs`, this report and `HANDOFF.md`.

Preview **http://127.0.0.1:4222/?view=planning**, matching external planning-drawer-app. Existing owner **PlanningV3@local.invalid**, unchanged owner-only credentials: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`. Existing main PostgreSQL55496/Auth4304 retained; only4222 web bundle replaced. Main evidence under that root/planning-fix. Mutations used separate disposable55499/Auth4320/app4236, new configured resources and existing identities; temporary services stopped afterward, records/evidence retained. No existing owner capability/rate, schedule, source allocation or operational record changed. No new accounts/grants.

134 local migration files/all133 pre-task hashes unchanged. Export Reader,untracked Design System,compensation/Quality/Warehouse/sidebar work preserved. One new forward SQL correction installed only in the two verified disposable local runtimes; no claim of hosted history alignment. `development` HEADbb0d20e5dd433b896dd319f56e75f0d9eb5d2862,index empty; no hosted access,deployment,Git writes,3000 or unrelated-preview operation. STOP for owner manual review.

28 October follow-up: [Operational UX corrections](operational-ux-workflow-corrections.md) supersede only the affected Quality/dispatch/overdue-replanning/navigation presentation and contracts. Local verification is separate from owner acceptance; earlier dated evidence below remains historical. No hosted activation or migration edits.

27 October 2026. **LOCAL IMPLEMENTATION COMPLETE; owner visual approval pending.** This is a presentation/integration change over Planning V2, not a new scheduling engine or hosted release.

## Daily workflow

1. **Unscheduled production requests:** one compact item table across existing authorized request origins. Reference, Product, quantity/unit, priority, required-by and real scheduling blocker. Sort by existing priority order, required-by or reference; existing line/Product/priority filters remain. Open the reference by click/Enter for the manual form, or drag that reference to the existing Gantt.
2. **Production schedule:** existing persisted line/time Gantt, protected placement preview, maintenance reservations/actual-stop overlays, conflicts, panning and exact calculated finish. Previous/Today/Next and Day/Week are immediate controls; custom start/zoom and technical availability explanations are optional. Unknown/incomplete availability remains visible and disables advice/drag; manual placement still requires authoritative server validation.
3. **Scheduled and in-production orders:** compact per-item table, with planned start/finish, assigned line, actual persisted execution status and lock/hold information. Separate text identifies elapsed planned start, elapsed planned finish and elapsed customer/business deadline. Production completion does not claim Quality release or Warehouse receipt.
4. **Order details:** existing schedule editor, permitted lock/unschedule, request origin, Sales guidance, calculated finish, history/reasons and permission-filtered related records. Rates/duration calculations and supporting request/history detail are on demand. Related-record explorer returns to the selected order without clearing filters.
5. **Exceptional work:** existing completion/replacement/stock decisions and protected revision/cancellation remain mounted inside a closed, labelled exceptional-work area. Actual created work joins the ordinary queue; its existing capable-line restrictions and Quality hold remain enforced. There is no new work generation or special scheduling queue.

The board reader is date-scoped. The list now merges available snapshot jobs with protected board jobs by ID, with the board taking precedence, so future jobs outside the selected chart range do not disappear from the list. This does not establish completeness for a truncated snapshot; existing authoritative board/resource completeness still governs placement advice. Maintenance and Production Start SQL/readiness contracts are unchanged.

Desktop uses compact tables. At 390px, the same semantic rows present labelled cells so quantities, units and blockers remain visible; long lists scroll within their region. The actual time-based Gantt remains horizontally scrollable in both English and Arabic/RTL. Existing tokens/components/CSS are reused. The MRPeasy [production schedule manual](https://www.mrpeasy.com/resources/user-manual/production-planning/production-schedule/) informed the ordinary chart-to-details interaction; Factory Lean retains its own protected capacity rules and never moves sibling jobs automatically.

## Separate backend dependency: overdue unstarted rescheduling

The owner's approved policy is **not yet enabled**. Current installed `private.record_plan_revision()` still rejects changes when the old planned start has passed, even when actual production has not started. Its latest definition is `20260927215323_preserve_replanning_after_unschedule.sql:10` (elapsed-start check at lines 22–24). The lock command also rejects elapsed starts (`20260927213517_planning_lock_and_revisions.sql:119`). `ProductionPlanning.tsx` deliberately retains matching `editableItem`, `canToggleLock` and `dragReason` guards.

A separate forward migration must replace the elapsed-planned-start veto with authoritative never-started/never-consumed/otherwise-reversible checks under the existing locks, preserving permissions, reason/history, capacity, capability, maintenance, freeze/lock, retries and immutable actual timestamps. Its caller/trigger interactions and races need focused SQL verification. Do not bypass that veto in the UI or edit historical migrations. No migration or scheduling-policy change was made here.

## Verification and preserved state

- **103 affected Node tests PASS:** Planning interactions/engine, presentation timing/sorting, operational board, execution queue and internal production. Old card-only assertions were updated for compact tables and contextual slot assistance; business assertions remain.
- **TypeScript PASS; isolated optimized Webpack production build PASS.** Final browser checks use the final rebuilt source.
- **Real authenticated local browser:** manual scheduling and real queue-to-Gantt drag each returned HTTP 200 from `plan_product_item` and persisted in PostgreSQL. Queues/list/chart updated. Future replan returned HTTP 200 through `revise_product_plan`, required a reason and retained history. Capability/overlap returned HTTP 400 with `planningIncompatibleLine`/`planningOverlap`, leaving the rejected job unassigned. Locked/completed changes returned protected errors without changing records.
- Existing protected completion work appeared in the ordinary queue. Normal Factory Floor Start returned HTTP 200; its actual status became active without rewriting its planned timestamps. Planning displayed In production. No new Good, Scrap, WIP, Quality determination, receipt or Sales transaction was made by these Planning acceptance steps.
- Source-record drill-through read the original 90/10 evidence and returned to the selected order. Enter/Escape details navigation retained filters. Final EN/AR 390px measurements: document 390px, table 328px, actual chart 980px; no document overflow. Desktop/week view showed real persisted jobs. Final read-only visual checks recorded no page exceptions or failing API responses.
- Scoped shared visual lint recorded no low-contrast or broken-image findings. It flags intentional scroll regions and visually clipped semantic mobile headers (their labels are displayed on every cell). The reused Gantt's compact axis labels are approximately 10.9px and remain a minor readability tradeoff for owner review; there is no claim of a comprehensive accessibility certification.
- **Two independent security checks:** restricted local viewer and owner against a known different local factory. Existing application contract returns HTTP 400 `{error:permissionError}`; direct authenticated Data API/SQL boundary independently returns HTTP 403 / SQLSTATE 42501. All Production/Planning records and revisions were unchanged across denied attempts. Do not relabel the application responses as HTTP 403.
- Tests use disposable PostgreSQL `127.0.0.1:55496`, test-only Auth/Data adapter `127.0.0.1:4304`, application `127.0.0.1:4222`. Original SQL authorization/RLS executes as the authenticated actor. Normal synthetic login is required. This is not hosted Supabase acceptance.
- Shipped public manufactured-output capability remains FALSE; completed-shift late recording remains FALSE/schema 0. Existing disposable helper predicate alone simulates the inactive manufactured workflow for the controlled recovery fixture. No activation setting was changed. All 112 repository migrations are unchanged; Export Reader remains excluded from the executable disposable chain.
- `development` HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, index empty. Earlier dirty work, Design System and Export Reader preserved. Port 4221 and its original process/database remain untouched; no localhost:3000 configuration/process change, hosted access, deployment or Git write.

## Preview, evidence and next gate

Preview: **http://127.0.0.1:4222/**. Factory: **Planning V3 local factory**; primary line: **Printing line**. Normal local owner: `PlanningV3@local.invalid`. Verified synthetic credentials are outside the repository in `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt` (owner-restricted directory).

That runtime directory retains final `focused-final.txt`, `typescript-final.txt`, `build-final.txt`, `acceptance.json`, `security.json`, `visual-final.json`, screenshots and preservation hashes. Intermediate browser harness selector/loading assertions were corrected; committed actions were inspected before continuation. Replanning was re-submitted once during an intermediate harness continuation; it did not change quantities or inventory. Final acceptance is based on actual persisted state, not mocked client success. Do not blindly replay write acceptance against the completed fixture. `tests/planning-v3/visual.mjs` is read-only; preparation requires a fresh, owned disposable root and unused ports.

Changed scope: `src/features/ProductionPlanning.tsx`, `src/app/globals.css`, EN/AR locale files, presentation-only `src/utils/planning-workspace.mjs`, affected `tests/planning.test.mjs`, `tests/planning-workspace.test.mjs`, `tests/planning-v3/{prepare-preview.ps1,fixture.sql,browser.mjs,acceptance.mjs,security.mjs,visual.mjs}`, this report and `HANDOFF.md`. Product differentiators reviewed; no new competitive capability claim is warranted for this scheduling UX change.

**STOP for owner visual approval.** Main localhost:3000 source/runtime/database verification and consolidation, complete diff/history review, and an explicitly scoped GitHub checkpoint remain a separate future authorized task. Overdue unstarted rescheduling remains a separate protected-backend item. No hosted release, activation or broader recovery development is authorized by this milestone.


## 2 November 2026 — consolidated local acceptance fixes
Queue drag start and scheduled-item grab offset now differ correctly; native ghost suppressed, interval/annotation separated, last preview revalidated on drop. Customer deadline recommendation remains protected/advisory with explicit selection and Save, earliest alternative separate, out-of-range timeline check. Country/IANA zone selection and authorized existing settings replace browser-zone guessing. Normal Lock removed, historical Unlock retained; Close and Remove from Schedule labels. Same-scope guidance/status geometry survives polling. See [consolidated report](e2e-acceptance-consolidated-fixes.md) for evidence and limits; owner preview/data preserved.


## 4 November 2026 — isolated 4222 material preparation rollout

The local material preparation, custody/reservation and departmental-update extension is implemented in the isolated4222 source only. Planning warning7h remains separate from preparation6h. Factory time is Asia/Qatar; exact Day/Week occupancy is distinct from short-job captions. Existing stock/Sales/Quality/production permissions and workflows remain protected. Read [the consolidated report](automatic-material-preparation-rollout.md) and [the physical-input/operator guide](production-material-inputs.md) for configuration, migrations, proof and manual acceptance limits. No hosted release or source promotion to3000 is claimed.
