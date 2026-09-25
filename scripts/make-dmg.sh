#!/bin/bash
# Packages a Gumroad-ready DMG from the signed build (no notarization — that
# requires the Developer ID pipeline in scripts/release.sh).
#
# Layout: Voza.app + Applications symlink + INSTALL.txt (EN/ES).
# Usage: ./scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Voza.app"
[[ -d "$APP" ]] || { echo "No $APP — run ./build.sh release first"; exit 1; }
# The stable `voza-dev` signature is what keeps TCC grants alive for the
# DEVELOPER machine; on a customer machine this check only guarantees the
# bundle is internally consistent (every dylib/helper signed).
codesign --verify "$APP" 2>/dev/null || { echo "Signature invalid — rebuild with ./build.sh release"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
STAGE="build/dmg-stage"
DMG="build/Voza-${VERSION}-early-access.dmg"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp packaging/INSTALL.txt "$STAGE/"

hdiutil create -volname "Voza $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
echo "DMG ready:    $DMG"
echo "SHA-256:      $(cat "$DMG.sha256")"
echo "Publish with: the .dmg + the .sha256 (lets buyers verify the download)."
