# Service Account Key Rotation Runbook

작성일: 2026-03-07  
목적: 서비스 계정 키 유출/오남용 리스크(HC-01) 대응 절차를 표준화한다.

## 1) 기본 원칙

- 서비스 계정 JSON 키는 저장소/workspace에 상주시키지 않는다.
- 키는 단기 사용 후 즉시 폐기한다.
- 운영 스크립트 실행 전 대상 프로젝트 검증을 반드시 수행한다.

## 2) 긴급 대응 트리거

아래 중 하나라도 해당하면 즉시 키 폐기 절차를 시작한다.

- 키 파일이 저장소 루트/하위 폴더에서 탐지됨
- 키 파일이 채팅/메일/스크린샷으로 외부 공유됨
- 의심스러운 Firestore/Storage/Admin API 호출이 관측됨

## 3) 즉시 조치 (15분 내)

1. Firebase Console -> Service Accounts에서 노출 의심 키를 비활성/삭제
2. 동일 서비스 계정으로 신규 키 1개만 재발급
3. 기존 실행 세션/로컬 터미널 환경변수(`GOOGLE_APPLICATION_CREDENTIALS`) 정리
4. 신규 키는 안전 저장소(비공개 시크릿 스토어/OS keychain)에만 보관

## 4) 복구 조치 (1시간 내)

1. 운영 스크립트 사전검증
  - `MIGRATION_PROJECT_ID` 설정
  - `MIGRATION_CONFIRM_PROJECT` 동일값 설정
  - `DRY_RUN=1`로 선실행
2. dry-run 결과 검토 후 필요 시 `DRY_RUN=0` 실행
3. 실행 후 키 폐기 여부 결정
  - 일회성 작업이면 즉시 폐기
  - 반복 작업이면 만료주기/접근통제 재설정

## 5) 사후 점검

1. 저장소 키 파일 탐지 점검:
  - `ls -la | rg "firebase-adminsdk|service-account|\\.json$"`
2. 정책 드리프트 점검:
  - 마이그레이션 문서(`scripts/README_MIGRATION.md`)와 운영절차 일치 확인
3. 사고 기록:
  - 발생 시각, 노출 범위, 폐기 시각, 재발급 시각, 복구 결과

## 6) 책임

- 1차 실행자: 운영 작업 실행자
- 2차 검토자: 프로젝트 보안/운영 검토자

