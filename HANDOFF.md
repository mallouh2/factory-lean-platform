# Factory Lean — Current Handoff

Updated 2026-09-29 (Asia/Riyadh). Authoritative checkout: `C:\Users\Temp\Documents\GitHub\factory-lean-platform`. Read `AGENTS.md` and inspect the repository before continuing; this is a snapshot, not a substitute for code or live database state.

## Milestone and Git state

- Planning V2 is frozen and pushed. Production Execution V2 Phase 1 passed freeze review, was manually accepted by the user, and is frozen and pushed at `f8503d033ce6e67687ccc37566769f09457311da` (`feat: add production execution v2 phase 1`).
- Branch `main` and remote `main` include the Production Execution V2 Phase 1 checkpoint. The project-context documentation is a separate checkpoint; preserve the local Machine Management work when committing or pushing it.
- Six legitimate, uncommitted **Machine Management** files remain: `src/app/globals.css`, `src/features/CenterAlternatives.tsx`, `src/features/Configuration.tsx`, `src/features/LineBuilder.tsx`, `src/locales/en.json`, and `src/locales/ar.json`. They group machine editor fields, clarify alternatives with line/category context, adjust empty state/action hierarchy and RTL arrows, and update EN/AR text. Preserve and review them as separate work; they are not part of the Execution checkpoint. No untracked files were present at this audit.

## Database state

- Local migration files: **31**, through `20260928091903_keep_planning_after_actual_start.sql`.
- TESTING `silmfbpjyepalnggwulp`: **31 applied**, matching the Local migration versions, including both Execution Phase 1 forward migrations.
- DEV `jjcvfysjmqimvnumxasm`: **11 applied**, through `20260916135000_platform_session_continuity`; intentionally behind. Do not reconcile or push DEV without a separate explicit request. Recheck all histories immediately before any future database push.

## Verified behavior and limits

- Execution uses persisted Planning order and database guarded Start/Finish commands. Planned timestamps remain planning truth; actual start/finish are recorded separately with server time. The database enforces one active item per line. Execution leaves later plans, machine physical states, and transfers alone. Factory Floor exposes ready/active/next items and Production Request details show Plan vs Actual.
- Focused checks reported at the checkpoint: 122/122, TypeScript, and `git diff --check` passed. Earlier rollback-only TESTING SQL covered permissions, order, line activity, transitions, timestamps, and Planning history. TESTING browser checks covered Start/Finish, retained plans, next-item readiness, borrowed-machine display, and EN/AR duration/variance. The user manually accepted Phase 1; broad release review remains separate.
- The shared duration formatter covers Planning, Smart Slot, Factory Floor, request variances, downtime, and reports. Smart Slot can show stale suggestions after an external schedule change; saving revalidates. Historical planned items can overlap or fall outside the factory's newer working calendar; their stored plans are not silently moved.
- The two old TESTING demo items `PO-2026-001` and `PO-2026-002` were reconciled with user authorization during Phase 1 testing. Subsequent user testing changed visible item states. Treat TESTING contents as live and inspect before assuming either item's current status. DEV was not touched during this documentation task.

## Exact next task

1. Begin **Downtime Capture V1 discovery**, not implementation. Identify operator/technician and Production Engineer decisions; research relevant industrial products before final requirements. Approved direction: fast mobile first stoppage capture with initial reason Mechanical, Electrical, Material, Quality, Setup, or Other; a Production Engineer later reviews/approves the final reason or root cause. Retain the initial reason for audit and base future Lean reporting primarily on the approved cause.
2. Review the separate local Machine Management edits before any future checkpoint. No new migration push is needed for TESTING. Verify Local, TESTING, and DEV histories before any later database push.

Recommended model for the Downtime Capture discovery and subsequent normal feature design: **GPT-6 Sol Medium**. Escalate to Sol High for critical database transition or permission implementation. Start with discovery before implementation.
