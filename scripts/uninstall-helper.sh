#!/usr/bin/env bash
set -euo pipefail

# Removes the root fan helper installed by MacFanControl.
# macOS will ask for your administrator password.

LABEL="com.macfancontrol.helper"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
HELPER="/usr/local/libexec/MacFanControlHelper"

echo "Removing MacFanControl helper…"

sudo /bin/launchctl bootout "system/${LABEL}" >/dev/null 2>&1 || true
sudo /bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
sudo /usr/bin/killall MacFanControlHelper >/dev/null 2>&1 || true
sudo /bin/rm -f "$PLIST" "$HELPER"
sudo /bin/rm -f /tmp/macfancontrol-*.sock /tmp/macfancontrol-*.log

echo "Fan helper removed. Opening MacFanControl will ask for permission again if you want to control fans."
