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
- Live cue keyboard/swipe transition flow

Limitations:
- `test/integration/live_cue_web_e2e_test.dart` uses fake/mocked dependencies.
- Browser real-path issues (Firestore transport/CORS/image renderer fallback/pointer events)
  are not fully covered by mocked integration tests.

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
- Minimum coverage threshold controlled by:
  - `COVERAGE_MIN` (explicit value, highest priority)
  - `COVERAGE_STAGE` (stage preset): `baseline=35`, `step50=50`, `step60=60`
- CI must execute:
  - `flutter analyze`
  - `flutter test --coverage`
  - `scripts/ci/check_coverage.sh`
  - `flutter build web --release`
- Any failure blocks deployment.
- `scripts/ci/check_coverage.sh` applies temporary exclusion regex by default for high-interaction screens:
  - `lib/features/projects/live_cue_page.dart`
  - `lib/features/projects/segment_a_page.dart`
  - `lib/features/projects/segment_b_page.dart`
  - `lib/features/teams/team_home_page.dart`
- Exclusion reduction note:
  - `lib/features/teams/team_invite_panel.dart` was removed from default exclusion (2026-03-07, step-down phase)
- Override policy:
  - `COVERAGE_EXCLUDE_REGEX=""` to disable exclusions and measure full scope.
  - `COVERAGE_EXCLUDE_REGEX="<regex>"` to set custom exclusion scope.
- Reporting policy (required):
  - Excluded scope gate: `scripts/ci/check_coverage.sh` (current threshold 35%)
  - Raw scope report: `COVERAGE_EXCLUDE_REGEX="" scripts/ci/check_coverage.sh`
  - Release notes must include both values (`excluded` + `raw`)
  - CI raw report command (non-blocking gate): `COVERAGE_EXCLUDE_REGEX="" COVERAGE_MIN=0 scripts/ci/check_coverage.sh`

## 5. Runner Dependency Policy
- `lcov` install attempted in CI.
- If `lcov` unavailable, parse `coverage/lcov.info` directly.
- Firestore Rules emulator suite(`scripts/ci/test_rules.sh`) requires Java 17+.

## 6. Manual Alpha Checklist (pre-beta)
- Team create/delete
- Project create/list/open/delete
- Invite link open/accept
- Song upload/open in live cue
- Notes draw/erase/save
- LiveCue Safari matrix required:
  - execute `docs/livecue_repro_matrix.md` LC-SAF-01~06
  - release approval requires LC-SAF-01/04/05 pass evidence

## 7. Exit Criteria
- Critical self-healing scenarios pass.
- CI pipeline fully green.
- No blocking P1 regression in manual alpha checklist.
