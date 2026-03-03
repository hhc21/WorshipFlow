#!/usr/bin/env bash
set -euo pipefail

LCOV_FILE="${1:-coverage/lcov.info}"
MIN_COVERAGE="${COVERAGE_MIN:-35}"

if [[ ! -f "$LCOV_FILE" ]]; then
  echo "::error::Coverage file not found: $LCOV_FILE"
  exit 1
fi

extract_by_lcov() {
  lcov --summary "$LCOV_FILE" 2>/dev/null | awk '
    /lines\.*:/ {
      gsub("%", "", $2);
      print $2;
      exit;
    }'
}

extract_by_lcov_info() {
  awk -F: '
    /^LF:/ { lf += $2 }
    /^LH:/ { lh += $2 }
    END {
      if (lf == 0) {
        print "0.00"
      } else {
        printf "%.2f\n", (lh / lf) * 100
      }
    }' "$LCOV_FILE"
}

coverage=""
if command -v lcov >/dev/null 2>&1; then
  coverage="$(extract_by_lcov || true)"
fi

if [[ -z "$coverage" ]]; then
  coverage="$(extract_by_lcov_info)"
fi

printf "Coverage result: %s%% (minimum required: %s%%)\n" "$coverage" "$MIN_COVERAGE"

if ! awk -v c="$coverage" -v m="$MIN_COVERAGE" 'BEGIN { exit((c + 0 >= m + 0) ? 0 : 1) }'; then
  echo "::error::Coverage gate failed: ${coverage}% < ${MIN_COVERAGE}%"
  exit 1
fi

echo "Coverage gate passed."

