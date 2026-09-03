#!/usr/bin/env bash
# Build, install and launch Tågkollen on an iOS Simulator, optionally taking a screenshot.
#
#   Scripts/simulator.sh                      # iPhone 17 Pro
#   Scripts/simulator.sh "iPad Pro 13-inch (M5)"
#   Scripts/simulator.sh "iPhone 17 Pro" shot.png   # also save a screenshot after launch
#   TAB=search Scripts/simulator.sh                   # open a specific tab (map|saved|search), debug builds only
#   TRAIN=520 Scripts/simulator.sh                    # open a train's detail at launch, debug builds only
#   SKIP_BUILD=1 Scripts/simulator.sh                 # reuse the last build
#
# If .env.local defines TRV_API_KEY it is passed to the app as an environment variable.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-iPhone 17 Pro}"
SHOT="${2:-}"
BUNDLE_ID="se.tagkollen.app"
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

if [ -z "${SKIP_BUILD:-}" ]; then
echo "▶ Building for $DEVICE ($UDID)"
# Keep (ad hoc) code signing on: without it the widget extension loses its entitlements and App Intents
# registration, so widgets stay on their placeholder and the App Group is unavailable.
xcodebuild -project Tagkollen.xcodeproj -scheme Tagkollen -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  build -quiet
fi

APP=$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "Tagkollen.app" | head -1)
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
if [ -f .env.local ]; then
  # shellcheck disable=SC1091
  set -a; source .env.local; set +a
fi
ARGS=()
[ -n "${TAB:-}" ] && ARGS+=(-tab "$TAB")
[ -n "${TRAIN:-}" ] && ARGS+=(-train "$TRAIN")
SIMCTL_CHILD_TRV_API_KEY="${TRV_API_KEY:-}" xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" "${ARGS[@]}" >/dev/null
echo "▶ Launched $BUNDLE_ID"

if [ -n "$SHOT" ]; then
  sleep 4
  xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null
  echo "▶ Screenshot saved to $SHOT"
fi
