# WorshipFlow Implementation Plan (Detailed Baseline)

작성일: 2026-03-12 (KST)
역할: 실행 기준선(Execution Baseline), 단계 상태판(Status Board), 검증 게이트(Release Gate), 후속 Workstream 정의 문서

근거 문서:
- `research.md`
- `product_roadmap.md`
- `system_architecture.md`
- `data_model.md`
- `firestore_rules.md`
- `livecue_protocol.md`
- `docs/release_runbook.md`
- `docs/ops/release_checklist.md`
- `docs/ops/device_validation.md`
- `docs/ops/post_deploy_runtime_issues.md`

---

# 0. 문서 운용 원칙

## 0.1 이 문서를 상세하게 유지하는 이유
이 문서는 단순 TODO가 아니라 다음 목적의 운영 기준선이다.

1. 컨텍스트 압축/세션 전환 시 복구 가능한 단일 기준 제공
2. 구현 의사결정과 검증 근거를 추적 가능한 형태로 보관
3. 코드 상태와 문서 상태를 분리하지 않고 동기화
4. SP별 완료/미완료/리스크/다음 단계를 한 문서에서 확인

## 0.2 소스 오브 트루스 규칙
- 코드가 문서보다 우선한다.
- 문서와 코드가 충돌하면 문서를 코드 기준으로 수정한다.
- 검증 결과(`analyze/test/rules`)가 문구보다 우선한다.

## 0.3 운영 정책
- GitHub는 백업/복구 용도로만 사용한다.
- 승인 없는 전면 재작성(Big Rewrite)은 금지한다.
- 대형 파일은 기능 단위로만 수정한다.
- 런타임 안전성이 기능 확장보다 우선한다.

## 0.4 현재 개발 모드
- 제품 핵심 구조는 Flutter(iOS/Android) 앱이다.
- 현재 실행 사이클은 웹 기준으로 빠르게 검증하되 앱 코어 원칙을 훼손하지 않는다.
- Next.js Viewer는 핵심 엔진이 아니라 fallback/보조 경로다.

## 0.5 작업 단위 제한 정책
한 번의 작업 사이클에서는 아래 중 1개 축을 우선 대상으로 제한한다.
- 동기화 로직
- 렌더링 로직
- 입력 처리 로직
- 브릿지 로직
- Firebase 데이터 접근 로직

복합 이슈라도 가능한 한 사이클을 분리해 회귀 범위를 줄인다.

## 0.6 대형 파일 거버넌스
고위험 파일:
- `lib/features/projects/live_cue_page.dart`
- `lib/features/teams/team_home_page.dart`
- `lib/features/admin/global_admin_page.dart`

규칙:
1. 전면 재작성 금지
2. 기능 단위 수정
3. 변경 범위 사전 명시
4. 변경 후 검증 3종 필수
5. 무관한 리팩토링 동시 수행 금지

## 0.7 상태 소유권 정책
- Sync state: `LiveCueSyncCoordinator`
- Render state: `_LiveCueRenderPresenter`
- Input state: `LiveCueStrokeEngine`
- Persistence state: `LiveCueNotePersistenceAdapter`

원칙:
- UI는 상태 소유자가 아니다.
- UI는 이벤트를 전달하고 결과를 소비한다.
- 상태 복구/정합화는 소유 계층에서만 수행한다.

## 0.8 Async Safety 정책
- `build()`에서 async 시작 금지
- listener 중복 attach 금지
- dispose 이후 도착 결과 방어
- stale emission은 generation/sequence 기준 drop
- fallback 전환이 input state를 끊지 않도록 분리

## 0.9 Observability 정책
관찰 대상:
- render pipeline state
- sync revision 변화
- input state transition
- render fallback trigger
- stream emission ordering
- preload suppression
- cache pressure/eviction

원칙:
- critical transition은 로그/metric을 남긴다.
- 임시 디버그 로그와 상시 운영 로그를 분리한다.
- 운영 로그는 first-error 분석에 재사용 가능해야 한다.

## 0.10 필수 검증 명령
코드/규칙 변경 후 반드시 실행:
- `flutter analyze`
- `flutter test --reporter=compact`
- `bash scripts/ci/test_rules.sh`

---

# 1. 현재 단계 상태판 (2026-03-12)

## 1.1 개발 단계
현재 단계:
**Post-SP-08 Mainline / Next Workstream Planning**

의미:
- SP-07 Release Gate는 저장소 기준으로 historical close 상태다.
- SP-08 score resolution / LiveCue preview stabilization 작업이 `main`에 반영되었다.
- 현재 우선순위는 후속 workstream 계획과 유지보수 리스크 관리다.

## 1.2 SP 상태 매트릭스
| SP | 상태 | 현재 판정 |
|---|---|---|
| SP-01 | 완료 | App Foundation 기준선 충족 |
| SP-01A | 완료 | Bridge Security Hardening 반영 |
| SP-02 | 완료 | LiveCue Sync Core 신뢰화 완료 |
| SP-03 | 완료 | Sync/Render/Input/Persistence 분리 완료 |
| SP-04 | 완료(구현+문서PASS) | 실기 문서 PASS, historical release evidence 반영 완료 |
| SP-05-1 | 완료 | 운영자 -> 팀 진입 |
| SP-05-2 | 완료 | setlist CRUD |
| SP-05-3 | 완료 | reorder + cue 이동 |
| SP-05-4 | 완료 | 운영자 UI 안정화 |
| SP-05-5 | 통합 완료 | 다음곡/이전곡 UX는 SP-05-4 운영 동선에 통합 관리 |
| SP-05-6 | 통합 완료 | cue 이동은 SP-05-3 범위에 통합 반영 |
| SP-05-7 | 통합 완료 | 운영자 UI 기본 기능은 SP-05-4에 통합 반영 |
| SP-06 | 완료 | Runtime Guard + Observability |
| SP-07 | 완료 | Release Gate historical close (`wf-v1.0.0` 이후 mainline 진행) |
| SP-08 | 완료 | Score Resolution & LiveCue Preview Performance main 반영 |
| SP-09 | 예정 | Music Metadata Layer |
| SP-10 | 예정 | Performance Assistance Layer |
| SP-11 | 예정 | Collaboration Layer |
| SP-12 | 예정 | Production Ops Maturity |
| SP-13 | 예정 | Score System Expansion |
| SP-14 | 예정 | Community Song Contribution Pipeline |

## 1.3 현재 우선순위
1. post-SP-08 runtime regression 관측
2. maintainability hotspot 추적
3. 다음 workstream 기준선 확정

---

# 2. 공통 아키텍처/데이터 기준선

## 2.1 Canonical Firestore 경로
- `teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}`
- `teams/{teamId}/projects/{projectId}/liveCue/state`
- `teams/{teamId}/projects/{projectId}/sharedNotes/main`
- `teams/{teamId}/userProjectNotes/{noteId}`
- `teams/{teamId}/songRefs/{songId}`
- `songs/{songId}`
- `users/{uid}/ClientProbe/mobile`

원칙:
- canonical 외 병렬 경로 신설 금지(명시 승인 없이는 불가)
- 경로 변경은 아키텍처 변경으로 간주한다.

## 2.2 라우팅 기준선
- `/admin`
- `/teams/:teamId`
- `/teams/:teamId/projects/:projectId`
- `/teams/:teamId/projects/:projectId/live`
- `/teams/:teamId/songs/:songId`

운영 동선:
`admin -> team -> project -> setlist/liveCue`

## 2.3 좌표/스키마 계약
- 좌표: 상대 좌표 `0.0 ~ 1.0`
- 정밀도: fixed-8
- 스키마 버전: `relative-v1`

## 2.4 Next.js Viewer Positioning
- 장기 핵심 엔진이 아니다.
- Flutter 경로 정상 시 우선 사용하지 않는다.
- web fallback / 브라우저 특수 이슈 우회 계층으로 유지한다.

---

# 3. SP-01 App Foundation (완료)

## 3.1 목표
- iOS/Android 실행 경로 확보
- 모바일 로그인/인증 경로 확보
- Firebase read/write probe 기준선 확보

## 3.2 범위
포함:
- 플랫폼 실행
- Firebase Auth 연결
- Firestore probe write/read

비포함:
- LiveCue 엔진 리팩토링
- 운영 기능 확장

## 3.3 Workstreams
### WS-01 플랫폼 실행 기준선
- iOS 플랫폼 생성/실행
- Android 플랫폼 생성/실행

### WS-02 모바일 인증 기준선
- 모바일 Google 로그인 경로 확인
- 사용자 세션 생성 검증

### WS-03 Firestore Probe 기준선
- `users/{uid}/ClientProbe/mobile` write/read 성공 검증

## 3.4 DoD
- [x] iOS 실행 성공
- [x] Android 실행 성공
- [x] 모바일 로그인 성공
- [x] probe write/read 성공
- [x] 정적 검증 3종 통과

## 3.5 잔여 리스크
- 기준선은 충족, 운영 회귀는 SP-07 이후 first-error 루프로 재관측

---

# 4. SP-01A Bridge Security Hardening (완료)

## 4.1 목표
- Host/Viewer 브릿지 보안 경계 강화

## 4.2 Workstreams
### WS-01 postMessage 보안 기본값 제거
- `targetOrigin='*'` 제거

### WS-02 Origin Whitelist 도입
- 허용 도메인만 메시지 수신/전송

### WS-03 토큰 전달 경계 재검증
- Host -> Viewer 토큰 전달 방식 점검

## 4.3 DoD
- [x] wildcard origin 제거
- [x] whitelist 정책 반영
- [x] 토큰 전달 경계 재검증 기록

## 4.4 리스크
- 도메인/환경 추가 시 whitelist 드리프트 가능

---

# 5. SP-02 LiveCue Sync Core 신뢰화 (완료)

## 5.1 목표
- 운영자 선택 상태와 LiveCue 로드 상태를 신뢰 가능한 단일 해석으로 정렬

## 5.2 범위
포함:
- current/next 해석 규칙
- stream ordering 안정화
- fallback 해석 안정화

비포함:
- 렌더 엔진 분리
- 입력 엔진 분리

## 5.3 Workstreams
### WS-01 current 해석 우선순위 정렬
해석 순서:
1. `currentCueLabel`
2. `songId`
3. `title+key`

### WS-02 stream ordering 안정화
- listener 중복 제거
- stale emission drop
- generation/sequence trace 강화

### WS-03 fallback 신뢰화
- unresolved state에서 안전 fallback 정책 적용
- mismatch 재현 저감

## 5.4 DoD
- [x] 운영자 선택 곡이 LiveCue 동일 로드
- [x] stream ordering 역전/충돌 미재현
- [x] score load failure 핵심 시나리오 재현 제거
- [x] 관련 테스트/정적 검증 통과

## 5.5 잔여 리스크
- 실사용 장시간 세션에서 간헐 race 가능성(관측 대상)

---

# 6. SP-03 LiveCue 책임 분리 (완료)

## 6.1 목표
- Sync/Render/Input/Persistence 책임 충돌 제거
- 단일 소유자 구조 확립

## 6.2 단계별 Workstreams
### WS-01 구조 분석/경계 정의
- `live_cue_page.dart` 책임 분류
- side-effect/hotspot 식별

### WS-02 SyncCoordinator 분리
- cue/setlist snapshot 해석 책임 이관
- attach/detach/lifecycle 단일화

### WS-03 RenderPresenter 분리
- preview/warm/fallback/viewport 책임 이관

### WS-04 StrokeEngine 분리
- begin/append/end/erase/undo/clear/tool state 이관

### WS-05 NotePersistenceAdapter 분리
- private/shared load/save/migrate 책임 이관

## 6.3 DoD
- [x] 4계층 분리 완료
- [x] UI 직접 상태 소유 제거
- [x] build side-effect 위험 구간 축소
- [x] 정적 검증/관련 테스트 통과

## 6.4 잔여 리스크
- 통합 대형 파일 유지보수 비용
- UI 통합 레이어에 로직 재침투 가능성

---

# 7. SP-04 Runtime Stability (완료: 구현+문서 PASS)

## 7.1 목표
- 실기기/장시간 세션에서 입력/렌더/메모리 안정성 확보

## 7.2 범위
포함:
- pointer/stylus 안정화
- orientation 대응
- preload 충돌 방지
- cache/eviction 전략
- 드로잉 중 불필요 rebuild 축소

비포함:
- 새 기능 추가
- 엔진 구조 변경

## 7.3 Workstreams
### WS-01 Pointer/Stroke 안정화
- 입력 device 필터링
- active pointer lifecycle 정리

### WS-02 Orientation 대응
- 회전/리사이즈 시 안전 재계산
- active pointer 정리

### WS-03 Cache Safety
- ImageCache 상한
- preview cache LRU eviction
- future cache 제한

### WS-04 Preload/Render 충돌 완화
- drawing 중 preload 억제
- fallback과 input 충돌 최소화

### WS-05 검증 패키지 정리
- 실기 시나리오 결과를 문서로 구조화

## 7.4 DoD
- [x] pointer/orientation/preload/cache 하드닝 반영
- [x] 정적 검증 3종 통과
- [x] `docs/ops/device_validation.md` 시나리오 PASS 문서화
- [ ] runbook/checklist에 시각/빌드/로그/미디어 링크 1:1 연결

## 7.5 잔여 리스크
- 실기 결과는 PASS 문서화 완료.
- SP-07 게이트는 저장소 기준으로 종료되었고, 추가 evidence 정리는 운영 문서 품질 개선 범위로 관리한다.

---

# 8. SP-05 Product Features (완료)

## 8.1 목표
- 운영자 동선에서 실운영 필수 기능 제공

## 8.2 SP-05-1 운영자 -> 팀 진입 (완료)
### Workstream
- 운영자 팀 목록 진입 경로
- 팀 홈 라우팅/context 전달 안정화
- global admin 접근 정책 반영

### DoD
- [x] `/admin`에서 팀 진입 가능
- [x] teamId 누락/오염 방어
- [x] blank body 회귀 방지

## 8.3 SP-05-2 setlist CRUD (완료)
### Workstream
- `segmentA_setlist` 조회
- 생성/수정/삭제
- 재진입 시 데이터 유지

### DoD
- [x] CRUD 전부 동작
- [x] canonical 경로 저장
- [x] 컨텍스트(teamId/projectId) 누락 없음

## 8.4 SP-05-3 reorder + cue 이동 (완료)
### Workstream
- reorder 저장 전략
- cue 이동 시 liveCue/state 반영
- current/next 정합성 유지

### DoD
- [x] reorder 저장/재진입 유지
- [x] cue 이동 반영
- [x] current/next 해석 일관성

## 8.5 SP-05-4 운영자 UI 안정화 (완료)
### Workstream
- loading/empty/error UI 정리
- admin -> team -> project -> setlist 동선 안정화
- 라우터 파라미터 검증 강화

### DoD
- [x] 주요 운영 동선에서 blank screen 제거
- [x] null/invalid context 방어
- [x] 오류 메시지 명시화

## 8.6 SP-05 전체 DoD
- [x] 운영자 기본 동선 완성
- [x] setlist 조작/이동 기능 완성
- [x] LiveCue 진입 전 운영 경로 안정성 확보

## 8.7 잔여 리스크
- 운영자 권한과 팀 멤버십 경계에서 일부 read 제한 케이스 관측 필요

---

# 9. SP-06 Runtime Guard / Observability (완료)

## 9.1 목표
- 운영 중 데이터/상태 불일치 조기 감지 및 안전 fallback 적용

## 9.2 범위
포함:
- runtime guard 계층
- ops metrics
- router guard
- setlist integrity guard
- host-viewer init payload validation

비포함:
- canonical 모델 변경
- 엔진 구조 변경

## 9.3 Workstreams
### WS-01 Runtime Guard Layer
- invalid/null snapshot/state 방어
- fallback/에러 상태 표준화

### WS-02 LiveCue State Validation
- current/next/index 유효성 검증
- invalid 상태 시 안전 복구 경로

### WS-03 Setlist Integrity Guard
- reorder 후 order 연속성 검증
- empty setlist 시 current/next clear 정책

### WS-04 Router Parameter Guard
- teamId/projectId/songId 형식 검증
- invalid route 안전 처리

### WS-05 Ops Metrics
핵심 metric:
- `runtime_guard_triggered`
- `livecue_state_invalid`
- `setlist_order_invalid`
- `router_invalid_id`
- `firestore_snapshot_error`

## 9.4 DoD
- [x] guard/metric 핵심 축 반영
- [x] critical flow 보호 확인
- [x] 정적 검증 3종 통과

## 9.5 잔여 리스크
- metric 노이즈와 실제 장애 상관성 튜닝 필요

---

# 10. SP-07 Release Gate (완료)

## 10.1 목표
- 배포 가능 여부를 문서/검증/증빙으로 최종 판정

## 10.2 범위
포함:
- static gate
- functional gate
- runtime gate
- device validation evidence 연결
- first-error/regression 운영 루프 준비

비포함:
- 신규 제품 기능 개발
- 엔진 구조 재설계

## 10.3 Workstreams
### WS-01 Static Gate 확정
- analyze/test/rules 최신 PASS 확보

### WS-02 Functional Gate 점검
- admin -> team -> project -> setlist/liveCue 동선
- setlist CRUD/reorder/cue 이동 회귀 확인

### WS-03 Runtime Gate 점검
- guard/metric 동작
- invalid route/state 방어

### WS-04 Device Evidence 연결
- `device_validation.md` 결과를 checklist/runbook 증빙 필드와 연결

### WS-05 Release Evidence 패키지 완결
필수 필드:
- timestamp(KST)
- build/release version
- log reference
- screenshot/video link

### WS-06 승인 판정 기록
- `APPROVED` 또는 `BLOCKED` 근거 기록

## 10.4 DoD
- [x] static gate PASS
- [x] 기능/런타임 게이트 기준 정렬
- [x] device validation PASS 문서 반영
- [x] 최신 검증 결과를 `docs/release_evidence.md`에 반영
- [x] release evidence snapshot과 저장소 이력이 SP-07 종료 상태를 지지
- [x] post-release runtime 이슈는 SP-08 후속 안정화 범위로 이관
- [x] main 기준 상태판에서 SP-07 closed 처리

## 10.5 현재 판정
- 상태: Closed (historical release gate complete)
- 근거:
  - `wf-v1.0.0` 태그와 `SP-07 release evidence recorded` 이력이 존재한다.
  - 이후 SP-08 구현/리팩토링 커밋이 `main`에 순차 반영되었다.
- 해석 원칙:
  - `docs/release_evidence.md`는 SP-07 말단 시점의 snapshot 문서다.
  - 그 snapshot에 남아 있던 residual issue는 이후 post-release stabilization/SP-08 범위로 이관되었다.
- 결론: 현재 저장소 기준 상태판에서는 SP-07을 더 이상 진행중으로 보지 않는다.

## 10.6 SP-07 후속 관측 메모
- historical release evidence와 운영 로그 링크 정밀도는 추가 문서 개선 여지가 있다.
- post-deploy runtime issue는 SP-07 open blocker가 아니라 후속 안정화 입력으로 관리한다.
- LiveCue 초기 attach/re-entry 타이밍 불안정 가능성
  - auth-ready 시점, first snapshot 수신 시점, watchdog 시작 시점, fullscreen/operator 전환 타이밍에 따라 first-entry 지연/재시도 필요 상황이 재현될 수 있음
- legacy setlist 항목의 canonical field 오염 가능성
  - `songId/title/key/cueLabel/displayTitle` 혼재 데이터에서 display 문자열이 해석 경로에 개입해 project/LiveCue 해상도 불일치가 재발할 수 있음

---

# 11. SP-08 Score Resolution & LiveCue Preview Performance (상세)

상태: 완료 (`main` 반영)

## 11.1 Goal
- project / library / LiveCue 전 구간에서 score resolution/preview 동작을 동일 규칙으로 정렬
- LiveCue first-entry 지연을 현재 baseline(약 15s) 대비 실질적으로 단축
- SP-13/SP-14 확장 이전에 안정적인 해상도/프리뷰 성능 기반선을 확립

## 11.2 Scope
### 1) Score Resolution Consistency
대상:
- project setlist
- song library
- LiveCue preview
- segment editors

핵심:
- 모든 score lookup이 단일 resolver 경로를 사용
- `songId` 우선 해석
- title-only 상황에서 fallback 해석 안정화
- `normalized title` / `aliases` / `team songRefs` 처리 일관화
- display 문자열(`displayTitle`, `cueLabel`)은 lookup source-of-truth로 사용하지 않음

### 2) Preview Flow Consistency
대상:
- project setlist 진입
- library 진입
- LiveCue preview 진입

핵심:
- in-app preview 우선
- 외부 새 탭은 선택형 fallback로만 허용
- 내비게이션 일관성 유지: `project -> song detail -> back -> project`
- 프리뷰 경로별 중복 resolver 로직 제거

### 3) LiveCue First-Entry Performance Optimization
목표:
- first useful render를 가능한 빠르게 노출
- 전체 asset 준비 전 첫 페이지 우선 렌더

전략:
- First Useful Render 전략
  - LiveCue enter
  - `songId` resolve
  - asset metadata fetch
  - first page render
  - remaining pages preload
- Storage 요청 최적화
  - 중복 `getDownloadURL()` 최소화
  - resolved storage URL 캐시 재사용
  - 가능한 경로는 병렬 요청으로 전환
- staged loading
  1. first page
  2. remaining pages preload
  3. background cache

## 11.3 Out of Scope
- community score upload pipeline (`songs_pending`) 전체 구현
- moderation system
- advanced metadata system
- collaboration editing features
- canonical 데이터 모델 전면 변경

위 항목은 SP-13/SP-14 이후 단계에서 다룬다.

## 11.4 Workstreams
### WS-01 Unified Resolver Path
- score lookup 공통 경로 강제
- fallback 우선순위/정규화 규칙 고정
- legacy setlist(`songId` 누락) sanitize/backfill 동작 점검

DoD:
- [x] lookup 경로가 화면별로 분산되지 않고 단일화됨
- [x] title-only fallback 동작이 project/library/LiveCue에서 동일함
- [x] legacy 항목 해석 실패율 감소

### WS-02 Preview Consumer Alignment
- preview consumer(관리자/사용자/프로젝트/LiveCue) 동작 통일
- 지원 포맷 정책 통일: `jpg/png/jpeg/webp/pdf`
- preview 진입/복귀 내비게이션 회귀 제거

DoD:
- [x] preview 진입점별 UX/동작이 일관됨
- [x] in-app preview 기본 동작 유지, 새 탭은 fallback로만 동작
- [x] 복귀 동선(project context) 회귀 없음

### WS-03 LiveCue First-Entry Latency Hardening
- first page 우선 렌더로 초기 대기시간 축소
- sequential Storage asset loading 병목 제거
- repeated `getDownloadURL()` 호출 병목 완화
- first useful render 이전 async loader 재실행 최소화

DoD:
- [x] first useful render 시간이 기존 baseline 대비 유의미하게 감소
- [x] 첫 페이지 렌더가 전체 asset 준비를 기다리지 않음
- [x] 중복 Storage 요청이 관측 로그 기준 감소

### WS-04 Read Amplification Guard
- resolver/preview 공용 경로의 중복 read 패턴 관측/억제
- broad fallback query 사용 빈도 metric 추적
- 동일 곡 다중 surface 진입 시 캐시 재사용 검증

DoD:
- [x] 동일 플로우 내 중복 song lookup read가 감소
- [x] `team songRefs`/canonical `songs` 중복 조회 억제
- [x] 신규 read amplification 회귀 없음

## 11.5 Definition of Done (통합)
### Resolution Stability
- [x] 모든 score lookup이 unified resolver path를 사용
- [x] fallback title resolution이 일관되게 동작
- [x] legacy setlist(`songId` 없음) 항목도 해석 가능

### Preview Consistency
- [x] library/project/LiveCue 프리뷰 진입 동작 일관
- [x] preview 이후 back navigation이 문맥을 유지

### LiveCue Performance
- [x] LiveCue first useful render가 현재 baseline(약 15s) 대비 체감 가능한 수준으로 단축
- [x] 남은 asset 전체 준비 완료 전에도 first page가 먼저 표시됨
- [x] repeated `getDownloadURL()` 호출이 최소화

### System Integrity
- [x] Firestore read amplification 신규 회귀 없음
- [x] 기존 테스트/게이트 유지
- [x] canonical/fallback 곡 모두 preview/resolution 정상

## 11.6 Verification
- `flutter analyze` PASS
- `flutter test --reporter=compact` PASS
- `bash scripts/ci/test_rules.sh` PASS
- 수동 검증:
  - 문제 곡/정상 곡 각각 project + library + LiveCue preview 비교
  - first-entry/재진입 latency 비교
  - fallback 경로(무 `songId`) 해석 일관성 확인
  - read-heavy 시나리오에서 broad query metric 확인

## 11.7 Expected Impact
- SP-08은 향후 확장(SP-13 canonicalization, SP-14 contribution pipeline)의 성능/안정성 기반선을 제공
- 사용자 체감 개선:
  - LiveCue 첫 진입 대기시간 단축
  - 곡 해상도 실패율 감소
  - preview 경로 혼선 감소

## 11.8 리스크
- legacy 데이터 품질 편차로 fallback 오탐 가능성
- 네트워크/브라우저 상태에 따라 first-entry 개선폭 변동 가능성
- 캐시 정책 과도 적용 시 stale preview 노출 위험(관측 로그로 추적 필요)

---

# 12. SP-09 Music Metadata Layer (상세)

상태: 예정

## 12.1 목표
- setlist item 단위 음악 메타데이터를 구조화해 운영 품질 향상
- LiveCue에서 read-only 소비 가능한 표준 메타 계약 확립

## 12.2 범위
포함:
- `segmentA_setlist/{itemId}` 메타 필드 확장
- 운영자 편집 UI 입력/검증
- LiveCue current/next 메타 read-only 노출

비포함:
- 자동 편곡/추천
- 오디오 DSP/분석 엔진

## 12.3 데이터 계약(초안)
필수/권장 필드:
- `tempoBpm` (int, 20~300)
- `timeSignature` (string, 예: `4/4`, `3/4`, `6/8`)
- `sectionMarkers` (list, optional)
- `arrangementNote` (string, optional)
- `keyText` (기존 규약 재사용)

정합성 규칙:
- 범위 외 값은 저장 차단
- null 허용 필드와 미입력 필드를 구분
- legacy 항목은 기본값 강제가 아니라 optional 소비

## 12.4 Workstreams
### WS-01 Metadata Contract Definition
세부:
- 필드 타입/범위/기본값/누락 정책 확정
- 문서(`data_model.md`, `livecue_protocol.md`) 동기화

DoD:
- [ ] 메타 계약 표 확정
- [ ] 저장/조회 경로에서 타입 드리프트 없음

### WS-02 Admin Editing UX
세부:
- setlist 항목 편집 패널에 메타 입력 추가
- 저장 전 validation + 오류 메시지 표준화

DoD:
- [ ] invalid metadata 저장 차단
- [ ] 오류 메시지 사용자 이해 가능 수준

### WS-03 LiveCue Consumption
세부:
- current/next 영역 read-only 표기
- sync/input/render ownership 침범 금지

DoD:
- [ ] 메타 표시는 가능, 엔진 소유권 침범 없음

### WS-04 Legacy Compatibility + Backfill
세부:
- 메타 없는 기존 항목 호환
- 선택적 backfill 유틸리티

DoD:
- [ ] 기존 데이터로 회귀 없음
- [ ] backfill 실행 여부와 무관하게 앱 정상 동작

### WS-05 Observability
세부:
- metadata validation failure 로그
- out-of-range 입력 빈도 추적

DoD:
- [ ] metadata 오류가 무음 실패되지 않음

## 12.5 SP-09 DoD
- [ ] metadata 저장/조회 구현
- [ ] validation 정책 반영
- [ ] LiveCue read-only 소비 반영
- [ ] legacy 호환성 확인
- [ ] 정적 검증 3종 통과

## 12.6 검증 포인트
- setlist 재진입 시 metadata 유지
- current/next 전환 시 metadata 일관성
- 잘못된 값 입력 시 저장 차단 + 안내 메시지

## 12.7 리스크
- metadata 필드 확장으로 UI 복잡도 증가
- 운영자 입력 품질 편차

---

# 13. SP-10 Performance Assistance Layer (상세)

상태: 예정

## 13.1 목표
- 라이브 운영 보조 기능(tempo/count-in/timer/scroll) 제공
- 코어 sync/input 안정성 훼손 없이 보조 계층으로 구현

## 13.2 범위
포함:
- tempo tap
- count-in
- cue timer
- auto scroll assist
- SP-09 metadata(`tempoBpm`, `timeSignature`) 기반 보조 기능 연동

비포함:
- MIDI 연동
- 오디오 DSP
- LiveCue 코어 엔진 재설계

## 13.3 Workstreams
### WS-01 Tempo Tap Engine
세부:
- 탭 간격 기반 BPM 계산
- 이상치 제거/안정화 평균
- setlist item `tempoBpm` 존재 시 초기 템포 기준값으로 연동

DoD:
- [ ] 느린/빠른 탭 입력에서 BPM 안정 출력
- [ ] metadata 연동 시에도 수동 탭 보정 로직 충돌 없음

### WS-02 Count-in Flow
세부:
- 시작/취소/재시작 상태 모델
- 곡 전환/큐 이동과의 충돌 방지

DoD:
- [ ] count-in 상태 전이 deterministic

### WS-03 Cue Timer
세부:
- 경과 시간 표시
- pause/resume/reset
- 재진입 시 정책(복원/초기화) 명시

DoD:
- [ ] 타이머 상태가 전이 규칙대로 유지

### WS-04 Auto Scroll Assist
세부:
- 속도 프리셋/사용자 커스텀
- 사용자 수동 조작 시 즉시 중단
- 장시간 세션 성능 영향 측정

DoD:
- [ ] auto scroll이 필기/입력과 충돌하지 않음

### WS-05 Runtime/Observability Guard
세부:
- `assist_start/assist_stop/assist_error` 로그
- 세션 메모리/리빌드 영향 관측

DoD:
- [ ] 보조 기능 장애가 운영 로그로 추적 가능

## 13.4 SP-10 DoD
- [ ] tempo tap/count-in/timer/scroll 기본 기능 동작
- [ ] core sync/input 경계 침범 없음
- [ ] 장시간 세션 성능 회귀 허용 범위 내
- [ ] 정적 검증 3종 통과

## 13.5 검증 포인트
- BPM 계산 일관성
- `tempoBpm/timeSignature` metadata 반영 일관성
- 곡 전환 중 보조 기능 상태 전이
- 필기 중 auto scroll 충돌 여부

## 13.6 리스크
- 보조 기능 추가로 UI 복잡도 증가
- timer/scroll 상태가 sync 이벤트와 경쟁할 수 있음

---

# 14. SP-11 Collaboration Layer (상세)

상태: 예정

## 14.1 목표
- multi-user 협업을 위한 shared note/cue/presence 기반 확장
- 충돌/권한/동시성 규칙을 deterministic하게 정의

## 14.2 범위
포함:
- shared notes 협업
- presence 모델
- cue 협업 동기화
- 충돌 처리/권한 정책
- comment system (문맥 기반 코멘트/스레드)

비포함:
- 음성/영상 실시간 통신
- 전역 권한 체계 전면 개편

## 14.3 Workstreams
### WS-01 Collaboration Contract
세부:
- 이벤트 모델(`join/leave/edit/commit/sync`)
- revision/token 기반 ordering 정책

DoD:
- [ ] 이벤트 계약 문서+코드 정렬

### WS-02 Presence Model
세부:
- online/idle/offline 상태
- heartbeat/TTL 정책

DoD:
- [ ] presence state 오탐/유실률 허용 범위 내

### WS-03 Shared Notes Concurrency
세부:
- 동시 편집 충돌 정책(last-write 금지 여부 포함)
- 병합 가능/차단 범위 정의

DoD:
- [ ] 동시 편집에서 데이터 유실 재현 방지

### WS-04 Cue Collaboration
세부:
- 변경 주체 우선순위(leader/admin)
- 중복 명령/역전 이벤트 방어
- stale event 처리 규칙 강화

DoD:
- [ ] 다중 기기 cue ordering deterministic

### WS-05 Role/Permission Matrix
역할:
- viewer
- editor
- leader
- team admin
- global admin

세부:
- 역할별 read/write 범위 확정
- rules/UI/code 정합성 검증

DoD:
- [ ] 무권한 write 차단 + 사용자 피드백 일관성

### WS-06 Observability + Incident Runbook
세부:
- 협업 전용 metric 확장
- incident runbook 협업 시나리오 추가

DoD:
- [ ] 협업 장애 원인 추적 가능한 로그 체계

### WS-07 Comment System
세부:
- score/setlist/liveCue 문맥 기반 코멘트 스레드 모델 정의
- 코멘트 생성/수정/삭제 권한 정책 정의
- 코멘트 알림/미확인 상태 표기 정책 정의

DoD:
- [ ] comment thread 생성/조회/권한 규칙이 협업 모델과 일치

## 14.4 SP-11 DoD
- [ ] shared note 동시 편집 정책 구현
- [ ] presence 상태 모델 구현
- [ ] cue 협업 ordering 보장
- [ ] comment system 정책/동작 구현
- [ ] 권한 정책 정합성 확보
- [ ] 정적 검증 3종 통과

## 14.5 검증 포인트
- 두 명 이상 동시 편집 시 유실/충돌 여부
- 다중 기기 cue 이동 충돌 처리
- comment thread 권한/동기화 일관성
- 역할별 권한 차단 메시지 정확성

## 14.6 리스크
- 협업 기능은 race 조건 폭증 가능성 높음
- 운영 로그 볼륨 증가로 노이즈 관리 필요

---

# 15. SP-12 Production Ops Maturity (상세)

상태: 예정

## 15.1 목표
- 릴리스/운영 체계를 반복 가능한 표준으로 고도화
- 증빙/모니터링/롤백/회고 루프를 제도화

## 15.2 범위
포함:
- release train 표준화
- gate 자동화 보강
- monitoring/alerting 정책
- rollback/recovery 절차
- post-release review 정례화
- Firebase Hosting 배포 표준화
- production Firestore rules 검증/배포 체계
- CI/CD 파이프라인 운영 기준
- release tagging 체계

비포함:
- 플랫폼 전환
- 인프라 전면 재구축

## 15.3 Workstreams
### WS-01 Release Train Standardization
세부:
- 버전 태깅 규칙
- artifact naming 규칙
- release note 템플릿

DoD:
- [ ] 릴리스 문서 형식 일관성 확보

### WS-02 Gate Automation Enhancement
세부:
- static gate 결과 자동 수집
- evidence 필드 자동 채움 가능한 항목 자동화
- CI/CD 파이프라인에서 gate 결과 자동 게시

DoD:
- [ ] 수동 누락률 유의미 감소
- [ ] CI/CD에서 gate PASS/FAIL 추적 가능

### WS-03 Monitoring & Alerting
세부:
- 핵심 metric 대시보드
- alert threshold/노이즈 억제 정책
- 배포 직후 모니터링 초기 관측 절차 고정

DoD:
- [ ] critical 이슈 조기 탐지율 개선

### WS-04 Rollback & Recovery
세부:
- 롤백 트리거 기준
- 실행 절차/권한/책임자 명시
- 복구 후 검증 체크리스트

DoD:
- [ ] 롤백 드릴 실행 기록 확보

### WS-05 Post-Release Review Loop
세부:
- first-error 회고 템플릿
- 회귀 유형 분류 체계
- 다음 릴리스 액션아이템 연동

DoD:
- [ ] 릴리스마다 postmortem/retro 산출물 생성

### WS-06 Deployment Infrastructure Governance
세부:
- Firebase Hosting 배포 절차/권한 분리
- production Firestore rules 배포 전/후 검증 절차
- release tagging 규칙(semantic/date based) 고정

DoD:
- [ ] Hosting/rules/tagging 절차가 runbook/checklist와 일치

## 15.4 SP-12 DoD
- [ ] 릴리스 프로세스 재현 가능
- [ ] Firebase Hosting 배포 기준 확정
- [ ] production Firestore rules 배포 검증 체계 확정
- [ ] CI/CD 파이프라인 기준 확정
- [ ] release tagging 기준 확정
- [ ] 모니터링/알림/롤백 체계 운영 가능
- [ ] post-release review 정례화
- [ ] 정적 검증 3종 통과

## 15.5 검증 포인트
- 릴리스 증빙 누락률
- 경보 false-positive 비율
- 롤백/복구 리드타임

## 15.6 리스크
- 프로세스 자동화 미흡 시 문서-실행 괴리 재발

---

# 16. SP-13 Score Canonicalization & Resolution Layer (상세)

상태: 예정

## 16.1 Goal
Establish the canonical score identity and resolution layer so preview consistency, stable lookup, and scalable discovery are guaranteed across all consumers.
SP-13 acts as the data/resolution foundation that SP-14 (community contribution pipeline) must rely on.

## 16.2 Problem
Current score handling has several limitations:
- score preview behavior is inconsistent across UI entry points
- some flows still open scores in a new browser tab
- LiveCue score resolution may fail when metadata is incomplete
- score discoverability is limited without search indexing

영향:
- 실시간 예배 운영 중 탐색/확인 동선이 느려짐
- 동일 곡이라도 진입점에 따라 사용자 경험이 달라짐

## 16.3 Scope
SP-13 introduces:
1. Unified in-app score preview
2. Stable score resolution pipeline
3. Score preview consistency across all UI entry points
4. Search token indexing for song discovery
5. Canonical score identity contract and lookup-source rules

비범위:
- LiveCue 엔진 ownership 구조 변경
- canonical Firestore 경로 재설계

## 16.4 Supported Preview Formats
In-app preview must support:
- `jpg`
- `png`
- `jpeg`
- `webp`
- `pdf`

Preview must render consistently in:
- score library
- project score access
- LiveCue preview
- admin score library

## 16.5 Score Resolution Pipeline
Resolution must always run after sanitization.

Lookup priority order:
1. `songId`
2. `teams/{teamId}/songRefs`
3. `canonicalTitle + canonicalKey`
4. `aliases`
5. `searchTokens`

Normalization rules:
- remove decorated display text
- normalize whitespace
- normalize key values
- support legacy setlist entries

### Canonical Score Identity
Canonical fields:
- `songId` (primary identity)
- `canonicalTitle`
- `canonicalKey`
- `aliases[]`
- `searchTokens[]`
- `displayTitle` (render-only)

Explicit rule:
- `displayTitle` and `cueLabel` must NOT be used as lookup source-of-truth fields.
- alias collision은 반드시 동일한 canonical `songId`로 수렴해야 하며, 표기 변형(예: `Way Maker` / `Waymaker` / `Way maker`)이 별도 canonical identity를 만들면 안 된다.

### Legacy Compatibility Strategy
- sanitize decorated strings before resolution
- support on-read sanitization
- optional on-write repair
- gradual backfill for missing `songId`
- maintain compatibility with existing project documents
- no forced full migration

목표:
- “score not found” 오류 감소
- LiveCue score loading 안정화

## 16.6 Implementation Areas
Flutter UI:
- `lib/features/songs/global_song_panel.dart`
- `lib/features/songs/song_detail_page.dart`
- project score preview entry points
- LiveCue preview entry points
- preview consumers must consume the same resolver output:
  - admin library preview
  - user library preview
  - project preview
  - LiveCue preview

Firestore:
- `songs` collection
- search token indexing

## 16.7 Workstreams
### WS-01 Unified In-App Preview
- 인앱 기본 프리뷰(새 탭 강제 제거)
- 진입점별 UI/동작 일관성 보장
- 모든 preview consumer가 동일 resolver output을 사용하도록 정렬

### WS-02 Resolution Stability
- canonical identity 기반 5단계 해석 파이프라인 고정
- legacy 데이터 fallback 안정화
- displayText/cueLabel 비권위 원칙 적용 및 검증

### WS-03 Discovery Indexing
- `searchTokens` 생성/갱신 정책
- 부분 검색 정확도 개선

### WS-04 Regression Safety
- 기존 project/LiveCue 동선 회귀 방지
- 오류 메시지 구체화
- on-read sanitize / optional on-write repair / gradual backfill 회귀 검증

## 16.8 Definition of Done
SP-13 완료 조건:
- [ ] score preview opens in-app by default
- [ ] preview behavior is consistent across all entry points
- [ ] canonical score identity contract is defined and enforced
- [ ] LiveCue score resolution is stable
- [ ] legacy setlist items resolve correctly
- [ ] search token indexing improves song discovery
- [ ] SP-14가 SP-13 canonical identity/resolution 규칙을 전제로 설계되도록 기준선 연결

## 16.9 Verification
Required checks:
- [ ] `flutter analyze` PASS
- [ ] `flutter test --reporter=compact` PASS
- [ ] `bash scripts/ci/test_rules.sh` PASS
- [ ] manual preview verification
- [ ] canonical resolver validation (`songId -> songRefs -> canonicalTitle+canonicalKey -> aliases -> searchTokens`)
- [ ] `displayTitle`/`cueLabel`이 lookup source-of-truth로 사용되지 않는지 회귀 검증

---

# 17. SP-14 Community Song Contribution Pipeline (상세)

상태: 예정

## 17.1 Goal
Define a quality-gated ingestion pipeline for community-contributed scores, with moderation and canonical database integration.
SP-14는 direct insert 단계가 아니라 controlled ingestion 단계이며, canonical identity/resolution은 SP-13 규칙을 그대로 의존한다.

## 17.2 Problem
현재 곡 DB는 관리자 업로드 의존도가 높아 다음 문제가 있다:
- database growth is slow
- admin workload increases over time
- users cannot contribute missing songs
- duplicate songs may appear across teams

## 17.3 Contribution Flow
Pipeline model:
`User Upload -> Pending Storage -> Automated Validation -> Moderation Review -> Canonical Resolution -> Global Score DB`

Steps:
1. user uploads song score
2. submission stored in pending collection (`songs_pending`)
3. automated validation runs before moderation
4. moderators review validated submissions
5. canonical resolution is applied using SP-13 rules
6. only approved items are inserted into canonical DB

## 17.4 Firestore Data Model
Canonical song database:
- `songs/{songId}`

Staging submissions (non-canonical):
- `songs_pending/{submissionId}`

Pending staging fields:
- `uploaderId`
- `titleRaw`
- `keyRaw`
- `sourceLink`
- `uploadTimestamp`
- `validationStatus`
- `moderationStatus`

Optional staging metadata:
- `artist`
- `bpm`
- `tags`
- `category`
- `aliases`

규칙:
- `songs_pending` 레코드는 raw/staging 데이터이며 canonical score로 취급하지 않는다.

## 17.5 Moderation Actions
Administrators can:
- approve submission
- link to existing canonical song
- reject submission
- request edit
- merge duplicate songs

Policy:
- moderation 대상은 automated validation을 통과한 항목으로 제한한다.
- approved songs are written into `songs/{songId}`
- rejected submissions remain in moderation logs
- canonical insertion rules:
  - canonical `songId` 생성
  - title/key 정규화
  - 필요 시 aliases 연결
  - `searchTokens` 갱신
  - uploader attribution 메타데이터 보존
- duplicate/alias handling:
  - 기존 `songId`에 alias로 연결
  - alternate key/version으로 연결
  - 중복 제출로 판단 시 reject

## 17.6 Database Growth Strategy
Expected benefits:
- scalable song database expansion
- community-driven content growth
- reduced administrator bottleneck
- improved song availability across churches

## 17.7 Safety Requirements
The system must ensure:
- moderation before canonical insertion
- duplicate detection
- metadata normalization
- compatibility with existing projects
- user upload는 pending/moderation 파이프라인을 우회해 canonical library를 직접 수정할 수 없다.
- SP-14는 SP-13의 canonical identity/resolution/sanitization 규칙을 재사용하며, 별도 규칙을 재구현하지 않는다.
- pending submission은 validation/moderation 과정에서 기존 canonical `songId`와 매칭될 수 있지만, `matched`는 `approved`를 의미하지 않으며 명시적 moderation approval 없이는 canonical 삽입/갱신이 불가하다.

Legacy projects must continue to work without forced schema migration.

## 17.8 Workstreams
### WS-01 Submission Intake
- 사용자 업로드 입력 수집
- raw payload를 `songs_pending`에 staging 저장

### WS-01A Automated Validation Stage
- canonical title normalization
- key normalization
- duplicate detection against canonical library
- resolution attempt via SP-13 resolver
- metadata completeness check
- invalid submissions는 pending 상태 유지(`validationStatus=failed`)

### WS-02 Moderation Console
- approve/reject/request edit/merge duplicate 처리
- moderation audit log 유지
- `validationStatus=passed` 항목 우선 검토

### WS-03 Canonical Integration
- moderation-approved 항목만 `songs/{songId}` 승격
- canonical insertion rule(정규화/aliases/searchTokens/attribution) 적용
- 기존 song 중복/충돌 처리(alias link / alternate key / reject)

### WS-04 Compatibility Guard
- 기존 LiveCue/project 흐름 무중단 보장
- legacy setlist 호환성 검증
- SP-13 resolver output과 일관성 검증

## 17.9 Definition of Done
SP-14 완료 조건:
- [ ] users can submit songs
- [ ] submissions are stored in `songs_pending`
- [ ] automated validation stage runs before moderation
- [ ] admins can approve/reject/link/request-edit submissions
- [ ] approved songs appear in the global `songs` collection
- [ ] canonical insertion rules(songId/title-key normalization/aliases/searchTokens/attribution) 적용
- [ ] existing LiveCue flows continue to function without breaking changes

## 17.10 Verification
Required checks:
- [ ] `flutter analyze` PASS
- [ ] `flutter test --reporter=compact` PASS
- [ ] `bash scripts/ci/test_rules.sh` PASS
- [ ] submission -> validation -> moderation -> canonical DB flow verified
- [ ] invalid submission이 pending에 잔류하는지 검증
- [ ] bypass 시도 시 canonical write가 차단되는지 검증

---

# 18. Cross-SP 검증 루프

## 18.1 Research Refresh 루프
- SP 종료마다 `research.md` 업데이트
- 코드와 문서 drift 재판정

## 18.2 Logic Verification 루프
매 단계 공통 점검:
- 데이터 흐름 꼬임
- Future/Stream ordering
- 상태 전이 충돌
- side-effect 위치 적절성

## 18.3 Platform Regression 루프
- iPad/iPhone/Android 태블릿 시나리오 재검증
- fallback 경로와 canonical 경로 동작 비교

## 18.4 First-Error 루프
필수 기록 필드:
- timestamp
- device/browser/build
- 재현 조건
- 로그 참조
- 스크린샷/영상 링크

## 18.5 Post-SP-07 고위험 안정화 검증
우선 검증 대상:
- LiveCue initial attach/re-entry timing
  - attach state machine 단계별 로그(attach start/auth-ready/first snapshot/watchdog start-watchdog clear) 관측
  - first-snapshot timeout metric 수집 및 브라우저/네트워크 조건별 재진입 회귀 테스트
- legacy setlist canonical hygiene
  - display-text 비권위(non-authoritative) 원칙 검증
  - sanitize/backfill 전략이 project/LiveCue/library 공통 해상도에서 일관 동작하는지 검증
- 대형 통합 UI 파일 회귀 핫스팟
  - 한 번에 한 핫스팟만 수정(미니 패치)
  - 수정 축(preview/reorder/retry/admin-path)을 분리해 교차 회귀 여부를 시나리오별로 검증

---

# 19. Release Evidence 패키지 표준

## 19.1 Evidence 필수 필드
- Timestamp (KST)
- Build/Release Version
- Scenario ID
- Command/Log Reference
- Screenshot/Video Link
- Result(PASS/FAIL)

## 19.2 Evidence 저장 위치
- 실행 체크: `docs/ops/release_checklist.md`
- 절차/판정: `docs/release_runbook.md`
- 기기 시나리오: `docs/ops/device_validation.md`
- 사후 이슈: `docs/ops/post_deploy_runtime_issues.md`

## 19.3 승인 상태 표기 규칙
- `READY FOR APPROVAL`: 게이트 통과 + 증빙 패키지 완결
- `BLOCKED`: 게이트 실패 또는 증빙 누락
- `DEPLOYED`: 실제 배포 실행 확인 후 표기

---

# 20. Architecture Risk Register

## 20.1 Large UI Integration Risk
대상:
- `live_cue_page.dart`
- `segment_a_page.dart`
- `team_home_page.dart`
- `global_admin_page.dart`

리스크:
- UI 레이어로 상태/비즈니스 로직 재침투
- 통합 파일 간 교차 회귀
  - preview 수정 후 reorder 회귀
  - retry 수정 후 fullscreen 회귀
  - admin 경로 수정 후 user 경로 회귀
  - loading/error/empty 상태의 독립 회귀

완화:
- 기능 단위 분리
- 상태 소유권 정책 강제
- 변경 후 검증 3종 + 회귀 체크
- 최소 패치 원칙 유지, 전면 재작성 금지, 한 번에 한 hotspot만 수정

## 20.2 Firestore Path Coupling Risk
리스크:
- 경로 변경 시 광범위 영향

완화:
- 경로 헬퍼/중앙 accessor 유지
- canonical 변경은 별도 승인

## 20.3 Sync Ordering Drift Risk
리스크:
- 협업 단계에서 race/역전 재발

완화:
- generation/sequence 유지
- stale emission drop 정책 유지
- first-error 루프로 조기 감지

## 20.4 Documentation Drift Risk
리스크:
- 문서와 코드 불일치로 잘못된 의사결정 유발

완화:
- SP 종료 시 plan/research/map 동기화
- release gate 전 문서 감사 고정

## 20.5 LiveCue Initial Attach/Re-entry Timing Risk
리스크:
- first-entry attach가 auth readiness/first snapshot/watchdog 타이밍에 민감하여 초기 진입 지연 또는 재시도 의존이 재발할 수 있음
- operator/fullscreen 전환 및 네트워크 변동 시 current/next 반영 지연이 발생할 수 있음

완화:
- attach state machine 명시화(상태 전이/실패 전이/재시도 전이)
- auth-ready gating 기준 고정
- first-snapshot timeout metric 및 re-entry regression 시나리오 상시 점검

## 20.6 Legacy Setlist Canonical Contamination Risk
리스크:
- legacy 항목에서 `songId/title/key/cueLabel/displayTitle`가 혼재되어 display 문자열이 canonical 해석을 오염시킬 수 있음
- library에서는 열리지만 project/LiveCue에서는 실패하는 간헐 불일치가 발생할 수 있음

완화:
- canonical field 우선순위 강제(`songId -> songRefs -> normalized title -> searchTokens`)
- display-text non-authoritative 원칙 고정
- sanitize/backfill 전략과 legacy compatibility validation을 릴리즈 전 회귀 체크에 포함

---

# 21. 다음 실행 순서 (실행형 로드맵)

## 21.1 즉시 실행 (Post-SP-08)
1. post-SP-08 runtime regression 샘플 수집
2. maintainability hotspot 추적 갱신
3. 다음 workstream 기준선 확정

## 21.2 다음 착수 (SP-09+ 계획)
1. metadata 계약 입력 범위 확정
2. LiveCue attach/re-entry timing hardening 필요도 재판정
3. legacy setlist sanitize/backfill 검증 케이스 유지
4. SP-13/SP-14 의존 관계 정렬

## 21.3 중기 (SP-09~SP-14)
- SP-09: metadata 계약 + 입력/검증
- SP-10: performance assist 기능 계층
- SP-11: collaboration 계약/권한/동시성
- SP-12: 운영 프로세스 성숙화
- SP-13: score preview/resolution/discovery 확장
- SP-14: community contribution/moderation pipeline

## 21.4 리스크 기반 후속 안정화 우선순위
1. LiveCue initial attach/re-entry timing hardening
2. legacy setlist canonical hygiene(sanitize/backfill) hardening
3. 대형 통합 UI 파일 hotspot별 분할 안정화(한 사이클 한 영역 원칙)

---

# 22. 최종 성공 기준

## 22.1 구조/품질
- [ ] 상태 소유권 경계 유지
- [ ] async safety 위반 없음
- [ ] 정적 검증 3종 지속 PASS

## 22.2 운영 기능
- [ ] 운영자 동선 일관성
- [ ] setlist/cue 흐름 안정성
- [ ] LiveCue 진입/동기화 신뢰성

## 22.3 운영 안정성
- [ ] first-error 루프 작동
- [ ] 주요 runtime issue 재발률 감소

## 22.4 릴리스 준비
- [x] SP-07 historical close 반영
- [x] 승인/배포 이력 기준선 기록
- [x] 배포 후 회귀 루프 시작

## 22.5 확장 준비
- [x] SP-08 착수 조건 충족 및 main 반영 완료
- [ ] SP-09~SP-14 실행 전 계약/리스크 사전 정렬

---

# 23. 요약

현재 WorshipFlow는:
- SP-01~SP-06 핵심 구현/안정화가 완료된 상태이며,
- SP-07 Release Gate는 historical close 상태이고,
- SP-08 score resolution / LiveCue preview stabilization이 `main`에 반영된 상태다.

이 문서는 이후 SP-09~SP-14 확장과
SP-08 후속 유지보수를
동일 밀도의 Workstream/DoD/검증/리스크 체계로 이어가기 위한 상세 기준선이다.
