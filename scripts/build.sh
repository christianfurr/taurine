#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/taurine-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Taurine.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARCH=$(uname -m)
xcrun clang -std=c11 -Wall -Wextra -Werror -O2 -target "$ARCH-apple-macos13.0" \
  Sources/PowerSession.c -framework CoreFoundation -framework IOKit \
  -o "$APP/Contents/MacOS/TaurinePower"
xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos13.0" \
  Sources/Taurine.swift Sources/Updates.swift -framework AppKit -o "$APP/Contents/MacOS/Taurine"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Taurine</string>
  <key>CFBundleIdentifier</key><string>com.christianfurr.Taurine</string>
  <key>CFBundleName</key><string>Taurine</string>
  <key>CFBundleDisplayName</key><string>Taurine</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.0</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/MacOS/TaurinePower"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$PWD/build"
OUTPUT_DIR="$HOME/Library/Caches/com.christianfurr.Taurine/build"
mkdir -p "$OUTPUT_DIR"
ditto --norsrc --noextattr "$APP" "$OUTPUT_DIR/Taurine.app"
codesign --verify --deep --strict "$OUTPUT_DIR/Taurine.app"
# A ZIP survives file-provider metadata in Documents; an unpacked app does not.
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$PWD/build/Taurine.zip"
print "$OUTPUT_DIR/Taurine.app"
print "$PWD/build/Taurine.zip"
