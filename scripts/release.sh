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

echo "==> Signing embedded whisper-cli helper with Developer ID (runtime hardened)"
codesign --force --sign "$VOZA_SIGNING_ID" \
  --options runtime \
  --timestamp \
  "$APP/Contents/MacOS/whisper-cli"

echo "==> Signing app bundle with Developer ID (runtime hardened)"
codesign --force --sign "$VOZA_SIGNING_ID" \
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
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG" "$DMG.sha256"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp packaging/INSTALL.txt "$STAGE/"
hdiutil create -volname "Voza $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "==> Notarizing DMG"
ditto -c -k --keepParent "$DMG" build/Voza-dmg.zip
xcrun notarytool submit build/Voza-dmg.zip \
  --keychain-profile "$VOZA_KEYCHAIN_PROFILE" \
  --wait
xcrun stapler staple "$DMG"

shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
echo ""
echo "Release ready: $DMG"
echo "SHA-256:       $(cat "$DMG.sha256")"
echo "Next: attach the DMG + .sha256 to the Gumroad product + GitHub release."
