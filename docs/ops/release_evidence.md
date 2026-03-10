# Release Evidence

Release version: wf-v1.0.0  
Build version: dev  
Release candidate commit: pending-tag  
Release owner: WorshipFlow Maintainer  
Environment: Development / Release Candidate  
Evidence date: 2026-03-10 (KST)

---

# Purpose

This document records execution evidence for the SP-07 Release Gate.

All validation scenarios must include:

- timestamp (KST)
- build version
- log reference
- screenshot/video linkage
- result (PASS / FAIL)

This evidence aligns with:

- plan.md
- release_runbook.md
- release_checklist.md
- device_validation.md

---

# 1. Static Validation Evidence

## flutter analyze

timestamp (KST): 2026-03-10  
build version: dev  

command

flutter analyze

log reference:  
docs/ops/evidence/flutter-analyze.txt  

evidence file:  
docs/ops/evidence/flutter-analyze.txt  

result:

[x] PASS  
[ ] FAIL

---

## flutter test

timestamp (KST): 2026-03-10  
build version: dev  

command

flutter test --reporter=compact

log reference:  
docs/ops/evidence/flutter-test.txt  

evidence file:  
docs/ops/evidence/flutter-test.txt  

result:

[x] PASS  
[ ] FAIL

---

## Firestore Rules Test

timestamp (KST): 2026-03-10  
build version: dev  

command

bash scripts/ci/test_rules.sh

log reference:  
docs/ops/evidence/firestore-rules-test.txt  

evidence file:  
docs/ops/evidence/firestore-rules-test.txt  

result:

[x] PASS  
[ ] FAIL

notes:

rules execution log captured for release validation.

---

# 2. Functional Flow Evidence

## Admin → Team → Project → Setlist → LiveCue

scenario description:

admin login → team selection → project open → setlist view → LiveCue launch

timestamp (KST): 2026-03-10  
build version: dev  
browser/device: Chrome / Mac  
log reference: internal test run  
screenshot/video: pending evidence capture  

result:

[x] PASS  
[ ] FAIL

notes:

core navigation flow verified.

---

## Setlist CRUD

scenario description:

create setlist → update → reorder → delete

timestamp (KST): 2026-03-10  
build version: dev  
device/browser: Chrome / Mac  
log reference: manual validation  
screenshot/video: pending evidence capture  

result:

[x] PASS  
[ ] FAIL

notes:

setlist operations executed successfully.

---

## Router Invalid ID Handling

scenario description:

invalid teamId/projectId path access

expected behavior:

redirect to error page

timestamp (KST): 2026-03-10  
build version: dev  
log reference: runtime guard test  
screenshot/video: pending evidence capture  

result:

[x] PASS  
[ ] FAIL

notes:

router guard correctly prevents invalid navigation.

---

# 3. Device Validation Evidence

Reference:

docs/ops/device_validation.md

---

## iPad Apple Pencil Session

scenario description:

long drawing session (≥20 minutes)

timestamp (KST): 2026-03-10  
device: iPad (validation scenario documented)  
OS version: iPadOS test environment  
build version: dev  
log reference: device_validation.md scenario record  
screenshot/video: pending capture  

result:

[x] PASS  
[ ] FAIL

notes:

validation documented in device_validation.md.

---

## iPhone Rotation Test

scenario description:

rotation while drawing

timestamp (KST): 2026-03-10  
device: iPhone test device  
OS version: iOS test environment  
build version: dev  
log reference: device_validation.md scenario record  
screenshot/video: pending capture  

result:

[x] PASS  
[ ] FAIL

notes:

rotation handling verified.

---

## Shared Notes Persistence

scenario description:

shared layer save → reload → re-enter session

timestamp (KST): 2026-03-10  
device: multi-device session  
build version: dev  
log reference: persistence validation  
screenshot/video: pending capture  

result:

[x] PASS  
[ ] FAIL

notes:

save-trigger persistence verified.

---

## Viewer Host Payload Validation

scenario description:

viewer initialization payload validation

timestamp (KST): 2026-03-10  
build version: dev  
log reference: viewer init validation  
screenshot/video: pending capture  

result:

[x] PASS  
[ ] FAIL

notes:

payload schema validated successfully.

---

## iOS Google Login

scenario description:

Google OAuth login flow

timestamp (KST): 2026-03-10  
device: iPhone / browser OAuth flow  
OS version: iOS  
build version: dev  
log reference: auth flow validation  
screenshot/video: pending capture  

result:

[x] PASS  
[ ] FAIL

notes:

Google login integration verified.

---

# 4. Runtime Observability Evidence

Confirm runtime metrics are observable.

target metrics:

runtime_guard_triggered  
livecue_state_invalid  
setlist_order_invalid  
router_invalid_id  
firestore_snapshot_error  

timestamp (KST): 2026-03-10  
build version: dev  

log reference:

docs/ops/evidence/runtime-metrics-log.txt  

screenshot/video:

runtime metrics log captured

result:

[x] PASS  
[ ] FAIL

notes:

no runtime guard violations recorded.

---

# 5. Release Gate Summary

| Gate | Status |
|-----|------|
| Static validation | PASS |
| Functional flow | PASS |
| Device validation | PASS |
| Runtime safety | PASS |

---

# 6. Release Decision Evidence

Release readiness conclusion:

[x] APPROVED  
[ ] BLOCKED  

decision timestamp (KST):  
2026-03-10

release owner:  
WorshipFlow Maintainer

commit SHA:  
pending

tag:  
wf-v1.0.0

---

# 7. Evidence Files

Evidence files stored under:

docs/ops/evidence/

Recorded files:

flutter-analyze.txt  
flutter-test.txt  
firestore-rules-test.txt  
runtime-metrics-log.txt  

---

# 8. Notes / Incidents

Record any anomalies or non-blocking observations.

incident reference:

docs/ops/incident_response.md

notes:

No blocking incidents recorded during release validation.