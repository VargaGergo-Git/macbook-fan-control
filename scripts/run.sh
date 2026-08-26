#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building MacFanControl and MacFanControlHelper..."
swift build -c release

find_binary() {
  local name="$1"
  local path

  for path in \
    "$ROOT/.build/release/$name" \
    "$ROOT/.build/out/Products/Release/$name" \
    "$ROOT/.build/debug/$name" \
    "$ROOT/.build/out/Products/Debug/$name"
  do
    if [[ -f "$path" && -x "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  find "$ROOT/.build" \
    -type f \
    -name "$name" \
    ! -path '*.dSYM/*' \
    ! -path '*/indexstore/*' \
    2>/dev/null \
    | awk '
      /\/(release|Release)\// { print; found=1; exit }
      { candidates[++n]=$0 }
      END { if (!found && n) print candidates[1] }
    '
}

APP="$(find_binary MacFanControl)"
HELPER="$(find_binary MacFanControlHelper)"

if [[ -z "${APP:-}" || -z "${HELPER:-}" ]]; then
  echo "Build succeeded, but binaries were not found under .build/"
  echo "Looked for MacFanControl and MacFanControlHelper in:"
  echo "  .build/release/"
  echo "  .build/out/Products/Release/"
  find "$ROOT/.build" -type f -name 'MacFanControl*' ! -path '*.dSYM/*' 2>/dev/null | sed 's/^/  /' || true
  exit 1
fi

APP_DIR="$(dirname "$APP")"
HELPER_DIR="$(dirname "$HELPER")"

if [[ "$APP_DIR" != "$HELPER_DIR" ]]; then
  echo "Copying helper next to app binary..."
  cp "$HELPER" "$APP_DIR/MacFanControlHelper"
  chmod +x "$APP_DIR/MacFanControlHelper"
  HELPER="$APP_DIR/MacFanControlHelper"
fi

echo "Launching $APP"
echo "Helper: $HELPER"
exec "$APP"
