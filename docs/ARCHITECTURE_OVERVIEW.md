# WorshipFlow Architecture Overview

## Purpose

This document provides a high-level overview of the WorshipFlow system architecture.

It helps developers, reviewers, and AI agents quickly understand how the system is structured.

---

# System Overview

WorshipFlow is a real-time worship service control system built around the **LiveCue runtime engine**.

Core responsibilities

- setlist management
- cue sequencing
- shared annotations
- live session synchronization
- team based project management

Primary platforms

- Web (primary)
- iPad (Apple Pencil support)
- Mobile browser

---

# Core Architecture

The LiveCue engine follows a layered architecture.

```
Input Layer
↓
Render Layer
↓
Sync Layer
↓
Persistence Layer
```

---

# Input Layer

Handles user interactions.

Examples

- Apple Pencil input
- touch gestures
- cue navigation
- annotation drawing

Responsibilities

- capture input events
- translate into stroke operations
- pass events to rendering system

---

# Render Layer

Responsible for displaying LiveCue content.

Responsibilities

- cue display
- annotation rendering
- setlist UI
- visual synchronization

Important file

```
live_cue_page.dart
```

---

# Sync Layer

Handles multi-user synchronization.

Responsibilities

- real-time state updates
- viewer/host communication
- Firestore snapshot listeners
- session state reconciliation

Important file

```
live_cue_sync_coordinator.dart
```

---

# Persistence Layer

Handles storage and retrieval.

Primary storage

Firestore

Key collections

```
teams/{teamId}/projects/{projectId}/segmentA_setlist
teams/{teamId}/projects/{projectId}/liveCue/state
teams/{teamId}/projects/{projectId}/sharedNotes
teams/{teamId}/userProjectNotes
```

Reference

```
data_model.md
firestore_rules.md
```

---

# Runtime Safety

WorshipFlow includes runtime guards to prevent invalid states.

Primary components

```
runtime_guard.dart
ops_metrics.dart
```

Responsibilities

- detect invalid LiveCue states
- validate router parameters
- detect Firestore snapshot failures
- emit operational metrics

Example metrics

```
runtime_guard_triggered
livecue_state_invalid
setlist_order_invalid
router_invalid_id
firestore_snapshot_error
```

---

# Navigation Flow

Primary navigation path

```
Global Admin
↓
Team
↓
Project
↓
LiveCue
```

Key files

```
global_admin_page.dart
team_home_page.dart
live_cue_page.dart
```

Router guards ensure invalid IDs cannot crash the app.

---

# Large File Governance

Some files are intentionally large due to UI complexity.

High-risk files

```
live_cue_page.dart
team_home_page.dart
global_admin_page.dart
```

Rules

- avoid full rewrites
- modify by functional unit
- preserve runtime guards

---

# Release Safety

Production release is gated by:

```
docs/ops/release_checklist.md
docs/ops/device_validation.md
docs/ops/incident_response.md
```

These documents define:

- release validation
- device testing
- incident handling

---

# Current Development Stage

Current stage

```
Release Candidate
```

SP progress

```
SP-01 → SP-03 complete
SP-04 implementation complete (device validation pending)
SP-05 feature complete
SP-06 runtime safety complete
SP-07 release gate pending
```

---

# Summary

WorshipFlow architecture prioritizes

- runtime safety
- deterministic state handling
- real-time synchronization
- minimal UI state ownership

The system is designed for **stable live service operation** rather than rapid feature experimentation.