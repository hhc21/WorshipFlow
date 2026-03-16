# WorshipFlow Product Development Map

작성일: 2026-03-10 (KST)  
문서 역할: WorshipFlow 프로젝트의 전체 제품 개발 상태를 한 장으로 보여주는 상위 지도 문서

참조 문서:
- plan.md
- research.md
- product_roadmap.md
- system_architecture.md
- data_model.md
- firestore_rules.md
- livecue_protocol.md
- docs/release_runbook.md

---

# 1. 이 문서의 목적

이 문서는 WorshipFlow 프로젝트의 **전체 개발 상태를 한 눈에 이해하기 위한 제품 지도**다.

다음 질문에 답하기 위한 문서다.

- 지금 프로젝트는 어디까지 왔는가
- 무엇이 이미 완성되었는가
- 무엇이 남아 있는가
- 다음 단계는 무엇인가
- 배포 전에 무엇을 검증해야 하는가

이 문서는 plan.md를 대체하지 않는다.

- plan.md → 실행 기준선
- 이 문서 → 제품 개발 지도

---

# 2. 현재 제품 상태 한 줄 요약

WorshipFlow는 현재

**“SP-07 Release Gate는 저장소 기준으로 종료되었고  
SP-08 score resolution / LiveCue preview stabilization,  
SP-09 music metadata layer까지 main에 반영된 상태다.”**

---

# 3. 현재 개발 진행도
엔진 개발        ██████████ 100%
UX 안정화        ██████████ 100%
실기기 안정화    ██████████ 100%
운영 기능        ██████████ 100%
운영 안정화      ██████████ 100%
협업 기능        ░░░░░░░░░░ 0%
배포 준비        ██████████ 100%
현재 상태 요약

- 엔진 구조 개발 완료
- 운영 기능 개발 완료
- 운영 안정화 완료
- 실기 시나리오 PASS 문서화 완료 (`docs/ops/device_validation.md`)
- Release Gate historical close 반영
- SP-08 resolver / preview / latency stabilization 반영
- SP-09 typed metadata boundary / LiveCue read-only metadata rendering 반영
- 현재 `main`은 release-gate 직전 상태가 아니라 post-SP-09 mainline 상태

현재 위치

**Post-SP-09 Mainline / Pre-Deploy Baseline Refresh**

---

# 4. 개발 단계 지도

---

# 4.1 ENGINE FOUNDATION

진행도: 100%

포함 단계

- SP-01 App Foundation
- SP-01A Bridge Security Hardening
- SP-02 LiveCue Sync Core 신뢰화
- SP-03 LiveCue 책임 분리

핵심 결과

구조 분리 완료

- LiveCueSyncCoordinator
- RenderPresenter
- LiveCueStrokeEngine
- NotePersistenceAdapter

의미

동기화 / 렌더링 / 입력 / 저장 계층이 분리되어  
이후 기능 개발 시 엔진 구조를 깨지 않는다.

---

# 4.2 RUNTIME STABILITY

진행도: 100% (문서 기준)

포함 단계

SP-04 실기기 안정화

완료된 것

- pointer / stylus 입력 안정화
- orientation 대응
- preload 충돌 완화
- ImageCache 상한 관리
- preview cache 관리
- 정적 검증 통과

후속 메모

- SP-04 실기 시나리오 PASS는 유지된다.
- 추가 evidence 정밀도 보강은 운영 문서 품질 관리 범위로 다룬다.

의미

코드와 기기 시나리오 문서는 정렬되어 있고  
현재는 post-SP-09 기준에서 회귀 관측과 다음 단계 계획이 우선이다.

---

# 4.3 PRODUCT FEATURES

진행도: 100%

포함 단계

- SP-05-1 운영자 → 팀 진입
- SP-05-2 setlist CRUD
- SP-05-3 setlist reorder / cue 이동
- SP-05-4 운영자 UI 안정화

완료된 기능

- 운영자에서 팀 진입 가능
- setlist 생성 / 수정 / 삭제
- setlist reorder
- cue 이동
- 운영자 UI 동선 안정화
- blank / loading / error 상태 정리

의미

실제 운영자가 사용할 수 있는  
제품 기능은 완성되었다.

---

# 4.4 RUNTIME SAFETY

진행도: 100%

포함 단계

SP-06 런타임 가드

완료된 것

- runtime_guard
- ops_metrics
- router guard
- setlist integrity guard
- liveCue state validation
- host viewer init validation

대표 runtime metric

- runtime_guard_triggered
- livecue_state_invalid
- setlist_order_invalid
- router_invalid_id
- firestore_snapshot_error

의미

WorshipFlow는 이제

**운영 중 오류를 감지하고 방어할 수 있는 시스템**

이 되었다.

---

# 4.5 RELEASE GATE

진행도: 100%

포함 단계

SP-07 배포 게이트

완료된 것

- release gate 기준 문서화
- release_runbook 작성
- first-error 운영 루프 정의
- fallback 정책 정의
- 대형 파일 변경 가이드 정의
- 정적 게이트 3종 기준 정렬 및 최근 실행 통과
- 기기 검증 시나리오 PASS 문서 반영
- `wf-v1.0.0` 기준 historical release evidence 기록
- 이후 mainline은 SP-08 구현 단계로 진행

후속 메모

- post-deploy runtime 관측 기록은 release-gate open blocker가 아니라 후속 안정화 입력으로 관리

---

# 4.6 COLLABORATION LAYER

진행도: 0%

예정 단계

SP-11 이후

예정 기능

- shared layer
- shared cue
- multi user sync
- 협업 권한 모델
- 충돌 처리
- 협업 UI

의미

현재 제품은

**운영 기능 MVP**

이고 이후 확장은

**협업 기능**

이 된다.

---

# 5. 현재 아키텍처 상태

핵심 구조

- Sync Layer
- Render Layer
- Input Layer
- Persistence Layer

이 구조 덕분에

- 기능 추가
- 안정화
- runtime guard 추가

가 **엔진 구조를 깨지 않고 가능하다**

---

# 6. Canonical 데이터 구조

현재 canonical 경로

teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}

teams/{teamId}/projects/{projectId}/liveCue/state

teams/{teamId}/projects/{projectId}/sharedNotes/main

teams/{teamId}/userProjectNotes/{noteId}

---

# 7. 문서 구조

루트 canonical 문서

- plan.md
- research.md
- product_roadmap.md
- system_architecture.md
- data_model.md
- firestore_rules.md
- livecue_protocol.md

운영 문서

docs/

- release_runbook.md
- livecue_incident_runbook.md
- livecue_repro_matrix.md
- test_strategy.md
- security_key_rotation_runbook.md
- tech_debt_register.md
- delete_queue_poc.md
- web_cache_strategy.md
- feature_checklist.md

---

# 8. 지금 남은 핵심 과제

1️⃣ post-SP-09 runtime regression 관측

- LiveCue attach/re-entry timing 재발 여부 추적
- fullscreen first-visible latency 회귀 추적
- legacy setlist canonical hygiene 재관측

2️⃣ maintainability hotspot 관리

- large file watchlist 유지
- hotspot별 미니 패치 원칙 유지
- 변경 빈도/회귀 집중도 기반 분리 우선순위 관리

3️⃣ 다음 workstream 기준선 확정

- SP-10 setlist metadata display enhancements
- song subtitle / alias resolution direction
- SP-13 canonical score expansion

---

# 9. 다음 단계

post-SP-09 회귀 샘플 축적

다음 SP 우선순위 확정

대형 파일/운영 리스크 정렬

---

# 10. 이후 제품 확장

협업 기능

- multi user cue
- collaborative notes
- shared live control
- remote team sync
