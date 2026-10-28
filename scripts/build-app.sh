#!/bin/zsh
# Builds "Inbox Cleaner.app" into ./build. Pass --install to copy it into /Applications and open it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Inbox Cleaner.app"
VERSION="1.0.0"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/InboxCleaner"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/InboxCleaner"

if [[ ! -f build/AppIcon.icns ]]; then
    rm -rf build/AppIcon.iconset
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Inbox Cleaner</string>
    <key>CFBundleDisplayName</key><string>Inbox Cleaner</string>
    <key>CFBundleIdentifier</key><string>com.inboxcleaner.app</string>
    <key>CFBundleExecutable</key><string>InboxCleaner</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x InboxCleaner 2>/dev/null || true
    rm -rf "/Applications/Inbox Cleaner.app"
    cp -R "$APP" /Applications/
    open "/Applications/Inbox Cleaner.app"
    echo "Installed to /Applications and launched."
fi
