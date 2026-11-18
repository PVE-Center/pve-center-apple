#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

usage() {
    cat <<'EOF'
Usage: ./scripts/deploy-device.sh [OPTIONS]

Déploie PVE Center sur un appareil physique iPhone, iPad ou Apple TV.

Options:
  -t, --team <TEAM_ID>     Identifiant d'équipe Apple Developer (ex: ABCDE12345).
                           Si omis, Xcode doit déjà avoir un Team configuré dans Signing & Capabilities.
  -p, --platform <plat>    ios (défaut) ou tvos
  -d, --device <UDID>      Identifiant de l'appareil cible (auto-détecté s'il n'y en a qu'un)
  -l, --list               Lister les appareils physiques connectés et quitter
  -h, --help               Afficher cette aide

Exemples:
  ./scripts/deploy-device.sh --list
  ./scripts/deploy-device.sh -t ABCDE12345 -p ios
  ./scripts/deploy-device.sh -t ABCDE12345 -p tvos -d <UDID_APPLE_TV>
EOF
}

TEAM_ID=""
TARGET_PLATFORM="ios"
DEVICE_ID=""
LIST_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--team) TEAM_ID="${2:-}"; shift 2 ;;
        -p|--platform) TARGET_PLATFORM="${2:-}"; shift 2 ;;
        -d|--device) DEVICE_ID="${2:-}"; shift 2 ;;
        -l|--list) LIST_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Option inconnue : $1" >&2; usage; exit 1 ;;
    esac
done

echo "Appareils Apple physiques détectés (xcrun devicectl) :"
DEVICES_OUT="$(xcrun devicectl list devices 2>&1 || true)"
echo "$DEVICES_OUT"

if [[ "$LIST_ONLY" -eq 1 ]]; then
    exit 0
fi

PHYSICAL_LINES="$(echo "$DEVICES_OUT" | grep -E "connected|available" | grep -v "simulated" || true)"

if [[ -z "$DEVICE_ID" ]]; then
    if [[ "$TARGET_PLATFORM" == "tvos" ]]; then
        DEVICE_ID="$(echo "$PHYSICAL_LINES" | grep -i "Apple TV" | head -n 1 | grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}|[0-9A-Fa-f]{24,}" | head -n 1 || true)"
    else
        DEVICE_ID="$(echo "$PHYSICAL_LINES" | grep -iE "iPhone|iPad" | head -n 1 | grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}|[0-9A-Fa-f]{24,}" | head -n 1 || true)"
    fi
fi

if [[ -z "$DEVICE_ID" ]]; then
    echo "" >&2
    echo "Aucun appareil physique ($TARGET_PLATFORM) connecté ou jumelé détecté." >&2
    echo "Assurez-vous que :" >&2
    echo "  1. L'iPhone/iPad est branché en USB (ou sur le même Wi-Fi) et déverrouillé (« Faire confiance à cet ordinateur »)," >&2
    echo "     et que le « Mode développeur » est activé (Réglages > Confidentialité et sécurité > Mode développeur)." >&2
    echo "  2. L'Apple TV est jumelée dans Xcode > Window > Devices and Simulators." >&2
    exit 1
fi

if [[ "$TARGET_PLATFORM" == "tvos" ]]; then
    SDK="appletvos"
    PRODUCT_DIR="Release-appletvos"
    DEST="generic/platform=tvOS"
else
    SDK="iphoneos"
    PRODUCT_DIR="Release-iphoneos"
    DEST="generic/platform=iOS"
fi

DERIVED_DATA="build/device-${TARGET_PLATFORM}-dd"
TEAM_ARGS=()
if [[ -n "$TEAM_ID" ]]; then
    TEAM_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

echo "Compilation de PVE Center pour $TARGET_PLATFORM ($SDK)..."
xcodebuild \
    -project PVECenter.xcodeproj \
    -scheme PVECenter \
    -configuration Release \
    -sdk "$SDK" \
    -destination "$DEST" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    ${TEAM_ARGS[@]+"${TEAM_ARGS[@]}"} \
    build

APP_PATH="$DERIVED_DATA/Build/Products/$PRODUCT_DIR/PVE Center.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "Erreur : bundle introuvable à $APP_PATH" >&2
    exit 1
fi

echo "Installation sur l'appareil $DEVICE_ID..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

BUNDLE_ID="$(xcodebuild -project PVECenter.xcodeproj -scheme PVECenter -showBuildSettings 2>/dev/null | awk -F' = ' '/PRODUCT_BUNDLE_IDENTIFIER/ {print $2; exit}' || true)"
BUNDLE_ID="${BUNDLE_ID:-io.ac.pvepanel.app}"

echo "Lancement de PVE Center ($BUNDLE_ID) sur l'appareil $DEVICE_ID..."
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || true
