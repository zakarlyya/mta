#!/bin/bash
# Builds MTABar.app. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/MTABar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MTABar "$APP/Contents/MacOS/MTABar"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MTABar</string>
    <key>CFBundleIdentifier</key><string>com.zakariyya.mtabar</string>
    <key>CFBundleName</key><string>MTA Bar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MTABar || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/MTABar.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/MTABar.app
    echo "Installed to ~/Applications/MTABar.app"
fi
