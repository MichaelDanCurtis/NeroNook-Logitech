#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -sdk -Xswiftc "$(xcrun --show-sdk-path)"
bin="$(swift build -c release -Xswiftc -sdk -Xswiftc "$(xcrun --show-sdk-path)" --show-bin-path)"
app="$PWD/build/Logitech Module.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/LogitechPlugin" "$app/Contents/MacOS/LogitechPlugin"
ditto Resources/Views "$app/Contents/Resources/Views"
cp Resources/NookPlugin.json "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>cafe.nero.plugin.logitech</string><key>CFBundleName</key><string>Logitech Module</string><key>CFBundleExecutable</key><string>LogitechPlugin</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.3.0</string><key>CFBundleVersion</key><string>3</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>LSUIElement</key><true/></dict></plist>
PLIST
codesign --force --sign "${NERONOOK_SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
