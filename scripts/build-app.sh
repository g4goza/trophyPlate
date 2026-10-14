#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox)"
APP_PATH="$PWD/build/TrophyPlate.app"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$BIN_DIR/TrophyPlate" "$APP_PATH/Contents/MacOS/TrophyPlate.new"
mv -f "$APP_PATH/Contents/MacOS/TrophyPlate.new" "$APP_PATH/Contents/MacOS/TrophyPlate"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TrophyPlate</string>
<key>CFBundleIdentifier</key><string>com.g4goza.trophyplate</string>
<key>CFBundleName</key><string>TrophyPlate</string>
<key>CFBundleDisplayName</key><string>TrophyPlate</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP_PATH"
print "Built $APP_PATH"
