#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="PVE Center"
EXECUTABLE_NAME="PVECenter"
BUNDLE_ID="io.github.pvepanel.app"
BUILD_ROOT="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_ROOT/${APP_NAME}.app"
SRC_ICON="$SCRIPT_DIR/PVECenter/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-mac-1024.png"
if [[ ! -f "$SRC_ICON" ]]; then
  SRC_ICON="$SCRIPT_DIR/PVECenter/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
fi

echo "==> Compilation Swift 6 Release..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Erreur : binaire introuvable à $BIN_PATH" >&2
  exit 1
fi

echo "==> Assemblage du bundle $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Génération de AppIcon.icns depuis l'icône 1024x1024
ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_TMP"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SRC_ICON" --out "$ICONSET_TMP/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SRC_ICON" --out "$ICONSET_TMP/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_TMP" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_TMP")"

cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>fr</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleExecutable</key>
	<string>${EXECUTABLE_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>CFBundleURLName</key>
			<string>io.github.pvepanel.app.connect</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>pvecenter</string>
			</array>
		</dict>
	</array>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>27.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
</dict>
</plist>
EOF

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Signature ad-hoc macOS..."
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --verbose=2 "$APP_BUNDLE"

DEST_APPS="/Applications"
if [[ ! -w "$DEST_APPS" ]]; then
  DEST_APPS="$HOME/Applications"
  mkdir -p "$DEST_APPS"
fi
rm -rf "$DEST_APPS/${APP_NAME}.app"
cp -R "$APP_BUNDLE" "$DEST_APPS/${APP_NAME}.app"

echo "==> Bundle macOS prêt :"
echo "    - Build : $APP_BUNDLE"
echo "    - Installé : $DEST_APPS/${APP_NAME}.app"
