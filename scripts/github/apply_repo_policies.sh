#!/usr/bin/env bash
set -euo pipefail

OWNER="${GITHUB_OWNER:-hhc21}"
REPO="${GITHUB_REPO:-WorshipFlow}"
BRANCH="${GITHUB_BRANCH:-main}"
REVIEWER_ID="${GITHUB_REVIEWER_ID:-215528270}"
REVIEWER_LOGIN="${GITHUB_REVIEWER_LOGIN:-hhc21}"

ensure_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "::error::gh is not authenticated. Run: gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key"
    exit 1
  fi
}

apply_branch_protection() {
  cat <<EOF | gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$OWNER/$REPO/branches/$BRANCH/protection" \
    --input -
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci / ci"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true
}
EOF
}

apply_environment() {
  local env_name="$1"
  cat <<EOF | gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$OWNER/$REPO/environments/$env_name" \
    --input -
{
  "wait_timer": 0,
  "reviewers": [
    {
      "type": "User",
      "id": $REVIEWER_ID
    }
  ],
  "can_admins_bypass": false,
  "prevent_self_review": false
}
EOF
}

ensure_plan_label() {
  if gh api "/repos/$OWNER/$REPO/labels/plan-approved" >/dev/null 2>&1; then
    return 0
  fi
  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "/repos/$OWNER/$REPO/labels" \
    -f name='plan-approved' \
    -f color='0E8A16' \
    -f description='Plan approval confirmed'
}

attach_plan_label() {
  local number
  number="$(gh api "/repos/$OWNER/$REPO/pulls?state=open&per_page=1" --jq '.[0].number // empty')"
  if [[ -z "$number" ]]; then
    number="$(gh api "/repos/$OWNER/$REPO/issues?state=open&per_page=1" --jq '.[0].number // empty')"
  fi
  if [[ -z "$number" ]]; then
    number="$(
      gh api \
        --method POST \
        -H "Accept: application/vnd.github+json" \
        "/repos/$OWNER/$REPO/issues" \
        -f title='PLAN-APPROVED' \
        -f body='자동 정책 적용을 위한 승인 트래킹 이슈입니다.' \
        -f assignees[]="$REVIEWER_LOGIN" \
        -f labels[]='plan-approved' \
        --jq '.number'
    )"
    echo "Created tracking issue #$number with plan-approved label."
    return 0
  fi

  gh api \
    --method POST \
    -H "Accept: application/vnd.github+json" \
    "/repos/$OWNER/$REPO/issues/$number/labels" \
    -f labels[]='plan-approved' >/dev/null
  echo "Applied plan-approved label to issue/PR #$number."
}

main() {
  ensure_auth
  ensure_plan_label
  apply_branch_protection
  apply_environment "staging"
  apply_environment "production"
  attach_plan_label
  echo "Repository policy apply completed for $OWNER/$REPO."
}

main "$@"
