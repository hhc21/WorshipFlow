# WorshipFlow (교회 예배팀 운영 웹앱 MVP)

카카오톡으로 하던 예배 운영 흐름을 웹앱으로 통합하는 Flutter Web + Firebase MVP입니다.

## 기술 스택
- Flutter Web
- Firebase: Auth (Google), Firestore, Storage, Hosting
- 상태관리: flutter_riverpod
- 라우팅: go_router
- UI: Material 3

## 빠른 시작

### 1) Flutter 설치 확인
```bash
flutter --version
flutter doctor
```

### 2) Firebase 프로젝트 생성
- Firebase Console에서 프로젝트 생성
- Auth(Google) 활성화
- Firestore 생성
- Storage 버킷 생성

### 3) FlutterFire 설정
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=worshipflow-df2ce
```
- 위 명령으로 `lib/firebase_options.dart`가 생성됩니다.

### 4) 로컬 실행 (Web)
```bash
flutter pub get
flutter run -d chrome
```

### 5) 배포 (Firebase Hosting)
```bash
flutter build web
firebase deploy
```

## Firebase 설정 파일
- `firebase.json`
- `.firebaserc`
- `firestore.rules`
- `storage.rules`

## CI/CD (GitHub Actions)
- CI: `.github/workflows/ci.yml`
  - `flutter analyze`
  - `flutter test --coverage`
  - `scripts/ci/check_coverage.sh`
  - `flutter build web --release`
- Staging Deploy: `.github/workflows/deploy_staging.yml`
- Production Deploy: `.github/workflows/deploy_prod.yml`

### GitHub Environments 권장 시크릿
- `staging` / `production` 각각 분리:
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_SERVICE_ACCOUNT_JSON` (권장) 또는 `FIREBASE_TOKEN` (임시)

운영 절차는 `docs/release_runbook.md`를 기준으로 진행합니다.

## Firestore 컬렉션 구조 (권장)
```
teams/{teamId}
teams/{teamId}/members/{userId}
teams/{teamId}/invites/{inviteId}
teams/{teamId}/songs/{songId}
teams/{teamId}/songs/{songId}/assets/{assetId}
teams/{teamId}/projects/{projectId}
teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}
teams/{teamId}/projects/{projectId}/segmentB_application/{itemId}
teams/{teamId}/projects/{projectId}/liveCue/{docId}
teams/{teamId}/userSongNotes/{noteId}
teams/{teamId}/userProjectNotes/{noteId}
```

## 권한 요약 (Firestore Rules 반영)
- 팀 멤버만 팀 데이터 접근 가능
- TeamAdmin만 멤버 관리
- Leader: Segment A + LiveCue 편집
- Speaker: Segment B + LiveCue 편집
- Member: 읽기 + 본인 notes만 쓰기
- Storage는 teamId 경로 기준 멤버 접근만 허용

## 팀 초대 (이메일 기반)
- TeamAdmin이 이메일로 초대 생성
- 초대 문서는 `invites/{email}` (lowercase)로 생성
- 로그인 사용자는 자신의 이메일 초대를 확인 후 수락

## LiveCue 실시간 구독
- 실시간 구독은 `projects/{projectId}/liveCue/state` 문서에만 사용
- 그 외 데이터는 단발성 조회(Future) 방식으로 로딩

## 메모
- `lib/firebase_options.dart`는 `flutterfire configure`로 생성됩니다.
- 프로젝트 생성 시 leader 멤버에게 `capabilities.songEditor = true`를 부여합니다.
