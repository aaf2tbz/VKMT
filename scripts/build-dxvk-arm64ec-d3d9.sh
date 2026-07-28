#!/bin/bash
# Targeted rebuild/stage of DXVK D3D9 for the native-host ARM64EC route.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
SRC="$VKMT/third_party/dxvk"
OUT="$SRC/runtime/dxvk-vkmt-1a5919b"
BUILD="$OUT/build.arm64ec"
STAGE="$OUT/arm64ec"
DLL="$BUILD/src/d3d9/d3d9.dll"

test -x "$TOOL/arm64ec-w64-mingw32-clang"
test -f "$SRC/build-vkmt-arm64ec.txt"
test -d "$BUILD"

export PATH="$TOOL:$PATH"
ninja -C "$BUILD" src/d3d9/d3d9.dll
python3 "$VKMT/scripts/fix-x18-tls.py" "$DLL"

mkdir -p "$STAGE"
install -m 0644 "$DLL" "$STAGE/d3d9.dll"
"$TOOL/llvm-readobj" --file-headers "$STAGE/d3d9.dll" |
    grep -q IMAGE_FILE_MACHINE_ARM64EC
if "$TOOL/llvm-objdump" -d "$STAGE/d3d9.dll" | grep -Eq '\[x18(,|\])'; then
    echo "ARM64EC D3D9 stage still contains x18-based TLS access" >&2
    exit 1
fi
printf 'DXVK_ARM64EC_D3D9_STAGE_OK %s\n' "$STAGE/d3d9.dll"
