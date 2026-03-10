# WorshipFlow Codex Context

This file gives Codex persistent repository context for the WorshipFlow project.

It is a high-level working context file.
It does not replace `AGENTS.md`.
It complements `AGENTS.md` by summarizing the current repository reality, current development stage, architecture boundaries, and safe working rules.

---

## 1. Repository Identity

Project: WorshipFlow

WorshipFlow is a live worship-service control system built around a LiveCue runtime engine.

Core product capabilities include:

- admin → team → project navigation
- setlist management
- cue sequencing
- live cue state control
- drawing / notation support
- release-gate based validation workflow

This repository is already beyond early MVP stage.
It is currently in **pre-release validation / release gate execution stage**.

---

## 2. Mandatory Reading Order

Before doing any task, always read in this order:

1. `AGENTS.md`
2. `docs_index.md`
3. `docs/product_development_map.md`
4. `plan.md`

Use these roles:

- `AGENTS.md`
  - repository-wide agent rules
- `docs_index.md`
  - document structure map
- `docs/product_development_map.md`
  - overall product development state
- `plan.md`
  - execution baseline and current SP state

If documentation and code disagree:

**Code is the source of truth.**

Update documentation instead of assuming documentation correctness.

---

## 3. Current Development Stage

Current SP status:

- SP-01 complete
- SP-01A complete
- SP-02 complete
- SP-03 complete
- SP-04 implementation complete / real-device evidence pending
- SP-05-1 complete
- SP-05-2 complete
- SP-05-3 complete
- SP-05-4 complete
- SP-06 complete
- SP-07 in release-gate / pre-release audit stage

Current stage summary:

**Release Candidate / Pre-Release Validation**

This means:

- core engine work is complete
- product feature work is complete
- runtime safety work is complete
- release readiness, device validation, and deployment decision are the current priorities

Do not behave as if this is an early feature-building phase.
This repository is in stabilization and release-readiness mode.

---

## 4. Product Status Overview

Rough progress snapshot:

- Engine development: 100%
- UX stabilization: 100%
- Real-device stabilization: 70%
- Product features: 100%
- Runtime safety: 100%
- Collaboration layer: 0%
- Release preparation: in progress

Interpretation:

- The core product is built
- Runtime protection exists
- The remaining critical work is:
  - SP-04 real-device evidence
  - SP-07 release gate execution
  - post-gate deployment decision
  - later collaboration work

---

## 5. Architecture Boundaries

LiveCue architecture is split into 4 responsibilities:

- Sync Layer
- Render Layer
- Input Layer
- Persistence Layer

Core engine files:

- `lib/features/projects/live_cue_sync_coordinator.dart`
- `lib/features/projects/live_cue_page.dart`
- `lib/features/projects/live_cue_stroke_engine.dart`
- `lib/features/projects/live_cue_note_persistence_adapter.dart`

Important principle:

Do not casually blur these boundaries.

UI should not become the owner of state interpretation that belongs to engine/runtime layers.

Do not re-implement current/next resolution logic inside random UI code.

---

## 6. Canonical Firestore Paths

Canonical paths include:

- `teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}`
- `teams/{teamId}/projects/{projectId}/liveCue/state`
- `teams/{teamId}/projects/{projectId}/sharedNotes/main`
- `teams/{teamId}/userProjectNotes/{noteId}`
- `users/{uid}/ClientProbe/mobile`

Do not invent parallel structures unless explicitly requested.

Do not migrate canonical structures casually.

Any path-related change must be treated as architecture-sensitive.

---

## 7. Runtime Safety Context

Runtime safety already exists in this repository.

Important files:

- `lib/core/runtime/runtime_guard.dart`
- `lib/core/ops/ops_metrics.dart`

Important protections already exist:

- router parameter guard
- setlist integrity guard
- liveCue state validation
- host-viewer init payload validation
- observability metrics

Important metrics include:

- `runtime_guard_triggered`
- `livecue_state_invalid`
- `setlist_order_invalid`
- `router_invalid_id`
- `firestore_snapshot_error`

Do not remove or weaken runtime observability.

If you add new runtime-critical behavior, ensure the system remains observable.

---

## 8. Release Gate Context

Release-gate policy is defined mainly in:

- `plan.md`
- `docs/release_runbook.md`

SP-07 is not a feature-expansion phase.

SP-07 is about:

- release readiness confirmation
- static validation
- functional gate verification
- runtime safety gate verification
- device validation resumption scope
- first-error / regression loop readiness
- fallback operations policy
- large-file change governance

If asked to help with SP-07, bias toward:

- audits
- documentation alignment
- operational readiness
- test/readiness checklists

Do not treat SP-07 as “build new features.”

---

## 9. Large File Governance

The following files are high-risk / large files:

- `lib/features/projects/live_cue_page.dart`
- `lib/features/teams/team_home_page.dart`
- `lib/features/admin/global_admin_page.dart`

Rules:

- do not rewrite them completely
- prefer small functional-unit edits
- add tests when touching high-risk paths
- runtime-safe changes first
- avoid speculative cleanup in large files
- do not mix unrelated edits in one change

---

## 10. Safe Working Rules

Always prefer:

- minimal safe changes
- architecture-respecting changes
- documentation alignment
- explicit validation
- deterministic state handling

Avoid:

- broad refactors without request
- changing canonical data structures
- weakening runtime guards
- adding hidden fallback logic
- introducing state ownership confusion
- rewriting large files for convenience

---

## 11. Validation Requirements

After code changes, run:

- `flutter analyze`
- `flutter test --reporter=compact`
- `bash scripts/ci/test_rules.sh`

If any of these fail, the task is not complete.

For documentation-only tasks, code validation is not required unless code was changed.

---

## 12. Typical Task Classification

When a task comes in, classify it first:

### A. Feature implementation
Examples:
- setlist improvements
- collaboration layer
- admin product flow additions

### B. Runtime stability
Examples:
- guards
- validation
- observability
- fallback behavior

### C. Release gate / operations
Examples:
- readiness audit
- release checklist
- incident / runbook update
- device validation planning

### D. Documentation update
Examples:
- `plan.md`
- runbooks
- roadmap
- docs index updates

Always determine category before changing anything.

---

## 13. Release-Stage Risk Awareness

Current known release-stage risks:

- SP-04 real-device evidence still pending
- iPad Apple Pencil long-session validation pending
- iPhone rotation + drawing validation pending
- iOS shared-layer real-device validation pending
- iOS local Google login re-verification pending
- global admin can enter team views, but some project reads may still be limited by rules
- fallback path must not drift into primary default behavior

Treat these as real release concerns, not theoretical notes.

---

## 14. Fallback Policy Reminder

Next Viewer is a fallback / support path.

It is not the primary engine.

Fallback is allowed only when:

- canonical path shows reproducible failure
- platform-specific rendering issue is confirmed
- host-viewer contract validation passes

Fallback is not allowed merely for convenience or preference.

Do not silently push users onto fallback paths.

---

## 15. Expected Response Style

When working on tasks, structure the response like this:

1. Context summary
2. Plan
3. Implementation (if required)
4. Validation steps
5. Risk notes

This keeps work aligned with repository conventions and makes audits easier.

---

## 16. Practical Working Summary

When unsure, remember:

- Read the 4 core context docs first
- Trust code over docs
- Protect architecture boundaries
- Do not casually touch large files
- Preserve runtime safety
- Release readiness matters more than feature expansion right now

This repository is not in prototype mode.
It is in stabilization and release-readiness mode.