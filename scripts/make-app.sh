#!/bin/bash
# Build a release binary and wrap it into dist/WindowKeeper.app.
# An .app bundle keeps the Accessibility grant stable across rebuilds of the
# repo (the grant follows the bundle path) and can be added to Login Items.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/WindowKeeper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/WindowKeeper "$APP/Contents/MacOS/WindowKeeper"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WindowKeeper</string>
    <key>CFBundleIdentifier</key>
    <string>com.saqibkamran.windowkeeper</string>
    <key>CFBundleName</key>
    <string>WindowKeeper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Prefer a stable signing identity: ad-hoc signatures change on every build,
# and macOS silently revokes the Accessibility grant when the app's code
# signature no longer matches — forcing a manual re-grant after each install.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F '"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
