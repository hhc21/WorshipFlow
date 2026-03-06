# Tech Debt Register

작성일: 2026-03-04

## 1. 목적
- Phase 3(레거시 정리/기술 부채 청산) 결과를 문서로 고정한다.
- 중복 제거, 삭제 정책, 레거시 fallback 유지/제거 기준을 명시한다.

## 2. 이번 사이클 결정사항

### 2-1. 권한/역할 파싱 공통화
- 공통 유틸: `lib/core/roles.dart`
- 적용 범위:
  - `team_select_page.dart`
  - `team_home_page.dart`
  - `project_detail_page.dart`
  - `live_cue_page.dart`

효과:
- `admin/owner/team_admin/팀장` 등 alias 처리 분기를 단일화.
- 화면별 중복 switch 제거로 회귀 위험 감소.

### 2-2. Firestore ID/참조 유틸 공통화
- 공통 유틸: `lib/core/firestore_id.dart`
- 호환 유지: `lib/utils/firestore_id.dart`는 re-export만 수행.
- v2/legacy 개인 메모 doc id 규칙을 유틸로 통합:
  - `privateProjectNoteDocIdV2`
  - `privateProjectNoteDocIdLegacy`

### 2-3. 전역 관리자 기능 단일 진입점
- 원칙: 전역 곡 관리(생성/수정/업로드/삭제)는 `/admin`에서만 수행.
- `GlobalSongPanel`은 기본값을 읽기 전용으로 유지하고, 관리자에게 `/admin` 이동 경로를 제공.
- 중복 책임 정리:
  - `GlobalSongPanel`: 검색/조회 중심
  - `GlobalAdminPage`: 운영/변경 작업 중심

### 2-4. 대규모 삭제 로직 표준화/실패 정책
- `team_home_page.dart`의 팀/프로젝트 삭제 경로에 공통 정책 적용:
  - 배치 삭제 재시도(일시 오류 시 최대 2회)
  - 스킵 가능 오류 코드와 실패 코드를 분리 수집
  - 사용자 메시지에 생략된 정리 스텝 요약 노출

스킵 가능 오류:
- `permission-denied`
- `failed-precondition`
- `unavailable`

재시도 대상 오류:
- `aborted`
- `unavailable`
- `deadline-exceeded`
- `resource-exhausted`

## 3. 대규모 삭제 방식 비교 (클라이언트 vs Cloud Function)

| 항목 | 클라이언트 일괄 삭제 | Cloud Function 비동기 삭제 |
|---|---|---|
| 구현 속도 | 빠름 | 중간 |
| 대규모 데이터 안정성 | 보통 (세션/타임아웃 영향) | 높음 (서버 재시도/큐잉 가능) |
| 운영 가시성 | 낮음 | 높음 (로그/상태 문서화 용이) |
| 권한 모델 단순성 | 보통 | 높음 (서버 권한으로 일관 처리) |

현재 결정:
- 단기: 현재 클라이언트 삭제 경로 유지(표준화/실패 요약 적용).
- 중기: 팀 삭제를 Cloud Function 작업 큐 방식으로 이전 검토.

Cloud Function 전환 트리거:
- 팀당 프로젝트/메모/자산 규모가 커져 삭제 시간 초과가 반복될 때
- 운영자 수동 재시도가 월 2회 이상 발생할 때

## 4. Legacy Fallback 유지/제거 기준

### 4-1. 유지 중인 fallback
- 개인 프로젝트 메모 doc id:
  - v2 우선, legacy doc id/query fallback 유지
- 역할 alias fallback:
  - 한글/legacy role 값을 공통 유틸에서 정규화
- Storage URL fallback:
  - `storagePath` 실패 시 legacy `downloadUrl` 사용

### 4-2. 제거 조건
아래 조건을 모두 만족하면 fallback 제거를 시작한다.
1. 최근 4주간 fallback 경로 사용률이 1% 미만
2. 스테이징/프로덕션 회귀 테스트 통과
3. 데이터 마이그레이션 백업/롤백 절차 확정

### 4-3. 제거 순서
1. 사용률 로깅 추가
2. read fallback 비활성(쓰기는 v2만)
3. 1주 모니터링
4. legacy 분기 삭제

## 5. 후속 액션
- `team delete`를 Cloud Function 큐 방식으로 PoC 작성
- fallback 사용률 로깅 지표 추가
- 운영자 도구(`/admin`) UX 고도화 후 `GlobalSongPanel` 읽기 전용 범위 확정

---

## 6. 2026-03-04 추가 반영 (백로그 완료분)

### 6-1. 운영 지표 경로(B-08)
- 공통 로거: `lib/services/ops_metrics.dart`
- 저장 경로: `teams/{teamId}/opsMetrics/{metricId}`
- 현재 수집 이벤트:
  - `delete.team_delete` (`started/success/failed`, skipped/failed step count)
  - `delete.project_delete` (`started/success/failed`, skipped/failed step count)
  - `legacy_fallback.*` 사용 이벤트

### 6-2. legacy fallback 사용률 계측(B-09)
- 계측 위치:
  - `ProjectNotesPanel`의 legacy doc id / query fallback
  - `LiveCue` private note payload의 legacy doc id / query fallback
- 제거 판단 기준:
  - 최근 4주 fallback 이벤트 비율이 1% 미만일 때 단계적 제거 시작

### 6-3. 비동기 삭제 큐 PoC(B-05)
- PoC 워커: `functions-poc/delete_queue_worker.js`
- 설계 문서: `docs/delete_queue_poc.md`
- 큐 경로: `teams/{teamId}/deleteQueue/{requestId}`

## 7. 대형 파일 분해 설계 (Phase F)

### 7-1. `live_cue_page.dart` 분해 단위
- `live_cue_shell.dart`
  - 페이지 진입/권한/라우팅/상단 액션
- `live_cue_polling.dart`
  - setlist/liveCue 폴링 스트림, 시그니처 중복 제거, transport 정책 연계
- `live_cue_viewer.dart`
  - 악보 로딩/렌더 전략/오류 fallback
- `live_cue_drawing_layer.dart`
  - 필기/지우개/undo/save, 레이어 직렬화
- `live_cue_controls.dart`
  - 곡 이동/키 변경/오버레이 컨트롤

분리 기준:
- 데이터 동기화, 렌더링, 입력 이벤트를 같은 위젯에 혼합하지 않는다.
- 각 모듈은 외부로 노출할 상태를 DTO/Value 객체로 제한한다.

### 7-2. `team_home_page.dart` / `team_select_page.dart` 분해 단위
- `team_membership_service.dart`
  - membership mirror/self-healing 로직 분리
- `team_project_index.dart`
  - 최근 프로젝트 계산/정렬/복구 분리
- `team_invite_flow.dart`
  - 초대 수락/거절/링크 초대 검증 분리
- `team_actions.dart`
  - 삭제/역할 변경/정리 작업 분리

### 7-3. 테스트 경계 재정의
- 단위 테스트:
  - 폴링 시그니처 계산
  - role/membership/self-healing 판정
  - 삭제/정리 실패 분류(재시도/스킵)
- 위젯 테스트:
  - viewer 렌더 오류 시 fallback UI
  - 필기 레이어 툴 상태 전환
  - 팀 선택/초대 카드 상태 렌더링
- 통합 테스트:
  - LiveCue 곡 전환 + 악보 표시 + 필기 저장
  - 팀 초대/합류 요청/권한 반영 end-to-end

### 7-4. 영향 범위 추적 방식
- PR 템플릿에 모듈 단위 체크박스 추가
- 변경 파일이 속한 모듈별 필수 테스트 매핑 표 유지
- 릴리즈 노트에 `changed modules` 섹션을 강제
