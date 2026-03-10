# Release Evidence

Release version:  
Build version:  
Release candidate commit:  
Release owner:  
Environment:  
Evidence date:  

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

timestamp (KST):  
build version:  

command

flutter analyze

log reference:  
evidence file:  

result:

[ ] PASS  
[ ] FAIL

---

## flutter test

timestamp (KST):  
build version:  

command

flutter test --reporter=compact

log reference:  
evidence file:  

result:

[ ] PASS  
[ ] FAIL

---

## Firestore Rules Test

timestamp (KST):  
build version:  

command

bash scripts/ci/test_rules.sh

log reference:  
evidence file:  

result:

[ ] PASS  
[ ] FAIL

---

# 2. Functional Flow Evidence

## Admin → Team → Project → Setlist → LiveCue

scenario description:

admin login → team selection → project open → setlist view → LiveCue launch

timestamp (KST):  
build version:  
browser/device:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

## Setlist CRUD

scenario description:

create setlist → update → reorder → delete

timestamp (KST):  
build version:  
device/browser:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

## Router Invalid ID Handling

scenario description:

invalid teamId/projectId path access

expected behavior:

redirect to error page

timestamp (KST):  
build version:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

# 3. Device Validation Evidence

Reference:

docs/ops/device_validation.md

---

## iPad Apple Pencil Session

scenario description:

long drawing session (≥20 minutes)

timestamp (KST):  
device:  
OS version:  
build version:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

## iPhone Rotation Test

scenario description:

rotation while drawing

timestamp (KST):  
device:  
OS version:  
build version:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

## Shared Notes Persistence

scenario description:

shared layer save → reload → re-enter session

timestamp (KST):  
device:  
build version:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

## Viewer Host Payload Validation

scenario description:

viewer initialization payload validation

timestamp (KST):  
build version:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

## iOS Google Login

scenario description:

Google OAuth login flow

timestamp (KST):  
device:  
OS version:  
build version:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

# 4. Runtime Observability Evidence

Confirm runtime metrics are observable.

target metrics:

runtime_guard_triggered  
livecue_state_invalid  
setlist_order_invalid  
router_invalid_id  
firestore_snapshot_error  

timestamp (KST):  
build version:  
log reference:  
screenshot/video:  

result:

[ ] PASS  
[ ] FAIL

notes:

---

# 5. Release Gate Summary

| Gate | Status |
|-----|------|
| Static validation | |
| Functional flow | |
| Device validation | |
| Runtime safety | |

---

# 6. Release Decision Evidence

Release readiness conclusion:

[ ] APPROVED  
[ ] BLOCKED  

decision timestamp (KST):  

release owner:  

commit SHA:  

tag:  

---

# 7. Evidence Files

Evidence files stored under:

docs/ops/evidence/

Example:

docs/ops/evidence/
- ipad-pencil-session.mov
- iphone-rotation-test.mov
- runtime-metrics-log.txt
- setlist-flow.png
- router-invalid-id.png

---

# 8. Notes / Incidents

Record any anomalies or non-blocking observations.

incident reference:

docs/ops/incident_response.md

notes: