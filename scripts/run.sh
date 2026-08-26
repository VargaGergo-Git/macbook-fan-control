#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building MacFanControl and MacFanControlHelper..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path 2>/dev/null || true)"

find_binary() {
  local name="$1"
  local path

  if [[ -n "${BIN_DIR:-}" ]]; then
    for path in "$BIN_DIR/$name" "$BIN_DIR/$name.app/Contents/MacOS/$name"; do
      if [[ -f "$path" ]]; then
        printf '%s\n' "$path"
        return 0
      fi
    done
  fi

  for path in \
    "$ROOT/.build/release/$name" \
    "$ROOT/.build/out/Products/Release/$name" \
    "$ROOT/.build/debug/$name" \
    "$ROOT/.build/out/Products/Debug/$name"
  do
    if [[ -f "$path" ]]; then
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

APP="$(find_binary MacFanControl || true)"
HELPER="$(find_binary MacFanControlHelper || true)"

if [[ -z "${APP:-}" || -z "${HELPER:-}" ]]; then
  echo "Build succeeded, but binaries were not found."
  echo "swift build --show-bin-path: ${BIN_DIR:-<empty>}"
  echo "Files matching MacFanControl*:"
  find "$ROOT/.build" -name 'MacFanControl*' ! -path '*.dSYM/*' 2>/dev/null | sed 's/^/  /' || true
  exit 1
fi

chmod +x "$APP" "$HELPER" 2>/dev/null || true

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
