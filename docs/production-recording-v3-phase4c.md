# Production Recording V3 — Phase 4C

20 October 2026. **LOCAL COMPLETE; owner review and hosted acceptance pending.** Phase4A/4B and simplified History were approved by the Phase4C authorization. Older reports retain their historical acceptance status.

## Delivered workflow

Production History → select one entry → Actions → Request Correction. The focused dialog reads a fresh, complete protected entry snapshot; shows official/proposed Good in the configured unit and Scrap KG; and requires one editable reason (3–2,000 characters). Six suggestions fill the same field. Supporting WIP/remaining work, discarded processing quantity, existing startup Scrap and explicit source allocation remain conditional. Zero-WIP entries offer Other quantities on demand. No shift/occurrence retiming UI or new posting logic was introduced.

Orders view plus edit OR approve controls submission. An ordinary submitter receives Pending Approval with unchanged official quantities. Effective Orders approve uses the existing atomic self-approval contract. Current individual/package grants remain SQL truth; no role/title-based authorization. Production → Corrections & Approvals provides Pending/Approved/Rejected/My Requests, six columns, single selection and one toolbar Actions menu. Completed rows compare original-at-request with actual applied/proposed values; pending rows compare current official values. Decision Details shows current/proposed quantities, exact differences, reason, requester and original-at-request values on demand. Rejection uses the existing required explanation. Mobile rows stack into labelled cards; EN/AR/RTL, native dialog/keyboard behavior and Phase4A tokens are retained.

Pending count is reused only from an already loaded pending query; no separate polling. My Requests is SQL-own-scoped for ordinary submitters; approvers filter their authorized loaded pages locally and use Load more for further pages. This avoids an unnecessary new query contract. A requester outside the existing authorized technician-name catalogue is shown as unavailable; no employee-permission bypass or invented name.

## Minimal read extension and retry safety

Forward migration **20261020150000_production_correction_context.sql** adds only a read wrapper over existing private.production_correction_values and the existing protected reporting projection/authorization. The existing reporting response omits startup KG/remaining-work text and the existing request reader needs a submitted request; a lossless, atomic draft needs this wrapper. Exact decimals and revision are returned together with identity. Empty pinned search_path, explicit factory filter, existing correction authorization, authenticated-only grant and revoked anonymous/public execution. No writer, approval, source, gate or historical migration changed. Applied only to disposable localhost PostgreSQL. There are98 local migration files; the original97 bytes, including Export Reader, are preserved. Remote history is not verified or changed.

Existing /api/production-corrections GET accepts a strict context_entry read and decorates queue rows with bounded same-factory RLS metadata reads. POST/SQL remains the existing protected submit/approve/reject contract. SourceAllocationFields is reused; pooled stock remains UNATTRIBUTED and proposals reserve nothing. SQL revalidates sources, commitments and revision at approval. No inventory arithmetic is duplicated in UI.

Before a write the exact intent and UUID are retained in actor/factory-scoped sessionStorage. Uncertain responses/timeouts freeze the draft and offer protected status recovery or the same intent/UUID retry. Invalid storage fails closed. Actor/factory changes cannot reuse another scope's command. Definitive stale/permission failures show an actionable response; no automatic rebase or optimistic posting. The normal application snapshot/History refreshes after confirmed success. SessionStorage recovery is limited to the current browser tab/session, not cross-device recovery.

The approved seven-column History, no summaries/status/Actions columns, exact product/order Scrap total, Details and exports remain intact. Correcting Scrap does not approve its cause or re-review Quality/Lean evidence; existing saved Lean/Loss snapshots and immutable originals remain protected by unchanged backend rules.

## Executed verification

- **159/159 focused Node tests:** correction backend/API, complete context and RLS metadata, exact payloads, required/custom reasons, source picks, uncertain retry identity, HTTP denial/stale errors, approval-only and revoked History operations, navigation/permissions, scoped Scrap and departmental exports.
- **9 PostgreSQL checks in a rolled-back transaction:** complete exact context; technician pending; approval; stale denial; rejection; self-approval without unrelated stock/WIP postings; revoked edit authority; factory isolation; anon revocation. No fixtures/permission changes from this suite persist.
- **One actual two-connection race:** concurrent approvals of one controlled new request returned the same correction, with exactly one source/Good deduction. Original protected SQL executed with authenticated claims. Test entry 56a3a91f-096c-4fc8-a884-0259678ca5d6 retained for review.
- **One focused real Edge smoke,5 groups:** normal separate local worker/owner logins, mandatory editable reason, pending official-value preservation, queue approval, owner self-approval and History refresh, English/Arabic/390px. No uncaught page errors. Later read-only embedded-browser review uses the same full app. Chrome/Firefox, real Supabase GoTrue/PostgREST and comprehensive accessibility/hosted acceptance remain pending.
- TypeScript, final isolated optimized Next16.3.5 build and whitespace checks PASS. Build src/public inputs hashed against the current checkout. Actual browser evidence is the guarded local Auth/Data adapter plus original PostgreSQL grants/RLS, not hosted proof. Fresh full-chain installation and every inherited suite were not repeated.

Controlled fixture: one new2 Meter Good/.125 KG recording; concurrent source correction2→1.5 Meter/.15 KG; browser worker correction to.2 KG approved; owner self-correction to.3 KG. Original five recordings untouched. Final six entries:40.75 gross Meter,40.25 official Good Meter,2.20 Scrap KG,2 WIP Meter,reserved0. Stock/source credits/ledger all40.25; no duplicate Good/source posting or invented physical identification. Recording and Maintenance activation remain FALSE. Rejection/stale/revocation test transactions rolled back.

## Preview, evidence and scope

http://127.0.0.1:4207/?view=productionCorrections ; History http://127.0.0.1:4207/?view=productionHistory . Existing local preview account credentials remain outside the repository in the disposable runtime. No TESTING/Simulation credentials used. Leave local servers running for owner review.

Evidence root: C:\Users\Temp\AppData\Local\Temp\FactoryLean-Phase4C-6ab645a939244458990e82d9759bd4be (fixture.json, browser-results.json, desktop/mobile images, SQL/Node logs, conservation and preservation.json). Exact task file manifest is preservation.json. Product pattern reference: [Tulip correction guidance](https://support.tulip.co/docs/process-data-corrections-and-review) supports preserving original evidence and correction context; Factory Lean retains its explicitly approved per-person self-approval policy.

No unrelated work overwritten. No hosted access/deployment, Git writes/commit/push, new user, persisted permission change, late-recording activation or Phase4D. STOP for owner review.
