#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI_YML="$ROOT_DIR/.github/workflows/ci.yml"
STAGING_YML="$ROOT_DIR/.github/workflows/deploy_staging.yml"
PROD_YML="$ROOT_DIR/.github/workflows/deploy_prod.yml"

assert_contains() {
  local file="$1"
  local text="$2"
  local label="$3"
  if ! grep -Fq -- "$text" "$file"; then
    echo "::error::[deploy-gate] Missing '$label' in $file"
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  local label="$3"
  if grep -Fq -- "$text" "$file"; then
    echo "::error::[deploy-gate] Unexpected '$label' in $file"
    exit 1
  fi
}

assert_contains "$STAGING_YML" "workflow_run:" "staging workflow_run trigger"
assert_contains "$STAGING_YML" "workflows:" "staging workflow source declaration"
assert_contains "$STAGING_YML" "- ci" "staging depends on ci workflow"
assert_contains "$STAGING_YML" "github.event.workflow_run.conclusion == 'success'" "staging success-only gate"
assert_contains "$STAGING_YML" "needs: preflight" "staging deploy needs preflight"
assert_not_contains "$STAGING_YML" "push:" "staging direct push trigger"

assert_contains "$CI_YML" "flutter test --coverage" "ci coverage tests"
assert_contains "$STAGING_YML" "flutter test --coverage" "staging preflight coverage tests"
assert_contains "$PROD_YML" "flutter test --coverage" "production preflight coverage tests"
assert_contains "$CI_YML" "scripts/ci/verify_storage_cors_policy.sh" "ci storage cors policy check"
assert_contains "$STAGING_YML" "scripts/ci/verify_storage_cors_policy.sh" "staging storage cors policy check"
assert_contains "$PROD_YML" "scripts/ci/verify_storage_cors_policy.sh" "production storage cors policy check"
assert_contains "$CI_YML" "scripts/ci/ensure_flutter_sourcemap_stub.sh" "ci flutter source map stub step"
assert_contains "$STAGING_YML" "scripts/ci/ensure_flutter_sourcemap_stub.sh" "staging flutter source map stub step"
assert_contains "$PROD_YML" "scripts/ci/ensure_flutter_sourcemap_stub.sh" "production flutter source map stub step"
assert_contains "$CI_YML" "--dart-define=WF_FIRESTORE_TRANSPORT=" "ci transport dart-define"
assert_contains "$STAGING_YML" "--dart-define=WF_FIRESTORE_TRANSPORT=" "staging transport dart-define"
assert_contains "$PROD_YML" "--dart-define=WF_FIRESTORE_TRANSPORT=" "production transport dart-define"
assert_contains "$STAGING_YML" "verify_livecue_safari_gate.sh required" "staging safari smoke required gate"
assert_contains "$PROD_YML" "verify_livecue_safari_gate.sh required" "production safari smoke required gate"
assert_contains "$CI_YML" "scripts/ci/test_rules.sh" "ci firestore rules suite"
assert_contains "$STAGING_YML" "scripts/ci/test_rules.sh" "staging firestore rules suite"
assert_contains "$PROD_YML" "scripts/ci/test_rules.sh" "production firestore rules suite"
assert_contains "$PROD_YML" "needs: preflight" "production deploy needs preflight"

echo "Deploy gate policy verification passed."
