# WorshipFlow LiveCue Protocol (2026-03-10)

## 0. 문서 역할

`livecue_protocol.md`는 LiveCue 동기화 규약 문서다.  
이 문서는 현재 구현된 데이터 경로/상태 해석/메시지 계약을 정의한다.

## 1. 프로토콜 범위

적용 범위:
- 운영 화면 LiveCue
- fullscreen LiveCue
- (웹 fallback 시) Next.js Viewer 브릿지

비범위:
- 팀/프로젝트 생성 정책
- 제품 전략 결정(roadmap)

## 2. Canonical 데이터 경로

### 2.1 LiveCue 상태

- `teams/{teamId}/projects/{projectId}/liveCue/state`

핵심 키:
- `currentSongId`, `currentDisplayTitle`, `currentFreeTextTitle`, `currentKeyText`, `currentCueLabel`
- `nextSongId`, `nextDisplayTitle`, `nextFreeTextTitle`, `nextKeyText`, `nextCueLabel`
- `updatedAt`, `updatedBy`

### 2.2 Setlist

- `teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}`

해석에 쓰는 주요 필드:
- `order`, `songId`, `displayTitle`, `freeTextTitle`, `keyText`, `cueLabel`

### 2.3 노트/필기 레이어

- shared: `teams/{teamId}/projects/{projectId}/sharedNotes/main`
- private: `teams/{teamId}/userProjectNotes/{noteId}`

## 3. LiveCue 상태 해석 규약

### 3.1 Current 곡 해석 우선순위

`LiveCueResolvedState` 기준:
1. `currentCueLabel` 매칭
2. `currentSongId` 매칭
3. `title + key` 매칭
4. unresolved이면 setlist fallback

목적:
- cue 문서 누락/지연 시 잘못된 곡 표시를 줄이고 안정적으로 fallback한다.

### 3.2 Sync ordering 규약

`LiveCueSyncCoordinator` 기준:
- 웹: polling 전환 시 generation 증가 + cancel 후 재attach
- 비웹: native snapshot stream 단일화
- emission sequence trace를 기록해 역전/충돌을 탐지

## 4. 상태 소유권 규약 (현재 구현)

- Sync state: `LiveCueSyncCoordinator`
- Render state: `_LiveCueRenderPresenter`
- Input state: `LiveCueStrokeEngine`
- Persistence state: `LiveCueNotePersistenceAdapter`
- UI 레이어: 소유 상태를 직접 계산/저장하지 않고 결과를 소비

## 5. 입력/필기 프로토콜

### 5.1 Input lifecycle

`LiveCueStrokeEngine` 기준:
- beginStroke
- appendStroke
- endStroke
- eraseAt
- undoCurrentLayer
- clearCurrentLayer

### 5.2 레이어 모델

- private layer
- shared layer
- editing layer 토글 기반으로 대상 레이어 결정

### 5.3 좌표/정밀도 계약

`SketchStroke` 계약:
- schema: `relative-v1`
- coordinate range: `0.0 ~ 1.0`
- precision: fixed-8

## 6. Persistence 프로토콜

`LiveCueNotePersistenceAdapter` 기준:

load:
- private(v2) 우선
- legacy doc id fallback
- legacy query fallback
- fallback 데이터는 가능하면 v2로 migration write-back

save:
- editing layer 기준으로 private/shared 저장 분기
- 필요 시 both-layer 저장

## 7. 역할 모델

현재 구현 역할:
- 운영자/인도자(쓰기 권한 보유 사용자): cue 상태 변경 가능
- 일반 팀원(viewer): cue 읽기/필기 참여 중심

권한 실제 판정은 Firestore Rules를 따른다:
- liveCue write: team admin 또는 project leader
- liveCue read: team member

## 8. Web fallback 프로토콜 (Next Viewer)

### 8.1 위치

- Next Viewer는 핵심 엔진이 아니라 web fallback/보조 경로다.

### 8.2 핸드셰이크

Viewer -> Host:
- `viewer-ready`

Host -> Viewer:
- `host-init`

Viewer -> Host:
- `init-applied`

### 8.3 상태/동기 이벤트

Viewer -> Host:
- `ink-dirty`
- `ink-commit`
- `ink-synced`
- `asset-cors-failed`

Host -> Viewer:
- `token-refresh`
- `ink-synced`

### 8.4 초기 데이터 필수 항목

`host-init` payload 핵심:
- `teamId`, `projectId`
- `currentSongId`, `currentKeyText`
- `scoreImageUrl`
- `idToken`
- `editingLayer`
- `willReadFrequently`
- `privateStrokes`, `sharedStrokes`
- `sketchSchemaVersion`, `coordinatePrecision`

## 9. Async safety 규약

현재 구현에서 지키는 원칙:
- 중복 listener 생성 최소화
- scope 변경 시 stream attach/detach 순차 처리
- stale emission 탐지(generation/sequence)
- 입력 중 preload 충돌 완화(드로잉 활성 시 warm prefetch 억제)

## 10. 현재 남은 과제

- 실기기 최종 증빙(iPad/iPhone) 기반의 입력/렌더 안정성 확정
- global admin 경로 확장 시 team member 전용 데이터 접근 정책 조정 여부 판단
- fallback 경로(Next Viewer) 유지/축소를 실측 데이터로 판단

---

요약:
- LiveCue 프로토콜의 canonical 경로는 `teams/{teamId}/projects/{projectId}` 축이다.
- Sync/Render/Input/Persistence 분리 이후, 상태 소유권과 동기화 규약은 코드 기준으로 정렬된 상태다.
- Next Viewer는 fallback/보조 경로로 유지한다.
