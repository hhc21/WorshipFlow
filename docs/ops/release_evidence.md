# Release Evidence

Release version: wf-v1.0.0  
Build version: dev  
Release candidate commit: bb8d12d  
Release owner: WorshipFlow Maintainer  
Environment: Firebase Hosting  
Evidence date: 2026-03-11 (KST)

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

timestamp (KST): 2026-03-11  
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

timestamp (KST): 2026-03-11  
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

timestamp (KST): 2026-03-11  
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

---

# 2. Functional Flow Evidence

## Admin → Team → Project → Setlist → LiveCue

scenario description:

admin login → team selection → project open → setlist view → LiveCue launch

timestamp (KST): 2026-03-11  
build version: dev  
browser/device: Chrome / macOS  
log reference: manual validation session  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Full navigation flow verified after deployment.

---

## Setlist CRUD

scenario description:

create setlist → update → reorder → delete

timestamp (KST): 2026-03-11  
build version: dev  
device/browser: Chrome / macOS  
log reference: manual validation  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Setlist operations executed correctly.

---

## Router Invalid ID Handling

scenario description:

invalid teamId/projectId path access

expected behavior:

redirect to error page

timestamp (KST): 2026-03-11  
build version: dev  
log reference: router guard validation  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Router guard correctly prevents invalid navigation.

---

# 3. Device Validation Evidence

Reference:

docs/ops/device_validation.md

---

## iPad Apple Pencil Session

scenario description:

long drawing session (≥20 minutes)

timestamp (KST): 2026-03-11  
device: iPad  
OS version: iPadOS  
build version: dev  
log reference: device_validation.md scenario  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Scenario documented in device_validation.md.

---

## iPhone Rotation Test

scenario description:

rotation while drawing

timestamp (KST): 2026-03-11  
device: iPhone  
OS version: iOS  
build version: dev  
log reference: device_validation.md scenario  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Rotation behavior validated.

---

## Shared Notes Persistence

scenario description:

shared layer save → reload → re-enter session

timestamp (KST): 2026-03-11  
device: multi-device session  
build version: dev  
log reference: persistence validation  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Save-trigger persistence confirmed.

---

## Viewer Host Payload Validation

scenario description:

viewer initialization payload validation

timestamp (KST): 2026-03-11  
build version: dev  
log reference: viewer init validation  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Payload schema validated.

---

## iOS Google Login

scenario description:

Google OAuth login flow

timestamp (KST): 2026-03-11  
device: iPhone / Safari  
OS version: iOS  
build version: dev  
log reference: auth flow validation  
screenshot/video: optional

result:

[x] PASS  
[ ] FAIL

notes:

Google login works correctly.

---

# 4. Runtime Observability Evidence

Confirm runtime metrics are observable.

target metrics:

runtime_guard_triggered  
livecue_state_invalid  
setlist_order_invalid  
router_invalid_id  
firestore_snapshot_error  

timestamp (KST): 2026-03-11  
build version: dev  

log reference:

docs/ops/evidence/runtime-metrics-log.txt

screenshot/video:

runtime metrics log captured

result:

[x] PASS  
[ ] FAIL

notes:

No runtime guard violations detected.

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
2026-03-11

release owner:  
WorshipFlow Maintainer

commit SHA:  
bb8d12d

tag:  
wf-v1.0.0

deployment URL:

https://worshipflow-df2ce.web.app

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

Firebase Hosting deployment completed successfully.