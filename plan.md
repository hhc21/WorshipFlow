# WorshipFlow Implementation Plan (2026-03-10 Final)

작성일: 2026-03-10  
근거 문서:
- `research.md` (2026-03-10 Baseline)
- `product_roadmap.md` (2026-03-10 Baseline)
- `system_architecture.md` (2026-03-10)
- `data_model.md` (2026-03-10)
- `firestore_rules.md` (2026-03-10)
- `livecue_protocol.md` (2026-03-10)

이 문서는 WorshipFlow의 **구현 계획 / 실행 기준 문서**다.  
코드 분석은 `research.md`, 제품 전략은 `product_roadmap.md`, 시스템 구조는 `system_architecture.md`가 담당한다.

즉:
- `research.md` → 현재 코드 상태
- `product_roadmap.md` → 제품 방향 / 우선순위
- `system_architecture.md` → 현재 시스템 구조
- `plan.md` → 구현 순서 / 게이트 / 검증 기준

---

# 0. 절대 정책

## 0.1 운영 정책

- GitHub는 백업/복구 용도로만 사용한다.
- 본 문서는 구현 계획 문서이며, 구현은 별도 승인 후 진행한다.
- 문서, 코드, 검증 결과가 서로 충돌할 경우 **현재 코드 + 검증 결과**를 우선 기준으로 삼는다.

## 0.2 현재 개발 운영 모드

현재 사이클은 **웹 기준 개발**을 지속한다.

이 의미는 다음과 같다.

- 기능 개발 / 구조 개선 / 운영 기능 구현은 웹 기준으로 먼저 진행한다.
- 실기 시나리오 결과는 `docs/ops/device_validation.md`를 기준으로 관리한다.
- 현재 단계는 실기 재수행보다 Release Gate 증빙 패키지 정렬을 우선한다.
- 모바일 실기 검증은 배포 승인 이후 회귀 루프에서 재검증할 수 있다.

## 0.3 구현 안전 정책

### 작업 단위 제한

한 번의 작업 사이클에서 아래 5개 영역 중 **하나만 수정**할 수 있다.

- 동기화 로직
- 렌더링 로직
- 입력 처리 로직
- 브릿지 로직
- Firebase 데이터 접근 로직

위 5개 영역을 동시에 수정하는 작업은 금지한다.

### 대형 파일 수정 제한

다음 파일은 대형 파일로 간주한다.

- `live_cue_page.dart`
- `team_select_page.dart`
- `team_home_page.dart`
- `global_admin_page.dart`

적용 규칙:

1. 한 작업에서 최대 300줄 범위를 원칙으로 한다.
2. 함수 단위 / 책임 단위로 분리 작업 수행한다.
3. 기능 이동은 인터페이스와 역할 정의 이후 진행한다.
4. 대형 파일을 한 번에 전면 재작성하지 않는다.

### 리팩토링 금지 원칙

다음 작업은 승인 없이 수행하지 않는다.

- 상태관리 라이브러리 교체
- Flutter 아키텍처 패턴 전면 변경
- Next.js Viewer 구조 전면 재설계
- Firebase 데이터 모델 대규모 변경
- LiveCue 전체 파일 재작성

## 0.4 상태 소유권 정책

각 상태는 단일 소유자를 가진다.

- Sync state → `LiveCueSyncCoordinator`
- Render state → `RenderPresenter`
- Input state → `LiveCueStrokeEngine`
- Persistence state → `LiveCueNotePersistenceAdapter`

원칙:

- UI는 상태를 직접 계산/복구/정합화하지 않는다.
- UI는 이벤트를 전달하고 결과를 소비한다.
- 동일 상태를 여러 계층이 동시에 수정하는 구조는 금지한다.

## 0.5 Async Safety 정책

원칙:

- `build()` 내부에서 async 작업을 직접 시작하지 않는다.
- Future / Stream ordering은 lifecycle과 분리해서 안전하게 관리한다.
- dispose 이후 도착 가능한 async 결과를 항상 고려한다.
- state update 전 lifecycle / mounted 상태를 확인한다.
- Stream listener 중복 생성 / 중복 attach는 금지한다.
- preload / render fallback / input state가 서로 입력을 끊지 않도록 분리한다.

## 0.6 Observability 정책

LiveCue 및 핵심 동기화 구조는 runtime trace가 가능해야 한다.

관찰 대상:

- render pipeline state
- sync revision 변화
- input state transition
- render fallback trigger
- stream emission ordering
- preload suppression 여부
- cache pressure / eviction

원칙:

- critical state transition은 로그를 남긴다.
- race condition 의심 구간은 debug instrumentation 대상으로 기록한다.
- 임시 로그와 상시 로그를 구분한다.

---

# 1. 현재 기준선 요약

## 1.1 현재 완료 / 부분완료 상태

### 완료

- WP-08 보안 게이트(키 노출 점검 자동화, 키 정책 문서화)
- WP-03 데이터 표준
  - 상대 좌표 `0.0 ~ 1.0`
  - fixed-8
  - `relative-v1`
- SP-01 App Foundation 복구
- SP-01A Bridge Security Hardening
- SP-02 LiveCue Sync Core 신뢰화
- SP-03 구조 분리
  - SyncCoordinator
  - RenderPresenter
  - StrokeEngine
  - NotePersistenceAdapter
- SP-05-1 운영자 → 팀 진입

### 부분완료

- SP-07 Release Gate 실행 증빙
  - 정적 게이트(`analyze`/`test`/`rules`) 통과 상태 확인 완료
  - `docs/ops/device_validation.md` 기준 실기 시나리오 PASS 문서화 완료
  - Release Gate 최종 승인용 증빙 패키지(타임스탬프/빌드 버전/로그 참조/미디어 링크) 정리 대기

### 보류

- 없음 (핵심 실기 시나리오는 문서상 PASS 상태로 반영됨)

## 1.2 현재 개발 방향

현재 개발 순서는 다음과 같다.

1. SP-07 증빙 패키지 정리
   - release checklist 항목별 실행 시각(KST)
   - build/release version
   - 로그 참조 경로
   - 스크린샷/영상 링크
2. SP-07 최종 PASS/FAIL 판정
3. 배포 승인(또는 FAIL 항목 보완 후 재판정)
4. 배포 후 first-error / regression 운영 루프
5. SP-08+ 협업 기능 백로그 착수

---

# 2. 현재 구조 기준 구현 상태

## 2.1 Canonical 데이터 축

현재 canonical 데이터 구조는 `teams/{teamId}` 중심이다.

핵심 경로:

- `users/{uid}`
- `users/{uid}/ClientProbe/mobile`
- `users/{uid}/teamMemberships/{teamId}` (미러/보조)
- `teams/{teamId}`
- `teams/{teamId}/members/{memberId}`
- `teams/{teamId}/projects/{projectId}`
- `teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}`
- `teams/{teamId}/projects/{projectId}/segmentB_application/{itemId}`
- `teams/{teamId}/projects/{projectId}/liveCue/state`
- `teams/{teamId}/projects/{projectId}/sharedNotes/main`
- `teams/{teamId}/userProjectNotes/{noteId}`
- `songs/{songId}`
- `globalAdmins/{uid}`

장기 확장용 구조인 `churches/{churchId}`는 현재 canonical이 아니다.

## 2.2 현재 라우팅 기준선

주요 경로:

- `/sign-in`
- `/teams`
- `/teams/:teamId`
- `/teams/:teamId/projects/:projectId`
- `/teams/:teamId/projects/:projectId/live`
- `/teams/:teamId/songs/:songId`
- `/admin`

운영자 경로:

- `/admin`
- 팀 목록
- `/teams/{teamId}` 진입 가능

## 2.3 현재 LiveCue 구조

### Sync Layer

- `LiveCueSyncCoordinator`
- `LiveCueResolvedState`

책임:
- cue/setlist attach/detach
- 웹 polling 전환 순차 보장
- native snapshot stream
- generation / sequence trace
- `currentCueLabel -> songId -> title+key` fallback

### Render Layer

- `_LiveCueRenderPresenter`

책임:
- preview cache / warm preview
- preload / prefetch
- renderer fallback
- overlay visibility
- viewport / transform 제어

### Input Layer

- `LiveCueStrokeEngine`

책임:
- beginStroke / appendStroke / endStroke
- erase / undo / clear
- brush/tool state
- layer visibility
- drawing mode state

### Persistence Layer

- `LiveCueNotePersistenceAdapter`

책임:
- private/shared note load/save
- legacy fallback
- migration write-back
- layer persistence 분기

---

# 3. Roadmap (완료 / 진행 / 예정)

## 3.1 SP-01 App Foundation

상태: 완료

목표:
- iOS/Android 실행 가능 상태 확보
- Firebase 연결
- 모바일 로그인 probe 기준선 확보

완료 항목:

- iOS 플랫폼 생성 확인
- Android 플랫폼 생성 확인
- Firebase 모바일 설정 연결 확인
- 최소 1회 Flutter 앱 빌드 성공
- 최소 1회 iOS Simulator 실행 성공
- 최소 1회 Android Emulator 실행 성공
- 모바일 환경 로그인 흐름 확인
- 앱 내 Firebase probe write/read 성공

메모:
- SP-01 기준선 자체는 당시 모바일 probe 성공으로 충족되었다.
- iOS 로그인 시나리오는 `docs/ops/device_validation.md`에 PASS로 기록되어 있다.

## 3.2 SP-01A Bridge Security Hardening

상태: 완료

완료 항목:

- `targetOrigin='*'` 제거
- origin whitelist 정책 적용
- Host → Viewer 토큰 전달 경계 재검증

## 3.3 SP-02 LiveCue Sync Core 신뢰화

상태: 완료

완료 기준:

- 운영자 탭에서 선택한 악보가 LiveCue에서 동일하게 로드됨
- stream ordering 로그에 역전/충돌 없음
- score load failure 재현 제거

반영 항목:

- cueLabel 우선순위 해석 강화
- `songId -> title+key` fallback 보강
- 운영화면 / fullscreen 공통 해석 정리
- native stream 단일화
- 웹 polling 전환 순차 보장
- stale/missing songId 회귀 테스트 추가

남은 항목:

- SP-02 자체 미완 항목은 없다.
- 실기 회귀 재측정은 SP-07 승인 후 운영 루프에서 수행한다.

## 3.4 SP-03 LiveCue 책임 충돌 해소

상태: 구현 완료

완료 항목:

### 1단계
- 책임 경계 정의
- 인터페이스 설계

### 2단계
- SyncCoordinator 분리

### 3단계
- RenderPresenter 분리

### 4단계
- StrokeEngine 분리

### 5단계
- NotePersistenceAdapter 분리

보강 결과:

- Sync / Render / Input / Persistence 경계 분리
- UI 직접 계산/저장 책임 축소
- adapter / engine / coordinator 중심 구조로 정렬
- 전용 테스트 추가
  - stroke engine test
  - note persistence adapter test

남은 리스크:

- 대형 파일 유지보수 비용
- 일부 관찰 로그(`RenderBox was not laid out`, `AppCheckProvider not installed`) 영향도 추적 필요

---

# 4. SP-04 실기기 안정화

상태: **구현 완료 / 실기 시나리오 문서 PASS / 릴리스 승인 증빙 패키지 보강 대기**

목표:
- 실제 기기 환경에서 LiveCue가 안정적으로 동작하도록 정리

## 4.1 완료된 코드 하드닝

반영 범위:

- pointer device 안정화
- orientation 변경 대응
- preload 충돌 방지
- ImageCache 메모리 제한
- preview cache eviction
- 긴 세션 메모리 안정화 장치
- 드로잉 중 rebuild 감소
- 필기 입력 안정성 보강

세부 반영:

- 지원 입력 종류 필터링
- active pointer 추적
- `WidgetsBindingObserver` 기반 metrics 변화 처리
- rotation / resize 시 active pointer 정리
- viewer transform reset
- drawing 중 warm prefetch 억제
- ImageCache 상한 적용 / 복원
- preview cache LRU eviction
- song key future cache 상한
- 입력 / preload / render 경쟁 최소화

## 4.2 검증 상태

통과:

- `flutter analyze`
- `flutter test --reporter=compact`
- `bash scripts/ci/test_rules.sh`

## 4.3 완료 조건

구현 기준:
- [x] 필기 끊김 방지 코드 반영
- [x] 회전 대응 코드 반영
- [x] 메모리 안정화 코드 반영
- [x] 정적 검증 통과

실기기 기준:
- [x] Apple Pencil 장시간 필기 안정성 (문서 PASS)
- [x] iPhone 회전 안정성 (문서 PASS)
- [x] 공유 노트 저장-재진입 지속성 (문서 PASS)
- [x] Viewer host payload 검증 시나리오 (문서 PASS)
- [x] iOS Google 로그인 시나리오 (문서 PASS)

근거 문서:
- `docs/ops/device_validation.md`

## 4.4 남은 증빙 패키징 체크 (SP-07 실행)

- [ ] 각 시나리오별 실행 시각(KST) 링크를 release checklist에 반영
- [ ] build version / release version을 시나리오별로 기재
- [ ] 로그 참조 위치(파일/콘솔 캡처)를 checklist/runbook에 교차 연결
- [ ] 스크린샷/영상 링크를 runbook evidence 섹션에 정리

## 4.5 보류 메모

현재 기준 보류 항목은 없다.

주의:
- 본 상태는 `docs/ops/device_validation.md`에 기록된 PASS 문서 기준이다.
- 배포 승인 전에는 SP-07 증빙 패키지(타임스탬프/빌드/로그/미디어 링크) 정리가 필요하다.

---

# 5. SP-05 운영 기능

목표:
- 실제 예배 운영에서 사용할 기능 구현

주의:
- SP-05의 공식 완료 판정은 `SP-05-1 ~ SP-05-4` 기준으로 이미 충족되었다.
- 아래 5.2~5.7 세부 분해안은 초기 백로그 초안이며, 현재 Release Gate 판정의 기준 체크리스트는 아니다.

## 5.1 SP-05-1 운영자 → 팀 진입

상태: 완료

완료 내용:

- 운영자 팀 목록에서 팀 홈 진입 가능
- 팀 리스트 항목 onTap 경로 추가
- 명시적 버튼으로 팀 홈 열기 추가
- global admin 기반 접근 허용
- teamId trim / validation / encode 반영
- 회귀 테스트 추가

검증:
- `flutter analyze` 통과
- `flutter test --reporter=compact` 통과
- `bash scripts/ci/test_rules.sh` 통과

남은 리스크:
- global admin이 팀 멤버가 아닐 경우,
  일부 팀 프로젝트 데이터 read는 rules 상 제한될 수 있음
- 운영자 계정의 팀 내 쓰기 액션은 아직 별도 검증 필요

## 5.2 SP-05-2 setlist 관리

상태: 예정

할 일:

- [ ] setlist 목록 조회 안정화
- [ ] setlist 생성
- [ ] setlist 수정
- [ ] setlist 저장
- [ ] setlist 항목 삭제/복구 정책 정리

완료 조건:

- 운영자가 프로젝트 내 setlist를 생성/수정/저장할 수 있음
- setlist 데이터가 canonical 경로에 저장됨
- 실시간 반영과 저장 상태가 UI에 명확히 표현됨

## 5.3 SP-05-3 곡 순서 변경

상태: 예정

할 일:

- [ ] drag reorder
- [ ] 순서 변경 persistence
- [ ] reorder 이후 LiveCue ordering 정합성 유지
- [ ] 충돌 시 fallback 규칙 명확화

완료 조건:

- 곡 순서 변경 후 setlist order가 저장됨
- 재접속 후 동일 순서 복원
- LiveCue 현재/다음 곡 계산이 reorder 후에도 정확함

## 5.4 SP-05-4 곡 빠른 이동

상태: 예정

할 일:

- [ ] 특정 곡 즉시 이동
- [ ] setlist index jump
- [ ] 현재 곡 표시/UI 동기화

완료 조건:

- 운영자가 특정 곡으로 즉시 이동 가능
- 운영/전체화면/구독 클라이언트에 동일 반영

## 5.5 SP-05-5 다음곡 / 이전곡

상태: 예정

할 일:

- [ ] next song
- [ ] previous song
- [ ] 현재 / 다음 곡 상태 동기화

완료 조건:

- next / previous 제어가 setlist ordering과 일치
- 잘못된 곡 참조 / fallback mismatch 없음

## 5.6 SP-05-6 cue 이동

상태: 예정

할 일:

- [ ] cue index 이동
- [ ] current cue broadcast
- [ ] currentCueLabel / songId / title+key fallback 정합성 유지

완료 조건:

- cue 이동이 LiveCueResolvedState 규칙과 충돌하지 않음
- 운영/전체화면 동기화 유지

## 5.7 SP-05-7 운영자 UI 기본 기능

상태: 예정

할 일:

- [ ] 운영자 컨트롤 패널
- [ ] 현재 곡 상태 표시
- [ ] next 곡 상태 표시
- [ ] cue 상태 표시
- [ ] 운영자 동선 최소화
- [ ] 오류/로딩/저장 상태 표현 개선

완료 조건:

- 실제 예배 운영에서 핵심 제어를 1~2단계 안에 수행 가능
- 운영자 화면이 읽기/제어 관점에서 일관됨

## 5.8 SP-05 전체 완료 기준

- [x] 운영자 → 팀 진입
- [ ] setlist 관리
- [ ] 곡 순서 변경
- [ ] 곡 빠른 이동
- [ ] 다음곡 / 이전곡
- [ ] cue 이동
- [ ] 운영자 UI 기본 기능

---

# 6. SP-06 협업 기능

목표:
- 팀 단위 협업을 위한 shared layer / shared cue / multi-user sync 안정화

주의:
- 이 섹션은 협업 기능 백로그 초안이다.
- 현재 공식 SP-06 완료 상태(웹 런타임 운영 가드 강화)와는 별개로 관리한다.

## 6.1 shared layer 안정화

할 일:

- [ ] shared layer 로드 정합성
- [ ] shared layer 저장 정합성
- [ ] 재접속 복원 검증
- [ ] private/shared 혼합 편집 안전성 점검

완료 조건:

- 사용자 A 필기가 사용자 B에 안정적으로 반영됨
- shared layer 저장/복원이 재접속 후 유지됨

## 6.2 shared cue

할 일:

- [ ] shared cue 상태 모델 정의
- [ ] cue broadcast 범위 정리
- [ ] 운영자/인도자/뷰어 반영 정책 정리

완료 조건:

- 팀 단위 cue 공유가 LiveCue 프로토콜과 충돌하지 않음

## 6.3 multi-user sync 안정성

할 일:

- [ ] 동시 진입 안정성
- [ ] generation/sequence 관찰 강화
- [ ] listener 중복/경쟁 조건 재검증
- [ ] reconnect 후 ordering 안정성 검증

완료 조건:

- 다중 사용자 환경에서 sync ordering 충돌이 재현되지 않음

## 6.4 필기 충돌 처리

할 일:

- [ ] 동시 편집 충돌 정책 정의
- [ ] layer 충돌 시 우선순위 정리
- [ ] 충돌 회복 UX 정의
- [ ] partial save / stale overwrite 방지

완료 조건:

- 동시 필기 시 데이터 손실/겹침 규칙이 명확하고 재현 가능함

## 6.5 사용자 권한

권한 축:

- viewer
- editor
- leader
- team admin
- global admin

할 일:

- [ ] viewer / editor 권한 구분
- [ ] shared/private 편집 범위 구분
- [ ] 운영자 경로와 팀 경로 권한 정책 정리
- [ ] Firestore rules / UI 동작 정합성 검증

완료 조건:

- 역할별 읽기/쓰기 범위가 문서/규칙/코드에서 일치함

## 6.6 SP-06 전체 완료 기준

- [ ] shared layer 안정화
- [ ] shared cue 정의
- [ ] multi-user sync 안정성 확보
- [ ] 필기 충돌 처리 정책 정리
- [ ] viewer/editor/leader 권한 정합성 확보

---

# 7. SP-07 배포 게이트 실행 상태

목표:
- 배포 가능 여부를 문서/검증 근거로 최종 판정
- 배포 자체(실행)와 배포 승인(판정)을 구분하여 관리

## 7.1 정적 게이트

- [x] `flutter analyze` PASS
- [x] `flutter test --reporter=compact` PASS
- [x] `bash scripts/ci/test_rules.sh` PASS

## 7.2 실기 시나리오 문서 상태

- [x] `docs/ops/device_validation.md` 기준 5개 시나리오 PASS 기록 확인
- [x] shared notes 항목 문구를 구현 모델(save-trigger persistence)과 정렬

## 7.3 Release 실행 증빙 패키지 (남은 작업)

- [ ] checklist/runbook에 시나리오별 실행 timestamp(KST) 연결
- [ ] build version / release version 기입
- [ ] 로그 참조 위치(파일/콘솔 캡처) 연결
- [ ] 스크린샷/영상 링크를 시나리오별로 연결

## 7.4 SP-07 표현 원칙

- Release Gate 정적 검증 PASS와 기기 검증 문서 PASS는 사실로 기록한다.
- 최종 승인 전까지는 `APPROVED/배포완료`를 선언하지 않는다.
- Release Gate 최종 상태는 증빙 패키지 검토 후 `PASS/FAIL`로 확정한다.

## 7.5 현재 판정

- 상태: **Release Candidate / 승인 대기**
- 의미:
  - static gate: PASS
  - device validation: 문서 PASS
  - release execution evidence: 정리/서명 대기

## 7.6 SP-07 전체 완료 기준

- [x] static gate PASS
- [x] device validation 문서 PASS 반영
- [x] release checklist 기준 항목 정의 완료
- [ ] 증빙 패키지(시각/빌드/로그/미디어 링크) 완결
- [ ] 최종 `APPROVED` 또는 `BLOCKED` 판정 기록

---

# 8. SP-07 이후 개발

## 8.1 운영자 모드 확장

주의:
- SP-05-1 운영자 → 팀 진입은 이미 완료됨
- 여기서는 그 이후 확장 범위를 다룬다

할 일:

- [ ] 운영자 팀 목록 조회 UX 고도화
- [ ] 운영자 → 프로젝트 진입 확장
- [ ] 운영자 → LiveCue 직접 진입 확장
- [ ] 팀 LiveCue 상태 조회
- [ ] 팀 LiveCue 제어
- [ ] 팀 컨텍스트 routing 확장
- [ ] global admin 프로젝트 읽기 범위 정책 정리

## 8.2 이후 단계(선택)

필요 시:

- [ ] offline 모드
- [ ] PWA 지원
- [ ] iPad 앱 패키징
- [ ] Android 태블릿 지원

---

# 9. Web Fallback / Next Viewer 계획

## 9.1 현재 위치

Next.js Viewer는 핵심 엔진이 아니라 **web fallback / 보조 경로**다.

현재 역할:

- 긴급 조회 경로
- 웹 운영 보조 경로
- 브라우저 특수 이슈 우회 경로

## 9.2 하지 않는 역할

웹 fallback은 다음 책임을 장기 핵심 책임으로 갖지 않는다.

- 주 편집 엔진
- 모바일 UX 기준 플랫폼
- 앱보다 우선하는 릴리즈 기준 플랫폼
- LiveCue 핵심 책임의 영구 소유자

## 9.3 유지/축소 판단 기준

다음 기준으로 판단한다.

1. Flutter 단일 경로에서 동일 버그 재현 여부
2. Viewer 경로에서 완화 효과 존재 여부
3. 이중 유지 비용 대비 안정성 이득

원칙:
- 데이터 기준으로 유지/축소를 판단한다.
- 신념 기반으로 강제 제거하지 않는다.

---

# 10. Contract / Sync Plan

## 10.1 데이터 스키마

고정 규약:

- 좌표: 상대 좌표 `0.0 ~ 1.0`
- 정밀도: fixed-8
- 스키마 버전: `relative-v1`

해야 할 일:

- [ ] NaN / Infinity / 범위 초과 값 폐기 규칙 문서화
- [ ] layer payload validation 기준 보강

## 10.2 메시지 프로토콜

현재 기준:

- `viewer-ready`
- `host-init`
- `init-applied`
- `ink-dirty`
- `ink-commit`
- `ink-synced`
- `asset-cors-failed`

해야 할 일:

- [ ] idempotency key 정책 정리
- [ ] 재전송 규칙 정리
- [ ] protocol version mismatch 처리 정책 정리

## 10.3 sync revision / ordering

해야 할 일:

- [ ] `syncRevision` 단조 증가 규칙 명시
- [ ] generation token 규칙 문서화
- [ ] stale emission drop 기준 문서화
- [ ] dirty / synced 전이 규칙 정리

## 10.4 Firebase 저장/권한 규칙

해야 할 일:

- [ ] membership source 단일화 로드맵
- [ ] deleteQueue / opsMetrics 운영 의미 문서화
- [ ] shared/private note persistence 권한 범위 재검토

---

# 11. Verification / Research Refresh Loop

리서치와 논리 검증은 1회성 작업이 아니라 단계별 반복 루프로 수행한다.

## 11.1 루프 기준

- [ ] SP-05 이후 research refresh
- [ ] SP-06 이후 sync / collaboration verification
- [ ] SP-07 이후 release readiness verification
- [ ] 배포 후 platform-specific regression verification

## 11.2 공통 검증 항목

- [ ] 데이터 흐름 꼬임 여부
- [ ] Future / Stream ordering 보장 여부
- [ ] 상태 전이 충돌 여부
- [ ] side-effect 위치 적절성
- [ ] 실기기 회귀 여부
- [ ] rules / runtime 정합성
- [ ] 역할/권한 UX 충돌 여부

---

# 12. 배포 후 테스트 계획

## 12.1 Apple Pencil 테스트

- [ ] latency 확인
- [ ] stroke smoothing
- [ ] palm rejection
- [ ] 빠른 필기 테스트

## 12.2 공유 필기 테스트

- [ ] 사용자 A 필기
- [ ] 사용자 B 실시간 반영
- [ ] shared layer 저장
- [ ] 재접속 후 복원

## 12.3 장시간 테스트

- [ ] 30~60분 사용
- [ ] 곡 이동 반복
- [ ] 필기 + 저장 반복
- [ ] 메모리 안정성 확인

---

# 13. Release Readiness / Deployment Gate

배포는 구현 완료만으로 허용되지 않는다.

## 13.1 사전 배포 게이트

- [ ] SP-04 ~ SP-07 핵심 게이트 충족
- [ ] `flutter analyze` 통과
- [ ] `flutter test` 통과
- [ ] rules test 통과
- [ ] web fallback 최소 시나리오 정상
- [ ] 치명 보안 이슈 미해결 상태 없음
- [ ] 모바일 실기 검증 재개 및 최소 증빙 확보

## 13.2 배포 후 확인 항목

- [ ] first-error 기록
- [ ] 회귀 여부 확인
- [ ] fallback 경로 정상 여부 확인
- [ ] 실사용 피드백 수집

---

# 14. 현재 보류 항목

현재 기준 핵심 보류 항목은 없다.

남은 블로커(승인 전 정리 필요):

- Release checklist 최종 체크/서명
- runbook evidence 패키지(시각/빌드/로그/미디어 링크) 완결
- 최종 `APPROVED` 또는 `BLOCKED` 판정 기록

원칙:

- `device_validation.md`에 기록된 PASS는 인정한다.
- 단, 배포 승인 문서가 완결되기 전에는 release approved를 선언하지 않는다.

---

# 15. Final Success Criteria

다음 조건을 모두 만족하면 현재 계획은 성공으로 판정한다.

## 구조 / 품질

- [ ] LiveCue 핵심 책임 경계가 유지된다
- [ ] UI 레이어가 상태 소유권을 침범하지 않는다
- [ ] 동일 버그 재발 가능성이 구조적으로 낮아진다
- [ ] `flutter analyze` / `flutter test` / rules test 기준이 유지된다

## 운영 기능

- [ ] 운영자가 실제 예배 운영 기능을 사용할 수 있다
- [ ] 팀 / 프로젝트 / LiveCue 운영 동선이 일관된다
- [ ] setlist / cue / 곡 이동 기능이 안정적으로 동작한다

## 협업 기능

- [ ] shared layer / shared cue가 팀 단위로 안정적으로 동작한다
- [ ] multi-user sync 충돌이 재현되지 않는다
- [ ] 역할별 권한 정책이 코드/규칙/UI에서 일치한다

## 배포 준비

- [ ] production build / deploy / env / rules 기준이 정리된다
- [ ] 배포 게이트를 통과할 수 있는 검증 근거가 확보된다

## 실기 검증

- [ ] iPad / iPhone / 필요 시 Android 태블릿 테스트를 완료한다
- [ ] Apple Pencil / 공유 필기 / 장시간 테스트 기준을 충족한다

---

# 16. 요약

현재 기준 요약:

- SP-01 완료
- SP-01A 완료
- SP-02 완료
- SP-03 완료
- SP-04 구현 완료 / `device_validation.md` 기준 시나리오 PASS 문서 반영
- SP-05-1 ~ SP-05-4 완료
- SP-06 런타임 가드 강화 완료
- SP-07 static gate PASS + device validation 문서 PASS
- 최종 release 승인 판정은 증빙 패키지 정리 후 대기

즉, 현재 상태는 다음으로 정리된다.

**기능/안정화 구현은 완료되었고,  
현재는 SP-07 릴리스 게이트 최종 승인 문서를 마감하는 단계다.**




## 14. SP-08 Operations & Observability

Goal:
Enable stable real-world operation by introducing operational monitoring and observability.

Scope:
- Admin monitoring panel
- LiveCue session monitoring
- Runtime guard metrics dashboard
- Incident logging

Implementation:
- ops_metrics collection
- runtime_guard_triggered metrics
- session state viewer

Definition of Done:
- Admin can inspect active sessions
- Runtime guard events are logged
- Incident logs available for debugging


## 15. SP-09 Music Metadata

Goal:
Support structured music metadata for each setlist item.

Scope:
- BPM (tempo)
- Key
- Time signature
- Section markers

Firestore Model:

segmentA_setlist/{itemId}

{
  title
  key
  tempo
  timeSignature
  sectionMarkers
}

Definition of Done:
- Metadata stored per setlist item
- LiveCue renderer can read metadata
- UI editor supports metadata input


## 16. SP-10 Performance Assistance

Goal:
Provide live performance assistance features for musicians.

Scope:
- Tempo tap
- Count-in
- Cue timer
- Auto scroll

Implementation:
- LiveCue renderer integrates tempo metadata
- BPM-based cue timing
- Count-in visual indicator

Definition of Done:
- Tempo tap calculates BPM
- Count-in works
- Cue timing visible in LiveCue


## 17. SP-11 Collaboration Layer

Goal:
Enable multi-user collaboration within a project.

Scope:
- Shared notes editor
- Presence indicator
- Cue sync between devices
- Comment system

Implementation:
- sharedNotes/main document
- Presence tracking
- Realtime collaboration UI

Definition of Done:
- Multiple users can edit notes
- Changes sync across devices
- Presence state visible


## 18. SP-12 Production Deployment

Goal:
Prepare WorshipFlow for production deployment.

Scope:
- Firebase Hosting deployment
- Production Firestore rules
- CI/CD pipeline
- Version tagging

Implementation:
- GitHub CI pipeline
- release tagging
- production environment setup

Definition of Done:
- Production deploy successful
- Release version tagged
- Production monitoring enabled

# 19. Architecture Risk Register

This section tracks architectural risks for WorshipFlow.

These are not release blockers but must be monitored.

---

## Large UI Integration Files

High risk files

- live_cue_page.dart
- team_home_page.dart
- global_admin_page.dart

Risk

UI integration layers may accumulate business logic over time.

Examples

- cue state interpretation
- navigation state
- runtime guards
- collaboration UI

Impact

- regression risk
- difficult debugging
- unsafe automated edits

Mitigation

SP-08 ~ SP-10 동안 기능 단위 모듈 분리 진행

Rules

- never rewrite entire large files
- extract feature modules
- maintain engine ownership boundaries

---

## Firestore Path Coupling

Risk

Client logic tightly coupled to Firestore path structure.

Impact

Future schema changes may break multiple features.

Mitigation

Introduce centralized path helpers.

---

## Sync Ordering Drift

Risk

Future collaboration features may introduce ordering race conditions.

Mitigation

Maintain

- generation tokens
- syncRevision guards
- stale event filtering

---

# End of Plan
