# Release Runbook

## 1. Scope
- This runbook defines staging/production release and rollback for WorshipFlow.
- Source of truth branch: `main`.

## 2. Preconditions
- `PLAN-APPROVED` is confirmed.
- Required PR review and CI checks are green.
- Firebase rules (`firestore.rules`, `storage.rules`) changes are reviewed.

## 3. Environment Secrets
Set these separately in GitHub Environments.

### staging
- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_JSON` (recommended) or `FIREBASE_TOKEN` (temporary)

### production
- `FIREBASE_PROJECT_ID`
- `FIREBASE_SERVICE_ACCOUNT_JSON` (recommended) or `FIREBASE_TOKEN` (temporary)
- Required reviewers enabled

## 4. Staging Release
1. Merge approved PR into `main`.
2. Run `deploy-staging` workflow.
3. Verify app health on staging URL.
4. Verify deployment build flags:
   - confirm workflow log includes `--dart-define=WF_FIRESTORE_TRANSPORT=long-polling`
5. Verify Storage CORS before LiveCue validation:
   - current bucket CORS must match `scripts/storage_cors.json`
   - if mismatch, re-apply CORS and re-run smoke checks
4. Run smoke checks:
   - login
   - team select/team home
   - project create/open
   - live cue sheet open
   - iPad Safari LiveCue smoke (`docs/livecue_repro_matrix.md` 기준 최소 1케이스)

## 5. Production Release
1. Create release tag from `main` (e.g., `v1.3.0`).
2. Run `deploy-production` workflow with `release_ref` set to tag.
   - `livecue_safari_smoke_result=pass`
   - `livecue_safari_smoke_evidence=<issue/comment/video link>`
   - build must include `--dart-define=WF_FIRESTORE_TRANSPORT=long-polling`
3. Approve `production` environment deployment.
4. Validate post-deploy smoke checks.

## 6. Rollback
1. Select previous stable release tag.
2. Run `deploy-production` with previous tag as `release_ref`.
3. Verify rollback smoke checks.
4. Record incident summary and corrective actions.

Immediate rollback triggers (any one):
- within 30 minutes after deploy, LC-SAF-01/04/05 has at least one FAIL
- iPad Safari gray/black screen reproduced in 2+ independent sessions
- pencil/touch drawing input loss reproduced once
- score load failure caused by Firestore/Storage access error occurs 3 times in a row

## 7. Incident Notes
When release fails due to auth/rules/cache:
- Confirm environment secrets first.
- Confirm rules were deployed with hosting.
- Confirm browser cache behavior according to `docs/web_cache_strategy.md`.
- For LiveCue incidents, follow `docs/livecue_incident_runbook.md`.
