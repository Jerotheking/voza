#!/bin/bash
# Release pipeline: build → Developer ID sign → notarize → staple → DMG.
#
# Required environment:
#   VOZA_SIGNING_ID  e.g. "Developer ID Application: JERONIMO REY (TEAMID)"
#   VOZA_KEYCHAIN_PROFILE   notarytool keychain profile name (xcrun notarytool store-credentials)
#
# Usage: ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Voza.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
DMG="build/Voza-${VERSION}.dmg"

[[ -n "${VOZA_SIGNING_ID:-}" ]] || { echo "Set VOZA_SIGNING_ID (Developer ID Application identity)"; exit 1; }
[[ -n "${VOZA_KEYCHAIN_PROFILE:-}" ]] || { echo "Set VOZA_KEYCHAIN_PROFILE (notarytool profile)"; exit 1; }

echo "==> Building release"
./build.sh release

echo "==> Signing with Developer ID (runtime hardened)"
codesign --force --deep --sign "$VOZA_SIGNING_ID" \
  --entitlements packaging/Voza.entitlements \
  --options runtime \
  --timestamp \
  "$APP"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping for notarization"
rm -f build/Voza.zip
ditto -c -k --keepParent "$APP" build/Voza.zip

echo "==> Submitting for notarization (may take a few minutes)"
xcrun notarytool submit build/Voza.zip \
  --keychain-profile "$VOZA_KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Creating DMG"
rm -f "$DMG"
hdiutil create -volname "Voza $VERSION" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$DMG"

echo "==> Notarizing DMG"
ditto -c -k --keepParent "$DMG" build/Voza-dmg.zip
xcrun notarytool submit build/Voza-dmg.zip \
  --keychain-profile "$VOZA_KEYCHAIN_PROFILE" \
  --wait
xcrun stapler staple "$DMG"

echo ""
echo "Release ready: $DMG"
echo "Next: attach the DMG to the Gumroad product + GitHub release."
