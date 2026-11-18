#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

DEFAULT_UDID="A26D8355-CCA7-4E9A-B650-5830FBEF67C1"
BUNDLE_ID="$(xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -showBuildSettings 2>/dev/null | awk -F' = ' '/PRODUCT_BUNDLE_IDENTIFIER/ {print $2; exit}' || true)"
BUNDLE_ID="${BUNDLE_ID:-io.ac.pvepanel.app}"
APP_NAME="PVE Center.app"
DERIVED_DATA="build/sim-dd"

# Choose iPhone simulator UDID (passed as $1, or default iPhone 18 Pro if present, else first available iPhone)
if [[ -n "${1:-}" ]]; then
    UDID="$1"
elif xcrun simctl list devices available | grep -q "$DEFAULT_UDID"; then
    UDID="$DEFAULT_UDID"
else
    UDID="$(xcrun simctl list devices available | grep -E "iPhone .*\([0-9A-F-]{36}\)" | head -n 1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
fi

if [[ -z "$UDID" ]]; then
    echo "Erreur : aucun simulateur iPhone disponible trouvé via 'xcrun simctl list devices available'." >&2
    exit 1
fi

DEVICE_LINE="$(xcrun simctl list devices available | grep "$UDID" | head -n 1 | xargs)"
echo "Simulateur sélectionné : $DEVICE_LINE"

echo "Fermeture des éventuels simulateurs Apple TV actifs..."
while IFS= read -r TV_UDID; do
    if [[ -n "$TV_UDID" ]]; then
        xcrun simctl shutdown "$TV_UDID" 2>/dev/null || true
    fi
done < <(xcrun simctl list devices booted | grep "Apple TV" | sed -nE 's/.*\(([0-9A-F-]{36})\).*/\1/p')

echo "Démarrage du simulateur iPhone..."
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

DEV_APP_DIR="$(dirname "$(dirname "$(xcode-select -p)")")/Applications"
if [[ -d "$DEV_APP_DIR/DeviceHub.app" ]]; then
    open "devices://device/open?id=$UDID" 2>/dev/null || open "$DEV_APP_DIR/DeviceHub.app" || true
elif [[ -d "$(xcode-select -p)/Applications/Simulator.app" ]]; then
    open "$(xcode-select -p)/Applications/Simulator.app" --args -CurrentDeviceUDID "$UDID" || true
else
    open "devices://device/open?id=$UDID" 2>/dev/null || open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null || true
fi

echo "Compilation de PVE Center pour iphonesimulator..."
xcodebuild \
    -project PVECenter.xcodeproj \
    -scheme PVECenter \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Erreur : bundle introuvable à $APP_PATH" >&2
    exit 1
fi

echo "Installation de $APP_NAME sur le simulateur..."
xcrun simctl install "$UDID" "$APP_PATH"

echo "Lancement de $BUNDLE_ID..."
xcrun simctl launch "$UDID" "$BUNDLE_ID"
