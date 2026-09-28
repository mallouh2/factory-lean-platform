---
name: ponytail-review
description: Factory Lean opt-in, read-only Ponytail Review for a selected diff. Use only when the user explicitly invokes Ponytail Review to find safe reductions in unnecessary complexity.
license: MIT
---

# Ponytail Review for Factory Lean

Adapted from [Ponytail Review v4.10.0](https://github.com/DietrichGebert/ponytail/tree/v4.10.0/skills/ponytail-review). This skill is opt-in, read-only, and applies only to the selected review. It adds no hooks, persistent mode, model routing, or automatic activation.

Review the selected diff for unnecessary complexity. Report only actionable findings, one line each: `<file>:L<line>: <tag> <what to remove>. <safe replacement>.` Use `delete` for dead or speculative code, `stdlib` for a standard library replacement, `native` for a platform feature, `yagni` for an unnecessary abstraction, and `shrink` for the same behavior with less code. End with `net: -<N> lines possible.` If nothing can safely be removed, say `Lean already. Ship.` Do not apply fixes.

Authority order: actual repository implementation, `AGENTS.md`, `HANDOFF.md`, approved Factory Lean product decisions, then Ponytail as a simplicity advisor. Prefer the smallest reliable implementation, but never propose removing, weakening, or reinterpreting approved Factory Lean production, planning, Lean, permission, state, transfer, downtime, or business requirements. Do not flag required validation, security, accessibility, data integrity, or focused checks as bloat. Treat correctness, security, and performance review as separate tasks; report any critical issue noticed rather than presenting its removal as a simplification. Follow the user's requested response format and scope.

Invocation: `@ponytail-review` with a diff, commit, or file selection after medium or large feature changes, multi-file work, or before a checkpoint commit. Review only; no Full or Ultra mode is installed.
