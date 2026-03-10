# AGENTS.md — WorshipFlow Repository Guide

Scope: This file governs the entire repository.

This document provides context and rules for AI coding agents such as Codex, Cursor, Copilot, and other automated development tools.

---

# 1. Reading Order (MANDATORY)

Before performing any task, agents MUST read the following documents in order:

1. docs_index.md  
2. docs/product_development_map.md  
3. plan.md  

Purpose:

docs_index.md  
→ explains repository documentation structure

product_development_map.md  
→ explains overall product development status

plan.md  
→ defines the execution baseline and SP stages

If documentation conflicts with code:

**CODE IS THE SOURCE OF TRUTH**

Update documentation instead of assuming documentation correctness.

---

# 2. Project Overview

Project name: WorshipFlow

WorshipFlow is a live worship service control system.

Core responsibilities:

- setlist management
- cue sequencing
- live drawing / notation system
- admin → team → project operational flow
- real-time LiveCue state control

The system is built around a **LiveCue runtime engine**.

---

# 3. Architecture Overview

LiveCue architecture is split into four responsibilities:

Sync Layer  
Render Layer  
Input Layer  
Persistence Layer

Core engine files:

lib/features/projects/live_cue_sync_coordinator.dart  
lib/features/projects/live_cue_page.dart  
lib/features/projects/live_cue_stroke_engine.dart  
lib/features/projects/live_cue_note_persistence_adapter.dart  

Never break this separation without strong justification.

---

# 4. Canonical Firestore Structure

Canonical data paths:

teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}

teams/{teamId}/projects/{projectId}/liveCue/state

teams/{teamId}/projects/{projectId}/sharedNotes/main

teams/{teamId}/userProjectNotes/{noteId}

Agents must NOT introduce new parallel structures unless explicitly requested.

---

# 5. Current Development Stage

See plan.md for authoritative status.

Current state summary:

SP-01 App Foundation → complete  
SP-02 LiveCue Sync Core → complete  
SP-03 LiveCue Engine Separation → complete  
SP-04 Runtime Stability → implementation complete, device validation pending  
SP-05 Product Features → complete  
SP-06 Runtime Guards → complete  
SP-07 Release Gate → ready to execute

Current repository stage:

**Pre-Release Validation**

---

# 6. Runtime Safety System

Runtime safety is implemented through guards and metrics.

Key components:

runtime_guard.dart  
ops_metrics.dart  
router guards  
setlist integrity guard  
liveCue state validation  
host-viewer init validation

Key metrics:

runtime_guard_triggered  
livecue_state_invalid  
setlist_order_invalid  
router_invalid_id  
firestore_snapshot_error

Agents must preserve runtime observability.

---

# 7. Large File Governance

These files are considered large / sensitive:

lib/features/projects/live_cue_page.dart  
lib/features/teams/team_home_page.dart  
lib/features/admin/global_admin_page.dart  

Rules:

- Avoid full rewrite
- Modify only the necessary functional section
- Never introduce architectural rewrites casually
- Tests required for major changes

---

# 8. Validation Requirements

After any code change agents MUST run:

flutter analyze

flutter test --reporter=compact

bash scripts/ci/test_rules.sh

If any step fails, the task is incomplete.

---

# 9. Release Gate

Release validation is defined in:

docs/release_runbook.md

Release checks include:

Static validation
- flutter analyze
- flutter test
- Firestore rules tests

Functional validation
- admin → team → project navigation
- setlist CRUD
- reorder
- cue move

Runtime validation
- runtime guard metrics
- router validation
- liveCue state integrity

---

# 10. First-Error Protocol

A first-error event is the first critical runtime issue in a session.

Priority order:

1 livecue_state_invalid  
2 setlist_order_invalid  
3 router_invalid_id  
4 firestore_snapshot_error  

When discovered:

1 record timestamp  
2 record device/browser/build  
3 record reproduction steps  
4 capture logs  
5 attach screenshot/video evidence

---

# 11. Fallback Policy

Next Viewer is a fallback path, not the primary engine.

Fallback allowed when:

- canonical runtime fails
- platform rendering issue confirmed
- host-viewer contract validated

Fallback forbidden when:

- canonical path is healthy
- fallback used for convenience only

---

# 12. Coding Guidelines

Prefer minimal safe changes.

Avoid large structural rewrites.

Follow existing architecture.

Do not introduce new frameworks.

Maintain deterministic behavior in state handling.

---

# 13. Agent Response Format

Agents should respond using this structure:

1 Context summary  
2 Plan  
3 Implementation (if required)  
4 Validation steps  
5 Risk notes

---

# 14. Key Principle

WorshipFlow prioritizes:

Runtime safety  
Operational stability  
Predictable state handling  

Feature expansion is secondary to runtime reliability.