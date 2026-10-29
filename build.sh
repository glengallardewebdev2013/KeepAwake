#!/bin/bash
set -e
cd "$(dirname "$0")"

SELF_SIGNED_NAME="KeepAwake Self Signed"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Run: xcode-select --install"
  exit 1
fi

APP="KeepAwake.app"
BIN="$APP/Contents/MacOS/KeepAwake"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

SDK=""
for candidate in MacOSX26.sdk MacOSX.sdk; do
  path="/Library/Developer/CommandLineTools/SDKs/$candidate"
  if [ -d "$path" ]; then SDK="$path"; break; fi
done
SDK_FLAG=""
if [ -n "$SDK" ]; then
  echo "Using SDK: $SDK"
  SDK_FLAG="-sdk $SDK"
fi

echo "Compiling (release + stripped)..."
swiftc -O -wmo -gnone $SDK_FLAG main.swift -o "$BIN" -framework Cocoa -framework IOKit

echo "Stripping symbols..."
strip -rSTx "$BIN" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>KeepAwake</string>
  <key>CFBundleDisplayName</key><string>KeepAwake</string>
  <key>CFBundleIdentifier</key><string>local.keepawake</string>
  <key>CFBundleExecutable</key><string>KeepAwake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')
if [ -n "$DEV_ID" ]; then
  echo "Signing with Developer ID: $DEV_ID"
  codesign --force --deep --options runtime --identifier local.keepawake -s "$DEV_ID" "$APP"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$SELF_SIGNED_NAME"; then
  echo "Signing with self-signed certificate: $SELF_SIGNED_NAME"
  codesign --force --deep --identifier local.keepawake -s "$SELF_SIGNED_NAME" "$APP"
else
  echo "WARNING: '$SELF_SIGNED_NAME' certificate not found — falling back to ad-hoc."
  codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
fi

echo ""
echo "Done! Built $(pwd)/$APP"
