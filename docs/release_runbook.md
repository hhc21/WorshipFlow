# Release Runbook (SP-07 Release Gate)

## 1. Scope
- This runbook defines release-gate checks before deployment and first-error/regression loop after deployment.
- GitHub is used for backup/recovery only.
- This runbook does not define new product features or architecture changes.

## 2. Preconditions
- `plan.md` SP-07 baseline is approved.
- No pending schema migration for canonical Firestore path (`teams/{teamId}/projects/{projectId}/...`).
- LiveCue engine structural change is not included in this release batch.

## 2.1 Evidence Record (Required Fields)
Every release-gate evidence item must include:
- timestamp (KST)
- build version (and release version if available)
- log reference (file path, console capture, or CI URL)
- screenshot/video linkage

Rule:
- A gate is not treated as fully executed until these fields are recorded.

## 3. Static Validation Gate (Required)
Run all commands and record output timestamp:
1. `flutter analyze`
2. `flutter test --reporter=compact`
3. `bash scripts/ci/test_rules.sh`

Gate rule:
- Any failure blocks release.

Evidence record:
- command execution timestamp (KST)
- build version used for verification
- command output log reference
- optional screenshot/video linkage for CI execution

## 4. Functional Gate (Web Runtime)
Required flow checks:
1. `/admin -> /teams/{teamId} -> /projects/{projectId} -> setlist -> LiveCue`
2. setlist CRUD
3. setlist reorder / cue move
4. blank/loading/empty/error states
5. invalid router id handling

Evidence:
- screen recording or screenshots for each flow
- error message capture when negative cases are tested
- execution timestamp (KST) per flow
- build version
- log reference (console/file path)

## 5. Mobile Real-Device Resume Gate (SP-04 Deferred Items)
Execute near release (pre-release or immediate post-release internal test):
1. iPad + Apple Pencil long drawing session (>= 20 min)
2. iPhone rotation + drawing session (>= 10 min)
3. iOS shared-layer drawing read/write verification
4. iOS local Google login re-verification

Pass criteria:
- white flicker / white-out reproduction: 0
- drawing input loss: 0
- first-error critical event: 0 in target scenario

Evidence record:
- scenario timestamp (KST)
- device + OS + build version
- log reference
- screenshot/video linkage

## 6. Runtime Observability Gate
Confirm runtime metrics are emitted in target scenarios:
- `runtime_guard_triggered`
- `livecue_state_invalid`
- `setlist_order_invalid`
- `router_invalid_id`
- `firestore_snapshot_error`
- host-viewer guard values inside `runtime_guard_triggered.guard`:
  - `host_viewer_contract_invalid`
  - `viewer_target_origin_not_whitelisted`

Validation rule:
- Metrics must be observable in console/log capture when injecting negative scenarios.

Evidence record:
- validation timestamp (KST)
- build version
- log reference containing metric payload
- screenshot linkage if UI trigger is involved

## 7. First-Error / Regression Loop
### 7.1 First-error definition
- First critical error event observed in a session after deploy.
- Priority order: `livecue_state_invalid` -> `setlist_order_invalid` -> `router_invalid_id` -> `firestore_snapshot_error`.

### 7.2 Required regression checklist
- current/next mismatch
- setlist order discontinuity/duplication
- invalid route id handling
- snapshot null/not-found handling
- fallback malfunction
- long-session memory/input degradation

### 7.3 Evidence template
- timestamp (KST)
- device/browser/build
- reproduction conditions
- first error log line
- metric/log payload
- video or screenshot link

## 8. Fallback Operations Policy
Principle:
- Next Viewer is a fallback/support path, not the primary engine.

Allow fallback when:
- canonical path emits runtime guard failures in reproducible scenario
- platform-specific rendering issue is confirmed
- host-viewer contract validation passes

Do not allow fallback when:
- canonical path is healthy but fallback is forced by preference only
- fallback evidence/metric is missing
- fallback errors persist without exit criteria

Return-to-canonical criteria:
- canonical path passes same scenario twice consecutively
- no new first-error event in those runs

## 9. Large-File Change Governance
Target large files:
- `lib/features/projects/live_cue_page.dart`
- `lib/features/teams/team_home_page.dart`
- `lib/features/admin/global_admin_page.dart`

Rules:
- avoid full rewrite in one cycle
- change by functional unit only
- no large-file patch without tests
- runtime-safe guard/observability patches first

## 10. Backup / Recovery
### 10.1 Backup
1. Commit release candidate changes.
2. Push to remote as backup snapshot.
3. Record commit SHA/tag in release notes.

### 10.2 Recovery
1. Select previous stable backup SHA/tag.
2. Restore local workspace from backup.
3. Re-run static + functional gates.
4. Record incident summary and corrective actions.

## 11. Immediate Rollback Triggers
- Any critical first-error event reproduced in release-critical scenario.
- white-out/white-flicker reproduced in production-like run.
- input loss reproduced once in verified scenario.
- score load failure caused by Firestore/Storage access error occurs 3 times in a row.

## 12. Reference
- `docs/livecue_repro_matrix.md`
- `docs/livecue_incident_runbook.md`
- `.github/workflows/ci.yml`
- `.github/workflows/deploy_staging.yml`
- `.github/workflows/deploy_prod.yml`
