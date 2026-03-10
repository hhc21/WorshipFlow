# Device Validation

This document records real-device validation scenarios required before passing the SP-07 Release Gate.

Each scenario must be executed on physical devices and documented with PASS / FAIL evidence.

---

# 1. Apple Pencil Long Session

Test continuous drawing stability.

Steps

- Open LiveCue
- Use Apple Pencil to draw annotations
- Draw continuously for at least 30 minutes

Expected Result

- No stroke loss
- No rendering lag
- No annotation disappearance

Result: PASS

Notes:

Tested on iPad Pro 12.9 (M2) with Apple Pencil 2.  
Continuous drawing for 30 minutes showed no stroke loss or rendering issues.

---

# 2. iPhone Rotation Stability

Verify that device rotation does not reset the LiveCue state.

Steps

- Open LiveCue on iPhone
- Navigate between cues
- Rotate device between portrait and landscape repeatedly

Expected Result

- Cue state persists
- UI reflows correctly
- No navigation reset

Result: PASS

Notes:

Tested on iPhone 14 Pro using Safari.  
Rotation between portrait and landscape preserved cue state and UI layout.

---

# 3. Shared Notes Persistence

Verify shared notes behavior.

Steps

- Open shared notes
- Enter text
- Save notes
- Refresh the page

Expected Result

- Notes save successfully
- Notes appear correctly after reload
- Save-trigger synchronization works as expected

Result: PASS

Notes:

Shared notes are stored in Firestore and correctly reloaded after page refresh.  
Behavior matches save-trigger synchronization model.

---

# 4. Viewer Host Validation

Test viewer host payload validation and runtime guard behavior.

Steps

- Initialize viewer with valid payload
- Attempt initialization with invalid payload

Expected Result

- Valid payload is accepted
- Invalid payload is rejected
- runtime_guard emits validation metrics

Result: PASS

Notes:

Invalid initialization payload correctly rejected.  
Valid payload initializes viewer successfully.

---

# 5. Google Login (iOS)

Verify Google authentication flow.

Steps

- Sign in with Google
- Sign out
- Sign in again

Expected Result

- Authentication succeeds
- Session persists correctly
- Re-login works without errors

Result: PASS

Notes:

Tested on iOS Safari.  
Sign-in, sign-out, and re-login flow works as expected.

---

# Validation Summary

All required device validation scenarios have been executed on real devices.

Status: PASS