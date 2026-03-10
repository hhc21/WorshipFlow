#!/usr/bin/env bash
set -euo pipefail

MATRIX_FILE="${1:-docs/livecue_repro_matrix.md}"

if [[ ! -f "$MATRIX_FILE" ]]; then
  echo "::error::Matrix file not found: $MATRIX_FILE"
  exit 1
fi

if rg -n '\| LC-SAF-[0-9]{2} .* \| TODO \|' "$MATRIX_FILE" >/dev/null; then
  echo "::error::LiveCue repro matrix contains TODO status rows."
  rg -n '\| LC-SAF-[0-9]{2} .* \| TODO \|' "$MATRIX_FILE"
  exit 1
fi

missing_fields=0
for case_id in LC-SAF-01 LC-SAF-02 LC-SAF-03 LC-SAF-04 LC-SAF-05 LC-SAF-06; do
  row="$(rg -n "\\| ${case_id} \\|" "$MATRIX_FILE" || true)"
  if [[ -z "$row" ]]; then
    echo "::error::Missing matrix row: ${case_id}"
    missing_fields=1
    continue
  fi
  if [[ "$row" != *"first_error:"* ]]; then
    echo "::error::${case_id} row missing first_error field"
    missing_fields=1
  fi
  if [[ "$row" != *"video:"* ]]; then
    echo "::error::${case_id} row missing video field"
    missing_fields=1
  fi
done

if [[ "$missing_fields" -ne 0 ]]; then
  exit 1
fi

echo "LiveCue repro matrix verification passed."
