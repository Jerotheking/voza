#!/bin/bash
# Builds Voza.app from the SwiftPM package (no Xcode project needed).
# Usage: ./build.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/Voza.app"
PLIST="packaging/Info.plist"

[[ -f "$PLIST" ]] || { echo "Missing $PLIST"; exit 1; }

if [[ "$CONFIG" == "release" ]]; then
  swift build -c release --product Voza
  BIN=".build/release/Voza"
else
  swift build --product Voza
  BIN=".build/debug/Voza"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Voza"
cp "$PLIST" "$APP/Contents/Info.plist"

# Generate .icns from the SVG icon if tools are available.
if [[ -f "design/assets/voza-icon.svg" ]] && command -v qlmanage >/dev/null 2>&1; then
  ./scripts/make-icons.sh || true
fi
[[ -f "build/AppIcon.icns" ]] && cp "build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

 codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Run:  open $APP   (first launch will trigger macOS permission prompts)"
