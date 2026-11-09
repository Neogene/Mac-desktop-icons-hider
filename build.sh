#!/bin/bash
# Builds "Desktop Icons.app" (requires Xcode Command Line Tools: xcode-select --install)
set -e
cd "$(dirname "$0")"

APP="Hide Desktop Icons.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal binary (Apple Silicon + Intel)
BIN="$APP/Contents/MacOS/DesktopIcons"
swiftc -O -target arm64-apple-macos11.0  main.swift -o "$BIN-arm64"
swiftc -O -target x86_64-apple-macos11.0 main.swift -o "$BIN-x86_64"
lipo -create -output "$BIN" "$BIN-arm64" "$BIN-x86_64"
rm "$BIN-arm64" "$BIN-x86_64"

# App icon (Finder / Applications). Regenerate with: python3 tools/make_icon.py
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>it</string><string>es</string><string>fr</string><string>de</string></array>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleName</key><string>Desktop Icons</string>
    <key>CFBundleDisplayName</key><string>Hide Desktop Icons</string>
    <key>CFBundleIdentifier</key><string>it.leganza.DesktopIcons</string>
    <key>CFBundleExecutable</key><string>DesktopIcons</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0.1</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

echo "Done: $(pwd)/$APP"
echo "Run with:  open \"$APP\""