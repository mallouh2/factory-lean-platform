# Disposable local preview owner authorization

27 October 2026 — **COMPLETE for shared local fixtures; no hosted change.**

## Confirmed cause

The 4222 application uses test-only Auth/Data adapter 4304 and PostgreSQL `127.0.0.1:55496`, database `factory_lean_quality_local`. The server's actual data directory was independently matched to the owned temporary runtime before writes. The existing account `PlanningV3@local.invalid` / `53d045ae-2bfe-4acb-8b98-e0e4b11dc81e` has approved owner membership in factory `3ab24bb6-654e-40ab-a8bd-e0c8ca5c62c8` (Planning V3 local factory). Its role_id is null; authority comes from actual grants, not a displayed title. All **102/102 defined permissions** were already direct and effective; package assignments are zero, and effective permission resolution still uses the normal direct/package union.

The shared protocol adapter had a short hardcoded RPC list. It rejected legitimate calls such as `create_sales_order` with HTTP403 / `42501: Local fixture RPC not allowed` before the unchanged protected SQL function ran. Its table list also covered only seven tables. Earlier preview-specific list patches were not in the shared initializer, so fresh previews reproduced the problem. A second protocol gap treated JSON arrays as PostgreSQL array-literal strings; this broke direct-grant/package command parameters (`expected_direct`, `packages`) independently of actual authority.

## Permanent shared correction

- `tests/production-recording-full-app/backend.mjs` now discovers the existing **public** RPC contract using authenticated SQL EXECUTE grants. It does not expose private functions or add database grants. Every operation still executes under the actual authenticated fixture actor/SQL role and original factory/person/package/stock/state checks. Mutating GET calls return405; protected writes require POST.
- Public table reads require existing authenticated SELECT grants and execute with original RLS. Projection, filters, ordering and paging remain bounded/validated. No direct table-write API or service-role business shortcut was added.
- `local-policy.mjs` validates the explicit disposable marker, temporary root, loopback URLs/ports, database name and actual server data directory. Every writing transaction independently rechecks the target before switching to the authenticated role. A loopback proxy to a hosted database cannot satisfy the owned data-directory contract.
- On **first credential-file creation**, initialization idempotently fills the designated approved owner's direct grants using the existing `user_permissions` model, mirroring the existing owner-creation trigger. It never creates users or changes memberships/packages. Only configured owners are included. Existing credential files/passwords are retained. Initialization does not run on every login/request, so deliberate permission revocation remains effective.
- Planning's preview preparer now launches the shared adapter directly, removing its one-off list patch. Other already-running previews were not restarted or altered. New previews using this shared preparation inherit the correction automatically.

This remains a bounded standalone Auth/Data test adapter, not a claim of complete GoTrue/PostgREST/Storage/Edge emulation. Production authorization and application source are unchanged.

## Actual verification

Normal browser login verified the existing owner ID and exact factory. Successful authenticated API/browser checks:

1. Sales creation and approval: `create_sales_order`, `approve_sales_order`, both HTTP200.
2. Eligible internal Production Request creation: HTTP200.
3. Planning V3 manual form scheduling: protected `plan_product_item` HTTP200, persisted line/start/finish.
4. Permitted future replan: `revise_product_plan` HTTP200, meaningful reason and recorded history.
5. Planning drag-event path: browser DataTransfer events invoked existing drag handlers and protected SQL, HTTP200 on the existing capable Extrusion line. Native pointer automation across the tall scrolling page was inconclusive; no native-pointer success is claimed for this run. Occupied Printing correctly rejected placement before SQL; no job was finished or moved to force a slot.
6. Existing active work recorded **2 Meter Good, 0 WIP, 0 Scrap KG** through the protected V3 writer, HTTP200.
7. Valid Quality inspection/release and a physical two-meter Warehouse receipt, HTTP200 each. Final source has quantity_credited/available/identified2, actual Production Item/entry/shift genealogy and exactly **one RECEIPT event**. No duplicate stock credit.
8. Physical source identification and an eligible one-meter Sales source reservation, HTTP200. No existing commitment was changed merely to force a result.
9. Protected permission-package administration read HTTP200, and a valid existing settings save HTTP200. The same owner legitimately performs this manufactured-output Quality inspection under current rules; independent Maintenance verification was not exercised or bypassed.

Security and lifecycle evidence:

- Existing restricted worker's creation attempt HTTP403 / SQLSTATE42501.
- Owner targeting a known different local fixture factory HTTP403; cross-factory table read returns an empty array.
- Protected temporary factory-scoped `orders:create` grant via the established direct-grant command made `can_access` true; restoring the original grants made it false immediately, and the next write returned403. Original restricted grants were restored; audit records were retained.
- The allowed alternative of **reinitializing the existing disposable fixture twice** was tested. User count stayed10, owner direct/effective grants stayed102, and restricted permissions stayed unchanged. No second database/account was created. No duplicate grants or users.
- Business record/revision digests stayed unchanged across denied and grant/revoke checks. Mutating GET returned405 without a new record.
- Five focused policy tests and Node syntax checks PASS. Final owner run reports no page errors. Separate authenticated Sales/Planning/Quality/Warehouse/Settings reads report no page errors; the initial unauthenticated `/api/data`401 before normal login is expected. One earlier intermediate browser run observed `Invalid time value`; it was not reproduced in the final owner run or separate read checks. It was not attributed to permissions or patched in application code.
- No TypeScript/build rerun: no application source changed. Prior Planning V3 evidence remains separately dated and intact.

## Runtime and handoff

Working preview: **http://127.0.0.1:4222/**. Same existing owner and unchanged password. Credentials remain outside Git in:

`C:\Users\Temp\AppData\Local\Temp\FactoryLean-Planning-V3-eb89d4f1b7da423d954a0d2aec33dca2\LOCAL-LOGIN.txt`

The owner-restricted `owner-permissions-fix` directory within that runtime retains before-file hashes, original adapter copies, acceptance requests/results, security/reinitialization results, final source evidence and final read checks. Completed write scenarios must not be replayed blindly. After this adapter update, an older open tab may need normal sign-out/sign-in because this existing local auth shim keeps sessions in process memory; no password reset occurred.

Changed files: shared `backend.mjs`; new shared `local-policy.mjs`, `owner-acceptance.mjs`, `owner-security.mjs`; `tests/local-preview-policy.test.mjs`; Planning `prepare-preview.ps1`; shared preview README; this report; `HANDOFF.md`.

All112 migration bytes, application/Planning design, Design System and unrelated dirty work are preserved. Manufactured-output shipped capability remains FALSE; completed-shift late recording FALSE/schema0. The already-existing disposable manufactured helper simulation remains test-only. Port4221, earlier previews and localhost3000 were not changed. No hosted access, deployment, Git write, commit or push. **STOP: no overdue-rescheduling SQL, Planning redesign, main-environment consolidation or checkpoint.**
