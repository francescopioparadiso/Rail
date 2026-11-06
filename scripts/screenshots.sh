#!/bin/zsh
# App Store screenshots and thumbnails of Rail, in Italian, on invented data (no
# account needed). For each device it builds Rail, runs it on its own simulator
# (created the first time) and saves, in Thumbnails/:
#   Screenshots/<device>/1…7.png  the bare screen, nothing around it
#   Thumbnails/<device>/1…7.png   the screen in the bezel, under its title
# Devices: iPhone 18 Pro (1206 × 2622), iPhone Duo folded (1398 × 2034).
# Usage: scripts/screenshots.sh        (titles below; bezels downloaded to Thumbnails/Bezels)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.francescoparadis.Rail"
BUILD_DIR="${TMPDIR:-/tmp}/rail-screenshots-build"

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
# allows them in marketing images, not in this public repository
BEZELS="$ROOT/Thumbnails/Bezels"
# fetch_bezels <dmg> <path in the dmg with COLOR> <saved name with COLOR> <colors…>
fetch_bezels() {
    local dmg="$1" source="$2" target="$3"; shift 3
    [[ -f "$BEZELS/${target//COLOR/$1}" ]] && return
    local work=$(mktemp -d)
    curl -sfL -o "$work/bezel.dmg" "https://devimages-cdn.apple.com/design/resources/download/$dmg"
    mkdir "$work/mount"
    yes | hdiutil attach -nobrowse -readonly -mountpoint "$work/mount" "$work/bezel.dmg" >/dev/null 2>&1
    mkdir -p "$BEZELS"
    for color in "$@"; do
        cp "$work/mount/${source//COLOR/$color}" "$BEZELS/${target//COLOR/$color}"
    done
    hdiutil detach "$work/mount" >/dev/null 2>&1
    echo "Downloaded the bezels in $dmg"
}
fetch_bezels Bezel-iPhone-18.dmg "PNG/iPhone 18 Pro/iPhone 18 Pro - COLOR - Portrait.png" \
    "iPhone 18 Pro - COLOR.png" Silver Black Burgundy Glacier
fetch_bezels Bezel-iPhone-Duo.dmg "PNG/iPhone Duo - COLOR - Outer Closed Portrait.png" \
    "iPhone Duo - COLOR.png" "Night Sky" "Star White"

# Build once, for any simulator, and the thumbnail maker beside it
xcodebuild -project "$ROOT/Rail.xcodeproj" -scheme Rail -configuration Debug \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$BUILD_DIR" build -quiet
APP="$BUILD_DIR/Build/Products/Debug-iphonesimulator/Rail.app"
swiftc -O "$ROOT/scripts/thumbnail.swift" -o "$BUILD_DIR/thumbnail"

# shoot <device> <simulator type> <runtime> [display width]
shoot() {
    local device="$1" type="$2" runtime="$3" width="${4:-}"
    local name="Screenshots $device"
    local shots="$ROOT/Thumbnails/Screenshots/$device" thumbs="$ROOT/Thumbnails/Thumbnails/$device"

    # The simulator: found by name, created the first time with an English region,
    # so the status bar reads "9:41" rather than "09:41"
    local udid=$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == '$name' and d.get('isAvailable', True):
            print(d['udid']); sys.exit()
")
    if [[ -z "$udid" ]]; then
        udid=$(xcrun simctl create "$name" "$type" "$runtime")
        xcrun simctl boot "$udid"
        xcrun simctl spawn "$udid" defaults write -g AppleLocale en_US
        xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array en
        xcrun simctl shutdown "$udid"
        echo "Created simulator $name"
    fi

    # Booted, light, with Apple's 9:41 status bar, Rail installed with every
    # permission so no prompt covers a screen
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl ui "$udid" appearance light
    xcrun simctl status_bar "$udid" override --time "9:41" \
        --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 \
        --batteryState discharging --batteryLevel 100
    xcrun simctl install "$udid" "$APP"
    xcrun simctl privacy "$udid" grant all "$BUNDLE" 2>/dev/null || true

    # The display to capture: the one of the given width (the Duo's outer one),
    # or the only one
    local display=()
    if [[ -n "$width" ]]; then
        display=(--display=$(xcrun simctl io "$udid" enumerate | python3 -c "
import sys
uuid = None
for line in sys.stdin:
    line = line.strip()
    if line.startswith('UUID:'): uuid = line.split()[1]
    if line == 'Default width: $width': print(uuid); break
"))
    fi

    # One launch per screen. A launch takes several seconds to draw; the board (5)
    # also waits for the live departures, and the journey (2) for its push.
    mkdir -p "$shots" "$thumbs"
    for n in 1 2 3 4 5 6 7; do
        xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
        xcrun simctl launch "$udid" "$BUNDLE" -rail-screenshot "$n" \
            -AppleLanguages "(it)" -AppleLocale it_IT >/dev/null
        if [[ $n == 5 ]]; then sleep 14; else sleep 10; fi
        xcrun simctl io "$udid" screenshot --type=png "${display[@]}" "$shots/$n.png" >/dev/null 2>&1
        local title="${TITLES[$n]}"
        BEZELS="$BEZELS" "$BUILD_DIR/thumbnail" "$device" "$shots/$n.png" "$thumbs/$n.png" \
            "${title%%|*}" "${title#*|}" >/dev/null
        echo "$device $n done"
    done
    xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
}

shoot "iPhone 18 Pro" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-2
shoot "iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4 1398
