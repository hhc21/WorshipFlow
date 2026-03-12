# Release Evidence (SP-07 Snapshot)

Last updated: 2026-03-12 (KST)
Status: Release Candidate (SP-07 not closed)

---

## 1. Static Gate

### flutter analyze
- Result: PASS
- Command: `flutter analyze`
- Timestamp (KST): Pending evidence link
- Build version: Pending evidence link
- Log reference: Pending evidence link

### flutter test
- Result: PASS
- Command: `flutter test --reporter=compact`
- Timestamp (KST): Pending evidence link
- Build version: Pending evidence link
- Log reference: Pending evidence link

### Rules test
- Result: Not updated in this cycle
- Note: Rules test pass/fail is out of scope for this specific evidence refresh.

---

## 2. Functional / Manual Verification

### LiveCue first entry
- Functional result: PASS
- Residual issue: initial score render latency (~15 seconds)
- Type: latency (not hard failure)
- Timestamp (KST): Pending evidence link
- Log reference: Pending evidence link
- Screenshot / video: Pending evidence link

### Problem song test (`주의 집에 거하는 자`)
- Result: PASS
- Note: score resolution confirmed in latest manual verification.
- Timestamp (KST): Pending evidence link
- Log reference: Pending evidence link
- Screenshot / video: Pending evidence link

### In-app preview
- Result: PASS
- Note: in-app preview flow confirmed.
- Timestamp (KST): Pending evidence link
- Log reference: Pending evidence link
- Screenshot / video: Pending evidence link

### Setlist reorder
- Result: PARTIAL
- Working: reorder behavior itself works.
- Residual issue: visible numbering does not refresh correctly after reorder.
- Timestamp (KST): Pending evidence link
- Log reference: Pending evidence link
- Screenshot / video: Pending evidence link

---

## 3. SP-07 Interpretation

- Evidence was refreshed with latest verification outcomes.
- Current build remains **Release Candidate**.
- SP-07 is **not fully closed** yet due to residual runtime issues:
  - LiveCue first-entry render latency (~15s)
  - setlist reorder numbering refresh mismatch
- Final approval must wait for residual issue stabilization and full evidence-package linkage.
