#!/bin/bash
# Builds a universal (Apple Silicon + Intel) MTABar.app.
# Pass --install to copy it to ~/Applications and launch it.
# Set VERSION to stamp the bundle version (default: 1.0.0).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/MTABar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MTABar" "$APP/Contents/MacOS/MTABar"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MTABar</string>
    <key>CFBundleIdentifier</key><string>com.zakariyya.mtabar</string>
    <key>CFBundleName</key><string>MTA Bar</string>
    <key>CFBundleDisplayName</key><string>MTA Bar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.travel</string>
    <key>LSUIElement</key><true/>
    <key>NSLocationUsageDescription</key><string>MTA Bar uses your location to show the next train from your nearest saved station.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>MTA Bar uses your location to show the next train from your nearest saved station.</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/MTABar"))"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MTABar || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/MTABar.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/MTABar.app
    echo "Installed to ~/Applications/MTABar.app"
fi
