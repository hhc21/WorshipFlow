# WorshipFlow 코드베이스 리서치 보고서

작성일: 2026-03-02
분석 대상 경로: `/Users/hwanghuichan/Downloads/개발/WorshipFlow`

## 1. 분석 목적/범위
이 문서는 현재 코드베이스를 **구현 변경 없이** 깊이 읽고, 아래를 파악한 결과를 정리한다.
- 실제 런타임 동작 방식
- 화면/기능별 데이터 흐름
- Firestore/Storage 데이터 모델
- Firebase Rules 기반 권한 모델
- 장애/오류 발생 시 복구 로직
- 구조적 리스크와 후속 점검 포인트

제외 범위:
- 기능 추가/버그 수정 구현
- 배포 작업
- 외부 콘솔(Firebase Console) 상태 확인

---

## 2. 프로젝트 개요

### 2.1 기술 스택
- Flutter Web (Dart 3.10)
- 상태관리: `flutter_riverpod`
- 라우팅: `go_router`
- Firebase:
  - Auth (Google)
  - Firestore
  - Storage
  - Hosting
- 보조: `http` (관리자 마이그레이션에서 원격 파일 GET)

핵심 정의 파일:
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/pubspec.yaml`
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/main.dart`
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/app/router.dart`
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/firestore.rules`
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/storage.rules`

### 2.2 앱 초기화
`main.dart`에서:
1. `Firebase.initializeApp(DefaultFirebaseOptions.currentPlatform)`
2. Firestore Web 설정:
   - `persistenceEnabled: true`
   - `webExperimentalAutoDetectLongPolling: true`
   - long-poll timeout 25초
3. `ProviderScope`로 앱 실행

의도:
- Safari/네트워크 환경에서 websocket 이슈를 long polling fallback으로 완화
- 오프라인/캐시 내성 강화

### 2.3 라우팅/인증 게이트
`router.dart` 핵심:
- 비로그인 시 `/sign-in`으로 리다이렉트
- 로그인 후 `/sign-in` 접근 시 `redirect` 쿼리 안전검증 후 복귀
- 안전검증: `/_isSafeRedirectPath`
  - 외부 스킴/authority 차단
  - `//` path 차단

주요 라우트:
- `/sign-in`
- `/admin`
- `/teams`
- `/teams/:teamId`
- `/teams/:teamId/projects/:projectId`
- `/teams/:teamId/projects/:projectId/live`
- `/teams/:teamId/songs/:songId`

---

## 3. UI/테마 구조

### 3.1 공통 테마
`theme.dart`:
- Seed color `#0E4E87`
- 밝은 톤 기반 Material3
- 폰트 fallback에 한글 우선 폰트 포함
- 카드/입력/버튼/내비게이션 스타일 통일

### 3.2 공통 컴포넌트
`ui_components.dart`:
- `AppContentFrame`: 배경 그라디언트/원형 패턴 + max width 레이아웃
- `AppHeroPanel`: 상단 그라디언트 히어로
- `AppSectionCard`: 섹션 헤더+본문 카드
- `AppStateCard`, `AppLoadingState`: 상태 UI 표준화
- `CircleOfFifthsHelpButton` + `CircleOfFifthsGuideCard`
  - `cord.jpg`(5도권 이미지) 다이얼로그/줌 표시

---

## 4. 데이터 모델(실사용 관점)

### 4.1 최상위 컬렉션
- `globalAdmins/{uid}`: 운영자 권한 소스
- `songs/{songId}`: 전역 곡
  - `songs/{songId}/assets/{assetId}`: 악보 파일 메타
- `teams/{teamId}`: 팀 문서
  - `members/{uid}`
  - `invites/{email}`
  - `inviteLinks/{inviteLinkId}`
  - `songRefs/{songId}`
  - `projects/{projectId}`
    - `segmentA_setlist/{itemId}`
    - `segmentB_application/{itemId}`
    - `liveCue/state`
    - `sharedNotes/main`
  - `userProjectNotes/{noteId}` (v2 docId 규약 사용)
  - `userSongNotes/{noteId}`
- `teamNameIndex/{normalizedName}`: 팀 이름 중복 방지 인덱스
- `users/{uid}/teamMemberships/{teamId}`: 멤버십 미러(클라이언트 조회 최적화 및 복구 축)

### 4.2 팀/프로젝트 ID 규칙
- 팀: Firestore auto id
- 프로젝트: 예배 날짜 문자열을 doc id로 사용(예: `2026.02.20`)
  - 동일 날짜 중복 생성 시 새로 만들지 않고 기존 프로젝트 재진입 처리

### 4.3 개인 메모 doc id 규약
- v2: `v2__{projectId}__{userId}`
- legacy fallback: `{projectId}__{userId}` 및 query fallback
- 읽기 시 v2 우선, legacy 발견 시 v2로 best-effort 마이그레이션

---

## 5. 권한 모델(Rules + 클라이언트)

### 5.1 Firestore rules 요약
핵심 함수:
- `isTeamMember(teamId)`:
  - `teams/{teamId}.memberUids` 포함
  - `teams/{teamId}/members/{uid}` 존재
  - `users/{uid}/teamMemberships/{teamId}` 존재
  - creator 여부
- `isTeamAdmin(teamId)`:
  - creator 또는 admin role
- `canWriteLiveCue(teamId, projectId)`:
  - 프로젝트 인도자 또는 팀장

주요 정책:
- 전역 songs read: 로그인 사용자
- 전역 songs write: global admin
- team create: 생성자/이름/memberUids 검증
- team update:
  - 팀장 일반 수정
  - 멤버 본인의 `memberUids` self-heal 허용 경로 별도
- team delete: 팀장 또는 creator
- members:
  - create는 초대 상태 또는 creator self-heal 조건
  - update는 팀장 권한, 또는 본인 nickname/displayName 업데이트만 허용
- invites/inviteLinks:
  - 팀장 생성/관리
  - 본인 이메일 초대 수락 허용
- projects/segment/liveCue/sharedNotes:
  - 읽기: 팀멤버
  - 쓰기: 역할 조건 분기

### 5.2 Storage rules 요약
- `songs/**`:
  - read: 로그인
  - write: global admin + 용량<25MB + 이미지/PDF
- `teams/{teamId}/**`:
  - read: team member 또는 global admin
  - write: team admin 또는 global admin + 용량/타입 제한

### 5.3 클라이언트 권한 방어
화면 단에서도 운영자/팀장/인도자 체크를 수행해 UX 차단을 제공
(최종 보안은 rules가 담당)

---

## 6. 인증/프로필/닉네임 흐름

### 6.1 로그인
`sign_in_page.dart`:
- 기본: `signInWithPopup(GoogleAuthProvider())`
- popup blocked류 예외 시 `signInWithRedirect` fallback

### 6.2 사용자 프로필 동기화
`team_select_page.dart`:
- 로그인 후 `users/{uid}`에 nickname/displayName/email 업데이트(best-effort)
- 닉네임 설정 다이얼로그 제공
- 닉네임 변경 시 `collectionGroup('members')` 대상 userId/uid 기반으로 member doc nickname도 전파(best-effort)

### 6.3 UID 비노출 정책
`user_display_name.dart`:
- UI는 nickname → displayName → email → fallback 순
- raw uid는 표시하지 않도록 설계

---

## 7. 팀 선택 화면 동작 상세
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/teams/team_select_page.dart`

### 7.1 데이터 로딩 캐시
- `_fetchTeamsCached(uid)`
- `_fetchInvitesCached(email)`

### 7.2 팀 생성
핵심 특징:
- 이름 정규화(`normalizeTeamName`) + 길이 제한(<=40)
- `teamNameIndex` 트랜잭션 예약으로 중복 차단
- stale index(팀 문서 없는 인덱스) 감지 시 정리 후 재시도
- 팀 생성 순서:
  1. 팀 문서 생성
  2. `members/{uid}` admin 생성
  3. `users/{uid}/teamMemberships/{teamId}` 미러 생성
- 실패 시 인덱스 롤백(best-effort)

### 7.3 팀 목록 조회/복구
`_fetchTeams`:
- 1차: `users/{uid}/teamMemberships`
- 2차: `teams.where(memberUids arrayContains uid)` + `createdBy==uid`
- 3차 legacy fallback: `collectionGroup('members')` by `userId/uid/email`
- 이후 각 teamId에 대해:
  - 팀 문서 존재 검증
  - 멤버십 유효성 검증(member doc, creator, memberUids)
  - memberUids self-heal
  - creator admin member doc self-heal
  - membership mirror upsert
  - 유효하지 않은 항목은 mirror 삭제

### 7.4 초대 수락
- 이메일 초대(`invites/{email}`) 수락
  - pending 상태 재확인
  - member doc + membership mirror + memberUids 반영
  - invite status accepted 업데이트
- 링크 초대(`inviteLinks/{inviteCode}`) 수락
  - active 상태 재확인
  - member doc + membership mirror + memberUids 반영

### 7.5 탭 구조
- 탭1: 팀/프로젝트
- 탭2: 악보 라이브러리(전역 관리 안내 + `GlobalSongPanel`)

---

## 8. 팀 홈 화면 동작 상세
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/teams/team_home_page.dart`

### 8.1 컨텍스트 로드/자가복구
- team + member 동시 확인
- creator인데 member doc 누락 시 admin member self-heal

### 8.2 프로젝트 목록/최근 프로젝트
- 프로젝트 리스트 Future 로드
- 정렬: date desc + createdAt desc
- `lastProjectId` 우선 진입 버튼 제공
- lastProjectId 무효 시 fallback으로 최신 프로젝트 재설정

### 8.3 역할 관리
- 팀장만 변경 가능
- 마지막 팀장 강등 차단
- `members/{uid}.role` + `users/{uid}/teamMemberships/{teamId}.role` 동시 업데이트

### 8.4 팀 전환
- 내 팀 목록 로드 후 BottomSheet로 전환

### 8.5 팀 삭제
`_confirmAndDeleteTeam`:
- 다단계 정리:
  - 멤버십 미러
  - invites/inviteLinks/songRefs
  - userProjectNotes(v2/legacy 규약 모두)
  - 프로젝트 하위 컬렉션(segment/live/shared)
  - projects
  - teamNameIndex
  - team doc
  - members(마지막)
- 일부 정리 실패(permission-denied 등)는 partial cleanup 안내

### 8.6 프로젝트 삭제
- segmentA/segmentB/liveCue/sharedNotes 삭제 후 project doc 삭제

### 8.7 팀 정보 불일치 UX
- permission-denied/not-found일 때
  - “내 목록에서 제거” 액션 제공
  - `users/{uid}/teamMemberships/{teamId}` 정리 유도

---

## 9. 프로젝트 상세/세그먼트 동작

### 9.1 프로젝트 상세
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/projects/project_detail_page.dart`
- team member 검증 + creator self-heal
- 상단 액션: 팀 홈/악보보기/메모 레이어
- 탭:
  - 예배 전(`SegmentAPage`)
  - 적용찬양(`SegmentBPage`)
  - LiveCue(`LiveCuePage`)

### 9.2 Segment A (예배 전)
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/projects/segment_a_page.dart`

기능:
- 말씀 본문 저장(`scriptureText`)
- 단건 콘티 입력
- 다건(여러 줄) 일괄 입력
- 콘티 수정/삭제
- 메모/레퍼런스 링크

파싱 포인트:
- `1 D 곡명`, `1 곡명 D`, `1-2 Db 곡명` 등 cue label 분리
- 곡 자동매칭: searchTokens + title exact fallback

LiveCue 동기화:
- setlist 변경 시 `_syncLiveCueFromSetlist`
- current/next 자동 시드/보정

### 9.3 Segment B (적용찬양)
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/projects/segment_b_page.dart`
- 단건 입력 기반 목록 관리
- song candidate 다중 시 선택 다이얼로그
- 곡 상세로 이동 가능

---

## 10. LiveCue 동작 상세
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/projects/live_cue_page.dart`

### 10.1 공통 헬퍼
- cue 필드 생성/초기화
- setlist 기반 current/next 계산
- preview 후보 songId 계산(songId + title fallback)
- asset key 기반 필터링(`isAssetKeyMatch`)

### 10.2 LiveCue 운영 모드(`LiveCuePage`)
- setlist 스트림 + liveCue state 스트림 결합
- 현재/다음 표시
- 이전/다음 버튼, 키보드(←/→, A/D), 스와이프 전환
- 키 선택(가능 키 목록 로드)
- current가 비어있으면 setlist로 자동 seed

### 10.3 악보보기 전체화면(`LiveCueFullScreenPage`)
- 검은 배경 immersive UI
- `InteractiveViewer`로 확대/축소
- overlay 자동 숨김/토글
- image asset:
  - 우선 bytes(`getData`) 시도
  - fallback `Image.network`
- non-image(PDF 등): 새 탭/직접 열기 제공
- preview cache:
  - null 결과는 캐시 고정하지 않음(새 업로드 반영 위해)

### 10.4 필기 레이어
- 개인 레이어 + 공유 레이어 분리
- 펜/지우개 모드
- dot stroke(탭) + drag stroke
- undo/clear/save
- 저장 경로:
  - 개인: `teams/{teamId}/userProjectNotes/v2__{projectId}__{uid}`
  - 공유: `teams/{teamId}/projects/{projectId}/sharedNotes/main`
- legacy note fallback read + v2 migration

---

## 11. 악보/곡 관리 동작

### 11.1 전역 악보 패널
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/songs/global_song_panel.dart`
- 전역 곡 검색/생성
- 전역 곡별 asset 업로드
- asset 목록 바텀시트: 링크복사/새탭/다운로드
- 관리자 여부는 `globalAdminProvider`로 제어

특징:
- 파일 선택: `pickFileForUpload`
- content-type 추론 + 25MB 제한 검증
- storage path: `songs/{songId}/{safeName}_{timestamp}.{ext}`
- filename에서 key 자동 추출

### 11.2 팀 곡 라이브러리
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/songs/song_library_panel.dart`
- 팀 연결곡: `songRefs` 표시
- 전역곡 검색 후 팀에 추가(`songRefs/{songId}`)
- 운영자는 여기서 전역 곡 생성/악보업로드도 가능

### 11.3 곡 상세
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/songs/song_detail_page.dart`
- 팀 멤버 접근 확인 후 표시
- key 파라미터가 있으면 해당 key asset 우선 필터링
- 운영자 기능:
  - 악보 업로드
  - 표시명 수정
  - 악보 삭제(storage 파일 + firestore 메타)
- 개인 곡 메모: `teams/{teamId}/userSongNotes`

### 11.4 운영자 페이지
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/features/admin/global_admin_page.dart`
- `/admin` 라우트 보호 후 접근
- 팀별 legacy songs -> global songs 마이그레이션 도구
- 전역 곡 CRUD/악보 관리
- 악보 썸네일 bytes 우선 + URL fallback
- 악보 키 수정/삭제/미리보기

---

## 12. 유틸리티 로직

### 12.1 키/곡 파싱
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/utils/song_parser.dart`
- `parseSongInput`
  - prefix key / suffix key 양방향 파싱
- `canonicalKeyText`
  - enharmonic 동치 처리(Db=C#, Gb=F# 등)
- `extractKeyFromFilename`
  - 파일명에서 key 추출
- `isAssetKeyMatch`
  - asset 메타/파일명 key와 요청 key 비교
- `transposeKey`
  - 반음 기준 이조

### 12.2 Storage helper
파일: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/utils/storage_helpers.dart`
- 허용 타입 판정(PDF/이미지)
- 에러 메시지 표준화(permission/cors/quota 등)
- retry(backoff)
- `resolveAssetDownloadUrl`
  - storagePath 우선
  - 실패 시 stored downloadUrl fallback

### 12.3 브라우저 helper
파일:
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/utils/browser_helpers.dart`
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/utils/browser_helpers_web.dart`
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/lib/utils/browser_helpers_stub.dart`

기능:
- clipboard write
- Web Share API
- 파일 업로드 input
- 새탭 열기 / 다운로드
- blank popup 핸들

---

## 13. 웹/배포 구성

### 13.1 Hosting
`firebase.json`:
- hosting public: `build/web`
- SPA rewrite: `** -> /index.html`

### 13.2 index.html 전략
- custom splash
- 서비스워커 등록 해제 + 1회 reload 로직
  - 목적: 구버전 번들 캐시 문제 감소
  - 부작용: PWA 오프라인 이점 약화

### 13.3 manifest/icon
- `web/manifest.json`에 PWA 메타
- 아이콘은 `web/icons/*` 사용

---

## 14. 오류 내성/복구 설계 포인트

1) 멤버십 복구 다중축
- team doc `memberUids`
- members subcollection
- users teamMemberships mirror

2) creator self-heal
- 팀/프로젝트/LiveCue 진입 시 creator member doc 누락 복구

3) stale reference 정리
- 존재하지 않는 teamId/projectId 감지 시 mirror 정리/안내

4) storage URL 복구
- storagePath 재해석 우선
- 실패 시 legacy downloadUrl fallback

5) null preview 캐시 금지
- 업로드 직후 재시도 시 정상 반영

6) timeout 처리
- 주요 Firestore read/write에 timeout 적용한 경로 다수

---

## 15. 현재 구조에서 확인된 리스크/기술부채

### 15.1 테스트 커버리지 부족
- `test/widget_test.dart`는 placeholder 단일 테스트
- 실제 권한/실기기/브라우저 회귀 자동화 미흡

### 15.2 클라이언트-룰 정합성 민감 구간
- team/member/membership self-heal 로직이 다층이라 규칙 변경 시 영향 큼
- role 문자열(`speaker`, `leader`, 한글 role`) 호환 경로가 넓어 추후 정규화 필요

### 15.3 대규모 삭제 비용
- 팀 삭제는 다중 컬렉션 반복 batch delete
- 데이터량 큰 팀에서 시간/쿼터/실패 재시도 전략 필요

### 15.4 관리자 기능 중복
- 전역 곡 관리 기능이 `GlobalSongPanel`과 `GlobalAdminPage`에 중첩 존재
- 운영 UX 기준으로 책임 분리 필요

### 15.5 legacy 데이터 호환 코드 지속 증가
- v1/v2 note doc id, member uid/userId/email fallback 등
- 마이그레이션 완료 후 정리 계획 필요

---

## 16. 운영 전 필수 확인 체크(코드 기준)

1) Firestore Rules 최신본 게시
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/firestore.rules`

2) Storage Rules 최신본 게시
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/storage.rules`

3) Storage CORS 적용
- `/Users/hwanghuichan/Downloads/개발/WorshipFlow/scripts/storage_cors.json`
- 절차 문서: `/Users/hwanghuichan/Downloads/개발/WorshipFlow/scripts/README_CORS.md`

4) 운영자 계정 등록
- `globalAdmins/{uid}` 존재 확인

5) 웹 캐시 이슈 확인
- index.html service worker unregister 정책이 현재 운영 의도와 맞는지 검토

---

## 17. 결론
현재 코드베이스는 **팀/프로젝트/콘티/LiveCue/악보/초대/권한**의 핵심 경로를 대부분 포함하고 있으며,
특히 과거 이슈(권한 오류, stale reference, 캐시/URL 문제)를 완화하기 위한 복구 로직이 광범위하게 들어가 있다.

반면, 안정적 운영 판정을 위해서는 다음이 남는다.
- rules/CORS 실제 게시 상태와 코드 정합성 점검
- 다계정/다브라우저 실사용 시나리오 회귀 테스트
- 자동화 테스트 확대(현재는 사실상 수동 검증 의존)

이 문서는 “현재 코드가 어떻게 동작하는가”를 정리한 리서치 결과이며,
다음 단계(계획 문서 작성/구현)는 별도 요청 시 진행하는 것이 적절하다.
