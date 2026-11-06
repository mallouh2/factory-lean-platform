# Quality inspection follow-up placement —1 November2026

Locally verified UI refinement: optional Production follow-up now belongs inside the selected inspection/unchanged-approval confirmation. Existing actor-bound UUID command, output/entry/item links, immutable NEEDS_ACTION→IN_PROGRESS→RESOLVED lifecycle and independent stock/quantity status are unchanged. Fresh98m unchanged approval+follow-up, concurrent Quality retries, drawer opening and actual1m receipt were verified: one FINDING, still NEEDS_ACTION, no rejection/WIP/replacement, one physical credit. Exact scope, quantity/weight UI and evidence: [Quality V2 final report](quality-inspection-v2-final.md). No hosted activation or release.

# Automatic compensation and separate stock requirements —31 October2026

**COMPLETE locally; owner manual review pending.** This supersedes the earlier documented stock-request integration gap for ordinary compensation. It does not replace the original replacement, allocation-revision, receiving or production contracts.

## Behavior and protected boundary

One **Total Quantity to Produce / إجمالي الكمية المطلوب إنتاجها** input previews rejected replacement first, unfinished replacement second, extra stock last. Exact decimal strings are preserved through UI/API; SQL numeric recalculates inside the transaction. The protected reader supplies currently eligible rejection/unfinished quantities, not notification prose. For eligible2+4, totals2/5/6/8 split2/0/0,2/3/0,2/4/0,2/4/2. A5 total warns that1 remains, without disabling Confirm. Existing allocations reduce eligibility; a stored partial5 replacement retains all4 physical units with only1 original-demand entitlement unassigned. An allocation decision is not physical production, Scrap, consumption or Warehouse credit.

One new forward migration: `20261031090000_quality_production_distribution_v1.sql` (SHA256 c6b19712306c3326610cc1c24e0044941ba4c6b048054dab4b38f957663f4861). New protected `plan_quality_production` takes factory/target/payload/expected_revision/request_id. It preserves factory→fulfillment→structure lock order and rechecks effective authorization, source revision and activation. It calls existing `plan_production_compensation` for only the eligible replacement; any excess calls existing `create_production_request` for separate INTERNAL_PRODUCTION, normal priority, no line/schedule/actual execution and no original-demand fulfillment allocation. Existing active/ended and Planning fallback guards apply only to the replacement portion. The stock work follows the ordinary Planning/Production/Quality/receipt workflow; this task did not execute that whole lifecycle.

Both portions and one private immutable actor/UUID decision receipt commit together. Failed stock creation rolls back replacement, source dispositions and receipt. Exact retries recover the saved combined result; conflicting payload/actor or unrelated existing UUID is rejected. Receipt evidence retains the authoritative Quality finding/revision, source item/unit, actor/server time and separate work IDs. No client actor/provenance, new ledger, permission grant or unrestricted stock credit. New table has RLS, no direct authenticated/service-role grants; private helper is revoked. Existing command/API stays available for pending earlier retries and explicit allowance transfers. Source/Quality holds, issued/started/committed work, required exceptional revision reasons and stale-source rejection remain real blockers. Ordinary compensation has no typed reason.

The reader adds protected distribution and separate stock work metadata without changing its existing capacity/fallback/decisions. The drawer retains real completion/replacement cards and shows real extra-stock order reference/quantity/status separately. Extra stock is never included in original shortage coverage. Quality followup status stays independent; opening/refreshing/creating work does not resolve it. The dropdown is replaced by four wrapping pressed-state buttons: Open(default), Needs Action, In Progress, Resolved, with concise Arabic equivalents. Existing server filters/global outstanding count remain authoritative.

## Verification and limitations

- **27 new standalone PostgreSQL assertions +12 expected rejections PASS**, all scenario tests roll back: requested splits, decimals, real Piece fixture through recording/Quality/request (fractional Piece rejected), partial stored entitlement, existing issued completion excluded, immutable UUID receipt, permissions/cross-factory/stale/hold guards, no fabricated lot/stock, atomic injected failure. Existing **15 assertions +7 negatives PASS**, including legitimate reasoned supersession, issued/hold blocking, partial physical receiving and immutable prior evidence.
- **Three real transaction races PASS**, lock waits observed: same UUID, competing allocations, receipt versus replacement. One6 entitlement/one4 release/one2 stock requirement, no fabricated receipt; exact replay returns the receipt and stale competitor fails. These are concurrent transactions, not a claim of two manager browser logins.
- **25 focused Node tests PASS**, TypeScript PASS, exact-source isolated optimized webpack build PASS. New API tests cover one total payload and origin rejection. Existing React state/retry pattern and CSS architecture reused; status buttons have accessible pressed/group semantics and wrap at390. Token colors include text labels, not color-only meaning.
- Actual separate-fixture browser **active5** HTTP200→2 rejected/3 unfinished/remaining1, original target909; **ended8** HTTP200→6 linked replacement +2 separate Planning stock; exact replay200 once, restricted write403. Four actual server filters and EN/AR390 screenshots PASS. Initial harness failures were exact accessible button-name and Meter label assumptions; corrected tests only, no business bypass or blind resubmission.
- Owner normal-login read-only smoke4222 PASS: existing903/4/2/default6, live8 split2/4/2, partial5 warning/Confirm enabled, audit/equipment, full reload/navigation/Refresh recovery, two unchanged current followups. No owner business POSTs/compensation decisions. All117 prior table digests unchanged during schema installation and owner smoke; later118-table read smoke unchanged. All132 prior migration hashes, owner credentials and eight QA identity/permission table digests unchanged. Both shipped gates FALSE; inherited disposable helper unchanged. Local standalone PostgreSQL/Auth adapter evidence only; no hosted acceptance.

**Explicit limits:** moving an ended active allowance remains the existing exceptional transfer with recording-complete confirmation and capped quantity; it is not silently reclassified as a new total request. No stock-only creation from a fully covered/blocked Quality record: use the existing internal-production workflow. No change to protected cancellation, no automatic receiving/fulfillment, no additional-stock execution acceptance claim. Normal independent stock scheduling still requires Planning.

**Preview:** http://127.0.0.1:4222/?view=lines, matching external `allocation-app`. Existing owner `PlanningV3@local.invalid`; unchanged owner-only credentials at `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`. Evidence under that root/allocation (owner-install.json,owner-preview.json,screenshots,audit.json); separate FactoryLean-Compensation-Fix-44983c02-abe2-414a-8608-f3e1dd7b74d9 root contains allocation-browser.json,allocation-concurrency.json and EN/AR screenshots. Main55496/4304/4222 retained; temporary QA55499/4320/4236 stopped after tests, data preserved. No hosted/deployment/activation/Git/3000 operations. The obsolete adapter fix remains intact.

## Incremental file manifest

Migration above; `src/utils/quality-production-distribution.mjs`; `src/features/ProductionQualityCompletion.tsx`; `src/features/ProductionQualityActions.tsx`; `src/features/quality-updates.css`; `src/app/api/manufactured-output/route.ts`; `tests/production-compensation-api.test.mjs`; `tests/quality-production-allocation.test.mjs`; `tests/quality-production-allocation.sql`; `tests/quality-production-allocation-concurrency.mjs`; `tests/quality-production-allocation-browser.mjs`; `tests/quality-production-allocation-install-local.mjs`; `tests/quality-production-allocation-owner.mjs`; this report; `HANDOFF.md`; `docs/PRODUCT_DIFFERENTIATORS.md` (factual parity update). External runtime.json points to the matching allocation-app; no credential/env changes. STOP for owner review.

# Quality Updates loading failure —31 October2026

**COMPLETE locally.** Actual fresh-owner reproduction: `/api/data`200, `/api/production-quality?factory=3ab24bb6-654e-40ab-a8bd-e0c8ca5c62c8`403 with `permissionError`; local adapter log42501 `Local fixture RPC not allowed`. The previously copied preview-root backend.mjs predates the followup/compensation contracts and was accidentally used during server restoration. Its static allowlist rejected the protected reader. Factory credentials, actual SQL permissions, schema and latest compensation source were valid. The empty drawer consequently showed its existing data warning and loading placeholder. Separately, pre-restart browser sessions cannot refresh against the adapter's new in-memory session map (401 user validation/400 refresh); a normal login succeeds, without resets.

## Repair and restart contract

- Restore the existing **tests/production-recording-full-app/backend.mjs** service on4304 with the same runtime.json. It discovers only public functions granted to authenticated and retains real actor-scoped SQL/RLS authorization. No private functions or universal access were exposed.
- External root/backend.mjs is now a guarded delegating entry point, not an obsolete protocol copy. It requires the existing disposable marker, loopback endpoint and saved credentials. The previous file is preserved under compensation-fix/obsolete-backend-before-loading-fix.mjs.
- Preview root: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2`. Existing owner credential file: `LOCAL-LOGIN.txt`; never copy its contents into documentation. App compensation-fix-app4222 / Auth4304 / PostgreSQL55496 are running. No other preview was restarted.
- To start the adapter from that root: `node backend.mjs runtime.json`. Keep it running with the matching existing app and database. After restarting Auth, use normal sign-in if a browser holds a previous session. Session persistence is not implemented by this disposable adapter; no authentication bypass was added.

## Actual verification

`node tests/quality-loading-preview.mjs` PASS: normal existing-owner login; active factory snapshot200; fresh current followups200; two outstanding records (PO36 In Progress, PO32 Needs Action); details and quantities; reload; navigation away/back; English/Arabic RTL390 screenshots inspected. Existing Refresh is only visible after an error: one explicitly intercepted503 tests recovery, then real backend200 supplies the rows. No cached-success substitution. Known second-factory followups403/no rows; restricted user's actual Quality inspection read403/no rows. That user's permitted Orders followup read correctly remains200; it is not incorrectly classified as a denial requirement.

`node tests/quality-compensation-owner-preview.mjs` PASS: actual owner909/903/4/2 drawer, six-meter ordinary replacement default, protected action record/equipment navigation; zero business POSTs/decisions. All117 public/private/auth table digests unchanged. Both shipped gates FALSE.16 focused Node API tests PASS. First expanded harness incorrectly assumed a successful-state Refresh button and restricted Orders read403; corrected only those test expectations to the actual existing UI/permissions. No business behavior weakened.

Evidence in preview-root/loading-fix/browser.json, details.png, en390.png, ar390.png. Source changes limited to the read-only browser regression and these documentation/HANDOFF notes; runtime wrapper changed outside Git. No application source/migration changes, so TypeScript/build were not rerun. No hosted access/deployment/Git write, no owner operational transactions, no permission/password changes. Existing132 migrations/Export Reader/Design System and unrelated dirty work preserved. Owner manual review can resume at http://127.0.0.1:4222/?view=lines; sign in normally if needed. STOP.

# Compensation drawer correction — 2 m / 6 m eligibility and ordinary form

29 October 2026 — **COMPLETE locally; owner manual review pending.** The approved visual direction is retained. This supersedes the eligibility explanation and ordinary replacement form in the preceding drawer report.

## Confirmed root cause on the owner's actual record (read only)

PO-0000036 / output3ec93374-3a02-4f39-b241-18cf99538bb2: original909m; applied Quality revision2:903 finished,4 recoverable unfinished,2 rejected; output revision3. No completion/replacement work, no unfinished lot mapping, no Quality hold. The4m had **not been received into Warehouse**. The earlier private.production_compensation_state summed unfinished entitlement only through received lot rows, yielding unfinished_unassigned0 and available2. This was a backend receiving/entitlement coupling, not hidden completion work or a frontend numeric-input maximum.

## Minimal protected fix

One forward migration: **20261029123000_quality_compensation_entitlement_v1.sql**. All131 previous migration files remain unchanged.

- Source eligibility now reads authoritative reviewed unfinished groups and their existing live DISPOSITION usage, independently of whether Warehouse has created a lot. Existing accepted/pending/baseline/assigned-work coverage, physical holds and source-revision checks still cap the result.
- Reuses the existing protected DISPOSITION branch, which already supports an unfinished group before receiving. production_compensation_releases may reference the immutable source group before a lot exists; its key is factory/decision/group. This records demand entitlement only. It creates no lot, issue, consumption, Scrap, Warehouse receipt or finished credit.
- After an actual receipt creates the lot, existing output_work_allocations resolves that release by factory/output/group. The same four units cannot also complete original demand; independent stock-only recovery still requires physically received/issued material. Partial receiving2+2 was verified: the first lot contains exactly2 physical/stored units, while the separate original group entitlement4 is already released; after the second receipt physical/stored4 and one released entitlement4 remain. No physical quantity is inferred from entitlement.
- Ordinary replacement omits a typed reason. After actor-bound replay and source-revision checks, SQL derives an auditable reason from the authoritative Quality finding and original order. Immutable intent evidence retains Quality event UUID/revision, documented reason, group classifications/rejected quantity, original reference, decision type and reason origin. Existing columns retain actor/server time/quantity/mode/UUID. Client-supplied provenance is not accepted. Old nonempty-reason calls and exact receipts remain compatible; later Quality wording never rewrites saved evidence or changes an exact UUID replay.
- Active allowance, ended HIGH unscheduled replacement, capacity/shift/ownership checks and physical receiving are reused. No production recording, inventory or general Planning writer was rebuilt.

## Focused UI correction

Ordinary replacement is **one quantity input**, prefilled from the protected eligible amount, a short execution-path hint, Confirm Replacement and Cancel. Removed the duplicated form statistics and manual reason field. Removed the empty zero-work quantity grid. The top original/accepted/unfinished/rejected cards remain. No additional-stock control is presented as functional.

Real linked work stays visible. A wholly unissued/unstarted eligible COMPLETE card offers **Change to replacement**: an explicit exceptional confirmation with its required revision reason, calling existing revise_manufactured_completion CHANGE/REPLACE. Existing schedule/state/revision fingerprint, Warehouse authority and irreversible-state checks remain intact; this does not silently cancel anything. Issued/started/committed/locked/held cases retain their exact blockers. The old work is retained as retired history and the linked replacement appears immediately.

## Current evidence

- **15 focused standalone PostgreSQL assertions +7 expected rejections PASS**: unreceived6 eligibility, partial active3, original target/execution protection, server-derived evidence, actor/UUID conflict, replay after later review, later partial receiving and stock-only ownership, eligible supersession, issued source and Quality hold. All test scenario transactions roll back.
- **Three real concurrency groups PASS**, observed lock waits: same UUID; competing allocation UUIDs; receiving racing replacement. One6m entitlement/one4m release, no fabricated lot; the stale competitor is rejected. These are two protected database transactions, not mocked concurrency or a claim of two different authorized manager logins.
- **28 focused Node tests PASS**, including omitted ordinary reason forwarding and existing compensation/permission/drill-through/follow-up regressions. TypeScript and exact-source isolated optimized webpack production build PASS.
- Authenticated local browser: active6 **200** on original job; ended6 **200** as separate HIGH unscheduled work; both exact UUID replays **200**, one decision each. Confirmed no typed reason in request, genuine server Quality provenance, no fake lot/stock and original target909 unchanged. Actual protected CHANGE4 **200**, old completion retired and stored4 unchanged; issued4 has a precise blocker and no Change action. Separate existing restricted login **403**.
- Actual desktop / EN390 / Arabic RTL390 screenshots inspected: one ordinary input, no repeated statistics/reason, clear disabled7 versus eligible6, no document overflow or clipped Arabic controls. The preceding keyboard/native-dialog and visual-token behavior is retained.
- Tested schema installed **only on verified disposable owner55496** after isolated acceptance. **All117 existing public/private/auth table digests, credentials and local predicate preserved**. PO-0000036 now reads available6 / unassigned unfinished4, with no owner decision submitted. Matching owner4222 normal-login read smoke confirms one input/default6/no reason; zero business POSTs/page errors; data digests remain identical. Both shipped activation gates FALSE.

Write acceptance used a new, independently verified disposable loopback copy55499/4320/4236. Obsolete business fixtures were discarded only in that copy; all8 identity/membership/permission table digests and existing credentials were retained. A genuinely current shift was configured before production (five-second setup lead; authoritative occurrence verified), with no backdating or late activation. The older isolated QA factory was between verified shifts; its real readiness fence was not bypassed. Resolved harness issues (cold compilation wait, bounded code length, ambiguous test query, and consistent identity for partial receiving) did not cause blind resubmission of a committed request: the saved UUID response was recovered/replayed.

This is standalone PostgreSQL with the established local Auth/Data adapter, not hosted Supabase acceptance. Existing irreversible/cancellation limitations remain protected; no broad business-data cleanup or historical migration repair was implemented.

## Exact incremental manifest

- supabase/migrations/20261029123000_quality_compensation_entitlement_v1.sql (new)
- src/features/ProductionQualityCompletion.tsx
- src/features/quality-updates.css
- tests/production-compensation-api.test.mjs
- tests/quality-compensation-fixture.sql (new; existing identities and protected fixture operations)
- tests/quality-compensation-eligibility.sql (new)
- tests/quality-compensation-concurrency.mjs (new)
- tests/quality-compensation-browser.mjs (new)
- tests/quality-compensation-install-local.mjs (new)
- tests/quality-compensation-owner-preview.mjs (new)
- docs/production-quality-corrective-actions.md
- HANDOFF.md

Optional extra stock production remains a separate future integration: the generic internal-request command exists but has no UUID receipt/recovery argument. No stock-only quantity is merged into customer-demand replacement, and no new request subsystem was built.

Evidence: main runtime compensation-fix (owner-diagnosis.json, owner-install.json, owner-preview.json, owner-form-six.png, build.txt, typescript.txt); fresh copy C:\Users\Temp\AppData\Local\Temp\FactoryLean-Compensation-Fix-44983c02-abe2-414a-8608-f3e1dd7b74d9 (sql-results.txt, concurrency.json, browser.json, form-desktop.png, form-en390.png, form-ar390.png). The listed verification artifacts contain no passwords/tokens; runtime credentials remain outside Git.

Preview **http://127.0.0.1:4222/?view=lines**, matching compensation-fix-app. Existing PlanningV3@local.invalid, unchanged restricted credentials at C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt. Open Quality Updates → PO-0000036 → Produce Replacement Quantity. Inspect default6 and the short form; no owner replacement has been submitted automatically.

**LOCAL ONLY.**132 local migration files/all131 prior hashes preserved. No hosted access/deployment/activation/Git writes,3000 or unrelated-preview changes. Existing owner records, active business workflows, Export Reader, Design System and unrelated dirty work preserved. STOP for owner review.

---

# Quality Updates drawer — simplified operational detail

29 October 2026 — **COMPLETE locally; owner visual/manual approval pending.** This delivery changes only the Floor Quality detail and its confirmation/record views. The compensation implementation and earlier evidence below remain intact.

## Result and design decisions

The ordinary detail now answers: **What did Quality find? What work exists? What can Production do next?** Four typed outcome quantities use the existing Inter/IBM Plex Sans Arabic, 28px quantity text and approved neutral/success/warning/error tokens with explicit labels. Measured rejected KG remains separate. Findings, unfinished-operation names, group notes and requested process actions retain their distinct meanings. No invented quantities, raw identifiers, accounting classifications or long explanatory panels.

Existing work appears before new actions, with actual source-bound order code, type, quantity and state. Scheduled work is distinguished from waiting for Planning, active execution, Quality hold, cancellation and receipt still pending. Execution completion is never displayed as physical receipt. Same-job allowances show the original order and recorded/unused quantities; transferred allowance is not counted twice. Cancelled/superseded and stock-only work are excluded from current demand coverage. Source/context pagination is read fully; matching never uses product names.

Original Quality shortfall, completion work, replacement work and availability for new work remain separate. In the verified 903/4/2 case, completion4 leaves a visible original shortfall6 and only2 available for new work. No duplicate Complete action is offered. Existing Details opens the exact protected Planning source/work, including its authorized revision/cancellation controls; the drawer does not perform a cancellation or bypass issued/started/committed/locked work. Missing stored input directs the employee to Warehouse receipt/allocation/hold prerequisites.

Complete and Replacement are direct contextual actions, opening one short form with quantity, purpose, reason and consequence. Exact decimal strings, effective permissions, source revision, actor-bound UUID storage and same-request retries remain in place. Successful creation closes the form and refreshes work immediately. Start Handling remains available without a needless explanation field; Mark Resolved still requires the actual action taken and server eligibility. Opening the drawer never resolves anything. History is removed from the ordinary detail but remains accessible through an on-demand **View action record** using the same protected evidence and existing Dialog; the production/Quality record is reachable there. Native dialog keyboard/Escape and Cancel focus restoration are retained.

Comparable workflow references were reviewed: [Tulip's focused operator tasks](https://support.tulip.co/docs/work-instructions-apps-overview) and [MRPeasy's distinction between inspection and rework](https://www.mrpeasy.com/demo-videos/quality-control/). Adapted task/result/action hierarchy only; Factory Lean's manufactured-only Quality and actual-receiving contracts remain unchanged. Permanent visual-craft guidance was added to UX_SIMPLICITY_STANDARD, without changing or approving the separate Design System document.

## Functional verification (new local fixtures only)

- Normal existing QA owner login, new COMPLETE4 through the real drawer: HTTP200, real order reference/status appears immediately; duplicate action disappears.
- Fresh authoritative revision: duplicate COMPLETE4 **422**, and replacement6 while completion4 remains allocated **422**. Work/output/stock/follow-up counts unchanged. Earlier stale-revision retry independently returned409. No cancellation or redistribution was attempted to force success.
- Active REPLACE2 through the drawer: **200**, same original target909/execution, no new replacement Planning job. Ended rejected-only REPLACE5: **200**, distinct unscheduled linked work; no fictional unfinished lot.
- Exact prior completion UUID replay **200**, no extra work. Existing restricted account write **403** and known foreign-factory read **403**, no unauthorized effects.
- Unchanged accepted100 with explicit printer observation: no fictional shortage/action; actual START **200** and reasoned RESOLVE **200**. No inventory movement was caused by these follow-up actions.
- **27/27 focused Node tests PASS** (five new presentation regressions plus existing compensation/API/drill-through/follow-up tests). Includes exact decimal arithmetic, exclusive coverage, transfer non-duplication, cancelled work and unknown/partial receipt presentation.
- **TypeScript and isolated optimized webpack production build PASS** for the matching source. Default Turbopack cannot resolve the external dependency junction in this isolated temporary copy; webpack succeeded without dependency/configuration changes in the repository. An initial QA-only origin mismatch was corrected in its temporary environment file before authentication/write acceptance; no production authorization was weakened.
- Authenticated rendered screenshots inspected at desktop1440, intermediate768 and mobile390, EN/AR RTL; prominent numbers, semantic contrast, wrapping, direct forms, Details navigation and keyboard behavior verified. Shared visual lint reported only the intentional single drawer scroller and screen-reader-only order label, no actionable clipping/tiny-text/contrast findings. The operational dialog uses its supported light surface. No global operational dark theme is introduced or claimed tested.
- Final actual owner4222 read-only smoke: normal login, drawer/record view, Arabic390 and equipment navigation PASS; **all114 pre-existing table digests unchanged**, zero business POSTs/page errors and zero owner compensation decisions. Existing manual records, credentials/grants and sessions preserved. Separate local55498 fixtures used existing identities; no account/grant changes.

Evidence: main runtime quality-drawer (node.txt, typescript.txt, build.txt, owner-preview.json/screenshots); separate SQL runtime quality-drawer (acceptance.json, visual.json, EN1440/768/390 and AR390 screenshots). QA auth/application ports4319/4235; main55496/4304/4222 retained.

## Optional stock production and limits

Additional stock is **not created in this drawer**. The existing generic create_production_request makes separate INTERNAL_PRODUCTION through the normal order workflow, but its six-argument contract has no UUID receipt/recovery field and the compensation command only authorizes original-demand entitlement. Adding it here would need a separate retry-safe stock-request integration; it is not silently included in replacement quantities or claimed verified. No broad backend extension was made. Existing protected cancellation/revision limitations and physical/shift/Quality holds remain; the drawer links to Details rather than inventing overrides.

## Exact incremental files

- src/features/ProductionQualityActions.tsx
- src/features/ProductionQualityCompletion.tsx
- src/features/quality-updates.css (new)
- src/utils/quality-update-summary.mjs (new; presentation only)
- src/app/layout.tsx (scoped stylesheet import)
- tests/quality-update-summary.test.mjs (new)
- tests/quality-updates-browser.mjs (new)
- tests/quality-updates-visual.mjs (new)
- tests/quality-updates-owner-preview.mjs (new)
- docs/design/UX_SIMPLICITY_STANDARD.md
- docs/production-quality-corrective-actions.md
- HANDOFF.md

**No migration. All131 pre-task migration bytes, business writers, API authorization, active stock paths, Export Reader, Design System and unrelated dirty work are preserved.** Both shipped gates remain FALSE; existing disposable helper simulation is unchanged. No hosted access, deployment, activation or Git writes. Localhost3000 and unrelated previews unchanged.

Preview: **http://127.0.0.1:4222/?view=lines**. Existing PlanningV3@local.invalid; unchanged owner-only credentials at C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt. Open Quality Updates and select an existing finding; inspecting it is read-only. Review linked work before opening a permitted form. Owner approval is pending; stop here.

---

# Production compensation and unfinished completion — current local result

29 October 2026 — **COMPLETE for the requested local compensation/completion acceptance paths.** No hosted release or activation. The previous partial checkpoint is retained below as history.

## Implemented protected workflow

- Forward migrations `20261029110000_production_compensation_v1.sql` , `20261029114500_compensation_recording_attribution_v1.sql` , `20261029115500_compensation_work_quantity_guard_v1.sql` and `20261029120500_compensation_transfer_recording_confirmation_v1.sql` add immutable compensation decisions, per-entry allowance attribution and source-entitlement releases, with private tables, RLS, revoked direct access, effective factory permissions and actor-bound UUID recovery. These are audit/entitlement records, **not another inventory or Scrap ledger**.
- `production_compensation_read` and `plan_production_compensation` use authoritative applied Quality quantities, current finding/holds, existing allocations, pending execution and actual physical receipts. Reviewed accepted but unreceived output already covers demand. Unreviewed declared output is separately labelled Awaiting Quality and conservatively covers potential demand; it is never labelled accepted or physically received. Live coverage is serialized under existing factory → fulfillment → structure locks; source revisions and permissions are checked again inside the command. Original requirement, saved Planning history and execution identity cannot be rewritten to simulate replacement.
- Active and planned replacement budgets cannot be exceeded using ordinary overproduction confirmation. Active execution: explicit allowance on the **same job and line**, no Planning job. New production after an explicit allowance decision spends its immutable FIFO shares first, even before the original baseline is fully recorded; remaining units stay baseline and the combined unit cap is enforced. Actual additional entries spend immutable allowance shares; the remaining allowance participates in the existing V3 fingerprint. Existing physical/OPEN-transfer, shift, calendar, capability and maintenance contracts remain authoritative. A waiting subsequent commitment, including an overdue queued job, blocks extension. An explicitly confirmed fallback creates separate HIGH unscheduled work without moving either reservation.
- Ended execution: a linked HIGH unscheduled REPLACE item uses the existing Planning/Production/Quality/receiving pipeline. A rejected-only source has **no invented lot, issue or WIP**. The original job stays ended. If an approved active allowance is genuinely unused when execution ends, an explicit recording-complete attestation and reasoned UUID-protected transfer move its remaining entitlement into that same existing planned-work contract; it does not create another allowance or release physical stock twice.
- Complete4 + Replace2 and Replace6 share exclusive coverage. Replacement first covers rejected units; any additional portion releases only eligible, physically stored unfinished entitlement through existing DISPOSITION. Existing issued/started/consumed/committed/locked work is not silently retired. Physical unfinished quantity remains unchanged until real processing. Independently processing released stock has no original-demand linkage.
- Existing Production Quality drawer now provides Complete/Replacement choices, active/planned consequences, required quantity/reason and explicit confirmation, with durable exact-UUID retry. Recording shows authorized replacement separately from the original requirement. EN/AR, RTL and390px verified. Work creation does not resolve the follow-up or fulfill demand; receipt and existing resolution rules remain separate.

## Integration defects fixed during verification

1. A later same-shift context definition had lost the existing WIP_PROCESSING branch. The new forward migration restores it; the issued completion path can now record without violating recording_v3_shape.
2. Generic overproduction confirmation treated an audited allowance as unexplained excess. It is omitted only inside the protected output adapter with an existing allowance; the entry guard still checks every unit and rejects excess. Ordinary production behavior outside this case is unchanged.
3. Current-open-shift recording after Finish remains available under the existing bounded execution period. It does not reopen work or enable after-shift recording. Transferring unused allowance invalidates the recording fingerprint and prevents spending it again.
4. Finding groups may disappear in a full rejection. Eligibility checks authoritative hold rows directly, so removing groups cannot hide issued-stock holds. Later changed Quality evidence blocks obsolete replacement execution and recording.

## Actual quantitative acceptance

| Scenario | Original requirement | Reviewed original result | Executed additional work | Actual finished receipts | Stored unfinished after scenario |
|---|---:|---|---|---:|---:|
| Active Replace6 |909m|903 finished +4 unfinished +2 rejected; measured Quality Scrap1kg|6m on original job|909m|4m, preserved |
| Ended rejected-only |100m|95 finished +5 rejected; measured Quality Scrap2.5kg|5m linked planned replacement|100m|0m, no fictitious lot |
| Mixed Complete4 + Replace2 |909m|903 finished +4 unfinished +2 rejected; measured Quality Scrap1kg|2m on original; real issue/consumption/completion4m|909m|0m |
| Independent reuse after Replace6 (SQL)|909m|Same source as first SQL case|Released4m processed for stock after original fulfillment|Original entitlement remains909m; stock913m|0m |

Production-unit quantities and measured Scrap KG remain separate. Original technician evidence is retained; Quality rejected mass is existing Quality evidence, not silently written into original technician Scrap fields. No receipt is inferred from execution or inspection.

Actual authenticated browser fixture IDs:

| Path | Original item / output | Replacement/completion |
|---|---|---|
| Active |b1ff0113-0c64-4de5-9c55-1f7d129f2cf0 /185287a9-5f4c-4ec7-8e18-b87e27ac0338|Allowance08a14115-0c50-4b41-8916-e230cc6e391f; item unchanged |
| Ended |ba4fd47d-f793-41a0-b17f-718de03f8de8 /bab81684-9a8d-48c0-a9d0-060523adca14|Planned itemdf118e42-62d2-400a-9894-8cedbb6f7254 |
| Mixed |98d20082-c350-4fbb-90a6-f4dd98b8dd5e /8ffcec91-4e07-463b-9b95-65ffe187e9d2|Completeb7a22f5a-d4ca-49de-9c69-87eed037c7fd; Warehouse request7158aff0-5a29-4b71-b9c0-53fce1b297b5; replacement allowance50966c1a-90ea-466c-8823-f5cd8ffe31fd |

The controlled acceptance occurrence was genuinely open on29 October07:37–11:37 UTC (shift570e232c-f081-492e-9d8b-ef86f61d5dbb), created normally before execution. No historic timestamp or closed shift was altered. Fresh products/lines used existing QA identities and their existing factory permissions; no accounts or grants were created. Exact line/product/output/entry/request/UUID references and before/after receipts are retained in the evidence files.

## Verification and honest limits

- **48 distinct PostgreSQL assertions plus23 expected rejections PASS**, including global/source coverage, full and mixed completion, no issue-before-start, exact consumption, immutable audit, target/timestamp protection, late-within-open-shift behavior, unused allowance transfer, disabled contracts, holds and stale evidence.
- **Four real concurrent transaction groups PASS**, with observed lock waits for competing managers and same-UUID retry; concurrent recording admits one additional entry and rejects the stale competitor. A separate actual issued-input race consumes four meters once and rejects its competitor. No concurrency guarantee is inferred from mocks.
- **22 focused Node tests PASS**: compensation API, existing drill-through APIs and Production follow-up endpoint. Origin, actor injection, exact quantity strings, UUID conflict and authorization responses are covered. The existing read-only API mock was updated to export the newly imported origin validator; its read assertions remain unchanged.
- Actual normal browser logins: **28 unique business HTTP200 responses /31 saved steps**, covering drawer decisions and the complete active, ended and mixed pipelines. Final built UI additionally submitted a real allowance, showed it in Record Production, rendered EN/AR390, and returned **403** for an existing restricted user's write and known foreign-factory read; foreign source in own scope returned **422/output_not_found**. Denied attempts did not change decisions, entries or stock.
- Additional actual browser case: original requirement100m, initial record50m reviewed48+2rejected; manager allowance2 and normal Record Production Save each returned HTTP200. The next2m were attributed to that allowance, target remained100, gross recorded52, and none was physically received. A regression then confirmed reviewed48 / awaiting inspection2 remain distinct; spent allowance evidence stays in the drawer.
- TypeScript and isolated optimized production build PASS. The entire inactive migration chain (Export Reader excluded) was replayed in a separate empty loopback schema database; no historical migration was edited.
- Main owner preview: normal read-only login, new drawer and existing equipment navigation PASS, zero business POSTs/page errors. **All114 pre-existing public/private/auth table digests, credentials and prior private fixture predicate were preserved** across local schema installation and owner smoke. Main owner compensation table remains empty. Earlier4m QA completion work was not issued, started or replaced.

Resolved test-development failures are retained in evidence: exact-label selectors, an obsolete assumption that the owner's first finding must be Needs Action (it was legitimately In Progress), SQL variable/column name collisions, the WIP classification failure, and the overdue-reservation edge. These are not hidden behind a false full-suite result. No unrelated historical platform suite, hosted Supabase service or deployment was tested.

Legacy gross-production fields remain historical; reviewed, awaiting-inspection and physical-receipt quantities are shown separately in the Quality-aware drawer. No historic cumulative row was rewritten.

**Protected limitations:** a new finding/reconciliation, unavailable source, expired shift or irreversible work can still block a command. The old lot-based cancellation/revision screen does not acquire a bypass for new rejected-only compensation work. Such revisions require a separately protected review contract; this delivery does not silently cancel obligations, edit historical decisions or override consumed/committed work. No remaining execution blocker exists for the requested fresh-source paths above. Hosted deployment/activation and user manual acceptance remain separate.

## Exact task file manifest

Modified application/tests:

- src/app/api/manufactured-output/route.ts
- src/features/ProductionQualityActions.tsx
- src/features/ProductionQualityCompletion.tsx
- src/features/ProductionRecordingV3.tsx
- tests/manufactured-output-phase4d-api.test.mjs

Added:

- supabase/migrations/20261029110000_production_compensation_v1.sql
- supabase/migrations/20261029114500_compensation_recording_attribution_v1.sql
- supabase/migrations/20261029115500_compensation_work_quantity_guard_v1.sql
- supabase/migrations/20261029120500_compensation_transfer_recording_confirmation_v1.sql
- tests/production-compensation.sql
- tests/production-compensation-flows.sql
- tests/production-compensation-security.sql
- tests/production-compensation-final.sql
- tests/production-compensation-capacity.sql
- tests/production-compensation-recording.sql
- tests/production-compensation-source-revision.sql
- tests/production-compensation-disabled.sql
- tests/production-compensation-concurrency.mjs
- tests/production-compensation-api.test.mjs
- tests/production-compensation-browser.mjs
- tests/production-compensation-preview.mjs
- tests/production-compensation-owner-preview.mjs
- tests/production-compensation-install-local.mjs
- tests/production-compensation-partial.sql
- tests/production-compensation-partial-fixture.mjs
- tests/production-compensation-partial-browser.mjs
- tests/production-compensation-inspection.sql
- tests/production-compensation-work-budget.sql
- tests/production-compensation-transfer-confirmation.sql
- tests/production-compensation-transfer-browser.mjs

Documentation: this report, docs/manufactured-output-phase4.md, docs/PRODUCT_DIFFERENTIATORS.md and HANDOFF.md. All127 pre-task migration hashes and each new migration after its local installation, unrelated dirty work, Export Reader and Design System are preserved. No Git writes.

## Preview and evidence

Main preview: **http://127.0.0.1:4222/?view=lines**. Refresh the page for the matching bundle. Existing **PlanningV3@local.invalid**; unchanged owner-only credentials:
C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt.

Open Floor → Quality Updates → select a finding → Complete or replace missing output. The drawer explains whether replacement stays on active execution or creates HIGH unscheduled Planning work. Inspect warnings, quantity and reason before confirmation. Opening is read-only. When transferring an unused allowance after Finish, first record all actual output, then explicitly confirm that recording is complete. Finish alone is not recording completeness. Creating work is not fulfillment; completed receipts and existing reasoned follow-up resolution remain separate. Existing owner manual records were not used for write acceptance.

Evidence is outside Git: production-compensation under the main runtime above; PostgreSQL/browser fixtures and HTTP evidence under C:\Users\Temp\AppData\Local\Temp\FactoryLean-OperationalUX-SQL-d7232dad5d0d4b6689e384197aadc0ab (production-compensation-browser.json, production-compensation-concurrency.json, compensation-final-preview.json and screenshots). Disposable acceptance used55498/4318/4234. Main55496/4304 retained; only the owned4222 web bundle was replaced. Matching app: production-compensation-owner-app.

Both shipped manufactured-output capability and completed-shift late gate remain **FALSE**. Existing disposable helper simulation is unchanged. LOCAL ONLY: no hosted access, deployment, activation, commit, push, merge, port3000 or unrelated-preview restart. **STOP; user visual/manual review is next.**

---

## Previous partial checkpoint — historical, superseded by the result above

# Quality corrective actions and Production compensation

29 October 2026 — **PARTIAL / LOCAL ONLY.** The follow-up workflow and navigation are implemented and verified. Production compensation is **not complete**. The missing replacement paths remain unavailable; no ordinary target edit, reopened execution or substitute Planning job was used to simulate them.

## Phase results

| Brief phase | Result |
|---|---|
| 1 — Operational follow-up status | Implemented: Needs Action → In Progress → Resolved, protected notes/revisions/UUIDs, immutable actor/time history; opening does not transition. Outstanding count includes Needs Action and In Progress. |
| 2 — Accepted output with a process concern | Implemented: optional Requires Production Follow-Up, separate Quality Observation and Requested corrective action. Matching approval without the option creates no new task. Existing rejection reasons/group notes remain separate. |
| 3 — Production-specific drawer | Implemented: latest accepted result vs recorded output, rejection/unfinished quantities and operation names, requested action, status, actual remaining demand, history and eligible completion. No Quality editor/Warehouse receipt/legacy cross-department buttons. |
| 4 — Unfinished completion | Linked work creation integrated and tested through the real drawer. Existing protected source allocation, Warehouse issue requirement, HIGH unscheduled Planning work and UUID replay retained. Full newly created child execution → Quality → receipt was **not executed in this task**. Unreceived/held/unavailable material cannot be allocated. No new pending-receipt intent engine. |
| 5 — Replacement compensation | **NOT IMPLEMENTED / BLOCKED IN THE NEW DRAWER.** Active-execution target allowances, rejected-only replacement and mixed complete/replace decisions remain gaps. Existing source-bound Planning REPLACE remains unchanged, but is not presented as the requested new Production compensation path. |
| 6 — Resolution vs physical fulfillment | Implemented conservatively: a process action may resolve with evidence; a material finding cannot resolve while its authoritative demand remains unmet or related source stock is held. Creating work never marks it resolved. |
| 7 — Equipment navigation | Implemented within Production, with a distinct equipment icon, existing configuration authorization/forms, correct active state and EN/AR labels. Cancellation of the existing unsaved-work prompt cannot open management. |
| 8 — Acceptance | Follow-up, permission, concurrency, completion-creation and owner read checks pass. Active/ended replacement and a fresh full completion-execution chain remain unverified; overall COMPLETE is therefore inappropriate. |

## Protected implementation

One new forward local migration: `20261029060000_production_quality_followups_v1.sql`. All **126 pre-task migration files remain byte-identical**; local file count is **127**. No remote history was inspected or claimed aligned. The new migration remained a local development draft while its functions were verified on disposable databases; no historical migration was changed.

- Private append-only `production_quality_followup_events`: factory/output/finding revision, operation, resulting state, UUID, actor, server timestamp and immutable payload. UPDATE/DELETE uses the existing immutable-evidence guard. No authenticated/service-role table access is granted.
- Existing `public.manufactured_output_command`: retains authorization, factory-lock order, disabled gate and original private Quality writer. Separates the three optional process fields before calling that writer; stores the full command evidence atomically. Quality UUID replay must match actor, target and payload. No new stock, Scrap or quantity writer.
- New protected `public.production_quality_followups(factory,page,state)`: outstanding/Needs Action/In Progress/Resolved filters, global outstanding count, latest authoritative Quality evidence and action history. Legacy ACKs do **not** resolve tasks. A later ordinary matching inspection neither silently clears an open process action nor discards its resolved history. Disabled readers return an unavailable result with an empty JSON array.
- New protected `public.production_quality_followup_command(factory,target,operation,payload,expected_revision,request_id)`: START/RESOLVE only, effective Factory view + Orders edit, factory → fulfillment → output locking, permission recheck after waiting, current finding/status revision, meaningful resolution note and exact actor-bound UUID replay. An edited replay revision conflicts. Resolution checks actual demand and related Quality holds.
- `GET/POST /api/production-quality` uses normal authenticated clients, private/no-store responses and origin validation for writes. SQL remains authoritative. Session storage preserves unknown writes for exact UUID retry.
- Existing `plan_manufactured_completion` via `/api/manufactured-output` remains the only completion-allocation command. The drawer supplies its exact source group, quantity, operations, source revision and UUID; the existing protected engine creates the source-linked item and Warehouse material request. No automatic issue, consumption, schedule, Good, receipt or demand satisfaction.

No old read acknowledgement was bulk converted to Resolved. Existing Quality/Lean/Loss snapshots, source records, execution timestamps and active stock behavior remain unchanged.

## Exact compensation dependency

The present `plan_manufactured_completion` contract requires a real unfinished `manufactured_output_lots`/`unfinished_lots` source, a selected Quality group, available stored quantity and its demand entitlement. It cannot create replacement for rejected-only output. Its REPLACE path creates a separate unscheduled job; it cannot safely implement the active-order policy.

`production_orders.target_quantity` currently participates in both demand and manufacturing/recording contracts. Raising it directly would also change the demand against which fulfillment and completion allocations are checked. Keeping it unchanged and merely allowing ordinary overproduction would omit the approved replacement allowance/audit and unfinished-entitlement release. Neither is the requested behavior.

The remaining implementation needs: an immutable same-execution manufacturing allowance distinct from original demand; integration with recording eligibility/fingerprints and remaining-target readers; exclusive demand coverage across accepted receipts, unfinished dispositions and replacement allowances; source entitlement handling before/after Warehouse receipt; rejected-only ended-job linkage; and explicit schedule-overrun reporting without changing saved planned timestamps. Those protections have **not been added** here. No new “Produce Replacement” button is exposed with an unsafe or misleading backend. This is an implementation gap, not a claim that additional owner authorization is missing.

Mixed Complete4 + Replace2 / Replace6, active compensation, ended rejected-only replacement and source entitlement release remain **NOT TESTED**. No claim of full order-flow acceptance is made.

## Verified local evidence

Independent runtime checks: owner preview PostgreSQL **127.0.0.1:55496**, existing Auth/Data adapter **4304**, app **4222**; mutation tests on separate disposable PostgreSQL **55498**, Auth/Data **4317**, app **4233**. Endpoint, database and owned data directory were checked. Normal local logins were used. Hosted environments were never accessed.

- **25/25 focused Node tests PASS**: protected API argument forwarding/default filters, invalid filters, denied read/no data disclosure, actor injection rejection, equipment grant filtering, sidebar behavior and local-runtime safety; existing exact receipt tests included.
- **15 distinct new PostgreSQL assertions PASS**, plus **six expected rejections**: matching with/without follow-up, one-event retries, list opening without transition, In Progress stays outstanding, later ordinary matching review preserves open/resolved action history, evidence-backed process resolution, no stock/new production from follow-up, source-bound completion replay, Warehouse issue requirement, HIGH unscheduled work, unchanged received demand; restricted execution, edited UUID replay, premature material resolution, immutable evidence, foreign-factory read and disabled write rejected. The disabled predicate was tested inside a rolled-back disposable transaction; no activation row was changed.
- **Two actual concurrent START groups PASS**, with observed database lock waits: same UUID replays one transition; competing UUIDs with the same status revision yield one transition and one stale rejection. No lock/retry guarantee is inferred from component mocks.
- Authenticated browser at **4233**: unchanged accepted10m + explicit printing concern saved through protected Quality HTTP200; opening the dedicated drawer made no transition; actual START and reasoned RESOLVE each HTTP200. Stock/Production records and orders stayed byte-identical. EN desktop and AR/RTL390 checked; screenshot inspected.
- Actual browser completion: output `28e6f951-ed3c-4a15-9467-6c3dc173bbd9`, **4m** of genuinely stored unfinished material; UUID `b7dd0713-d454-4523-bba0-70031cfb052b`. Protected work `218e79ec-4ba1-4d7c-b323-8c18891cc33a`, material request `aaae99d2-835f-4717-ae8e-41cfb678b350`, HTTP200. Verified line/actual start NULL, priority HIGH, quantity4, request REQUESTED. Original received-demand metric stayed **15m**; no issue, input consumption or new finished receipt was invented. This metric is not a claim that held stock is dispatchable.
- Existing separate restricted QA user: actual follow-up write **403**, known foreign-factory read **403**, no event changes; no equipment destination. Owner opened the existing equipment-management module without saving.
- Existing owner **4222**: normal login, current tasks, opening without transition, dedicated drawer, equipment destination/active state, actual Quality optional control and disabled shipped gates verified read-only. Zero business POSTs; no owner follow-up events were created by the tests.
- TypeScript and isolated optimized production build PASS. Existing unrelated historical harness failures are unchanged and were not rerun as a broad suite. Earlier evidence remains in `warehouse-final-cleanup.md`; no green full-project result is claimed.

Early test failures were corrected transparently: the immutable guard's exact error name, absent zero-balance row in an unreceived fixture, selector labels, and a race-query whitespace/observation-window issue. A substantive added regression exposed loss of resolved action history after a later ordinary matching review; the final helper preserves that history. These fixes did not change production quantities or weaken checks.

Evidence: `quality-actions` under `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2`; separate SQL results in the existing `FactoryLean-OperationalUX-SQL-d7232dad5d0d4b6689e384197aadc0ab` runtime. Test scripts are preserved. Credentials and generated files remain outside Git.

## Files

Added: the migration above; `src/app/api/production-quality/route.ts`; `src/features/ProductionQualityActions.tsx`; `src/features/ProductionQualityCompletion.tsx`; `tests/production-quality-actions.test.mjs`; `tests/quality-actions{.sql,-security.sql,-disabled.sql,-completion.sql,-concurrency.mjs,-browser.mjs,-completion-browser.mjs,-denials.mjs,-preview.mjs}`; this report.

Modified: `src/features/ProductionRecordingV3.tsx`, `src/features/ManufacturedOutput.tsx`, `src/utils/operational-navigation.mjs`, `src/components/OperationalNavigation.tsx`, `src/components/NavigationIcon.tsx`, `src/components/FactoryApp.tsx`, `tests/sidebar-navigation.test.mjs`, `HANDOFF.md`, `docs/PRODUCT_DIFFERENTIATORS.md`. All other pre-task files are preserved, including Export Reader and Design System. Legacy `QualityUpdateButton` remains for its existing historical/component consumers; Floor now uses the operational component.

## Preview and manual review

URL: **http://127.0.0.1:4222/?view=lines**. Existing owner **PlanningV3@local.invalid**; unchanged owner-restricted credentials file:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.

1. Refresh Floor → Quality Updates. Opening an item must keep it outstanding. Start Handling records responsibility; material shortage resolution remains blocked until real fulfillment/hold eligibility permits it.
2. Quality → select a pending inspection. Requires Production Follow-Up reveals a separate observation and requested action; accepting matching quantities does not itself reject or alter stock.
3. For eligible stored unfinished material, open Complete Unfinished Production, inspect quantity/operations and make an explicit decision. This creates real local work; merely opening it does not.
4. Production → Manage Lines & Machines opens the existing configuration module. Do not save configuration just to test navigation.

Original owner review records, account/membership/grants and credentials remain unchanged. Both shipped manufactured-output capability and completed-shift late recording remain **FALSE** (late schema0); pre-existing disposable helper simulation remains unchanged. No hosted access, deployment, Git write, port3000 operation or unrelated-preview change. Temporary acceptance processes are stopped after verification; the owner preview remains running.

Bounded product references: [Tulip Frontline QMS](https://support.tulip.co/docs/frontline-qms-1) distinguishes quality issue/CAPA tracking; [MRPeasy Quality Control](https://www.mrpeasy.com/resources/user-manual/settings/system/professional-functions/quality-control/) keeps repair work as a separate manufacturing/service-order process. These support separating action tracking from goods disposition; they do not replace the owner's active-execution compensation policy or imply it is implemented.

**STOP after this partial local delivery. No automatic checkpoint, hosted work or unrelated next task.**
