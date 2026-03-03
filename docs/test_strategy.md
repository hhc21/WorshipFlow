# Test Strategy

## 1. Objectives
- Prevent regressions in team/project/live cue critical flow.
- Detect permission-sensitive and self-healing regressions before deploy.
- Enforce coverage gate in CI.

## 2. Test Layers

### Unit Tests
- Parser/normalization helpers
- Storage helper validation
- Team name normalization
- User display name resolution
- Firestore doc id validation

### Widget Tests
- Team select rendering states
- Team home loading/error states
- Live cue action-level UI safety

### Integration Tests
- Team create -> project create -> project open
- Invite accept and role visibility
- Song asset upload metadata path
- Live cue open and asset resolve flow

## 3. Self-Healing Regression Scenarios (Required)
The following scenarios must be covered explicitly.

1. Missing creator member doc recovery
- Input: team exists, creator member doc missing
- Expected: member doc restored with admin role

2. Invalid lastProjectId fallback
- Input: team.lastProjectId points to missing/invalid project id
- Expected: fallback to most recent valid project and team.lastProjectId rewritten

3. Stale teamNameIndex cleanup path
- Input: name index points to missing team document
- Expected: stale index cleanup and create retry succeeds

4. Invalid membership mirror entries
- Input: teamMemberships contains invalid doc ids
- Expected: invalid entries ignored and UI remains functional

## 4. Coverage Policy
- Minimum coverage threshold controlled by `COVERAGE_MIN` (default 35).
- CI must execute:
  - `flutter analyze`
  - `flutter test --coverage`
  - `scripts/ci/check_coverage.sh`
  - `flutter build web --release`
- Any failure blocks deployment.

## 5. Runner Dependency Policy
- `lcov` install attempted in CI.
- If `lcov` unavailable, parse `coverage/lcov.info` directly.

## 6. Manual Alpha Checklist (pre-beta)
- Team create/delete
- Project create/list/open/delete
- Invite link open/accept
- Song upload/open in live cue
- Notes draw/erase/save

## 7. Exit Criteria
- Critical self-healing scenarios pass.
- CI pipeline fully green.
- No blocking P1 regression in manual alpha checklist.
