#!/bin/zsh
# Builds "Clutter Clear.app" into ./build. Pass --install to copy it into /Applications and open it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Clutter Clear.app"
VERSION="1.1.0"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClutterClear"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClutterClear"

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
    <key>CFBundleName</key><string>Clutter Clear</string>
    <key>CFBundleDisplayName</key><string>Clutter Clear</string>
    <key>CFBundleIdentifier</key><string>com.clutterclear.app</string>
    <key>CFBundleExecutable</key><string>ClutterClear</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Clutter Clear uses Apple Mail to check and clean up inboxes you added through Mail, such as AT&amp;T or SBC addresses.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x ClutterClear 2>/dev/null || true
    # Remove the app from before it was renamed.
    pkill -x InboxCleaner 2>/dev/null || true
    rm -rf "/Applications/Inbox Cleaner.app"
    rm -rf "/Applications/Clutter Clear.app"
    cp -R "$APP" /Applications/
    open "/Applications/Clutter Clear.app"
    echo "Installed to /Applications and launched."
fi
