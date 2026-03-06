#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-required}"
RESULT_RAW="${LIVECUE_SAFARI_SMOKE_RESULT:-}"
EVIDENCE="${LIVECUE_SAFARI_SMOKE_EVIDENCE:-}"
RESULT="$(echo "$RESULT_RAW" | tr '[:upper:]' '[:lower:]')"

is_pass=false
case "$RESULT" in
  pass|passed|ok|true|yes)
    is_pass=true
    ;;
esac

if [[ "$MODE" == "warn" ]]; then
  if [[ "$is_pass" == "true" ]]; then
    echo "LiveCue Safari smoke gate (warn): PASS"
    if [[ -n "$EVIDENCE" ]]; then
      echo "Evidence: $EVIDENCE"
    fi
    exit 0
  fi
  echo "::warning::LiveCue Safari smoke check is not marked as pass. result='${RESULT_RAW:-<empty>}'"
  if [[ -n "$EVIDENCE" ]]; then
    echo "::warning::Evidence: $EVIDENCE"
  fi
  exit 0
fi

if [[ "$is_pass" != "true" ]]; then
  echo "::error::LiveCue Safari smoke gate failed. Set LIVECUE_SAFARI_SMOKE_RESULT=pass and provide evidence."
  echo "::error::Current result='${RESULT_RAW:-<empty>}' evidence='${EVIDENCE:-<empty>}'"
  exit 1
fi

echo "LiveCue Safari smoke gate: PASS"
if [[ -n "$EVIDENCE" ]]; then
  echo "Evidence: $EVIDENCE"
fi
