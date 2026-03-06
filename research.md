# WorshipFlow 리서치 보고서 (Hard Refresh)

작성일: 2026-03-07  
최종 업데이트: 2026-03-07  
분석 경로: `/Users/hwanghuichan/Downloads/개발/WorshipFlow`

---

## 0) 이번 리서치 목표

이번 리서치는 단순 구조 요약이 아니라, 현재 실제 장애(악보 로딩 실패/깜빡임/아이패드 필기 불가)를 기준으로
`코드 + 설정 + CI + 문서`를 동시에 검증해 **원인 후보/우선순위/실행 백로그**를 재정의하는 데 목적이 있다.

요청 조건:
- 코드 수정 없음
- `research.md`와 이후 `plan.md`만 업데이트
- 디버깅 + 최적화 관점 포함

---

## 1) 조사 방법 및 범위

### 1.1 파일 전수 스캔 범위
- 앱 코드: `lib/**`
- 테스트: `test/**`
- 워크플로우: `.github/workflows/**`
- 운영 스크립트: `scripts/**`, `functions-poc/**`
- 운영 문서: `docs/**`
- 규칙/배포: `firestore.rules`, `storage.rules`, `firebase.json`, `web/index.html`

### 1.2 코드베이스 규모 스냅샷
- Dart 파일: `54`
- Markdown 문서: `13`
- 워크플로우 파일: `4`
- 핵심 대형 파일(라인 수):
  - `lib/features/projects/live_cue_page.dart`: `3289`
  - `lib/features/teams/team_home_page.dart`: `2181`
  - `lib/features/teams/team_select_page.dart`: `2064`
  - `lib/features/admin/global_admin_page.dart`: `1235`
  - `lib/features/projects/segment_a_page.dart`: `1060`

의미:
- LiveCue/Team 영역이 단일 파일에 집중되어 있어, 장애 원인 추적과 회귀 테스트 비용이 크다.

---

## 2) 현재 상태 검증 (실행 근거)

### 2.1 정적/테스트/빌드
- `flutter analyze`: 통과 (`No issues found`)
- `flutter test`: 통과 (`All tests passed`, 60개 시나리오)
- `flutter test --coverage`: 통과
- `scripts/ci/check_coverage.sh`: 통과
  - 제외 적용 커버리지: `43.69%` (기준 35%)
  - 전체 실제 커버리지: `28.45%` (제외 없이 계산, 기준 26% 통과)
- `flutter build web --release`: 통과

### 2.2 로컬 규칙 테스트
- `scripts/ci/test_rules.sh`: **로컬 실패 (Java 런타임 없음)**
  - CI에서는 Java 설치 스텝이 있으므로 통과 가능하지만,
  - 로컬에서는 동일 검증이 즉시 불가한 상태.

의미:
- 파이프라인은 "형식상 green"이지만,
- 실제 장애가 발생한 LiveCue 경로 대부분이 커버리지 제외 대상이라 품질 신뢰도가 제한적이다.

---

## 3) 아키텍처 현황 (핵심만)

### 3.1 앱 초기화/라우팅
- `main.dart`
  - Firestore 설정에서 `WF_FIRESTORE_TRANSPORT` 환경값 지원
  - 기본값은 `auto`
- `router.dart`
  - 인증 게이트 + 안전한 redirect path 검증

### 3.2 데이터/권한
- Firestore:
  - `teams`, `projects`, `liveCue`, `members`, `invites`, `joinRequests`, `teamNameIndex`, `users/{uid}/teamMemberships`
- Rules:
  - 팀 멤버십 3축 허용(`memberUids`, `members`, `teamMemberships`)로 self-healing 친화
  - `joinRequests` 허용 규칙 존재
- Storage:
  - `songs/**` 읽기 로그인 사용자, 쓰기 global admin
  - `teams/{teamId}/**`는 team admin/global admin 중심

### 3.3 팀 정책 구현 상태
사용자 요청했던 정책들은 현재 코드상 반영되어 있다.
- 동일 팀명 생성 시: 새 팀 생성 대신 `joinRequests` 생성 경로 있음
- 팀 합류: 팀장 초대 기반 흐름 유지
- 일반 팀 목록 UI에서 팀 ID 비노출
- 유령 팀 정리는 사용자 액션이 아닌 내부 정리 로직으로 처리

---

## 4) LiveCue 장애 디버깅 분석 (핵심)

사용자 보고 증상:
1. 악보 진입 전 로딩/깜빡임
2. 검은/회색 화면 또는 로딩 실패
3. iPad + Apple Pencil 필기 불가/불안정
4. 콘솔에 Firestore Listen CORS류 메시지, `Stream has already been listened to`, `Cannot add to a constant list` 류 오류

### 4.1 코드 레벨 관찰

#### A) 웹 전용 폴링 스트림 사용
- `live_cue_page.dart`에서 Web일 때 `snapshots()` 대신 주기형 `get()` 폴링 스트림 사용
- `_setlistPollingStream`, `_liveCuePollingStream`
- 현재 폴링 주기:
  - setlist: 3.5초
  - liveCue state: 1.0초

영향:
- 상태가 바뀌지 않아도 주기성 네트워크 비용이 발생할 수 있고,
- setlist query는 문서 수가 많을수록 읽기 비용 급증

추정 읽기량(현재 주기 기준):
- 공식: `(60/setlist_interval)*(N+1) + (60/cue_interval)*1`
- N=20이면 분당 약 `420 reads/min`

#### B) 웹 이미지 렌더 fallback이 필기와 충돌 가능
- 이미지 로드 실패 시 `WebHtmlElementStrategy.prefer`로 전환
- 코드 안에 이미 경고 문구 존재: "호환 모드에서 필기 입력이 불안정할 수 있음"

해석:
- 현재 코드가 이미 문제를 인지하고 있으며,
- 이 fallback 모드가 iPad 필기 실패/깜빡임과 강하게 연결될 가능성이 높다.

#### C) `WF_FIRESTORE_TRANSPORT` 배포 주입 상태
- `ci/staging/prod` 워크플로우 모두 `WF_FIRESTORE_TRANSPORT=long-polling` 주입 확인
- 빌드 명령에 `--dart-define=WF_FIRESTORE_TRANSPORT=...` 명시 확인

해석:
- transport 주입 누락 문제는 해소되었고,
- 남은 리스크는 실기기 안정성 검증/운영 증거 축적이다.

#### D) Storage CORS는 문서/JSON만 있고 강제 검증이 없음
- `scripts/storage_cors.json`, `scripts/README_CORS.md`는 존재
- 하지만 CI에서 bucket CORS 적용 여부를 검증하지 않음

해석:
- 환경이 한 번 틀어지면 같은 코드라도 이미지 로드 실패/브라우저 CORS 실패가 재발할 수 있다.

#### E) 소스맵 404 노이즈
- `build/web/flutter.js`에 `//# sourceMappingURL=flutter.js.map`
- 릴리스 산출물에는 `flutter.js.map` 없음
- Hosting rewrite 때문에 DevTools에서 JSON parse 경고 발생 가능

해석:
- 직접 장애 원인은 아니지만 디버깅 노이즈를 크게 만든다.

#### F) 서비스워커 강제 해제 + 1회 reload 정책
- `web/index.html`에서 기존 서비스워커를 unregister 후 `wf_sw_cleared` 세션 플래그로 1회 reload 수행
- iPad Safari 환경(탭 재진입/세션 분리/프라이빗 모드)에서 초기 진입 체감 깜빡임을 키울 수 있음

해석:
- stale cache 방지에는 유효하지만, 라이브 환경에서는 \"초기 재로딩\" 자체가 UX 리스크가 될 수 있다.

### 4.2 원인 가설 (우선순위/신뢰도)

- H1 (높음): Storage/CORS/이미지 fetch 실패 -> html element fallback -> 필기 이벤트 충돌
- H2 (중간): Firestore transport 주입은 완료됐지만, 실기기에서 안정성 증거가 아직 부족
- H3 (중~높음): 주기형 폴링 구조 자체가 재빌드/깜빡임/읽기비용을 유발할 수 있음
- H4 (중간): 비결정적 런타임 오류(`Stream listened`, `const list`)는 LiveCue 복합 상태 전환에서 간헐 발생
- H5 (중간): 서비스워커 강제 해제 후 1회 reload 정책이 초기 진입 깜빡임/지연 체감을 증폭

---

## 5) 최적화 진단

### 5.1 구조 최적화 관점
- LiveCue 단일 파일 3k+ 라인: 렌더러, 입력, 권한, 데이터동기화가 한 파일에 결합
- TeamHome/TeamSelect도 2k 라인급으로 결합도 높음

영향:
- 장애 수정 시 사이드이펙트 위험 증가
- 테스트 타겟팅 난이도 상승

### 5.2 성능/비용 최적화 관점
- 폴링 주기형 Firestore 읽기 비용이 매우 큼
- setlist 전체를 매 주기 재조회하는 구조는 실시간성 대비 비용 효율이 낮음

### 5.3 테스트 최적화 관점
- 커버리지 게이트는 통과하지만,
- 핵심 고위험 파일이 기본 제외 regex에 다수 포함
- 실질 리스크가 큰 영역이 CI gate 밖에 남아 있음
- `test/integration/live_cue_web_e2e_test.dart`는 `FakeFirestore` + `MockStorage` 중심이라
  실제 브라우저 CORS/이미지 fetch/renderer fallback 경로를 직접 검증하지 못함

### 5.4 운영 최적화 관점
- LiveCue Safari smoke gate는 staging/prod 모두 `required`로 설정됨
- 남은 과제는 gate 증거(실기기 영상/로그 링크)를 릴리즈 승인 흐름에 누락 없이 축적하는 운영 절차다.

---

## 6) 문서-실상 모순 점검

### 6.1 `docs/feature_checklist.md`와의 모순
- 체크리스트 상 다수 항목이 `DONE`으로 보이지만,
- 실제 사용자 실기기 이슈(필기 불가/깜빡임/CORS류)가 존재

판정:
- LiveCue 관련 항목(F-307/F-308/F-403/S-003/S-006)은 `DONE`이 아니라
  최소 `PARTIAL` 또는 `IN-PROGRESS`로 엄격 관리하는 것이 타당

### 6.2 품질 게이트의 맹점
- 현재 gate는 "빌드/테스트 통과"를 보장하지만
- "실기기 Safari + Pencil 안정성"은 gate에 강제되지 않음

### 6.3 재현 매트릭스 완결성
- `docs/livecue_repro_matrix.md` 기준, LC-SAF-02/06은 아직 `TODO` 상태
- 즉, 핵심 장애는 재현됐지만 "전체 케이스 완결"은 미달

판정:
- Phase A는 부분 완료이며, 전 케이스 로그/영상 증거 확보 전까지 `BLOCKED` 유지가 타당

---

## 7) 업그레이드/최적화 백로그 (우선순위 + 난이도 + 예상효과)

| ID | 우선순위 | 항목 | 난이도 | 예상효과 |
|---|---|---|---|---|
| B-01 | P0 | LiveCue iPad 필기 실패 원인 분리(이미지 fallback 모드 vs 입력 레이어) | 중 | 핵심 사용성 복구, 실사용 전환 가능 |
| B-02 | P0 | Storage CORS 운영 상태 점검/재적용/검증 자동화 | 하~중 | 악보 로딩 실패 재발률 급감 |
| B-03 | P0 | 배포 빌드에 Firestore transport 전략 명시(`WF_FIRESTORE_TRANSPORT`) | 하 | Safari Listen 불안정 감소 |
| B-04 | P1 | LiveCue 웹 폴링 구조 비용/깜빡임 개선(주기/대상 최소화) | 중~상 | 읽기 비용/깜빡임 동시 개선 |
| B-05 | P0 | LiveCue 렌더러 전략 분리(필기 모드에서 pointer 안정 우선) | 중 | Pencil/터치 안정화 |
| B-06 | P1 | LiveCue 장애 재현 매트릭스 기반 자동/반자동 회귀 루틴 구축 | 중 | "정상처럼 보이지만 실제 실패" 방지 |
| B-07 | P1 | 커버리지 제외 축소(특히 LiveCue/TeamHome 일부) | 중 | CI 신뢰도 상승 |
| B-08 | P2 | flutter.js.map 노이즈 정리(디버깅 신호 품질 개선) | 하 | 운영 디버깅 속도 개선 |
| B-09 | P2 | 대형 파일 모듈 분해(LiveCue/TeamHome 우선) | 상 | 유지보수성/테스트성 개선 |
| B-10 | P1 | staging Safari smoke required gate 운영 모니터링 | 하 | gate 누락/우회 재발 방지 |
| B-11 | P0 | 서비스워커 정책(로컬/override 한정 해제) 운영 모니터링 | 하 | 초기 진입 UX 회귀 방지 |
| B-12 | P1 | LiveCue Next.js/Vercel PoC(한정 범위) | 중 | 전면 전환 전 실측 기반 판단 가능 |
| B-13 | P1 | Flutter vs Next.js Go/No-Go 의사결정 문서화 | 하~중 | 전환 의사결정 혼선 방지 |

---

## 8) 즉시 실행 권장 순서

1. B-02 (CORS 운영 검증 자동화)
2. B-01/B-05 (필기 불가 핵심 경로 안정화)
3. B-04 (폴링 비용/깜빡임 개선)
4. B-06/B-08/B-09 (회귀/디버깅/구조 개선)
5. B-10/B-11 (적용 완료 항목 운영 모니터링)
6. B-12/B-13 (LiveCue 한정 PoC 후 전환 의사결정)

이 순서를 쓰는 이유:
- 1~3은 장애 체감을 직접 줄이는 P0,
- 4~5는 구조적 재발 방지 축.

### 8.1 Plan 정합을 위한 정량 기준(연동)
아래 기준은 `plan.md`의 완료 조건과 동일한 운영 목표로 고정한다.

- Firestore transport 운영안:
  - staging/prod 모두 `WF_FIRESTORE_TRANSPORT=long-polling` 주입 완료 상태 유지
  - 안정화 완료 전까지 `auto` 전환은 별도 승인 실험으로 분리
- 성능 목표:
  - 사용자 1명, setlist 20곡 기준 LiveCue 읽기량 `<= 420 reads/min`
  - 곡 전환 후 악보 첫 표시 시간(First Paint) `<= 1.5s` (동일 네트워크 10회 평균)
- 품질 목표:
  - 커버리지 게이트(제외 기준) 임계치 `35%` 유지
  - 전체(raw) 커버리지 `28.45%` 달성(1차 목표 `>= 26%` 완료), 다음 목표는 `>= 30%`
- 롤백 가드레일:
  - 배포 후 30분 내 LC-SAF-01/04/05 중 1건 FAIL이면 즉시 롤백 검토
  - iPad Safari 회색/검은 화면 다중 재현 또는 필기 입력 손실 재현 시 즉시 롤백

---

## 9) 결론

현재 상태는 "기능 구현은 넓게 진행되었지만, LiveCue 실사용 안정성이 완결되지 않은 상태"다.
핵심은 코드 자체보다도 `웹 런타임(브라우저/CORS/renderer/transport)`과 `배포 파이프라인 설정`의 정합성이다.

따라서 다음 계획은 신규 기능 확장보다,
- LiveCue 안정화(P0)
- 배포/운영 검증 자동화(P0/P1)
- 커버리지 맹점 축소(P1)
를 먼저 완료하도록 구성해야 한다.

추가 결론(플랫폼 전략):
- 현 시점 전면 전환(Flutter -> Next.js)은 일정/리스크가 커서 비추천
- 대신 LiveCue 경로 한정 Next.js + Vercel PoC를 먼저 수행해 실측 데이터로 의사결정하는 것이 타당

---

## 10) 참고한 핵심 파일

- `lib/features/projects/live_cue_page.dart`
- `lib/main.dart`
- `web/index.html`
- `lib/utils/storage_helpers.dart`
- `lib/features/teams/team_select_page.dart`
- `lib/features/teams/team_invite_panel.dart`
- `firestore.rules`
- `storage.rules`
- `.github/workflows/ci.yml`
- `.github/workflows/deploy_staging.yml`
- `.github/workflows/deploy_prod.yml`
- `scripts/ci/check_coverage.sh`
- `scripts/storage_cors.json`
- `docs/livecue_incident_runbook.md`
- `docs/livecue_repro_matrix.md`
- `docs/feature_checklist.md`

---

## 11) 플랫폼 전환 검토 (Flutter -> Next.js/Vercel)

### 11.1 검토 배경
- 사용자 이슈의 중심은 SEO/초기 유입이 아니라 `iPad Safari + Apple Pencil` 실사용 안정성이다.
- 현재 Flutter Web은 앱형 UX 장점이 있으나, LiveCue의 렌더/필기/브라우저 런타임 이슈 해결 비용이 크다.
- Next.js는 웹 표준 기반(Canvas/Pointer/DOM 제어)으로 LiveCue 같은 인터랙션 구간에서 대안이 될 수 있다.

### 11.2 대안 비교

| 대안 | 장점 | 단점/리스크 | 현재 판단 |
|---|---|---|---|
| A. Flutter 유지 + 안정화 지속 | 기존 코드/도메인 자산 재사용, 전환비용 최소 | Safari/Pencil 이슈 해결 난이도 지속 | **기본 경로(유지)** |
| B. 전면 Next.js 재구축 + Vercel 이전 | 웹 생태계 도구/인력 확보 용이, 배포 파이프라인 단순화 | 기능 재구현 범위 큼, 회귀 리스크 높음, 일정 지연 | **현 시점 비추천** |
| C. 하이브리드: LiveCue만 Next.js PoC | 핵심 장애 구간만 빠르게 검증 가능, 실패 시 롤백 쉬움 | 이원화 운영 복잡도 증가, 경계 설계 필요 | **권장(다음 단계)** |

### 11.3 권고안
1. 당장은 Flutter 메인 앱(팀/프로젝트/관리자)은 유지한다.
2. LiveCue 화면만 Next.js로 별도 PoC를 만든다.
3. Vercel Preview/Production을 통해 실기기(iPad Safari) 성능/안정성을 먼저 검증한다.
4. PoC가 목표 미달이면 Flutter 경로 안정화에 집중하고 전면 전환은 보류한다.

### 11.4 Go / No-Go 의사결정 게이트
- 아래 조건을 PoC에서 모두 만족하면 확장 전환 검토:
  - LC-SAF-01/04/05 각 3회 연속 PASS
  - 2분 연속 필기 시 입력 손실 0, 깜빡임 0
  - 곡 전환 First Paint 평균 `<= 1.5s` (10회)
  - Firestore/Storage 접근 오류 재현률 현행 대비 유의미 감소
- 하나라도 미달이면:
  - 전면 전환 중단
  - Flutter LiveCue 안정화 백로그(B-01/B-04/B-05/B-11) 우선 지속
