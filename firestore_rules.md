# WorshipFlow Firestore Security Model (2026-03-10)

## 0. 문서 역할

`firestore_rules.md`는 `firestore.rules`의 현재 보안 모델을 설명한다.  
이 문서는 보안 정책 설명 문서이며, 구현 코드는 `firestore.rules`가 기준이다.

## 1. 현재 규칙의 기본 원칙

1. 기본 전제: 인증 사용자(`request.auth != null`)만 접근  
2. 팀 중심 권한 모델:
   - team member
   - team admin
   - project leader
3. global admin 예외 모델:
   - `globalAdmins/{uid}` 존재 시 일부 조회 경로 허용
4. 최소 권한 원칙:
   - 읽기/쓰기 권한을 경로별로 분리

## 2. 핵심 판별 함수(개념)

`firestore.rules` 내부 핵심 함수:
- `isGlobalAdmin()`
- `isTeamMember(teamId)`
- `isTeamAdmin(teamId)`
- `isProjectLeader(teamId, projectId)`
- `canWriteLiveCue(teamId, projectId)`

의미:
- LiveCue 쓰기 = `project leader` 또는 `team admin`
- 팀/프로젝트 기본 읽기 = `team member` 중심
- global admin은 일부 목록/상세 조회에 예외 허용

## 3. Canonical 경로별 권한 요약

### 3.1 글로벌/사용자 경로

- `globalAdmins/{userId}`
  - read: 본인 문서만
  - write: 불가(수동 관리)

- `users/{userId}`
  - read/write: 본인만

- `users/{userId}/ClientProbe/mobile`
  - read/create/update: 본인만
  - delete: 불가

- `users/{userId}/teamMemberships/{teamId}`
  - read: 본인
  - create/update/delete: 본인/팀 관리자 조건 조합

### 3.2 teams 루트

- `teams/{teamId}`
  - list/get: `isGlobalAdmin` 또는 `isTeamMember`
  - create: signed-in creator 조건
  - update/delete: team admin/creator 중심

의미:
- global admin은 팀 목록/상세 문서를 읽을 수 있다.

### 3.3 팀 하위 멤버 경로

- `teams/{teamId}/members/{userId}`
  - list/get: global admin/team admin/멤버 조건 조합
  - create/update/delete: 초대/관리 정책 기반 제한

### 3.4 프로젝트/LiveCue 경로

- `teams/{teamId}/projects/{projectId}`
  - read: `isTeamMember`
  - write: team admin 또는 project leader

- `teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}`
- `teams/{teamId}/projects/{projectId}/segmentB_application/{itemId}`
  - read: `isTeamMember`
  - write: team admin 또는 project leader

- `teams/{teamId}/projects/{projectId}/liveCue/{docId}`
  - read: `isTeamMember`
  - write: `canWriteLiveCue` (team admin/project leader)

- `teams/{teamId}/projects/{projectId}/sharedNotes/{noteId}`
  - read/write: `isTeamMember`

### 3.5 운영 경로

- `teams/{teamId}/deleteQueue/{requestId}`
  - create/get/list: team admin
  - update/delete: 불가

- `teams/{teamId}/opsMetrics/{metricId}`
  - create: team member
  - get/list: team admin

### 3.6 전역 곡 / 레거시 곡

- `songs/{songId}` 및 `songs/{songId}/assets/{assetId}`
  - read: signed-in
  - write: global admin

- `teams/{teamId}/songs/{songId}` (legacy)
  - read: team member 또는 global admin
  - write: 불가(마이그레이션 중 읽기 전용)

## 4. collectionGroup('members') fallback 정책

규칙:
- `/{anyPath=**}/members/{memberId}` get/list 허용은 본인 멤버십 탐색 범위로 제한
- 허용 조건:
  - `memberId == request.auth.uid`
  - 또는 문서의 `userId/uid/email`이 요청자와 일치

의미:
- 팀 선택/닉네임 동기화용 fallback은 가능
- 광범위한 멤버 디렉터리 조회는 방지

## 5. 운영자 → 팀 진입(SP-05-1)과 규칙 의미

현재 반영 상태:
- global admin은 `teams/{teamId}` list/get과 `members` list/get이 허용된다.
- 따라서 운영자 도구에서 팀 목록 조회 및 팀 홈 진입 컨텍스트 구성은 가능하다.

중요한 제한:
- `projects` read는 기본적으로 `isTeamMember(teamId)` 기준이다.
- 즉 global admin이 팀 멤버가 아니면 팀 홈 내 일부 프로젝트 데이터는 제한될 수 있다.

## 6. 현재 허용된 것 vs 보류된 것

### 6.1 현재 허용된 것

- 모바일 로그인 probe 경로(`ClientProbe/mobile`) read/write
- team-select용 members collectionGroup fallback
- 운영자 팀 목록 조회 + 팀 홈 진입을 위한 팀/멤버 조회

### 6.2 아직 보류/제한된 것

- global admin의 팀 프로젝트 데이터 전면 읽기 권한 확대
- 운영자 경로에서 팀 멤버 권한을 넘는 쓰기 작업

## 7. 설계/운영 가이드

1. canonical 보안 축은 `teams/{teamId}` 중심으로 유지한다.  
2. global admin 예외는 조회 중심으로 최소화한다.  
3. 팀 멤버십 fallback은 본인 조회 범위를 넘지 않도록 유지한다.  
4. 권한 확장은 "운영 편의"가 아니라 "보안 모델 일관성" 기준으로 진행한다.
