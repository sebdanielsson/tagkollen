#!/usr/bin/env bash
# Captures the App Store screenshot set on the simulators whose pixel sizes App Store Connect requires:
#   iPhone 6.9" (iPhone 17 Pro Max)   1320 × 2868
#   iPad 13"    (iPad Pro 13-inch)    2064 × 2752
#
# Output: fastlane/screenshots/<locale>/<iphone|ipad>-<nn>-<name>.png, which is what
# `fastlane release` uploads. deliver picks the device family from the pixel size, so every locale
# is one flat folder.
#
#   Scripts/screenshots.sh                         # both devices, both locales
#   Scripts/screenshots.sh "iPhone 17 Pro Max"     # one device
#   LOCALES=sv Scripts/screenshots.sh              # one locale
#   TRAIN=560 Scripts/screenshots.sh               # pin the train instead of picking one live
#   SKIP_BUILD=1 Scripts/screenshots.sh            # reuse the last build
#
# Needs TRV_API_KEY in .env.local and `idb` (https://fbidb.io) for the iPhone captures, which drag
# the bottom card to the height that frames each subject. Which screen is showing is decided by the
# debug launch arguments -save/-train/-station/-tab, so no UI automation has to find its way there.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -d /Applications/Xcode.app ] && [ -z "${DEVELOPER_DIR:-}" ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [ -f .env.local ]; then
  # shellcheck disable=SC1091
  set -a; source .env.local; set +a
fi
: "${TRV_API_KEY:?TRV_API_KEY is not set — put it in .env.local}"

BUNDLE_ID="${APP_BUNDLE_ID:-se.tagkollen.app}"
DERIVED=".build/DerivedData"
OUT_ROOT="fastlane/screenshots"
IDB="${IDB:-$HOME/.local/bin/idb}"
# Seconds to let the map, the live stream and the timetable settle before each capture.
SETTLE="${SETTLE:-12}"
# Station shown on the departure board. Stockholm C is the busiest board in the country.
STATION="${STATION:-Cst}"

DEVICES=("$@")
if [ $# -eq 0 ]; then
  DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")
fi
read -r -a LOCALE_LIST <<<"${LOCALES:-en-US sv}"

# The train to feature. Pinning TRAIN makes a rerun reproducible; otherwise pick one that is
# actually moving right now, so the map has a live position and a drawn route to show.
pick_train() {
  python3 - "$TRV_API_KEY" <<'PY'
import datetime, json, sys, urllib.request

KEY = sys.argv[1]
ENDPOINT = "https://api.trafikinfo.trafikverket.se/v2/data.json"


def query(body: str):
    request = urllib.request.Request(
        ENDPOINT,
        data=f'<REQUEST><LOGIN authenticationkey="{KEY}"/>{body}</REQUEST>'.encode(),
        headers={"Content-Type": "text/xml"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)["RESPONSE"]["RESULT"][0]


# Trains reporting a position in the last ten minutes and moving at line speed: those are under way,
# not stabled, so the map has something to draw.
moving = query(
    '<QUERY objecttype="TrainPosition" namespace="järnväg.trafikinfo" schemaversion="1.1" limit="500">'
    '<FILTER><AND><GT name="TimeStamp" value="$dateadd(-0.00:10:00)"/>'
    '<GT name="Speed" value="80"/></AND></FILTER>'
    "<INCLUDE>Train.AdvertisedTrainNumber</INCLUDE></QUERY>"
).get("TrainPosition", [])
idents = sorted({p["Train"]["AdvertisedTrainNumber"] for p in moving if p.get("Train", {}).get("AdvertisedTrainNumber")})
if not idents:
    sys.exit("no train is moving right now — pass TRAIN=<number>")

# Of those, the one calling at the most stations: a long-distance run fills the timeline and the map.
stops = query(
    '<QUERY objecttype="TrainAnnouncement" namespace="rail.trafficinfo" schemaversion="2.0" limit="6000">'
    "<FILTER><AND>"
    f'<IN name="AdvertisedTrainIdent" value="{",".join(idents)}"/>'
    f'<EQ name="ScheduledDepartureDateTime" value="{datetime.date.today().isoformat()}"/>'
    '<EQ name="ActivityType" value="Avgang"/>'
    "</AND></FILTER>"
    "<INCLUDE>AdvertisedTrainIdent</INCLUDE></QUERY>"
).get("TrainAnnouncement", [])
counts: dict[str, int] = {}
for row in stops:
    counts[row["AdvertisedTrainIdent"]] = counts.get(row["AdvertisedTrainIdent"], 0) + 1
if not counts:
    sys.exit("none of the moving trains is advertised today — pass TRAIN=<number>")

# The runner-up rides along in the Saved list, so that section shows two rows rather than one.
ranked = sorted(counts, key=lambda ident: -counts[ident])
print(" ".join(ranked[:2]))
PY
}

if [ -n "${TRAIN:-}" ]; then
  SAVED="${SAVED:-$TRAIN}"
else
  echo "▶ Picking a train that is under way…"
  read -r TRAIN SECOND <<<"$(pick_train)"
  SAVED="${SAVED:-$TRAIN,$SECOND}"
fi
echo "▶ Featuring train $TRAIN; saved list: $SAVED"

if [ -z "${SKIP_BUILD:-}" ]; then
  [ -d Tagkollen.xcodeproj ] || Scripts/bootstrap.sh
  echo "▶ Building"
  xcodebuild -project Tagkollen.xcodeproj -scheme Tagkollen -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" build -quiet
fi
APP=$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "Tagkollen.app" | head -1)
[ -n "$APP" ] || { echo "No build in $DERIVED — run without SKIP_BUILD"; exit 1; }

udid_for() {
  xcrun simctl list devices available -j | python3 -c "
import json,sys
for runtime, devices in json.load(sys.stdin)['devices'].items():
    if 'iOS' not in runtime: continue
    for device in devices:
        if device['name'] == sys.argv[1]: print(device['udid']); sys.exit(0)
sys.exit(1)" "$1"
}

for DEVICE in "${DEVICES[@]}"; do
  case "$DEVICE" in iPad*) PREFIX="ipad";; *) PREFIX="iphone";; esac
  UDID=$(udid_for "$DEVICE") || { echo "No simulator named '$DEVICE'"; exit 1; }

  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  # Fresh install, so the Saved list holds exactly what -save pins and nothing from a previous run.
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$UDID" "$APP"
  # No permission alert in the middle of a capture.
  xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID" >/dev/null 2>&1 || true
  # The status bar Apple uses in its own screenshots.
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
  if [ "$PREFIX" = iphone ]; then
    [ -x "$IDB" ] || { echo "idb not found at $IDB — install it or set IDB=<path>"; exit 1; }
    "$IDB" connect "$UDID" >/dev/null 2>&1 || true
  fi

  for LOCALE in "${LOCALE_LIST[@]}"; do
    case "$LOCALE" in
      sv) LANGUAGE="sv"; REGION="sv_SE";;
      *)  LANGUAGE="en"; REGION="en_US";;
    esac
    OUT="$OUT_ROOT/$LOCALE"
    mkdir -p "$OUT"
    echo "▶ $DEVICE · $LOCALE → $OUT/$PREFIX-*.png"

    # Language is passed per launch rather than written to the simulator's global preferences, which
    # would need a reboot between locales.
    launch() {
      SIMCTL_CHILD_TRV_API_KEY="$TRV_API_KEY" xcrun simctl launch --terminate-running-process \
        "$UDID" "$BUNDLE_ID" -AppleLanguages "($LANGUAGE)" -AppleLocale "$REGION" "$@" >/dev/null
    }
    settle() {
      python3 -c "import time; time.sleep(${1:-$SETTLE})"
    }
    shot() {
      settle "${2:-$SETTLE}"
      xcrun simctl io "$UDID" screenshot "$OUT/$PREFIX-$1.png" >/dev/null 2>&1
      echo "  ✓ $PREFIX-$1"
    }
    # Drags on the card, in points on a 440 × 956 screen. The detent cannot be set from the outside —
    # `presentationDetents(selection:)` snaps back to the middle height whenever the card's content
    # changes — so these are the same gestures a hand would make.
    swipe() {
      "$IDB" ui swipe --udid "$UDID" --duration 0.4 "$@" >/dev/null 2>&1
      settle 2
    }
    expand_card() { swipe 220 470 220 90; }
    collapse_card() { swipe 220 450 220 930; }
    scroll_card() { swipe 220 780 220 300; }

    if [ "$PREFIX" = iphone ]; then
      # The card opens at its middle height over the map. Each shot drags it to whatever frames its
      # subject: up for a list, down to the search bar when the map itself is the subject.
      launch -save "$SAVED"
      shot "01-map"
      launch -train "$TRAIN"
      shot "02-train"
      launch -train "$TRAIN"
      settle
      expand_card
      scroll_card
      shot "03-stops" 2
      launch -station "$STATION"
      settle
      expand_card
      shot "04-station" 2
      launch -train "$TRAIN"
      settle
      collapse_card
      shot "05-route" 2
    else
      launch
      shot "01-map"
      launch -train "$TRAIN"
      shot "02-train"
      launch -station "$STATION"
      shot "03-station"
      launch -tab saved -save "$SAVED"
      shot "04-saved"
    fi
  done

  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
done

# App Store Connect rejects an alpha channel; the simulator always writes one.
FILES=()
for LOCALE in "${LOCALE_LIST[@]}"; do
  while IFS= read -r file; do FILES+=("$file"); done < <(find "$OUT_ROOT/$LOCALE" -name '*.png' | sort)
done
swift Scripts/strip-alpha.swift "${FILES[@]}"

printf '\n'
for file in "${FILES[@]}"; do
  read -r width height alpha <<<"$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$file" | awk '/pixelWidth|pixelHeight|hasAlpha/ {print $2}' | tr '\n' ' ')"
  printf '  %-44s %sx%s alpha=%s\n' "$file" "$width" "$height" "$alpha"
done
echo "Done. Review the images; \`fastlane release\` uploads them with the next release."
