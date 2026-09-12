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

# D025 — the MLX engine loads `mlx.metallib` from the binary's directory at
# runtime (device.cpp: load_default_library). Without it, cleanup (Pulido)
# throws "Failed to load the default metallib". Cached: no-op when MLX unchanged.
./scripts/make-metallib.sh build
cp build/mlx.metallib "$APP/Contents/MacOS/mlx.metallib"

# Generate .icns from the SVG icon if tools are available.
if [[ -f "design/assets/voza-icon.svg" ]] && command -v qlmanage >/dev/null 2>&1; then
  ./scripts/make-icons.sh || true
fi
[[ -f "build/AppIcon.icns" ]] && cp "build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Stable self-signed identity (created 2026-09-08, login keychain): keeps the
# CDHash signature constant across rebuilds so macOS TCC permission grants
# (microphone / accessibility / input monitoring) SURVIVE re-packaging.
# Ad-hoc signing (-) changes the signature every build and silently voids grants.
# To recreate the identity: see docs (security add-trusted-cert -r trustRoot -p codeSign).
sign_identity="voza-dev"
if ! security find-identity -v -p codesigning | grep -q "$sign_identity"; then
  echo "WARN: '$sign_identity' identity not found — falling back to ad-hoc (TCC grants will reset per build)."
  sign_identity="-"
fi
codesign --force --sign "$sign_identity" "$APP/Contents/MacOS/mlx.metallib" 2>/dev/null || true
codesign --force --sign "$sign_identity" "$APP" 2>&1 || true
codesign --verify "$APP" >/dev/null 2>&1 \
  || echo "WARN: codesign verify failed — TCC grants (mic/accessibility) may reset on next relaunch."

echo "Built $APP"
echo "Run:  open $APP   (first launch will trigger macOS permission prompts)"
