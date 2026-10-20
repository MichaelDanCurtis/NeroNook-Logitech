#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
destination="$project_root/build"
reference="$destination/Logitech Module.app"
mkdir -p "$destination"
signing_identity="$(python3 scripts/signing.py identity --bundle cafe.nero.plugin.logitech --reference "$reference")"
stage="$(mktemp -d "$destination/.logitech-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
swift build -c release -Xswiftc -sdk -Xswiftc "$(xcrun --show-sdk-path)"
bin="$(swift build -c release -Xswiftc -sdk -Xswiftc "$(xcrun --show-sdk-path)" --show-bin-path)"
app="$stage/Logitech Module.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -R "$bin/NookPluginSDK_NookPluginSDK.bundle" "$app/Contents/Resources/"
cp "$bin/LogitechPlugin" "$app/Contents/MacOS/LogitechPlugin"
ditto Resources/Views "$app/Contents/Resources/Views"
cp Resources/NookPlugin.json "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>cafe.nero.plugin.logitech</string><key>CFBundleName</key><string>Logitech Module</string><key>CFBundleExecutable</key><string>LogitechPlugin</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.5.4</string><key>CFBundleVersion</key><string>8</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>LSUIElement</key><true/></dict></plist>
PLIST
python3 scripts/signing.py sign --identity "$signing_identity" "$app"
python3 scripts/signing.py verify --reference "$reference" "$app"
if [[ -e "$reference" ]]; then mv "$reference" "$destination/Logitech Module.previous.$(date +%Y%m%d%H%M%S).app"; fi
mv "$app" "$reference"
printf 'Development app: %s\n' "$reference"
