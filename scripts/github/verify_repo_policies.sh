#!/usr/bin/env bash
set -euo pipefail

OWNER="${GITHUB_OWNER:-hhc21}"
REPO="${GITHUB_REPO:-WorshipFlow}"
BRANCH="${GITHUB_BRANCH:-main}"

ensure_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "::error::gh is not authenticated."
    exit 1
  fi
}

assert_eq_true() {
  local value="$1"
  local label="$2"
  if [[ "$value" != "true" ]]; then
    echo "::error::$label is not enabled."
    exit 1
  fi
}

assert_not_empty() {
  local value="$1"
  local label="$2"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "::error::$label is missing."
    exit 1
  fi
}

verify_branch_protection() {
  local raw json
  raw="$(gh api "/repos/$OWNER/$REPO/branches/$BRANCH/protection")"
  json="$(printf '%s' "$raw")"

  assert_eq_true "$(printf '%s' "$json" | jq -r '.enforce_admins.enabled')" "enforce_admins"
  assert_not_empty "$(printf '%s' "$json" | jq -r '.required_pull_request_reviews.required_approving_review_count')" "required approving review count"
  assert_eq_true "$(printf '%s' "$json" | jq -r '.required_status_checks.strict')" "strict status checks"

  if ! printf '%s' "$json" | jq -e '.required_status_checks.contexts | index("ci / ci") != null' >/dev/null; then
    echo "::error::Required status check 'ci / ci' is missing."
    exit 1
  fi
}

verify_environment() {
  local env_name="$1"
  local raw json
  raw="$(gh api "/repos/$OWNER/$REPO/environments/$env_name")"
  json="$(printf '%s' "$raw")"

  if ! printf '%s' "$json" | jq -e '.protection_rules[]? | select(.type == "required_reviewers")' >/dev/null; then
    echo "::error::Environment '$env_name' is missing required reviewers."
    exit 1
  fi
}

verify_plan_label() {
  gh api "/repos/$OWNER/$REPO/labels/plan-approved" >/dev/null
  local tagged
  tagged="$(gh api "/repos/$OWNER/$REPO/issues?state=all&labels=plan-approved&per_page=1" --jq '.[0].number // empty')"
  assert_not_empty "$tagged" "issue/pr with plan-approved label"
}

main() {
  ensure_auth
  verify_branch_protection
  verify_environment "staging"
  verify_environment "production"
  verify_plan_label
  echo "Repository policy verification passed for $OWNER/$REPO."
}

main "$@"
