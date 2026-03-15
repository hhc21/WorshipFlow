# Release Evidence (SP-07 Historical Snapshot)

Last updated: 2026-03-15 (KST)
Status: Historical close reference (SP-07 closed, current main moved into SP-08)

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

- This document preserves the closing-edge snapshot around SP-07.
- Current repository history has moved past this point:
  - `wf-v1.0.0` release evidence tag exists
  - subsequent SP-08 commits are already merged on `main`
- The residual runtime issues listed in this snapshot were handed off to post-release stabilization / SP-08 work.
- Therefore this document should not be interpreted as meaning that SP-07 is still the active current stage.
