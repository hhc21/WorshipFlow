# WorshipFlow Data Model (2026-03-10)

## 0. 문서 역할

`data_model.md`는 현재 런타임 데이터 구조를 정의한다.  
구현 코드와 규칙(`firestore.rules`)에 맞는 **canonical 경로**를 기준으로 작성한다.

## 1. Canonical 모델 (현재 운영 경로)

현재 canonical 데이터 축은 `teams/{teamId}` 중심이다.

핵심 원칙:
- Team/Project/LiveCue/Note의 런타임 경로는 `teams` 루트 하위
- 사용자별 상태는 `users/{uid}` 하위
- 글로벌 운영자 권한은 `globalAdmins/{uid}`로 별도 관리

## 2. Top-level Collections

### 2.1 `users/{uid}`

용도:
- 사용자 개인 문서
- 멤버십 미러
- 모바일 probe

주요 하위 경로:
- `users/{uid}/ClientProbe/mobile`
- `users/{uid}/teamMemberships/{teamId}`

### 2.2 `teams/{teamId}`

용도:
- 팀 워크스페이스 루트

주요 필드(예):
- `name`
- `createdBy`
- `memberUids`
- `lastProjectId`
- `updatedAt`

주요 하위 경로:
- `members/{memberId}`
- `projects/{projectId}`
- `userProjectNotes/{noteId}`
- `songRefs/{songId}`
- `invites/{inviteId}`
- `inviteLinks/{inviteLinkId}`
- `joinRequests/{requesterUid}`
- `deleteQueue/{requestId}`
- `opsMetrics/{metricId}`

### 2.3 `songs/{songId}`

용도:
- 전역 곡/악보 메타

주요 하위 경로:
- `songs/{songId}/assets/{assetId}`

### 2.4 `globalAdmins/{uid}`

용도:
- 글로벌 운영자 식별

## 3. Team Workspace 모델

### 3.1 Team Member

경로:
- `teams/{teamId}/members/{memberId}`

주요 필드(예):
- `userId`, `uid`, `email`
- `displayName`, `nickname`
- `role` (`admin`, `leader`, `member` 등)
- `teamName`
- `capabilities`

참고:
- 팀 선택 화면은 `collectionGroup('members')` fallback을 사용해 본인 멤버십을 조회한다.

### 3.2 Team Project

경로:
- `teams/{teamId}/projects/{projectId}`

주요 필드(예):
- `date`
- `title`
- `leaderUserId`
- `leaderDisplayName`
- `updatedAt`

하위 경로:
- `segmentA_setlist/{itemId}`
- `segmentB_application/{itemId}`
- `liveCue/state`
- `sharedNotes/main`

### 3.3 Setlist Item (`segmentA_setlist`)

경로:
- `teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}`

주요 필드(코드 사용 기준):
- `order`
- `songId`
- `displayTitle`
- `freeTextTitle`
- `keyText`
- `cueLabel` (또는 순번 기반 fallback)

## 4. LiveCue 데이터 모델

### 4.1 LiveCue State

경로:
- `teams/{teamId}/projects/{projectId}/liveCue/state`

주요 필드(코드 사용 키):
- current
  - `currentSongId`
  - `currentDisplayTitle`
  - `currentFreeTextTitle`
  - `currentKeyText`
  - `currentCueLabel`
- next
  - `nextSongId`
  - `nextDisplayTitle`
  - `nextFreeTextTitle`
  - `nextKeyText`
  - `nextCueLabel`
- meta
  - `updatedAt`
  - `updatedBy`

해석 규칙(동기화 레이어):
- `currentCueLabel -> songId -> title+key` 순으로 current index를 해석
- unresolved 시 setlist fallback 사용

### 4.2 LiveCue Note Layer

shared note:
- `teams/{teamId}/projects/{projectId}/sharedNotes/main`

private note:
- `teams/{teamId}/userProjectNotes/{noteId}`
  - 권장 doc id: `v2__{projectId}__{userId}`
  - legacy id/query fallback 존재

노트 공통 필드(예):
- `content`
- `drawingStrokes`
- `visibility`
- `teamId`, `projectId`
- `userId`, `ownerUserId` (private)
- `updatedAt`, `updatedBy`

## 5. 필기(Stroke) 데이터 계약

모델:
- `SketchStroke` (`lib/features/projects/models/sketch_stroke.dart`)

계약:
- 스키마 버전: `relative-v1`
- 좌표계: `0.0 ~ 1.0` 상대 좌표
- 정밀도: 소수점 8자리 fixed-8
- 필드:
  - `schemaVersion`
  - `colorValue`
  - `width`
  - `points[{x,y}]`

## 6. 운영자 → 팀 진입과 데이터 컨텍스트

운영자 팀 진입(`SP-05-1`) 시 Team Home 컨텍스트는 다음을 함께 로드한다.

- `teams/{teamId}` 문서
- `teams/{teamId}/members/{uid}` 문서
- `globalAdmins/{uid}` 존재 여부

즉 팀 멤버 문서가 없어도 global admin 문서가 있으면 팀 홈 진입 컨텍스트를 구성할 수 있다.

## 7. 보조/레거시 모델

### 7.1 유지 중인 보조 경로

- `users/{uid}/teamMemberships/{teamId}` (미러/복구/탐색 보조)
- `teamNameIndex/{nameKey}`
- legacy private note id/query fallback

### 7.2 장기 확장 모델 (현재 canonical 아님)

- `churches/{churchId}/...` 구조는 장기 SaaS/멀티 조직 확장 관점에서만 유지한다.
- 현재 운영 경로와 혼용하지 않는다.

## 8. 상태 정리

현재 구현 기준으로 데이터 모델의 사실 상태는 다음과 같다.

- canonical: `teams/{teamId}` 중심
- LiveCue: `projects/{projectId}/liveCue/state` + setlist + note layer
- 보안/권한: team member/team admin/global admin 역할 조합
- 레거시: 최소 fallback만 유지, 신규 경로는 canonical 축에 맞춘다
