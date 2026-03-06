# WorshipFlow 실행 계획서 (Replan)

작성일: 2026-03-07  
기준 문서: `research.md` (2026-03-07 Hard Refresh)

---

## 0) 원칙

### 0-1. 현재 상태 인식
- 기능 폭은 넓지만, LiveCue 실사용 안정성(특히 iPad Safari + Pencil)이 아직 불충분하다.
- 따라서 다음 사이클은 **신규 기능 추가보다 안정화/최적화 우선**으로 진행한다.

### 0-2. 진행 원칙
1. 장애 재현 조건을 먼저 고정한다.
2. 재현 불가 상태에서 "완료" 처리하지 않는다.
3. 코드 수정 후 반드시 실기기 매트릭스로 재검증한다.
4. Production 반영 전, Safari smoke 증거를 남긴다.

### 0-3. 상태 정의
- `NOT-STARTED`: 착수 전
- `IN-PROGRESS`: 구현/검증 진행 중
- `BLOCKED`: 외부 조건(콘솔 설정/권한/기기) 필요
- `DONE`: 코드 + 검증 + 증거까지 완료

---

## 1) 우선순위 맵

| Priority | 트랙 | 목표 |
|---|---|---|
| P0 | 장애 안정화 | 악보 깜빡임/회색화면/필기 불가 해결 |
| P0 | 설정 정합성 | CORS/Firestore transport/배포 설정 정합성 확보 |
| P1 | 비용/성능 | LiveCue 폴링 구조 최적화(읽기 비용/재빌드 감소) |
| P1 | 품질게이트 | LiveCue 회귀 테스트/실기기 게이트 강화 |
| P1 | 플랫폼 전략 | LiveCue의 Next.js/Vercel PoC 검증 후 전환 의사결정 |
| P2 | 구조 개선 | 대형 파일 분해/커버리지 맹점 축소 |

---

## 2) Phase A — 장애 기준선 고정 (P0)

상태: `BLOCKED` (MANUAL 증거 수집 대기)

### 목표
- "무엇이 실패인지"를 케이스 단위로 고정하고, 수정 후 PASS/FAIL을 명확히 판단 가능하게 만든다.

### 작업
- [ ] `docs/livecue_repro_matrix.md`의 LC-SAF-01~06 실제 결과 채우기 (현재 LC-SAF-02/06은 TODO)
- [ ] (MANUAL) 케이스별 첫 에러 로그 1줄 + 영상 링크 첨부
- [x] `docs/livecue_incident_runbook.md`에 이번 장애 패턴(필기 불가/회색화면) 업데이트

### 완료 기준
- [x] 최소 iPad Safari 케이스 3개 이상 재현 결과가 기록됨
- [ ] "현재 실패 증상"이 문장 아닌 데이터(케이스/로그/영상)로 남음 (LC-SAF 전 케이스 기준)

---

## 3) Phase B — 설정/배포 정합성 복구 (P0)

상태: `BLOCKED` (MANUAL 운영 증빙 대기)

### 목표
- 코드 이전에 환경 불일치(CORS/transport/build flag)로 생기는 장애를 제거한다.

### 작업
- [ ] (MANUAL) Storage bucket CORS 현재값 확인 및 `scripts/storage_cors.json`과 일치 검증
- [x] CORS 검증 절차를 runbook에 체크리스트로 고정
- [x] staging/prod 빌드에서 `WF_FIRESTORE_TRANSPORT` 값을 명시적으로 고정
  - staging: `long-polling`
  - prod: `long-polling` (안정화 완료 전까지 고정, `auto` 전환은 별도 승인 실험으로 분리)
- [x] `web/index.html` 서비스워커 강제 unregister + 1회 reload 정책의 운영 모드(개발/운영) 분리 방안 확정
- [x] staging 워크플로우에서도 Safari smoke를 fail-fast로 올릴지 정책 결정

### 완료 기준
- [ ] (MANUAL) CORS 적용 여부를 콘솔/CLI 출력으로 증빙 가능
- [x] `deploy_staging.yml`, `deploy_prod.yml` 빌드 명령에 `--dart-define=WF_FIRESTORE_TRANSPORT=...`가 명시됨
- [x] 워크플로우 정적 증빙:
  - `grep -n "WF_FIRESTORE_TRANSPORT" .github/workflows/deploy_staging.yml .github/workflows/deploy_prod.yml` 결과 확인 완료
  - 정적 확인(2026-03-05): `.github/workflows/deploy_staging.yml:27,68` / `.github/workflows/deploy_prod.yml:32,73`
- [ ] (MANUAL) staging/prod 최근 배포 실행 로그 링크 각각 1개 이상 첨부
- [x] 서비스워커 정책이 \"stale 방지\"와 \"라이브 UX(초기 깜빡임 최소화)\"를 동시에 만족하도록 문서화
- [x] staging에서 장애 재현 케이스가 경고가 아닌 차단 조건으로 관리됨(또는 의도적 예외 문서화)

---

## 4) Phase C — LiveCue 렌더/입력 안정화 (P0)

상태: `BLOCKED` (MANUAL 실기기 검증 대기)

### 목표
- iPad 실사용에서 악보 로딩과 필기 동작을 안정화한다.

### 작업
- [x] LiveCue 이미지 렌더 실패 경로를 단계별로 분리(네트워크 실패 vs 디코딩 실패 vs 렌더 전략 전환)
- [x] 필기 모드에서 `WebHtmlElementStrategy.prefer` fallback 충돌 여부 점검
- [x] 필기 모드와 확대/축소/곡 전환 동시 사용 시 깜빡임 원인 분리
- [x] `Stream has already been listened to` / `Cannot add to a constant list` 로그 재현 조건 수집

### 완료 기준
- [ ] (MANUAL) iPad Safari + Apple Pencil 기준, LC-SAF-01/04/05 각각 연속 3회 PASS
- [ ] (MANUAL) 각 케이스는 2분 이상 연속 필기(선 긋기+지우개+되돌리기 포함) 시나리오로 수행
- [ ] (MANUAL) 필기 중 화면 깜빡임 0회, 입력 손실 0회 (허용치 0%)
- [ ] (MANUAL) 회색/검은 화면 0회 (허용치 0%)
- [ ] (MANUAL) 치명 콘솔 오류가 재현되지 않음(허용 경고 목록 제외)

---

## 5) Phase D — 성능/비용 최적화 (P1)

상태: `BLOCKED` (MANUAL 성능 측정 대기)

### 목표
- LiveCue의 읽기 비용과 불필요 재빌드를 줄여 라이브 안정성을 높인다.

### 작업
- [x] 웹 폴링(setlist 3.5s / liveCue 1.0s) 구조의 읽기량 계측 지표 정의
- [x] setlist 전체 재조회 빈도 최소화 전략 설계
- [x] current/next 상태 변경과 무관한 UI 재빌드 분리
- [x] 악보 프리로드/캐시 정책을 필기 안정성 우선으로 재조정

### 완료 기준
- [x] 사용자 1명, setlist 20곡 기준 분당 읽기량 `<= 420` (기준선 약 1050/min 대비 60% 이상 절감)
  - 계산 근거(2026-03-05): `setlist 3.5s`, `liveCue 1.0s`, `N=20` -> `(60/3.5)*(20+1) + (60/1.0)*1 = 420`
- [ ] (MANUAL) 곡 전환 후 악보 첫 표시 시간(First Paint) `<= 1.5s` (동일 네트워크 조건 10회 평균)
- [ ] (MANUAL) 곡 전환 시 체감 깜빡임 감소(동일 케이스 비교 영상 확보)
- [ ] (MANUAL) 최적화 후에도 LC-SAF 주요 케이스 PASS 유지

---

## 6) Phase E — 테스트/게이트 강화 (P1)

상태: `DONE`

### 목표
- "CI green인데 실사용 실패"를 줄이는 방어선 구축.

### 작업
- [x] LiveCue 장애 재현 케이스를 테스트 전략 문서에 강제 항목으로 명시
- [x] 커버리지 제외 regex 축소 계획 수립(고위험 파일부터 단계적 복구)
- [x] `FakeFirestore/MockStorage` 기반 통합 테스트 한계를 문서화하고, 실브라우저 CORS/렌더 경로 수동 검증 체크를 필수화
- [x] 실기기 Safari smoke 결과를 릴리즈 승인 필수 증거로 통일
- [x] 로컬 rules 테스트 실행 환경(Java) 준비 가이드 정리

### 완료 기준
- [x] `docs/test_strategy.md`에 LiveCue 실환경 회귀 케이스가 필수로 반영
- [x] CI 커버리지 게이트(제외 기준)는 현재 임계치 `35%`를 명시하고 매 실행마다 검사
- [x] 커버리지 지표를 `제외 기준`과 `전체(raw) 기준` 2축으로 함께 보고
- [x] 전체(raw) 커버리지는 `28.45%`로 1차 목표 `>= 26%` 달성 (2026-03-05 측정)
- [x] 릴리즈 시 evidence 링크 누락 시 승인 불가

---

## 7) Phase F — 구조 개선/부채 상환 (P2)

상태: `IN-PROGRESS` (설계 완료, 구현 미착수)

### 목표
- 대형 단일 파일 구조를 분해해 디버깅과 회귀 리스크를 줄인다.

### 작업
- [x] `live_cue_page.dart`를 데이터/렌더/입력/오버레이 단위로 분리 설계
- [x] `team_home_page.dart`, `team_select_page.dart` 책임 분리 계획 수립
- [x] 분리 후 테스트 경계(단위/위젯) 재정의

### 완료 기준
- [x] 파일 분해 후 핵심 흐름별 테스트 포인트가 명시됨
- [x] 변경 영향 범위가 기능 단위로 추적 가능해짐
- [ ] 1차 모듈 분리 코드 반영(예: LiveCue 렌더/입력 분리) 후 회귀 테스트 PASS

---

## 8) 백로그 추적표 (research 연동)

| Backlog ID | 내용 | Phase | 상태 |
|---|---|---|---|
| B-01 | iPad 필기 실패 원인 분리 | C | BLOCKED |
| B-02 | Storage CORS 적용/검증 자동화 | B | NOT-STARTED |
| B-03 | Firestore transport 배포 전략 명시 | B | DONE |
| B-04 | LiveCue 폴링 최적화 | D | BLOCKED |
| B-05 | 렌더러/필기 모드 충돌 완화 | C | BLOCKED |
| B-06 | LiveCue 회귀 루틴 강화 | E | DONE |
| B-07 | 커버리지 제외 축소 | E | DONE |
| B-08 | flutter.js.map 노이즈 정리 | F | NOT-STARTED |
| B-09 | 대형 파일 모듈 분해 | F | IN-PROGRESS |
| B-10 | staging Safari gate 강화 | B/E | DONE |
| B-11 | 서비스워커 강제 unregister/reload 정책 재검토 | B | DONE |
| B-12 | LiveCue Next.js/Vercel PoC | G | NOT-STARTED |
| B-13 | 전면 전환 Go/No-Go 의사결정 | G | NOT-STARTED |

---

## 9) 이번 실행에서 확인된 상태

- `analyze/test/build`는 통과하지만, LiveCue 실기기 안정성은 미완료
- 커버리지는 제외 적용 시 43.69%, 전체(raw)는 28.45%로 1차 목표(>=26%) 달성
- LiveCue 통합 테스트는 mock 중심이라 실제 CORS/렌더 fallback 경로는 별도 실기기 검증이 필요
- 로컬 rules 테스트는 Java 미설치로 즉시 실행 불가
- 팀 정책(동일팀명 합류요청/팀ID 비노출/유령팀 사용자 액션 제거)은 코드상 반영됨
- 배포 워크플로우(`ci/staging/prod`) 빌드에 `WF_FIRESTORE_TRANSPORT=long-polling` 주입 완료
- staging Safari smoke gate를 `required`로 상향해 fail-fast 동작 반영
- `web/index.html` 서비스워커 강제 해제 로직을 로컬 개발/명시적 override에서만 동작하도록 분리
- 전면 전환(Flutter -> Next.js)은 즉시 진행하지 않고, LiveCue 한정 PoC 기반으로 의사결정

---

## 10) 다음 실행 권장

1. Phase A/B를 먼저 끝내고,
2. Phase C에서 iPad 필기/렌더 안정성을 닫은 뒤,
3. Phase D(수동 성능 계측)를 닫고,
4. 그 다음 Phase F 리팩터링으로 들어간다.
5. 안정화 지표 확보 후 Phase G(Next.js/Vercel PoC)로 전환 검토를 진행한다.

이 순서를 지키지 않으면, 구조 개선 중에 실사용 장애가 다시 숨겨질 가능성이 높다.

---

## 11) 릴리즈 롤백 조건 (P0 Guardrail)

상태: `BLOCKED` (MANUAL 리허설 대기)

### 목표
- \"배포는 완료됐지만 실사용 장애가 남는 상태\"를 운영 단계에서 즉시 차단한다.

### 롤백 트리거 (하나라도 충족 시 즉시 롤백)
- 배포 후 30분 내 LC-SAF-01/04/05 중 1개라도 FAIL 재현
- iPad Safari에서 회색/검은 화면이 2건 이상 독립 세션에서 확인
- 필기 입력 손실 또는 펜 이벤트 끊김이 1회라도 재현
- Firestore/Storage 접근 오류로 악보 로딩 실패가 연속 3회 발생

### 완료 기준
- [x] 롤백 담당자/실행 명령/증거 수집 경로가 runbook에 명시됨
- [ ] (MANUAL) staging 1회, prod 1회 롤백 리허설 기록이 남아 있음

---

## 12) Phase G — 플랫폼 전환 검토 (Flutter vs Next.js/Vercel) (P1)

상태: `BLOCKED` (MANUAL PoC 실행/판정 대기)

### 목표
- Flutter 메인 앱은 유지하면서, LiveCue 경로의 Next.js/Vercel 전환 가능성을 실측 데이터로 판단한다.

### 작업
- [x] Flutter 유지 + LiveCue 한정 PoC 전략을 `research.md/plan.md`에 반영
- [ ] (MANUAL) LiveCue Next.js PoC 범위(라우트/데이터 계약/권한 경계) 승인
- [ ] (MANUAL) Vercel Preview 배포 후 iPad Safari 실기기 테스트 3회 수행
- [ ] (MANUAL) Flutter 대비 성능/안정성 비교표 작성
- [ ] (MANUAL) Go/No-Go 의사결정 기록(전면 전환/부분 전환/보류 중 1개 확정)

### 완료 기준
- [ ] (MANUAL) LC-SAF-01/04/05 각 3회 PASS
- [ ] (MANUAL) 2분 연속 필기 시 깜빡임 0, 입력 손실 0
- [ ] (MANUAL) 곡 전환 First Paint 평균 `<= 1.5s` (10회)
- [ ] (MANUAL) 전환 의사결정 결과가 문서화되고 다음 단계(확장/보류)가 확정됨
