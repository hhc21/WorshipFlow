# WorshipFlow System Architecture (2026-03-10)

## 0. 문서 역할

`system_architecture.md`는 현재 시스템 구조를 설명한다.

- 코드 분석/상태 판정: `research.md`
- 구현 계획: `plan.md`
- 제품 전략: `product_roadmap.md`
- 시스템 구성/책임/경계: `system_architecture.md`

## 1. 시스템 개요

현재 런타임 구조:

1. Flutter Client (Web 중심 운영, Mobile 경로 존재)
2. Firebase Backend
   - Firebase Auth
   - Firestore
   - Firebase Storage
3. Web fallback Viewer (Next.js, 선택 경로)

핵심 도메인:
- Team Workspace
- Project/Setlist
- LiveCue 동기화/렌더/입력/노트
- Admin Tooling (글로벌 운영자)

## 2. 애플리케이션 라우팅 구조

라우터: `lib/app/router.dart`

주요 경로:
- `/sign-in`
- `/teams` (팀/프로젝트 진입 루트)
- `/teams/:teamId` (팀 홈)
- `/teams/:teamId/projects/:projectId`
- `/teams/:teamId/projects/:projectId/live`
- `/teams/:teamId/songs/:songId`
- `/admin` (운영자 도구)

운영자 팀 진입 경로(현재 반영):
- `/admin` → 팀 목록 → `/teams/{teamId}`

## 3. LiveCue 아키텍처 (현재 구현 구조)

LiveCue는 단일 파일 중심 구조에서 책임 분리 구조로 이동했다.

### 3.1 Sync Layer

구성:
- `LiveCueSyncCoordinator`
- `LiveCueResolvedState`

책임:
- cue/setlist 스트림 attach/detach
- 웹 polling 전환 순차 보장
- generation/sequence tracing
- `currentCueLabel -> songId -> title+key` fallback 해석

### 3.2 Render Layer

구성:
- `_LiveCueRenderPresenter` (현재 `live_cue_page.dart` 내부)

책임:
- preview cache/prefetch
- renderer fallback 제어
- overlay visibility
- viewport(transform) 제어

### 3.3 Input Layer

구성:
- `LiveCueStrokeEngine`

책임:
- stroke lifecycle(begin/append/end)
- erase/undo/clear
- brush/tool state
- layer visibility(private/shared)

### 3.4 Persistence Layer

구성:
- `LiveCueNotePersistenceAdapter`

책임:
- private/shared note load/save
- legacy note fallback + migration
- note I/O를 UI에서 분리

## 4. Web Fallback / Next Viewer 구조

### 4.1 위치

Next.js Viewer는 핵심 엔진이 아니라 **fallback/보조 렌더 경로**다.

구성:
- Host (Flutter): `next_viewer_host_web.dart`
- Contract: `next_viewer_contract.dart`
- Viewer (Next.js): `apps/livecue-web-next/app/page.tsx`

### 4.2 브릿지 프로토콜 요약

Host/Viewer 시퀀스:
- Viewer `viewer-ready`
- Host `host-init`
- Viewer `init-applied`

편집 상태:
- `ink-dirty`
- `ink-commit`
- `ink-synced`

에러:
- `asset-cors-failed`

보안 경계:
- host는 허용 origin whitelist 기반으로 postMessage 송신/수신을 제한

## 5. Team / Admin 시스템 구조

### 5.1 Team 경로

- Team Select: `team_select_page.dart`
- Team Home: `team_home_page.dart`

Team Home 진입 컨텍스트:
- team 문서
- member 문서
- global admin 여부

즉, 팀 멤버/팀 생성자 중심 구조를 유지하면서 운영자 예외 진입을 수용한다.

### 5.2 Admin 경로

- Global Admin Route/Page: `global_admin_page.dart`
- 기능:
  - 팀 목록 조회
  - 팀 홈 진입
  - 전역 곡 관리/마이그레이션

## 6. 데이터/보안 레이어 경계

### 6.1 데이터 축

현재 canonical 축은 `teams/{teamId}`다.

- Team/Project/LiveCue/Notes 모두 teams 하위
- users 하위에는 개인 프로필/멤버십 미러/ClientProbe

### 6.2 보안 축

Firestore Rules(`firestore.rules`) 기준:
- 기본 권한: team member / team admin / project leader
- global admin 예외: 팀/멤버 조회 및 일부 운영 경로
- deleteQueue/opsMetrics는 별도 정책으로 보호

## 7. 개념 구조 vs 현재 구현 구조

### 7.1 현재 구현 구조

- teams 중심 런타임
- LiveCue 4계층 분리 반영
- 운영자→팀 진입 반영

### 7.2 장기 개념 구조

- `churches/{churchId}` 같은 상위 조직 축은 장기 확장 가능성으로만 유지
- 현재 운영 경로와 혼용하지 않는다

## 8. 현재 구조의 기술적 의미

강점:
- LiveCue 핵심 책임 경계가 이전 대비 명확해짐
- 운영자 팀 접근 경로가 시스템 수준에서 연결됨

남은 과제:
- 대형 파일 유지보수 비용
- 모바일 실기 증빙(특히 iOS) 재개 필요
- global admin 진입 이후 일부 팀 멤버 전용 데이터 접근 범위 명확화
