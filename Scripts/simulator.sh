#!/usr/bin/env bash
# Build, install and launch Tågkollen on an iOS Simulator, optionally taking a screenshot.
#
#   Scripts/simulator.sh                      # iPhone 17 Pro
#   Scripts/simulator.sh "iPad Pro 13-inch (M5)"
#   Scripts/simulator.sh "iPhone 17 Pro" shot.png   # also save a screenshot after launch
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-iPhone 17 Pro}"
SHOT="${2:-}"
BUNDLE_ID="se.sebastiandanielsson.tagkollen"
DERIVED=".build/DerivedData"

if [ -d /Applications/Xcode.app ] && [ -z "${DEVELOPER_DIR:-}" ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

[ -d Tagkollen.xcodeproj ] || Scripts/bootstrap.sh

UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
data=json.load(sys.stdin)['devices']
want=sys.argv[1]
for runtime,devs in data.items():
    if 'iOS' not in runtime: continue
    for d in devs:
        if d['name']==want:
            print(d['udid']); sys.exit(0)
sys.exit(1)
" "$DEVICE") || { echo "No simulator named '$DEVICE'. Available:"; xcrun simctl list devices available | grep -E "iPhone|iPad"; exit 1; }

echo "▶ Building for $DEVICE ($UDID)"
xcodebuild -project Tagkollen.xcodeproj -scheme Tagkollen -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build -quiet

APP=$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "Tagkollen.app" | head -1)
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
if [ -f .env.local ]; then
  # shellcheck disable=SC1091
  set -a; source .env.local; set +a
fi
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" >/dev/null
echo "▶ Launched $BUNDLE_ID"

if [ -n "$SHOT" ]; then
  sleep 4
  xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null
  echo "▶ Screenshot saved to $SHOT"
fi
