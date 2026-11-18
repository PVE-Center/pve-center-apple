#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

DERIVED_DATA="build/mac-release-dd"
APP_NAME="PVE Center.app"
DEST_APP="/Applications/$APP_NAME"

echo "Compilation de $APP_NAME pour macOS (Release)..."
xcodebuild \
    -project PVECenter.xcodeproj \
    -scheme PVECenter \
    -configuration Release \
    -sdk macosx \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Erreur : binaire introuvable dans $BUILT_APP" >&2
    exit 1
fi

echo "Installation dans $DEST_APP..."
rm -rf "$DEST_APP"
ditto "$BUILT_APP" "$DEST_APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$DEST_APP" || true

echo "Terminé ! $APP_NAME installé dans /Applications."
echo "Pour lancer : open \"$DEST_APP\""
