# Incident Response

Last updated:  
Owner:  
Service: WorshipFlow  

Incident contact:

Primary:
Secondary:

---

# Purpose

Define the response procedure when a production issue occurs in WorshipFlow.

This guide ensures incidents are detected, mitigated, and resolved quickly while minimizing service disruption.

---

# Incident Definition

An incident is any event that causes:

- service disruption
- incorrect LiveCue behavior
- data inconsistency
- authentication failure
- Firestore synchronization issues

Typical indicators include:

- repeated runtime guard triggers
- Firestore snapshot errors
- unexpected UI state
- user reports of broken functionality

---

# Detection

Incidents are typically detected through system metrics.

Primary signals

- runtime_guard_triggered
- livecue_state_invalid
- setlist_order_invalid
- router_invalid_id
- firestore_snapshot_error

Detection sources

- ops metrics
- error logs
- user reports
- monitoring dashboards

---

# Severity Levels

## SEV-1 (Critical)

Production service unusable.

Examples

- LiveCue cannot load
- Firestore data corruption
- authentication failure for all users

Action

Immediate mitigation required.

---

## SEV-2 (Major)

Major functionality degraded but service still partially usable.

Examples

- cue transitions failing
- setlist order breaking
- viewer host failing

Action

Fix required within the same release cycle.

---

## SEV-3 (Minor)

Non-critical issue.

Examples

- UI rendering bug
- minor navigation issue
- delayed synchronization

Action

Document and schedule fix.

---

# Immediate Mitigation

When an incident is detected:

1. Identify affected feature

Possible areas

- LiveCue engine
- setlist management
- router navigation
- Firestore synchronization
- viewer host communication

2. Stabilize the system

Possible mitigation actions

- reload LiveCue state
- restart session
- disable viewer host temporarily
- force setlist reload
- clear local cache

Never modify Firestore data unless absolutely necessary.

---

# Investigation

Locate the guard or error that triggered the incident.

Common sources

runtime_guard.dart  
router.dart  
ops_metrics.dart  

Examples

setlist_order_invalid  
→ reorder operation failed

livecue_state_invalid  
→ LiveCue state mismatch

router_invalid_id  
→ invalid Firestore document ID

firestore_snapshot_error  
→ Firestore listener failure

---

# Resolution

Apply the smallest safe fix.

Rules

- avoid rewriting large files
- modify only affected logic
- preserve runtime guard protections
- avoid introducing new state paths

After applying a fix run:

flutter analyze

flutter test --reporter=compact

bash scripts/ci/test_rules.sh

All validations must pass.

---

# Verification

Confirm the incident is resolved.

Verification steps

- reproduce the original issue
- confirm the fix works
- confirm runtime guards are not triggering
- confirm no new errors appear

---

# Postmortem

Every SEV-1 and SEV-2 incident requires documentation.

Record the following

Timestamp  
Trigger condition  
Affected feature  
Root cause  
Fix applied  
Preventive action  

Postmortems should be stored in:

docs/incidents/

Example filename

incident_YYYY_MM_DD.md

---

# Prevention

After resolving an incident

- add regression tests if applicable
- improve runtime guard coverage
- update documentation if needed
- verify release checklist

The goal is to prevent recurrence.