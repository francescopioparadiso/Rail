#!/bin/zsh
# App Store screenshots and thumbnails of Rail, in Italian, on invented data (no
# account needed). It builds Rail, runs it on its own iPhone 18 Pro simulator
# (created the first time) and saves, in Images/:
#   Resources/Screenshots/1…7.png  the bare screen (1206 × 2622), nothing around it
#   Thumbnails/1…7.png             the screen in the bezel, under its title
# Usage: scripts/screenshots.sh   (titles below; bezels downloaded to Images/Resources/Bezels)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.francescoparadis.Rail"
BUILD_DIR="${TMPDIR:-/tmp}/rail-screenshots-build"
NAME="Screenshots iPhone 18 Pro"
SHOTS="$ROOT/Images/Resources/Screenshots"
THUMBS="$ROOT/Images/Thumbnails"

# The title of each screen, two lines; a part between *stars* is New York italic
TITLES=(
    "Mai più|*sorprese*"
    "Tutto sotto|*controllo*"
    "Importa tutto|dalle *mail*"
    "Fai una ricerca|*intelligente*"
    "Tieni sott’occhio|l’intera *stazione*"
    "Aggiungi gli|*abbonamenti*"
    "*Profilo,*|tutto tuo!"
)

# Apple's bezels (Apple Design Resources), downloaded the first time: their licence
# allows them in marketing images, not in this public repository. The opened-out
# Duo is for the social posts (`thumbnail "iPhone Duo Open"`).
BEZELS="$ROOT/Images/Resources/Bezels"
# fetch_bezels <dmg> <path in the dmg with COLOR> <saved name with COLOR> <colors…>
fetch_bezels() {
    local dmg="$1" source="$2" target="$3"; shift 3
    [[ -f "$BEZELS/${target//COLOR/$1}" ]] && return
    local work=$(mktemp -d)
    curl -sfL -o "$work/bezel.dmg" "https://devimages-cdn.apple.com/design/resources/download/$dmg"
    mkdir "$work/mount"
    # "yes" accepts the licence; fed in rather than piped, so pipefail does not trip on it
    hdiutil attach -nobrowse -readonly -mountpoint "$work/mount" "$work/bezel.dmg" < <(yes) >/dev/null 2>&1
    mkdir -p "$BEZELS"
    for color in "$@"; do
        cp "$work/mount/${source//COLOR/$color}" "$BEZELS/${target//COLOR/$color}"
    done
    hdiutil detach "$work/mount" >/dev/null 2>&1
    echo "Downloaded the bezels in $dmg"
}
fetch_bezels Bezel-iPhone-18.dmg "PNG/iPhone 18 Pro/iPhone 18 Pro - COLOR - Portrait.png" \
    "iPhone 18 Pro - COLOR.png" Silver Black Burgundy Glacier
fetch_bezels Bezel-iPhone-Duo.dmg "PNG/iPhone Duo - COLOR - Inner Open Landscape.png" \
    "iPhone Duo Open - COLOR.png" "Night Sky" "Star White"

# Build, and the thumbnail maker beside it
xcodebuild -project "$ROOT/Rail.xcodeproj" -scheme Rail -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$BUILD_DIR" build -quiet
APP="$BUILD_DIR/Build/Products/Debug-iphonesimulator/Rail.app"
swiftc -O "$ROOT/scripts/thumbnail.swift" -o "$BUILD_DIR/thumbnail"

# The simulator: found by name, created the first time with an English region, so
# the status bar reads "9:41" rather than "09:41"
UDID=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == '$NAME' and d.get('isAvailable', True):
            print(d['udid']); sys.exit()
")
if [[ -z "$UDID" ]]; then
    UDID=$(xcrun simctl create "$NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro \
        com.apple.CoreSimulator.SimRuntime.iOS-27-2)
    xcrun simctl boot "$UDID"
    xcrun simctl spawn "$UDID" defaults write -g AppleLocale en_US
    xcrun simctl spawn "$UDID" defaults write -g AppleLanguages -array en
    xcrun simctl shutdown "$UDID"
    echo "Created simulator $NAME"
fi

# Booted, light, with Apple's 9:41 status bar, Rail installed with every permission
# so no prompt covers a screen
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState discharging --batteryLevel 100
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant all "$BUNDLE" 2>/dev/null || true

# One launch per screen. A launch takes several seconds to draw; the board (5) also
# waits for the live departures, and the journey (2) for its push.
mkdir -p "$SHOTS" "$THUMBS"
for n in 1 2 3 4 5 6 7; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" -rail-screenshot "$n" \
        -AppleLanguages "(it)" -AppleLocale it_IT >/dev/null
    if [[ $n == 5 ]]; then sleep 14; else sleep 10; fi
    xcrun simctl io "$UDID" screenshot --type=png "$SHOTS/$n.png" >/dev/null 2>&1
    title="${TITLES[$n]}"
    BEZELS="$BEZELS" "$BUILD_DIR/thumbnail" "iPhone 18 Pro" "$SHOTS/$n.png" "$THUMBS/$n.png" \
        "${title%%|*}" "${title#*|}" >/dev/null
    echo "Screen $n done"
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
