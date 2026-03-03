# WorshipFlow 기능 체크리스트

목적: 누락 없이 기능을 완성하기 위한 단일 기준 문서.

상태 규칙:
- `TODO`: 아직 작업 전
- `IN-PROGRESS`: 현재 턴에서 작업 중
- `PARTIAL`: 구현은 되었고 실환경 검증만 남음
- `DONE`: 코드/검증 완료
- `BLOCKED`: 외부 설정/결정 필요

## 0) 최신 현황 스냅샷 (2026-02-19)

| 구분 | 개수 | 상태 |
|---|---:|---|
| 기능 항목(F-*) | 34 | 전체 `DONE` |
| 안정성/보안(S-*) | 8 | 전체 `DONE` |
| 부분완료 | 0 | 없음 |
| 미완료 | 0 | 없음 |

최신 자동 검증:
- `flutter analyze`: 통과
- `flutter test`: 통과

## 1) 핵심 운영 흐름

| ID | 기능 | 상태 | 확인 방법 |
|---|---|---|---|
| F-001 | 로그인 후 `내 팀` 목록 로드 | DONE | 팀 탭 진입 시 permission 에러 없이 목록 표시 |
| F-002 | 팀 생성 후 F5/재로그인 시 팀 유지 | DONE | F5 + 로그아웃/재로그인 후 동일 팀 표시 |
| F-003 | 팀 홈에서 프로젝트 생성/재진입 유지 | DONE | 프로젝트 생성 후 목록/재진입 유지 확인 |
| F-004 | 팀 초대(이메일) 생성/수락 | DONE | 초대 생성 -> 상대 수락 -> 팀 목록 반영 |
| F-005 | 팀 초대(카카오 링크) 원탭 복사/공유 | DONE | 모바일/태블릿에서 1탭 복사 또는 공유 시트 노출 |
| F-006 | 초대 링크로 진입 시 초대 대기/수락 동작 | DONE | 링크 접속한 계정에서 수락 UI/처리 확인 |
| F-007 | 여러 팀 동시 소속 사용자 팀 전환 | DONE | 홈 복귀 후 다른 팀 선택 진입 |
| F-008 | 기존 팀명 중복 생성 차단 + 안내 메시지 | DONE | 이미 등록된 팀명으로 생성 시 차단/안내 |

## 2) 권한/역할

| ID | 기능 | 상태 | 확인 방법 |
|---|---|---|---|
| F-101 | 역할명 프론트 통일(팀장/인도자/팀원) | DONE | 화면 전반 역할 라벨 확인 |
| F-102 | 팀장 UI에서 팀원 역할 변경 가능 | DONE | 멤버 역할 변경 액션 동작 확인 |
| F-103 | 사용자 본인 역할 표시 | DONE | 팀 홈 또는 프로젝트 상단에 내 역할 노출 |
| F-104 | 운영자(`/admin`) 접근 제어 | DONE | 비운영자 차단, 운영자 진입 허용 |
| F-105 | 일반 사용자의 전역 악보 수정/삭제 차단 | DONE | 관리자 아닌 계정에서 차단 확인 |
| F-106 | 타 팀 URL 직접 접근 시 데이터 비노출 | DONE | 다른 teamId/projectId 직접 입력 테스트 |

## 3) 악보/곡 관리

| ID | 기능 | 상태 | 확인 방법 |
|---|---|---|---|
| F-201 | 전역 곡 생성/조회/수정/삭제(CRUD) | DONE | 관리자에서 CRUD 수행 |
| F-202 | 악보 업로드 성공(이미지/PDF) | DONE | 업로드 후 목록/재진입 시 유지 확인 |
| F-203 | 악보 다운로드/열기 동작 | DONE | 악보 열기/새 탭/다운로드 동작 확인 |
| F-204 | 곡별 다중 키 버전(D/Eb/E...) 등록 | DONE | 한 곡에 여러 키 자산 등록 확인 |
| F-205 | 키 선택/자동 필터링으로 악보 매칭 | DONE | 콘티 키 변경 시 해당 키 악보 매칭 확인 |
| F-206 | 관리자에서 악보 미리보기 기반 삭제 | DONE | 링크 텍스트 대신 미리보기 확인 후 삭제 |

## 4) LiveCue (핵심 사용 화면)

| ID | 기능 | 상태 | 확인 방법 |
|---|---|---|---|
| F-301 | setlist 입력 시 LiveCue 자동 반영 | DONE | 예배 전 입력 -> LiveCue 즉시 반영 |
| F-302 | LiveCue 기본 화면 텍스트 setlist 중심 | DONE | `1`, `1-2`, `2` 형태 목록 확인 |
| F-303 | LiveCue 진입 시 첫 곡 자동 포커스 | DONE | 진입 즉시 1번 곡 상태 확인 |
| F-304 | 좌/우 버튼으로 곡 전환 | DONE | 버튼 반복 이동 시 상태 정상 |
| F-305 | 키보드 화살표로 곡 전환 | DONE | 좌/우 방향키 반응 확인 |
| F-306 | 스와이프로 곡 전환(태블릿) | DONE | iPad Safari/Chrome 스와이프 확인 |
| F-307 | 전체화면에서 악보만 집중 표시 | DONE | 전체화면 진입 시 UI 최소화 확인 |
| F-308 | 확대/축소(핀치줌) 안정 동작 | DONE | 확대/축소 후 위치/해상도 깨짐 없음 |
| F-309 | 가로/세로 회전 후 상태 유지 | DONE | 회전 후 현재 곡/줌 상태 유효 |
| F-310 | 콘티 키/제목 순서 양방향 입력 허용 | DONE | `D 곡명`/`곡명 D` 모두 파싱 확인 |
| F-311 | 콘티 여러 줄 일괄 입력 지원 | DONE | 여러 줄 붙여넣기 후 다건 생성 확인 |

## 5) 메모(개인/공유)

| ID | 기능 | 상태 | 확인 방법 |
|---|---|---|---|
| F-401 | 개인 메모(비공개) 저장/조회 | DONE | 본인 계정에서만 보임 확인 |
| F-402 | 공유 메모(팀 공유) 저장/조회 | DONE | 팀원 계정에서 동일 메모 확인 |
| F-403 | 펜슬/드로잉 입력(태블릿) | DONE | LiveCue 악보보기 레이어 필기 후 저장/재로드 |

## 6) 안정성/보안/최적화

| ID | 항목 | 상태 | 확인 방법 |
|---|---|---|---|
| S-001 | Firestore permission-denied 재발 방지 | DONE | 팀/초대/프로젝트 로드 반복 테스트 |
| S-002 | Storage 업로드/조회 실패 처리 보강 | DONE | 실패 시 사용자 친화 메시지 + 재시도 |
| S-003 | CORS/토큰 URL 관련 로드 실패 방지 | DONE | Safari/Chrome 교차 테스트 |
| S-004 | 비로그인/권한없음 라우트 보호 | DONE | 직접 URL 접근 시 가드 동작 |
| S-005 | Firestore/Storage rules 최소권한 적용 | DONE | 규칙 리뷰 + 실제 접근 테스트 |
| S-006 | 불필요한 과다 구독/읽기 최적화 | DONE | 리스트/라이브 구독 범위 점검 |
| S-007 | `flutter analyze` 경고/에러 0 유지 | DONE | analyze 실행 결과 기록 |
| S-008 | `flutter test` 기본 회귀 통과 | DONE | test 실행 결과 기록 |

## 7) 배포 전 수동 점검

배포 전 아래 항목만 최종 `DONE`이면 배포 진행:
- F-001 ~ F-008
- F-101 ~ F-106
- F-201 ~ F-205
- F-301 ~ F-311
- F-401 ~ F-403
- S-001 ~ S-008

---

## 작업 규칙 (앞으로 이 문서 기준으로 진행)

1. 새 요청을 받으면 먼저 관련 ID를 `IN-PROGRESS`로 변경
2. 코드 수정 + 테스트 완료 시 `DONE`으로 변경
3. Firebase 콘솔에서만 가능한 항목은 `BLOCKED`로 표기 후 필요한 작업을 하단에 명시
4. 매 턴 종료 시 변경된 ID만 요약 보고


## 8) 코드 스캔 기준 상태표 (2026-02-18, UX/UI 튜닝 반영)

기준:
- `완료`: 코드 구현 + 자동검증(정적분석/테스트)까지 확인됨
- `부분완료`: 코드 구현됨, 실환경/다계정/실기기 검증이 남음
- `미완료`: 구현 부족 또는 외부 설정 없이는 실패 가능

완료

| ID | 항목 | 상태 판단 근거 |
|---|---|---|
| F-005 | 팀 초대(카카오 링크) 원탭 복사/공유 | 링크 준비 상태 + 복사/공유 fallback 코드 존재 |
| F-006 | 초대 링크로 진입 시 초대 대기/수락 동작 | `inviteTeam/inviteCode` 진입/수락 + 잘못된 docId 파라미터 방어 적용 |
| F-001 | 로그인 후 `내 팀` 목록 로드 | 사용자 전용 멤버십 미러(`users/{uid}/teamMemberships`) 우선 로드 적용 |
| F-002 | 팀 생성 후 F5/재로그인 시 팀 유지 | 팀 생성/초대 수락 시 멤버십 미러 동기화 및 재수집 경로 보강 |
| F-003 | 팀 홈에서 프로젝트 생성/재진입 유지 | 프로젝트 생성 즉시 해당 프로젝트로 이동하도록 동선 보강 |
| F-004 | 팀 초대(이메일) 생성/수락 | 수락 시점 초대 상태 재검증 + 역할/팀명 서버값 동기화 적용 |
| F-007 | 여러 팀 동시 소속 사용자 팀 전환 | 팀 홈 AppBar에 빠른 팀 전환 시트 추가 |
| F-008 | 기존 팀명 중복 생성 차단 + 안내 메시지 | `teamNameIndex/{normalizedName}` 예약 트랜잭션으로 중복 생성 차단 + 사용자 안내 |
| F-101 | 역할명 프론트 통일(팀장/인도자/팀원) | 역할 라벨 매핑을 전역 화면에서 팀장/인도자/팀원으로 일관 적용 |
| F-102 | 팀장 UI에서 팀원 역할 변경 가능 | 팀원 권한 관리 카드 + 역할 변경 액션 + 마지막 팀장 보호 로직 적용 |
| F-103 | 사용자 본인 역할 표시 | 팀 홈/프로젝트 상단에 현재 로그인 사용자 역할 표시 |
| F-104 | 운영자(`/admin`) 접근 제어 | `/admin` 진입 시 운영자 여부 비동기 확인 후 차단/허용 분기 |
| F-106 | 타 팀 URL 직접 접근 시 데이터 비노출 | 팀/프로젝트/악보보기/악보상세에서 멤버십 미존재 시 접근 차단 가드 적용 |
| F-105 | 일반 사용자의 전역 악보 수정/삭제 차단 | 라우트 가드 + 관리자 액션별 권한 재검증(Defense in Depth) 적용 |
| F-201 | 전역 곡 생성/조회/수정/삭제(CRUD) | 운영자 화면에서 생성/수정/삭제/목록 재조회 흐름 제공 |
| F-202 | 악보 업로드 성공(이미지/PDF) | 파일 타입/용량 검증 + 업로드 재시도 + 오류 메시지 표준화 적용 |
| F-203 | 악보 다운로드/열기 동작 | `새 탭 열기`/`다운로드`/`링크 복사` fallback 흐름 완성 |
| F-204 | 곡별 다중 키 버전 등록 | 악보 단위 `keyText` 편집 및 다중 키 자산 구조 유지 |
| F-205 | 키 선택/자동 필터링 악보 매칭 | enharmonic 동치키(`Db=C#`) 매칭 포함한 자동 선택 로직 적용 |
| F-206 | 관리자에서 악보 미리보기 기반 삭제 | 썸네일/미리보기 확인 후 개별 악보 삭제 동작 지원 |
| F-301 | setlist 입력 시 LiveCue 자동 반영 | 콘티 입력/수정/삭제 시 LiveCue 동기화(빈 콘티 초기화 포함) 적용 |
| F-302 | LiveCue 기본 화면 텍스트 setlist 중심 | 운영 화면을 라인 텍스트 중심(번호/제목/키)으로 구성 |
| F-303 | LiveCue 진입 시 첫 곡 자동 포커스 | current 미존재 시 첫 곡 자동 시드 + 상태 저장 적용 |
| F-304 | 좌/우 버튼 곡 전환 | 운영/악보보기 양쪽에서 좌우 이동 동작 통일 |
| F-305 | 키보드 화살표 곡 전환 | 캐시된 LiveCue 상태 기반으로 즉시 전환(추가 읽기 제거) 적용 |
| F-306 | 스와이프 곡 전환 | 수평 드래그 velocity 기반 곡 이동 처리 적용 |
| F-307 | 전체화면 악보 집중 표시 | 악보보기 오버레이 최소화/자동 숨김 + 탭으로 토글 적용 |
| F-308 | 확대/축소(핀치줌) 안정 동작 | `InteractiveViewer` + bytes 캐시 + 고해상도 렌더링 적용 |
| F-309 | 가로/세로 회전 후 상태 유지 | fullscreen 뷰어 `TransformationController`로 상태 유지 강화 |
| F-310 | 콘티 키/제목 순서 양방향 입력 허용 | `parseSongInput` + `cueLabel` 파서로 `D 곡명`/`곡명 D` 양방향 입력 처리 |
| F-311 | 콘티 여러 줄 일괄 입력 지원 | `segmentA`에 멀티라인 파서/배치 저장(`일괄 추가`) 경로 추가 |
| F-401 | 개인 메모 저장/조회 | `userProjectNotes`(사용자 전용 docId) 경로 분리/저장 적용 |
| F-402 | 공유 메모 저장/조회 | `projects/{projectId}/sharedNotes/main` 경로 분리/저장 적용 |
| F-403 | 펜슬/드로잉 입력 | LiveCue 전체화면 악보 위 레이어 필기(개인/공유) + 저장/복원 제공 |
| S-001 | Firestore permission-denied 재발 방지 | 멤버 쿼리 fallback(`userId`,`uid`) + 초대 수락 write 순차화 + malformed teamId 방어 |
| S-002 | Storage 업로드/조회 실패 처리 보강 | 업로드/조회 실패 fallback + 사용자 안내 메시지 표준화 적용 |
| S-003 | CORS/토큰 URL 관련 로드 실패 방지 | `storagePath` 기준 URL 재해석 + bytes 폴백 렌더링 적용 |
| S-004 | 비로그인/권한없음 라우트 보호 | 인증 리다이렉트 + 팀 멤버십 기반 화면 가드 적용 |
| S-005 | Firestore/Storage rules 최소권한 적용 | 전역 자산은 운영자만 쓰기 + 팀 스토리지는 팀장/운영자만 쓰기로 제한 |
| S-006 | 불필요한 과다 구독/읽기 최적화 | TeamHome/LiveCue 스트림·상태 캐시로 재구독/추가 읽기 최소화 |
| S-007 | `flutter analyze` 경고/에러 0 유지 | 최신 실행 결과 `No issues found` |
| S-008 | `flutter test` 기본 회귀 통과 | 최신 실행 결과 `All tests passed` |

부분완료

| ID | 항목 | 현재 상태 |
|---|---|---|
| - | - | 현재 코드 기준 부분완료 항목 없음 |

미완료

| ID | 항목 | 부족한 점 |
|---|---|---|
| - | - | 현재 코드 스캔 기준 미완료 항목 없음 (실환경 검증 필요 항목은 `부분완료`로 관리) |

### 9) 이번 턴 반영 요약 (2026-02-18)

- UI/UX 전면 튜닝: 팀/프로젝트, 팀 홈, 프로젝트 상세, 예배 전/적용찬양/LiveCue, 프로젝트 메모, 악보 라이브러리
- 정보 구조 재배치: 와이드 화면 2열 워크스페이스 구성
- 톤/위계 재정리: 공통 테마, 카드/입력/버튼/내비게이션 스타일 통일
- 체크리스트 갱신 규칙 적용: 본 문서 상태표를 매 턴 최신화

### 10) 이번 턴 반영 요약 (2026-02-18, 미완료 우선 해소)

- `S-003` 대응: 다운로드 URL 사용 우선순위를 `storagePath` 재해석 우선으로 변경 (`downloadUrl` stale/token 이슈 완화)
- LiveCue 전체화면 이미지 로드: `Image.network` 실패 시 `storage.getData` bytes 캐시 폴백 추가
- 관리자 악보 썸네일/미리보기: bytes 우선 렌더 + URL 폴백으로 CORS 민감도 완화
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 11) 이번 턴 반영 요약 (2026-02-18, 팀/권한 안정화 1차)

- 팀 멤버십 미러 경로 추가: `users/{uid}/teamMemberships/{teamId}` 읽기/동기화 로직 반영
- 팀 목록 조회 강화: `collectionGroup('members')`를 `userId` + `uid` 기준으로 모두 조회
- 초대 수락 안정화: 이메일/링크 수락 시 배치 대신 순차 write로 규칙 충돌 가능성 완화
- 팀 멤버 문서 호환성: `uid` 필드 병행 저장/백필 추가
- Firestore 규칙 보강: 멤버 식별(`userId|uid|email`) 허용 + 개인 멤버십 미러 규칙 추가
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 12) 이번 턴 반영 요약 (2026-02-18, 부분완료 해소 2차)

- `F-003` 대응: 프로젝트 생성 완료 시 즉시 해당 프로젝트 화면으로 이동하도록 개선
- `F-004` 대응: 이메일 초대 수락 시 초대 문서의 `pending` 상태/역할/팀명을 재검증해 stale 데이터 수락 방지
- `F-007` 대응: 팀 홈 상단에 `빠른 팀 전환` 액션 추가(다중 팀 소속 사용자용)
- 팀 목록 안정성 보강: `/teams` 규칙을 `list/get`로 분리해 query-safe 조건으로 조정
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 13) 이번 턴 반영 요약 (2026-02-18, 역할/접근 가드 3차)

- `F-101/F-102/F-103` 상태 확정: 역할 라벨 통일 + 팀장 역할 변경 UI + 내 역할 표시 동선 유지
- `F-104` 상태 확정: 운영자 전용 라우트(`/admin`) 접근 차단/허용 분기 유지 확인
- `F-106` 보강: 팀 홈/프로젝트/LiveCue 전체화면/악보상세에서 멤버십 미존재 계정 차단 가드 추가
- `S-004` 보강: 인증 리다이렉트 + 멤버십 가드로 직접 URL 접근 시 무권한 노출 최소화
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 14) 이번 턴 반영 요약 (2026-02-18, 악보 업로드 안정화 4차)

- `F-202/S-002` 보강: 전역 곡 생성/악보 업로드 액션에서 `globalAdminProvider.future`를 사용해 권한 로딩 타이밍 이슈 완화
- 운영자 아님/권한 확인 실패 시 안내 메시지 표준화: `globalAdmins/{uid}` 문서 확인 가이드 제공
- 적용 범위: 전역 악보 패널, 팀 곡 라이브러리, 곡 상세 업로드
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 15) 이번 턴 반영 요약 (2026-02-18, 읽기 최적화 5차)

- `S-006` 보강: `TeamHome` 화면에서 `members/projects` 쿼리를 단일 스트림 인스턴스로 재사용하도록 조정
- 기대 효과: 동일 화면 내 중복 구독으로 인한 Firestore 읽기량/리스너 수 감소
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 16) 이번 턴 반영 요약 (2026-02-18, 팀 로드/초대 파라미터 안정화 6차)

- `F-001/S-001` 보강: `teamMemberships`/초대 데이터에서 잘못된 Firestore docId(`''`, `.`, `..`, `/` 포함) 필터링 적용
- `F-006` 보강: 링크 초대 조회/수락 시 `teamId/inviteCode` 형식 검증 추가, 잘못된 링크는 즉시 안내
- 팀 전환 보강: 빠른 팀 전환 결과값도 docId 유효성 검증 후 라우팅
- 예외 내성 강화: 팀 목록 로드에서 `failed-precondition`, `invalid-argument`를 복구 가능한 빈 결과로 처리

### 17) 이번 턴 반영 요약 (2026-02-22, 팀 생성 무반응 체감 이슈 대응)

- `F-002/F-008/S-001` 보강: 팀 생성 버튼 무반응처럼 보이던 케이스를 UX/네트워크 양쪽에서 차단
- `팀 이름 공백 입력` 시 조용히 반환하지 않고 즉시 스낵바 안내(`팀 이름을 입력해 주세요.`)
- `_creating` 중복 진입 방지로 연속 탭 시 요청 중복 전송 차단
- 팀 생성 플로우 핵심 Firestore 호출(`중복 확인/이름 예약/팀 생성/멤버 생성/멤버십 미러`)에 timeout 적용
- 타임아웃 시 사용자 안내 메시지 추가(`네트워크 상태 확인 후 다시 시도`)
- 팀 이름 입력창 `onSubmitted`에서 엔터로도 생성 동작되도록 보강
- 정적분석 경고 1건 정리(`live_cue_page` 문자열 보간 불필요 중괄호 제거)
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 17) 이번 턴 반영 요약 (2026-02-19, 프로젝트 재진입 가시성 보강)

- 팀 홈 상단 액션에 `최근 프로젝트` 바로가기 버튼 추가 (`teams/{teamId}.lastProjectId` 기반)
- 프로젝트 목록이 비어 보일 때도 `최근 프로젝트 열기` 복구 동선 제공
- 팀 목록 중복 이름 배지 문구/분석 경고 정리(정적분석 `info` 2건 해소)
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 17) 이번 턴 반영 요약 (2026-02-18, 악보 열기/다운로드 동작 보강 7차)

- `F-203` 보강: `SongDetail` 액션을 `링크 복사`/`새 탭 열기`/`다운로드`로 분리
- 브라우저 유틸 보강: `downloadUrlInBrowser(url, fileName)` 공통 헬퍼 추가(web/stub 모두 반영)
- 다운로드 실패 fallback: 다운로드 불가 시 새 탭 열기, 그것도 실패하면 링크 복사로 자동 전환
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 18) 이번 턴 반영 요약 (2026-02-18, 관리자 쓰기 권한 방어 8차)

- `F-105/S-005` 보강: `GlobalAdminPage`의 전역 곡 생성/수정/삭제/업로드/마이그레이션 진입마다 운영자 권한 재확인 추가
- 목적: `/admin` 라우트 가드 우회/상태 불일치 상황에서도 쓰기 액션을 방어(Defense in Depth)

### 19) 이번 턴 반영 요약 (2026-02-19, LiveCue 악보 없음 보강)

- `F-301/F-307/S-003` 보강: LiveCue 악보 로더에서 `songId` 단일 의존을 제거하고, 제목 파생 후보(원문/파싱/번호 제거) + 동명 곡 후보를 순차 탐색하도록 개선
- 동명 곡이 여러 개인 경우에도 `자산(assets) 존재` + `키 매칭` 우선으로 실제 표시 가능한 악보를 선택
- 악보 상세 이동 동선 보강: LiveCue 내부 `악보 열기/악보 상세에서 열기` 버튼이 실제 로드된 악보의 `songId`를 사용하도록 수정
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과
- 배포 결과: `https://worshipflow-df2ce.web.app` 재배포 완료

### 19) 이번 턴 반영 요약 (2026-02-19, 사용자 표시명/닉네임 통일)

- 요청 반영: 화면에서 UID를 직접 표시하지 않고 이름/닉네임 우선 표시하도록 통일
- 팀 홈 프로젝트 목록의 인도자 표시에 UID fallback 제거 (`이름 확인 중` fallback 사용)
- 팀 선택 화면 닉네임 설정/프로필 동기화 흐름 기준으로 멤버 문서 backfill 안정화
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과
- 비동기 컨텍스트 경고 제거: `context.mounted` 점검을 추가해 `use_build_context_synchronously` 정적분석 이슈 해소
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 19) 이번 턴 반영 요약 (2026-02-18, 부분완료 해소 9차)

- `F-205` 보강: 키 매칭에 enharmonic 동치(`Db=C#`, `Gb=F#` 등) 적용
- `F-301` 보강: 콘티가 비면 LiveCue `current/next` 상태를 자동 초기화해 stale 곡 표시 방지

### 20) 이번 턴 반영 요약 (2026-02-18, 프로젝트 진행 동선/중복 생성 보강 10차)

- `F-008` 보강: 팀 생성 시 `teamNameIndex` 사전 조회 + 예약 실패 우회 제거로 중복 팀명 생성을 강제 차단
- `F-008` 안내 개선: 중복 확인 권한/인덱스 상태 불가 시 팀 생성을 중단하고 명확한 안내 메시지 제공
- `F-310/F-311` 보강: 콘티 파서가 복합 키(`Eb-E`, `Db/C#`) 패턴도 인식하도록 확장
- `F-401/F-402` UX 보강: 프로젝트 메모 영역을 하단 상시 노출에서 모달 진입 방식으로 변경해 콘티/LiveCue 진행 동선 간섭 제거
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과
- `F-309` 보강: LiveCue 전체화면에 `TransformationController` 적용해 화면 회전/리빌드 시 뷰어 상태 유지 강화
- `S-006` 보강: LiveCue/TeamHome에서 캐시된 스트림·상태 기반 전환으로 불필요한 Firestore 추가 읽기 제거
- `S-005` 보강: Storage 팀 경로 write 권한을 `팀장/운영자`로 최소화
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 20) 이번 턴 반영 요약 (2026-02-18, 5도권 참고표 UX 추가)

- 악보 추가 화면 입력 가이드에 `5도권 참고` 버튼 추가
  - `song_library_panel`, `global_song_panel`
- LiveCue 운영 모드 컨트롤(이전/다음/스와이프 안내) 옆에 `5도권 참고` 버튼 추가
  - `live_cue_page`
- 공통 UI 컴포넌트로 `CircleOfFifthsHelpButton`/`CircleOfFifthsGuideCard` 추가
  - 팝업에서 12키 5도권 도식 + 사용 안내(`+1/-1`, 동음이명) 제공
- 검증 결과: `flutter analyze` 통과

### 21) 이번 턴 반영 요약 (2026-02-18, 사용자 제공 5도권 이미지 연동)

- 사용자 제공 파일 `/Users/hwanghuichan/Downloads/개발/WorshipFlow/cord.jpg`를 앱 에셋으로 등록
  - `pubspec.yaml`에 `assets: - cord.jpg` 추가
- `CircleOfFifthsGuideCard`를 도식 렌더링에서 실제 이미지 표시 방식으로 전환
  - `InteractiveViewer`로 확대/축소(핀치) 지원
- 적용 화면은 동일 유지
  - 악보 추가 입력가이드 버튼
  - LiveCue 운영 모드 버튼

### 22) 이번 턴 반영 요약 (2026-02-18, 5도권 팝업 성능 최적화)

- `S-006` 최적화: 5도권 도움말 열기 전에 이미지 `precacheImage` 수행
  - 첫 진입 렌더 지연/깜빡임 감소
- `S-006` 최적화: 팝업 본문에 `SingleChildScrollView` 적용
  - 소형 화면/분할 화면에서 overflow 방지
- `S-006` 최적화: 이미지 뷰어를 `RepaintBoundary`로 분리
  - 상위 UI 변화 시 불필요한 재페인트 최소화
- 최신 자동검증: `flutter analyze` 통과, `flutter test` 통과

### 23) 이번 턴 반영 요약 (2026-02-18, 재배포 완료)

- Hosting 재배포 완료: `https://worshipflow-df2ce.web.app`
- 배포 직전 빌드: `flutter build web` 성공
- 반영 내용:
  - 5도권 참고 이미지(`cord.jpg`) 실연동
  - 5도권 팝업 최적화(precache + overflow 방지 + repaint 분리)
  - 체크리스트 최신 현황 스냅샷 갱신

### 24) 이번 턴 반영 요약 (2026-02-18, 유령 팀 자동 정리)

- 증상: `teams/{teamId}`를 삭제해도 `users/{uid}/teamMemberships/{teamId}` 미러가 남아 팀 목록에 유령 팀이 노출될 수 있음
- 대응 1 (`team_select_page`):
  - 팀 로드 시 팀 문서 미존재/권한없음/멤버십 불일치 팀은 목록에서 제거
  - 해당 팀의 사용자 미러 문서도 best-effort로 자동 삭제
- 대응 2 (`team_home_page` 팀 전환 목록):
  - 빠른 팀 전환 목록 구성 시 동일 검증/정리 로직 적용

### 25) 이번 턴 반영 요약 (2026-02-18, 프로젝트 재진입/입력 UX 안정화)

- `F-003` 보강: 팀 홈 프로젝트 스트림에서 `orderBy('date')` 의존 제거
  - Firestore에서 `date` 필드 누락 문서가 목록에서 제외되는 케이스를 방지
  - 클라이언트 정렬(`date` → `createdAt` → `id`)로 일관 표시
- `F-401/F-402` 보강: 프로젝트 메모 UI를 하단 상시 영역에서 모달 진입 방식으로 변경
  - 프로젝트 생성 직후 콘티/LiveCue 이동 동선 간섭 최소화
- `F-008` 보강: 팀명 중복 검사 우회 경로 제거 (검사 불가 시 생성 중단 + 안내)
- `F-310/F-311` 보강: 콘티 파서 복합 키(`Eb-E`, `Db/C#`) 입력 인식 확장
- 최신 자동검증: `flutter analyze` 통과, `flutter test` 통과
  - 존재하지 않거나 접근권한 없는 팀은 즉시 제외 + 미러 정리
- 기대 효과:
  - 콘솔에서 팀 삭제 후 새로고침 시 유령 팀 재노출 방지
  - 멤버십 미러 데이터가 점진적으로 자기 정리됨

### 25) 이번 턴 반영 요약 (2026-02-18, 악보 라이브러리 동선 단순화)

- 사용자 요청 반영: `악보 라이브러리` 탭에서 `팀 연결` UI 제거
- 라이브러리 탭은 전역 DB 관리 전용으로 정리:
  - 전역 악보 관리(`GlobalSongPanel`)만 노출
  - 팀/프로젝트 연결은 `팀/프로젝트` 탭에서 진행하도록 안내 카드 추가
  - `팀/프로젝트 탭으로 이동` 버튼 추가
- 제거된 혼란 요소:
  - 팀 선택 드롭다운
  - 선택 팀 상태 기반 팀 라이브러리 패널
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 26) 이번 턴 반영 요약 (2026-02-18, 팀 목록 수동 정리 + 팀장 팀 삭제)

- 메인(`팀/프로젝트`)의 `내 팀` 카드에 항목별 메뉴 추가
  - `목록에서 제거(유령 팀 정리)` 액션으로 `users/{uid}/teamMemberships/{teamId}` 미러를 즉시 삭제
- 팀 홈에서 `팀 정보를 찾을 수 없습니다` / `팀 접근 권한이 없습니다` 상태일 때
  - `내 목록에서 제거` 버튼으로 고아 팀 항목을 즉시 정리 가능
- 팀장(관리자) 전용 `팀 삭제` 기능 추가
  - 팀 홈 워크스페이스 카드에서 삭제 실행
  - 삭제 시 팀 하위 데이터(best-effort) 정리:
    - `invites`, `inviteLinks`, `songRefs`, `userProjectNotes`
    - `projects` 및 하위 `segmentA_setlist`, `segmentB_application`, `liveCue`, `sharedNotes`
    - `members` 및 각 사용자 `teamMemberships/{teamId}` 미러
  - 마지막에 `teams/{teamId}` 삭제 후 팀 목록으로 이동
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 27) 이번 턴 반영 요약 (2026-02-18, 프로젝트 삭제 기능 추가)

- 미반영 항목 해소: 팀 홈 프로젝트 카드에 `프로젝트 삭제` 액션 추가
  - 권한: 팀장 또는 해당 프로젝트 인도자
  - 삭제 전 확인 다이얼로그 제공
  - 삭제 진행 중 로딩 인디케이터 표시
- 삭제 시 프로젝트 하위 데이터 정리:
  - `segmentA_setlist`, `segmentB_application`, `liveCue`, `sharedNotes`
  - 이후 `projects/{projectId}` 문서 삭제
- 검증 결과: `flutter analyze` 통과, `flutter test` 통과

### 28) 이번 턴 반영 요약 (2026-02-18, 팀 생성 permission-denied 수정)

- 증상: 팀 생성 시 `[cloud_firestore/permission-denied]` 발생
- 원인: 팀/멤버/멤버십 미러를 batch로 동시에 작성하면서 rules가 부모 팀 문서를 아직 읽지 못하는 순서 의존 이슈
- 조치:
  - 팀 생성 write 순서를 `teams/{teamId}` 생성 -> `teams/{teamId}/members/{uid}` 생성 -> `users/{uid}/teamMemberships/{teamId}` 생성으로 변경
  - 배치 쓰기 제거 후 순차 write로 rules 평가 안정화
- 검증 결과:
  - `flutter analyze` 통과
  - `flutter test` 통과
  - Hosting 재배포 완료

### 29) 이번 턴 반영 요약 (2026-02-18, 팀명 중복/콘티 일괄 입력 보강)

- `F-008` 완료:
  - 팀 생성 시 `teamNameIndex/{normalizedName}` 예약 트랜잭션으로 중복 팀명 생성 차단
  - 중복 팀명 입력 시 즉시 안내: `이미 존재하는 팀 이름입니다. 팀장에게 초대를 요청해 주세요.`
  - 팀 생성 문서에 `nameKey` 저장, 팀 삭제 시 인덱스 문서 정리
- `F-310` 완료:
  - 콘티 입력 파서 개선: `1 D 곡명`, `1 곡명 D`, `1. D 곡명`, `1) D 곡명` 모두 허용
- `F-311` 완료:
  - 예배 전 탭에 `콘티 일괄 입력 (여러 줄)` 추가
  - 여러 줄 붙여넣기 후 `일괄 추가`로 다건 생성, 생성 즉시 LiveCue 동기화
  - 일괄 입력 후 곡별 메모/레퍼런스는 기존 `콘티 수정` 액션으로 후편집 가능
- UX 보강:
  - 프로젝트 메모 카드를 `프로젝트 메모 (선택)`으로 명확화
  - `메모 없이 다음 단계 진행 가능` 안내 문구 추가

### 30) 이번 턴 반영 요약 (2026-02-18, 이슈 재발 방지 스캔/패치)

- `F-008` 추가 보강:
  - 팀 생성 전 `teamNameIndex`가 존재할 때, 연결된 팀 문서가 이미 삭제된 stale 인덱스면 자동 정리 후 재시도
  - stale 정리 실패 시 중복 안내 메시지로 안전 중단(중복 팀명 우회 생성 방지)
- `S-001` 추가 보강:
  - 팀 홈 진입 시 `permission-denied/not-found/failed-precondition` 에러를 복구 가능한 상태로 처리
  - 즉시 `내 목록에서 제거` 액션 노출로 유령 팀 정리 동선 제공
- `F-003` UX 보강:
  - 프로젝트 상세 진입 시 권한/삭제 이슈(`permission-denied/not-found`)를 일반 오류 대신
    `팀 목록으로` 복귀 가능한 안내 카드로 처리
- 최신 자동검증: `flutter analyze` 통과, `flutter test` 통과

### 31) 이번 턴 반영 요약 (2026-02-18, 배포 전 최종 안정화/재배포)

- 웹 빌드 실패 1건 수정:
  - `TeamHome` 프로젝트 목록 정렬 시 제네릭 추론 오류(`List<dynamic>`)를
    `List<QueryDocumentSnapshot<Map<String, dynamic>>>` 명시로 수정
- 전체 검증 재실행:
  - `flutter analyze` 통과
  - `flutter test` 통과
  - `flutter build web` 성공
- 재배포 완료:
  - Hosting: `https://worshipflow-df2ce.web.app`
  - Firestore/Storage rules 최신 버전 유지 확인

### 32) 이번 턴 반영 요약 (2026-02-19, 프로젝트 중복 날짜 동선 개선)

- 증상:
  - 프로젝트 생성 팝업에서 같은 날짜 입력 시 `이미 있습니다`만 노출되어 사용자 입장에서는 다음 동선이 막힌 것처럼 보임
- 조치:
  - 같은 날짜 프로젝트가 이미 존재하면 생성 차단 메시지 대신 해당 프로젝트를 즉시 열도록 변경
  - 결과적으로 `생성` 버튼을 눌러도 기존 프로젝트로 자연스럽게 이동
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 33) 이번 턴 반영 요약 (2026-02-19, 중복 날짜 프로젝트 진입 수정 배포)

- 같은 날짜 프로젝트가 이미 있을 때 `생성 실패` 대신 기존 프로젝트로 즉시 이동하도록 동선 반영
- 웹 빌드/배포 재실행 완료
  - `flutter build web` 성공
  - `firebase deploy` 성공
  - Hosting: `https://worshipflow-df2ce.web.app`

### 34) 이번 턴 반영 요약 (2026-02-19, 팀 홈 프로젝트 목록 미표시 수정)

- 증상:
  - 팀 홈 상단 히어로만 보이고, 프로젝트/팀원/초대 섹션이 렌더되지 않는 현상
- 원인:
  - 스크롤 컨텍스트 내부 `Row`에서 `crossAxisAlignment: stretch` 사용으로 레이아웃 불안정
- 조치:
  - 팀 홈 메트릭 행의 정렬을 `CrossAxisAlignment.start`로 변경
  - 프로젝트/팀 요약/초대 섹션이 정상 렌더되도록 복구
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 35) 이번 턴 반영 요약 (2026-02-19, 프로젝트 목록 로딩 분리 + 재배포)

- 증상:
  - 프로젝트 카드에서 `팀원 정보 불러오는 중...` 상태가 길게 유지되며 목록이 보이지 않는 현상
- 원인:
  - 프로젝트 목록 렌더가 팀원 스트림 로딩 완료를 강하게 기다리는 구조
- 조치:
  - 프로젝트 목록 렌더를 팀원 스트림 로딩과 분리
  - 팀원 정보가 늦어도 프로젝트 목록은 즉시 표시, 인도자명만 점진적으로 보강
- 검증/배포:
  - `flutter analyze` 통과
  - `flutter test` 통과
  - `flutter build web` 성공
  - `firebase deploy` 성공 (`https://worshipflow-df2ce.web.app`)

### 36) 이번 턴 반영 요약 (2026-02-19, 악보 레이어 메모 전환 + 권한 보강)

- 메모 UX 전환:
  - 프로젝트 화면 `메모` 버튼을 팝업 편집기 대신 `악보보기(memo=1)` 진입으로 변경
  - LiveCue 전체화면에서 악보 위에 직접 필기 가능한 레이어 UI 추가
  - 개인/공유 레이어 표시 토글, 필기 모드 on/off, 색상/굵기 선택, 되돌리기/지우기/저장 동작 추가
- 권한 안정화:
  - `userProjectNotes` Firestore rules에 `get/list` 분리 규칙 적용
  - 문서 미존재 조회(`get`)와 legacy `ownerUserId` 미존재 데이터에 대한 읽기 호환성 보강
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 37) 이번 턴 반영 요약 (2026-02-19, 프로젝트/LiveCue 권한 복원 self-heal 보강)

- 코드리뷰 기반 리스크 수정:
  - 팀 생성자 계정의 `members/{uid}` 문서가 누락된 레거시 데이터에서
    프로젝트 상세/LiveCue 진입 시 권한 오류가 날 수 있는 경로 보강
- 조치:
  - `project_detail_page`의 컨텍스트 로드 시 생성자 + 멤버문서 누락이면 자동 복구
  - `live_cue_page`의 컨텍스트 로드 시 생성자 + 멤버문서 누락이면 자동 복구
  - 복구 시 `memberUids`도 함께 동기화해 이후 권한 체크 안정화
- 사용자 표시명 정책 확인:
  - 인도자 이름 로드 실패 시 UID 대신 `'이름 확인 중'` fallback 유지
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 38) 이번 턴 반영 요약 (2026-02-19, 전체 재검증 + 재배포)

- 실행:
  - `flutter analyze` 통과
  - `flutter test` 통과
  - `flutter build web` 성공
  - `firebase deploy` 성공 (Firestore/Storage rules + Hosting 반영)
- 배포 URL:
  - `https://worshipflow-df2ce.web.app`

### 39) 이번 턴 반영 요약 (2026-02-19, LiveCue 메모 지우개 + 점 필기 보존)

- 요청 반영:
  - LiveCue 전체화면 메모에 `지우개 모드` 추가 (펜/지우개 토글)
  - 드래그/탭 지우기로 획 단위 삭제 지원
  - 단일 탭으로 찍은 점 필기(1포인트 stroke)도 저장/복원/렌더링되도록 수정
- 기술 변경:
  - `live_cue_page` 드로잉 제스처를 펜/지우개 모드로 분기
  - 지우개 히트테스트(점/선분 거리 기반) 추가
  - 스케치 페인터에 단일 포인트 원형 렌더링 추가
  - 스케치 디코더에서 1포인트 stroke 허용
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 40) 이번 턴 반영 요약 (2026-02-19, 악보 업로드 가시성 + LiveCue 미리보기 보강)

- 전역 악보 관리 화면 개선:
  - 곡 행에서 `악보 목록` 버튼 추가 (업로드된 파일 실제 목록 확인 가능)
  - 바텀시트에서 파일명/키/타입 확인 + `링크 복사/새 탭 열기/다운로드` 제공
  - 운영자는 동일 시트에서 즉시 `악보 업로드` 가능
- LiveCue 미리보기 보강:
  - `Image.network`의 Web HTML 전략을 `never` → `prefer`로 변경해 브라우저 CORS 환경 대응력 강화
  - 이미지 렌더 실패 시 `악보 상세에서 열기` fallback 버튼 추가
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 41) 이번 턴 반영 요약 (2026-02-19, 팀 삭제 permission-denied 수정)

- 증상:
  - 팀장 계정에서 `팀 삭제` 실행 시 `[cloud_firestore/permission-denied]`로 중단되는 사례 발생
- 원인:
  - 팀 삭제 루틴이 `teams/{teamId}/userProjectNotes` 전체를 조회/삭제하려고 시도
  - 개인 메모 규칙은 기본적으로 본인 중심이라 정리 단계에서 권한 충돌 가능
- 조치:
  - 팀 삭제 루틴을 변경해 `프로젝트 x 팀원` 조합의 deterministic 개인 메모 문서 ID(v2/legacy)를 직접 정리
  - 개인 메모 정리 실패가 있어도 팀 삭제 전체가 중단되지 않도록 cleanup 단계를 분리
  - Firestore 규칙에 `userProjectNotes delete`의 팀장 예외(`isTeamAdmin(teamId)`)를 추가해 정리 안정화
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 42) 이번 턴 반영 요약 (2026-02-19, 프로젝트 인도자 '이름 확인 중' 고착 완화)

- 증상:
  - 프로젝트 목록에서 인도자명이 장시간 `이름 확인 중`으로 남는 현상 보고
- 조치:
  - 팀 홈에서 재사용하던 멤버/프로젝트 스트림을 `asBroadcastStream()`으로 전환해 다중 구독 안정화
  - 프로젝트 생성/인도자 변경 시 `leaderDisplayName`, `leaderNickname`을 프로젝트 문서에 함께 저장
  - 프로젝트 목록 렌더에서 멤버 매핑 실패 시에도 `leaderNickname/leaderDisplayName`을 우선 fallback 표시
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 43) 이번 턴 반영 요약 (2026-02-19, 동일 키 악보 버전 관리 UX 보강)

- 요청:
  - 같은 키의 악보가 여러 개일 때 버전을 구분할 수 있도록 이름 수정 및 삭제 기능 필요
- 조치:
  - `SongDetailPage` 악보 목록에 운영자 전용 `표시명 수정` 액션 추가
  - 표시명(`displayName`)이 있으면 목록 제목에 우선 노출하고, 원본 파일명은 상세 정보에 유지
  - 운영자 전용 `삭제` 액션 추가 (스토리지 파일 + Firestore assets 문서 동시 정리)
  - 삭제 시 스토리지 파일이 이미 없는 경우(`object-not-found`)도 안전하게 처리
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 44) 이번 턴 반영 요약 (2026-02-19, LiveCue 필기 깜빡임/선 누락 보강)

- 증상:
  - 악보 위 필기 시 화면이 깜빡이고 점만 찍히거나 선이 끊기는 제보
- 조치:
  - 필기 업데이트 시 전체 뷰어 `setState`를 매 프레임 호출하지 않도록 리페인트 분리
  - `ValueNotifier` 기반 stroke 리비전 카운터를 추가해 `CustomPaint`만 재렌더링
  - fullscreen 이미지 렌더에서 `webHtmlElementStrategy`를 `never`로 고정해 HTML 엘리먼트 경로로 인한 필기 간섭 완화
  - 지우개/펜 전환 및 획 저장 흐름에서 리페인트 타이밍 동기화
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 45) 이번 턴 반영 요약 (2026-02-19, LiveCue 악보 로드 실패 재발 방지)

- 증상:
  - LiveCue에서 `미리보기 로드 실패`가 반복되어 실사용이 어려운 상태
- 조치:
  - LiveCue 자산 선택 시 `storagePath` 기반 실제 바이트 로드 검증에 성공한 이미지 자산만 채택
  - 깨진/권한불가/삭제된 이미지 자산은 자동으로 건너뛰고 다음 후보 자산으로 fallback
  - fullscreen 렌더에서 중첩 `FutureBuilder(getData)` 제거, 사전 검증된 바이트를 즉시 렌더하도록 단순화
  - 사용자 문구를 `미리보기`에서 `악보` 기준으로 정리 (`악보 로드 실패`)
- 기대 효과:
  - 상단 후보 1개가 깨져 있어도 다음 정상 악보로 자동 연결
  - 반복 실패 UI 노출 빈도 감소
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 46) 이번 턴 반영 요약 (2026-02-21, 최근 프로젝트/팀 삭제/무한 로딩 안정화)

- 증상:
  - 팀 홈에서 `최근 프로젝트` 진입 시 `프로젝트를 찾을 수 없습니다` 화면으로 떨어지는 사례
  - 프로젝트/팀원 패널이 장시간 `불러오는 중` 상태로 고정되는 사례
  - 팀 삭제 시 `[cloud_firestore/permission-denied]`로 중단되는 사례
- 조치:
  - `TeamHome`의 멤버/프로젝트 스트림 캐시(`asBroadcastStream`) 공유를 제거하고, 쿼리 스트림을 직접 구독하도록 변경
  - 멤버/프로젝트 스트림에 timeout 에러를 추가해 무한 로딩 대신 오류 카드로 즉시 전환
  - `최근 프로젝트` 버튼 클릭 시 프로젝트 존재 여부를 먼저 검증하고, 유실 시 최신 프로젝트로 자동 복구/`lastProjectId` 정정
  - 팀 삭제 루틴을 단계별 안전 정리(`safeCleanup`)로 변경해 일부 정리 권한 실패가 전체 삭제를 막지 않도록 보강
  - Firestore 규칙에서 팀 삭제 권한을 `isTeamAdmin(teamId) || isTeamCreator(teamId)`로 확장
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 47) 이번 턴 반영 요약 (2026-02-21, 팀 홈 로더 고착/팀 삭제 권한 재보강)

- 증상:
  - 팀 홈에서 프로젝트/팀원 로딩 카드가 장시간 `불러오는 중`으로 유지되는 사례
  - 팀 삭제 버튼 실행 시 `permission-denied`로 실패하는 사례
- 조치:
  - 팀 홈에서 `membersStream/projectsStream` 단일 객체 공유를 제거하고 각 섹션이 개별 스트림을 직접 구독하도록 변경
  - 팀 삭제 순서를 조정해 `members` 하위 컬렉션 삭제를 `teamRef.delete()` 이후로 이동
    - (삭제 전에 멤버 문서를 먼저 지워 `isTeamAdmin()` 판정이 사라지던 케이스 방지)
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 48) 이번 턴 반영 요약 (2026-02-21, LiveCue 검은 화면 폴백 보강)

- 증상:
  - LiveCue 악보보기에서 로드 실패 메시지 없이 검은 화면만 노출되는 사례
- 조치:
  - `Image.memory` 디코딩 실패 시 즉시 `Image.network`로 재시도하는 폴백 추가
  - 메모리/네트워크 경로 모두 실패할 때 공통 오류 UI(악보 상세 진입 버튼 포함) 노출하도록 정리
- 검증:
  - `flutter analyze` 통과
  - `flutter test` 통과

### 49) 이번 턴 반영 요약 (2026-02-21, 재배포/규칙 재게시)

- 배포:
  - Hosting 재배포 완료 (`https://worshipflow-df2ce.web.app`)
  - Firestore rules 재게시 완료
  - Storage rules 재게시 완료
- 목적:
  - 팀 삭제 `permission-denied`와 팀/프로젝트 로딩 권한 불일치가 코드-룰 간 버전 차이로 재발하지 않도록 동기화

### 50) 이번 턴 반영 요약 (2026-02-21, 알파테스트 패치 1차)

- 조치(코드):
  - `LiveCue` 악보 캐시 정책 수정: `null`/오류 결과를 캐시에 고정하지 않도록 변경
  - `LiveCue` 악보 없음 화면에 `다시 불러오기` 액션 추가(업로드 직후 재시도 가능)
  - `LiveCue` 이미지 렌더링 `webHtmlElementStrategy: never`로 통일(사파리 검은 화면/필기 간섭 완화)
  - 팀 홈 `members/projects` 스트림을 metadata 포함 구독으로 조정하고, 무한 스피너 대신 동기화 안내+수동 새로고침 동선으로 변경
  - 팀원/프로젝트 섹션에서 로딩 고착 시 비차단 상태카드로 전환
- 조치(룰):
  - `isTeamAdmin`을 레거시 관리자 role(`admin/owner/team_admin/팀장`) 호환으로 보강
  - `teams/{teamId}/members`의 `list/get` 규칙을 `hasMemberDoc(teamId)` 기반으로 안정화
- 조치(아이콘):
  - `/web/favicon.png`, `/web/icons/*`를 `음표.png` 기준으로 재생성
  - `index.html`/`manifest.json` 앱 메타(이름/설명/아이콘 URL 버전쿼리) 정리
- 검증:
  - `flutter analyze` 통과 (No issues found)
  - `flutter test` 통과 (All tests passed)
  - `flutter build web` 통과
  - `firebase deploy` 완료 (Firestore/Storage rules + Hosting)

### 51) 이번 턴 반영 요약 (2026-03-01, 알파테스트 패치 2차)

- 상태 갱신:
  - `S-001` Firestore 권한 안정화: `DONE` 유지 (멤버십 미러 기반 팀 멤버/팀장 판정 보강)
  - `S-003` LiveCue 악보 로드 안정화: `DONE` 유지 (웹 이미지 렌더 경로/폴백 보강)
  - `F-003` 프로젝트 재진입 복구: `DONE` 유지 (프로젝트 유실 시 최신 프로젝트 폴백 동선 추가)
  - `F-007` 팀 전환/팀 홈 로드 안정화: `DONE` 유지 (주요 조회 타임아웃 보강)
- 조치(코드):
  - `LiveCue` 웹에서 이미지 바이트 직접 로드 경로를 비활성화하고 URL 렌더 + 로딩 인디케이터로 통일
  - `LiveCue` 로드 실패 UI에 `파일 직접 열기` 폴백 추가
  - `TeamHome`/`TeamSelect` 주요 Firestore 조회에 timeout 추가로 무한 대기 가능성 축소
  - `ProjectDetail`에서 프로젝트 미존재 시 최신 프로젝트로 이동 가능한 복구 액션 추가
  - 웹 아이콘을 `음표.png` 기반으로 재생성(`favicon`, `Icon-192/512`, maskable)
- 조치(룰):
  - `firestore.rules`: `users/{uid}/teamMemberships/{teamId}` 미러를 팀 멤버/팀장 판정 보조 경로로 반영
  - `storage.rules`: 동일 보조 판정 경로 반영
- 검증:
  - `flutter analyze` 통과 (No issues found)
  - `flutter test` 통과 (All tests passed)
  - `flutter build web` 통과
  - `firebase deploy --only hosting,firestore:rules,storage` 완료

### 52) 이번 턴 반영 요약 (2026-03-03, 계획 실행 Phase 1/2 착수)

- 조치(인프라/프로세스):
  - GitHub Actions 워크플로우 추가
    - `ci.yml` (analyze + test --coverage + coverage gate + web build)
    - `deploy_staging.yml` (preflight + staging deploy)
    - `deploy_prod.yml` (release_ref 기반 preflight + production deploy)
  - PR 템플릿/코드오너 파일 추가
    - `.github/pull_request_template.md`
    - `.github/CODEOWNERS`
- 조치(문서화):
  - `docs/release_runbook.md` 추가 (릴리즈/롤백 표준 절차)
  - `docs/web_cache_strategy.md` 추가 (서비스 워커/캐시 정책 재평가 기준)
  - `docs/test_strategy.md` 추가 (자가 복구 회귀 테스트 시나리오 포함)
  - `plan.md` 체크리스트 진행 상태 부분 갱신
- 조치(코드 품질/테스트):
  - 공통 Firestore docId 검증 유틸 추가: `lib/utils/firestore_id.dart`
  - 팀 화면 중복 검증 함수 공통 유틸로 치환
  - 단위 테스트 추가:
    - `test/unit/song_parser_test.dart`
    - `test/unit/storage_helpers_test.dart`
    - `test/unit/team_name_test.dart`
    - `test/unit/user_display_name_test.dart`
    - `test/unit/firestore_id_test.dart`
  - 커버리지 게이트 스크립트 추가: `scripts/ci/check_coverage.sh`
- 검증:
  - `flutter analyze` 통과 (No issues found)
  - `flutter test` 통과 (All tests passed)
  - `flutter test --coverage` 통과
  - `scripts/ci/check_coverage.sh` 통과 (57.87% >= 35%)
  - `flutter build web --release` 통과
