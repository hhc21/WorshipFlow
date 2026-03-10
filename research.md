# WorshipFlow Research Baseline (2026-03-10)

작성일: 2026-03-10 (KST)  
대상 경로: `/Users/hwanghuichan/Downloads/개발/WorshipFlow`

## 0. 문서 목적

`research.md`는 현재 코드베이스의 사실 상태를 분석해 기록하는 문서다.  
구현 계획은 `plan.md`가 담당하며, 본 문서는 계획/아이디어가 아니라 **현재 코드 근거**를 우선한다.

운영 정책:
- GitHub는 백업/복구 용도로만 사용한다.

## 1. 이번 기준선에서 확인한 상태

### 1.1 개발 방향(현재 의사결정)

- 현재 개발은 웹 기준으로 계속 진행한다.
- iOS 로컬 Google 로그인 이슈는 보류 상태다.
- iPad Apple Pencil 실기 테스트, iOS 공유 필기 실기 테스트는 보류 상태다.
- 위 보류 항목은 SP-07 이후(배포 직전/배포 후 내부 테스트 단계)에서 재개한다.

### 1.2 SP 진행 상태(코드 반영 기준)

- SP-03 구조 분리: 반영 완료
  - `LiveCueSyncCoordinator` 분리: `lib/features/projects/live_cue_sync_coordinator.dart`
  - `RenderPresenter` 분리: `lib/features/projects/live_cue_page.dart` 내부 `_LiveCueRenderPresenter`
  - `LiveCueStrokeEngine` 분리: `lib/features/projects/live_cue_stroke_engine.dart`
  - `LiveCueNotePersistenceAdapter` 분리: `lib/features/projects/live_cue_note_persistence_adapter.dart`
- SP-04 실기기 안정화: 코드 하드닝 반영 완료, 실기기 최종 증빙 대기
  - pointer/orientation/preload/ImageCache/eviction/rebuild 범위 조정 반영
  - `flutter analyze`, `flutter test --reporter=compact`, `bash scripts/ci/test_rules.sh` 통과
- SP-05-1 운영자 → 팀 진입: 반영 완료
  - 운영자 팀 목록에서 팀 홈 진입 가능
  - global admin 기반 접근 허용 보강

## 2. Architecture Audit (현재 구현 구조)

### 2.1 런타임 축

- 라우팅: `lib/app/router.dart`
  - `/teams` (팀 선택)
  - `/teams/:teamId` (팀 홈)
  - `/admin` (운영자 도구)
- 운영자 경로:
  - `lib/features/admin/global_admin_page.dart`에서 팀 목록 렌더
  - 팀 클릭/버튼으로 `/teams/{teamId}` 이동
- 팀 홈:
  - `lib/features/teams/team_home_page.dart`
  - 팀 문서 + 멤버 문서 + global admin 여부를 조합해 접근 판단

### 2.2 LiveCue 코어 구조(분리 상태)

- Sync 책임: `LiveCueSyncCoordinator`
  - 비웹: native snapshot stream
  - 웹: polling stream + generation/sequence trace
  - current index 해석과 fallback 규칙은 `LiveCueResolvedState`에 집중
- Render 책임: `_LiveCueRenderPresenter`
  - preview cache / prefetch / fallback / overlay / viewport
- Input 책임: `LiveCueStrokeEngine`
  - stroke begin/append/end, erase/undo/clear, tool state
- Persistence 책임: `LiveCueNotePersistenceAdapter`
  - private/shared note load/save
  - legacy fallback + migration write-back

판정:
- SP-03의 핵심 목표(동기화/렌더/입력/저장 책임 분리)는 코드 기준으로 달성됨.

### 2.3 Web fallback / Next Viewer 위치

- Host: `lib/features/projects/next_viewer_host_web.dart`
- Contract: `lib/features/projects/next_viewer_contract.dart`
- Viewer: `apps/livecue-web-next/app/page.tsx`
- 현재 위치:
  - 핵심 엔진이 아닌 웹 fallback/보조 경로
  - host-viewer 핸드셰이크(`viewer-ready` → `host-init`) 기반
  - 상대 좌표 `0.0~1.0`, fixed-8, `relative-v1` 유지

## 3. SP-04 분석 반영

### 3.1 현재 상태(반영 완료)

반영 파일: `lib/features/projects/live_cue_page.dart`

- pointer 안정화:
  - 지원 입력 종류 필터링(touch/stylus/inverted stylus 중심)
  - active pointer 추적
- orientation/metrics 대응:
  - `WidgetsBindingObserver` 기반 metrics 변화 처리
  - active pointer 정리, viewer transform reset
- preload 충돌 완화:
  - 드로잉 활성 포인터 존재 시 warm prefetch 억제
- 캐시 안정화:
  - ImageCache 상한 적용/복원
  - preview cache/prefetch LRU eviction
  - song key future cache 상한

### 3.2 남은 상태

- SP-04는 "코드 하드닝 완료" 단계이며, 실기기 최종 증빙은 미완료다.
- 특히 iPad/iPhone 장시간 세션 증빙은 보류 상태다.

## 4. SP-05-1 분석 반영 (운영자 → 팀 진입)

### 4.1 현재 상태(반영 완료)

- 운영자 팀 목록에서 team home 진입 추가:
  - `lib/features/admin/global_admin_page.dart`
- teamId 전달 안정화:
  - trim + doc id validation + encode
- team home 접근 보강:
  - `lib/features/teams/team_home_page.dart`
  - member/creator가 아니어도 global admin이면 진입 허용
- 회귀 테스트:
  - `test/widget/team_home_page_regression_test.dart`에 global admin 진입 케이스 반영

### 4.2 범위 밖(의도적으로 미진행)

- 운영자 → 프로젝트 진입 확장
- 운영자 → LiveCue 직접 진입 확장

## 5. 데이터/보안 관점 정합성

### 5.1 Canonical 데이터 축

현재 런타임 canonical 경로는 `teams/{teamId}` 중심이다.

핵심 경로:
- `users/{uid}`
- `users/{uid}/ClientProbe/mobile`
- `teams/{teamId}`
- `teams/{teamId}/members/{memberId}`
- `teams/{teamId}/projects/{projectId}`
- `teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}`
- `teams/{teamId}/projects/{projectId}/liveCue/state`
- `teams/{teamId}/projects/{projectId}/sharedNotes/main`
- `teams/{teamId}/userProjectNotes/{noteId}`

### 5.2 Firestore 규칙 관찰 요약

- global admin(`globalAdmins/{uid}`)은 `teams` list/get, `members` list/get에 예외 허용됨.
- 단, 프로젝트 read는 기본적으로 team member 기반이므로 global admin이 팀 멤버가 아니면 일부 팀 홈 정보는 제한될 수 있다.
- `collectionGroup('members')` fallback은 본인 멤버십 탐색 용도로 query-safe 제한이 걸려 있다.

## 6. 현재 상태 vs 남은 리스크

### 6.1 현재 상태 (확정)

- LiveCue 구조 분리 완료(Sync/Render/Input/Persistence)
- LiveCue 프로토콜 핵심 계약(relative-v1, fixed-8) 유지
- SP-04 하드닝 코드 반영 + 정적 검증 통과
- SP-05-1 운영자 팀 진입 경로 복구 완료

### 6.2 남은 리스크 (미해결)

- iOS 로컬 Google 로그인 환경/설정 이슈(보류)
- iPad/iPhone 실기기 장시간 필기 증빙 미완
- global admin의 팀 홈 진입은 가능하지만, 팀 멤버 전용 데이터는 규칙에 따라 제한 가능
- 대형 파일(`live_cue_page.dart`, `team_home_page.dart`, `global_admin_page.dart`) 유지보수 비용
- 관찰 로그(`RenderBox was not laid out`, `AppCheckProvider not installed`)의 플랫폼별 영향도 추가 분리 필요

## 7. 보류 항목 정리

현재 보류(문서화만 유지, 즉시 구현 안 함):
- iOS 로컬 Google 로그인 재검증
- iPad Apple Pencil 실기 검증
- iOS 공유 필기 실기 검증

재개 시점:
- SP-07 이후 배포 직전/배포 후 내부 테스트 사이클

## 8. 결론

현재 코드베이스는 다음 상태다.

- 구조 측면: SP-03 핵심 분리 완료
- 안정화 측면: SP-04 하드닝 완료(증빙 대기)
- 운영 동선 측면: SP-05-1 운영자 → 팀 진입 완료

따라서 현재 기준선은 "구조 정리와 웹 중심 개발을 이어가되, 모바일 실기 증빙 항목은 배포 게이트 시점으로 지연"으로 정의한다.
