# Storage CORS 적용

웹에서 악보 이미지/파일을 안정적으로 불러오려면 Storage bucket CORS를 설정해야 합니다.

## 1) CORS 설정 반영

```bash
gcloud storage buckets update gs://worshipflow-df2ce.firebasestorage.app --cors-file=scripts/storage_cors.json
```

`gcloud` 대신 `gsutil`을 쓰는 경우:

```bash
gsutil cors set scripts/storage_cors.json gs://worshipflow-df2ce.firebasestorage.app
```

## 2) 확인

```bash
gsutil cors get gs://worshipflow-df2ce.firebasestorage.app
```

설정 후 브라우저 캐시를 비우고 재로그인 후 테스트하세요.
