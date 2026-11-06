# Production completion and recording — 31 October 2026

1 November follow-up: [direct recording and missing-work verification](production-recording-selection.md) adds an exact-item Floor Record action, current-list refresh and a single protected shift explanation. Shift/recent supporting details are now collapsed; the older screenshots below capture the prior visual iteration. Recording/finish/Quality/receipt contracts and gates remain unchanged.

**COMPLETE / LOCAL VERIFIED. Owner manual approval pending.** This is a focused Factory Floor/Recording V3 improvement, not a release or activation certificate.

## Operational change

Previously, Factory Floor End Production immediately invoked `finish_product_item`; recording was a separate task, including eligible same-shift recording after completion. End now opens the existing Recording V3 modal for that exact item. The operator reviews actual quantities, edits the suggestion, then selects **Save Production & End Execution**. Only a confirmed protected recording receipt permits the subsequent existing protected finish command. Ordinary recording uses **Save Production** and never ends execution. Cancel performs neither write.

This follows the bounded operator pattern documented by [MRPeasy's My Production Plan](https://www.mrpeasy.com/resources/user-manual/reporting/my-production-plan/details/), which asks for actual quantities when pausing/finishing. It is workflow parity, not evidence of unique differentiation or measured training savings. Existing design tokens/components, progressive detail and EN/AR terminology are reused. `PRODUCT_DIFFERENTIATORS.md` was reviewed; no material competitive-position change is claimed.

The identity shows Product, Production Order, line and authoritative work type, followed by compact **Requested / Already Recorded / Remaining** quantities with units. Scrap remains KG and is never subtracted from meters/pieces. The new read-only authenticated point API uses RLS and Orders view permission, exact factory/item filters and private/no-store responses. Database numeric tokens are preserved before JSON number parsing. It reads the existing entry/correction-maintained gross `production_orders.good_quantity`, not accepted production, fulfillment or Warehouse stock. `remaining = max(target_quantity - good_quantity, 0)` uses exact decimal arithmetic. No new aggregate ledger exists.

Only End entry initially suggests remaining. Existing nonempty drafts and operator edits take precedence; background reads never reset the suggestion, draft, focus or dialog. Confirmed finish clears its unsaved suggestion so it cannot become a later ordinary recording default. Existing excess-output confirmation/allowances remain authoritative. Zero remaining does not create a zero entry. **End Without New Recording** requires explicit confirmation, calls only protected finish and retains the shortage.

## Transaction and retry boundaries

Recording and finish remain **two existing protected transactions**, not a new combined atomic SQL writer. The original immutable recording UUID/body is retained before submission, with additive completion-purpose metadata bound to the item and actual execution start (including microseconds). A rejection leaves execution active. An uncertain response keeps existing Check/Retry recovery; it cannot be replaced with another payload or repurposed as an ordinary recording.

After confirmed recording but failed finish, the result explicitly says output was saved and execution still needs ending. **Retry End Execution** reads the same execution and invokes finish only; it never posts output again. Reload preserves that recovery. If finish committed but its response was lost, authoritative completed state resolves success without another recording. A different execution start, denied read or unknown state fails closed. Existing SQL permissions/state/locks and current-shift deadlines remain decisive. No automatic machine state, transfer, Planning timestamp, Sales demand or allowance change was introduced. Integrated End requires the existing recording view/edit permissions; edit-only users receive a disabled explanatory control rather than a dead button.

## Proven metadata defect and justified forward migration

Source-linked replacement/completion jobs can have public request type `INTERNAL_PRODUCTION` and null older rejection linkage columns. Using that public header alone incorrectly described replacement as stock work. Existing `private.manufactured_completion_work.choice` is authoritative.

New local forward migration **`20261031202858_production_recording_work_kind_v3.sql`** adds nullable `work_kind` to the existing protected `manufactured_output_read(...,'options',...)` response. It reuses that reader's factory authorization, activation, security/search path and grants; guarded definition replacement stops if the expected contract differs. No table, business writer, permission, gate or new RPC was added. Old consumers ignore the additive field. Matching new UI fails closed for malformed available options. The request type used for ordinary work is independently read through the bounded RLS point query, not inferred from a truncated snapshot.

The migration was applied only to the verified disposable QA clone and existing local owner preview. Before/after reader ACL and hashes of recording, finish and activation functions are identical. All **135 pre-task migration file hashes remain unchanged; 136 local files** now exist. No hosted history/alignment claim is made.

## Focused acceptance evidence

All write scenarios used independently verified loopback PostgreSQL **55500**, database `factory_lean_quality_local`, dedicated disposable data directory; Auth adapter **4322**, matching full application **4238**. Existing copied accounts and direct/package assignments were retained. No users or passwords were created/reset. The clone's obsolete operational shift data was discarded once to establish fresh protected current-shift fixtures; identity/permission dependencies were checked first. This reset was confined to that clone, never the original owner database. No authorization or shift guard was bypassed.

| Scenario | Actual result |
|---|---|
| Normal Sales-linked job, requested6m / recorded2m | Suggested4 editable to3. Gross2→5, entries1→2, Scrap0→0.25KG, completed, remaining1. Saved Planning times unchanged. |
| No new output | Gross2 and entry count unchanged; execution completed; shortage4 retained. Separate zero-remaining case creates no zero entry. |
| Cancel | No entry/status change. |
| Protected overproduction rejection | 1000m rejected; active/gross2 unchanged; draft1000 retained for review. |
| Recording commits, finish fails | Injected pre-command503 after valid3m recording: gross5, one new entry, still active. Reload/status recovery followed by finish-only retry completes; no duplicate entry. |
| Internal stock | Requested6, gross2→6; correct stock work label; no original customer demand altered. |
| Replacement | Own target5, gross0→3; origin demand100 unchanged; authoritative replacement label. |
| Unfinished completion | Own target4, gross0→4; issued source input4 consumed exactly once, lot available0; origin target909 unchanged; completion label. |
| Completed same-shift ordinary recording | Gross2→3 with existing actual_finish unchanged; Save only, no End action. |
| UUID replay/concurrency | Two simultaneous exact-UUID recording replays return200/200 without extra entries; unfinished consumption remains4 even after Quality/receipt. Lost-finish-response reconciliation also has a focused client regression. |
| Permissions/factory isolation | Restricted summary403, finish400 under existing RPC error mapping, recording403; known foreign-factory summary/recording403. Before/after operational state unchanged. Eight account/membership/direct/package table digests unchanged. |

The actual protected handoff was exercised for normal, stock, replacement and completion output. Unapproved receipt returned **422 / `output_quality_required`**. Quality approval returned200. For normal output, the new3m declaration became2m accepted +1m rejected with separately measured0.5KG Quality Scrap: recorded gross remained5m. Concurrent same-UUID eligible Warehouse receipts returned200/200 with exactly one credit. New-product stock changed **0→2m normal, 0→4m stock, 0→3m replacement, 0→4m completion**. No output/Quality/receipt entitlement was created by End Without New Recording. No Warehouse bypass was reproduced in this manufactured-output path.

**Boundary:** these manufactured-path tests use the inherited disposable private test predicate, unchanged by this task. The shipped manufactured-output capability remains FALSE; inactive legacy immediate-credit behavior is intentionally unchanged. This does not certify an activated accounting cutover. Local tests use real protected PostgreSQL/RLS behind the existing local Auth/Data adapter; they are not hosted Supabase GoTrue/PostgREST acceptance.

## Automated and visual verification

- **106/106 focused Node tests PASS:** completion summary/API/recovery, existing Recording UI, same-shift/shift-work/late-recording and manufactured-output Phases2–4 utility regressions. Final permission-control/translation regression also passed after the small final UI change.
- TypeScript **PASS**. Exact-source isolated optimized Next/webpack production build **PASS**. One mistakenly started repository-root build was cancelled; its ignored generated output was not staged or committed. Final verification uses the isolated loopback-configured build.
- Fourteen operational browser scenarios PASS, plus final work-type and no-record-draft cleanup checks. Evidence retains actual HTTP responses, before/after rows, source consumption, receipts and UUIDs; successful writes are not rerun by the recovery harness.
- EN1440/768/390 and AR390 screenshots inspected. Compact typed summary, all inputs reachable above sticky footer, no page overflow. Narrow footer puts primary action on its own full-width row, avoiding compressed Arabic text.
- Two actual30s refresh cycles in desktop English and mobile Arabic: dialog/input node identity, focus, drafts1.5m/0.125KG, scroll, dimensions and summary remain stable; data/summary requests200. No business POST during visual checks. Shared visual lint found only the intended vertically scrolling dialog body.
- Original owner preview normal login/read-only smoke PASS: no business POST, no browser error; summary API200. Both shipped gates FALSE.

## Existing owner data and manual preview

Read-only **PO-0000050** (`eb9b400c-ec89-43e5-b073-fa23fef87bf6`) was already completed before this task: target6m, gross recorded0, accepted0, zero entries, remaining6m. Actual start `2026-10-31T12:08:32.51513+00:00`, finish `12:08:56.509857+00:00`; saved06:58–06:59UTC plan unchanged. No recording, completion replay, Quality or stock fix was applied to this order. Its state supports the missed-recording observation, not a proven Warehouse bypass. Eligibility to add output still depends on the existing open-shift contract; no historical shift is reopened for review.

Main preview: **http://127.0.0.1:4222/?view=lines**, matching `production-end-app` in the existing owner runtime. Owner `PlanningV3@local.invalid`; verified unchanged credentials file:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.
The original DB55496/Auth4304 remain running. Their stopped processes were normally resumed earlier during the task; credentials/data were not reset. Refresh/sign in normally if an old browser session expired.

Separate manual fixture: **http://127.0.0.1:4238/?view=lines**, line **End recording manual**, order **PO-0001078**, item `a24eae3b-2689-4ce5-b644-d2e119d6c8f4`: active requested6 / recorded2 / remaining4m. Select End Production, inspect/edit the suggestion, or Cancel. This fixture has not been ended by acceptance automation. Use only that preview's existing credentials in:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Production-End-65b76ac01c494ac6b7b57f99886b9f6f\LOCAL-LOGIN.txt`.
Do not mix the two local factories. Current-shift fixture expires normally; no late-recording activation was enabled.

## Exact incremental file manifest

Existing modified files:

- `src/features/FactoryFloorV2.tsx`
- `src/features/ProductionRecordingV3.tsx`
- `src/features/production-recording-v3.css`
- `src/services/production-recording-client.ts`
- `src/utils/production-recording-intent.mjs`
- `src/locales/en.json`, `src/locales/ar.json`
- `tests/production-recording-ui.test.mjs`
- `docs/production-recording-v3-same-shift.md`, `HANDOFF.md`

New files:

- `src/app/api/production-completion/route.ts`
- `src/services/production-completion-client.ts`
- `src/utils/production-completion.mjs`
- `supabase/migrations/20261031202858_production_recording_work_kind_v3.sql`
- `tests/production-completion.test.mjs`
- `tests/production-end-recording/prepare-local.ps1`
- `tests/production-end-recording/fixture.sql`, `fixture.mjs`, `manual-local.mjs`
- `tests/production-end-recording/install-local.mjs`
- `tests/production-end-recording/browser.mjs`, `final-browser.mjs`, `visual.mjs`, `owner-readonly.mjs`, `verify.mjs`
- `docs/production-recording-completion-ux.md`

No package/dependency/configuration changes. Test scripts contain no credentials; only verified local credentials-file paths. Existing correction/void and quantity writers are reused, not rewritten. Product recipes, Sales entitlements, completed-shift policy and all unrelated Phase4 gaps remain outside scope.

## Evidence and preservation

QA evidence root:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Production-End-65b76ac01c494ac6b7b57f99886b9f6f`.
`browser.json`, `verification.json`, `reader-install.json`, `final-browser.json`, `visual.json`, `fixtures.json` preserve scoped results/IDs. Screenshots: `modal-1440-en-top.png`, `modal-768-en-fields.png`, `modal-390-en-fields.png`, `modal-390-ar-stable.png`, `end-finish-pending.png`, `type-replacement.png`, `type-completion.png`.

Owner runtime `production-end-recording/` contains before/preservation evidence, owner read smoke and reader-install security comparison. **118 original public-table digests and credential-file hashes unchanged**. All135 historical migrations, Export Reader, Design System, prior Gantt/refresh/navigation work and unrelated dirty files preserved. Source-matched isolated bundle; development HEAD `bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, index empty. No hosted environment, deployment, Git write, localhost3000 or unrelated-preview mutation. Both shipped activation gates FALSE; inherited disposable predicate unchanged. Stop for owner manual review; no automatic checkpoint or next task.
