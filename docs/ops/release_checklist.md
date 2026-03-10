# Release Checklist

Release version:  
Build version:  
Release owner:  
Release date:  

---

# Purpose

This checklist verifies that WorshipFlow is ready for production deployment.

All checks must pass before approving a release.

---

# 1. Repository State

Confirm the repository is in a clean and aligned state.

Checklist

- [ ] `plan.md` reflects the current SP status
- [ ] `product_development_map.md` matches `plan.md`
- [ ] `release_runbook.md` matches runtime implementation
- [ ] `AGENTS.md` exists in repository root
- [ ] `.codex/context.md` exists
- [ ] documentation drift resolved
- [ ] `docs_index.md` correctly references all documents

---

# 2. Static Validation

Run the required validation commands.

Run

```bash
flutter analyze
flutter test --reporter=compact
bash scripts/ci/test_rules.sh
```

Expected Result

All commands must pass.

Checklist

- [ ] flutter analyze PASS
- [ ] flutter test PASS
- [ ] test_rules.sh PASS

---

# 3. Runtime Safety Verification

Verify runtime guards exist and are functioning.

Required guards

- runtime_guard
- router parameter guard
- setlist integrity guard
- LiveCue state validation
- host viewer payload validation

Expected metrics

- runtime_guard_triggered
- livecue_state_invalid
- setlist_order_invalid
- router_invalid_id
- firestore_snapshot_error

Checklist

- [ ] runtime_guard implemented
- [ ] ops_metrics implemented
- [ ] router guard implemented
- [ ] setlist validation implemented
- [ ] viewer payload validation implemented
- [ ] runtime metrics observable in logs

---

# 4. Firestore Model Integrity

Verify Firestore paths match the canonical data model.

Required canonical paths

teams/{teamId}/projects/{projectId}/segmentA_setlist/{itemId}

teams/{teamId}/projects/{projectId}/liveCue/state

teams/{teamId}/projects/{projectId}/sharedNotes/main

teams/{teamId}/userProjectNotes/{noteId}

Checklist

- [ ] code paths match `data_model.md`
- [ ] security rules match `firestore.rules`
- [ ] no orphaned Firestore collections exist
- [ ] no unexpected document structure introduced

---

# 5. Router Integrity

Verify navigation guards and route validation.

Checklist

- [ ] invalid Firestore ID blocked
- [ ] missing document handled gracefully
- [ ] invalid routes redirected to error page
- [ ] admin → team → project navigation works
- [ ] router parameter guard active

Expected behavior

Invalid path → error page  
Missing document → error page  
Valid path → normal route  

---

# 6. Large File Safety

Large files require careful review.

High-risk files

```
live_cue_page.dart
team_home_page.dart
global_admin_page.dart
```

Checklist

- [ ] no full rewrites performed
- [ ] changes limited to functional units
- [ ] runtime guards preserved
- [ ] no state logic duplicated in UI
- [ ] tests updated if logic changed

---

# 7. Device Validation

Device testing must be completed.

Reference

`docs/ops/device_validation.md`

Checklist

- [ ] iPad Apple Pencil session PASS
- [ ] iPhone rotation PASS
- [ ] shared notes persistence PASS (save-trigger model)
- [ ] viewer host validation PASS
- [ ] Google login (iOS) PASS

Device validation notes

- timestamp (KST):
- build/release version:
- log reference:
- screenshot/video linkage:

---

# 8. Operational Readiness

Verify operational monitoring and response readiness.

Checklist

- [ ] ops metrics visible
- [ ] runtime guard metrics logged
- [ ] error logs accessible
- [ ] incident response guide available
- [ ] monitoring dashboards available

Reference

`docs/ops/incident_response.md`

---

# 9. Release Gate Confirmation

Release may proceed only if all checks pass.

Approval checklist

- [ ] static validation PASS
- [ ] runtime safety PASS
- [ ] Firestore integrity PASS
- [ ] router integrity PASS
- [ ] device validation PASS
- [ ] operational readiness PASS

---

# Final Decision

Release Status

[x] APPROVED
[ ] BLOCKED

Notes

---
