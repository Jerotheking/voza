#!/bin/bash
# pstack verification lever (D055): compiles VozaKit + VozaSmoke against a matched
# local macOS SDK, runs all 3 hermetic smoke suites (default, v01, corrections),
# and validates the plan-glm handoff structure and links.
set -euo pipefail
cd "$(dirname "$0")/.."

# Auto-clean orphan locks (.build/.lock and stale .git/index.lock)
rm -f .build/.lock
if [[ -f .git/index.lock ]]; then
  lock_age=$(( $(date +%s) - $(stat -f %m .git/index.lock 2>/dev/null || date +%s) ))
  [[ $lock_age -ge 5 ]] && rm -f .git/index.lock || true
fi

SDK=""
for candidate in \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" \
  "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"; do
  if [[ -d "$candidate" ]]; then
    SDK="$candidate"
    break
  fi
done

[[ -n "$SDK" ]] || { echo "ERROR: No macOS SDK found under /Library/Developer/CommandLineTools/SDKs"; exit 1; }

TMP_BUILD="$(mktemp -d /tmp/voza-verify.XXXXXX)"
trap 'rm -rf "$TMP_BUILD"' EXIT

echo "==> [1/5] Compiling VozaKit + VozaSmoke (SDK: $(basename "$SDK"))"
swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -emit-module -emit-library -module-name VozaKit -enable-testing \
  $(find Sources/VozaKit -name '*.swift') \
  -o "$TMP_BUILD/libVozaKit.dylib" \
  -emit-module-path "$TMP_BUILD/VozaKit.swiftmodule"

swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -I "$TMP_BUILD" -L "$TMP_BUILD" -lVozaKit \
  -Xlinker -rpath -Xlinker "$TMP_BUILD" \
  Sources/VozaSmoke/main.swift \
  -o "$TMP_BUILD/VozaSmoke"

echo "==> [2/5] Running VozaSmoke (pure default suite)"
"$TMP_BUILD/VozaSmoke"

echo "==> [3/5] Running VozaSmoke v01 (hermetic isolation suite)"
"$TMP_BUILD/VozaSmoke" v01

echo "==> [4/5] Running VozaSmoke corrections (Auto-Learn + adversarial guards)"
"$TMP_BUILD/VozaSmoke" corrections

echo "==> [5/5] Validating docs/plan-glm (plan.py validate)"
python3 -B docs/plan-glm/tools/plan.py validate

echo "==> ALL VERIFICATION CHECKS PASSED."
