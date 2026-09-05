#!/usr/bin/env bash
# Captures App Store screenshots on the simulators whose pixel sizes App Store Connect requires:
#   iPhone 6.9" (iPhone 17 Pro Max)   1320 × 2868
#   iPad 13"    (iPad Pro 13-inch)    2064 × 2752
# Output: fastlane/screenshots/<locale>/<iphone|ipad>-<nn>-<name>.png (LOCALE=sv for Swedish). Needs a booted-capable simulator per device
# and TRV_API_KEY in .env.local. Uses `idb` (https://fbidb.io) for taps when available; otherwise it
# only captures the map.
#
#   Scripts/screenshots.sh                 # both devices
#   Scripts/screenshots.sh "iPhone 17 Pro Max"
#   TRAIN=537 Scripts/screenshots.sh       # train to open for the detail screenshot
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /Applications/Xcode.app ] && [ -z "${DEVELOPER_DIR:-}" ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DEVICES=("${@:-iPhone 17 Pro Max}")
if [ $# -eq 0 ]; then
  DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")
fi
TRAIN="${TRAIN:-537}"
IDB="${IDB:-$HOME/.local/bin/idb}"
# deliver (fastlane) picks the device type from the pixel size, so every locale is one flat folder.
OUT_ROOT="fastlane/screenshots"
LOCALE="${LOCALE:-en-US}"

for DEVICE in "${DEVICES[@]}"; do
  case "$DEVICE" in iPad*) PREFIX="ipad";; *) PREFIX="iphone";; esac
  OUT="$OUT_ROOT/$LOCALE"
  mkdir -p "$OUT"
  echo "▶ $DEVICE → $OUT/$PREFIX-*.png"
  UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
for runtime,devs in json.load(sys.stdin)['devices'].items():
    if 'iOS' not in runtime: continue
    for d in devs:
        if d['name']==sys.argv[1]: print(d['udid']); sys.exit(0)
sys.exit(1)" "$DEVICE")
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  # Status bar like Apple's own screenshots.
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true

  shot() { sleep "${2:-2}"; xcrun simctl io "$UDID" screenshot "$OUT/$1.png" >/dev/null; echo "  ✓ $1"; }
  launch() { SKIP_BUILD="${SKIP_BUILD:-}" TRAIN="${1:-}" Scripts/simulator.sh "$DEVICE" >/dev/null 2>&1; SKIP_BUILD=1; }

  launch ""
  sleep 8
  shot "$PREFIX-01-map" 1
  launch "$TRAIN"
  sleep 8
  shot "$PREFIX-02-train" 1
  if [ -x "$IDB" ]; then
    "$IDB" ui button HOME >/dev/null 2>&1 || true
  fi
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  python3 - "$OUT" <<'PY'
import struct, sys, pathlib
for png in sorted(pathlib.Path(sys.argv[1]).glob("*.png")):
    with open(png, "rb") as f:
        head = f.read(24)
    w, h = struct.unpack(">II", head[16:24])
    print(f"  {png.name}: {w}x{h}")
PY
done
echo "Done. Review the images, then upload them in App Store Connect (1–10 per device size, no alpha)."
