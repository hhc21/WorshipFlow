# Code Size Snapshot

- Generated: 2026-03-15 23:34:08 KST
- Branch: `main`
- Purpose: Capture an evidence-based maintainability snapshot of current repository file sizes so future refactor and risk discussions can use measured baselines instead of intuition.
- Method: Line counts were collected from repository files using shell/Python line counting over `lib/**/*.dart`, `test/**/*.dart`, `scripts/**/*.sh`, and `docs/**/*.md`, excluding generated/dependency directories such as `build/`, `.dart_tool/`, `.git/`, `node_modules/`, `ios/Pods/`, and `android/.gradle/`.
- Scope scanned: 103 files, approximately 26,538 lines across the targeted directories.

## 1. Largest Dart files

| File | Lines | Notes |
|---|---:|---|
| `lib/features/teams/team_select_page.dart` | 1,973 | team selection flow, onboarding, routing-heavy UI |
| `lib/features/teams/team_home_page.dart` | 1,918 | team home orchestration, project list, loading/error states |
| `lib/features/projects/live_cue_fullscreen_sections.dart` | 1,813 | fullscreen LiveCue UI sections and viewer/drawing surface composition |
| `lib/features/projects/live_cue_page.dart` | 1,517 | LiveCue orchestration and state-owner bridge |
| `lib/features/projects/segment_a_page.dart` | 1,483 | setlist management, reorder, cue operations |
| `lib/features/admin/global_admin_page.dart` | 1,315 | admin navigation, team/project operational UI |
| `lib/features/songs/song_detail_page.dart` | 960 | song detail, preview, asset handling |
| `lib/features/songs/global_song_panel.dart` | 840 | song library entry panel and list interactions |
| `lib/features/teams/team_invite_panel.dart` | 681 | invite/join flow UI and state handling |
| `lib/services/song_search.dart` | 644 | song resolver, fallback lookup, normalization |
| `lib/features/projects/live_cue_sync_coordinator.dart` | 638 | LiveCue sync coordination and stream lifecycle |
| `lib/features/projects/live_cue_render_support.dart` | 608 | preview/render support and preview cache helpers |
| `lib/features/projects/project_notes_panel.dart` | 600 | project notes panel and note workflow UI |
| `lib/features/songs/song_library_panel.dart` | 539 | song library browsing surface |
| `lib/features/projects/live_cue_operator_sections.dart` | 476 | operator LiveCue UI section extraction |

Notes:
- The current LiveCue code is no longer concentrated in a single oversized file.
- The main LiveCue surface is now split across `live_cue_page.dart`, `live_cue_fullscreen_sections.dart`, `live_cue_render_support.dart`, and `live_cue_operator_sections.dart`.

## 2. Largest test files

| File | Lines | Notes |
|---|---:|---|
| `test/widget/segment_a_setlist_crud_test.dart` | 252 | setlist CRUD/reorder/cue regression coverage |
| `test/integration/live_cue_web_e2e_test.dart` | 235 | LiveCue fullscreen/web integration coverage |
| `test/integration/self_healing_flow_test.dart` | 192 | self-healing and membership path integration |
| `test/widget/project_detail_page_state_test.dart` | 158 | project access and UI state regression checks |
| `test/unit/song_search_test.dart` | 139 | resolver priority, fallback, and legacy-title coverage |
| `test/integration/critical_flow_test.dart` | 133 | critical app navigation and membership flow |
| `test/widget/team_home_page_regression_test.dart` | 101 | team home rendering regression guard |
| `test/integration/team_join_request_flow_test.dart` | 96 | team creation/join request integration |
| `test/unit/ops_metrics_test.dart` | 85 | observability and metric payload coverage |
| `test/widget/clipboard_helper_test.dart` | 84 | UI helper regression coverage |

## 3. Project-area summary

| Area | Files | Approx. lines | Representative files |
|---|---:|---:|---|
| LiveCue / projects | 17 | 9,081 | `live_cue_page.dart`, `live_cue_fullscreen_sections.dart`, `segment_a_page.dart` |
| songs / library | 3 | 2,339 | `song_detail_page.dart`, `global_song_panel.dart`, `song_library_panel.dart` |
| services | 3 | 737 | `song_search.dart`, `firebase_providers.dart` |
| core/runtime/ops | 4 | 320 | `runtime_guard.dart`, `ops_metrics.dart` |
| tests | 25 | 2,164 | `segment_a_setlist_crud_test.dart`, `live_cue_web_e2e_test.dart` |

Supplementary scan notes:
- `scripts/**/*.sh`: 10 files, largest is `scripts/github/apply_repo_policies.sh` at 121 lines.
- `docs/**/*.md`: 17 files, largest is `docs/feature_checklist.md` at 769 lines.

## 4. Current maintainability observations

- The repository is no longer dominated by a single LiveCue page file. The current snapshot reflects a post-SP-08 split where LiveCue responsibilities are distributed across orchestration, fullscreen UI sections, render support, and shared helpers.
- `live_cue_page.dart` is still important, but it is no longer the largest LiveCue file. The bigger maintenance hotspots are now spread across `live_cue_fullscreen_sections.dart`, `live_cue_page.dart`, `live_cue_render_support.dart`, and `live_cue_operator_sections.dart`.
- Size alone is not the only risk signal. Files such as `song_search.dart` and `live_cue_sync_coordinator.dart` are smaller than the large UI files but are architecturally sensitive because resolver and sync correctness depend on them.
- `team_select_page.dart`, `team_home_page.dart`, `segment_a_page.dart`, and `global_admin_page.dart` remain large operational UI surfaces and are still good candidates for focused modularization when change frequency starts clustering there.
- Future refactor decisions should use both file size and repeated-change frequency. A 600-line file touched every week may deserve earlier extraction work than a larger but stable file.

## 5. Refactor trigger heuristics

Use these as practical refactor triggers rather than absolute rules:

- A file grows beyond roughly 2,000 to 2,500 lines.
- Regressions repeatedly cluster in the same file or surface area.
- State ownership, lifecycle management, rendering, async orchestration, and error handling are mixed together in one place.
- Review/debug cost becomes disproportionately high compared with the size of the change.
- A file becomes the integration point for unrelated concerns and every fix starts carrying unrelated regression risk.

## 6. Suggested watchlist

Monitor these files/areas in future SP work:

- `lib/features/projects/live_cue_fullscreen_sections.dart`
  - Large fullscreen composition surface; likely regression hotspot when viewer, drawing, and overlay behavior change.
- `lib/features/projects/live_cue_page.dart`
  - Still owns orchestration and state bridge responsibilities; sensitive despite reduced size.
- `lib/features/projects/segment_a_page.dart`
  - High-change operational surface for setlist CRUD, reorder, and cue movement.
- `lib/features/teams/team_select_page.dart`
  - Large routing/onboarding surface with broad user-flow impact.
- `lib/features/teams/team_home_page.dart`
  - Large team/project home surface with many loading/error/access states.
- `lib/features/admin/global_admin_page.dart`
  - Large admin entry surface with navigation and operational-path risk.
- `lib/services/song_search.dart`
  - Smaller than UI hotspots, but architecturally important because resolver stability and fallback behavior depend on it.
