# LiveCue iPad Safari 재현 매트릭스

작성일: 2026-03-04  
목적: `LiveCue` 장애를 조건별로 고정 재현하고, 수정 후 동일 시나리오로 회귀 검증한다.

## 1) 테스트 전 공통 조건
- 앱 URL: `https://worshipflow-df2ce.web.app`
- 로그인 계정: 팀 멤버 + LiveCue 편집 권한 계정
- 대상 곡: 이미지 자산(필기 테스트용) + PDF 자산(직접열기 fallback 확인용)
- 브라우저 캐시: 일반 모드 1회, 강력 새로고침 1회
- 기록 기준:
  - 첫 에러 1줄
  - 발생 시각(로컬 시간)
  - 10초 이상 화면 녹화 링크

## 2) 재현 매트릭스

| Case ID | 기기 | OS / 브라우저 | 네트워크 | 파일 타입 | 입력 모드 | 기대 결과 | 실제 결과 | 상태 |
|---|---|---|---|---|---|---|---|---|
| LC-SAF-01 | iPad Pro | iPadOS / Safari | Wi-Fi | JPEG | 터치/펜슬 필기 | 악보 표시 + 필기 저장 정상 | first_error: `Fetch API cannot load ... Firestore/Listen/channel ... due to access control checks.`<br>video: `/Users/hwanghuichan/Downloads/IMG_9230.MOV`<br>증상: 필기 중 깜빡임/입력 손실 | FAIL |
| LC-SAF-02 | iPad Pro | iPadOS / Safari | LTE/5G 테더링 | JPEG | 터치/펜슬 필기 | 곡 전환 + 필기 연속 10분 무중단 | first_error: 미관측(실기기 재검증 필요)<br>time: 2026-03-07 18:30 (KST, 수집 슬롯 예약)<br>video: 증빙 대기 | PARTIAL |
| LC-SAF-03 | iPad Pro | iPadOS / Safari | Wi-Fi | PDF | 파일 직접 열기 fallback 정상 | first_error: 없음<br>video: 스크린샷 증거(파일 직접 열기 성공) | PASS |
| LC-SAF-04 | iPad Pro | iPadOS / Safari | Wi-Fi | JPEG | 지우개/되돌리기 | 지우개/되돌리기 정상 | first_error: `Another exception was thrown: Instance of 'minified:mh<erased>'`<br>video: `/Users/hwanghuichan/Downloads/IMG_9230.MOV`<br>증상: 지우개/되돌리기 불안정 | FAIL |
| LC-SAF-05 | iPad Pro | iPadOS / Safari | Wi-Fi | JPEG | 좌우 전환/스와이프 | 현재/다음 곡 전환 정상 | first_error: `악보 로드 실패 ...` + Firestore Listen CORS 로그<br>video: `/Users/hwanghuichan/Downloads/IMG_9230.MOV`<br>증상: 회색 화면 간헐 고정 | FAIL |
| LC-SAF-06 | iPhone | iOS / Safari | LTE/5G | JPEG | 터치 필기 | 축소 화면에서도 필기 입력 정상 | first_error: 미관측(실기기 재검증 필요)<br>time: 2026-03-07 18:30 (KST, 수집 슬롯 예약)<br>video: 증빙 대기 | PARTIAL |

## 3) 콘솔 치명 로그 재현 조건(수집본)

| 로그 시그니처 | 관측 Case | 관측 조건 | 비고 |
|---|---|---|---|
| `Bad state: Stream has already been listened to` | LC-SAF-05 | LiveCue 진입 후 곡 전환/필기 모드 on/off를 반복하고 재진입 시 콘솔에서 간헐 관측 | 재현률 낮음, 추가 고정 필요 |
| `Unsupported operation: 'add': Cannot add to a constant list` | LC-SAF-04 | 필기 모드에서 지우개/되돌리기 반복 중 간헐 관측 | 스택트레이스 minified 상태라 source-map 기반 재확인 필요 |
| `Fetch API cannot load ... Firestore/Listen/channel ... due to access control checks` | LC-SAF-01/05 | Safari + LiveCue 이미지 악보 조회 시 Firestore long-poll 경로에서 관측 | 환경/CORS 정합성 항목과 연계 점검 |

## 4) 오류 로그 템플릿

```
[LiveCue Incident]
time: 2026-03-04 23:59:59 (KST)
case_id: LC-SAF-01
device: iPad Pro 12.9 (iPadOS xx.x)
browser: Safari xx
network: Wi-Fi / LTE / 5G
first_error: Fetch API cannot load ... Firestore/Listen/channel ...
symptom: 회색 화면 고정 / 필기 입력 불가 / 곡 전환 실패
video: <link>
```

## 5) 판정 규칙
- `PASS`: 동일 조건 3회 재시도에서 모두 성공, 첫 에러 로그 없음
- `FAIL`: 1회라도 치명 증상(회색 화면, 필기 불가, 전환 불가) 발생
- `PARTIAL`: 치명 증상은 없지만 경고/지연이 관측됨
