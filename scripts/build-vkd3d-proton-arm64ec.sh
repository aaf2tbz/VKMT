#!/bin/bash
# Build the ARM64EC vkd3d-proton runtime with the in-tree LLVM-MinGW.
# This is the provider used by the ARM64EC and x86-64/FEX graphics lanes.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
SRC="$VKMT/third_party/vkd3d-proton"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
BUILD="${VKMT_VKD3D_ARM64EC_BUILD:-$SRC/build-arm64ec}"
STAGE="${VKMT_VKD3D_ARM64EC_STAGE:-$SRC/install-arm64ec}"
CROSS="$SRC/build-arm64ec.txt"

test -d "$SRC/.git" || { echo 'vkd3d-proton source is missing' >&2; exit 1; }
test -x "$TOOL/arm64ec-w64-mingw32-clang++" || { echo 'LLVM-MinGW ARM64EC compiler is missing' >&2; exit 1; }
test -f "$CROSS" || { echo 'ARM64EC cross file is missing' >&2; exit 1; }

export PATH="$TOOL:/opt/homebrew/bin:$PATH"
meson setup "$BUILD" "$SRC" --cross-file "$CROSS" --reconfigure \
    --buildtype release --prefix "$STAGE" --bindir bin --libdir lib -Db_lundef=false
meson compile -C "$BUILD" -j "${JOBS:-8}"
meson install -C "$BUILD"

for pe in "$STAGE/bin/d3d12.dll" "$STAGE/bin/d3d12core.dll"; do
    machine="$("$TOOL/llvm-readobj" --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
    test "$machine" = IMAGE_FILE_MACHINE_ARM64EC || {
        echo "Not ARM64EC PE: $pe ($machine)" >&2
        exit 1
    }
done
printf 'Installed ARM64EC vkd3d-proton runtime in %s\n' "$STAGE"
