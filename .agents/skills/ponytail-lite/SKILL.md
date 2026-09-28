---
name: ponytail-lite
description: Factory Lean opt-in Ponytail Lite for a coding task. Use only when the user explicitly invokes Ponytail Lite; implement the approved request fully, then mention a simpler alternative in one line if one exists.
license: MIT
---

# Ponytail Lite for Factory Lean

Adapted from [Ponytail v4.10.0](https://github.com/DietrichGebert/ponytail/tree/v4.10.0/skills/ponytail), Lite intensity only. This skill is opt-in for the current task. It adds no hooks, persistent mode, model routing, or automatic activation.

Read the task and the relevant existing code before choosing an implementation. Build everything the user approved. Prefer the smallest reliable implementation that meets the full requirement. Reuse existing code, standard library, native platform features, and installed dependencies where appropriate; avoid speculative abstractions and new dependencies when a small local solution works. Fix the root cause and leave an appropriate focused check for nontrivial logic.

Ponytail Lite's distinguishing behavior: after completing the requested work, name a simpler alternative in one line if a valid one exists, and let the user choose. Do not substitute that alternative for the approved requirement or delay the work to ask about it.

Authority order: actual repository implementation, `AGENTS.md`, `HANDOFF.md`, approved Factory Lean product decisions, then Ponytail as a simplicity advisor. Prefer the smallest reliable implementation, but never remove, weaken, or reinterpret approved Factory Lean production, planning, Lean, permission, state, transfer, downtime, or business requirements in the name of simplification. Preserve security, validation, accessibility, data integrity, and required tests. Follow the user's requested response format and scope, even when it is longer than Ponytail's usual output.

Invocation: `@ponytail-lite` with a small bug fix, bounded UI task, minor refactor, small utility, or simple API/frontend fix. The skill applies only to that request; no Full or Ultra mode is installed. Do not use an aggressive simplicity mode on the flow engine, permissions/RLS, transfers, Planning core state, downtime/root-cause workflow, Lean business logic, or architecture without explicit user direction.
