#!/usr/bin/env bash
set -euo pipefail

LCOV_FILE="${1:-coverage/lcov.info}"
COVERAGE_STAGE="${COVERAGE_STAGE:-baseline}"
MIN_COVERAGE="${COVERAGE_MIN:-}"
DEFAULT_EXCLUDE_REGEX='lib/features/projects/live_cue_page\.dart|lib/features/projects/segment_a_page\.dart|lib/features/projects/segment_b_page\.dart|lib/features/teams/team_home_page\.dart'
COVERAGE_EXCLUDE_REGEX="${COVERAGE_EXCLUDE_REGEX-$DEFAULT_EXCLUDE_REGEX}"

if [[ -z "$MIN_COVERAGE" ]]; then
  case "$COVERAGE_STAGE" in
    baseline) MIN_COVERAGE="35" ;;
    step50) MIN_COVERAGE="50" ;;
    step60) MIN_COVERAGE="60" ;;
    *)
      echo "::error::Unknown COVERAGE_STAGE: $COVERAGE_STAGE"
      exit 1
      ;;
  esac
fi

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
  awk -F: -v exclude_regex="$COVERAGE_EXCLUDE_REGEX" '
    function should_exclude(path) {
      return exclude_regex != "" && path ~ exclude_regex;
    }
    /^SF:/ {
      file = substr($0, 4);
      lf = 0;
      lh = 0;
    }
    /^LF:/ { lf = $2 + 0 }
    /^LH:/ { lh = $2 + 0 }
    /^end_of_record/ {
      if (!should_exclude(file)) {
        total_lf += lf;
        total_lh += lh;
      }
    }
    END {
      if (total_lf == 0) {
        print "0.00"
      } else {
        printf "%.2f\n", (total_lh / total_lf) * 100
      }
    }' "$LCOV_FILE"
}

coverage=""
if [[ -z "$COVERAGE_EXCLUDE_REGEX" ]] && command -v lcov >/dev/null 2>&1; then
  coverage="$(extract_by_lcov || true)"
fi

if [[ -z "$coverage" ]]; then
  coverage="$(extract_by_lcov_info)"
fi

if [[ -n "$COVERAGE_EXCLUDE_REGEX" ]]; then
  printf "Coverage exclude regex: %s\n" "$COVERAGE_EXCLUDE_REGEX"
fi
printf "Coverage stage: %s\n" "$COVERAGE_STAGE"

printf "Coverage result: %s%% (minimum required: %s%%)\n" "$coverage" "$MIN_COVERAGE"

if ! awk -v c="$coverage" -v m="$MIN_COVERAGE" 'BEGIN { exit((c + 0 >= m + 0) ? 0 : 1) }'; then
  echo "::error::Coverage gate failed: ${coverage}% < ${MIN_COVERAGE}%"
  exit 1
fi

echo "Coverage gate passed."
