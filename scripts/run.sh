#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building MacFanControl and MacFanControlHelper..."
swift build -c release

APP="$(find "$ROOT/.build" -type f -path '*/release/MacFanControl' ! -path '*.dSYM/*' 2>/dev/null | head -1)"
HELPER="$(find "$ROOT/.build" -type f -path '*/release/MacFanControlHelper' ! -path '*.dSYM/*' 2>/dev/null | head -1)"

if [[ -z "${APP:-}" || -z "${HELPER:-}" ]]; then
  echo "Build failed: could not locate release binaries under .build/"
  exit 1
fi

APP_DIR="$(dirname "$APP")"
HELPER_DIR="$(dirname "$HELPER")"

if [[ "$APP_DIR" != "$HELPER_DIR" ]]; then
  echo "Copying helper next to app binary..."
  cp "$HELPER" "$APP_DIR/MacFanControlHelper"
  chmod +x "$APP_DIR/MacFanControlHelper"
fi

echo "Launching $APP"
echo "Helper: $APP_DIR/MacFanControlHelper"
exec "$APP"
