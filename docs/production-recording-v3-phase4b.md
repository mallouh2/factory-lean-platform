# Production Recording V3 — Phase4B implementation

**Owner acceptance update,20 October2026:** the original two-control component preview failed owner visual acceptance. Its History mock caused a rendering exception. The bounded Phase4B-FIX diagnosis, real full-application review environment, navigation/localization corrections and current verification are documented in [production-recording-v3-phase4b-fix.md](production-recording-v3-phase4b-fix.md). Historical results below remain historical; owner approval is still pending. Phase4C/4D are not authorized.

20 October 2026. **LOCAL COMPLETE WITH PENDING ACCEPTANCE.** Production Recording UI implemented in the real application, locally only. Phase4C/4D, hosted acceptance and deployments are deferred. The standalone preview remains a reference; its synthetic posting logic was not copied into application business logic.

## Recovery and preservation

Repository `C:\Users\Temp\Documents\GitHub\factory-lean-platform`, branch development, HEAD bb0d20e5dd433b896dd319f56e75f0d9eb5d2862. main remains afd2674993df4d9bedda5cf35dc5b75de3cba4b0. Initial state:758 project files,35 modified tracked/160 untracked individual/zero staged,96 migrations.

Verified pre-edit backup: `C:\Users\Temp\Documents\FactoryLean-Development-Backups\Phase4B-PreImplementation-20261020-084056-3e6ade0d`. All758 ZIP entries were individually rehashed. Recovery ZIP SHA256 **2C5DD17938106488FC7447D4F353992CDB2A8B5905B34D3124C08BBEB37F59E2**. Git state/index and confidential ignored configuration are separately recorded under owner-only access. No credentials are in this report. Phase2 and Phase3C/pre3D recovery ZIPs were also reverified before implementation. An initial owner-SID ACL lookup failed before copying or editing; the successful checkpoint uses a verified numeric owner SID, with inherited access disabled.

All96 migration files, canonical untracked Design System, Export Reader, environment/link files and unrelated dirty work are preserved. No Git staging/commit/push/branch change or hosted access occurred. Final state:779 project files,40 modified tracked/181 untracked individual/zero staged;33 task files (12 modified baseline files,21 new). Final preservation evidence compares every baseline file, refs/index, private configuration and archive hashes; see evidence paths below.

## Screens, design and business integration

Factory Floor's existing header gains Record Production and History. The old embedded recording/history section is replaced only after preserving access to its supported functions. Machine state, effective flow, Start/Finish, transfers, downtime and Maintenance controls are unchanged.

The new focused modal uses the existing protected `/api/production-shift-work` reader. Work identity includes Product, request, item, line, status and units. No ambiguous automatic selection or product-name merging occurs. Protected pagination/search, no-work/read-error/permission/deadline states and an explicit spanning-shift declaration preserve backend truth. Technician defaults only to the authenticated person's matching technician record; otherwise selection is required. Decimal input stays text until exact canonical numeric JSON reaches the existing writer. Arabic digits are normalized without floating-point measurement conversion.

`/api/data` still invokes `record_lean_production`; the new `X-Factory-Recording:3` header selects the already established exact-token transport/error contract for preserved legacy/WIP input without inventing a recording context. SQL admission, permissions, conservation and source posting do not change. No new RPC, SQL policy or migration was added.

History still opens existing ProductionHistory and LeanScrapReview, including established correction protection. Other recording options retains existing independent-machine, WIP/source/destination, discarded production quantity, remaining work, startup and manual-shift workflows. Required source inputs appear directly when WIP processing is selected. Only the new wrapper requests exact outgoing measurement strings; other legacy callers retain their prior defaults and previews. No new inventory calculations are performed in the browser.

Approved fidelity: all256 first-root token values, Inter/IBM Arabic assets, white/blue/ink surfaces, reference proportions, spacing,12/16px radii,640px centered dialog,44px buttons/48px inputs, status surfaces, restrained transitions and mobile fullscreen. Styles are scoped; existing shell/Floor and unrelated pages are not redesigned. Necessary deviations: real dated occurrence/timezone and technician/declaration constraints; in-modal language button for accessibility; wider preserved History; existing compatibility form with its mandatory fields; long exact receipt values stack rather than truncate or round. The owner-approved gradual application standard is recorded in `docs/design/APPROVED_APPLICATION_UI.md`, without changing the proposed canonical Design System.

## Capability boundary

**Completed-job late recording remains disabled in actual application responses.** M1's SQL reader intentionally publishes FALSE; `src/utils/production-shift-work.mjs` rejects a TRUE response. The UI fails closed for unavailable/unknown authority and does not synthesize readiness. Ordinary eligible active work remains available under existing permissions; completed work retains Completed status and disabled Save.

Browser testing of enabled completed work uses an explicitly marked synthetic adapter only. Actual disposable PostgreSQL tests exercise the existing M2 gate TRUE/FALSE independently. This does not prove an enabled production reader publishes TRUE. A supported protected capability publication/activation integration requires separately authorized SQL work before completed-work UI acceptance; none is attempted here. Default gates remain FALSE/schema0; Maintenance remains unchanged.

## Durable recovery and recent entries

Each intentional submit persists an actor/factory-scoped UUID, exact raw body, creation/check time and schema version before POST. Storage write/readback failure prevents sending. Web Locks serialize preparation, status metadata and terminal acknowledgment across tabs; missing lock/storage support fails closed. Repeated clicks and same-body retries reuse the original UUID. Changed payloads cannot replace an unresolved recording. Old-tab recovery cannot overwrite a newer intent. Fetch timeouts retain uncertainty rather than claiming failure or creating another UUID.

On reopening after refresh/restart, the protected status reader checks the retained request. Only a matching version3 COMMITTED receipt with valid entry UUID is success. Current corrected values are displayed separately from the original receipt. Auth loss, collision, unavailable status and transport failure remain UNKNOWN. A definitive transactional rejection permits explicit review of the retained draft; a new intentional submit receives a new UUID. Unknown attempted intents never expire silently. Terminal acknowledgment removes the full payload and retains at most100 minimal receipt references, pruning references older than30 days on terminal acknowledgment. No access tokens or credentials are stored. Unsent ordinary drafts remain in scoped component memory, including work-to-work switching; this is not cross-browser draft synchronization or exactly-once physical recording across different users.

Recent5 protected History entries refresh after committed receipt; same-actor/item/exact quantities within30 minutes produce a nonblocking advisory. It is not proof of duplicate production. Refresh failure does not undo a confirmed save. No cross-factory data is accepted.

Browser testing found and fixed two UI timing issues: recovery triggered by a newly created intent could race its own POST; recovery now runs on opening a retained intent. A Review Draft footer control reused as Save could acquire a native form default during rendering; explicit preventDefault/button type and separate submit identity prevent accidental resubmission. Tests wait for asynchronous acknowledgment before checking cleanup.

## English, Arabic and accessibility

Existing dictionaries and FactoryApp language controller are reused. Modal labels, errors, statuses and notifications resolve keys at render time; `lang`/`dir` persist through the existing preference. An in-modal language action works while the surrounding document is inert. Arabic font, logical layout, isolated quantities, exact units and RTL are preserved.

Installed Edge155.0.4283.62: cold EN/AR, live switching with a modal/error/success open and refresh persistence PASS. In-app browser: modal opening, current-work identity and live EN→AR→EN text were separately observed PASS. Chrome/Firefox executables are unavailable at checked system/user paths: **PENDING**, not inferred from Chromium/Edge. No browser was installed.

Using normal controls in the unchanged Phase4A prototype, Edge reproduced a partial stale-English banner after Arabic selection: `notice.text` was translated when created and was retained during render. The remainder switched to Arabic/RTL. This establishes that particular partial defect, not the owner's original whole-page symptom. New application state stores message keys and retranslates on render; the prototype files remain unchanged.

Actual component checks cover640px desktop,768px tablet/short viewport,390px Arabic full screen, no horizontal overflow, body scrolling with footer retained,44px actions/16px inputs, linked field errors, alert/status semantics, native dialog labeling, focus restoration, keyboard containment and reduced motion. The shared visual runtime was adapted outside the repository only for installed Edge resolution and opening/selecting the component. After transition settlement its sole finding in each viewport is the intentional vertical body scroll; no residual contrast/tiny-text finding. Earlier immediate-transition contrast warnings were transient interpolation, not hidden final findings. Screen-reader hardware/software and a physical mobile keyboard are not certified.

## Executed verification

| Evidence | Result |
| --- | --- |
| Relevant Node regressions | 967/967 across52 files, zero failed/skipped;36 additional cases versus Phase3D |
| Actual React component / synthetic HTTP in Edge | 25/25; zero page exceptions or external requests |
| In-app browser | Separate read-only modal/work/EN–AR–EN checks PASS |
| TypeScript | PASS |
| Isolated optimized Next16.3.5 webpack build | PASS; dummy loopback configuration, no real environment file |
| Disposable PostgreSQL17.11 fresh / real pre-V3 upgrade | Both full runners PASS;95 ordered original migrations, Export Reader excluded |
| Counted SQL assertions/groups | 1107 fresh /1120 upgrade;337 preserved function contracts each;2 additional execution/downtime rollback suites each |
| Concurrency/deadline scenarios | 25 plus1 gate-preservation probe per path |
| Actual handler/client/SQL HTTP scenarios | 134 /413 RPC calls per path; includes33 integrated /161 RPC calls |
| Phase4B client integration added | Four per path: lost-response persisted intent/one stock-source credit, committed recovery, exact UUID retry/changed-intent protection, real SQL disabled-gate rejection |
| History traversal | 5010 unique rows /51 bounded pages per path |
| Final gate/cleanup | FALSE/schema0; Maintenance FALSE; owned PostgreSQL processes/data removed and ports released |

Test categories are not added into a single inflated total. Actual handlers, installed client and SQL run with local fixture Auth/PostgREST/Deno transports, not real hosted GoTrue/JWT renewal/schema-cache/browser-to-Supabase acceptance. Browser tests exercise the real React component with a bounded synthetic HTTP adapter, separately from real SQL integration. Uncommitted environment configuration points to hosted TESTING and was deliberately not used to start a write-capable localhost3000 application.

The final receipt-layout/focus refinements and authentication-error translations touch TSX/CSS/dictionaries only and are rechecked by Node/browser/TypeScript/build. SQL-exercised API/client/helper/migration inputs remain identical. The browser harness's asynchronous acknowledgment wait and screenshot transition settling do not change SQL evidence. Earlier diagnostic selector/race failures are superseded by passing runs and are not counted as PASS.

Evidence outside Git:

- Browser results/screenshots: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Phase4B-Visual-b3be6a68-8d47-4252-8eda-415a23227e9f` (final paths recorded in the final preservation evidence).
- Full fresh SQL: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Acceptance-M3D-60876237ea5042fd9c9891af32a5a31a\results`.
- Full upgrade SQL: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Acceptance-M3D-300861a9bccb4fe79d6b88f70f08cf68\results`.
- Isolated build: `C:\Users\Temp\AppData\Local\Temp\FactoryLean-Phase4B-Build-a0ee49a6f8ba405ba65a125839037327`.
- Prototype reproduction: `%TEMP%\FactoryLean-Phase4B-prototype-language.json`; final visual lint reports: `%TEMP%\FactoryLean-Phase4B-lint-*-final.json`.
- Final manifest, preservation, Node and typecheck evidence: `%TEMP%\FactoryLean-Phase4B-Final`.

The isolated component server is loopback4190 (`tests/production-recording-ui/preview.mjs`), intentionally synthetic and visibly labelled. It may remain running for owner visual review. It is not the authenticated application, a new operational writer or a hosted acceptance claim.

## Complete task file manifest

Modified existing files (12):

1. HANDOFF.md
2. src/app/api/data/route.ts
3. src/app/layout.tsx
4. src/components/FactoryApp.tsx
5. src/components/ui.tsx
6. src/features/FactoryFloorV2.tsx
7. src/features/ProductionRecording.tsx
8. src/features/types.ts
9. src/locales/en.json
10. src/locales/ar.json
11. tests/production-acceptance-precision.test.mjs
12. tests/production-acceptance/integrated.mjs

New files (21):

1. docs/design/APPROVED_APPLICATION_UI.md
2. docs/production-recording-v3-phase4b.md
3. src/features/ProductionRecordingV3.tsx
4. src/features/production-recording-v3.css
5. src/services/production-recording-client.ts
6. src/styles/design-tokens.css
7. src/utils/production-recording-intent.mjs
8. tests/production-recording-ui.test.mjs
9. tests/production-recording-ui/browser.mjs
10. tests/production-recording-ui/fixture.tsx
11. tests/production-recording-ui/preview.mjs
12. public/fonts/inter-LICENSE.txt
13. public/fonts/inter-latin-400-normal.woff2
14. public/fonts/inter-latin-500-normal.woff2
15. public/fonts/inter-latin-600-normal.woff2
16. public/fonts/inter-latin-700-normal.woff2
17. public/fonts/ibm-plex-sans-arabic-LICENSE.txt
18. public/fonts/ibm-plex-sans-arabic-arabic-400-normal.woff2
19. public/fonts/ibm-plex-sans-arabic-arabic-500-normal.woff2
20. public/fonts/ibm-plex-sans-arabic-arabic-600-normal.woff2
21. public/fonts/ibm-plex-sans-arabic-arabic-700-normal.woff2

No unrelated file is added to this scope. Existing dirty files are not thereby attributed to Phase4B. PRODUCT_DIFFERENTIATORS was reviewed: connecting an already verified recording backend to its approved UI adds no evidenced competitive claim, so its prior content was preserved.

## Deferred boundary and next authorized scope

No new correction submission/approval UI, global redesign, Phase4D final acceptance, hosted deployment, activation, credential recovery or Git operation. Existing History corrections retain their protected backend semantics. No permissions, account membership, operational records, saved Lean/Loss results or remote environments were changed.

Smallest Phase4C scope: use existing protected correction/reporting APIs to submit a reasoned proposal from Production History and provide one paginated **Production → Corrections & Approvals** destination. Separate submitter and effective approver actions; preserve pending-versus-official values, individual/package permissions, expected revisions, immutable UUID recovery and idempotent decisions. Reuse the approved dialog/drawer language, EN/AR/RTL and mobile patterns. Do not move the primary queue under Quality. Separately authorize capability-publication SQL before enabled completed-job acceptance. **STOP after Phase4B; do not begin either dependency automatically.**


## 2 November 2026 — authoritative-save completion
Ordinary confirmed saves acknowledge the exact immutable intent and close with a small toast. Sequential summary/report fetches no longer block ordinary success; current quantities refresh asynchronously. Unknown/failed results retain their protected recovery path. Save & End retains a committed recording and completion-only retry after a finish failure. Current/Previous selection replaces the repeat checkbox; previous occurrences use the separate inactive approval path, not ordinary late admission. See [approval contract](historical-production-approval-v1.md) and [consolidated evidence](e2e-acceptance-consolidated-fixes.md).
