# LiveCue 장애 대응 런북

작성일: 2026-03-04  
적용 범위: LiveCue 운영 화면(`악보보기`, 필기 레이어, 곡 전환)

## 1) 트리거 조건
아래 중 하나라도 충족하면 장애 대응 절차를 시작한다.
- iPad Safari에서 악보가 회색/검은 화면으로 고정
- 필기 입력(펜슬/터치)이 불가능하거나 반복 깜빡임
- `Firestore Listen/channel` 오류가 연속 발생
- `Bad state: Stream has already been listened to` 발생
- `Cannot add to a constant list` 발생

## 2) 1차 분류 (5분 내)
1. 재현 조건 고정:
   - 기기/OS/브라우저/네트워크/계정/곡 파일 타입 기록
2. 첫 에러 1줄 캡처:
   - 콘솔 첫 치명 로그만 우선 수집
3. 증상 분류:
   - A: 악보 렌더링 실패
   - B: 필기 레이어 입력 실패
   - C: Firestore 동기화 실패

## 3) 즉시 완화 조치
- A(렌더링 실패):
  - `파일 직접 열기`로 임시 우회
  - 곡 상세 페이지에서 원본 파일 열기 확인
  - 콘솔에서 CORS 관련 첫 에러 라인 저장 후 `scripts/storage_cors.json` 정합성 점검
- B(필기 실패):
  - 필기 모드 재진입 1회
  - 레이어 전환(개인/공유) 후 입력 재시도
  - 필기 모드 중 `WebHtmlElementStrategy.prefer` 경로 진입 여부 확인
- C(동기화 실패):
  - LiveCue 화면 재진입
  - 동일 계정으로 `현재/다음 곡` 상태 복구 확인
  - `WF_FIRESTORE_TRANSPORT=long-polling` 빌드 적용 여부 확인

## 4) 핫픽스/롤백 기준
- 핫픽스:
  - 단일 원인(렌더/입력/동기화)으로 범위가 작고, 재현 조건이 고정된 경우
- 롤백:
  - 장애 범위가 복합적이거나, 라이브 운영 중 연속 실패 시 즉시 이전 안정 릴리즈로 롤백
  - 배포 후 30분 내 LC-SAF-01/04/05 중 1건 FAIL이면 즉시 롤백 검토
  - iPad Safari 회색/검은 화면이 독립 세션 2건 이상이면 즉시 롤백
  - 필기 입력 손실 재현 시 즉시 롤백

## 5) 릴리즈 게이트 연동 (로컬 기준)
- Production 반영 전 반드시 Safari 스모크 결과를 기록한다.
- 필수 기록:
  - `livecue_safari_smoke_result=pass`
  - `livecue_safari_smoke_evidence=<이슈/영상 링크>`
- 검증 스크립트(로컬 실행):
  - `scripts/ci/verify_livecue_safari_gate.sh`

## 6) 사후 기록
- 장애 1건당 아래를 남긴다.
  - 재현 조건
  - 첫 에러 1줄
  - 임시 조치/영구 조치
  - 릴리즈 영향 범위
  - 재발 방지 액션

## 7) 롤백 실행 책임/증빙
- 1차 담당: 배포 실행자(Release owner)
- 2차 승인: 운영 승인자
- 실행 절차(백업/복구 정책):
  - 로컬에서 이전 안정 backup ref(`tag`/`commit`)를 체크아웃
  - 로컬 검증(`flutter analyze`, `flutter test --coverage`, Safari smoke) 후 재배포
- 증빙 경로:
  - 로컬 배포/복구 실행 로그
  - `docs/livecue_repro_matrix.md` 재검증 결과
  - 장애/복구 영상 링크

## 8) LiveCue 웹 폴링 계측 기준
- 현재 웹 폴링 간격:
  - setlist: 3.5초
  - liveCue state: 1.0초
- 렌더/캐시 안정화 정책:
  - 필기 모드에서는 `WebHtmlElementStrategy.prefer`를 사용하지 않음
  - setlist/liveCue 폴링은 스냅샷 시그니처 기준으로 중복 emit을 차단
  - 서비스워커 강제 해제는 로컬 개발/명시적 override에서만 수행
- 읽기량 계산식(클라이언트 1명):
  - `reads/min ~= (60 / setlist_interval_sec) * (N + 1) + (60 / cue_interval_sec) * 1`
  - `N=20` 기준 예상치: 약 420 reads/min
- 측정 항목:
  - 곡 전환 후 첫 표시 시간(First Paint)
  - 분당 읽기량 추정치(위 식 + 실제 폴링 로그)
  - 동일 곡 유지 중 재렌더 횟수(중복 emit 제거 확인)
