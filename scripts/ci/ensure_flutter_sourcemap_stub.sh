#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-build/web}"
FLUTTER_JS="$BUILD_DIR/flutter.js"
SOURCE_MAP="$BUILD_DIR/flutter.js.map"

if [[ ! -f "$FLUTTER_JS" ]]; then
  echo "::error::Missing Flutter web bundle: $FLUTTER_JS"
  exit 1
fi

if ! grep -q "sourceMappingURL=flutter.js.map" "$FLUTTER_JS"; then
  echo "No flutter.js sourceMappingURL footer detected. Skipping source map stub."
  exit 0
fi

if [[ -f "$SOURCE_MAP" ]]; then
  echo "flutter.js.map already present. No action needed."
  exit 0
fi

cat > "$SOURCE_MAP" <<'EOF'
{
  "version": 3,
  "file": "flutter.js",
  "sources": [],
  "sourcesContent": [],
  "names": [],
  "mappings": ""
}
EOF

echo "Created source map stub: $SOURCE_MAP"
