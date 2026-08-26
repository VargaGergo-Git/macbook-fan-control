#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-MacFanControl.app}"
DMG_NAME="${2:-MacFanControl.dmg}"
STAGING="dmg-staging"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found: $APP_DIR"
  echo "Build first: swift build -c release"
  echo "Then create the bundle or pass an existing .app path."
  exit 1
fi

rm -rf "$STAGING" "$DMG_NAME"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "MacFanControl" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING"

echo "Created $DMG_NAME"
