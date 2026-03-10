# LiveCue Next.js Viewer PoC

Safari white-out(B-02) 대응을 위한 Next.js 기반 필기 뷰어 PoC입니다.

## 실행

```bash
cd apps/livecue-web-next
npm install
npm run dev
```

기본 주소는 `http://localhost:3000`이며 Flutter Host의 `WF_NEXT_VIEWER_URL` 기본값과 맞춰져 있습니다.

## 프로토콜 요약

- Viewer -> Host
  - `viewer-ready`
  - `init-applied`
  - `ink-dirty`
  - `ink-commit`
  - `ink-synced`
  - `asset-cors-failed`
- Host -> Viewer
  - `host-init`
  - `token-refresh`
  - `ink-synced`

## 데이터 계약

- 좌표계: `0.0 ~ 1.0` 상대 좌표
- 정밀도: 소수점 8자리 고정(`round(value * 1e8) / 1e8`)
- 스키마 버전: `relative-v1`
