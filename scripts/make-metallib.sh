#!/bin/bash
# D025 — Builds mlx.metallib for Voza's in-process MLX engine.
#
# Why this exists: the MLX C++ build used by SwiftPM excludes the Metal kernels
# (no metallib is produced), but the runtime loads `mlx.metallib` eagerly at
# stream creation (device.cpp: load_default_library) — without it every MLX op
# throws "Failed to load the default metallib".
#
# Recipe: per-kernel `xcrun metal -c *.metal -o *.air`, then link all .air with
# `xcrun metallib` — mirroring kernels/CMakeLists.txt in the MLX checkout.
# Include dir (metal_3_0 vs metal_3_1) is auto-detected from the compiler
# itself, exactly like MLX's own CMakeLists.
#
# Caching: output is keyed on a hash of (kernel sources + headers + MLX
# version). If the cache is fresh, the script is a no-op — recompiles only when
# the pinned MLX source changes (or on first build / cache wipe).
#
# Usage: scripts/make-metallib.sh <output-dir>   (default: build/)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-build}"
OUT="$OUT_DIR/mlx.metallib"
# Vendored C++ repo root (include base) and its kernels dir: Cmlx/mlx/mlx/backend/…
MLX_ROOT=".build/checkouts/mlx-swift/Source/Cmlx/mlx"

[[ -d "$MLX_ROOT" ]] || { echo "make-metallib: MLX checkout not found at $MLX_ROOT (run swift package resolve first)" >&2; exit 1; }

KDIR="$MLX_ROOT/mlx/backend/metal/kernels"
SRCS=(
  arg_reduce arange binary binary_two copy fft
  reduce quantized fp4_quantized scan softmax logsumexp sort ternary unary
  gemv_masked
  steel/conv/kernels/steel_conv steel/conv/kernels/steel_conv_general
  steel/gemm/kernels/steel_gemm_fused steel/gemm/kernels/steel_gemm_gather
  steel/gemm/kernels/steel_gemm_masked steel/gemm/kernels/steel_gemm_splitk
  steel/gemm/kernels/steel_gemm_segmented
  steel/attn/kernels/steel_attention
)
HEADERS="arange.h binary.h binary_ops.h binary_two.h copy.h \
  fft/radix.h fft/readwrite.h quantized.h quantized_utils.h \
  atomic.h reduction/ops.h reduction/reduce_init.h reduction/reduce_all.h \
  reduction/reduce_col.h reduction/reduce_row.h \
  unary_ops.h unary.h ternary_ops.h ternary.h softmax.h scan.h sort.h logsumexp.h \
  steel/defines.h steel/utils.h steel/utils/integral_constant.h steel/utils/type_traits.h \
  steel/conv/conv.h steel/conv/params.h steel/conv/loader.h steel/conv/kernels/steel_conv.h steel/conv/kernels/steel_conv_general.h \
  steel/conv/loaders/loader_channel_l.h steel/conv/loaders/loader_channel_n.h steel/conv/loaders/loader_general.h \
  steel/gemm/gemm.h steel/gemm/mma.h steel/gemm/loader.h steel/gemm/transforms.h \
  steel/gemm/kernels/steel_gemm_fused.h steel/gemm/kernels/steel_gemm_gather.h steel/gemm/kernels/steel_gemm_masked.h \
  steel/gemm/kernels/steel_gemm_splitk.h steel/gemm/kernels/steel_gemm_segmented.h \
  steel/attn/attn.h steel/attn/loader.h steel/attn/mma.h steel/attn/params.h steel/attn/transforms.h steel/attn/kernels/steel_attention.h"

# --- MLX version for the cache key (checkout is a real git repo) ------------
MLX_VERSION="$(git -C "$MLX_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"

# --- Metal version via the compiler's own __METAL_VERSION__ (CMake parity) ---
# Macro is 10000*major + 100*minor (e.g. Metal 3.2 -> 32023 in newer toolchains;
# some toolchains report a short 3-digit form like 320). metal_3_1 includes are
# for Metal >= 3.1.
METAL_VER="$(echo "__METAL_VERSION__" | xcrun -sdk macosx metal -E -x metal -P - 2>/dev/null | tail -1 | tr -d '[:space:]')"
METAL_VER="${METAL_VER:-30000}"
if (( METAL_VER > 999 )); then
  MVER=$(( METAL_VER / 10000 )); MMIN=$(( (METAL_VER % 10000) / 100 ))
else
  MVER=$(( METAL_VER / 100 ));    MMIN=$(( METAL_VER % 100 / 10 ))
fi
INC_DIR="metal_3_0"; (( MVER > 3 || (MVER == 3 && MMIN >= 1) )) && INC_DIR="metal_3_1"

# --- Cache key: sources + headers + MLX version ------------------------------
TMPDIR_MAKEY="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_MAKEY"' EXIT
{
  echo "$MLX_VERSION"
  for f in "${SRCS[@]}"; do echo "$f $(md5 -q "$KDIR/$f.metal" 2>/dev/null || echo MISSING)"; done
  for h in $HEADERS; do
    for base in "$KDIR" "$KDIR/metal_3_0" "$KDIR/metal_3_1" "$KDIR/steel"; do
      [[ -f "$base/$h" ]] && { echo "$h $(md5 -q "$base/$h")"; break; }
    done
  done
} > "$TMPDIR_MAKEY/key"
KEY="$(md5 -q "$TMPDIR_MAKEY/key")"
CACHE="$OUT_DIR/metallib-cache/$KEY"
if [[ -f "$CACHE/mlx.metallib" ]]; then
  if [[ ! -f "$OUT" ]] || ! cmp -s "$CACHE/mlx.metallib" "$OUT"; then
    mkdir -p "$OUT_DIR"; cp "$CACHE/mlx.metallib" "$OUT"
  fi
  echo "make-metallib: cache hit ($KEY) -> $OUT"
  exit 0
fi

# --- Compile -----------------------------------------------------------------
command -v xcrun >/dev/null 2>&1 || { echo "make-metallib: xcrun not found (install Xcode)" >&2; exit 1; }
if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  echo "make-metallib: Metal toolchain missing. Run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

WORK="$TMPDIR_MAKEY/kernels"
mkdir -p "$WORK"
AIRS=()
for f in "${SRCS[@]}"; do
  TGT="$WORK/$(basename "$f").air"
  xcrun -sdk macosx metal -Wall -Wextra -fno-fast-math -Wno-c++17-extensions \
    -c "$KDIR/$f.metal" -I"$MLX_ROOT" -I"$KDIR/$INC_DIR" -o "$TGT" 2>"$TMPDIR_MAKEY/err.log" \
    || { echo "make-metallib: kernel $f failed:" >&2; cat "$TMPDIR_MAKEY/err.log" >&2; exit 1; }
  AIRS+=("$TGT")
done

mkdir -p "$CACHE" "$OUT_DIR"
xcrun -sdk macosx metallib "${AIRS[@]}" -o "$CACHE/mlx.metallib"
cp "$CACHE/mlx.metallib" "$OUT"
echo "make-metallib: built $OUT ($KEY, $(du -h "$OUT" | cut -f1))"
