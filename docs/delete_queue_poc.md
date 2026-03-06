# Delete Queue PoC (Cloud Function)

작성일: 2026-03-04

## 목적
- 대규모 팀/프로젝트 삭제를 클라이언트 동기 삭제에서 서버 비동기 큐 방식으로 전환하기 위한 PoC를 제공한다.
- 운영 중 타임아웃/재시도 부담을 줄이고, 삭제 상태 추적을 가능하게 한다.

## 큐 문서 경로
- `teams/{teamId}/deleteQueue/{requestId}`

필수 필드:
- `teamId`: 대상 팀 ID
- `requestedBy`: 요청 사용자 UID
- `type`: `teamDelete` 또는 `projectDelete`
- `status`: `queued` (초기값)

선택 필드:
- `projectId`: `type == projectDelete`일 때 필수

## 워커 파일
- `functions-poc/delete_queue_worker.js`

핵심 동작:
1. `queued` 요청 수신
2. 상태를 `running`으로 전환
3. 삭제 실행
  - `projectDelete`: `teams/{teamId}/projects/{projectId}` 재귀 삭제
  - `teamDelete`: `teams/{teamId}` 재귀 삭제 (+ `teamNameIndex` best-effort 정리)
4. 성공 시 `done`, 실패 시 `failed` + `errorMessage` 기록

## 보안 규칙 연동
`firestore.rules`에 아래 경로가 반영되어 있다.
- `teams/{teamId}/deleteQueue/{requestId}`
  - create: 팀장만 허용(`queued` 요청)
  - get/list: 팀장만 허용
  - update/delete: 클라이언트 금지

## 운영 전환 가이드
1. PoC를 실제 `functions/` 배포 구조로 이동
2. `firebase-functions`/`firebase-admin` 버전 고정
3. 운영에서 큐 소비량/실패율/평균 처리시간 지표 대시보드 연결
4. 클라이언트 `팀 삭제/프로젝트 삭제` 버튼에서 대용량 케이스를 큐 요청 모드로 라우팅
