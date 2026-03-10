#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

name_hits="$(
  find . -type f \
    -not -path './.git/*' \
    -not -path './build/*' \
    -not -path './node_modules/*' \
    -not -path './.dart_tool/*' \
    -not -path './.firebase/*' \
    | rg -n 'firebase-adminsdk|service-account' || true
)"

if [[ -n "$name_hits" ]]; then
  echo "::error::Potential service account key file detected by filename pattern."
  echo "$name_hits"
  exit 1
fi

content_hits="$(
  rg -n --glob '*.json' '"type"\\s*:\\s*"service_account"|\"private_key\"\\s*:' . \
    --glob '!build/**' \
    --glob '!node_modules/**' \
    --glob '!.dart_tool/**' \
    --glob '!.firebase/**' \
    --glob '!.git/**' || true
)"

if [[ -n "$content_hits" ]]; then
  echo "::error::Potential service account key content detected in JSON files."
  echo "$content_hits"
  exit 1
fi

echo "No service account key files detected."
