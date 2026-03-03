# WorshipFlow 실행 계획서 (Plan)

작성일: 2026-03-03  
기준 문서: `research.md`

---

## Do Not Implement Without Approval

이 문서는 **구현 전용 승인 게이트**를 포함한다. 아래 규칙을 만족하기 전에는 구현을 시작하지 않는다.

### Implementation Freeze (강제)
- `PLAN-APPROVED` 상태 전에는 **코드 수정 금지**.
- `PLAN-APPROVED` 상태 전에는 **PR 생성 금지**.
- `PLAN-APPROVED` 상태 전에는 **배포/릴리즈 금지**.
- 승인 전 허용 작업은 `research.md`, `plan.md` 등 **문서 수정만** 허용.

### 승인 절차 (plan-approved)
아래 2단계를 모두 충족해야 구현 가능 상태로 전환한다.
1. 사용자 채팅 승인: `PLAN-APPROVED` 명시
2. GitHub 이슈 또는 추적 PR에 `plan-approved` 라벨 부여

상태 정의:
- `PLAN-DRAFT`: 계획 작성/검토 단계 (구현 금지)
- `PLAN-APPROVED`: 구현 시작 가능
- `IMPLEMENTING`: 승인된 범위 구현 중
- `READY-FOR-DEPLOY`: 검증 완료, 배포 승인 대기

---

## 0) 목적

### 핵심 목표
1. 인프라 전환 및 버전 관리 시스템 구축 (GitHub + CI/CD)
2. 핵심 로직 테스트 자동화 (품질 검사 라인)
3. 레거시 코드 정리 및 기술 부채 청산

### 최종 지향점
- AI 협업 환경에서 안전하게 되돌릴 수 있는 구조
- 장기 운영 가능한 CI/CD 체계
- 명확한 승인 게이트 기반 개발 프로세스

### 비목표 (현재 계획 범위 외)
- Firebase 외 다른 DB로 즉시 전환
- 전면 기능 확장 중심 개발
- 전면 UI 리뉴얼 단독 진행

---

## 1) 단일 브랜치/배포 전략

기존 `main/develop` 혼선을 제거하고 **Trunk-Based (main 단일 기준)**로 통일한다.

### 1-1. 브랜치 규칙
- 영구 브랜치: `main`만 사용
- 작업 브랜치: `feature/*`, `fix/*`, `chore/*` (단기 생명주기)
- 모든 변경은 PR을 통해서만 `main` 병합
- 직접 `main` push 금지

### 1-2. 환경 분리 (Staging / Production)
- `staging`:
  - 목적: 베타 검증/회귀 확인
  - 소스: `main` 최신 커밋
  - 트리거: `workflow_dispatch` 또는 main merge 후 자동
- `production`:
  - 목적: 정식 운영
  - 소스: `main`의 릴리즈 태그 `vX.Y.Z`
  - 트리거: `workflow_dispatch` + `production` Environment 승인

### 1-3. 병합 및 배포 차단
- 필수 상태 체크: `ci` 성공
- 최소 리뷰 승인: 1명
- CI 실패 시 `main` 병합 금지
- CI 실패 시 staging/prod 배포 금지

---

## 2) Firebase 배포 인증 전략

### 2-1. 인증 방식 비교

| 방식 | 장점 | 단점 | 권장 사용 |
|---|---|---|---|
| `FIREBASE_TOKEN` | 초기 설정이 빠름, 도입 쉬움 | 개인 계정 의존, 토큰 수명/권한 관리 취약 | 단기 임시 |
| Service Account JSON | 계정 분리 가능, 권한 최소화 설계 용이 | JSON 키 유출 리스크, 키 로테이션 필요 | 중기 기본 |

권장 운영 원칙:
- 단기 안정화: `FIREBASE_TOKEN` 사용 가능
- 운영 전환: Service Account(JSON)로 전환 후 토큰 폐기
- 장기 고도화: OIDC(키리스) 전환 검토

### 2-2. GitHub Environments 시크릿 분리
- Environment:
  - `staging`
  - `production`
- 환경별 시크릿을 반드시 분리 저장:
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_SERVICE_ACCOUNT_JSON` 또는 `FIREBASE_TOKEN`
- `production` Environment는 승인자(required reviewers) 필수
- `staging`은 승인 완화 가능하나 prod 시크릿 재사용 금지

### 2-3. 배포 인증 정책
- staging/prod 각각 **독립 인증 정보** 사용
- 운영 중 인증 키 로테이션 주기 문서화 (`docs/release_runbook.md`)
- 인증 실패/권한 오류 시 배포 job 즉시 실패 처리

---

## 3) CI 품질 게이트 및 커버리지 정책

### 3-1. 필수 CI 단계
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test --coverage`
4. coverage threshold 검사
5. `flutter build web --release`

### 3-2. lcov 의존성 리스크와 보완
`lcov`가 runner에 없으면 커버리지 게이트가 무력화될 수 있다.

기본 전략:
- CI에서 `lcov`를 명시 설치
- 예: Ubuntu runner에서 `apt-get update && apt-get install -y lcov`

대체 전략:
- `lcov` 설치 실패 시 `coverage/lcov.info` 직접 파싱
- `scripts/ci/check_coverage.sh`는 두 경로를 모두 지원
  - 경로 A: `lcov --summary`
  - 경로 B: `awk/grep` 파싱

### 3-3. 실패 시 배포 차단 정책
- CI의 어느 단계라도 실패하면 전체 CI 실패
- staging/prod 배포 워크플로우는 `needs: ci`로 의존
- CI 실패 상태에서는 배포 job을 실행하지 않음
- prod는 CI 성공 + Environment 승인 없이는 배포 불가

---

## 4) research.md 리스크 ↔ Phase 매핑

`research.md` 15장 리스크를 실행 단계에 명시적으로 연결한다.

| 리스크 ID | `research.md` 요약 리스크 | 대응 Phase | 대응 방식 |
|---|---|---|---|
| R-01 | 테스트 커버리지 부족 | Phase 2 | 단위/위젯/통합 테스트 + 커버리지 게이트 |
| R-02 | 클라이언트-룰 정합성 민감 구간(자가 복구 포함) | Phase 2, 3 | 권한 시나리오 + 자가 복구(Self-Healing) 회귀 테스트 + 권한 로직 공통화 |
| R-03 | 대규모 삭제 비용/실패 재시도 부담 | Phase 3 | 삭제 경로 표준화 + 실패 처리 정책 + Cloud Function 비동기 삭제 대안 검토 |
| R-04 | 관리자 기능 중복(`GlobalSongPanel`/`GlobalAdminPage`) | Phase 3 | 책임 경계 재정의 및 중복 제거 |
| R-05 | legacy 호환 코드 증가 | Phase 3 | 마이그레이션 기준 수립 + fallback 단계적 축소 |
| R-06 | 운영 체크(rules/CORS/캐시) 누락 위험 | Phase 1, 2 | 배포 런북 고정 + 배포 전 점검 자동화 + 서비스 워커/캐시 정책 재평가 |

---

## 5) Phase 1: 인프라 전환 및 버전 관리 체계 구축

### 5-1. 목적
- 되돌릴 수 있는 배포 구조 확보
- 승인 기반 배포 통제 확립

### 5-2. 범위
- GitHub Actions CI/CD 골격 구축
- `main` 보호 규칙
- staging/prod Environment 분리
- 릴리즈/롤백 런북 정리
- 웹 캐시/서비스 워커 정책 재평가 및 운영 정책 결정

### 5-3. 예상 변경 파일 (상대경로)
- `.github/workflows/ci.yml`
- `.github/workflows/deploy_staging.yml`
- `.github/workflows/deploy_prod.yml`
- `.github/CODEOWNERS`
- `.github/pull_request_template.md`
- `docs/release_runbook.md`
- `docs/web_cache_strategy.md`
- `README.md`

### 5-4. 체크리스트
- [ ] GitHub 브랜치 보호 규칙 적용
- [ ] PR/리뷰 필수 정책 적용
- [ ] staging/prod Environment 생성 및 승인 정책 설정
- [x] Firebase 인증 방식(토큰/서비스계정) 선택 및 반영
- [x] 배포/롤백 절차 문서화
- [x] 서비스 워커 정책(유지/부분복구/비활성) 비교 후 운영안 확정

### 5-5. 완료 기준
- PR에서 CI 자동 실행 및 실패 시 merge 차단
- staging/prod 배포 파이프라인 분리 동작 확인
- 태그 기반 prod 릴리즈/롤백 절차 재현 가능
- 웹 캐시/서비스 워커 정책 결정 문서(`docs/web_cache_strategy.md`) 확정

---

## 6) Phase 2: 테스트 자동화 및 품질 게이트 구축

### 6-1. 목적
- 반복되는 회귀 오류를 배포 전에 차단

### 6-2. 범위
- 핵심 경로 테스트 작성
- 커버리지 게이트 상시 동작 보장
- 배포 차단 조건 CI에 강제
- 자가 복구(Self-Healing) 시나리오 회귀 테스트 포함

### 6-3. 예상 변경 파일 (상대경로)
- `test/unit/song_parser_test.dart`
- `test/unit/storage_helpers_test.dart`
- `test/unit/team_name_test.dart`
- `test/widget/team_select_page_test.dart`
- `test/widget/team_home_page_test.dart`
- `test/widget/live_cue_page_test.dart`
- `integration_test/critical_flow_test.dart`
- `integration_test/self_healing_flow_test.dart`
- `scripts/ci/check_coverage.sh`
- `docs/test_strategy.md`
- `pubspec.yaml` (필요 시 dev dependency 보강)

### 6-4. 체크리스트
- [x] 핵심 로직 단위 테스트 추가
- [ ] 핵심 화면 위젯 테스트 추가
- [ ] 권한/팀/프로젝트 주요 시나리오 통합 테스트 추가
- [ ] 자가 복구 시나리오(멤버십 누락/불일치, stale 참조, 최근 팀/프로젝트 복구) 회귀 테스트 추가
- [x] 커버리지 임계치 설정 및 스크립트 이중 경로 구현
- [ ] CI 실패 시 배포 차단 동작 검증

### 6-5. 완료 기준
- 커버리지 게이트가 CI에서 누락 없이 실행
- CI 실패 시 staging/prod 배포가 실제로 차단됨
- 핵심 사용자 경로 회귀 테스트 자동 실행
- 자가 복구 경로 회귀 테스트가 CI에 포함되어 재현 가능

---

## 7) Phase 3: 레거시 정리 및 기술 부채 청산

### 7-1. 목적
- 구조적 불안정 요소 제거
- 유지보수 비용 절감

### 7-2. 범위
- 권한/역할/ID 처리 공통화
- 관리자 기능 중복 제거
- legacy fallback 정리 기준 수립
- 대규모 삭제 처리의 서버 비동기 대안(Cloud Function) 검토 및 선택

### 7-3. 예상 변경 파일 (상대경로)
- `lib/features/songs/global_song_panel.dart`
- `lib/features/admin/global_admin_page.dart`
- `lib/features/teams/team_select_page.dart`
- `lib/features/teams/team_home_page.dart`
- `lib/features/projects/live_cue_page.dart`
- `lib/core/roles.dart` (신규)
- `lib/core/firestore_id.dart` (신규)
- `lib/repositories/*` (신규, 점진 도입)
- `docs/tech_debt_register.md`

### 7-4. 체크리스트
- [ ] 권한/역할 파싱 로직 단일화
- [ ] Firestore ID/참조 검증 유틸 공통화
- [ ] 대규모 삭제 로직 표준화 및 실패 처리 명확화
- [ ] 대규모 삭제의 Cloud Function 비동기 처리 대안 설계/비교(클라이언트 일괄 삭제 대비)
- [ ] 전역 관리자 기능 중복 제거
- [ ] legacy fallback 제거/유지 기준 문서화

### 7-5. 완료 기준
- 중복 코드와 분기 감소 지표 기록
- 핵심 경로 테스트 통과 상태 유지
- 기술 부채 항목 추적 문서 최신화
- 대규모 삭제 처리 방식(클라이언트/서버 비동기) 최종 결정 및 문서화

---

## 8) 승인 기반 실행 절차

### 8-1. 승인 전 (반복)
1. `research.md` 최신화
2. `plan.md` 구조/범위 업데이트
3. 사용자 메모 반영
4. 다시 검토
5. `PLAN-APPROVED` + `plan-approved` 라벨 확인

### 8-2. 승인 후 (실행)
1. Phase 1 수행 및 검증 기록
2. Phase 2 수행 및 검증 기록
3. Phase 3 수행 및 검증 기록
4. staging 배포 검증
5. production 승인 후 배포

---

## 9) 운영 산출물

### Phase 1 산출물
- CI/CD 워크플로우
- 브랜치/리뷰/배포 승인 정책
- 릴리즈/롤백 런북

### Phase 2 산출물
- 핵심 테스트 스위트
- 커버리지 게이트 스크립트
- 테스트 전략 문서

### Phase 3 산출물
- 공통화된 구조
- 기술부채 레지스터
- legacy 정리 기준 문서

---

## 10) 구현 시작 전 체크 (Gate Checklist)

아래 3개가 모두 true일 때만 구현 시작:
- [ ] 사용자 `PLAN-APPROVED` 선언 확인
- [ ] `plan-approved` 라벨 확인
- [ ] 이번 사이클 대상 Phase 범위 확정

만약 하나라도 미충족이면 상태를 `PLAN-DRAFT`로 유지하고 문서 작업만 수행한다.
