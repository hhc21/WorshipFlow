#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORS_FILE="${1:-$ROOT_DIR/scripts/storage_cors.json}"

if [[ ! -f "$CORS_FILE" ]]; then
  echo "::error::Storage CORS file not found: $CORS_FILE"
  exit 1
fi

python3 - "$CORS_FILE" <<'PY'
import json
import sys
from pathlib import Path

cors_path = Path(sys.argv[1])
data = json.loads(cors_path.read_text(encoding="utf-8"))

if not isinstance(data, list) or not data:
    raise SystemExit(f"::error::CORS policy must be a non-empty JSON array: {cors_path}")

rule = data[0]
if not isinstance(rule, dict):
    raise SystemExit(f"::error::First CORS rule must be an object: {cors_path}")

required_origins = {
    "https://worshipflow-df2ce.web.app",
    "https://worshipflow-df2ce.firebaseapp.com",
    "http://localhost:3000",
    "http://localhost:5000",
    "http://localhost:7357",
    "http://localhost:8080",
}
required_methods = {"GET", "HEAD", "OPTIONS"}
required_headers = {"Content-Type", "Authorization"}

origins = set(rule.get("origin", []))
methods = set(rule.get("method", []))
headers = set(rule.get("responseHeader", []))
max_age = rule.get("maxAgeSeconds", 0)

missing_origins = sorted(required_origins - origins)
missing_methods = sorted(required_methods - methods)
missing_headers = sorted(required_headers - headers)

if missing_origins:
    raise SystemExit(f"::error::Missing required CORS origins: {', '.join(missing_origins)}")
if missing_methods:
    raise SystemExit(f"::error::Missing required CORS methods: {', '.join(missing_methods)}")
if missing_headers:
    raise SystemExit(f"::error::Missing required CORS response headers: {', '.join(missing_headers)}")
if not isinstance(max_age, int) or max_age < 3600:
    raise SystemExit("::error::CORS maxAgeSeconds must be an integer >= 3600")

print(f"Storage CORS policy check passed: {cors_path}")
PY
