#!/bin/bash
# Builds "Desktop Icons.app" (requires Xcode Command Line Tools: xcode-select --install)
set -e
cd "$(dirname "$0")"

APP="Desktop Icons.app"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target "${ARCH}-apple-macos11.0" main.swift -o "$APP/Contents/MacOS/DesktopIcons"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Desktop Icons</string>
    <key>CFBundleDisplayName</key><string>Desktop Icons</string>
    <key>CFBundleIdentifier</key><string>com.example.DesktopIcons</string>
    <key>CFBundleExecutable</key><string>DesktopIcons</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

echo "Done: $(pwd)/$APP"
echo "Run with:  open \"$APP\""
