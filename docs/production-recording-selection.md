# Direct production recording and missing work — 1 November 2026

**COMPLETE / LOCAL VERIFIED. Stop for owner manual review.** The real owner order remains unavailable for recording until its legitimate shift configuration is addressed through an authorized workflow. This task does not change that configuration.

## Verified cause

Authenticated localhost4222 reproduction and read-only PostgreSQL55496 inspection agree:

- **PO-0000021 is the Production Request**, not the execution item. Its item **PO-0000022**, UUID `4afef1ed-2824-4c8a-ac4a-2a048142bbb8`, belongs to Printing line, is active, target100m, recorded gross Good2m, remaining98m. Actual execution began `2026-10-27T09:10:10.40992+00:00` and has no actual finish.
- Factory Floor legitimately displays persisted execution/line assignment under the request reference. That is not current-shift recording eligibility.
- At the investigation instant `2026-11-01T06:03:35+00:00`, the protected `production_shift_work` returned HTTP200, `available:false`, `reason:SCHEDULE_GAP`, `occurrence:null`, zero rows, factory timezoneUTC, `can_edit:true`, late capabilityFALSE. `first_verified_start` is `2026-10-28T08:56:52.779517+00:00`. No shift schedule covers the present instant. This is not a permission failure, Arabic/UTC conversion bug or proven reader-filter defect. The earlier execution timestamp alone does not prove eligibility; restoring a schedule is necessary, not a promise that every other existing eligibility rule will pass.
- The UI previously retained a selected item separately from the freshly loaded rows and emitted overlapping no-occurrence/no-work/work-changed messages. Its work fetch did not follow the normal30s snapshot refresh. Floor had no direct ordinary Record control bound to the item; a global form required another selection. It showed different request/item references without explaining their relationship.

No shift, execution, schedule, owner quantity or permission was changed to force eligibility. No backend migration is justified.

## Changes

Active Floor cards now offer Record Production with the exact item UUID. End Production retains its exact item binding. The shared form pins direct work, hides redundant selection/search and never selects another order as fallback. It shows request/item references together. Ineligible direct work retains its authorized product/line identity and requested/recorded/remaining summary rather than inventing a selectable row. For the owner case it shows100/2/98m and **one actionable shift-gap explanation**, with Save disabled.

The protected work list refreshes with the existing snapshot cycle. A direct target beyond the first page is looked up through the existing opaque-cursor pagination contract; no client-created execution context or alternative reader bypass exists. Selection and per-item drafts remain intact. A disappeared target stays selected and receives an unavailable explanation. SQL still validates current occurrence, execution/context fingerprint, permissions, source quantities, deadline and immutable UUID retries.

Removed generic introductory/preview banners above the daily inputs. Shift information and recent entries are collapsed details; mandatory current-shift declaration, source-consumption inputs, measured ScrapKG, excess-output confirmation, actual validation failures and recovery controls remain visible when applicable. Existing tokens, sticky actions, EN/AR/RTL and narrow-screen action layout are retained. This is bounded operational cleanup using the already-reviewed operator recording pattern, not a new competitive capability; Product Differentiators was reviewed and left unchanged.

Summary semantics remain the existing exact-decimal, entry/correction-maintained gross Good contract: `max(authorized target - recorded Good,0)`. Quality accepted/rejected and Warehouse stock are separate. No change to demand, allowances or units. Ordinary recording does not finish execution; End still records first then finishes, with durable finish-only recovery. No-new-output End creates no fake entry. Same-open-shift completed recording remains supported; closed-shift capability staysFALSE.

## Current acceptance evidence

- **97 focused Node tests PASS**, including new contextual-state tests, exact completion/API tests, retained-intent/recovery tests, shift-work parsing/authorization and same-shift rules. TypeScript and optimized isolated builds PASS. React review and whitespace check PASS.
- Owner normal login, exact card→Record, both references,100/2/98m, single warning and disabled Save PASS. No operational POST. Desktop1440/tablet768/mobile390 English and Arabic390 screenshots inspected.
- A separate verified disposable database55500/Auth4322/application4238 received a fresh protected shift and independent Sales-linked `selection` fixture using existing accounts. Original owner55496/Auth4304 data and shifts were untouched. Fixture start and initial2m recording use existing protected workflows; no new accounts or grants.
- Exact card→Record opens requested6/recorded2/remaining4m without reselecting. User entered1.5m and0.125KG Scrap. Protected saveHTTP200 left execution active, gross Good3.5m; the new entry is available in protected Quality readerHTTP200. Two concurrent identical UUID replaysHTTP200/200 leave two total entries (initial + new), sum effective Good3.5m, Scrap0.125KG, finished stock0. No premature Warehouse credit.
- Subsequent End opens the same form with remaining2.5m. Confirmed End Without New Recording completes execution with gross3.5m/entry count unchanged. Prior verified recording-then-finish failure/reload recovery, completed same-shift and full Quality/receipt tests remain applicable: protected writers, intent transport and handoff code were not modified, and focused recovery tests passed again. They were not falsely repeated as new full downstream acceptance.
- Two real30s refresh cycles in both owner-blocked and eligible Arabic mobile forms: protected work reads200/200, same dialog/input nodes, focus, drafts and scroll position. No silent order substitution. English/tablet layouts also checked.
- Fresh independent restricted-account recordingHTTP403 and summaryHTTP403; owner known foreign-factory recordingHTTP403. Execution row hash unchanged. No account/permission changes.
- One test-script error used `response.status()` on browser Fetch's numeric status after a successful save. Continued from saved UUID/evidence without a new recording; final replay/End/conservation checks PASS. This was not an application defect.

These are real local protected PostgreSQL/RLS checks behind the existing disposable Auth/Data adapter, not hosted Supabase acceptance. Manufactured path uses the inherited local test predicate; neither shipped gate was enabled. No universal activated-workflow readiness claim.

## Incremental manifest

Modified: `src/features/FactoryFloorV2.tsx`, `src/features/ProductionRecordingV3.tsx`, `src/locales/en.json`, `src/locales/ar.json`, `docs/production-recording-completion-ux.md`, `HANDOFF.md`.

New: `src/utils/recording-work-state.mjs`, `tests/recording-work-state.test.mjs`, `tests/recording-selection/before.mjs`, `browser.mjs`, `after-save.mjs`, `denial.mjs`, and this report. **13 files; no migration/dependency or configuration source change.** Test credentials are read from owner-restricted external files, never embedded.

## Preview and evidence

Main preview **http://127.0.0.1:4222/?view=lines**, matching `recording-selection-app` under existing owner runtime. Existing owner `PlanningV3@local.invalid`; credentials unchanged:
`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`.

Select Record Production on the Printing line's active requestPO-0000021. Expect exact itemPO-0000022,100/2/98m and a schedule-gap explanation. **Recording this owner order remains blocked by valid policy.** This task neither repairs that schedule nor automatically makes it eligible; owner authorization and normal configuration are needed separately.

Owner evidence: runtime `recording-selection/before.json`, `before.png`, `browser.json`, `1440-en.png`, `768-en.png`, `390-en.png`, `390-ar.png`. QA evidence in `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Production-End-65b76ac01c494ac6b7b57f99886b9f6f\recording-selection`: browser, denial and conservationJSON plus matching screenshots. QA selection fixture is now completed; do not rerun the write scenario blindly. Continuation script exists solely to reconcile the already-saved test result, not as a normal seed.

Preservation check:118 original owner public-table digests, credentials and all136 pre-task migration files unchanged. Prior Gantt/navigation/refresh work, Export Reader, Design System and unrelated dirty files preserved. Both shipped gatesFALSE, inherited disposable predicate unchanged. development HEAD`bb0d20e5dd433b896dd319f56e75f0d9eb5d2862`, index empty. No hosted access, deployment, Git writes, localhost3000 or unrelated-preview changes. STOP for manual review.
