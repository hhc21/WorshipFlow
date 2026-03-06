#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${FIREBASE_RULES_PROJECT:-demo-worshipflow}"
export FIREBASE_CLI_DISABLE_UPDATE_CHECK=1
export CI=1
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$PWD/.tmp/config}"
mkdir -p "$XDG_CONFIG_HOME"

npx firebase emulators:exec --project "$PROJECT_ID" --only firestore \
  "node scripts/rules/firestore_rules_self_healing_test.js"
