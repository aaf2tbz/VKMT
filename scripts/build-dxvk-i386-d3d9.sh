#!/bin/bash
# Targeted rebuild/stage of the i386 DXVK D3D9 DLL used by WoW64.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
SRC="$VKMT/third_party/dxvk"
OUT="$SRC/runtime/dxvk-vkmt-1a5919b"
BUILD="$OUT/build.clang.32"
STAGE="$OUT/x32"
DLL="$BUILD/src/d3d9/d3d9.dll"

test -x "$TOOL/i686-w64-mingw32-clang"
test -f "$SRC/build-vkmt-win32.txt"
test -d "$BUILD"

export PATH="$TOOL:$PATH"
ninja -C "$BUILD" src/d3d9/d3d9.dll

mkdir -p "$STAGE"
install -m 0644 "$DLL" "$STAGE/d3d9.dll"
"$TOOL/llvm-readobj" --file-headers "$STAGE/d3d9.dll" |
    grep -q IMAGE_FILE_MACHINE_I386
printf 'DXVK_I386_D3D9_STAGE_OK %s\n' "$STAGE/d3d9.dll"
