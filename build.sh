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

# STT engine (P0-2, fix final): whisper.cpp compilado de la fuente VENDIDA
# (vendor/whisper.cpp @ v1.9.4) — linkage estático con la librería Metal
# EMBEBIDA en el binario ("using embedded metal library" en runtime).
# La ruta brew se abandonó: su ggml hardcodea el directorio de backends en
# tiempo de compilación y los dlopen-ea desde Cellar, que no existe en la
# Mac del cliente. Cero Homebrew, cero dylibs externas — solo frameworks
# de sistema. La compilación es cache: solo corre la primera vez.
WHISPER_SRC="vendor/whisper.cpp/build-arm64/bin/whisper-cli"
WHISPER_TAG="v1.9.4"
if [[ ! -x "$WHISPER_SRC" ]]; then
  if [[ ! -d vendor/whisper.cpp ]]; then
    command -v git >/dev/null 2>&1 || { echo "ERROR: git requerido para traer el STT engine vendido"; exit 1; }
    echo "Fetching whisper.cpp $WHISPER_TAG (first build only)…"
    git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp.git vendor/whisper.cpp
  fi
  command -v cmake >/dev/null 2>&1 || { echo "ERROR: cmake requerido para compilar el STT engine vendido (brew install cmake)"; exit 1; }
  echo "Building vendored whisper.cpp (first build only)…"
  cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build-arm64 \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_SERVER=OFF >/dev/null
  cmake --build vendor/whisper.cpp/build-arm64 --target whisper-cli -j >/dev/null
fi
cp "$WHISPER_SRC" "$APP/Contents/MacOS/whisper-cli"
chmod +x "$APP/Contents/MacOS/whisper-cli"
# El helper nunca toca el micrófono (lee un WAV); ad-hoc basta y lo mantiene
# independiente de la identidad estable que firma el bundle de la app abajo.
codesign --force --sign - "$APP/Contents/MacOS/whisper-cli" 2>/dev/null || true
"$APP/Contents/MacOS/whisper-cli" --help >/dev/null 2>&1 \
  || { echo "ERROR: bundled whisper-cli fails to run"; exit 1; }
echo "Bundled STT engine: vendored whisper.cpp v1.9.4 (static, embedded Metal)"

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
codesign --force --sign "$sign_identity" "$APP" 2>&1 || true
codesign --verify "$APP" >/dev/null 2>&1 \
  || echo "WARN: codesign verify failed — TCC grants (mic/accessibility) may reset on next relaunch."

echo "Built $APP"
echo "Run:  open $APP   (first launch will trigger macOS permission prompts)"
