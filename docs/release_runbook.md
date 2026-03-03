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
4. Run smoke checks:
   - login
   - team select/team home
   - project create/open
   - live cue sheet open

## 5. Production Release
1. Create release tag from `main` (e.g., `v1.3.0`).
2. Run `deploy-production` workflow with `release_ref` set to tag.
3. Approve `production` environment deployment.
4. Validate post-deploy smoke checks.

## 6. Rollback
1. Select previous stable release tag.
2. Run `deploy-production` with previous tag as `release_ref`.
3. Verify rollback smoke checks.
4. Record incident summary and corrective actions.

## 7. Incident Notes
When release fails due to auth/rules/cache:
- Confirm environment secrets first.
- Confirm rules were deployed with hosting.
- Confirm browser cache behavior according to `docs/web_cache_strategy.md`.
