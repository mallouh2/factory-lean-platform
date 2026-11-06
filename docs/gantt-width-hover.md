# Gantt bar width and hover details — 6 November 2026

**IMPLEMENTED AND VERIFIED LOCALLY; owner manual review pending.** Preview: http://127.0.0.1:29511/?view=planning.

## A. Root cause

The owner's observation was correct: stationary PO-0000561 appeared much wider than its seven-minute drag representation. A read-only measurement of that actual order in the review app found a 5.6875px interval/button and duration band, but a permanently visible **168px detached caption**. The caption looked like an extended bar. Text did not change the timestamp-derived interval calculation; the fixed caption caused the misleading stationary appearance. The drag preview also carried a detached caption, creating another overlapping visual layer.

## B. Correction

- `src/features/ProductionPlanning.tsx`: compact real-data details on hover and keyboard focus, rendered outside the scrolling chart. Details include order, product, line, factory-local planned start/finish, human-readable duration and status. Placement is constrained to the viewport. Details clear on blur, pointer departure, scroll, resize, click and drag start. The existing order drawer remains the touch alternative. The scheduled bar's native title was replaced to avoid duplicate tooltips; its full accessible label remains.
- `src/app/globals.css`: hide short-bar captions, contain text within the actual interval, fill that precise interval with the existing color, suppress the detached drag caption and style the compact tooltip. No duration-based minimum width or source-fading behavior added.
- `tests/planning-gantt.test.mjs`: one regression covers 7/15/30/60/180-minute interval geometry and rendered-pixel compact thresholds at half-day/day/week scales.
- This report and `HANDOFF.md`: current evidence and preview pointers.

The existing shared Gantt layout uses actual start/finish timestamps and measured track width. Its compact threshold is 168 rendered pixels, independent of production duration. Drag calculations, snapping, API calls, scheduling validation and persistence are unchanged. Existing table links and keyboard focus provide access when a true interval is extremely narrow; touch users can select the order from the existing list.

## C. Width verification

Actual Chromium/Edge native pointer gestures; desktop 1440px, Day scale, 1171px duration track. Expected = track × minutes / 1440. Browser subpixel rounding is below 0.016px.

| Duration | Expected width (px) | Stationary width (px) | Drag width (px) | Result |
|---|---:|---:|---:|---|
| 7 min | 5.69236 | 5.6875 | 5.6875 | PASS |
| 15 min | 12.19792 | 12.1875 | 12.1875 | PASS |
| 30 min | 24.39583 | 24.390625 | 24.390625 | PASS |
| 60 min | 48.79167 | 48.78125 | 48.78125 | PASS |
| 3 h | 146.375 | 146.375 | 146.375 | PASS |

All five drag measurements used trusted native drag events followed by Escape cancellation, with zero scheduling commands. Separately, actual seven-minute EN/AR drops persisted the preview's exact line/start/finish in the isolated database and retained the same 5.6875px bar after reload.

The stationary matrix contains **52 measured comparisons** across EN/AR, desktop1440/mobile390 and Half-day/Day/Week. Half-day measures the three fixtures in that window; Day and Week measure all five. At 1440px, the seven-minute interval measures 11.375px / 5.6875px / 0.765625px respectively. Every case agrees with its actual track/scale within 0.08px. A separate half-day view confirms that the three-hour bar shows its existing label when adequate pixels are available. Short bars have no visible caption.

PO-0000561 itself was measured read-only before and after updating the review app: interval **5.6875px**, seven minutes; detached caption changed from visible168px to hidden0px. Its saved schedule remains 21:00–21:07 Qatar time.

## D. Tooltip verification

All four EN/AR desktop/mobile layouts pass hover, keyboard focus and viewport-bound measurements. Mobile click opens the existing drawer. Desktop EN and mobile AR screenshots were visually inspected: compact, readable details and correct RTL alignment. Seven-minute scheduled native drags in EN/AR and all five duration drags confirm that the tooltip disappears and the detached drag caption stays hidden. There is no new details modal.

## E. Regression results

- Focused Planning/Gantt: **87/87**.
- Full Node suite: **1490/1490**, zero skipped or failed.
- TypeScript: PASS. Isolated optimized Webpack production build: PASS.
- Native valid seven-minute scheduling: EN/AR persist and reload correctly.
- Native open-ended active-capacity conflict: EN/AR show the localized blocking explanation with no scheduling command or browser error.
- Native EN/AR vertical and horizontal autoscroll, Escape cancellation and unchanged source scheduling: PASS.
- Browser matrix: 52 proportional-width measurements; four hover/focus/mobile layouts; five duration drag comparisons; separate EN/AR tooltip-during-drag checks. No page errors in the final runs.

Earlier exploratory harness failures were retained and corrected: zoom changes preserve the window center, RTL sliders reverse arrow direction, and mobile cases were rerun before the final complete matrix. They are not counted as passing acceptance runs.

Evidence: `C:/Users/Temp/AppData/Local/Temp/FactoryLean-Gantt-Width-4202b482` (`width-browser-results.json`, `native-width-matrix.json`, `native-results.json`, `native-tooltip-results.json`, `native-conflict-after.json`, `scroll-cancel-results.json`, before/after owner measurements, screenshots and check logs).

## F. Safety and environment

Baseline: development / bb0d20e5dd433b896dd319f56e75f0d9eb5d2862, 87 modified tracked paths and 409 untracked status entries. A verified 1310-file pre-edit snapshot is retained under the evidence root. All unrelated baseline files and all 153 migrations remain byte-identical; branch, HEAD and index are unchanged. No commit, push, branch operation, hosted database change, migration, deployment or gate activation occurred.

State-changing browser checks used only the independently verified disposable loopback PostgreSQL29549 / adapter29550 / app29551, copied synthetic data and existing test accounts. No worker was started. Its local Auth/Data adapter is not hosted Supabase Auth/PostgREST, so these results are local acceptance evidence. Task-only services were stopped after verification; evidence/data retained.

The existing review app29511 retains its synthetic database29509 and adapter29510. Only the tested Gantt component and stylesheet were copied into its app after both target files matched the pre-edit hashes; originals were preserved. The read-only actual-order measurement confirmed the update. All release gates remain off. Existing owner4222, reference4242,3000, donors and prior preservation snapshots were not modified.
