#!/bin/bash
# Renders design/assets/voza-icon.svg into build/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="design/assets/voza-icon.svg"
OUT="build/AppIcon.iconset"
mkdir -p "$OUT" build

# Render a 1024px PNG from the SVG (qlmanage ships with macOS).
qlmanage -t -s 1024 -o build "$SRC" >/dev/null 2>&1
PNG="build/$(basename "$SRC").png"
[[ -f "$PNG" ]] || { echo "SVG render failed"; exit 1; }

for size in 16 32 128 256 512; do
  sips -z $size $size "$PNG" --out "$OUT/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$PNG" --out "$OUT/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$OUT" -o build/AppIcon.icns
echo "build/AppIcon.icns ready"
