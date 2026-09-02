#!/usr/bin/env bash
# Build, sign and install Tågkollen on a connected iPhone or iPad, then launch it.
#
#   Scripts/device.sh                 # first connected device
#   Scripts/device.sh "My iPhone"     # by name
#
# Needs DEVELOPMENT_TEAM in .env.local (Xcode > Settings > Accounts shows your team ID; a free
# Personal Team works). The device must be paired, trusted and have Developer Mode enabled.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /Applications/Xcode.app ] && [ -z "${DEVELOPER_DIR:-}" ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [ -f .env.local ]; then
  # shellcheck disable=SC1091
  set -a; source .env.local; set +a
fi
[ -n "${DEVELOPMENT_TEAM:-}" ] || { echo "Set DEVELOPMENT_TEAM in .env.local" >&2; exit 1; }
Scripts/bootstrap.sh >/dev/null

NAME="${1:-}"
DEVICE_JSON=$(mktemp)
xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null
UDID=$(python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2]
for d in devices:
    name = d["deviceProperties"]["name"]
    if want and name != want:
        continue
    print(d["hardwareProperties"]["udid"])
    break
' "$DEVICE_JSON" "$NAME")
[ -n "$UDID" ] || { echo "No connected device${NAME:+ named $NAME}" >&2; exit 1; }
echo "▶ Building for device $UDID"
xcodebuild -project Tagkollen.xcodeproj -scheme Tagkollen -configuration Debug \
  -destination "id=$UDID" -derivedDataPath .build/DerivedData \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet
APP=$(find .build/DerivedData/Build/Products/Debug-iphoneos -maxdepth 1 -name "Tagkollen.app" | head -1)
echo "▶ Installing"
xcrun devicectl device install app --device "$UDID" "$APP"
echo "▶ Launching"
xcrun devicectl device process launch --device "$UDID" se.sebastiandanielsson.tagkollen >/dev/null
echo "Done. If the app refuses to open, trust the developer certificate under Settings > General > VPN & Device Management."
