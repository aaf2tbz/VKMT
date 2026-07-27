#!/bin/bash
# Build and stage the pure-AArch64 DXVK pair used by the native VKMT gates.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
SRC="$VKMT/third_party/dxvk"
OUT="$SRC/runtime/dxvk-vkmt-1a5919b"
BUILD="$OUT/build.aarch64"
STAGE="$OUT/aarch64"
CROSS="$SRC/build-vkmt-aarch64.txt"

test -x "$TOOL/aarch64-w64-mingw32-clang"
test -f "$CROSS"

export PATH="$TOOL:$PATH"

if test -d "$BUILD"; then
    meson setup --reconfigure "$BUILD" "$SRC" --cross-file "$CROSS"
else
    meson setup "$BUILD" "$SRC" --cross-file "$CROSS" --buildtype release \
        --prefix "$OUT" --bindir aarch64 --libdir aarch64 -Db_ndebug=if-release
fi

meson compile -C "$BUILD"
python3 "$VKMT/scripts/fix-x18-tls.py" \
    "$BUILD/src/dxgi/dxgi.dll" "$BUILD/src/d3d11/d3d11.dll"

mkdir -p "$STAGE"
cp "$BUILD/src/dxgi/dxgi.dll" "$STAGE/dxgi.dll"
cp "$BUILD/src/d3d11/d3d11.dll" "$STAGE/d3d11.dll"
"$TOOL/llvm-readobj" --file-headers "$STAGE/dxgi.dll" | grep -q IMAGE_FILE_MACHINE_ARM64
"$TOOL/llvm-readobj" --file-headers "$STAGE/d3d11.dll" | grep -q IMAGE_FILE_MACHINE_ARM64
printf 'DXVK_AARCH64_STAGE_OK %s\n' "$STAGE"
