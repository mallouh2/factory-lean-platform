<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# Factory Lean project rules

## Authority and continuity

- The actual repository is implementation truth. Read this file and `HANDOFF.md` before substantial work, then inspect the current branch, HEAD, status, diff, and relevant code. Continue the exact current state; never restart completed work or discard legitimate uncommitted work.
- Use this file for durable rules and `HANDOFF.md` for the current milestone, Git/database state, limitations, and next task. Conversation and ChatGPT Project memory are helpful context only. If documentation conflicts with the repository, verify and update the documentation.
- Factory Lean is under active development. TESTING data is disposable unless explicitly preserved. Favor correct product/workflow behavior, focused tests, and user manual testing. Save broad release/security hardening for the publication stage; do not weaken business or authorization checks in the meantime. Avoid speculative abstractions and unnecessary complexity.

## Git and database safety

- Do not commit or push without explicit user authorization. Never use `git reset --hard`, `git clean`, or force push. Do not automatically rebase or merge to resolve divergence. Preserve dirty work; use selective or hunk staging when files contain multiple features.
- Make structural database changes through new forward migrations. Never edit an already applied migration to repair live behavior. Verify Local, TESTING, and DEV migration histories before any database push. Do not reconcile or push DEV unless explicitly requested in a separate task.
- Protect important state transitions at the database boundary, not only in the UI.

## Purpose and product discovery

- Factory Lean is a Lean operations product for small and medium factories, initially plastic pipe factories, not a generic ERP. Its purpose is to find where production time, output, and money are lost, determine why, and help management reduce those losses. Follow the loop: **Plan → Execute → Capture loss → Find cause → Action → Verify → Measure value → Next problem**.
- After implementing a material product capability, review `docs/PRODUCT_DIFFERENTIATORS.md`. Update it only when the change materially affects competitive differentiation, parity, or a documented competitive opportunity. Keep claims evidence-based and separate implemented capabilities from planned ideas.
- Before finalizing a new page, meaningful workflow, or substantial redesign, identify the real user and operational decision, separate essential information/actions from noise, and research comparable industrial products. Depending on the task, consider MachineMetrics, Vorne XL, Evocon, Autodesk Fusion Operations, MRPeasy, Tulip, Daftra, and other relevant products. Compare workflow, hierarchy, actions, statuses, visualizations, mobile behavior, error prevention, terminology, and KPIs. Adapt useful patterns for simple, affordable, Lean focused use by nontechnical factory staff. Report a better approach before implementation when research exposes weak or needlessly complex requirements. This research is unnecessary for trivial fixes, text, translations, spacing, and strictly bounded maintenance.
- For implementation: task → persona/product need → competitor research when relevant → final requirements → model selection → model specific prompt → implementation → focused test → user manual test → freeze review → checkpoint. Select the model before writing the final implementation prompt:
  - **GLM 5.3 Flash:** tiny bounded fixes, labels, translations, spacing, icons, small RTL/UI issues; give narrow files/steps and strict boundaries.
  - **GLM 5.3 Standard:** medium bounded or straightforward multi-file/UI tasks; give a checklist, moderate freedom, and focused tests.
  - **GPT-6 Sol Medium:** important features and moderate workflow/database logic; give product intent, invariants, acceptance criteria, architecture reuse, and room for the smallest appropriate implementation.
  - **GPT-6 Sol High:** critical state/database logic, concurrency, permissions/RLS, architecture-sensitive flows, and blockers; specify invariants, failure cases, database boundaries, and required caller/schema inspection.
  - Use Astra only if Sol High is genuinely insufficient.
- Project-local `@ponytail-lite` suits small bounded fixes, simple UI, and minor refactors; `@ponytail-review` suits feature, freeze, and checkpoint reviews. Both are subordinate to these rules, `HANDOFF.md`, and approved business logic. Never simplify away required business, state, or security behavior.

## Production and machine invariants

- `evaluateFlow` is the single source of truth for effective production flow. Physical machine state differs from production flow state. An **OPEN `production_transfer`** is assignment truth: a borrowed alternative stays borrowed, even if it stops, until the transfer is explicitly ended. Temporary borrowing never changes the machine's permanent `line_id`.
- Start/Finish Production records item execution only; it must not automatically change physical machine state or transfer lifecycle. A stopped alternative must not end its transfer.
- Every work center has `category_id`, its compatibility family. A shared category does not automatically configure alternatives; alternatives are explicit. Cross-category alternatives and transfers are invalid. Saving alternatives must never modify, delete, or reconstruct `work_center_capabilities`.
- Pause is intentional, not a stoppage. Resume restores only machines automatically idled by that pause and still eligible; it must not overwrite later manual states. The repository's flow and transfer rules govern borrowed machines returning to paused lines.

## Requests, Planning V2, and Execution V2

- One Production Request contains multiple Product Items; each item can be planned and executed independently. Required By is the customer/business deadline. Do not aggregate unlike quantities such as meters and pieces.
- Planning V2 is frozen. Planning assigns line and planned start/finish, never operator or technician. Rate, setup, and working calendar determine duration. Existing jobs never move automatically; there is no cascading reschedule. Smart Slot is advisory. Locked schedule changes follow replanning history and reason rules. Generic writes cannot bypass Planning validation.
- Execution Phase 1 separates **PLANNED = planning truth** from **ACTUAL = execution truth**. Execution never overwrites planned timestamps. Start and Finish record actual timestamps using database/server time. At most one Product Item may be active per line. The queue derives from persisted Planning schedule; execution does not reschedule later jobs. Planning lock does not block normal execution.
- Use the shared human readable duration formatter for durations, not timestamps: `45 min`, `1 h`, `1 h 30 min`, `5 h`, `1 d 1 h`. Preserve signed variance and EN/AR behavior; do not display long durations only as total minutes.

## Permissions and interface

- Authorize per person, never by job title or role alone. `View As` is a preview, not authorization. Use the existing TESTING account unless another is genuinely needed; do not casually create test accounts.
- For nontechnical factory users, favor obvious hierarchy, minimal steps, operational clarity, practical mobile use, EN/AR parity, and correct RTL. Keep configuration out of operational pages. Preserve the existing CSS architecture unless a change is justified and approved.
