# Production Recording V3 — Phase4D

21 October 2026. **LOCAL ACCEPTANCE PASS. STOP for owner review.** The owner approved Phases4A/4B/4C, simplified History, table double-click and pending navigation in the Phase4D brief. Older reports retain their historical approval status. No hosted acceptance or production-readiness claim.

## Two confirmed integration fixes

**4D-01 — My Requests filtered after pagination.** An approver could load fifty other employees' records and see an empty My Requests list despite having submissions later in the history. The existing SQL reader did not support requester filtering. Added only a boolean `mine` filter to the existing protected `production_correction_read`, before selection count/keyset pagination; the actor comes from `auth.uid()`, never a client-supplied ID. Existing factory/view permission, reviewer-versus-own authorization, cursor actor/factory/query/revision binding and private storage are preserved. UI now sends `mine=1` rather than filtering loaded rows. No new reader, writer, permission policy or unbounded browser fetch.

CLI-generated forward migration: `20261021060632_production_correction_my_requests.sql`. **99 local migration files**, with98 required in the standalone chain excluding Export Reader. All98 pre-task migration files remain byte-identical. New migration applied only to the fresh disposable localhost test cluster and retained localhost preview. History aggregate and Phase4C context migrations remain ordered before it. No remote history was accessed, repaired or deployed.

Actual regression:105 technician requests precede3 approver-owned requests. The first general page contains no owner submissions; `mine=true` returns total3, pages2+1, with no duplicates. Invalid/null/string flags, forged requester, cross-factory access and wrong-scope cursor reject. Ordinary employees remain own-scoped; anonymous execution remains revoked. Source/stock does not change from filtering.

**4D-02 — History rounded exact recorded quantities.** The real browser/Next/SQL chain preserved19 decimals in recording, immutable receipt and recovery, but legacy History parsed PostgreSQL numeric through JavaScript Number: `0.1234567890123456789` became `0.12345678901234568`. The supplementary KG query had the same risk. History and its shared contextual-export handler now use the existing exact JSON tokenizer before the installed client parses those two successful response paths. Quantities retain decimal text; page/count controls keep safe integer types. Unrelated RPCs and errors are unchanged. No numeric calculation, SQL posting, inventory/WIP rule or saved evidence was modified. Four focused regressions plus actual History browser/API checks confirm exact Good and Scrap after the fix.

## Executed acceptance

| Workflow | Evidence/result |
| --- | --- |
| Floor → Record → selected work → Good/Scrap → Save → History | Actual full Next app, protected current-shift reader and original SQL; configured Meter and KG; committed result before success; new1.25 Meter/.05 KG entry visible in History. |
| Connection recovery | A second committed entry has0.1234567890123456789 Meter and0.01234567890123456789 KG. Captured original UUID/body, lost response, browser refresh/status recovery, identical replay and changed-intent409; no second entry/stock credit. Node tests cover uncertain/invalid/denied outcomes and durable actor/factory intent constraints. |
| Technician correction | Separate normal local technician login; edited suggestion/free-text reason; proposed Scrap.075 KG remains Pending, official.05 KG unchanged; own tracking works; restricted pending-count API403/no count. |
| Approver decisions | Separate normal owner login; pending alert and requester/details; approval posts once and History shows.075 KG; a second.09 KG proposal is rejected without official effects; pending count returns to its original level; self-approval changes Scrap to.08 KG. Existing pending requests untouched. |
| My Requests | Actual UI/server-filtered owner list; separate SQL >100-row boundary/cursor regression. |
| Stock/source/WIP | Approved Good/Scrap, no-effects pending/rejected, WIP conservation, source availability and reservations tested through existing protected correction policy; actual retained preview Good, stock, source credits and ledger agree exactly. |
| Quality/Lean | Current corrected Scrap remains separate from prior reviewed evidence, requires authorized re-review and does not qualify stale/unreviewed Lean input. Actual protected Warehouse acknowledgment/retry adds no stock; saved initiative/comparison/Loss snapshots remain unchanged after correction/re-review. |
| History | Seven defaults, single selection, double-click and toolbar Details, six facts, independent product/order Scrap aggregate, scoped preferences and existing correction history on demand. Existing filters/preferences regressions pass; no summary/status/Actions column added. |
| EN/AR/mobile | Installed Edge155.0.4283.62; actual translated text, RTL, selected work with Good/KG controls at390×844, no document overflow; desktop History and mobile evidence retained. |
| Excel/Print | Real filtered History HTTP200 XLSX ZIP and HTTP200 Print HTML; no duplicate download, native Print dialog or physical PDF output claimed. |

### Counts and applicability

- **234/234 focused Node tests across13 files**, zero failures/skips in final run. Includes new filter/precision tests, existing recording/recovery, correction API/UI, History/filters/aggregate/preferences, pending alert, table handler, consumer precision and departmental-export contracts. This is not a full-project suite.
- **195 standalone PostgreSQL assertions/groups:**54 existing guarded-writer/boundary checks,70 correction/security/pagination checks (58 existing+12 new),62 consumer/review/saved-evidence checks, plus9 rolled-back context/UI checks. **Three actual separate-connection correction races** additionally verify duplicate approvals, conflicting terminal decisions and revocation while waiting. Counts are distinct categories, not inflated into one number.
- One fresh PostgreSQL17.11 cluster, loopback55478, all98 required original/forward files ordered, Export Reader excluded. Existing installed portable binaries reused; no install/service/PATH/dependency change. Completed-current-shift output is enabled only for that disposable SQL fixture, and completed status/actual timestamps are retained. Final recording/Maintenance gates FALSE. The unchanged earlier M2 expiry/locking race evidence remains applicable; all16 old M2 races and the complete Phase1–3D campaign were not rerun.
- **Eight practical browser groups PASS**, with resumed incomplete groups after the concrete precision fix; successful recording/decision groups were not repeated. Zero final page exceptions/external requests. TypeScript and isolated optimized Next16.3.5 webpack build PASS on final source. Browser/component proof uses the local Auth/Data adapter and original SQL, not hosted GoTrue/PostgREST/schema-cache.

## Controlled retained fixture

The previous shift had a legitimate06:01–07:01 UTC gap during this task. Read-only work returned occurrence null/zero eligible rows. One prospective **Morning shift / الوردية الصباحية** was configured through `configure_production_shift` as the authenticated existing local owner, within that gap and ending07:01:44.093381 UTC. Previous shift definition, Planning schedule, queue, machine states and transfer ownership were not edited. There is no manufactured completion/forced start or historical timestamp rewrite. Setup evidence includes the new shift ID and protected command result.

Two new entry IDs only:

- Normal: `17b73312-8ba7-4bdf-a0e2-8f3d16ed1ea0`, Good1.25 Meter; Scrap.05 → pending.075 → approved.075 → self-approved.08 KG; rejected.09 proposal has no effect.
- Recovery: `e31459f4-6d23-4257-ac49-5f5810abd1ee`, exact Good0.1234567890123456789 Meter/Scrap0.01234567890123456789 KG; one immutable request and one credit despite replay.

Existing six entries and unrelated pending request were not targeted by this task's writes. Final eight entries: gross Good42.1234567890123456789 Meter; official Good/finished on-hand/source credit/movement ledger each39.6234567890123456789 Meter; Scrap2.30234567890123456789 KG; effective recorded WIP output4 Meter; reserved0. The4 Meter value is effective recorded output, not the older gross2 Meter WIP figure in historical handoffs and not a substituted lot balance. Both new entries have zero WIP. No physical identification was invented.

Retained preview V3 gate FALSE/schema0 and Maintenance FALSE. M1 intentionally still publishes unavailable late capability; real completed-work UI activation integration remains a separately authorized release prerequisite. Enabled late evidence here is standalone SQL only.

## Harness diagnostics and limits

- Portable package has no pg_dump; fresh isolated setup replaced the proposed clone. No snapshot/restore of retained preview data occurred.
- Windows pg_ctl child output remained open; startup now uses file-backed output. The first fresh cluster inherited host timezone while fixtures explicitly model UTC; subsequent fresh setup sets UTC like the established runners. Failed startup/seed diagnostics are retained and not PASS evidence. Original SQL/migrations were not changed to make fixtures pass.
- The initial browser lost-response route was released before its asynchronous route handler finished. The recorded original UUID/body was resumed in a normal authorized browser recovery fixture, refreshed and recovered without another recording. This recovery-fixture restoration is test plumbing, not production authentication/session injection. Completed groups were skipped on resumption. The final client/storage/SQL tests remain authoritative for preserved original intent.
- The older History component-only hook harness lacked useRef and a real row-click event after the prior shared table handler. Updated only those harness inputs; final assertions all pass. No React hook/business rule was weakened.
- Existing Excel/Print numeric precision limits remain: values exceeding15 significant digits fail closed rather than being rounded into an export. The filtered compatible-value export path was tested successfully; no claim that Excel can natively preserve arbitrary PostgreSQL numeric precision. The exact History UI/API remains available.
- Chrome/Firefox, physical mobile input, screen readers, comprehensive dark mode and actual Print-to-PDF/manual acceptance remain unverified. Missing historical employee display names remain an audit-display limitation; IDs/permissions remain authoritative.
- Automatic approval review rejected removal of owned disposable PostgreSQL data folders with only “blocked by policy.” Test server55478 is stopped; temporary data and evidence remain. No alternate deletion was attempted. Original preview4207/4291/55476 stays running.

## Exact task manifest

Changed existing files:

1. `src/features/ProductionCorrections.tsx`
2. `src/utils/production-corrections.mjs`
3. `src/utils/production-history.mjs`
4. `src/app/api/production-history/route.ts`
5. `src/app/api/table-export/route.ts`
6. `tests/production-corrections.test.mjs`
7. `tests/production-history.test.mjs`
8. `HANDOFF.md`

New files:

9. `supabase/migrations/20261021060632_production_correction_my_requests.sql`
10. `tests/production-history-precision.test.mjs`
11. `tests/production-recording-phase4d/run-local.mjs`
12. `tests/production-recording-phase4d/my-requests.sql`
13. `tests/production-recording-phase4d/browser.mjs`
14. `docs/production-recording-v3-phase4d.md`

Evidence: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Phase4D-nW2Sz9` (starting hashes, final preservation/manifest, SQL logs/counts, race report, browser state/results, desktop/mobile images, Node, typecheck/build, export and preview totals). Scripts containing synthetic source quantities/UUIDs are separate from credentials; no passwords/tokens are logged or added to Git.

Development branch/HEAD bb0d20e5dd433b896dd319f56e75f0d9eb5d2862, main/index, all previous migration bytes, Design System, Export Reader and unrelated dirty work preserved. Product Differentiators reviewed; these corrections add no new competitive capability claim. No hosted project access/deployment, activation, Git write, commit or push.

## Stop / next recommendation

Owner review of the corrected local experience: http://127.0.0.1:4207/?view=productionCorrections . The retained runtime and fixtures remain for that review. Do not rerun write-capable browser tests casually; their state file deliberately retains completed groups and original request IDs.

Next smallest authorized scope, only after review: protected M1 capability-publication/activation integration for completed-work UI, retaining default FALSE, then a separate hosted release plan with required three-way history verification, isolated manifest/dry run, coordinated app/backend delivery and real hosted authentication/manual acceptance. Do not deploy, activate, commit or begin those steps automatically.
